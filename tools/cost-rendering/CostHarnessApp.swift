import Foundation
import PlannerCore
import PlannerUI
import SwiftUI

// A separate test-only host. It never opens a local library or calls a service.
// Launch input selects synthetic data; expected display text stays in the test.
@main
struct CostHarnessApp: App {
    private let scenarios: Result<[CostScenario], Error>

    init() {
        scenarios = Result { try CostScenario.load(arguments: ProcessInfo.processInfo.arguments) }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup { root }.defaultSize(width: 1000, height: 900)
        #else
        WindowGroup { root }
        #endif
    }

    @ViewBuilder private var root: some View {
        switch scenarios {
        case .success(let values): CostScenarioHost(scenarios: values)
        case .failure:
            Text("Cost harness could not load its synthetic scenario.")
                .accessibilityIdentifier("cost-harness-error")
        }
    }
}

private struct CostScenarioHost: View {
    let scenarios: [CostScenario]
    @State private var index = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(verbatim: scenarios[index].id).accessibilityIdentifier("cost-harness-case")
                    Text("Case \(index + 1) of \(scenarios.count)")
                        .accessibilityIdentifier("cost-harness-position")
                }
                Spacer()
                Button("Next fixture") { index += 1 }
                    .disabled(index + 1 == scenarios.count)
                    .accessibilityIdentifier("cost-harness-next")
            }.padding()
            Divider()
            GeometryReader { geometry in
                // One vertical owner contains the production view. A horizontal
                // viewport permits the explicit wide fixture on compact devices.
                ScrollView(.horizontal) {
                    ScrollView(.vertical) {
                        CostCoverageView(summary: scenarios[index].summary,
                            currentBuildID: "build.synthetic", currentBuildRevision: 1,
                            monthlyBudget: scenarios[index].budget, isSynthetic: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .environment(\.dynamicTypeSize, scenarios[index].largeText ? .accessibility3 : .large)
                    }
                    .frame(width: scenarios[index].width ?? geometry.size.width, height: geometry.size.height)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("cost-harness-content")
                }
            }.id(scenarios[index].id)
        }
    }
}

private struct CostScenario {
    let id: String
    let summary: CostSummary?
    let budget: ContractMoney
    var width: CGFloat? = nil
    var largeText = false

    private enum InputError: Error { case unsupportedGroup }

    private static func money(_ amount: String, currency: String = "USD") throws -> ContractMoney {
        try ContractMoney(amount: ContractDecimal(amount), currency: currency)
    }

    private static func summary(amount: String? = "110", coverage: CostCoverage = .complete,
                                unpriced: [String] = [], unsupported: [String] = [],
                                rates: RateApplicability = .current, amountCurrency: String = "USD",
                                revision: Int = 1) throws -> CostSummary {
        try CostSummary(buildID: "build.synthetic", buildRevision: revision, periodDays: 30,
            currency: "USD", total: amount.map { try money($0, currency: amountCurrency) },
            coverage: coverage, unpricedSelectionIDs: unpriced,
            unsupportedMeters: unsupported, rateApplicability: rates)
    }

    static func load(arguments: [String]) throws -> [CostScenario] {
        guard let offset = arguments.firstIndex(of: "--cost-group"), offset + 1 < arguments.count else {
            throw InputError.unsupportedGroup
        }
        let budget = try money("100")
        switch arguments[offset + 1] {
        case "rate-removal":
            // Explicit synthetic projections: the complete 110 includes a 90
            // expensive component and 20 retained priced costs. No rates are
            // calculated here and these values are not canonical-service output.
            return [
                CostScenario(id: "rate-complete", summary: try summary(), budget: budget),
                CostScenario(id: "rate-removed", summary: try summary(amount: "20", coverage: .partial,
                    unpriced: ["sel.expensive"]), budget: budget),
                CostScenario(id: "rate-recovered", summary: try summary(), budget: budget),
            ]
        case "boundaries":
            return [
                CostScenario(id: "absent", summary: nil, budget: budget),
                CostScenario(id: "missing-total", summary: try summary(amount: nil), budget: budget),
                CostScenario(id: "partial-zero", summary: try summary(amount: "0.0000", coverage: .partial,
                    unpriced: ["sel.expensive"]), budget: budget),
                CostScenario(id: "unknown-zero", summary: try summary(amount: "0.0000", coverage: .unknown), budget: budget),
                CostScenario(id: "complete-zero", summary: try summary(amount: "0.0000"), budget: budget),
                CostScenario(id: "unsupported", summary: try summary(amount: "20", coverage: .partial,
                    unsupported: ["meter.synthetic.unsupported"]), budget: budget),
                CostScenario(id: "expired", summary: try summary(rates: .expired), budget: budget),
                CostScenario(id: "unverified", summary: try summary(rates: .unknown), budget: budget),
                CostScenario(id: "mixed-currency", summary: try summary(amountCurrency: "EUR"), budget: budget),
                CostScenario(id: "stale", summary: try summary(unpriced: ["sel.stale"],
                    unsupported: ["meter.stale"], revision: 2), budget: budget),
            ]
        case "layout":
            return [
                CostScenario(id: "compact-exact", summary: try summary(
                    amount: "123456789012345678901234567890.123456789013"),
                    budget: try money("123456789012345678901234567890.123456789012"),
                    width: 375, largeText: true),
                CostScenario(id: "compact-partial", summary: try summary(amount: "20", coverage: .partial,
                    unpriced: ["sel.expensive"]), budget: budget, width: 375, largeText: true),
                CostScenario(id: "wide-partial-details", summary: try summary(amount: "20", coverage: .partial,
                    unpriced: ["sel.expensive"],
                    unsupported: (0..<22).map { String(format: "meter.synthetic.%02d", $0) }),
                    budget: budget, width: 820, largeText: true),
                CostScenario(id: "wide-recovered", summary: try summary(), budget: budget, width: 820, largeText: true),
            ]
        default: throw InputError.unsupportedGroup
        }
    }
}
