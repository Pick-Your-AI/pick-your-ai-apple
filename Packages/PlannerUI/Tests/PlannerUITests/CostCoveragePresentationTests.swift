import XCTest
import PlannerCore
@testable import PlannerUI

final class CostCoveragePresentationTests: XCTestCase {
    private func money(_ amount: String, _ currency: String = "USD") throws -> ContractMoney {
        try ContractMoney(amount: ContractDecimal(amount), currency: currency)
    }

    private func summary(amount: String? = "110", currency: String = "USD", amountCurrency: String = "USD",
                         coverage: CostCoverage = .complete, unpriced: [String] = [], unsupported: [String] = [],
                         rates: RateApplicability = .current, period: Int = 30,
                         buildID: String = "build.synthetic", revision: Int = 1) throws -> CostSummary {
        try CostSummary(buildID: buildID, buildRevision: revision, periodDays: period, currency: currency,
                        total: amount.map { try money($0, amountCurrency) }, coverage: coverage,
                        unpricedSelectionIDs: unpriced, unsupportedMeters: unsupported, rateApplicability: rates)
    }

    private func presentation(_ summary: CostSummary?, budget: ContractMoney? = nil,
                              buildID: String = "build.synthetic", revision: Int = 1) throws -> CostCoveragePresentation {
        CostCoveragePresentation(summary: summary, currentBuildID: buildID, currentBuildRevision: revision,
                                 monthlyBudget: try budget ?? money("100"))
    }

    func testRemovingMostExpensiveRateShowsPartialAndNeverWithinBudget() throws {
        let complete = try presentation(summary())
        XCTAssertEqual(complete.state, .complete)
        XCTAssertEqual(complete.budgetAssessment, .exceeded)
        let partial = try presentation(summary(amount: "20", coverage: .partial, unpriced: ["sel.expensive"]))
        XCTAssertEqual(partial.state, .partial)
        XCTAssertEqual(partial.heading, "Partial cost estimate")
        XCTAssertEqual(partial.amountLabel, "Reported amount for priced costs")
        XCTAssertEqual(partial.amount, try money("20"))
        XCTAssertEqual(partial.unpricedSelectionIDs, ["sel.expensive"])
        XCTAssertEqual(partial.budgetAssessment, .unknown(.incompleteCoverage))
        XCTAssertEqual(partial.budgetHeading(hasBudget: true), "Budget status unknown")
        let recovered = try presentation(summary())
        XCTAssertEqual(recovered, complete)
    }

    func testAbsentEstimateAndAbsentAmountNeverInventZero() throws {
        let absent = try presentation(nil)
        XCTAssertEqual(absent.state, .unavailable)
        XCTAssertNil(absent.amount)
        XCTAssertEqual(absent.budgetHeading(hasBudget: true), "Budget status unknown")
        let missingAmount = try presentation(summary(amount: nil))
        XCTAssertEqual(missingAmount.state, .unknown)
        XCTAssertNil(missingAmount.amount)
        XCTAssertEqual(missingAmount.budgetAssessment, .unknown(.missingTotal))
    }

    func testLiteralZeroKeepsItsCoverageAndRateConditions() throws {
        for coverage in [CostCoverage.partial, .unknown] {
            let value = try presentation(summary(amount: "0.0000", coverage: coverage))
            XCTAssertEqual(value.amount?.amount.rawValue, "0.0000")
            XCTAssertEqual(value.budgetAssessment, .unknown(.incompleteCoverage))
            XCTAssertNotEqual(value.state, .complete)
            XCTAssertEqual(value.budgetHeading(hasBudget: true), "Budget status unknown")
        }
        let complete = try presentation(summary(amount: "0.0000"))
        XCTAssertEqual(complete.budgetAssessment, .satisfied)
        XCTAssertEqual(complete.budgetHeading(hasBudget: true), "Within estimated budget")
        let unverified = try presentation(summary(amount: "0.0000", rates: .unknown))
        XCTAssertEqual(unverified.budgetAssessment, .unknown(.unverifiedRates))
        XCTAssertEqual(unverified.rateNotice, "Rate applicability is unverified")
    }

    func testContradictoryCompleteCoverageRemainsVisibleAndCannotPass() throws {
        for (unpriced, unsupported) in [(["sel.missing"], [String]()), ([String](), ["network_egress"])] {
            let value = try presentation(summary(amount: "1", unpriced: unpriced, unsupported: unsupported))
            XCTAssertEqual(value.state, .inconsistent)
            XCTAssertEqual(value.reportedCoverage, .complete)
            XCTAssertEqual(value.amountLabel, "Reported amount")
            XCTAssertEqual(value.unpricedSelectionIDs, unpriced)
            XCTAssertEqual(value.unsupportedMeters, unsupported)
            XCTAssertEqual(value.budgetHeading(hasBudget: true), "Budget status unknown")
        }
    }

