import Foundation
import PlannerCore
import PlannerData
import PlannerTransfer
import XCTest
@testable import PlannerUI

@MainActor
final class ImportedBuildT6BindingTests: XCTestCase {
    private func fixture(_ name: String = "t6-build") throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
    private func build(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> BuildSnapshot {
        var value = try T6FixtureJSON.object(fixture())
        change(&value)
        return try BuildTransfer.snapshot(fromDraftJSON: T6FixtureJSON.data(value))
    }
    private func setup() throws -> (DraftStore, ImportedBuildLibraryModel, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        return (store, ImportedBuildLibraryModel(store: store), folder)
    }
    private func save(_ snapshot: BuildSnapshot, to store: DraftStore) async throws -> DraftRecord {
        let wrapper = try ImportedBuildRecord(snapshot: snapshot, markedSynthetic: false, sourceRevision: nil)
        return try await store.save(id: UUID(), expectedRevision: nil, title: "Synthetic binding control",
                                    payload: JSONEncoder().encode(wrapper))
    }
    private func currentReport() async throws -> AnalysisState<EvaluationReport> {
        let report = try EvaluationReport.decode(JSONSerialization.data(withJSONObject: [
            "schema_version": "1.0.0", "id": "evaluation.synthetic.binding", "build_id": "build.fixture.1",
            "build_revision": 1, "catalog_snapshot_id": "catalog.fixture.1", "ruleset_id": "rules.fixture.1",
            "ruleset_version": "1.0.0", "dependency_graph_id": "dependencies.core.1", "dependency_graph_revision": 1,
            "evaluated_at": "2026-10-16T09:00:00Z", "result": "valid", "deployment_readiness": "needs_review",
            "findings": [], "summary": ["passed": 0, "failed": 0, "unknown": 0, "skipped": 0],
        ]))
        let owner = AnalysisStore<EvaluationReport>()
        let request = await owner.begin(for: report.analysisIdentity)
        _ = await owner.receive(report, for: request)
        return await owner.state
    }
    private func attachReport(_ model: ImportedBuildLibraryModel, build: BuildSnapshot) async throws {
        let state = try await currentReport()
        XCTAssertTrue(model.t6Review.receiveCompatibility(state, for: build))
    }

    func testLibrarySelectionUsesCompleteSnapshotAndNoCompatibilityDefault() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNil(model.t6Review.build)
        let snapshot = try build(), row = try await save(snapshot, to: store)
        await model.open(row)
        XCTAssertEqual(model.snapshot, snapshot)
        XCTAssertEqual(model.t6Review.build, snapshot)
        XCTAssertNil(model.t6Review.compatibility)
        await model.t6Review.retry()
        XCTAssertEqual(model.t6Review.content?.guidance.record, .notSupplied)
        XCTAssertNil(model.t6Review.compatibility)
        #if DEBUG
        let absent = T6SyntheticJourney.qualityAbsent, failed = T6SyntheticJourney.qualityFailedProposed
        XCTAssertEqual(absent.buildJSON, try fixture())
        XCTAssertEqual(failed.buildJSON, try fixture())
        XCTAssertNil(absent.qualityJSON); XCTAssertNil(absent.manifestJSON)
        XCTAssertEqual(failed.qualityJSON, try fixture("t6-quality-evaluation-run"))
        XCTAssertEqual(failed.manifestJSON, try fixture("t6-deployment-manifest"))
        #endif
    }

    func testSameIDRevisionWithChangedLockRetiresCompatibilityAndPicker() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = try build(), first = try await save(before, to: store)
        let after = try build { value in
            var locks = value["locks"] as! [String: Any]
            locks["catalog_snapshot_id"] = "catalog.other"; value["locks"] = locks
        }
        let second = try await save(after, to: store)
        await model.open(first)
        try await attachReport(model, build: before)
        let request = try XCTUnwrap(model.t6Review.beginFileSelection(.quality))
        await model.open(second)
        XCTAssertEqual(before.id, after.id)
        XCTAssertEqual(model.t6Review.build, after)
        XCTAssertNil(model.t6Review.compatibility)
        XCTAssertNil(model.t6Review.content)
        model.t6Review.fileSelectionFailed(for: request)
        XCTAssertNil(model.t6Review.notice)
        XCTAssertEqual(model.t6Review.build, after)
    }

    func testDuplicateForkGetsNewT6IdentityWithoutInheritedReport() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try build { $0.removeValue(forKey: "extensions") }
        let row = try await save(source, to: store)
        await model.open(row)
        try await attachReport(model, build: source)
        await model.duplicate(row)
        let fork = try XCTUnwrap(model.snapshot)
        XCTAssertNotEqual(model.selected?.id, row.id)
        XCTAssertNotEqual(fork.id, source.id)
        XCTAssertEqual(model.t6Review.build, fork)
        XCTAssertNil(model.t6Review.compatibility)
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(try ImportedBuildRecord.decode(retained.payload).snapshot, source)
    }

    func testLocalLabelRenameKeepsExactBuildReviewIdentity() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshot = try build(), row = try await save(snapshot, to: store)
        await model.open(row)
        try await attachReport(model, build: snapshot)
        await model.rename(row, to: "A new local label")
        XCTAssertEqual(model.selected?.revision, row.revision + 1)
        XCTAssertEqual(model.snapshot, snapshot)
        XCTAssertEqual(model.t6Review.build, snapshot)
        XCTAssertEqual(model.t6Review.compatibility?.result, .valid)
    }

    func testDeleteOtherPreservesReviewAndDeleteSelectedRetiresIt() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshot = try build(), selected = try await save(snapshot, to: store)
        let other = try await save(try build { $0["id"] = "build.other" }, to: store)
        await model.open(selected)
        try await attachReport(model, build: snapshot)
        let request = try XCTUnwrap(model.t6Review.beginFileSelection(.manifest))
        await model.delete(other)
        XCTAssertEqual(model.t6Review.build, snapshot)
        XCTAssertEqual(model.t6Review.compatibility?.result, .valid)
        await model.delete(selected)
        XCTAssertNil(model.snapshot); XCTAssertNil(model.t6Review.build)
        XCTAssertNil(model.t6Review.compatibility); XCTAssertNil(model.t6Review.content)
        XCTAssertFalse(model.t6Review.busy)
        model.t6Review.fileSelectionFailed(for: request)
        XCTAssertNil(model.t6Review.notice)
    }

    func testFailedOpenKeepsPriorSelectedReview() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshot = try build(), selected = try await save(snapshot, to: store)
        let removed = try await save(try build { $0["id"] = "build.removed" }, to: store)
        await model.open(selected)
        try await attachReport(model, build: snapshot)
        try await store.delete(id: removed.id, expectedRevision: removed.revision)
        await model.open(removed)
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(model.selected?.id, selected.id)
        XCTAssertEqual(model.t6Review.build, snapshot)
        XCTAssertEqual(model.t6Review.compatibility?.result, .valid)
    }
}
