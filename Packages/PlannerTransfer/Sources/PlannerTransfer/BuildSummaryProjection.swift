import Foundation
import PlannerCore

public enum BuildSummaryError: Error, Equatable, Sendable {
    case ambiguousSelectionIdentity, reportMismatch, unknownFindingParticipant, costSnapshotMismatch
}

/// One exact visible snapshot in one local editing/authority period. Retain this
/// immutable value while rendering; create a fresh context on input, selection,
/// account, route or owner change, including restoration to earlier bytes.
/// The UUID is a local freshness discriminator, never authentication or wire data.
public struct BuildSummaryContext: Equatable, Sendable {
    public let build: BuildSnapshot
    public let id: UUID

    public init(build: BuildSnapshot) throws {
        var ids = Set<String>()
        for selection in build.value.object!["selections"]!.array! {
            guard ids.insert(selection.object!["id"]!.string!).inserted else {
                throw BuildSummaryError.ambiguousSelectionIdentity
            }
        }
        self.build = build
        id = UUID()
    }

    public var evaluationIdentity: AnalysisIdentity {
        let locks = build.locks.object!
        return scoped(AnalysisIdentity(buildID: build.id, revision: Self.revision(build.value.object!["revision"]!.number!),
            versionLocks: ["catalog_snapshot_id": locks["catalog_snapshot_id"]!.string!,
                "ruleset_id": locks["ruleset_id"]!.string!, "ruleset_version": locks["ruleset_version"]!.string!,
                "dependency_graph_id": locks["dependency_graph_id"]!.string!,
                "dependency_graph_revision": Self.revision(locks["dependency_graph_revision"]!.number!)]))
    }

    /// Missing optional pricebook input supplies no cost request identity.
    public var costIdentity: AnalysisIdentity? {
        guard let pricebook = build.locks.object!["pricebook_id"]?.string else { return nil }
        return scoped(AnalysisIdentity(buildID: build.id, revision: Self.revision(build.value.object!["revision"]!.number!),
                                       versionLocks: ["pricebook_id": pricebook]))
    }

    fileprivate func scoped(_ identity: AnalysisIdentity) -> AnalysisIdentity {
        var locks = identity.versionLocks
        locks["local_summary_context"] = id.uuidString
        return AnalysisIdentity(buildID: identity.buildID, revision: identity.revision, versionLocks: locks)
    }

    fileprivate static func revision(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}

/// A supplied report attached to its exact captured input. Admission preserves
/// producer statements; it does not evaluate rules, infer readiness or grade evidence.
public struct BuildSummaryEvaluation: Sendable {
    public let context: BuildSummaryContext
    public let report: EvaluationReport
    public var identity: AnalysisIdentity { context.scoped(report.analysisIdentity) }

    public init(context: BuildSummaryContext, report: EvaluationReport) throws {
        guard context.scoped(report.analysisIdentity) == context.evaluationIdentity else {
            throw BuildSummaryError.reportMismatch
        }
        let ids = Set(context.build.value.object!["selections"]!.array!.map { $0.object!["id"]!.string! })
        guard report.findings.allSatisfy({ $0.selectionIDs.allSatisfy(ids.contains) }) else {
            throw BuildSummaryError.unknownFindingParticipant
        }
        self.context = context
        self.report = report
    }
}

/// Reuses the existing record/build/pricebook/selection admission. The original
/// scenario remains private local data, not a qualified quote or sharing payload.
public struct BuildSummaryCost: Sendable {
    public let context: BuildSummaryContext
    public let scenario: HistoricalCostScenario
    public var identity: AnalysisIdentity {
        context.scoped(AnalysisIdentity(buildID: scenario.estimate.buildID,
            revision: BuildSummaryContext.revision(scenario.estimate.buildRevision),
            versionLocks: ["pricebook_id": scenario.estimate.pricebookID]))
    }

    public init(context: BuildSummaryContext, scenario: HistoricalCostScenario) throws {
        guard context.build == scenario.build else { throw BuildSummaryError.costSnapshotMismatch }
        self.context = context
        self.scenario = scenario
    }
}

/// Currentness comes from the existing AnalysisStore plus the exact local context.
/// Stale data is withheld rather than retained as a current-looking summary.
public enum BuildSummaryAvailability<Value: Sendable>: Sendable {
    case unavailable(AnalysisUnavailableReason), pending, stale, current(Value)

    public var currentValue: Value? {
        if case .current(let value) = self { return value }
        return nil
    }
}

public struct BuildSummaryChoice: Equatable, Sendable {
    public let value: JSONValue
    fileprivate init(_ value: JSONValue) { self.value = value }
    public var id: String { value.object!["id"]!.string! }
    public var kind: String { value.object!["kind"]!.string! }
    public var role: String { value.object!["role"]!.string! }
    public var enabled: Bool { value.object!["enabled"] == .bool(true) }
    public var catalogItemID: String { value.object!["catalog_item_id"]!.string! }
    public var catalogItemVersion: String { value.object!["catalog_item_version"]!.string! }
}

public enum BuildSummaryCostCaution: String, Sendable {
    case reportedValuesOnly, partialCoverage, unknownCoverage, unpricedSelections
    case inconsistentCompleteCoverage, mixedCurrencies
}

/// Labels describe the supplied record only. Neither case is a verified total,
/// budget result, applicable price or arithmetic assertion. Unknown/inconsistent
/// coverage has no headline amount; its original record remains inspectable.
public enum BuildSummaryReportedAmount: Sendable, Equatable {
    case reportedComplete(CostEstimateMoney), reportedPartial(CostEstimateMoney), withheld
}

public struct BuildSummaryReportedCost: Sendable {
    public let scenario: HistoricalCostScenario
    public let amount: BuildSummaryReportedAmount
    public let cautions: [BuildSummaryCostCaution]

