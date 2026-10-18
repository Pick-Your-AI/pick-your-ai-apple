import Foundation
import SwiftUI
import PlannerTransfer

/// A local read-only result; every identity/value belongs to its labelled side.
public struct BuildComparisonView: View {
    let comparison: BuildComparison
    let beforeSynthetic: Bool
    let afterSynthetic: Bool
    public init(comparison: BuildComparison, beforeSynthetic: Bool, afterSynthetic: Bool) {
        self.comparison = comparison
        self.beforeSynthetic = beforeSynthetic; self.afterSynthetic = afterSynthetic
    }
    public var body: some View {
        List {
            Section("Before — pinned baseline") {
                identity(comparison.before, synthetic: beforeSynthetic)
            }
            Section("After — selected build") {
                identity(comparison.after, synthetic: afterSynthetic)
            }
            Section("Evidence and applicability") {
                Text(comparison.evidenceNotice).fixedSize(horizontal: false, vertical: true)
                Text("This comparison does not change either build. A matching configuration does not establish compatibility, readiness, or source rights.")
            }
            Section("Configuration differences (\(comparison.differences.count))") {
                if comparison.differences.isEmpty {
                    Text("No configuration differences in objectives, version locks, policy, selections, or relationships.")
                }
                ForEach(Array(comparison.differences.enumerated()), id: \.offset) { _, difference in
                    VStack(alignment: .leading, spacing: 8) {
                        if let kind = difference.selectionKind {
                            Text([difference.tier, kind.replacingOccurrences(of: "_", with: " ")].compactMap { $0 }.joined(separator: " · "))
                                .font(.headline)
                        }
                        Text(difference.path.joined(separator: " › "))
                            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Text("Before: " + ComparisonFieldText.display(difference.before))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("After: " + ComparisonFieldText.display(difference.after))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Compare builds")
        .accessibilityIdentifier("buildComparison")
    }
    private func identity(_ value: ComparedBuildIdentity, synthetic: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value.name).font(.headline)
            Text("Build ID: " + value.id).font(.caption).textSelection(.enabled)
            Text("Revision: " + value.revision)
            Text(synthetic ? "Marked synthetic fixture" : "Data qualification unknown")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
