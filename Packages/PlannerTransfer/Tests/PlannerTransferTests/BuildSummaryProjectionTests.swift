import Foundation
import XCTest
import PlannerCore
@testable import PlannerTransfer

/// Fictional producer statements test consumer binding, not policy or pricing.
final class BuildSummaryProjectionTests: XCTestCase, @unchecked Sendable {
    private func encoded(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        return try parser.parse()
    }
    private func build(_ changes: [String: JSONValue] = [:]) throws -> BuildSnapshot {
        var value = try fixture("build").object!
        for (key, replacement) in changes { value[key] = replacement }
        return try BuildTransfer.snapshot(fromDraftJSON: encoded(.object(value)))
    }
    private func finding(_ outcome: String = "fail", ids: [String] = ["sel_model"], remediation: String? = "Inspect **reported** [inputs](fixture:only).") -> JSONValue {
        var value: [String: JSONValue] = [
            "rule_id": .string("rule.summary.fixture"), "outcome": .string(outcome), "severity": .string("warning"),
            "code": .string("SYNTHETIC_SUMMARY"), "message": .string("FICTIONAL producer finding"),
            "selection_ids": .array(ids.map(JSONValue.string)),
            "evidence": .array([.object(["path": .string("selection.fixture"), "observed": .null,
                "expected": .string("unknown"), "source_version": .string("fixture-e\u{301}")])])
        ]
        if let remediation { value["remediation"] = .string(remediation) }
        return .object(value)
    }
    private func report(_ context: BuildSummaryContext, findings: [JSONValue]? = nil, changes: [String: JSONValue] = [:]) throws -> EvaluationReport {
        let build = context.build.value.object!, locks = context.build.locks.object!
        var value: [String: JSONValue] = [
            "schema_version": .string("1.0.0"), "id": .string("evaluation.summary.fixture"),
            "build_id": build["id"]!, "build_revision": build["revision"]!,
            "catalog_snapshot_id": locks["catalog_snapshot_id"]!, "ruleset_id": locks["ruleset_id"]!,
            "ruleset_version": locks["ruleset_version"]!, "dependency_graph_id": locks["dependency_graph_id"]!,
            "dependency_graph_revision": locks["dependency_graph_revision"]!, "evaluated_at": .string("2026-10-20T06:00:00Z"),
            "result": .string("indeterminate"), "deployment_readiness": .string("needs_review"),
            "findings": .array(findings ?? [finding()]),
            "summary": .object(["passed": .number(4), "failed": .number(2), "unknown": .number(1), "skipped": .number(3)])
        ]
        for (key, replacement) in changes { value[key] = replacement }
        return try EvaluationReport.decode(encoded(.object(value)))
    }
    private func evaluation(_ context: BuildSummaryContext, findings: [JSONValue]? = nil, changes: [String: JSONValue] = [:]) throws -> BuildSummaryEvaluation {
        try BuildSummaryEvaluation(context: context, report: report(context, findings: findings, changes: changes))
    }
    private func cost(_ context: BuildSummaryContext, changes: [String: JSONValue] = [:]) throws -> BuildSummaryCost {
        var value = try fixture("cost-estimate").object!
        value["build_id"] = .string(context.build.id)
        value["build_revision"] = context.build.value.object!["revision"]!
        value["pricebook_id"] = context.build.locks.object!["pricebook_id"]!
        for (key, replacement) in changes { value[key] = replacement }
        let estimate = try CostEstimateRecord.decode(encoded(.object(value)))
        return try BuildSummaryCost(context: context, scenario: HistoricalCostScenario(build: context.build, estimate: estimate))
    }
    private func current(_ input: BuildSummaryEvaluation) async -> AnalysisState<BuildSummaryEvaluation> {
        let store = AnalysisStore<BuildSummaryEvaluation>()
        let request = await store.begin(for: input.context.evaluationIdentity)
        let accepted = await store.receive(input, identity: input.identity, for: request)
        XCTAssertTrue(accepted)
        return await store.state
    }
    private func current(_ input: BuildSummaryCost) async -> AnalysisState<BuildSummaryCost> {
        let store = AnalysisStore<BuildSummaryCost>()
        let request = await store.begin(for: input.context.costIdentity!)
        let accepted = await store.receive(input, identity: input.identity, for: request)
        XCTAssertTrue(accepted)
        return await store.state
    }
    private func assertStale<T: Sendable>(_ value: BuildSummaryAvailability<T>, file: StaticString = #filePath, line: UInt = #line) {
        guard case .stale = value else { return XCTFail("Expected explicit stale input", file: file, line: line) }
        XCTAssertNil(value.currentValue, file: file, line: line)
    }
    private func assertPending<T: Sendable>(_ value: BuildSummaryAvailability<T>, file: StaticString = #filePath, line: UInt = #line) {
        guard case .pending = value else { return XCTFail("Expected pending input", file: file, line: line) }
        XCTAssertNil(value.currentValue, file: file, line: line)
    }