    func testOtherOrInvalidVisibleRevisionSuppressesReceivedAmountAndDetails() throws {
        let value = try summary(amount: "900", coverage: .partial, unpriced: ["sel.private"], unsupported: ["private_meter"])
        for (buildID, revision) in [("build.other", 1), ("build.synthetic", 2), ("", 1), ("build.synthetic", 0)] {
            let display = try presentation(value, buildID: buildID, revision: revision)
            XCTAssertEqual(display.state, .differentRevision)
            XCTAssertNil(display.amount)
            XCTAssertNil(display.estimateCurrency)
            XCTAssertNil(display.periodDays)
            XCTAssertEqual(display.unpricedSelectionIDs, [])
            XCTAssertEqual(display.unsupportedMeters, [])
            XCTAssertEqual(display.budgetHeading(hasBudget: true), "Budget status unknown")
        }
        XCTAssertEqual(value.total, try money("900"))
        XCTAssertEqual(value.unpricedSelectionIDs, ["sel.private"])
    }

    func testCurrenciesArePreservedWithoutConversionOrAggregation() throws {
        let conflict = try presentation(summary(amount: "1.2300", amountCurrency: "EUR"))
        XCTAssertEqual(conflict.state, .inconsistent)
        XCTAssertEqual(conflict.amount, try money("1.2300", "EUR"))
        XCTAssertEqual(conflict.estimateCurrency, "USD")
        XCTAssertEqual(conflict.budgetAssessment, .unknown(.mixedCurrency))
        let differentBudget = try presentation(summary(amount: "1"), budget: money("100", "EUR"))
        XCTAssertEqual(differentBudget.budgetAssessment, .unknown(.mixedCurrency))
        XCTAssertEqual(differentBudget.budgetHeading(hasBudget: true), "Budget status unknown")
    }

    func testExactAmountsRetainTrailingZerosAndBeyondBinaryPrecisionBudgetBoundary() throws {
        let value = try presentation(summary(amount: "9007199254740993.0000"), budget: money("9007199254740992"))
        XCTAssertEqual(value.amount?.amount.rawValue, "9007199254740993.0000")
        XCTAssertEqual(value.budgetAssessment, .exceeded)
        XCTAssertEqual(value.budgetHeading(hasBudget: true), "Above estimated budget")
        let boundary = try presentation(summary(amount: "100.000000000000"))
        XCTAssertEqual(boundary.budgetAssessment, .satisfied)
        XCTAssertEqual(boundary.amount?.amount.rawValue, "100.000000000000")
        XCTAssertEqual(try presentation(summary(amount: "100.000000000001")).budgetAssessment, .exceeded)
    }

    func testExpiredUnverifiedAndNonMonthlyEstimatesKeepBudgetUnknown() throws {
        let expired = try presentation(summary(amount: "1", rates: .expired))
        XCTAssertEqual(expired.budgetAssessment, .unknown(.expiredRates))
        XCTAssertEqual(expired.rateNotice, "Rate conditions have expired")
        let unverified = try presentation(summary(amount: "1", rates: .unknown))
        XCTAssertEqual(unverified.budgetAssessment, .unknown(.unverifiedRates))
        for days in [0, -1, 1, 29, 31] {
            let value = try presentation(summary(amount: "1", period: days))
            XCTAssertEqual(value.periodDays, days)
            XCTAssertEqual(value.budgetAssessment, .unknown(.unsupportedPeriod))
            XCTAssertEqual(value.budgetHeading(hasBudget: true), "Budget status unknown")
        }
    }

    func testNoBudgetDoesNotCreateAComparison() throws {
        let summaries: [CostSummary?] = [nil, try summary(amount: "1")]
        for supplied in summaries {
            let display = CostCoveragePresentation(summary: supplied, currentBuildID: "build.synthetic",
                currentBuildRevision: 1, monthlyBudget: nil)
            XCTAssertNil(display.budgetAssessment)
            XCTAssertEqual(display.budgetHeading(hasBudget: false), "No monthly budget set")
        }
    }

    func testMissingCostDetailsKeepOriginalOrderDuplicatesAndEmptyEntries() throws {
        let ids = ["sel.unknown", "", "sel.unknown"] + (0..<25).map { "sel.\($0)" }
        let meters = ["unknown", "", "gpu_hour"]
        let value = try presentation(summary(amount: "20", coverage: .partial, unpriced: ids, unsupported: meters))
        XCTAssertEqual(value.unpricedSelectionIDs, ids)
        XCTAssertEqual(value.unsupportedMeters, meters)
        XCTAssertEqual(value.budgetAssessment, .unknown(.incompleteCoverage))
    }
}
