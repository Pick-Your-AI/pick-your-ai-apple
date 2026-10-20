import Foundation
import PlannerCore
import SwiftUI

/// Displays an already validated report without evaluating or approving its claims.
/// Callers remain responsible for selecting the report for the exact current build.
public struct EvaluationReportView: View {
    private let report: EvaluationReport

    public init(report: EvaluationReport) { self.report = report }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Evaluation report").font(.title2).accessibilityAddTraits(.isHeader)
                Text(verbatim: "Reported compatibility: \(report.result.rawValue)")
                Text(verbatim: "Reported readiness: \(report.deploymentReadiness.rawValue)")
                Text("Missing or unknown observations do not establish compatibility.")
                    .foregroundStyle(.secondary)
                Text(verbatim: "Build: \(report.buildID), revision \(report.buildRevision)")
                Text(verbatim: "Catalog snapshot: \(report.catalogSnapshotID)")
                Text(verbatim: "Reported ruleset: \(report.rulesetID)")
                Text(verbatim: "Reported ruleset version: \(report.rulesetVersion)")
                Text(verbatim: "Evaluated at: \(report.evaluatedAt)")
                Text(verbatim: "Reported counts — pass: \(report.summary.passed), fail: \(report.summary.failed), unknown: \(report.summary.unknown), skipped: \(report.summary.skipped)")
                if report.findings.isEmpty {
                    Text("No findings were supplied. This does not establish a pass.")
                }
                ForEach(report.findings.indices, id: \.self) { index in
                    EvaluationFindingView(finding: report.findings[index])
                        .accessibilityIdentifier("evaluation-finding-\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .accessibilityIdentifier("evaluation-report")
    }
}

struct EvaluationFindingView: View {
    let finding: EvaluationFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: finding.ruleID).font(.headline).accessibilityAddTraits(.isHeader)
            Text(verbatim: "Reported rule outcome: \(finding.outcome.rawValue)")
            Text(verbatim: "Severity: \(finding.severity.rawValue)")
            Text(verbatim: "Code: \(finding.code)")
            Text(verbatim: finding.message)
            if finding.selectionIDs.isEmpty {
                Text("Reported participant selections: none supplied.")
            } else {
                ForEach(finding.selectionIDs.indices, id: \.self) { index in
                    Text(verbatim: "Reported participant selection \(index + 1): \(finding.selectionIDs[index])")
                }
            }
            if let remediation = finding.remediation,
               !remediation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: "Reported remediation: \(remediation)")
            } else {
                Text("No corrective action is described in this finding. Review its evidence before changing a setting.")
            }
            switch finding.evidencePresence {
            case .absent:
                Text("Evidence was not provided. Support is unknown.")
            case .empty:
                Text("The evidence list is empty. Support is unknown.")
            case .supplied:
                Text("Reported evidence values; presence alone is not verification.")
            }
            if let evidence = finding.evidence {
                ForEach(evidence.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Evidence path: \(quoted(evidence[index].path))")
                        EvidenceValueView(label: "Observed", value: evidence[index].observed)
                        EvidenceValueView(label: "Expected", value: evidence[index].expected)
                        if let source = evidence[index].sourceVersion {
                            Text(verbatim: "Source version: \(quoted(source))")
                        } else {
                            Text("Source version: not provided")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("evidence-entry-\(index)")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

private struct EvidenceValueView: View {
    let label: String
    let value: EvaluationJSONValue?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch EvidenceValuePresence(value) {
            case .absent:
                Text(verbatim: "\(label): not provided (unanswered)")
            case .explicitNull:
                Text(verbatim: "\(label): explicit null")
            case .literalUnknown:
                Text(verbatim: "\(label): literal string \"unknown\"")
            case .supplied:
                if let value {
                    Text(verbatim: "\(label): \(encoded(value))")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private func encoded(_ value: EvaluationJSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let bytes = try? encoder.encode(value), let text = String(data: bytes, encoding: .utf8) else {
        return "value could not be displayed; support is unknown"
    }
    return text
}

private func quoted(_ value: String) -> String { encoded(.string(value)) }
