import PlannerCore
import SwiftUI

/// Presents only analysis whose request and returned pins match the visible
/// build supplied by the containing editor. It never selects from response data.
@MainActor
public struct EvaluationAnalysisView: View {
    private let model: EvaluationAnalysisModel
    private let visibleIdentity: AnalysisIdentity?

    public init(model: EvaluationAnalysisModel, visibleIdentity: AnalysisIdentity?) {
        self.model = model
        self.visibleIdentity = visibleIdentity
    }

    public var body: some View {
        switch model.presentation(for: visibleIdentity) {
        case .current(let report):
            VStack(alignment: .leading, spacing: 12) {
                Text("Analysis for the visible build revision")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                EvaluationReportView(report: report)
            }
            .accessibilityIdentifier("visible-analysis-current")
        case .pending:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().accessibilityHidden(true)
                    Text("Analysis pending for this build revision")
                        .accessibilityIdentifier("visible-analysis-pending-caption")
                }
                Text("Compatibility and readiness remain unknown until a matching report arrives.")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("visible-analysis-pending")
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 8) {
                Text("Current analysis unavailable")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                Text(message(for: reason))
                Text("Compatibility and readiness are unknown.")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("visible-analysis-unavailable")
        }
    }

    private func message(for reason: AnalysisUnavailableReason) -> String {
        guard visibleIdentity != nil else { return "Select a build with supported pinned inputs to view current analysis." }
        switch reason {
        case .notRequested: return "No current evaluation has been requested for these build inputs."
        case .cancelled: return "The evaluation was cancelled. A new request is needed for these build inputs."
        case .failed: return "The evaluation did not complete. A new request is needed for these build inputs."
        case .disconnected: return "The connection was interrupted. Reconnect and request a new evaluation for these build inputs."
        }
    }
}
