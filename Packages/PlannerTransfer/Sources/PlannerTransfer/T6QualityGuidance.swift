import Foundation

/// One original selection, addressed by its position in this immutable build.
/// A position preserves duplicate IDs for inspection; it is not a reusable ID.
public struct T6QualitySelection: Equatable, Sendable {
    public let position: Int
    public let value: JSONValue
    fileprivate init(position: Int, value: JSONValue) {
        self.position = position; self.value = value
    }
    public var id: String { value.object!["id"]!.string! }
    public var kind: CatalogKind { CatalogKind(rawValue: value.object!["kind"]!.string!)! }
    public var enabled: Bool { value.object!["enabled"]! == .bool(true) }
    public var settings: JSONValue { value.object!["settings"]! }
}

/// No record supplied is not evidence that no evaluation exists elsewhere.
public enum T6QualityRecord: Equatable, Sendable {
    case notSupplied
    case supplied(HistoricalQualityScenario)
}

/// Facts about these inputs only. A selection is not an implemented control,
/// a reported result is not verified evidence, and neither establishes approval.
public enum T6QualityCaution: String, Sendable {
    case reportedValuesOnly, approvalNotEstablished
    case noGuardrailSelection, noEvaluationSuiteSelection, noEnabledEvaluationSuite
    case qualityRecordNotSupplied, evaluationSuiteDisabled
    case reportedRunFailed, reportedRunIncomplete, reportedMeasurementsFailed
    case artifactReferencesNotSupplied
}

public enum T6QualityNextStep: String, Sendable {
    case reviewGuardrailRequirements, selectEvaluationSuite, reviewDisabledEvaluationSuites
    case supplyQualityRecord, reviewRecordedFailures, completeEvaluationRecord
    case reviewEvidenceAndApprovals

    /// Default explanatory text; a consumer can localize the typed step itself.
    public var message: String {
        switch self {
        case .reviewGuardrailRequirements:
            return "Review the controls this workload needs. No guardrail selection was recorded; application or platform controls need their own evidence."
        case .selectEvaluationSuite:
            return "Select an evaluation suite for this workload before attaching its quality record."
        case .reviewDisabledEvaluationSuites:
            return "Review the disabled evaluation selection. Its recorded results do not establish an active evaluation plan."
        case .supplyQualityRecord:
            return "Supply a retained quality record for this exact build revision and evaluation selection."
        case .reviewRecordedFailures:
            return "Review the reported failures and their original measurements and thresholds. Missing evidence does not erase a recorded failure."
        case .completeEvaluationRecord:
            return "Review the incomplete evaluation record and obtain the remaining results for this build revision."
        case .reviewEvidenceAndApprovals:
            return "Review the original evidence and applicable approvals separately. Compatibility success and reported quality results do not establish quality approval."
        }
    }
}

/// Read-only T6 guidance for one selected build and, optionally, one selected run.
/// No latest/best-run selection, threshold arithmetic, compatibility evaluation,
/// evidence authentication, artifact access, storage, export or execution occurs.
public struct T6QualityGuidance: Equatable, Sendable {
    public let build: BuildSnapshot
    public let selections: [T6QualitySelection]
    public let record: T6QualityRecord
    public let cautions: [T6QualityCaution]
    public let nextSteps: [T6QualityNextStep]

    public var guardrails: [T6QualitySelection] { selections.filter { $0.kind == .guardrail } }
    public var evaluationSuites: [T6QualitySelection] { selections.filter { $0.kind == .evaluationSuite } }

    /// Nil denotes no supplied record; an empty array denotes a supplied record
    /// whose measurements contain no reported false flag, not approved quality.
    public var reportedFailedMeasurements: [QualityMeasurement]? {
        guard case .supplied(let scenario) = record else { return nil }
        return scenario.run.measurements.filter { !$0.passed }
    }

    public init(build: BuildSnapshot, run: QualityEvaluationRun? = nil) throws {
        // Reuse the existing exact build/revision/suite/metric admission. Errors
        // propagate unchanged and never attach a foreign record to this build.
        let scenario = try run.map { try HistoricalQualityScenario(build: build, run: $0) }
        let selections = build.value.object!["selections"]!.array!.enumerated().compactMap { position, value in
            let kind = value.object!["kind"]!.string!
            return kind == "guardrail" || kind == "evaluation_suite"
                ? T6QualitySelection(position: position, value: value) : nil
        }
        let suites = selections.filter { $0.kind == .evaluationSuite }
        var cautions: [T6QualityCaution] = [.reportedValuesOnly, .approvalNotEstablished]
        var steps: [T6QualityNextStep] = []
        if !selections.contains(where: { $0.kind == .guardrail }) {
            cautions.append(.noGuardrailSelection); steps.append(.reviewGuardrailRequirements)
        }
        if suites.isEmpty {
            cautions.append(.noEvaluationSuiteSelection); steps.append(.selectEvaluationSuite)
        } else if !suites.contains(where: \.enabled) {
            cautions.append(.noEnabledEvaluationSuite); steps.append(.reviewDisabledEvaluationSuites)
        }
        if let scenario {
            if scenario.evaluationSuite.object!["enabled"] == .bool(false) {
                cautions.append(.evaluationSuiteDisabled)
                if !steps.contains(.reviewDisabledEvaluationSuites) { steps.append(.reviewDisabledEvaluationSuites) }
            }
            if scenario.run.status == .failed { cautions.append(.reportedRunFailed) }
            if scenario.run.status == .incomplete { cautions.append(.reportedRunIncomplete) }
            let failedMeasurements = scenario.run.measurements.contains { !$0.passed }
            if failedMeasurements { cautions.append(.reportedMeasurementsFailed) }
            if scenario.run.status == .failed || failedMeasurements { steps.append(.reviewRecordedFailures) }
            if scenario.run.status == .incomplete { steps.append(.completeEvaluationRecord) }
            if scenario.run.artifacts.isEmpty { cautions.append(.artifactReferencesNotSupplied) }
        } else {
            cautions.append(.qualityRecordNotSupplied)
            if suites.contains(where: \.enabled) { steps.append(.supplyQualityRecord) }
        }
        steps.append(.reviewEvidenceAndApprovals)
        self.build = build; self.selections = selections
        self.record = scenario.map(T6QualityRecord.supplied) ?? .notSupplied
        self.cautions = cautions; self.nextSteps = steps
    }
}
