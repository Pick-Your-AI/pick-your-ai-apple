import Foundation
import PlannerCore
import PlannerTransfer
import XCTest
@testable import PlannerUI
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private enum T6TestFailure: Error { case synthetic }

/// Deliberately ignores cancellation to prove acceptance, rather than transport
/// cooperation, prevents an obsolete success or failure from changing the UI.
private actor SuspendedT6Preparation {
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

/// Admission controls can complete immediately: an obsolete picker must make
/// zero preparation calls, rather than hanging a suspended fake if it regresses.
private actor CountingT6Preparation {
    private(set) var callCount = 0
    func prepare(_ build: BuildSnapshot, _ inputs: T6ArtifactInputs) throws -> T6ReviewContent {
        callCount += 1
        return try T6ArtifactPreparation.evaluate(build: build, quality: nil, manifest: nil)
    }
}

@MainActor
final class T6ReviewModelTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
    private func object(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixture(name)) as? [String: Any])
    }
    private func bytes(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    private func build(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> BuildSnapshot {
        var object = try object("t6-build"); mutate(&object)
        return try BuildTransfer.snapshot(fromDraftJSON: bytes(object))
    }
    private func importFile(_ url: URL, kind: T6FileSelection.Kind, model: T6ReviewModel) async throws {
        let request = try XCTUnwrap(model.beginFileSelection(kind))
        await model.importFile(url, for: request)
    }
    private func content(_ build: BuildSnapshot) throws -> T6ReviewContent {
        try T6ArtifactPreparation.evaluate(build: build, quality: nil, manifest: nil)
    }
    private func report(_ result: String = "valid", catalog: String = "catalog.fixture.1") throws -> EvaluationReport {
        try EvaluationReport.decode(bytes([
            "schema_version": "1.0.0", "id": "evaluation.synthetic.t6", "build_id": "build.fixture.1",
            "build_revision": 1, "catalog_snapshot_id": catalog, "ruleset_id": "rules.fixture.1",
            "ruleset_version": "1.0.0", "dependency_graph_id": "dependencies.core.1",
            "dependency_graph_revision": 1, "evaluated_at": "2026-10-16T09:00:00Z",
            "result": result, "deployment_readiness": "needs_review", "findings": [],
            "summary": ["passed": 0, "failed": 0, "unknown": 0, "skipped": 0],
        ]))
    }
    private func current(_ report: EvaluationReport) async -> AnalysisState<EvaluationReport> {
        let store = AnalysisStore<EvaluationReport>()
        let request = await store.begin(for: report.analysisIdentity)
        _ = await store.receive(report, for: request)
        return await store.state
    }

    func testReportedCompatibilityPassDoesNotSupplyQualityOrApproval() async throws {
        let model = T6ReviewModel(build: try build())
        let state = await current(try report())
        XCTAssertTrue(model.receiveCompatibility(state, for: try build()))
        await model.review()
        XCTAssertEqual(model.compatibility?.result, .valid)
        XCTAssertEqual(model.content?.guidance.record, .notSupplied)
        XCTAssertTrue(model.content?.guidance.cautions.contains(.approvalNotEstablished) == true)
        XCTAssertEqual(model.content?.manifestIssue, .notSupplied)
        XCTAssertNil(model.content?.localArtifacts)
    }

    func testReportedQualityFailureAndZeroAreNotErasedByCompatibility() async throws {
        let model = T6ReviewModel(build: try build())
        let state = await current(try report())
        XCTAssertTrue(model.receiveCompatibility(state, for: try build()))
        await model.review(qualityJSON: try fixture("t6-quality-evaluation-run"))
        let failed = try XCTUnwrap(model.content?.guidance.reportedFailedMeasurements)
        XCTAssertEqual(failed.count, 1); XCTAssertEqual(failed[0].observed, 0)
        XCTAssertFalse(failed[0].passed); XCTAssertEqual(failed[0].threshold, Decimal(string: "0.85"))
        XCTAssertEqual(model.compatibility?.result, .valid)
    }

    func testReportedQualityPassDoesNotOverrideIncompatibleInputs() async throws {
        var run = try object("t6-quality-evaluation-run"); run["status"] = "passed"
        var rows = try XCTUnwrap(run["measurements"] as? [[String: Any]])
        rows[0]["passed"] = true; run["measurements"] = rows
        let model = T6ReviewModel(build: try build())
        let state = await current(try report("invalid"))
        XCTAssertTrue(model.receiveCompatibility(state, for: try build()))
        await model.review(qualityJSON: try bytes(run))
        XCTAssertEqual(model.compatibility?.result, .invalid)
        XCTAssertEqual(model.content?.guidance.reportedFailedMeasurements, [])
        XCTAssertTrue(model.content?.guidance.cautions.contains(.approvalNotEstablished) == true)
    }

    func testMissingCurrentCompatibilityOrWrongLocksNeverBecomesPass() async throws {
        let model = T6ReviewModel(build: try build())
        let matching = await current(try report())
        XCTAssertTrue(model.receiveCompatibility(matching, for: try build()))
        let foreign = await current(try report(catalog: "catalog.other"))
        XCTAssertFalse(model.receiveCompatibility(foreign, for: try build()))
        XCTAssertNil(model.compatibility)
        XCTAssertFalse(model.receiveCompatibility(.unavailable(identity: nil, reason: .notRequested), for: try build()))
        await model.review(); XCTAssertNil(model.compatibility)
        let original = try build()
        let changed = try build { $0["extensions"] = ["x_planning_notes": ["Changed retained input"]] }
        model.select(changed)
        XCTAssertFalse(model.receiveCompatibility(matching, for: original))
        XCTAssertNil(model.compatibility)
        XCTAssertTrue(model.receiveCompatibility(matching, for: changed))
        XCTAssertFalse(model.receiveCompatibility(.unavailable(identity: nil, reason: .failed), for: original))
        XCTAssertEqual(model.compatibility?.result, .valid)
    }

    func testProposedPairPreservesPendingApprovalsLocksMonitoringAndPrivateFields() async throws {
        let original = try build()
        let manifestBytes = try fixture("t6-deployment-manifest")
        let originalManifest = try DeploymentManifest.decode(manifestBytes)
        let model = T6ReviewModel(build: original)
        await model.review(manifestJSON: manifestBytes)
        let artifacts = try XCTUnwrap(model.content?.localArtifacts)
        let reopened = try BuildTransfer.snapshot(fromDraftJSON: artifacts.buildJSON)
        XCTAssertEqual(reopened, original)
        XCTAssertEqual(reopened.locks, original.locks)
        XCTAssertEqual(try DeploymentManifest.decode(artifacts.manifestJSON), originalManifest)
        XCTAssertEqual(originalManifest.approvals[0].t6Object?["decision"], .string("pending"))
        XCTAssertNotNil(reopened.value.t6Object?["extensions"])
        XCTAssertNil(model.content?.manifestIssue)
        // Public sharing remains the separately reviewed existing projection.
        let shared = try BuildTransfer.export(original, publicOwnerAlias: "synthetic-public-alias")
        let publicBuild = try BuildTransfer.preview(shared).snapshot
        XCTAssertNil(publicBuild.value.t6Object?["extensions"])
        XCTAssertNotEqual(shared, artifacts.buildJSON)
        XCTAssertEqual(model.build, original)
    }

    func testEveryNonProposedStatusIsRetainedWithoutPreparingArtifacts() async throws {
        for status in ["approved", "rejected", "deployed", "rolled_back"] {
            var manifest = try object("t6-deployment-manifest"); manifest["status"] = status
            let model = T6ReviewModel(build: try build())
            await model.review(manifestJSON: try bytes(manifest))
            XCTAssertEqual(model.content?.manifest?.status, status)
            XCTAssertEqual(model.content?.manifestIssue, .notProposed)
            XCTAssertNil(model.content?.localArtifacts)
            XCTAssertEqual(model.content?.manifest?.approvals[0].t6Object?["decision"], .string("pending"))
        }
    }

    func testMissingRequiredManifestReferencesStayIncompleteAndKeepQuality() async throws {
        for key in ["compatibility_report_id", "quality_run_id", "cost_estimate_id", "resource_estimate_id", "approvals"] {
            var manifest = try object("t6-deployment-manifest"); manifest.removeValue(forKey: key)
            let model = T6ReviewModel(build: try build())
            await model.review(qualityJSON: try fixture("t6-quality-evaluation-run"), manifestJSON: try bytes(manifest))
            XCTAssertEqual(model.content?.manifestIssue, .unreadableOrIncomplete, key)
            XCTAssertNil(model.content?.manifest, key); XCTAssertNil(model.content?.localArtifacts, key)
            XCTAssertEqual(model.content?.guidance.reportedFailedMeasurements?.count, 1)
        }
    }

    func testOptionalSelectionsAndDisabledFalseRemainExplicit() async throws {
        let sparse = try build { object in
            var selections = object["selections"] as! [[String: Any]]
            selections.removeAll { ["guardrail", "monitoring_stack"].contains($0["kind"] as! String) }
            for index in selections.indices where selections[index]["kind"] as? String == "evaluation_suite" {
                selections[index]["enabled"] = false
            }
            object["selections"] = selections
        }
        let model = T6ReviewModel(build: sparse)
        await model.review()
        XCTAssertTrue(model.content?.guidance.guardrails.isEmpty == true)
        XCTAssertEqual(model.content?.guidance.evaluationSuites.first?.enabled, false)
        XCTAssertTrue(model.content?.guidance.cautions.contains(.noEnabledEvaluationSuite) == true)
        XCTAssertEqual(model.build?.value.t6Object?["objectives"]?.t6Object?["requests_per_day"], .number(0))
    }

    func testWrongKindDuplicateOrDisabledTargetCannotPreparePlan() async throws {
        for mutation in 0..<2 {
            let input = try build { object in
                var selections = object["selections"] as! [[String: Any]]
                if mutation == 0 {
                    var duplicate = selections.first!
                    duplicate["id"] = "sel_deployment_target"; selections.append(duplicate)
                } else {
                    for index in selections.indices where selections[index]["id"] as? String == "sel_deployment_target" {
                        selections[index]["enabled"] = false
                    }
                }
                object["selections"] = selections
            }
            let model = T6ReviewModel(build: input)
            await model.review(manifestJSON: try fixture("t6-deployment-manifest"))
            XCTAssertEqual(model.content?.manifestIssue, .targetBinding)
            XCTAssertNil(model.content?.localArtifacts)
        }
    }

    func testForeignBuildAndRevisionRecordsAreNeverRewrittenForFork() async throws {
        for key in ["id", "revision"] {
            let input = try build {
                if key == "id" { $0[key] = "build.synthetic.fork" } else { $0[key] = 2 }
            }
            let model = T6ReviewModel(build: input)
            await model.review(qualityJSON: try fixture("t6-quality-evaluation-run"))
            XCTAssertNil(model.content); XCTAssertNotNil(model.notice)
            await model.review(manifestJSON: try fixture("t6-deployment-manifest"))
            XCTAssertEqual(model.content?.manifestIssue, .buildMismatch)
            XCTAssertEqual(model.content?.manifest?.buildID, "build.fixture.1")
            XCTAssertNil(model.content?.localArtifacts); XCTAssertEqual(model.build, input)
        }
    }

    func testStaleSuccessAfterChangedLockCannotReplaceCurrentRetry() async throws {
        let gate = SuspendedT6Preparation()
        let original = try build()
        let changed = try build { object in
            var locks = object["locks"] as! [String: Any]; locks["ruleset_version"] = "1.0.1"; object["locks"] = locks
        }
        let model = T6ReviewModel(build: original, preparation: .init(prepare: { try await gate.prepare($0, $1) }))
        let old = Task { await model.review() }; await gate.waitFor(0)
        model.select(changed)
        let fresh = Task { await model.review() }; await gate.waitFor(1)
        await gate.complete(1, .success(try content(changed))); await fresh.value
        await gate.complete(0, .success(try content(original))); await old.value
        XCTAssertEqual(model.content?.build, changed); XCTAssertNil(model.notice); XCTAssertFalse(model.busy)
    }

    func testStaleFailureCannotReplaceNewSuccess() async throws {
        let gate = SuspendedT6Preparation(); let input = try build()
        let model = T6ReviewModel(build: input, preparation: .init(prepare: { try await gate.prepare($0, $1) }))
        let old = Task { await model.review() }; await gate.waitFor(0)
        let fresh = Task { await model.retry() }; await gate.waitFor(1)
        await gate.complete(1, .success(try content(input))); await fresh.value
        await gate.complete(0, .failure(T6TestFailure.synthetic)); await old.value
        XCTAssertEqual(model.content?.build, input); XCTAssertNil(model.notice)
    }

    func testCancellationAndDeletionRejectLateCallbacksThenAllowRecovery() async throws {
        let gate = SuspendedT6Preparation(); let input = try build()
        let model = T6ReviewModel(build: input, preparation: .init(prepare: { try await gate.prepare($0, $1) }))
        let cancelled = Task { await model.review() }; await gate.waitFor(0)
        model.cancel(); await gate.complete(0, .success(try content(input))); await cancelled.value
        XCTAssertNil(model.content); XCTAssertFalse(model.busy)
        let deleted = Task { await model.retry() }; await gate.waitFor(1)
        model.clear(); await gate.complete(1, .failure(T6TestFailure.synthetic)); await deleted.value
        XCTAssertNil(model.build); XCTAssertNil(model.content); XCTAssertNil(model.notice)
        model.select(input)
        let retry = Task { await model.review() }; await gate.waitFor(2)
        await gate.complete(2, .success(try content(input))); await retry.value
        XCTAssertEqual(model.content?.build, input); XCTAssertNil(model.notice)
    }

    func testCallerCancellationRejectsCompletionEvenWhenWorkerIgnoresIt() async throws {
        let gate = SuspendedT6Preparation(); let input = try build()
        let model = T6ReviewModel(build: input, preparation: .init(prepare: { try await gate.prepare($0, $1) }))
        let caller = Task { await model.review() }; await gate.waitFor(0)
        caller.cancel(); await gate.complete(0, .success(try content(input))); await caller.value
        XCTAssertNil(model.content); XCTAssertFalse(model.busy)
        XCTAssertTrue(model.notice?.contains("cancelled") == true)
    }

    func testMalformedOversizedAndDuplicateKeysFailWithoutPrivateErrorTextAndRecover() async throws {
        let model = T6ReviewModel(build: try build())
        for data in [Data("PRIVATE-CANARY".utf8), Data(repeating: 32, count: BuildTransfer.maximumBytes + 1),
                     Data("{\"id\":\"PRIVATE-CANARY\",\"id\":\"another\"}".utf8)] {
            await model.review(qualityJSON: data)
            XCTAssertNil(model.content); XCTAssertNotNil(model.notice)
            XCTAssertFalse(model.notice?.contains("PRIVATE-CANARY") == true)
            XCTAssertFalse(model.busy)
        }
        await model.review(qualityJSON: try fixture("t6-quality-evaluation-run"))
        XCTAssertNotNil(model.content); XCTAssertNil(model.notice)
    }

    func testFileReadIsBoundedAndRemovalReturnsToUnanswered() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("quality.json")
        let original = try fixture("t6-quality-evaluation-run"); try original.write(to: url)
        let input = try build()
        let model = T6ReviewModel(build: input)
        try await importFile(url, kind: .quality, model: model); XCTAssertNotNil(model.content)
        XCTAssertEqual(try Data(contentsOf: url), original)
        await model.removeQuality(); XCTAssertEqual(model.content?.guidance.record, .notSupplied)
        try Data(repeating: 32, count: BuildTransfer.maximumBytes + 1).write(to: url)
        try await importFile(url, kind: .quality, model: model); XCTAssertNil(model.content); XCTAssertNotNil(model.notice)
        try await importFile(folder, kind: .quality, model: model); XCTAssertNil(model.content); XCTAssertNotNil(model.notice)
        let fifo = folder.appendingPathComponent("input-fifo")
        let created = fifo.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }; return mkfifo(path, 0o600)
        }
        XCTAssertEqual(created, 0)
        if created == 0 {
            try await importFile(fifo, kind: .quality, model: model)
            XCTAssertNil(model.content); XCTAssertNotNil(model.notice)
        }
        try original.write(to: url)
        try await importFile(url, kind: .quality, model: model); XCTAssertNotNil(model.content); XCTAssertNil(model.notice)
        let manifestURL = folder.appendingPathComponent("manifest.json")
        let manifest = try fixture("t6-deployment-manifest"); try manifest.write(to: manifestURL)
        try await importFile(manifestURL, kind: .manifest, model: model)
        XCTAssertNotNil(model.content?.localArtifacts)
        XCTAssertEqual(try Data(contentsOf: manifestURL), manifest)
        let foreign = try build { $0["id"] = "build.other.retained" }
        let foreignModel = T6ReviewModel(build: foreign)
        let foreignRequest = try XCTUnwrap(foreignModel.beginFileSelection(.quality))
        await model.importFile(folder, for: foreignRequest)
        model.fileSelectionFailed(for: foreignRequest)
        XCTAssertEqual(model.content?.build, input); XCTAssertNil(model.notice)
    }

    func testCancelledPickerSuccessAndFailureCannotReviveSameBuild() async throws {
        let input = try build()
        let url = URL(fileURLWithPath: "/synthetic-not-opened.json")
        for kind in [T6FileSelection.Kind.quality, .manifest] {
            for pickerCancellation in [false, true] {
                let counter = CountingT6Preparation()
                let model = T6ReviewModel(build: input, preparation: .init(prepare: { try await counter.prepare($0, $1) }))
                let obsolete = try XCTUnwrap(model.beginFileSelection(kind))
                if pickerCancellation { model.fileSelectionCancelled(for: obsolete) } else { model.cancel() }
                let cancelledNotice = model.notice
                await model.importFile(url, for: obsolete)
                model.fileSelectionFailed(for: obsolete)
                model.fileSelectionCancelled(for: obsolete)
                let callsBeforeRecovery = await counter.callCount
                XCTAssertEqual(callsBeforeRecovery, 0)
                XCTAssertEqual(model.build, input); XCTAssertNil(model.content); XCTAssertFalse(model.busy)
                XCTAssertEqual(model.notice, cancelledNotice)
                XCTAssertTrue(cancelledNotice?.contains("cancelled") == true)

                let fresh = try XCTUnwrap(model.beginFileSelection(kind))
                await model.importFile(url, for: fresh)
                model.fileSelectionFailed(for: obsolete)
                model.fileSelectionCancelled(for: obsolete)
                let callsAfterRecovery = await counter.callCount
                XCTAssertEqual(callsAfterRecovery, 1)
                XCTAssertEqual(model.content?.build, input); XCTAssertNil(model.notice)
            }
        }
    }

    func testNewPickerSupersedesOldCallbacksAndSuccessIsSingleUse() async throws {
        let input = try build(); let counter = CountingT6Preparation()
        let model = T6ReviewModel(build: input, preparation: .init(prepare: { try await counter.prepare($0, $1) }))
        let url = URL(fileURLWithPath: "/synthetic-not-opened.json")
        let obsolete = try XCTUnwrap(model.beginFileSelection(.quality))
        let fresh = try XCTUnwrap(model.beginFileSelection(.manifest))
        await model.importFile(url, for: obsolete)
        model.fileSelectionFailed(for: obsolete)
        model.fileSelectionCancelled(for: obsolete)
        let before = await counter.callCount
        XCTAssertEqual(before, 0); XCTAssertNil(model.content); XCTAssertNil(model.notice)
        await model.importFile(url, for: fresh)
        let accepted = model.content
        await model.importFile(url, for: fresh)
        model.fileSelectionFailed(for: fresh)
        model.fileSelectionCancelled(for: fresh)
        let after = await counter.callCount
        XCTAssertEqual(after, 1); XCTAssertEqual(model.content, accepted); XCTAssertNotNil(accepted)
        XCTAssertNil(model.notice); XCTAssertFalse(model.busy)
    }

    func testReviewRetryAndRestoredSelectionInvalidatePendingPicker() async throws {
        let input = try build()
        let changed = try build { $0["extensions"] = ["x_planning_notes": ["Changed selected content"]] }
        let url = URL(fileURLWithPath: "/synthetic-not-opened.json")
        for transition in ["review", "retry", "selection", "deletion"] {
            let counter = CountingT6Preparation()
            let model = T6ReviewModel(build: input, preparation: .init(prepare: { try await counter.prepare($0, $1) }))
            let obsolete = try XCTUnwrap(model.beginFileSelection(.quality))
            switch transition {
            case "review": await model.review()
            case "retry": await model.retry()
            case "selection": model.select(changed); model.select(input)
            default: model.clear(); model.select(input)
            }
            let accepted = model.content; let notice = model.notice
            let before = await counter.callCount
            await model.importFile(url, for: obsolete)
            model.fileSelectionFailed(for: obsolete)
            model.fileSelectionCancelled(for: obsolete)
            let after = await counter.callCount
            XCTAssertEqual(after, before, transition)
            XCTAssertEqual(model.content, accepted, transition); XCTAssertEqual(model.notice, notice, transition)
            XCTAssertEqual(model.build, input, transition); XCTAssertFalse(model.busy, transition)
            let fresh = try XCTUnwrap(model.beginFileSelection(.quality))
            await model.importFile(url, for: fresh)
            let recovered = await counter.callCount
            XCTAssertEqual(recovered, before + 1, transition)
            XCTAssertEqual(model.content?.build, input, transition); XCTAssertNil(model.notice, transition)
        }
    }

    func testOwnedImporterDisappearancePreservesItsExactTerminalCallback() async throws {
        let input = try build()
        let url = URL(fileURLWithPath: "/synthetic-not-opened.json")
        for kind in [T6FileSelection.Kind.quality, .manifest] {
            for terminal in ["success", "failure", "cancelled"] {
                let counter = CountingT6Preparation()
                let model = T6ReviewModel(build: input, preparation: .init(prepare: { try await counter.prepare($0, $1) }))
                let request = try XCTUnwrap(model.beginFileSelection(kind))
                XCTAssertFalse(model.handleDisappearance())
                XCTAssertFalse(model.handleDisappearance())
                XCTAssertEqual(model.build, input); XCTAssertNil(model.notice)
                switch terminal {
                case "success":
                    await model.importFile(url, for: request)
                    XCTAssertEqual(model.content?.build, input); XCTAssertNil(model.notice)
                case "failure":
                    model.fileSelectionFailed(for: request)
                    XCTAssertNil(model.content)
                    XCTAssertEqual(model.notice, "The file selection did not complete. Existing records were not changed.")
                default:
                    model.fileSelectionCancelled(for: request)
                    XCTAssertNil(model.content)
                    XCTAssertEqual(model.notice, "Review cancelled. Retry to inspect the selected records.")
                }
                let accepted = model.content; let notice = model.notice
                await model.importFile(url, for: request)
                model.fileSelectionFailed(for: request)
                model.fileSelectionCancelled(for: request)
                let calls = await counter.callCount
                XCTAssertEqual(calls, terminal == "success" ? 1 : 0)
                XCTAssertEqual(model.content, accepted); XCTAssertEqual(model.notice, notice)
                XCTAssertFalse(model.busy)
            }
        }
    }

    func testExplicitRouteCancellationRetiresAnOwnedImporterAfterDisappearance() async throws {
        let input = try build()
        let url = URL(fileURLWithPath: "/synthetic-not-opened.json")
        for kind in [T6FileSelection.Kind.quality, .manifest] {
            for closesRecord in [false, true] {
                let counter = CountingT6Preparation()
                let model = T6ReviewModel(build: input, preparation: .init(prepare: { try await counter.prepare($0, $1) }))
                let request = try XCTUnwrap(model.beginFileSelection(kind))
                XCTAssertFalse(model.handleDisappearance())
                if closesRecord { model.clear() } else { model.cancel() }
                let notice = model.notice
                await model.importFile(url, for: request)
                model.fileSelectionFailed(for: request)
                model.fileSelectionCancelled(for: request)
                let calls = await counter.callCount
                XCTAssertEqual(calls, 0); XCTAssertNil(model.content); XCTAssertFalse(model.busy)
                XCTAssertEqual(model.notice, notice)
                if closesRecord { XCTAssertNil(model.build) }
                else { XCTAssertEqual(model.build, input) }
            }
        }
    }

    func testOrdinaryDisappearanceCancelsUnfinishedReviewAndAllowsRecovery() async throws {
        let input = try build()
        for oldFailure in [false, true] {
            let gate = SuspendedT6Preparation()
            let model = T6ReviewModel(build: input, preparation: .init(prepare: { try await gate.prepare($0, $1) }))
            let pending = Task { await model.review() }; await gate.waitFor(0)
            XCTAssertTrue(model.busy)
            XCTAssertTrue(model.handleDisappearance())
            let notice = model.notice
            await gate.complete(0, oldFailure ? .failure(T6TestFailure.synthetic) : .success(try content(input)))
            await pending.value
            XCTAssertNil(model.content); XCTAssertFalse(model.busy)
            XCTAssertEqual(model.build, input); XCTAssertEqual(model.notice, notice)
            XCTAssertEqual(notice, "Review cancelled. Retry to inspect the selected records.")
            let recovered = Task { await model.retry() }; await gate.waitFor(1)
            await gate.complete(1, .success(try content(input))); await recovered.value
            XCTAssertEqual(model.content?.build, input); XCTAssertNil(model.notice)
        }
    }
}
