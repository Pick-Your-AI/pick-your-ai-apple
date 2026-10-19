import Foundation
import PlannerCore

/// Sanitized failures specific to this opt-in receiving profile. The existing
/// Core decoder still reports its own bounded wire/representation failures.
public enum FrozenReferenceReportError: Error, Equatable, Sendable {
    case bindingMismatch
    case inconsistentFindings
}

/// An immutable consistency receipt for the selected frozen-reference profile.
/// This does not execute predicates, authenticate a publisher or evidence, prove
/// that computation occurred, or grant current UI/deployment authority.
public struct FrozenReferenceReportAdmission: Sendable, Equatable,
    CustomStringConvertible, CustomDebugStringConvertible {
    public static let profileID = "local-retained-frozen-v1-no-external-evidence/1"

    public let report: EvaluationReport
    public let reportData: Data
    public let build: BuildSnapshot
    public let ruleset: Ruleset
    public let dependencyGraph: DependencyGraph

    private init(report: EvaluationReport, reportData: Data, build: BuildSnapshot,
                 ruleset: Ruleset, dependencyGraph: DependencyGraph) {
        self.report = report
        self.reportData = reportData
        self.build = build
        self.ruleset = ruleset
        self.dependencyGraph = dependencyGraph
    }

    /// Default diagnostics must not print private Build content or report evidence.
    public var description: String { "FrozenReferenceReportAdmission" }
    public var debugDescription: String { description }

    /// Response authority comes from the validated report, never from the request
    /// that happened to initiate a transport. Publishers and input versions must
    /// be approved separately; these identifiers are not content attestations.
    public var analysisIdentity: AnalysisIdentity { report.analysisIdentity }

    /// Inputs have already passed the unchanged frozen Transfer decoders. Their
    /// complete immutable values are retained, while the report binds the v1
    /// identity tuple. The graph is bound in full but no edges or rules execute.
    /// Perform this bounded synchronous work away from the UI actor.
    public static func decode(_ data: Data, build: BuildSnapshot, ruleset: Ruleset,
                              dependencyGraph: DependencyGraph) throws -> Self {
        let report = try EvaluationReport.decode(data)
        guard let b = build.value.object, let locks = b["locks"]?.object,
              b["schema_version"] == .string(report.schemaVersion),
              b["id"] == .string(report.buildID),
              b["revision"] == .number(Decimal(report.buildRevision)),
              locks["catalog_snapshot_id"] == .string(report.catalogSnapshotID),
              locks["ruleset_id"] == .string(report.rulesetID),
              locks["ruleset_version"] == .string(report.rulesetVersion),
              locks["dependency_graph_id"] == .string(report.dependencyGraphID),
              locks["dependency_graph_revision"] == .number(Decimal(report.dependencyGraphRevision)),
              ruleset.value.object?["id"] == locks["ruleset_id"],
              ruleset.value.object?["version"] == locks["ruleset_version"],
              dependencyGraph.value.object?["id"] == locks["dependency_graph_id"],
              dependencyGraph.value.object?["revision"] == locks["dependency_graph_revision"]
        else { throw FrozenReferenceReportError.bindingMismatch }

        let rules = ruleset.rules
        let findings = report.findings
        var ruleIDs = Set<Data>()
        guard findings.count == rules.count,
              rules.allSatisfy({ rule in
                  guard let id = rule.object?["id"]?.string else { return false }
                  return ruleIDs.insert(Data(id.utf8)).inserted
              })
        else { throw FrozenReferenceReportError.inconsistentFindings }

        // A selection participates only when the validated Boolean is true.
        // The reference emits sorted distinct IDs for all active affected kinds,
        // including on skipped/unknown findings; it does not prune by graph edges.
        let active = (b["selections"]?.array ?? []).filter {
            $0.object?["enabled"] == .bool(true)
        }
        var passed = 0, failed = 0, unknown = 0, skipped = 0
        var errorFailure = false, unknownBlocks = false
        for (finding, ruleValue) in zip(findings, rules) {
            guard let rule = ruleValue.object,
                  rule["id"] == .string(finding.ruleID),
                  rule["severity"] == .string(finding.severity.rawValue),
                  let kinds = rule["affected_kinds"]?.array
            else { throw FrozenReferenceReportError.inconsistentFindings }
            let ids = Set(active.compactMap { selection -> String? in
                guard let item = selection.object, let kind = item["kind"],
                      kinds.contains(kind) else { return nil }
                return item["id"]?.string
            }).sorted()
            // Frozen selection IDs are ASCII. JSONValue equality additionally
            // preserves byte-distinct strings if a future caller changes them.
            guard JSONValue.array(finding.selectionIDs.map(JSONValue.string)) ==
                    .array(ids.map(JSONValue.string))
            else { throw FrozenReferenceReportError.inconsistentFindings }
            switch finding.outcome {
            case .pass: passed += 1
            case .fail:
                failed += 1
                errorFailure = errorFailure || finding.severity == .error
            case .unknown:
                unknown += 1
                unknownBlocks = unknownBlocks || rule["on_unknown"] == .string("block")
            case .skipped: skipped += 1
            }
        }
        guard report.summary.passed == passed, report.summary.failed == failed,
              report.summary.unknown == unknown, report.summary.skipped == skipped
        else { throw FrozenReferenceReportError.inconsistentFindings }

        let strictUnknown = b["policy"]?.object?["fail_on_unknown"] == .bool(true)
        let result: EvaluationResult = errorFailure ? .invalid : unknown > 0 ? .indeterminate : .valid
        let readiness: EvaluationReadiness =
            errorFailure || unknownBlocks || (unknown > 0 && strictUnknown) ? .blocked : .needsReview
        guard report.result == result, report.deploymentReadiness == readiness
        else { throw FrozenReferenceReportError.inconsistentFindings }

        return Self(report: report, reportData: data, build: build,
                    ruleset: ruleset, dependencyGraph: dependencyGraph)
    }
}

public extension AnalysisStore where Value == FrozenReferenceReportAdmission {
    /// Reuse the existing fresh-attempt/selection gate. A consistent report cannot
    /// revive a cancelled, superseded, foreign-store or already consumed request.
    @discardableResult
    func receive(_ admission: FrozenReferenceReportAdmission, for request: AnalysisRequest) -> Bool {
        receive(admission, identity: admission.analysisIdentity, for: request)
    }
}
