import Foundation
import XCTest
@testable import PlannerCore

final class CostCoverageTests: XCTestCase {
    private func money(_ amount: String, _ currency: String = "USD") throws -> ContractMoney {
        try ContractMoney(amount: ContractDecimal(amount), currency: currency)
    }
    private func summary(total: ContractMoney? = nil, coverage: CostCoverage = .complete,
                         unpriced: [String] = [], unsupported: [String] = [],
                         rates: RateApplicability = .current, period: Int = 30,
                         revision: Int = 1, build: String = "build.fixture", currency: String = "USD") throws -> CostSummary {
        try CostSummary(buildID: build, buildRevision: revision, periodDays: period, currency: currency,
                        total: total, coverage: coverage, unpricedSelectionIDs: unpriced,
                        unsupportedMeters: unsupported, rateApplicability: rates)
    }
    private func assess(_ estimate: CostSummary, limit: ContractMoney? = nil) throws -> BudgetAssessment {
        estimate.assessMonthlyBudget(try limit ?? money("100"), currentBuildID: "build.fixture", currentBuildRevision: 1)
    }
    func testCompleteCurrentEstimateUsesExactBudgetBoundary() throws {
        XCTAssertEqual(try assess(summary(total: money("100"))), .satisfied)
        XCTAssertEqual(try assess(summary(total: money("99.999999999999"))), .satisfied)
        XCTAssertEqual(try assess(summary(total: money("100.000000000001"))), .exceeded)
        XCTAssertEqual(try assess(summary(total: money("9007199254740993")), limit: money("9007199254740992")), .exceeded)
    }
    func testMissingMostExpensiveRateCannotMakeBudgetSatisfied() throws {
        // Synthetic canonical service projection: 90 + 20 exceeds 100. Removing
        // the 90 rate leaves a 20 subtotal, with incomplete coverage and an ID.
        XCTAssertEqual(try assess(summary(total: money("110"))), .exceeded)
        let missing = try summary(total: money("20"), coverage: .partial, unpriced: ["sel.expensive"])
        XCTAssertEqual(try assess(missing), .unknown(.incompleteCoverage))
        // Recovery after the canonical rate is restored must use the full total.
        XCTAssertEqual(try assess(summary(total: money("110"))), .exceeded)
    }
    func testIncompleteAndUnmodeledCostsNeverPassEvenAtZero() throws {
        for coverage in [CostCoverage.partial, .unknown] {
            XCTAssertEqual(try assess(summary(total: money("0"), coverage: coverage)), .unknown(.incompleteCoverage))
        }
        XCTAssertEqual(try assess(summary(total: money("0"), unpriced: ["sel.unknown"])), .unknown(.unpricedSelections))
        XCTAssertEqual(try assess(summary(total: money("0"), unsupported: ["egress"])), .unknown(.unsupportedMeters))
        XCTAssertEqual(try assess(summary()), .unknown(.missingTotal))
    }
    func testCurrencyMismatchRemainsTypedUnknown() throws {
        XCTAssertEqual(try assess(summary(total: money("1", "EUR"))), .unknown(.mixedCurrency))
        XCTAssertEqual(try assess(summary(total: money("1")), limit: money("100", "EUR")), .unknown(.mixedCurrency))
        XCTAssertEqual(try assess(summary(total: money("1", "EUR"), currency: "EUR"), limit: money("100", "EUR")), .satisfied)
    }
    func testStalenessPeriodAndRateApplicabilityRemainUnknown() throws {
        XCTAssertEqual(try assess(summary(total: money("1"), revision: 2)), .unknown(.staleBuild))
        XCTAssertEqual(try assess(summary(total: money("1"), build: "build.other")), .unknown(.staleBuild))
        XCTAssertEqual(try assess(summary(total: money("1"), period: 31)), .unknown(.unsupportedPeriod))
        XCTAssertEqual(try assess(summary(total: money("1"), rates: .expired)), .unknown(.expiredRates))
        XCTAssertEqual(try assess(summary(total: money("1"), rates: .unknown)), .unknown(.unverifiedRates))
    }
    func testCanonicallyEquivalentBuildIDsRequireTheirOwnEstimate() throws {
        let composed = "build.caf\u{00e9}"
        let decomposed = "build.cafe\u{0301}"
        XCTAssertEqual(composed, decomposed)
        XCTAssertFalse(composed.utf8.elementsEqual(decomposed.utf8))
        let limit = try money("100")
        let cases: [(String, BudgetAssessment)] = [("0", .satisfied), ("20", .satisfied), ("110", .exceeded)]
        for (issuedBuildID, currentBuildID) in [(composed, decomposed), (decomposed, composed)] {
            for (amount, expected) in cases {
                let estimate = try summary(total: money(amount), build: issuedBuildID)
                XCTAssertEqual(Array(estimate.buildID.utf8), Array(issuedBuildID.utf8))
                XCTAssertEqual(estimate.assessMonthlyBudget(limit, currentBuildID: currentBuildID,
                                                            currentBuildRevision: 1), .unknown(.staleBuild))

                let exactCopy = String(decoding: Array(issuedBuildID.utf8), as: UTF8.self)
                XCTAssertEqual(estimate.assessMonthlyBudget(limit, currentBuildID: exactCopy,
                                                            currentBuildRevision: 1), expected)
                XCTAssertEqual(estimate.assessMonthlyBudget(limit, currentBuildID: exactCopy,
                                                            currentBuildRevision: 2), .unknown(.staleBuild))

                let recovered = try summary(total: money(amount), build: currentBuildID)
                XCTAssertEqual(recovered.assessMonthlyBudget(limit, currentBuildID: currentBuildID,
                                                             currentBuildRevision: 1), expected)
            }
        }
    }
    func testMoneyDecodingValidatesCurrencyAndDecimal() throws {
        for currency in ["usd", "US", "USDD", "123", "ÜSD", "USD\n"] {
            XCTAssertThrowsError(try money("1", currency))
            let payload = try JSONEncoder().encode(["amount": "1", "currency": currency])
            XCTAssertThrowsError(try JSONDecoder().decode(ContractMoney.self, from: payload))
        }
        for json in [#"{"amount":1,"currency":"USD"}"#, #"{"amount":"01","currency":"USD"}"#, #"{"amount":"1"}"#, #"{"amount":"1","currency":"USD","extra":true}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ContractMoney.self, from: Data(json.utf8)))
        }
        let original = try money("1.2300")
        let roundTrip = try JSONDecoder().decode(ContractMoney.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(roundTrip, original)
        XCTAssertEqual(roundTrip.amount.rawValue, "1.2300")
        XCTAssertThrowsError(try JSONDecoder().decode(CostCoverage.self, from: Data(#""estimated""#.utf8)))
    }
}
