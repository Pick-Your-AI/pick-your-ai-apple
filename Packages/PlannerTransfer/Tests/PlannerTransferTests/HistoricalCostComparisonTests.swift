import Foundation
import XCTest
@testable import PlannerTransfer

final class HistoricalCostComparisonTests: XCTestCase {
    private typealias Mutation = (path: [String], value: JSONValue)

    private func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        return try parser.parse()
    }

    private func replacing(_ value: JSONValue, path: ArraySlice<String>, with replacement: JSONValue) throws -> JSONValue {
        guard let key = path.first else { return replacement }
        if var object = value.object {
            let prior = try XCTUnwrap(object[key])
            object[key] = try replacing(prior, path: path.dropFirst(), with: replacement)
            return .object(object)
        }
        var array = try XCTUnwrap(value.array)
        let index = try XCTUnwrap(Int(key))
        guard array.indices.contains(index) else { throw TransferError.malformed }
        array[index] = try replacing(array[index], path: path.dropFirst(), with: replacement)
        return .array(array)
    }

    private func input(_ name: String, _ changes: [Mutation]) throws -> Data {
        var value = try fixture(name)
        for change in changes { value = try replacing(value, path: change.path[...], with: change.value) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func build(_ changes: [Mutation] = []) throws -> BuildSnapshot {
        try BuildTransfer.snapshot(fromDraftJSON: input("build", changes))
    }

    private func estimate(_ changes: [Mutation] = []) throws -> CostEstimateRecord {
        try CostEstimateRecord.decode(input("cost-estimate", changes))
    }

    private func scenario(buildChanges: [Mutation] = [], estimateChanges: [Mutation] = []) throws -> HistoricalCostScenario {
        try HistoricalCostScenario(build: build(buildChanges), estimate: estimate(estimateChanges))
    }

    private func later(buildChanges: [Mutation] = [], estimateChanges: [Mutation] = []) throws -> HistoricalCostScenario {
        try scenario(buildChanges: buildChanges,
                     estimateChanges: [(["id"], .string("estimate.fixture.2"))] + estimateChanges)
    }

    func testSameHistoricalRecordRetainsBothInputsWithoutInventingQualification() throws {
        let original = try scenario()
        let comparison = try HistoricalCostComparison.compare(original, original)
        XCTAssertEqual(comparison.before, original)
        XCTAssertEqual(comparison.after, original)
        XCTAssertEqual(comparison.changedFields, [])
        XCTAssertEqual(comparison.lineChanges, [])
        XCTAssertEqual(comparison.cautions, [.reportedValuesOnly])
        XCTAssertEqual(comparison.before.estimate.coverage, .complete)
        XCTAssertEqual(comparison.before.estimate.total.amount, "578.50")
    }

    func testDifferentPricebooksCurrenciesAndPeriodsRemainSeparate() throws {
        let before = try scenario()
        var changes: [Mutation] = [
            (["build_revision"], .number(2)), (["pricebook_id"], .string("prices.fixture.2")),
            (["period_days"], .number(365)), (["currency"], .string("EUR")),
            (["estimated_at"], .string("2026-10-18T08:30:00+02:00")),
        ]
        for field in ["subtotal", "tax", "total"] { changes.append(([field, "currency"], .string("EUR"))) }
        for line in ["0", "1"] {
            for field in ["unit_price", "amount"] {
                changes.append((["line_items", line, field, "currency"], .string("EUR")))
            }
        }
        let after = try later(buildChanges: [(["revision"], .number(2)),
            (["locks", "pricebook_id"], .string("prices.fixture.2"))], estimateChanges: changes)
        let result = try HistoricalCostComparison.compare(before, after)
        XCTAssertEqual(result.before.estimate.currency, "USD")
        XCTAssertEqual(result.after.estimate.currency, "EUR")
        XCTAssertEqual(result.before.estimate.periodDays, Decimal(30))
        XCTAssertEqual(result.after.estimate.periodDays, Decimal(365))
        XCTAssertEqual(result.after.estimate.estimatedAt, "2026-10-18T08:30:00+02:00")
        XCTAssertEqual(result.cautions, [.reportedValuesOnly, .differentPricebooks, .differentCurrencies, .differentPeriods])
        for field: HistoricalCostField in [.buildRevision, .buildLocks, .pricebookID, .estimatedAt, .periodDays, .currency] {
            XCTAssertTrue(result.changedFields.contains(field), field.rawValue)
        }
        XCTAssertEqual(result.before, before)
        XCTAssertEqual(result.after, after)
    }

    func testAbsentLinesStayAbsentAndPartialZeroIsStillUnqualified() throws {
        let before = try scenario()
        let after = try later(estimateChanges: [
            (["line_items"], .array([])), (["coverage"], .string("partial")),
            (["total", "amount"], .string("0.0000")),
            (["unpriced_selection_ids"], .array([.string("sel_compute_profile"), .string("sel_storage")])),
        ])
        let result = try HistoricalCostComparison.compare(before, after)
        XCTAssertEqual(result.lineChanges.count, 2)
        XCTAssertTrue(result.lineChanges.allSatisfy { $0.before != nil && $0.after == nil })
        XCTAssertEqual(result.after.estimate.total.amount, "0.0000")
        XCTAssertEqual(result.cautions, [.reportedValuesOnly, .afterIncompleteCoverage, .afterUnpricedSelections])
        XCTAssertTrue(result.changedFields.contains(.coverage))
        XCTAssertTrue(result.changedFields.contains(.unpricedSelectionIDs))
        XCTAssertEqual(result.before.estimate.lineItems.count, 2)
    }

    func testLineChangesRetainUsageRateMethodConfidenceAndAssumptions() throws {
        let before = try scenario()
        let after = try later(estimateChanges: [
            (["line_items", "0", "quantity"], .string("600.0000")),
            (["line_items", "0", "price_rate_id"], .string("rate.compute_profile.new")),
            (["line_items", "0", "unit_price", "amount"], .string("0.750000")),
            (["line_items", "0", "amount", "amount"], .string("450.0000")),
            (["line_items", "0", "method"], .string("manual_override")),
            (["line_items", "0", "confidence"], .string("high")),
            (["line_items", "0", "assumptions"], .array([.string("SYNTHETIC revised usage assumption")])),
        ])
        let result = try HistoricalCostComparison.compare(before, after)
        let change = try XCTUnwrap(result.lineChanges.first)
        XCTAssertEqual(result.lineChanges.count, 1)
        XCTAssertEqual(change.id, "line.compute_profile.fixture")
        XCTAssertEqual(change.before?.quantity, "720")
        XCTAssertEqual(change.before?.priceRateID, "rate.compute_profile.fixture")
        XCTAssertEqual(change.after?.quantity, "600.0000")
        XCTAssertEqual(change.after?.priceRateID, "rate.compute_profile.new")
        XCTAssertEqual(change.after?.unitPrice.amount, "0.750000")
        XCTAssertEqual(change.after?.amount.amount, "450.0000")
        XCTAssertEqual(change.after?.method, .manualOverride)
        XCTAssertEqual(change.after?.confidence, .high)
        XCTAssertEqual(change.after?.assumptions, ["SYNTHETIC revised usage assumption"])
        // Supplied inconsistent arithmetic is exposed as reported, never repaired.
        XCTAssertEqual(result.after.estimate.total.amount, "578.50")
        XCTAssertEqual(result.cautions, [.reportedValuesOnly])
    }

    func testLineOrderDoesNotManufactureChangesAndIDChangeIsRemovalPlusAddition() throws {
        let before = try scenario()
        let lines = try XCTUnwrap(fixture("cost-estimate").object?["line_items"]?.array)
        let reordered = try later(estimateChanges: [(["line_items"], .array(Array(lines.reversed())))])
        let sameLines = try HistoricalCostComparison.compare(before, reordered)
        XCTAssertEqual(sameLines.lineChanges, [])
        XCTAssertEqual(sameLines.changedFields, [.estimateID])
        let renamed = try later(estimateChanges: [(["line_items", "0", "id"], .string("line.z.new"))])
        let result = try HistoricalCostComparison.compare(before, renamed)
        XCTAssertEqual(result.lineChanges.map(\.id), ["line.compute_profile.fixture", "line.z.new"])
        XCTAssertNotNil(result.lineChanges[0].before)
        XCTAssertNil(result.lineChanges[0].after)
        XCTAssertNil(result.lineChanges[1].before)
        XCTAssertNotNil(result.lineChanges[1].after)
    }

    func testWrongBuildAndObsoleteRevisionCannotBindToVisibleSnapshot() throws {
        for changes: [Mutation] in [[(["build_id"], .string("build.other"))], [(["build_revision"], .number(2))]] {
            let record = try estimate(changes)
            XCTAssertThrowsError(try HistoricalCostScenario(build: build(), estimate: record)) {
                XCTAssertEqual($0 as? HistoricalCostComparisonError, .buildMismatch)
            }
        }
    }

    func testPricebookMustMatchItsOwnSavedBuildLock() throws {
        let record = try estimate([(["pricebook_id"], .string("prices.other"))])
        XCTAssertThrowsError(try HistoricalCostScenario(build: build(), estimate: record)) {
            XCTAssertEqual($0 as? HistoricalCostComparisonError, .pricebookMismatch)
        }
        let matching = try HistoricalCostScenario(build: build([(["locks", "pricebook_id"], .string("prices.other"))]),
                                                 estimate: record)
        XCTAssertEqual(matching.estimate.pricebookID, "prices.other")
    }

    func testUnknownPricedAndUnpricedSelectionsRejectWithoutChangingDecoder() throws {
        for changes: [Mutation] in [
            [(["line_items", "0", "selection_id"], .string("sel_absent"))],
            [(["unpriced_selection_ids"], .array([.string("sel_absent")]))],
        ] {
            let record = try estimate(changes)
            XCTAssertThrowsError(try HistoricalCostScenario(build: build(), estimate: record)) {
                XCTAssertEqual($0 as? HistoricalCostComparisonError, .unknownSelection)
            }
        }
    }

    func testDuplicateLineIDsFailComparisonAdmissionRatherThanOverwrite() throws {
        let record = try estimate([(["line_items", "1", "id"], .string("line.compute_profile.fixture"))])
        XCTAssertEqual(record.lineItems.count, 2) // The unchanged frozen decoder admits these bytes.
        XCTAssertThrowsError(try HistoricalCostScenario(build: build(), estimate: record)) {
            XCTAssertEqual($0 as? HistoricalCostComparisonError, .ambiguousLineIdentity)
        }
    }

    func testDuplicateBuildSelectionIDsFailComparisonAdmission() throws {
        var selections = try XCTUnwrap(fixture("build").object?["selections"]?.array)
        selections.append(try XCTUnwrap(selections.first))
        let snapshot = try build([(["selections"], .array(selections))])
        XCTAssertThrowsError(try HistoricalCostScenario(build: snapshot, estimate: estimate())) {
            XCTAssertEqual($0 as? HistoricalCostComparisonError, .ambiguousSelectionIdentity)
        }
    }

    func testOneEstimateIdentityCannotHideChangedHistoricalContents() throws {
        let before = try scenario()
        let after = try scenario(estimateChanges: [(["total", "amount"], .string("1.00"))])
        XCTAssertThrowsError(try HistoricalCostComparison.compare(before, after)) {
            XCTAssertEqual($0 as? HistoricalCostComparisonError, .conflictingEstimateIdentity)
        }
        XCTAssertEqual(before.estimate.total.amount, "578.50")
        XCTAssertEqual(after.estimate.total.amount, "1.00")
    }

    func testOneBuildRevisionCannotCarryConflictingSavedConfiguration() throws {
        let before = try scenario()
        let after = try later(buildChanges: [(["objectives", "requests_per_day"], .number(201))])
        XCTAssertThrowsError(try HistoricalCostComparison.compare(before, after)) {
            XCTAssertEqual($0 as? BuildComparisonError, .conflictingRevisionIdentity)
        }
        var selections = try XCTUnwrap(before.build.value.object?["selections"]?.array)
        selections.reverse()
        let reordered = try later(buildChanges: [(["selections"], .array(selections))])
        XCTAssertNoThrow(try HistoricalCostComparison.compare(before, reordered))
    }

    func testReportedCompleteWithUnpricedSelectionsRemainsExplicitlyUnqualified() throws {
        let after = try later(estimateChanges: [(["unpriced_selection_ids"], .array([.string("sel_storage")]))])
        let result = try HistoricalCostComparison.compare(scenario(), after)
        XCTAssertEqual(result.after.estimate.coverage, .complete)
        XCTAssertEqual(result.cautions, [.reportedValuesOnly, .afterUnpricedSelections])
        XCTAssertEqual(result.after.estimate.unpricedSelectionIDs, ["sel_storage"])
    }

    func testEveryNestedCurrencyMismatchRemainsVisibleOnTheCorrectSide() throws {
        let paths = [["subtotal", "currency"], ["tax", "currency"], ["total", "currency"],
                     ["line_items", "0", "unit_price", "currency"], ["line_items", "1", "amount", "currency"]]
        for path in paths {
            let mixed = try later(estimateChanges: [(path, .string("EUR"))])
            let forward = try HistoricalCostComparison.compare(scenario(), mixed)
            XCTAssertEqual(forward.cautions, [.reportedValuesOnly, .afterMixedCurrencies])
            let reverse = try HistoricalCostComparison.compare(mixed, scenario())
            XCTAssertEqual(reverse.cautions, [.reportedValuesOnly, .beforeMixedCurrencies])
            XCTAssertEqual(forward.after.estimate, mixed.estimate)
        }
    }

    func testExactUnicodeAndLongDecimalTextSurviveChangesAndLocalSerialization() throws {
        let long = String(repeating: "9", count: 200) + ".123456789012"
        let before = try scenario(estimateChanges: [
            (["line_items", "0", "assumptions"], .array([.string("Caf\u{e9}")])),
            (["total", "amount"], .string(long)),
        ])
        let after = try later(estimateChanges: [
            (["line_items", "0", "assumptions"], .array([.string("Cafe\u{301}")])),
            (["total", "amount"], .string(long)),
            (["tax", "amount"], .string("0.000000000000")),
        ])
        let result = try HistoricalCostComparison.compare(before, after)
        XCTAssertEqual(result.lineChanges.count, 1)
        XCTAssertFalse(try XCTUnwrap(result.lineChanges[0].before?.assumptions.first).utf8.elementsEqual(
            try XCTUnwrap(result.lineChanges[0].after?.assumptions.first).utf8))
        XCTAssertEqual(result.before.estimate.total.amount, long)
        XCTAssertEqual(result.after.estimate.total.amount, long)
        XCTAssertFalse(result.changedFields.contains(.total))
        XCTAssertTrue(result.changedFields.contains(.tax))
        for side in [result.before, result.after] {
            let reopened = try CostEstimateRecord.decode(side.estimate.encoded())
            XCTAssertEqual(reopened, side.estimate)
            XCTAssertEqual(reopened.pricebookID, side.build.locks.object?["pricebook_id"]?.string)
            XCTAssertEqual(reopened.total.amount, long)
            XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: side.build.encoded()), side.build)
        }
    }

    func testDifferentHistoricalBuildsKeepTheirOwnSelectionBindings() throws {
        let before = try scenario()
        let after = try later(buildChanges: [(["id"], .string("build.other")), (["revision"], .number(5))],
                              estimateChanges: [(["build_id"], .string("build.other")), (["build_revision"], .number(5))])
        let result = try HistoricalCostComparison.compare(before, after)
        XCTAssertEqual(result.before.build.id, "build.fixture.1")
        XCTAssertEqual(result.after.build.id, "build.other")
        XCTAssertEqual(result.after.estimate.buildRevision, Decimal(5))
        XCTAssertTrue(result.changedFields.contains(.buildID))
        XCTAssertTrue(result.changedFields.contains(.buildRevision))
        XCTAssertEqual(result.lineChanges, [])
        XCTAssertEqual(result.before, before)
        XCTAssertEqual(result.after, after)
    }
}
