import SwiftUI
import PlannerCore

/// Read-only cost coverage for the caller's explicitly selected build revision.
/// The caller must qualify the CostSummary projection upstream. A structural
/// CostEstimateRecord alone does not establish current rates or complete costs.
public struct CostCoverageView: View {
    private let presentation: CostCoveragePresentation
    private let monthlyBudget: ContractMoney?
    private let isSynthetic: Bool

    public init(summary: CostSummary?, currentBuildID: String, currentBuildRevision: Int,
                monthlyBudget: ContractMoney?, isSynthetic: Bool) {
        presentation = CostCoveragePresentation(summary: summary, currentBuildID: currentBuildID,
            currentBuildRevision: currentBuildRevision, monthlyBudget: monthlyBudget)
        self.monthlyBudget = monthlyBudget
        self.isSynthetic = isSynthetic
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isSynthetic {
                Text("Synthetic fixture — not real pricing")
                    .font(.headline).accessibilityIdentifier("costCoverage.synthetic")
            }
            Text(verbatim: presentation.heading)
                .font(.headline).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("costCoverage.status")
            Text(verbatim: presentation.explanation)
                .accessibilityIdentifier("costCoverage.explanation")
            if let amount = presentation.amount {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: presentation.amountLabel)
                    Text(verbatim: amount.currency + " " + amount.amount.rawValue)
                        .font(.title3.monospacedDigit()).textSelection(.enabled)
                        .accessibilityIdentifier("costCoverage.amount")
                }.accessibilityElement(children: .combine)
            } else {
                Text("Amount unknown").accessibilityIdentifier("costCoverage.amountUnknown")
            }
            if let currency = presentation.estimateCurrency,
               let amount = presentation.amount, amount.currency != currency {
                Text(verbatim: "Estimate currency: " + currency + "; reported amount currency: " + amount.currency)
            }
            if let days = presentation.periodDays {
                Text(days > 0 ? "Estimate period: \(days) days" : "Estimate period is unavailable")
            }
            if let rateNotice = presentation.rateNotice { Text(verbatim: rateNotice) }
            if presentation.state == .inconsistent, let coverage = presentation.reportedCoverage {
                Text(verbatim: "Reported coverage: " + coverage.rawValue)
            }
            missingValues("Selections without rates", values: presentation.unpricedSelectionIDs,
                          emptyLabel: "Unidentified selection")
            missingValues("Unsupported usage meters", values: presentation.unsupportedMeters,
                          emptyLabel: "Unidentified meter")

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: presentation.budgetHeading(hasBudget: monthlyBudget != nil))
                    .font(.headline).accessibilityIdentifier("costCoverage.budget")
                if let budget = monthlyBudget {
                    Text(verbatim: "30-day limit: " + budget.currency + " " + budget.amount.rawValue)
                        .textSelection(.enabled)
                }
                Text(verbatim: presentation.budgetExplanation(hasBudget: monthlyBudget != nil))
            }.accessibilityElement(children: .combine)
            Text("Estimates are not exact quotes.").font(.caption)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("costCoverage")
    }

    @ViewBuilder
    private func missingValues(_ title: String, values: [String], emptyLabel: String) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title + " (\(values.count))").font(.subheadline)
                ForEach(Array(values.prefix(20).enumerated()), id: \.offset) { _, value in
                    Text(verbatim: value.isEmpty ? emptyLabel : value).textSelection(.enabled)
                }
                if values.count > 20 {
                    Text("Showing the first 20 of \(values.count). These missing costs prevent a conclusive budget result.")
                }
            }.accessibilityElement(children: .combine)
        }
    }
}
