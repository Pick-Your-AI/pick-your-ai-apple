import Foundation
import XCTest
import PlannerCore
@testable import PlannerTransfer

// All mutable inputs and actors are method-local, including the async cases.
final class T6QualityGuidanceTests: XCTestCase, @unchecked Sendable {
    private func fixture(_ name: String) throws -> [String: JSONValue] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        return try XCTUnwrap(parser.parse().object)
    }
    private func build(_ fields: [String: JSONValue]) throws -> BuildSnapshot {
        try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(fields)))
    }
    private func run(_ fields: [String: JSONValue]) throws -> QualityEvaluationRun {
        try QualityEvaluationRun.decode(JSONEncoder().encode(JSONValue.object(fields)))
    }
    private func selection(_ fields: [String: JSONValue], id: String,
                           change: (inout [String: JSONValue]) -> Void) -> [String: JSONValue] {
        var result = fields
        result["selections"] = .array(fields["selections"]!.array!.map { original in
            var row = original.object!
            if row["id"] == .string(id) { change(&row) }
            return .object(row)
        })
        return result
    }
    private func retained(_ guidance: T6QualityGuidance) throws -> HistoricalQualityScenario {
        guard case .supplied(let scenario) = guidance.record else {
            XCTFail("Expected the supplied record"); throw TransferError.malformed
        }
        return scenario
    }
    /// A synthetic governed-shape report decoded by the real Core boundary.
    /// It names both a T1 and T2 selection; it executes no compatibility rules.
    private func report(for snapshot: BuildSnapshot, valid: Bool = true) throws -> EvaluationReport {
        let fields = snapshot.value.object!, locks = fields["locks"]!.object!
        let finding: JSONValue = .object([
            "rule_id": .string("rule.synthetic.compatibility"),
            "outcome": .string(valid ? "pass" : "fail"), "severity": .string("error"),
            "code": .string("SYNTHETIC_COMPATIBILITY"),
            "message": .string("Synthetic recorded T1/T2 outcome; no evaluator executed."),
            "selection_ids": .array([.string("sel_model"), .string("sel_accelerator")]),
        ])
        let wire: JSONValue = .object([
            "schema_version": .string("1.0.0"), "id": .string("report.synthetic.quality-guidance"),
            "build_id": fields["id"]!, "build_revision": fields["revision"]!,
            "catalog_snapshot_id": locks["catalog_snapshot_id"]!,
            "ruleset_id": locks["ruleset_id"]!, "ruleset_version": locks["ruleset_version"]!,
            "dependency_graph_id": locks["dependency_graph_id"]!,
            "dependency_graph_revision": locks["dependency_graph_revision"]!,
            "evaluated_at": .string("2026-10-16T09:00:00Z"),
            "result": .string(valid ? "valid" : "invalid"),
            "deployment_readiness": .string(valid ? "ready" : "blocked"),
            "findings": .array([finding]),
            "summary": .object(["passed": .number(valid ? 1 : 0), "failed": .number(valid ? 0 : 1),
                                "unknown": .number(0), "skipped": .number(0)]),
        ])
        return try EvaluationReport.decode(JSONEncoder().encode(wire))
    }

    func testAdmittedCompatibilityPassDoesNotSupplyQualityOrApproval() async throws {
        let snapshot = try build(fixture("build")), compatibility = try report(for: snapshot)
        let store = AnalysisStore<EvaluationReport>()
        let request = await store.begin(for: compatibility.analysisIdentity)
        let admitted = await store.receive(compatibility, for: request)
        let state = await store.state
        XCTAssertTrue(admitted)
        XCTAssertEqual(state, .current(request: request, value: compatibility))
        XCTAssertEqual(compatibility.result, .valid)
        XCTAssertEqual(compatibility.deploymentReadiness, .ready)
        let guidance = try T6QualityGuidance(build: snapshot)
        XCTAssertEqual(guidance.record, .notSupplied)
        XCTAssertNil(guidance.reportedFailedMeasurements)
        XCTAssertEqual(guidance.cautions, [.reportedValuesOnly, .approvalNotEstablished, .qualityRecordNotSupplied])
        XCTAssertEqual(guidance.nextSteps, [.supplyQualityRecord, .reviewEvidenceAndApprovals])
        XCTAssertEqual(guidance.build, snapshot)
    }

    func testCompatibilityPassKeepsFailedThresholdAndMissingArtifactsVisible() async throws {
        let snapshot = try build(fixture("build")), compatibility = try report(for: snapshot)
        let store = AnalysisStore<EvaluationReport>()
        let request = await store.begin(for: compatibility.analysisIdentity)
        let admitted = await store.receive(compatibility, for: request)
        XCTAssertTrue(admitted)
        var fields = try fixture("quality-evaluation-run")
        var measurement = fields["measurements"]!.array![0].object!
        measurement["observed"] = .number(0.2); measurement["passed"] = .bool(false)
        fields["measurements"] = .array([.object(measurement)]); fields["status"] = .string("failed")
        let original = try run(fields), guidance = try T6QualityGuidance(build: snapshot, run: original)
        XCTAssertEqual(try retained(guidance).run, original)
        XCTAssertEqual(guidance.reportedFailedMeasurements, original.measurements)
        XCTAssertEqual(guidance.cautions, [.reportedValuesOnly, .approvalNotEstablished, .reportedRunFailed,
                                            .reportedMeasurementsFailed, .artifactReferencesNotSupplied])
        XCTAssertEqual(guidance.nextSteps, [.reviewRecordedFailures, .reviewEvidenceAndApprovals])
        XCTAssertEqual(try retained(guidance).run.measurements[0].threshold, Decimal(string: "0.85"))
        let state = await store.state
        XCTAssertEqual(state, .current(request: request, value: compatibility))
    }

    func testIncompleteRunAndKnownFailureRetainBothReasons() throws {
        var fields = try fixture("quality-evaluation-run")
        var row = fields["measurements"]!.array![0].object!
        row["passed"] = .bool(false); fields["measurements"] = .array([.object(row)])
        fields["status"] = .string("incomplete")
        let original = try run(fields)
        let guidance = try T6QualityGuidance(build: build(fixture("build")), run: original)
        XCTAssertEqual(guidance.cautions, [.reportedValuesOnly, .approvalNotEstablished, .reportedRunIncomplete,
                                            .reportedMeasurementsFailed, .artifactReferencesNotSupplied])
        XCTAssertEqual(guidance.nextSteps, [.reviewRecordedFailures, .completeEvaluationRecord, .reviewEvidenceAndApprovals])
        XCTAssertEqual(guidance.reportedFailedMeasurements, original.measurements)
        XCTAssertEqual(try retained(guidance).run.value, .object(fields))
    }

    func testReportedContradictionsAreNotRecalculatedOrPromoted() throws {
        let snapshot = try build(fixture("build"))
        var fields = try fixture("quality-evaluation-run")
        var row = fields["measurements"]!.array![0].object!
        row["observed"] = .number(-9); row["threshold"] = .number(99)
        row["comparator"] = .string("eq"); row["passed"] = .bool(true)
        fields["measurements"] = .array([.object(row)])
        let reportedPass = try T6QualityGuidance(build: snapshot, run: run(fields))
        XCTAssertEqual(try retained(reportedPass).run.value, .object(fields))
        XCTAssertEqual(reportedPass.reportedFailedMeasurements, [])
        XCTAssertFalse(reportedPass.cautions.contains(.reportedMeasurementsFailed))
        XCTAssertEqual(reportedPass.nextSteps, [.reviewEvidenceAndApprovals])
        XCTAssertTrue(reportedPass.cautions.contains(.approvalNotEstablished))
        fields["status"] = .string("failed")
        let failedStatus = try T6QualityGuidance(build: snapshot, run: run(fields))
        XCTAssertTrue(failedStatus.cautions.contains(.reportedRunFailed))
        XCTAssertEqual(failedStatus.reportedFailedMeasurements, [])
        XCTAssertEqual(failedStatus.nextSteps, [.reviewRecordedFailures, .reviewEvidenceAndApprovals])
        fields["status"] = .string("passed"); row["passed"] = .bool(false)
        fields["measurements"] = .array([.object(row)])
        let failedRow = try T6QualityGuidance(build: snapshot, run: run(fields))
        XCTAssertEqual(try retained(failedRow).run.status, .passed)
        XCTAssertTrue(failedRow.cautions.contains(.reportedMeasurementsFailed))
        XCTAssertEqual(failedRow.nextSteps, [.reviewRecordedFailures, .reviewEvidenceAndApprovals])
    }

    func testDisabledSelectionAndAbsentFalseZeroSettingsRemainDistinct() throws {
        let original = try fixture("build"), quality = try run(fixture("quality-evaluation-run"))
        for supplied in [false, true] {
            let fields = selection(original, id: "sel_evaluation_suite") {
                $0["enabled"] = .bool(false)
                $0["settings"] = supplied ? .object(["gate_required": .bool(false), "minimum_score": .number(0)]) : .object([:])
            }
            let guidance = try T6QualityGuidance(build: build(fields), run: quality)
            let suite = try XCTUnwrap(guidance.evaluationSuites.first)
            XCTAssertFalse(suite.enabled)
            XCTAssertEqual(suite.settings.object?["gate_required"], supplied ? .bool(false) : nil)
            XCTAssertEqual(suite.settings.object?["minimum_score"], supplied ? .number(0) : nil)
            XCTAssertTrue(guidance.cautions.contains(.noEnabledEvaluationSuite))
            XCTAssertTrue(guidance.cautions.contains(.evaluationSuiteDisabled))
            XCTAssertEqual(guidance.nextSteps, [.reviewDisabledEvaluationSuites, .reviewEvidenceAndApprovals])
            XCTAssertEqual(try retained(guidance).evaluationSuite, suite.value)
            let missing = try T6QualityGuidance(build: build(fields))
            XCTAssertEqual(missing.nextSteps, [.reviewDisabledEvaluationSuites, .reviewEvidenceAndApprovals])
            XCTAssertTrue(missing.cautions.contains(.qualityRecordNotSupplied))
        }
    }

    func testOptionalTiersCanBeOmittedWithoutHidingT6Guidance() throws {
        let original = try fixture("build"), quality = try run(fixture("quality-evaluation-run"))
        let optionalKinds: Set<String> = ["data_source", "knowledge_base", "embedding_model", "vector_database", "rag_pipeline",
            "agent_framework", "tool", "mcp_server", "memory_store", "integration", "training_framework", "training_compute",
            "training_dataset", "fine_tuned_model"]
        var omitted = original
        let remaining = original["selections"]!.array!.filter { !optionalKinds.contains($0.object!["kind"]!.string!) }
        let ids = Set(remaining.map { $0.object!["id"]!.string! })
        omitted["selections"] = .array(remaining)
        omitted["links"] = .array(original["links"]!.array!.filter {
            ids.contains($0.object!["from_selection_id"]!.string!) && ids.contains($0.object!["to_selection_id"]!.string!)
        })
        let selected = try T6QualityGuidance(build: build(original), run: quality)
        let coreOnly = try T6QualityGuidance(build: build(omitted), run: quality)
        XCTAssertEqual(coreOnly.selections.map(\.value), selected.selections.map(\.value))
        XCTAssertEqual(coreOnly.cautions, selected.cautions)
        XCTAssertEqual(coreOnly.nextSteps, selected.nextSteps)
        XCTAssertEqual(try retained(coreOnly).build.value, .object(omitted))
        XCTAssertEqual(try retained(selected).build.value, .object(original))
    }

    func testAbsentT6SelectionsPromptReviewWithoutInventingRequirements() throws {
        var fields = try fixture("build")
        fields["selections"] = .array(Array(fields["selections"]!.array!.prefix(2)))
        fields["links"] = .array([])
        let guidance = try T6QualityGuidance(build: build(fields))
        XCTAssertTrue(guidance.selections.isEmpty)
        XCTAssertEqual(guidance.record, .notSupplied)
        XCTAssertEqual(guidance.cautions, [.reportedValuesOnly, .approvalNotEstablished, .noGuardrailSelection,
                                            .noEvaluationSuiteSelection, .qualityRecordNotSupplied])
        XCTAssertEqual(guidance.nextSteps, [.reviewGuardrailRequirements, .selectEvaluationSuite, .reviewEvidenceAndApprovals])
        XCTAssertNil(guidance.reportedFailedMeasurements)
        XCTAssertEqual(guidance.build.value, .object(fields))
    }

    func testExistingAdmissionRejectsForeignBindingsAndRecoversWithoutMutation() throws {
        let snapshot = try build(fixture("build")), original = try fixture("quality-evaluation-run")
        let invalid: [(String, JSONValue, HistoricalQualityComparisonError)] = [
            ("build_id", .string("build.synthetic.foreign"), .buildMismatch),
            ("build_revision", .number(2), .buildMismatch),
            ("evaluation_suite_selection_id", .string("sel_missing"), .unknownEvaluationSuite),
            ("evaluation_suite_selection_id", .string("sel_model"), .invalidEvaluationSuiteKind),
        ]
        for (key, value, expected) in invalid {
            var fields = original; fields[key] = value
            let rejected = try run(fields)
            XCTAssertThrowsError(try T6QualityGuidance(build: snapshot, run: rejected)) {
                XCTAssertEqual($0 as? HistoricalQualityComparisonError, expected)
            }
            XCTAssertEqual(rejected.value, .object(fields))
            let recovered = try T6QualityGuidance(build: snapshot, run: run(original))
            XCTAssertEqual(try retained(recovered).run.value, .object(original))
            XCTAssertEqual(recovered.build, snapshot)
        }
    }

    func testDuplicateSelectionsRemainVisibleWithoutARecordAndAdmissionStillRejectsThem() throws {
        var fields = try fixture("build")
        var rows = fields["selections"]!.array!
        let duplicate = try XCTUnwrap(rows.first { $0.object!["id"] == .string("sel_evaluation_suite") })
        rows.append(duplicate); fields["selections"] = .array(rows)
        let snapshot = try build(fields), quality = try run(fixture("quality-evaluation-run"))
        let guidance = try T6QualityGuidance(build: snapshot)
        XCTAssertEqual(guidance.evaluationSuites.map(\.value), [duplicate, duplicate])
        XCTAssertNotEqual(guidance.evaluationSuites[0].position, guidance.evaluationSuites[1].position)
        XCTAssertThrowsError(try T6QualityGuidance(build: snapshot, run: quality)) {
            XCTAssertEqual($0 as? HistoricalQualityComparisonError, .ambiguousSelectionIdentity)
        }
        var duplicateMetrics = try fixture("quality-evaluation-run")
        duplicateMetrics["measurements"] = .array(Array(repeating: duplicateMetrics["measurements"]!.array![0], count: 2))
        XCTAssertThrowsError(try T6QualityGuidance(build: build(fixture("build")), run: run(duplicateMetrics))) {
            XCTAssertEqual($0 as? HistoricalQualityComparisonError, .ambiguousMetricIdentity)
        }
        XCTAssertEqual(guidance.build.value, .object(fields))
    }

    func testIncompatibleCrossTierReportAndQualityRecordKeepSeparateOutcomes() async throws {
        let snapshot = try build(fixture("build")), compatibility = try report(for: snapshot, valid: false)
        let store = AnalysisStore<EvaluationReport>()
        let request = await store.begin(for: compatibility.analysisIdentity)
        let admitted = await store.receive(compatibility, for: request)
        XCTAssertTrue(admitted)
        let guidance = try T6QualityGuidance(build: snapshot, run: run(fixture("quality-evaluation-run")))
        XCTAssertEqual(compatibility.result, .invalid)
        XCTAssertEqual(compatibility.findings[0].outcome, .fail)
        XCTAssertEqual(compatibility.findings[0].selectionIDs, ["sel_model", "sel_accelerator"])
        XCTAssertEqual(try retained(guidance).run.status, .passed)
        XCTAssertEqual(guidance.nextSteps, [.reviewEvidenceAndApprovals])
        XCTAssertTrue(guidance.cautions.contains(.approvalNotEstablished))
        let state = await store.state
        XCTAssertEqual(state, .current(request: request, value: compatibility))
    }

    func testChangedRevisionRejectsOldQualityAndLateCompatibilityThenRecovers() async throws {
        let originalBuild = try fixture("build"), originalRun = try run(fixture("quality-evaluation-run"))
        let snapshot = try build(originalBuild), oldReport = try report(for: snapshot)
        let historical = try T6QualityGuidance(build: snapshot, run: originalRun)
        var nextFields = originalBuild; nextFields["revision"] = .number(2)
        let next = try build(nextFields), nextReport = try report(for: next)
        let store = AnalysisStore<EvaluationReport>()
        let oldRequest = await store.begin(for: oldReport.analysisIdentity)
        let nextRequest = await store.begin(for: nextReport.analysisIdentity)
        let acceptedOld = await store.receive(oldReport, for: oldRequest)
        XCTAssertFalse(acceptedOld)
        XCTAssertThrowsError(try T6QualityGuidance(build: next, run: originalRun)) {
            XCTAssertEqual($0 as? HistoricalQualityComparisonError, .buildMismatch)
        }
        XCTAssertEqual(try T6QualityGuidance(build: next).record, .notSupplied)
        var newRun = try fixture("quality-evaluation-run")
        newRun["id"] = .string("quality.synthetic.revision2"); newRun["build_revision"] = .number(2)
        let recovered = try T6QualityGuidance(build: next, run: run(newRun))
        let acceptedNext = await store.receive(nextReport, for: nextRequest)
        XCTAssertTrue(acceptedNext)
        let state = await store.state
        XCTAssertEqual(state, .current(request: nextRequest, value: nextReport))
        XCTAssertEqual(try retained(recovered).run.buildRevision, 2)
        XCTAssertEqual(try retained(historical).run, originalRun)
        XCTAssertEqual(historical.build, snapshot)
    }

    func testOriginalOrderPinsRolesAndGuardrailSettingsArePreserved() throws {
        var fields = try fixture("build")
        fields = selection(fields, id: "sel_guardrail") {
            $0["role"] = .string("fallback"); $0["enabled"] = .bool(false)
            $0["catalog_item_version"] = .string("reviewed-e\u{0301}")
            $0["settings"] = .object(["enforcement": .string("audit"), "failure_action": .string("fail_open")])
        }
        fields["selections"] = .array(Array(fields["selections"]!.array!.reversed()))
        let guidance = try T6QualityGuidance(build: build(fields))
        let expected = fields["selections"]!.array!.enumerated().filter {
            ["guardrail", "evaluation_suite"].contains($0.element.object!["kind"]!.string!)
        }
        XCTAssertEqual(guidance.selections.map(\.position), expected.map { $0.offset })
        XCTAssertEqual(guidance.selections.map(\.value), expected.map { $0.element })
        let guardrail = try XCTUnwrap(guidance.guardrails.first)
        XCTAssertFalse(guardrail.enabled)
        XCTAssertEqual(guardrail.value.object?["role"], .string("fallback"))
        XCTAssertEqual(guardrail.settings.object?["failure_action"], .string("fail_open"))
        XCTAssertEqual(Data(guardrail.value.object!["catalog_item_version"]!.string!.utf8), Data("reviewed-e\u{0301}".utf8))
        XCTAssertEqual(guidance.build.value, .object(fields))
    }

    func testExactDecimalsUnicodeAndPrivateReferencesRemainOriginalLocalValues() throws {
        var buildFields = try fixture("build"), runFields = try fixture("quality-evaluation-run")
        let revision = try XCTUnwrap(Decimal(string: "9000000000000000", locale: Locale(identifier: "en_US_POSIX")))
        let observed = try XCTUnwrap(Decimal(string: "-123456789.012345", locale: Locale(identifier: "en_US_POSIX")))
        let threshold = try XCTUnwrap(Decimal(string: "0.00000000000123456789", locale: Locale(identifier: "en_US_POSIX")))
        buildFields["revision"] = .number(revision); runFields["build_revision"] = .number(revision)
        runFields["sample_size"] = .number(revision)
        let names = ["e\u{0301}", "\u{00E9}"]
        let template = runFields["measurements"]!.array![0].object!
        runFields["measurements"] = .array(names.enumerated().map { index, name in
            var row = template; row["metric"] = .string(name)
            row["observed"] = .number(observed); row["threshold"] = .number(threshold)
            row["passed"] = .bool(false)
            if index == 0 { row.removeValue(forKey: "unit") } else { row["unit"] = .string("") }
            return .object(row)
        })
        runFields["artifacts"] = .array([.string("file:///tmp/private-quality.json"), .string("urn:private:quality")])
        runFields["notes"] = .array([.string("PRIVATE-LOCAL-NOTE"), .string("")])
        let snapshot = try build(buildFields), original = try run(runFields)
        let guidance = try T6QualityGuidance(build: snapshot, run: original)
        let scenario = try retained(guidance), failures = try XCTUnwrap(guidance.reportedFailedMeasurements)
        XCTAssertEqual(failures.map { Data($0.metric.utf8) }, names.map { Data($0.utf8) })
        XCTAssertEqual(failures.map(\.observed), [observed, observed])
        XCTAssertEqual(failures.map(\.threshold), [threshold, threshold])
        XCTAssertNil(failures[0].unit); XCTAssertEqual(failures[1].unit, "")
        XCTAssertEqual(scenario.run.sampleSize, revision)
        XCTAssertEqual(scenario.run.artifacts, ["file:///tmp/private-quality.json", "urn:private:quality"])
        XCTAssertEqual(scenario.run.notes, ["PRIVATE-LOCAL-NOTE", ""])
        XCTAssertFalse(guidance.cautions.contains(.artifactReferencesNotSupplied))
        XCTAssertTrue(guidance.cautions.contains(.approvalNotEstablished))
        XCTAssertEqual(try QualityEvaluationRun.decode(scenario.run.encoded()).value, .object(runFields))
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: scenario.build.encoded()).value, .object(buildFields))
        XCTAssertEqual(original.value, .object(runFields))
        XCTAssertEqual(snapshot.value, .object(buildFields))
    }
}