    fileprivate init(_ scenario: HistoricalCostScenario) {
        self.scenario = scenario
        let estimate = scenario.estimate
        var cautions: [BuildSummaryCostCaution] = [.reportedValuesOnly]
        if estimate.coverage == .partial { cautions.append(.partialCoverage) }
        if estimate.coverage == .unknown { cautions.append(.unknownCoverage) }
        if !estimate.unpricedSelectionIDs.isEmpty { cautions.append(.unpricedSelections) }
        let inconsistent = estimate.coverage == .complete && !estimate.unpricedSelectionIDs.isEmpty
        if inconsistent { cautions.append(.inconsistentCompleteCoverage) }
        let mixed = [estimate.subtotal, estimate.tax, estimate.total].contains { $0.currency != estimate.currency }
            || estimate.lineItems.contains { $0.unitPrice.currency != estimate.currency || $0.amount.currency != estimate.currency }
        if mixed { cautions.append(.mixedCurrencies) }
        self.cautions = cautions
        if inconsistent || mixed || estimate.coverage == .unknown { amount = .withheld }
        else if estimate.coverage == .partial { amount = .reportedPartial(estimate.total) }
        else { amount = .reportedComplete(estimate.total) }
    }
}

/// Inspection targets only, in producer finding order followed by cost status.
/// The zero-based ordinal is a display position, not a stable rule/selection ID.
/// No text is executable, no replacement is proposed and no success is inferred.
public enum BuildSummaryInspection: Sendable {
    case finding(ordinal: Int, finding: EvaluationFinding, suppliedRemediation: String?)
    case evaluationStatus, reportedEvaluation, costStatus, costCoverage
}

/// Pure immutable preparation for a persistent summary. The native consumer
/// supplies its actual current AnalysisStore states, maintains context ownership
/// and decides reachability/accessibility. This type owns no request or writer.
public struct BuildSummaryProjection: Sendable {
    public let context: BuildSummaryContext
    public let choices: [BuildSummaryChoice]
    public let evaluation: BuildSummaryAvailability<EvaluationReport>
    public let cost: BuildSummaryAvailability<BuildSummaryReportedCost>
    public let inspections: [BuildSummaryInspection]

    public init(
        visible context: BuildSummaryContext,
        evaluation: AnalysisState<BuildSummaryEvaluation> = .unavailable(identity: nil, reason: .notRequested),
        cost: AnalysisState<BuildSummaryCost> = .unavailable(identity: nil, reason: .notRequested)
    ) {
        self.context = context
        choices = context.build.value.object!["selections"]!.array!.map(BuildSummaryChoice.init)
        self.evaluation = Self.project(evaluation, expected: context.evaluationIdentity) { input in
            input.context == context ? (input.identity, input.report) : nil
        }
        self.cost = Self.project(cost, expected: context.costIdentity) { input in
            input.context == context ? (input.identity, BuildSummaryReportedCost(input.scenario)) : nil
        }
        var inspections: [BuildSummaryInspection] = []
        if let report = self.evaluation.currentValue {
            for (ordinal, finding) in report.findings.enumerated() where finding.outcome == .fail || finding.outcome == .unknown {
                let supplied = finding.remediation.flatMap {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                }
                inspections.append(.finding(ordinal: ordinal, finding: finding, suppliedRemediation: supplied))
            }
            if inspections.isEmpty && (report.result != .valid || report.deploymentReadiness != .ready) {
                inspections.append(.reportedEvaluation)
            }
        } else { inspections.append(.evaluationStatus) }
        if let estimate = self.cost.currentValue {
            if estimate.cautions.count > 1 || !estimate.scenario.estimate.warnings.isEmpty {
                inspections.append(.costCoverage)
            }
        } else { inspections.append(.costStatus) }
        self.inspections = inspections
    }

    private static func project<Input: Sendable, Output: Sendable>(
        _ state: AnalysisState<Input>, expected: AnalysisIdentity?,
        admit: (Input) -> (AnalysisIdentity, Output)?
    ) -> BuildSummaryAvailability<Output> {
        switch state {
        case .unavailable(let identity, let reason):
            guard identity == nil || identity == expected else { return .stale }
            return .unavailable(reason)
        case .pending(let request):
            return request.identity == expected ? .pending : .stale
        case .current(let request, let input):
            guard request.identity == expected, let (identity, value) = admit(input), identity == request.identity else {
                return .stale
            }
            return .current(value)
        }
    }
}