    func testChoicesPreserveOrderIdentityRolesDisabledSettingsAndLinks() throws {
        let original = try build()
        var rows = original.value.object!["selections"]!.array!
        var first = rows[0].object!; first["enabled"] = .bool(false); rows[0] = .object(first)
        rows.reverse()
        let visible = try build(["selections": .array(rows), "name": .string("Private e\u{301} name")])
        let context = try BuildSummaryContext(build: visible)
        let result = BuildSummaryProjection(visible: context)
        XCTAssertEqual(result.context.build, visible)
        XCTAssertEqual(result.choices.map(\.value), rows)
        XCTAssertEqual(result.choices.last?.id, "sel_workload")
        XCTAssertEqual(result.choices.last?.kind, "workload")
        XCTAssertEqual(result.choices.last?.role, "primary")
        XCTAssertEqual(result.choices.last?.enabled, false)
        XCTAssertEqual(result.choices.last?.catalogItemID, "cat.workload.fixture")
        XCTAssertEqual(result.choices.last?.catalogItemVersion, "2026.10-demo")
        XCTAssertEqual(result.context.build.value.object!["links"], original.value.object!["links"])
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: result.context.build.encoded()), visible)
    }

    func testEmptySelectionsAreRejectedBeforeSummaryProjection() throws {
        let original = try build()
        XCTAssertThrowsError(try build(["selections": .array([]), "links": .array([])])) {
            XCTAssertEqual($0 as? TransferError, .schemaViolation)
        }
        // Frozen Build admission requires at least two selections. This
        // projection does not invent a valid snapshot for an incomplete editor.
        XCTAssertEqual(original.value.object!["selections"]!.array!.count, 29)
    }

    func testDuplicateSelectionIdentityRejectsWithoutChangingFrozenAdmission() throws {
        let original = try build(); var rows = original.value.object!["selections"]!.array!
        rows.append(rows[0])
        let decoded = try build(["selections": .array(rows)])
        XCTAssertThrowsError(try BuildSummaryContext(build: decoded)) { XCTAssertEqual($0 as? BuildSummaryError, .ambiguousSelectionIdentity) }
        XCTAssertEqual(decoded.value.object!["selections"]!.array!.count, 30)
        XCTAssertEqual(original.value.object!["selections"]!.array!.count, 29)
    }

    func testEveryReportIdentityFieldMustMatchCapturedInputs() throws {
        let context = try BuildSummaryContext(build: build())
        let wrong: [(String, JSONValue)] = [("build_id", .string("build.other")), ("build_revision", .number(2)),
            ("catalog_snapshot_id", .string("catalog.other")), ("ruleset_id", .string("rules.other")),
            ("ruleset_version", .string("1.0.1")), ("dependency_graph_id", .string("graph.other")),
            ("dependency_graph_revision", .number(2))]
        for (key, value) in wrong {
            XCTAssertThrowsError(try evaluation(context, changes: [key: value])) { XCTAssertEqual($0 as? BuildSummaryError, .reportMismatch, key) }
        }
        XCTAssertEqual(try evaluation(context).identity, context.evaluationIdentity)
    }

    func testUnknownFindingParticipantIsRejectedButOriginalReportSurvives() throws {
        let context = try BuildSummaryContext(build: build())
        let supplied = try report(context, findings: [finding(ids: ["sel_missing"])])
        XCTAssertThrowsError(try BuildSummaryEvaluation(context: context, report: supplied)) { XCTAssertEqual($0 as? BuildSummaryError, .unknownFindingParticipant) }
        XCTAssertEqual(supplied.findings[0].selectionIDs, ["sel_missing"])
    }

    func testCurrentReportRetainsAllStatementsWithoutRecomputingItsSummary() async throws {
        let context = try BuildSummaryContext(build: build())
        let input = try evaluation(context, findings: [finding("pass"), finding("unknown"), finding("fail"), finding("skipped")])
        let result = BuildSummaryProjection(visible: context, evaluation: await current(input))
        XCTAssertEqual(result.evaluation.currentValue, input.report)
        XCTAssertEqual(result.evaluation.currentValue?.summary.passed, 4)
        XCTAssertEqual(result.evaluation.currentValue?.summary.failed, 2)
        XCTAssertEqual(result.evaluation.currentValue?.result, .indeterminate)
        XCTAssertEqual(result.evaluation.currentValue?.findings[1].severity, .warning)
        XCTAssertEqual(result.evaluation.currentValue?.findings[1].evidence?[0].observed, .null)
        XCTAssertEqual(result.evaluation.currentValue?.findings[1].evidence?[0].expected, .string("unknown"))
        var ordinals: [Int] = []
        for inspection in result.inspections {
            if case .finding(let ordinal, let value, _) = inspection {
                ordinals.append(ordinal); XCTAssertEqual(value, input.report.findings[ordinal])
            }
        }
        XCTAssertEqual(ordinals, [1, 2])
    }

    func testRepeatedRuleFindingsStayDistinctOrderedRows() async throws {
        let context = try BuildSummaryContext(build: build())
        let input = try evaluation(context, findings: [finding(), finding()])
        let result = BuildSummaryProjection(visible: context, evaluation: await current(input))
        XCTAssertEqual(result.evaluation.currentValue?.findings.count, 2)
        guard case .finding(let first, _, _) = result.inspections[0], case .finding(let second, _, _) = result.inspections[1] else { return XCTFail("Both original rows required") }
        XCTAssertEqual([first, second], [0, 1])
    }

    func testAbsentEmptyWhitespaceAndVerbatimRemediationRemainDistinct() async throws {
        let context = try BuildSummaryContext(build: build())
        let actions: [String?] = [nil, "", "\t \n\r\u{00a0}", "  **Inspect** [supplied](fixture:only).  "]
        let input = try evaluation(context, findings: actions.map { finding(remediation: $0) })
        let result = BuildSummaryProjection(visible: context, evaluation: await current(input))
        XCTAssertEqual(result.evaluation.currentValue?.findings.map(\.remediation), actions)
        for (index, action) in actions.enumerated() {
            guard case .finding(let ordinal, _, let supplied) = result.inspections[index] else { return XCTFail("Finding inspection required") }
            XCTAssertEqual(ordinal, index)
            XCTAssertEqual(supplied, index == 3 ? action : nil)
        }
    }

    func testEmptyReportedPassDoesNotInventAnOverallSuccessOrCorrection() async throws {
        let context = try BuildSummaryContext(build: build())
        let input = try evaluation(context, findings: [], changes: ["result": .string("valid"), "deployment_readiness": .string("ready")])
        let result = BuildSummaryProjection(visible: context, evaluation: await current(input))
        XCTAssertEqual(result.evaluation.currentValue, input.report)
        XCTAssertEqual(result.inspections.count, 1)
        guard case .costStatus = result.inspections[0] else { return XCTFail("Missing cost remains explicit") }
    }

    func testNonreadyReportWithoutFindingsRequiresInspectionNotAnInventedFix() async throws {
        let context = try BuildSummaryContext(build: build())
        let result = BuildSummaryProjection(visible: context, evaluation: await current(try evaluation(context, findings: [])))
        guard case .reportedEvaluation = result.inspections[0] else { return XCTFail("Inspect supplied report") }
    }

    func testCurrentRecordedCostPreservesExactLongMoneyAndOriginalWarnings() async throws {
        let context = try BuildSummaryContext(build: build())
        let money = JSONValue.object(["amount": .string(String(repeating: "9", count: 200) + ".000000000001"), "currency": .string("USD")])
        let input = try cost(context, changes: ["total": money])
        let result = BuildSummaryProjection(visible: context, cost: await current(input))
        let observed = try XCTUnwrap(result.cost.currentValue)
        XCTAssertEqual(observed.scenario, input.scenario)
        XCTAssertEqual(observed.amount, .reportedComplete(input.scenario.estimate.total))
        XCTAssertEqual(observed.cautions, [.reportedValuesOnly])
        XCTAssertEqual(observed.scenario.estimate.value.object!["total"], money)
        guard case .costCoverage = result.inspections.last! else { return XCTFail("Warnings remain inspectable") }
    }

    func testPartialRecordedZeroRemainsExplicitlyPartial() async throws {
        let context = try BuildSummaryContext(build: build())
        let input = try cost(context, changes: ["coverage": .string("partial"),
            "total": .object(["amount": .string("0.0000"), "currency": .string("USD")]),
            "unpriced_selection_ids": .array([.string("sel_model")])])
        let result = BuildSummaryProjection(visible: context, cost: await current(input))
        XCTAssertEqual(result.cost.currentValue?.amount, .reportedPartial(input.scenario.estimate.total))
        XCTAssertEqual(result.cost.currentValue?.cautions, [.reportedValuesOnly, .partialCoverage, .unpricedSelections])
        XCTAssertEqual(result.cost.currentValue?.scenario.estimate.unpricedSelectionIDs, ["sel_model"])
    }

    func testUnknownCoverageWithholdsZeroAndNonzeroHeadlineAmounts() async throws {
        let context = try BuildSummaryContext(build: build())
        for amount in ["0", "123.4500"] {
            let input = try cost(context, changes: ["coverage": .string("unknown"), "total": .object(["amount": .string(amount), "currency": .string("USD")])])
            let result = BuildSummaryProjection(visible: context, cost: await current(input))
            XCTAssertEqual(result.cost.currentValue?.amount, .withheld)
            XCTAssertEqual(result.cost.currentValue?.scenario.estimate.total.amount, amount)
            XCTAssertEqual(result.cost.currentValue?.cautions, [.reportedValuesOnly, .unknownCoverage])
        }
    }

    func testCompleteWithUnpricedParticipantsWithholdsContradictoryTotal() async throws {
        let context = try BuildSummaryContext(build: build())
        let input = try cost(context, changes: ["unpriced_selection_ids": .array([.string("sel_storage")])])
        let result = BuildSummaryProjection(visible: context, cost: await current(input))
        XCTAssertEqual(result.cost.currentValue?.amount, .withheld)
        XCTAssertEqual(result.cost.currentValue?.scenario.estimate.coverage, .complete)
        XCTAssertEqual(result.cost.currentValue?.cautions, [.reportedValuesOnly, .unpricedSelections, .inconsistentCompleteCoverage])
    }

    func testEveryNestedMixedCurrencyWithholdsAmountWithoutEditingRecord() async throws {
        let context = try BuildSummaryContext(build: build())
        for field in ["subtotal", "tax", "total", "unit_price", "amount"] {
            var value = try fixture("cost-estimate").object!
            if ["unit_price", "amount"].contains(field) {
                var rows = value["line_items"]!.array!, row = rows[0].object!, money = row[field]!.object!
                money["currency"] = .string("EUR"); row[field] = .object(money); rows[0] = .object(row); value["line_items"] = .array(rows)
            } else {
                var money = value[field]!.object!; money["currency"] = .string("EUR"); value[field] = .object(money)
            }
            let record = try CostEstimateRecord.decode(encoded(.object(value)))
            let input = try BuildSummaryCost(context: context, scenario: HistoricalCostScenario(build: context.build, estimate: record))
            let result = BuildSummaryProjection(visible: context, cost: await current(input))
            XCTAssertEqual(result.cost.currentValue?.amount, .withheld, field)
            XCTAssertEqual(result.cost.currentValue?.scenario.estimate, record)
            XCTAssertEqual(result.cost.currentValue?.cautions, [.reportedValuesOnly, .mixedCurrencies])
        }
    }

    func testCostCannotBindToDifferentFullSnapshotWithSameWireIdentity() throws {
        let original = try BuildSummaryContext(build: build()), input = try cost(original)
        let other = try BuildSummaryContext(build: build(["name": .string("Different same-revision bytes")]))
        XCTAssertThrowsError(try BuildSummaryCost(context: other, scenario: input.scenario)) { XCTAssertEqual($0 as? BuildSummaryError, .costSnapshotMismatch) }
        XCTAssertEqual(input.scenario.build, original.build)
    }

    func testAbsentPricebookCannotSupplyARequestOrHeadlineCost() throws {
        var locks = try build().locks.object!; locks.removeValue(forKey: "pricebook_id")
        let context = try BuildSummaryContext(build: build(["locks": .object(locks)]))
        let result = BuildSummaryProjection(visible: context)
        XCTAssertNil(context.costIdentity)
        XCTAssertNil(result.cost.currentValue)
        guard case .unavailable(.notRequested) = result.cost else { return XCTFail("Missing cost is not zero") }
    }

    func testFreshPendingStatesExposeNoOldReportOrCost() async throws {
        let context = try BuildSummaryContext(build: build())
        let reports = AnalysisStore<BuildSummaryEvaluation>(), costs = AnalysisStore<BuildSummaryCost>()
        await reports.begin(for: context.evaluationIdentity); await costs.begin(for: context.costIdentity!)
        let result = BuildSummaryProjection(visible: context, evaluation: await reports.state, cost: await costs.state)
        assertPending(result.evaluation); assertPending(result.cost)
    }

    func testUnavailableReasonsRemainExplicitAndForeignIdentityStaysStale() throws {
        let context = try BuildSummaryContext(build: build()), foreign = try BuildSummaryContext(build: build())
        for reason in [AnalysisUnavailableReason.notRequested, .cancelled, .failed, .disconnected] {
            let result = BuildSummaryProjection(visible: context,
                evaluation: .unavailable(identity: context.evaluationIdentity, reason: reason),
                cost: .unavailable(identity: context.costIdentity, reason: reason))
            guard case .unavailable(let actual) = result.evaluation else { return XCTFail("Reason required") }
            XCTAssertEqual(actual, reason); XCTAssertNil(result.cost.currentValue)
        }
        let result = BuildSummaryProjection(visible: context,
            evaluation: .unavailable(identity: foreign.evaluationIdentity, reason: .failed))
        assertStale(result.evaluation)
    }

    func testNewContextRetiresBothCurrentAndPendingSameRevisionInputs() async throws {
        let old = try BuildSummaryContext(build: build()), response = try evaluation(old), estimate = try cost(old)
        let reportState = await current(response), costState = await current(estimate)
        let oldStore = AnalysisStore<BuildSummaryEvaluation>(); await oldStore.begin(for: old.evaluationIdentity)
        var objectives = old.build.value.object!["objectives"]!.object!; objectives["requests_per_day"] = .number(201)
        for snapshot in [old.build, try build(["objectives": .object(objectives)]), try build(["revision": .number(2)])] {
            let fresh = try BuildSummaryContext(build: snapshot)
            XCTAssertNotEqual(fresh.evaluationIdentity, old.evaluationIdentity)
            let result = BuildSummaryProjection(visible: fresh, evaluation: reportState, cost: costState)
            assertStale(result.evaluation); assertStale(result.cost)
            assertStale(BuildSummaryProjection(visible: fresh, evaluation: await oldStore.state).evaluation)
        }
    }

    func testSameInputRetryUsesActualStoreGenerationAndWithholdsPreviousResult() async throws {
        let context = try BuildSummaryContext(build: build()), input = try evaluation(context)
        let store = AnalysisStore<BuildSummaryEvaluation>()
        let old = await store.begin(for: context.evaluationIdentity)
        let first = await store.receive(input, identity: input.identity, for: old); XCTAssertTrue(first)
        let next = await store.begin(for: context.evaluationIdentity)
        XCTAssertNotEqual(old.generation, next.generation)
        let late = await store.receive(input, identity: input.identity, for: old); XCTAssertFalse(late)
        assertPending(BuildSummaryProjection(visible: context, evaluation: await store.state).evaluation)
        let fresh = await store.receive(input, identity: input.identity, for: next); XCTAssertTrue(fresh)
        let state = await store.state
        XCTAssertEqual(BuildSummaryProjection(visible: context, evaluation: state).evaluation.currentValue, input.report)
    }

    func testLatePreviousContextResponseCannotReplaceNewVisibleResult() async throws {
        let old = try BuildSummaryContext(build: build()), fresh = try BuildSummaryContext(build: build(["revision": .number(2)]))
        let oldInput = try evaluation(old), freshInput = try evaluation(fresh)
        let store = AnalysisStore<BuildSummaryEvaluation>()
        let prior = await store.begin(for: old.evaluationIdentity), next = await store.begin(for: fresh.evaluationIdentity)
        let stale = await store.receive(oldInput, identity: oldInput.identity, for: prior); XCTAssertFalse(stale)
        let accepted = await store.receive(freshInput, identity: freshInput.identity, for: next); XCTAssertTrue(accepted)
        let result = BuildSummaryProjection(visible: fresh, evaluation: await store.state)
        XCTAssertEqual(result.evaluation.currentValue?.buildRevision, 2)
        XCTAssertEqual(result.context.build.value.object!["revision"], .number(2))
    }

    func testWrongCostResponseIdentityCannotBeCopiedFromTheRequest() async throws {
        let visible = try BuildSummaryContext(build: build()), other = try BuildSummaryContext(build: build())
        let input = try cost(other), store = AnalysisStore<BuildSummaryCost>()
        let request = await store.begin(for: visible.costIdentity!)
        let received = await store.receive(input, identity: input.identity, for: request); XCTAssertFalse(received)
        assertPending(BuildSummaryProjection(visible: visible, cost: await store.state).cost)
        // Even a caller manually assembling the public enum cannot attach the
        // other context's value to a real request issued for the visible one.
        assertStale(BuildSummaryProjection(visible: visible, cost: .current(request: request, value: input)).cost)
    }

    func testCurrentEvaluationAndCostRemainIndependentlyAvailable() async throws {
        let context = try BuildSummaryContext(build: build())
        let reportInput = try evaluation(context), costInput = try cost(context)
        let reports = AnalysisStore<BuildSummaryEvaluation>(), costs = AnalysisStore<BuildSummaryCost>()
        let reportRequest = await reports.begin(for: context.evaluationIdentity)
        await costs.begin(for: context.costIdentity!)
        let first = BuildSummaryProjection(visible: context, evaluation: await current(reportInput), cost: await costs.state)
        XCTAssertEqual(first.evaluation.currentValue, reportInput.report); assertPending(first.cost)
        let second = BuildSummaryProjection(visible: context, evaluation: await reports.state, cost: await current(costInput))
        assertPending(second.evaluation); XCTAssertEqual(second.cost.currentValue?.scenario, costInput.scenario)
        let cancelled = await reports.cancel(reportRequest); XCTAssertTrue(cancelled)
        let late = await reports.receive(reportInput, identity: reportInput.identity, for: reportRequest); XCTAssertFalse(late)
        guard case .unavailable(.cancelled) = BuildSummaryProjection(visible: context, evaluation: await reports.state).evaluation else { return XCTFail("Cancelled result remains unavailable") }
        await costs.disconnect()
        guard case .unavailable(.disconnected) = BuildSummaryProjection(visible: context, cost: await costs.state).cost else { return XCTFail("Disconnected cost remains unavailable") }
    }
}
