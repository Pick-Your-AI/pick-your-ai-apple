import Foundation
import PlannerTransfer
import XCTest
@testable import PlannerUI

private enum T6ReportTestError: Error { case synthetic }

/// Ignore cancellation deliberately so the model's acceptance guard is tested.
private actor SuspendedT6ReportPreparation {
    private var sequence = 0
    private var requests: [Int: CheckedContinuation<T6PlanReport, Error>] = [:]
    private var started: [Int: CheckedContinuation<Void, Never>] = [:]
    func prepare(_ content: T6ReviewContent) async throws -> T6PlanReport {
        let index = sequence; sequence += 1
        return try await withCheckedThrowingContinuation { continuation in
            requests[index] = continuation; started.removeValue(forKey: index)?.resume()
        }
    }
    func waitFor(_ index: Int) async {
        if requests[index] != nil { return }
        await withCheckedContinuation { started[index] = $0 }
    }
    func complete(_ index: Int, _ result: Result<T6PlanReport, Error>) {
        requests.removeValue(forKey: index)!.resume(with: result)
    }
}

@MainActor
final class T6PlanReportTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
    private func object(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixture(name)) as? [String: Any])
    }
    private func bytes(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    private func build(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> BuildSnapshot {
        var value = try object("t6-build"); mutate(&value)
        return try BuildTransfer.snapshot(fromDraftJSON: bytes(value))
    }
    private func content(build: BuildSnapshot? = nil, quality: Data? = nil,
                         manifest: Data? = nil) throws -> T6ReviewContent {
        let selected = try (build ?? self.build())
        let declaration = try (manifest ?? fixture("t6-deployment-manifest"))
        return try T6ArtifactPreparation.evaluate(build: selected, quality: quality, manifest: declaration)
    }
    private func reviewedModel(build: BuildSnapshot? = nil,
                               preparation: T6PlanReportPreparation = .live) async throws -> T6ReviewModel {
        let selected = try (build ?? self.build())
        let model = T6ReviewModel(build: selected, preparation: .live, reportPreparation: preparation)
        await model.review(qualityJSON: try fixture("t6-quality-evaluation-run"),
                           manifestJSON: try fixture("t6-deployment-manifest"))
        XCTAssertNotNil(model.content?.localArtifacts)
        return model
    }
    private func preview(_ model: T6ReviewModel) async throws -> T6PlanExportRequest {
        let task = try XCTUnwrap(model.preparePlanExport()); await task.value
        return try XCTUnwrap(model.planExport)
    }

    func testDeterministicReportPreservesAllLocksAndOriginalQualityCounts() throws {
        let input = try content(quality: fixture("t6-quality-evaluation-run"))
        let first = try T6PlanReport(content: input)
        XCTAssertEqual(first.bytes, try T6PlanReport(content: input).bytes)
        XCTAssertEqual(Data(first.text.utf8), first.bytes)
        XCTAssertTrue(first.text.hasPrefix("PROPOSED DEPLOYMENT PLAN\n"))
        XCTAssertTrue(first.text.contains("Not frozen-v1 JSON and not executable."))
        XCTAssertTrue(first.text.contains("Build ID: \"build.fixture.1\""))
        XCTAssertTrue(first.text.contains("Build revision: number \"1\""))
        for key in ["catalog_snapshot_id", "ruleset_id", "ruleset_version",
                    "dependency_graph_id", "dependency_graph_revision", "pricebook_id"] {
            XCTAssertTrue(first.text.contains("Lock \"\(key)\":"))
        }
        XCTAssertTrue(first.text.contains("Lock \"pricebook_id\": \"prices.fixture.1\""))
        XCTAssertTrue(first.text.contains("Reported quality status: \"failed\""))
        XCTAssertTrue(first.text.contains("Recorded sample size: number \"100\""))
        XCTAssertTrue(first.text.contains("Measurement rows: 1\nReported passed flags: 0\nReported false flags: 1\n"))
        XCTAssertEqual(T6PlanReportDocument(report: first).bytes, first.bytes)
        XCTAssertEqual(T6PlanReport.defaultFilename, "proposed-deployment-plan.txt")
        XCTAssertLessThanOrEqual(first.bytes.count, T6PlanReport.maximumBytes)
    }

    func testPrivateFieldsAndReferenceAddressesAreWithheldWithoutChangingInputs() throws {
        let selected = try build {
            $0["name"] = "PRIVATE__NAME"; $0["owner_ref"] = "PRIVATE__OWNER"
            $0["extensions"] = ["x_planning_notes": ["secret://private-owner-note"]]
            var rows = $0["selections"] as! [[String: Any]]
            var settings = rows[4]["settings"] as! [String: Any]
            settings["region"] = "PRIVATE__REGION"; rows[4]["settings"] = settings
            $0["selections"] = rows
        }
        var run = try object("t6-quality-evaluation-run")
        run["id"] = "private.quality"; run["evaluator_version"] = "PRIVATE__EVALUATOR"
        run["dataset_revision"] = "PRIVATE__DATASET"; run["notes"] = ["secret://private-quality-note"]
        run["artifacts"] = ["https://private.invalid/artifact?token=PRIVATE__TOKEN"]
        var manifest = try object("t6-deployment-manifest")
        manifest["id"] = "private.manifest"; manifest["notes"] = ["secret://private-manifest-note"]
        manifest["deployment_reference"] = "PRIVATE__DEPLOYMENT"
        manifest["rollback_artifact_uri"] = "https://private.invalid/rollback?token=PRIVATE__TOKEN"
        for key in ["compatibility_report_id", "quality_run_id", "cost_estimate_id", "resource_estimate_id"] {
            manifest[key] = "private.\(key)"
        }
        manifest["approvals"] = [["approver_ref": "secret://PRIVATE__APPROVER", "scope": "owner",
                                   "decision": "approved", "approved_at": "2026-10-16T09:00:00Z"]]
        let input = try content(build: selected, quality: bytes(run), manifest: bytes(manifest))
        let privatePair = try XCTUnwrap(input.localArtifacts)
        let originalBuild = try selected.encoded(); let originalManifest = try input.manifest!.encoded()
        let report = try T6PlanReport(content: input)
        for privateValue in ["PRIVATE__", "private.", "secret://", "https://", "2026-10-16T09:00:00Z"] {
            XCTAssertFalse(report.text.contains(privateValue), privateValue)
        }
        XCTAssertTrue(report.text.contains("rollback_artifact_uri: supplied; private address withheld"))
        XCTAssertTrue(report.text.contains("decision: \"approved\""))
        XCTAssertTrue(report.text.contains("No approval authority is inferred."))
        XCTAssertEqual(try selected.encoded(), originalBuild)
        XCTAssertEqual(try input.manifest!.encoded(), originalManifest)
        XCTAssertEqual(input.localArtifacts, privatePair)
        XCTAssertNotEqual(report.bytes, privatePair.buildJSON); XCTAssertNotEqual(report.bytes, privatePair.manifestJSON)
    }

    func testApprovalOrderDuplicatesAndDecisionsRemainReported() throws {
        var manifest = try object("t6-deployment-manifest")
        let rows: [[String: Any]] = [
            ["approver_ref": "\u{00e9}", "scope": "security", "decision": "pending"],
            ["approver_ref": "e\u{0301}", "scope": "finance", "decision": "rejected"],
            ["approver_ref": "\u{00e9}", "scope": "compliance", "decision": "approved", "approved_at": "2026-10-16T09:00:00Z"],
            ["approver_ref": "\u{00e9}", "scope": "security", "decision": "pending"],
        ]
        manifest["approvals"] = rows
        let input = try content(manifest: bytes(manifest))
        let report = try T6PlanReport(content: input)
        let expected = "Approval row 1\n  scope: \"security\"\n  decision: \"pending\"\n" +
            "Approval row 2\n  scope: \"finance\"\n  decision: \"rejected\"\n" +
            "Approval row 3\n  scope: \"compliance\"\n  decision: \"approved\"\n" +
            "Approval row 4\n  scope: \"security\"\n  decision: \"pending\"\n"
        XCTAssertTrue(report.text.contains(expected))
        XCTAssertEqual(input.manifest!.approvals.count, rows.count)
        XCTAssertFalse(report.text.contains("approver_ref"))
        XCTAssertFalse(report.text.contains("2026-10-16T09:00:00Z"))
    }

    func testQuotedUTF8PreservesSpellingAndCannotInjectLinesOrHiddenHeadings() throws {
        func report(_ version: String) throws -> T6PlanReport {
            let selected = try build {
                var rows = $0["selections"] as! [[String: Any]]
                rows[5]["catalog_item_version"] = version; $0["selections"] = rows
            }
            return try T6PlanReport(content: content(build: selected))
        }
        let composed = try report("\u{00e9}")
        let decomposed = try report("e\u{0301}")
        XCTAssertNotEqual(composed.bytes, decomposed.bytes)
        XCTAssertNotNil(composed.bytes.range(of: Data("\"\u{00e9}\"".utf8)))
        XCTAssertNotNil(decomposed.bytes.range(of: Data("\"e\u{0301}\"".utf8)))
        let injection = try report("v\"\\\nFORGED\r\t\u{2028}\u{2029}\u{202e}\u{0001}")
        XCTAssertTrue(injection.text.contains(#""v\"\\\nFORGED\r\t\u2028\u2029\u202e\u0001""#))
        XCTAssertFalse(injection.text.contains("\nFORGED"))
        for scalar in ["\u{2028}", "\u{2029}", "\u{202e}", "\u{0001}"] {
            XCTAssertFalse(injection.text.contains(scalar))
        }
    }

    func testRetainedSecretMarkersFailClosedAndAValidRetryRecovers() throws {
        for marker in ["secret://hidden", "SeCrEt://hidden"] {
            let selected = try build {
                var rows = $0["selections"] as! [[String: Any]]
                rows[5]["catalog_item_version"] = marker; $0["selections"] = rows
            }
            XCTAssertThrowsError(try T6PlanReport(content: content(build: selected))) {
                XCTAssertEqual($0 as? T6PlanReportError, .unsafeValue)
            }
        }
        XCTAssertFalse(try T6PlanReport(content: content()).bytes.isEmpty)
    }

    func testOutputLimitAppliesAfterEscapingWithoutChangingAValidInput() throws {
        var json = try XCTUnwrap(String(data: fixture("t6-build"), encoding: .utf8))
        let range = try XCTUnwrap(json.range(of: "2026.10-demo", options: .backwards))
        // This valid JSON scalar occupies three input bytes but six report bytes.
        json.replaceSubrange(range, with: String(repeating: "\u{202e}", count: 90_000))
        let original = Data(json.utf8)
        XCTAssertLessThan(original.count, BuildTransfer.maximumBytes)
        let selected = try BuildTransfer.snapshot(fromDraftJSON: original)
        let input = try content(build: selected)
        let privatePair = input.localArtifacts
        XCTAssertThrowsError(try T6PlanReport(content: input)) {
            XCTAssertEqual($0 as? T6PlanReportError, .oversized)
        }
        XCTAssertEqual(input.localArtifacts, privatePair)
        XCTAssertEqual(Data(json.utf8), original)
        XCTAssertLessThan(try T6PlanReport(content: content()).bytes.count, T6PlanReport.maximumBytes)
    }

    func testOnlyProposedExactlyBoundContentCanCreateAReport() throws {
        for status in ["approved", "rejected", "deployed", "rolled_back"] {
            var manifest = try object("t6-deployment-manifest"); manifest["status"] = status
            let input = try content(manifest: bytes(manifest))
            XCTAssertEqual(input.manifest?.status, status)
            XCTAssertThrowsError(try T6PlanReport(content: input))
        }
        for key in ["build_id", "build_revision", "deployment_target_selection_id"] {
            var manifest = try object("t6-deployment-manifest")
            if key == "build_revision" { manifest[key] = 2 }
            else if key == "deployment_target_selection_id" { manifest[key] = "sel_foreign" }
            else { manifest[key] = "build.foreign" }
            let input = try content(manifest: bytes(manifest))
            XCTAssertNotNil(input.manifest)
            XCTAssertEqual(input.manifestIssue, key == "deployment_target_selection_id" ? .targetBinding : .buildMismatch)
            XCTAssertThrowsError(try T6PlanReport(content: input))
        }
        let selected = try build()
        let absent = try T6ArtifactPreparation.evaluate(build: selected, quality: nil, manifest: nil)
        XCTAssertThrowsError(try T6PlanReport(content: absent))
        let input = try content()
        let foreign = try build { $0["name"] = "Changed same-ID snapshot" }
        let mismatched = T6ReviewContent(build: selected, guidance: try T6QualityGuidance(build: foreign),
            manifest: input.manifest, manifestIssue: nil, localArtifacts: input.localArtifacts)
        XCTAssertThrowsError(try T6PlanReport(content: mismatched)) {
            XCTAssertEqual($0 as? T6PlanReportError, .mismatchedContent)
        }
    }

    func testOptionalLocksOmittedTiersDisabledMonitoringAndRollbackStayExplicit() throws {
        let selected = try build {
            var locks = $0["locks"] as! [String: Any]; locks.removeValue(forKey: "pricebook_id"); $0["locks"] = locks
            var rows = $0["selections"] as! [[String: Any]]
            rows[5]["enabled"] = false; $0["selections"] = rows
        }
        let report = try T6PlanReport(content: content(build: selected))
        XCTAssertTrue(report.text.contains("Lock \"pricebook_id\": not supplied"))
        XCTAssertTrue(report.text.contains("Reported quality: not supplied; quality remains unknown."))
        XCTAssertTrue(report.text.contains("id: \"sel_monitoring_stack\""))
        XCTAssertTrue(report.text.contains("enabled: false"))
        XCTAssertTrue(report.text.contains("rollback_artifact_uri: not supplied"))
        let noMonitoring = try build {
            $0["selections"] = ($0["selections"] as! [[String: Any]]).filter { $0["kind"] as? String != "monitoring_stack" }
        }
        XCTAssertTrue(try T6PlanReport(content: content(build: noMonitoring)).text.contains("No monitoring selection was supplied."))
    }

    func testFilesSaveRequiresExactReviewedPreviewAndIsSingleUse() async throws {
        let model = try await reviewedModel()
        let retained = model.content
        let request = try await preview(model)
        XCTAssertFalse(model.beginPlanExport(request, disclosureReviewed: false))
        model.finishPlanExport(.saved, for: request)
        XCTAssertNil(model.notice); XCTAssertEqual(model.planExport, request)
        XCTAssertTrue(model.beginPlanExport(request, disclosureReviewed: true))
        XCTAssertFalse(model.beginPlanExport(request, disclosureReviewed: true))
        model.finishPlanExport(.saved, for: request)
        let savedNotice = model.notice
        XCTAssertTrue(savedNotice?.contains("Files reported") == true)
        XCTAssertNil(model.planExport); XCTAssertEqual(model.content, retained)
        for outcome in [T6PlanExportOutcome.failed, .cancelled, .saved] {
            model.finishPlanExport(outcome, for: request)
            XCTAssertEqual(model.notice, savedNotice)
        }
        let foreign = try await reviewedModel(); let other = try await preview(foreign)
        XCTAssertFalse(model.beginPlanExport(other, disclosureReviewed: true))
    }

    func testCurrentFailureCancellationAndPreviewDismissalRecoverWithoutPrivateMutation() async throws {
        let model = try await reviewedModel(); let retained = model.content
        for outcome in [T6PlanExportOutcome.failed, .cancelled] {
            let request = try await preview(model)
            XCTAssertTrue(model.beginPlanExport(request, disclosureReviewed: true))
            model.finishPlanExport(outcome, for: request)
            XCTAssertNil(model.planExport); XCTAssertEqual(model.content, retained)
            XCTAssertFalse(model.notice?.contains("was saved") == true)
            let notice = model.notice
            model.finishPlanExport(.saved, for: request)
            XCTAssertEqual(model.notice, notice)
        }
        let dismissed = try await preview(model); model.dismissPlanExport(dismissed)
        XCTAssertFalse(model.beginPlanExport(dismissed, disclosureReviewed: true))
        let fresh = try await preview(model)
        XCTAssertTrue(model.beginPlanExport(fresh, disclosureReviewed: true))
        model.finishPlanExport(.saved, for: fresh)
        XCTAssertEqual(model.content, retained)
    }

    func testRetiredFilesCallbacksCannotBorrowNewContentOrRestoredSameBuild() async throws {
        let selected = try build()
        let changed = try build { $0["extensions"] = ["x_planning_notes": ["Same ID, changed private context"]] }
        for transition in ["retry", "selection", "clear", "picker", "preview", "cancel"] {
            let model = try await reviewedModel()
            let obsolete = try await preview(model)
            XCTAssertTrue(model.beginPlanExport(obsolete, disclosureReviewed: true))
            switch transition {
            case "selection": model.select(changed); model.select(selected)
            case "clear": model.clear(); model.select(selected)
            case "picker": _ = model.beginFileSelection(.quality)
            case "preview": _ = try await preview(model)
            case "cancel": model.cancel()
            default: await model.retry()
            }
            let content = model.content; let notice = model.notice; let request = model.planExport
            for outcome in [T6PlanExportOutcome.saved, .failed, .cancelled] {
                model.finishPlanExport(outcome, for: obsolete)
                XCTAssertEqual(model.content, content, transition)
                XCTAssertEqual(model.notice, notice, transition)
                XCTAssertEqual(model.planExport, request, transition)
            }
            XCTAssertFalse(model.beginPlanExport(obsolete, disclosureReviewed: true), transition)
            await model.review(qualityJSON: try fixture("t6-quality-evaluation-run"),
                               manifestJSON: try fixture("t6-deployment-manifest"))
            let fresh = try await preview(model)
            XCTAssertTrue(model.beginPlanExport(fresh, disclosureReviewed: true), transition)
        }
    }

    func testLateReportPreparationSuccessAndFailureCannotReplaceFreshPreview() async throws {
        for oldFailure in [false, true] {
            let suspended = SuspendedT6ReportPreparation()
            let model = try await reviewedModel(preparation: .init(prepare: { try await suspended.prepare($0) }))
            let captured = try XCTUnwrap(model.content)
            let expected = try T6PlanReport(content: captured)
            let old = try XCTUnwrap(model.preparePlanExport()); await suspended.waitFor(0)
            model.cancelPlanExportPreparation()
            XCTAssertFalse(model.exportPreparing); XCTAssertNil(model.planExport)
            let fresh = try XCTUnwrap(model.preparePlanExport()); await suspended.waitFor(1)
            await suspended.complete(1, .success(expected)); await fresh.value
            let accepted = try XCTUnwrap(model.planExport); let notice = model.notice
            await suspended.complete(0, oldFailure ? .failure(T6ReportTestError.synthetic) : .success(expected))
            await old.value
            XCTAssertEqual(model.planExport, accepted); XCTAssertEqual(model.notice, notice)
            XCTAssertFalse(model.exportPreparing); XCTAssertEqual(model.content, captured)
        }
    }

    func testReportPreparationErrorsLeavePrivatePairAndAllowFreshRetry() async throws {
        let selected = try build {
            var rows = $0["selections"] as! [[String: Any]]
            rows[5]["catalog_item_version"] = "secret://private-report-marker"; $0["selections"] = rows
        }
        let model = try await reviewedModel(build: selected)
        let retained = model.content
        let task = try XCTUnwrap(model.preparePlanExport()); await task.value
        XCTAssertNil(model.planExport); XCTAssertFalse(model.exportPreparing)
        XCTAssertEqual(model.content, retained)
        XCTAssertNotNil(model.notice); XCTAssertFalse(model.notice!.contains("private-report-marker"))
        model.select(try build())
        await model.review(manifestJSON: try fixture("t6-deployment-manifest"))
        let recovered = try await preview(model)
        XCTAssertFalse(recovered.report.bytes.isEmpty)
    }

    func testOwnedExporterDisappearancePreservesItsExactTerminalCallback() async throws {
        for outcome in [T6PlanExportOutcome.saved, .failed, .cancelled] {
            let model = try await reviewedModel(); let retained = model.content
            let request = try await preview(model)
            XCTAssertTrue(model.beginPlanExport(request, disclosureReviewed: true))
            XCTAssertFalse(model.handleDisappearance())
            XCTAssertFalse(model.handleDisappearance())
            XCTAssertEqual(model.planExport, request); XCTAssertEqual(model.content, retained)
            XCTAssertNil(model.notice)
            model.finishPlanExport(outcome, for: request)
            XCTAssertNil(model.planExport); XCTAssertEqual(model.content, retained)
            switch outcome {
            case .saved:
                XCTAssertEqual(model.notice, "Files reported that the proposed-plan report was saved. No approval or deployment was performed.")
            case .failed:
                XCTAssertEqual(model.notice, "Files did not confirm a saved report. The retained declarations were not changed; prepare a fresh preview to retry.")
            case .cancelled:
                XCTAssertEqual(model.notice, "Plan report export was cancelled. No save was confirmed; the retained declarations were not changed.")
            }
            let notice = model.notice
            for late in [T6PlanExportOutcome.saved, .failed, .cancelled] {
                model.finishPlanExport(late, for: request)
                XCTAssertEqual(model.notice, notice); XCTAssertEqual(model.content, retained)
            }
            XCTAssertFalse(model.beginPlanExport(request, disclosureReviewed: true))
        }
    }

    func testExplicitRouteCancellationRetiresAnOwnedExporterAfterDisappearance() async throws {
        for closesRecord in [false, true] {
            let model = try await reviewedModel(); let input = model.build
            let request = try await preview(model)
            XCTAssertTrue(model.beginPlanExport(request, disclosureReviewed: true))
            XCTAssertFalse(model.handleDisappearance())
            if closesRecord { model.clear() } else { model.cancel() }
            let notice = model.notice
            for late in [T6PlanExportOutcome.saved, .failed, .cancelled] {
                model.finishPlanExport(late, for: request)
                XCTAssertEqual(model.notice, notice); XCTAssertNil(model.content)
                XCTAssertNil(model.planExport)
            }
            XCTAssertFalse(model.beginPlanExport(request, disclosureReviewed: true))
            if closesRecord { XCTAssertNil(model.build) }
            else { XCTAssertEqual(model.build, input) }
        }
    }

    func testOrdinaryDisappearanceCancelsReportPreparationAndUnsubmittedPreview() async throws {
        for oldFailure in [false, true] {
            let suspended = SuspendedT6ReportPreparation()
            let model = try await reviewedModel(preparation: .init(prepare: { try await suspended.prepare($0) }))
            let input = model.build; let captured = try XCTUnwrap(model.content)
            let expected = try T6PlanReport(content: captured)
            let pending = try XCTUnwrap(model.preparePlanExport()); await suspended.waitFor(0)
            XCTAssertTrue(model.exportPreparing)
            XCTAssertTrue(model.handleDisappearance())
            let notice = model.notice
            await suspended.complete(0, oldFailure ? .failure(T6ReportTestError.synthetic) : .success(expected))
            await pending.value
            XCTAssertNil(model.planExport); XCTAssertNil(model.content); XCTAssertFalse(model.exportPreparing)
            XCTAssertEqual(model.build, input); XCTAssertEqual(model.notice, notice)
            XCTAssertEqual(notice, "Review cancelled. Retry to inspect the selected records.")
            await model.review(qualityJSON: try fixture("t6-quality-evaluation-run"),
                               manifestJSON: try fixture("t6-deployment-manifest"))
            XCTAssertEqual(model.content, captured)
            let recovered = try XCTUnwrap(model.preparePlanExport()); await suspended.waitFor(1)
            await suspended.complete(1, .success(expected)); await recovered.value
            let preview = try XCTUnwrap(model.planExport)
            XCTAssertTrue(model.handleDisappearance())
            XCTAssertNil(model.planExport); XCTAssertNil(model.content)
            XCTAssertFalse(model.beginPlanExport(preview, disclosureReviewed: true))
            model.finishPlanExport(.saved, for: preview)
            XCTAssertEqual(model.notice, notice); XCTAssertEqual(model.build, input)
        }
    }
}
