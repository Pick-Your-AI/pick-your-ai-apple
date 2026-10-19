import Foundation
import PlannerData
import PlannerTransfer
import XCTest
@testable import PlannerUI

private enum T6NavigationTestFailure: Error { case synthetic }

/// Keep the real receiver and its actual callback factory, while deliberately
/// letting preparation finish after cancellation to test result admission.
private actor SuspendedT6NavigationPreparation {
    private var sequence = 0
    private var requests: [Int: CheckedContinuation<T6ReviewContent, Error>] = [:]
    private var started: [Int: CheckedContinuation<Void, Never>] = [:]
    func prepare(_ build: BuildSnapshot, _ inputs: T6ArtifactInputs) async throws -> T6ReviewContent {
        let index = sequence; sequence += 1
        return try await withCheckedThrowingContinuation { continuation in
            requests[index] = continuation; started.removeValue(forKey: index)?.resume()
        }
    }
    func waitFor(_ index: Int) async {
        if requests[index] != nil { return }
        await withCheckedContinuation { started[index] = $0 }
    }
    func complete(_ index: Int, _ result: Result<T6ReviewContent, Error>) {
        requests.removeValue(forKey: index)!.resume(with: result)
    }
}

/// These use the real library, selected immutable Build and the very same
/// navigation binding/tab owner used by the App. They do not simulate Files UI.
@MainActor
final class ImportedBuildT6NavigationTests: XCTestCase {
    private func fixture(_ name: String = "t6-build") throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
    private func build(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> BuildSnapshot {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        change(&value)
        return try BuildTransfer.snapshot(fromDraftJSON: JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }
    private func setup() throws -> (DraftStore, ImportedBuildLibraryModel, ImportedBuildLibraryNavigation, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let model = ImportedBuildLibraryModel(store: store)
        let navigation = ImportedBuildLibraryNavigation()
        navigation.setActive(true); navigation.attach(model)
        return (store, model, navigation, folder)
    }
    private func save(_ snapshot: BuildSnapshot, to store: DraftStore) async throws -> DraftRecord {
        let wrapper = try ImportedBuildRecord(snapshot: snapshot, markedSynthetic: false, sourceRevision: nil)
        return try await store.save(id: UUID(), expectedRevision: nil, title: "Synthetic route control",
                                    payload: JSONEncoder().encode(wrapper))
    }
    private func review(_ model: ImportedBuildLibraryModel) async throws {
        await model.t6Review.review(qualityJSON: try fixture("t6-quality-evaluation-run"),
                                   manifestJSON: try fixture("t6-deployment-manifest"))
        XCTAssertNotNil(model.t6Review.content?.localArtifacts)
    }
    private func export(_ model: ImportedBuildLibraryModel) async throws -> T6PlanExportRequest {
        let task = try XCTUnwrap(model.t6Review.preparePlanExport())
        await task.value
        return try XCTUnwrap(model.t6Review.planExport)
    }

    private func setup(preparation: T6ArtifactPreparation) throws
        -> (DraftStore, ImportedBuildLibraryModel, ImportedBuildLibraryNavigation, URL) {
        let (store, _, navigation, folder) = try setup()
        let model = ImportedBuildLibraryModel(store: store, preparation: .live,
                                             t6Preparation: preparation)
        navigation.attach(model)
        return (store, model, navigation, folder)
    }

    func testCapturedChildDisappearanceCannotCancelReopenedSameBuildWithoutFiles() async throws {
        let (store, model, _, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try await save(build(), to: store)
        await model.open(row)
        let before = try XCTUnwrap(model.openT6Review())
        let stale = model.t6DisappearanceHandler(for: before)
        let absent = model.t6DisappearanceHandler(for: nil)
        model.t6PresentationBinding(for: before).wrappedValue = false
        let after = try XCTUnwrap(model.openT6Review())
        XCTAssertNotEqual(before, after)
        await model.t6Review.retry()
        let accepted = try XCTUnwrap(model.t6Review.content)
        XCTAssertEqual(accepted.guidance.record, .notSupplied)
        XCTAssertNil(model.t6Review.planExport)
        XCTAssertFalse(stale()); XCTAssertFalse(absent()); XCTAssertFalse(stale())
        XCTAssertEqual(model.t6Review.content, accepted)
        XCTAssertEqual(model.t6Route, after)
        XCTAssertTrue(model.t6PresentationBinding(for: after).wrappedValue)
        XCTAssertNil(model.t6Review.notice); XCTAssertFalse(model.t6Review.busy)
        XCTAssertNil(model.t6Review.compatibility)
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(retained.payload, row.payload)
    }

    func testCapturedChildDisappearanceCannotCancelReopenedPendingWorkWithoutFiles() async throws {
        let gate = SuspendedT6NavigationPreparation()
        let (store, model, _, folder) = try setup(preparation: .init(prepare: { try await gate.prepare($0, $1) }))
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshot = try build(), row = try await save(snapshot, to: store)
        await model.open(row)
        let before = try XCTUnwrap(model.openT6Review())
        let stale = model.t6DisappearanceHandler(for: before)
        model.t6PresentationBinding(for: before).wrappedValue = false
        let after = try XCTUnwrap(model.openT6Review())
        let pending = Task { await model.t6Review.retry() }
        await gate.waitFor(0)
        XCTAssertTrue(model.t6Review.busy); XCTAssertNil(model.t6Review.content)
        XCTAssertFalse(stale()); XCTAssertFalse(stale())
        XCTAssertTrue(model.t6Review.busy); XCTAssertNil(model.t6Review.notice)
        XCTAssertEqual(model.t6Route, after)
        let expected = try T6ArtifactPreparation.evaluate(build: snapshot, quality: nil, manifest: nil)
        await gate.complete(0, .success(expected)); await pending.value
        XCTAssertEqual(model.t6Review.content, expected)
        XCTAssertFalse(model.t6Review.busy); XCTAssertNil(model.t6Review.notice)
        XCTAssertTrue(model.t6PresentationBinding(for: after).wrappedValue)
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(retained.payload, row.payload)
    }

    func testCurrentChildDisappearanceCancelsCompletedReviewWithoutFiles() async throws {
        let (store, model, _, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try await save(build(), to: store)
        await model.open(row)
        let route = try XCTUnwrap(model.openT6Review())
        let current = model.t6DisappearanceHandler(for: route)
        await model.t6Review.retry()
        XCTAssertNotNil(model.t6Review.content)
        XCTAssertTrue(current())
        XCTAssertNil(model.t6Review.content); XCTAssertFalse(model.t6Review.busy)
        XCTAssertEqual(model.t6Review.notice, "Review cancelled. Retry to inspect the selected records.")
        XCTAssertEqual(model.t6Route, route)
        XCTAssertTrue(model.t6PresentationBinding(for: route).wrappedValue)
        await model.t6Review.retry()
        XCTAssertNotNil(model.t6Review.content); XCTAssertNil(model.t6Review.notice)
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(retained.payload, row.payload)
    }

    func testCurrentChildDisappearanceCancelsPendingWorkWithoutFilesAndAllowsRetry() async throws {
        for oldFailure in [false, true] {
            let gate = SuspendedT6NavigationPreparation()
            let (store, model, _, folder) = try setup(preparation: .init(prepare: { try await gate.prepare($0, $1) }))
            defer { try? FileManager.default.removeItem(at: folder) }
            let snapshot = try build(), row = try await save(snapshot, to: store)
            await model.open(row)
            let route = try XCTUnwrap(model.openT6Review())
            let current = model.t6DisappearanceHandler(for: route)
            let pending = Task { await model.t6Review.retry() }; await gate.waitFor(0)
            XCTAssertTrue(model.t6Review.busy)
            XCTAssertTrue(current())
            let cancellation = model.t6Review.notice
            XCTAssertFalse(model.t6Review.busy); XCTAssertNil(model.t6Review.content)
            let expected = try T6ArtifactPreparation.evaluate(build: snapshot, quality: nil, manifest: nil)
            await gate.complete(0, oldFailure ? .failure(T6NavigationTestFailure.synthetic) : .success(expected))
            await pending.value
            XCTAssertNil(model.t6Review.content); XCTAssertFalse(model.t6Review.busy)
            XCTAssertEqual(model.t6Review.notice, cancellation)
            XCTAssertEqual(cancellation, "Review cancelled. Retry to inspect the selected records.")
            XCTAssertTrue(model.t6PresentationBinding(for: route).wrappedValue)
            let retry = Task { await model.t6Review.retry() }; await gate.waitFor(1)
            await gate.complete(1, .success(expected)); await retry.value
            XCTAssertEqual(model.t6Review.content, expected); XCTAssertNil(model.t6Review.notice)
            let retained = try await store.read(id: row.id)
            XCTAssertEqual(retained.payload, row.payload)
        }
    }

    func testCapturedChildDisappearancePreservesCurrentOwnedImporters() async throws {
        let (store, model, _, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try await save(build(), to: store)
        await model.open(row)
        for kind in [T6FileSelection.Kind.quality, .manifest] {
            let before = try XCTUnwrap(model.openT6Review())
            let stale = model.t6DisappearanceHandler(for: before)
            model.t6PresentationBinding(for: before).wrappedValue = false
            let after = try XCTUnwrap(model.openT6Review())
            let current = model.t6DisappearanceHandler(for: after)
            let request = try XCTUnwrap(model.t6Review.beginFileSelection(kind))
            XCTAssertFalse(stale()); XCTAssertFalse(current())
            XCTAssertNil(model.t6Review.notice); XCTAssertEqual(model.t6Route, after)
            let bytes = try fixture(kind == .quality ? "t6-quality-evaluation-run" : "t6-deployment-manifest")
            let url = folder.appendingPathComponent(kind == .quality ? "quality.json" : "manifest.json")
            try bytes.write(to: url)
            await model.t6Review.importFile(url, for: request)
            let accepted = try XCTUnwrap(model.t6Review.content)
            XCTAssertFalse(stale()) // The Files request has now ended.
            XCTAssertEqual(model.t6Review.content, accepted); XCTAssertNil(model.t6Review.notice)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            model.t6PresentationBinding(for: after).wrappedValue = false
        }
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(retained.payload, row.payload)
    }

    func testCapturedChildDisappearancePreservesCurrentOwnedExporter() async throws {
        let (store, model, _, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try await save(build(), to: store)
        await model.open(row)
        for outcome in [T6PlanExportOutcome.saved, .failed, .cancelled] {
            let before = try XCTUnwrap(model.openT6Review())
            let stale = model.t6DisappearanceHandler(for: before)
            model.t6PresentationBinding(for: before).wrappedValue = false
            let after = try XCTUnwrap(model.openT6Review())
            let current = model.t6DisappearanceHandler(for: after)
            try await review(model)
            let request = try await export(model)
            XCTAssertTrue(model.t6Review.beginPlanExport(request, disclosureReviewed: true))
            XCTAssertFalse(stale()); XCTAssertFalse(current()); XCTAssertFalse(current())
            XCTAssertEqual(model.t6Review.planExport, request); XCTAssertNil(model.t6Review.notice)
            model.t6Review.finishPlanExport(outcome, for: request)
            let accepted = try XCTUnwrap(model.t6Review.content), notice = model.t6Review.notice
            XCTAssertNil(model.t6Review.planExport); XCTAssertNotNil(notice)
            XCTAssertFalse(stale()) // No active exporter remains to mask a stale callback.
            XCTAssertEqual(model.t6Review.content, accepted); XCTAssertEqual(model.t6Review.notice, notice)
            XCTAssertEqual(model.t6Route, after)
            model.t6PresentationBinding(for: after).wrappedValue = false
        }
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(retained.payload, row.payload)
    }

    func testRouteRequiresAnActiveSelectedBuildAndHasOnePresentation() async throws {
        let (store, model, navigation, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNil(model.openT6Review())
        let snapshot = try build(), row = try await save(snapshot, to: store)
        await model.open(row)
        navigation.setActive(false)
        XCTAssertNil(model.openT6Review())
        navigation.setActive(true)
        let route = try XCTUnwrap(model.openT6Review())
        let binding = model.t6PresentationBinding(for: route)
        XCTAssertTrue(binding.wrappedValue)
        XCTAssertNil(model.openT6Review())
        XCTAssertEqual(model.t6Route, route)
        XCTAssertEqual(model.t6Review.build, snapshot)
        XCTAssertNil(model.t6Review.compatibility)
        await model.t6Review.retry()
        XCTAssertEqual(model.t6Review.content?.guidance.record, .notSupplied)
        binding.wrappedValue = false
        XCTAssertFalse(binding.wrappedValue)
        XCTAssertNil(model.t6Route)
        XCTAssertEqual(model.snapshot, snapshot)
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(retained.payload, row.payload)
    }

    func testNavigationPopRetiresBothOwnedImportersAndLateCallbacksBeforeRecovery() async throws {
        let (store, model, _, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try await save(build(), to: store)
        await model.open(row)
        for kind in [T6FileSelection.Kind.quality, .manifest] {
            let source = try fixture(kind == .quality ? "t6-quality-evaluation-run" : "t6-deployment-manifest")
            let url = folder.appendingPathComponent(kind == .quality ? "quality.json" : "manifest.json")
            try source.write(to: url)
            let route = try XCTUnwrap(model.openT6Review())
            try await review(model)
            let request = try XCTUnwrap(model.t6Review.beginFileSelection(kind))
            XCTAssertFalse(model.t6Review.handleDisappearance())
            model.t6PresentationBinding(for: route).wrappedValue = false
            let cancellation = model.t6Review.notice
            XCTAssertNotNil(cancellation); XCTAssertNil(model.t6Route)
            await model.t6Review.importFile(url, for: request)
            model.t6Review.fileSelectionFailed(for: request)
            model.t6Review.fileSelectionCancelled(for: request)
            XCTAssertEqual(model.t6Review.notice, cancellation)
            XCTAssertNil(model.t6Review.content); XCTAssertFalse(model.t6Review.busy)
            XCTAssertEqual(try Data(contentsOf: url), source)
            let next = try XCTUnwrap(model.openT6Review())
            XCTAssertNotEqual(next, route)
            await model.t6Review.retry()
            XCTAssertNotNil(model.t6Review.content?.localArtifacts)
            let fresh = try XCTUnwrap(model.t6Review.beginFileSelection(kind))
            XCTAssertNotEqual(fresh, request)
            await model.t6Review.importFile(url, for: fresh)
            XCTAssertNotNil(model.t6Review.content?.localArtifacts)
            model.t6PresentationBinding(for: next).wrappedValue = false
        }
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(retained.payload, row.payload)
    }

    func testActualTabWithdrawalRetiresOwnedExportButSameTabReappearancePreservesIt() async throws {
        let (store, model, navigation, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try await save(build(), to: store)
        await model.open(row)
        let route = try XCTUnwrap(model.openT6Review())
        try await review(model)
        let request = try await export(model)
        XCTAssertTrue(model.t6Review.beginPlanExport(request, disclosureReviewed: true))
        XCTAssertFalse(model.t6Review.handleDisappearance())
        navigation.attach(model); navigation.setActive(true)
        XCTAssertEqual(model.t6Review.planExport, request)
        XCTAssertFalse(model.t6Review.handleDisappearance())
        navigation.setActive(false)
        let cancellation = model.t6Review.notice
        XCTAssertNotNil(cancellation); XCTAssertNil(model.t6Route)
        XCTAssertFalse(model.t6PresentationBinding(for: route).wrappedValue)
        XCTAssertNil(model.t6Review.planExport); XCTAssertNil(model.openT6Review())
        for outcome in [T6PlanExportOutcome.saved, .failed, .cancelled] {
            model.t6Review.finishPlanExport(outcome, for: request)
            XCTAssertEqual(model.t6Review.notice, cancellation)
        }
        navigation.setActive(true)
        XCTAssertNotEqual(try XCTUnwrap(model.openT6Review()), route)
        await model.t6Review.retry()
        let fresh = try await export(model)
        XCTAssertNotEqual(fresh, request)
        XCTAssertEqual(fresh.report, request.report)
        XCTAssertFalse(model.t6Review.beginPlanExport(fresh, disclosureReviewed: false))
        XCTAssertTrue(model.t6Review.beginPlanExport(fresh, disclosureReviewed: true))
        model.t6Review.finishPlanExport(.cancelled, for: fresh)
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(retained.payload, row.payload)
    }

    func testOldNavigationBindingCannotWithdrawReopenedSameBuildRoute() async throws {
        let (store, model, _, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try await save(build(), to: store)
        await model.open(row)
        let before = try XCTUnwrap(model.openT6Review())
        let stale = model.t6PresentationBinding(for: before)
        let oldPick = try XCTUnwrap(model.t6Review.beginFileSelection(.quality))
        stale.wrappedValue = false
        let after = try XCTUnwrap(model.openT6Review())
        let fresh = try XCTUnwrap(model.t6Review.beginFileSelection(.quality))
        XCTAssertNotEqual(before, after)
        stale.wrappedValue = false
        model.t6PresentationBinding(for: nil).wrappedValue = false
        model.t6Review.fileSelectionFailed(for: oldPick)
        model.t6Review.fileSelectionCancelled(for: oldPick)
        XCTAssertEqual(model.t6Route, after)
        XCTAssertTrue(model.t6PresentationBinding(for: after).wrappedValue)
        XCTAssertFalse(model.t6Review.handleDisappearance())
        XCTAssertNil(model.t6Review.notice)
        let bytes = try fixture("t6-quality-evaluation-run"), url = folder.appendingPathComponent("quality.json")
        try bytes.write(to: url)
        await model.t6Review.importFile(url, for: oldPick)
        XCTAssertNil(model.t6Review.content)
        await model.t6Review.importFile(url, for: fresh)
        XCTAssertNotNil(model.t6Review.content)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testLabelRenamePreservesRouteButSameIDRevisionWithDifferentLocksWithdrawsIt() async throws {
        let (store, model, _, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = try build(), row = try await save(before, to: store)
        let after = try build { value in
            var locks = value["locks"] as! [String: Any]
            locks["catalog_snapshot_id"] = "catalog.other"; value["locks"] = locks
        }
        let other = try await save(after, to: store)
        await model.open(row)
        let route = try XCTUnwrap(model.openT6Review())
        let pick = try XCTUnwrap(model.t6Review.beginFileSelection(.manifest))
        await model.rename(row, to: "Renamed locally")
        XCTAssertEqual(model.t6Route, route)
        XCTAssertTrue(model.t6PresentationBinding(for: route).wrappedValue)
        XCTAssertFalse(model.t6Review.handleDisappearance())
        XCTAssertEqual(model.selected?.revision, row.revision + 1)
        await model.open(other)
        XCTAssertEqual(before.id, after.id)
        XCTAssertEqual(before.value.t6Object?["revision"], after.value.t6Object?["revision"])
        XCTAssertNil(model.t6Route)
        XCTAssertEqual(model.t6Review.build, after)
        XCTAssertNil(model.t6Review.compatibility); XCTAssertNil(model.t6Review.content)
        model.t6Review.fileSelectionFailed(for: pick)
        XCTAssertNil(model.t6Review.notice)
        XCTAssertNotEqual(try XCTUnwrap(model.openT6Review()), route)
    }

    func testDeletingAnotherRowKeepsOwnedRequestAndDeletingSelectedClearsIt() async throws {
        let (store, model, _, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try await save(build(), to: store)
        let other = try await save(build { $0["id"] = "build.other" }, to: store)
        await model.open(row)
        let route = try XCTUnwrap(model.openT6Review())
        let pick = try XCTUnwrap(model.t6Review.beginFileSelection(.quality))
        await model.delete(other)
        XCTAssertEqual(model.t6Route, route)
        XCTAssertFalse(model.t6Review.handleDisappearance())
        await model.delete(row)
        XCTAssertNil(model.selected); XCTAssertNil(model.snapshot); XCTAssertNil(model.t6Route)
        XCTAssertNil(model.t6Review.build); XCTAssertNil(model.t6Review.content)
        model.t6Review.fileSelectionFailed(for: pick)
        model.t6Review.fileSelectionCancelled(for: pick)
        XCTAssertNil(model.t6Review.notice)
        XCTAssertNil(model.openT6Review())
    }

    func testClosingSelectedBuildClearsOwnedExportWithoutDeletingRetainedRow() async throws {
        let (store, model, _, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try await save(build(), to: store)
        await model.open(row)
        let route = try XCTUnwrap(model.openT6Review())
        try await review(model)
        let request = try await export(model)
        XCTAssertTrue(model.t6Review.beginPlanExport(request, disclosureReviewed: true))
        model.closeSelectedBuild()
        XCTAssertNil(model.selected); XCTAssertNil(model.snapshot); XCTAssertNil(model.t6Route)
        XCTAssertNil(model.t6Review.build); XCTAssertNil(model.t6Review.planExport)
        for outcome in [T6PlanExportOutcome.saved, .failed, .cancelled] {
            model.t6Review.finishPlanExport(outcome, for: request)
            XCTAssertNil(model.t6Review.notice)
        }
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(retained.payload, row.payload)
        await model.open(retained)
        XCTAssertNotEqual(try XCTUnwrap(model.openT6Review()), route)
        await model.t6Review.retry()
        XCTAssertEqual(model.t6Review.content?.guidance.record, .notSupplied)
        XCTAssertNil(model.t6Review.compatibility)
    }

    func testFailedStorageActionPreservesRouteUntilActualLibraryOwnerReplacement() async throws {
        let (store, model, navigation, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try await save(build(), to: store)
        let removed = try await save(build { $0["id"] = "build.removed" }, to: store)
        await model.open(row)
        let route = try XCTUnwrap(model.openT6Review())
        let pick = try XCTUnwrap(model.t6Review.beginFileSelection(.manifest))
        try await store.delete(id: removed.id, expectedRevision: removed.revision)
        await model.open(removed)
        XCTAssertEqual(model.t6Route, route)
        _ = try await store.rename(id: row.id, expectedRevision: row.revision, title: "External local label")
        await model.delete(row)
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(model.t6Route, route)
        XCTAssertFalse(model.t6Review.handleDisappearance())
        let replacement = ImportedBuildLibraryModel(store: store)
        navigation.attach(replacement)
        let cancellation = model.t6Review.notice
        XCTAssertNotNil(cancellation); XCTAssertNil(model.t6Route)
        XCTAssertNil(model.openT6Review())
        model.t6Review.fileSelectionFailed(for: pick)
        XCTAssertEqual(model.t6Review.notice, cancellation)
        let retained = try await store.read(id: row.id)
        XCTAssertEqual(retained.payload, row.payload)
        await replacement.open(retained)
        XCTAssertNotNil(replacement.openT6Review())
        XCTAssertNil(replacement.t6Review.compatibility)
    }
}
