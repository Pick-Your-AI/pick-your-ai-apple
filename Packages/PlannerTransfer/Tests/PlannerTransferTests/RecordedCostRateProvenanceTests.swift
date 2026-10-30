import Foundation
import PlannerCore
import XCTest
@testable import PlannerTransfer

final class RecordedCostRateProvenanceTests: XCTestCase {
    private typealias Mutation = (path: [String], value: JSONValue?)

    private func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        return try parser.parse()
    }

    private func replacing(_ value: JSONValue, path: ArraySlice<String>, with replacement: JSONValue?) throws -> JSONValue {
        guard let key = path.first else { return try XCTUnwrap(replacement) }
        if var object = value.object {
            if path.count == 1 { object[key] = replacement }
            else { object[key] = try replacing(XCTUnwrap(object[key]), path: path.dropFirst(), with: replacement) }
            return .object(object)
        }
        var array = try XCTUnwrap(value.array)
        let index = try XCTUnwrap(Int(key))
        guard array.indices.contains(index) else { throw TransferError.malformed }
        array[index] = try replacing(array[index], path: path.dropFirst(), with: replacement)
        return .array(array)
    }

    private func input(_ name: String, _ changes: [Mutation] = []) throws -> Data {
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
    private func book(_ changes: [Mutation] = []) throws -> Pricebook {
        try Pricebook.decode(input("pricebook", changes))
    }
    private func inspection(buildChanges: [Mutation] = [], estimateChanges: [Mutation] = [],
                            bookChanges: [Mutation] = []) throws -> RecordedCostRateProvenance {
        try RecordedCostRateProvenance(build: build(buildChanges), estimate: estimate(estimateChanges),
                                      pricebook: book(bookChanges))
    }
    private func bookValue(_ value: Pricebook) throws -> JSONValue {
        var parser = try JSONParser(JSONEncoder().encode(value))
        return try parser.parse()
    }

    func testMatchingReferencesRetainEveryOriginalAndAllLimitations() throws {
        let snapshot = try build(), record = try estimate(), pricebook = try book()
        let result = RecordedCostRateProvenance(build: snapshot, estimate: record, pricebook: pricebook)
        XCTAssertEqual(result.build.value, snapshot.value)
        XCTAssertEqual(result.estimate.value, record.value)
        XCTAssertEqual(try bookValue(XCTUnwrap(result.pricebook)), try bookValue(pricebook))
        XCTAssertEqual(result.inputIssues, [])
        XCTAssertEqual(result.lines.map(\.position), [0, 1])
        XCTAssertEqual(result.lines.map(\.line.value), record.lineItems.map(\.value))
        XCTAssertEqual(result.lines.map(\.candidateSelection?.position), [7, 9])
        XCTAssertEqual(result.lines.map(\.selectionMatchCount), [1, 1])
        XCTAssertEqual(result.lines.map(\.rateMatchCount), [1, 1])
        XCTAssertTrue(result.lines.allSatisfy { $0.issues.isEmpty })
        let rate = try XCTUnwrap(result.lines[0].candidateRate)
        XCTAssertEqual(rate.id, "rate.compute_profile.fixture")
        XCTAssertEqual(rate.catalogItemID, "cat.compute_profile.fixture")
        XCTAssertEqual(rate.catalogItemVersion, "2026.10-demo")
        XCTAssertEqual(rate.unitPrice.amount.rawValue, "0.80")
        XCTAssertEqual(rate.provenance.verificationStatus, .estimated)
        XCTAssertEqual(result.limitations, [.pricebookRevisionNotRecorded, .rateApplicabilityNotAssessed,
                                          .sourceDeclarationsNotVerified, .arithmeticAndCoverageNotAssessed])
    }

    func testMissingPricebookKeepsTheEstimateAndDoesNotInventRates() throws {
        let record = try estimate()
        let result = RecordedCostRateProvenance(build: try build(), estimate: record, pricebook: nil)
        XCTAssertNil(result.pricebook)
        XCTAssertEqual(result.inputIssues, [.pricebookNotSupplied])
        XCTAssertEqual(result.lines.count, 2)
        for row in result.lines {
            XCTAssertNil(row.candidateRate)
            XCTAssertEqual(row.rateMatchCount, 0)
            XCTAssertEqual(row.issues, [.pricebookNotSupplied])
        }
        XCTAssertEqual(result.estimate.value, record.value)
        XCTAssertEqual(result.estimate.total.amount, "578.50")
    }

    func testForeignBuildCannotHideBehindMatchingSelectionIDs() throws {
        let result = try inspection(buildChanges: [(["id"], .string("build.foreign"))])
        XCTAssertEqual(result.inputIssues, [.estimateBuildIDDiffers])
        XCTAssertTrue(result.lines.allSatisfy { $0.issues == [.estimateBuildIDDiffers] })
        XCTAssertEqual(result.lines[0].candidateSelection?.id, "sel_compute_profile")
        XCTAssertEqual(result.build.id, "build.foreign")
        XCTAssertEqual(result.estimate.buildID, "build.fixture.1")
    }

    func testDifferentBuildRevisionAndExplicitRecoveryKeepBothRecords() throws {
        let stale = try inspection(buildChanges: [(["revision"], .number(2))])
        XCTAssertEqual(stale.inputIssues, [.estimateBuildRevisionDiffers])
        XCTAssertTrue(stale.lines.allSatisfy { $0.issues == [.estimateBuildRevisionDiffers] })
        let recovered = try inspection(buildChanges: [(["revision"], .number(2))],
                                       estimateChanges: [(["build_revision"], .number(2))])
        XCTAssertEqual(recovered.inputIssues, [])
        XCTAssertTrue(recovered.lines.allSatisfy { $0.issues.isEmpty })
        XCTAssertEqual(stale.estimate.buildRevision, 1)
        XCTAssertEqual(recovered.estimate.buildRevision, 2)
        XCTAssertEqual(recovered.limitations, stale.limitations)
    }

    func testMissingAndDifferentBuildPricebookLocksAreObservations() throws {
        for (value, issue): (JSONValue?, RecordedCostRateIssue) in [
            (nil, .buildPricebookLockMissing), (.string("prices.other"), .buildPricebookLockDiffers)
        ] {
            let result = try inspection(buildChanges: [(["locks", "pricebook_id"], value)])
            XCTAssertEqual(result.inputIssues, [issue])
            XCTAssertTrue(result.lines.allSatisfy { $0.issues == [issue] })
            XCTAssertEqual(result.build.locks.object?["pricebook_id"], value)
            XCTAssertEqual(result.estimate.pricebookID, "prices.fixture.1")
        }
    }

    func testForeignPricebookDoesNotQualifyTheSameNamedRate() throws {
        let result = try inspection(bookChanges: [(["id"], .string("prices.other"))])
        XCTAssertEqual(result.inputIssues, [.suppliedPricebookIDDiffers])
        XCTAssertTrue(result.lines.allSatisfy { $0.issues == [.suppliedPricebookIDDiffers] })
        XCTAssertEqual(result.lines[0].candidateRate?.id, "rate.compute_profile.fixture")
        XCTAssertEqual(result.pricebook?.id, "prices.other")
        XCTAssertEqual(result.estimate.pricebookID, "prices.fixture.1")
    }

    func testMissingSelectionDoesNotUseAnotherSelectionWithTheSameItem() throws {
        let result = try inspection(estimateChanges: [(["line_items", "0", "selection_id"], .string("sel_absent"))])
        XCTAssertNil(result.lines[0].candidateSelection)
        XCTAssertEqual(result.lines[0].selectionMatchCount, 0)
        XCTAssertEqual(result.lines[0].issues, [.selectionNotFoundInSuppliedBuild])
        XCTAssertNotNil(result.lines[0].candidateRate)
        XCTAssertEqual(result.lines[1].issues, [])
        XCTAssertEqual(result.estimate.lineItems[0].selectionID, "sel_absent")
    }

    func testMissingRateNeverSelectsAnotherRateByItemOrMeter() throws {
        let result = try inspection(estimateChanges: [(["line_items", "0", "price_rate_id"], .string("rate.absent"))])
        XCTAssertNil(result.lines[0].candidateRate)
        XCTAssertEqual(result.lines[0].rateMatchCount, 0)
        XCTAssertEqual(result.lines[0].issues, [.rateNotFoundInSuppliedPricebook])
        XCTAssertEqual(result.lines[1].issues, [])
        let recovered = try inspection()
        XCTAssertEqual(recovered.lines[0].candidateRate?.id, "rate.compute_profile.fixture")
        XCTAssertEqual(recovered.lines[0].issues, [])
        XCTAssertEqual(result.lines[0].line.priceRateID, "rate.absent")
    }

    func testDuplicateSelectionIDsRemainAmbiguousEvenWhenRowsAreIdentical() throws {
        var selections = try XCTUnwrap(fixture("build").object?["selections"]?.array)
        selections.append(selections[7])
        let result = try inspection(buildChanges: [(["selections"], .array(selections))])
        XCTAssertEqual(result.lines[0].selectionMatchCount, 2)
        XCTAssertNil(result.lines[0].candidateSelection)
        XCTAssertEqual(result.lines[0].issues, [.selectionIDAmbiguous])
        XCTAssertEqual(result.lines[1].issues, [])
        XCTAssertEqual(result.build.value.object?["selections"]?.array, selections)
    }

    func testDuplicateRateIDsPreserveConflictingCandidatesWithoutChoosingOne() throws {
        var rates = try XCTUnwrap(fixture("pricebook").object?["rates"]?.array)
        var duplicate = try XCTUnwrap(rates[0].object)
        duplicate["catalog_item_version"] = .string("different-version")
        rates.append(.object(duplicate))
        let result = try inspection(bookChanges: [(["rates"], .array(rates))])
        XCTAssertEqual(result.lines[0].rateMatchCount, 2)
        XCTAssertNil(result.lines[0].candidateRate)
        XCTAssertEqual(result.lines[0].issues, [.rateIDAmbiguous])
        XCTAssertEqual(result.lines[1].issues, [])
        XCTAssertEqual(result.pricebook?.rates.count, 3)
        XCTAssertEqual(result.pricebook?.rates.last?.catalogItemVersion, "different-version")
    }

    func testDuplicateLineIDsRetainIndependentOrderedRows() throws {
        let result = try inspection(estimateChanges: [(["line_items", "1", "id"], .string("line.compute_profile.fixture"))])
        XCTAssertEqual(result.lines.map(\.position), [0, 1])
        XCTAssertEqual(result.lines.map(\.line.id), ["line.compute_profile.fixture", "line.compute_profile.fixture"])
        XCTAssertEqual(result.lines.map(\.candidateRate?.id), ["rate.compute_profile.fixture", "rate.storage.fixture"])
        XCTAssertEqual(result.lines.map(\.line.amount.amount), ["576.00", "2.50"])
        XCTAssertTrue(result.lines.allSatisfy { $0.issues == [.duplicateLineID] })
    }

    func testReorderedInputsJoinByIdentityAndKeepEstimateOrder() throws {
        let selections = try XCTUnwrap(fixture("build").object?["selections"]?.array)
        let rates = try XCTUnwrap(fixture("pricebook").object?["rates"]?.array)
        let lines = try XCTUnwrap(fixture("cost-estimate").object?["line_items"]?.array)
        let result = try inspection(buildChanges: [(["selections"], .array(Array(selections.reversed())))],
            estimateChanges: [(["line_items"], .array(Array(lines.reversed())))],
            bookChanges: [(["rates"], .array(Array(rates.reversed())))])
        XCTAssertEqual(result.lines.map(\.line.id), ["line.storage.fixture", "line.compute_profile.fixture"])
        XCTAssertEqual(result.lines.map(\.candidateRate?.id), ["rate.storage.fixture", "rate.compute_profile.fixture"])
        XCTAssertEqual(result.lines.map(\.candidateSelection?.position), [19, 21])
        XCTAssertTrue(result.lines.allSatisfy { $0.issues.isEmpty })
    }

    func testItemAndVersionDifferencesRetainBothLiteralBindings() throws {
        let result = try inspection(bookChanges: [
            (["rates", "0", "catalog_item_id"], .string("cat.other")),
            (["rates", "0", "catalog_item_version"], .string("other-version")),
        ])
        XCTAssertEqual(result.lines[0].issues, [.catalogItemIDDiffers, .catalogItemVersionDiffers])
        XCTAssertEqual(result.lines[0].candidateSelection?.catalogItemID, "cat.compute_profile.fixture")
        XCTAssertEqual(result.lines[0].candidateRate?.catalogItemID, "cat.other")
        XCTAssertEqual(result.lines[0].candidateSelection?.catalogItemVersion, "2026.10-demo")
        XCTAssertEqual(result.lines[0].candidateRate?.catalogItemVersion, "other-version")
    }

    func testUnicodeEquivalentVersionTextDoesNotCollapse() throws {
        let composed = "version-é", decomposed = "version-e\u{301}"
        XCTAssertEqual(composed, decomposed) // Swift display-string equality is not identity.
        XCTAssertFalse(composed.utf8.elementsEqual(decomposed.utf8))
        let result = try inspection(buildChanges: [(["selections", "7", "catalog_item_version"], .string(composed))],
            bookChanges: [(["rates", "0", "catalog_item_version"], .string(decomposed))])
        XCTAssertEqual(result.lines[0].issues, [.catalogItemVersionDiffers])
        XCTAssertEqual(Array(try XCTUnwrap(result.lines[0].candidateRate).catalogItemVersion.utf8), Array(decomposed.utf8))
        let recovered = try inspection(buildChanges: [(["selections", "7", "catalog_item_version"], .string(decomposed))],
            bookChanges: [(["rates", "0", "catalog_item_version"], .string(decomposed))])
        XCTAssertEqual(recovered.lines[0].issues, [])
    }

    func testMeterDifferenceDoesNotConvertUsage() throws {
        let result = try inspection(bookChanges: [(["rates", "0", "meter"], .string("request"))])
        XCTAssertEqual(result.lines[0].issues, [.meterDiffers])
        XCTAssertEqual(result.lines[0].line.meter, .gpuHour)
        XCTAssertEqual(result.lines[0].candidateRate?.meter, .request)
        XCTAssertEqual(result.lines[0].line.quantity, "720")
        XCTAssertEqual(result.lines[0].line.amount.amount, "576.00")
    }

    func testDecimalSpellingDifferencesAreVisibleWithoutNumericRounding() throws {
        let result = try inspection(bookChanges: [(["rates", "0", "unit_price", "amount"], .string("0.8000"))])
        XCTAssertEqual(try ContractDecimal("0.80"), try ContractDecimal("0.8000"))
        XCTAssertEqual(result.lines[0].issues, [.unitPriceAmountTextDiffers])
        XCTAssertEqual(result.lines[0].line.unitPrice.amount, "0.80")
        XCTAssertEqual(result.lines[0].candidateRate?.unitPrice.amount.rawValue, "0.8000")
    }

    func testNumericUnitPriceDifferenceIsDistinctFromSpellingDifference() throws {
        func issues(recorded: String? = nil, rate: String? = nil) throws -> [RecordedCostRateIssue] {
            var estimateChanges: [Mutation] = [], bookChanges: [Mutation] = []
            if let recorded { estimateChanges.append((["line_items", "0", "unit_price", "amount"], .string(recorded))) }
            if let rate { bookChanges.append((["rates", "0", "unit_price", "amount"], .string(rate))) }
            return try inspection(estimateChanges: estimateChanges, bookChanges: bookChanges).lines[0].issues
        }
        // Same value, different spelling: text code only.
        XCTAssertEqual(try issues(rate: "0.8000"), [.unitPriceAmountTextDiffers])
        XCTAssertEqual(try issues(rate: "0.800000000000"), [.unitPriceAmountTextDiffers])
        XCTAssertEqual(try issues(recorded: "0.8000"), [.unitPriceAmountTextDiffers])
        // Different value (10x, 1/10x, last fractional digit): numeric code only.
        XCTAssertEqual(try issues(rate: "8.00"), [.unitPriceAmountValueDiffers])
        XCTAssertEqual(try issues(rate: "0.08"), [.unitPriceAmountValueDiffers])
        XCTAssertEqual(try issues(recorded: "8.00"), [.unitPriceAmountValueDiffers])
        XCTAssertEqual(try issues(rate: "0.800000000001"), [.unitPriceAmountValueDiffers])
        // Identical spelling reports neither.
        XCTAssertEqual(try issues(recorded: "8.00", rate: "8.00"), [])
        // Both records stay visible and no arithmetic is repaired.
        let tenfold = try inspection(bookChanges: [(["rates", "0", "unit_price", "amount"], .string("8.00"))])
        XCTAssertEqual(tenfold.lines[0].line.unitPrice.amount, "0.80")
        XCTAssertEqual(tenfold.lines[0].candidateRate?.unitPrice.amount.rawValue, "8.00")
        XCTAssertEqual(tenfold.lines[0].line.amount.amount, "576.00")
    }

    func testRecordedRegionDifferenceIsReportedAndAbsenceIsNotADifference() throws {
        let rateDiffers = try inspection(bookChanges: [(["rates", "0", "region"], .string("eu-west-fixture"))])
        XCTAssertEqual(rateDiffers.lines[0].issues, [.rateRegionDiffersFromBuildObjective])
        XCTAssertEqual(rateDiffers.lines[1].issues, [])
        XCTAssertEqual(rateDiffers.lines[0].candidateRate?.region, "eu-west-fixture")
        let objectiveDiffers = try inspection(buildChanges: [(["objectives", "region"], .string("eu-west-fixture"))])
        XCTAssertEqual(objectiveDiffers.lines.map(\.issues), [[.rateRegionDiffersFromBuildObjective],
                                                             [.rateRegionDiffersFromBuildObjective]])
        let absent = try inspection(bookChanges: [(["rates", "0", "region"], nil)])
        XCTAssertEqual(absent.lines[0].issues, [])
        XCTAssertNil(absent.lines[0].candidateRate?.region)
        let caseDiffers = try inspection(bookChanges: [(["rates", "0", "region"], .string("US-EAST-FIXTURE"))])
        XCTAssertEqual(caseDiffers.lines[0].issues, [.rateRegionDiffersFromBuildObjective])
        let missingRate = try inspection(estimateChanges: [(["line_items", "0", "price_rate_id"], .string("rate.absent"))],
            bookChanges: [(["rates", "0", "region"], .string("eu-west-fixture"))])
        XCTAssertNil(missingRate.lines[0].candidateRate)
        XCTAssertEqual(missingRate.lines[0].issues, [.rateNotFoundInSuppliedPricebook])
    }

    func testRecordedValidityWindowIsComparedExactlyWithoutAClock() throws {
        func issues(from: String? = nil, until: String? = nil) throws -> [RecordedCostRateIssue] {
            var changes: [Mutation] = []
            if let from { changes.append((["rates", "0", "valid_from"], .string(from))) }
            if let until { changes.append((["rates", "0", "valid_until"], .string(until))) }
            return try inspection(bookChanges: changes).lines[0].issues
        }
        // The recorded estimate time is 2026-10-16T09:00:00Z.
        XCTAssertEqual(try issues(from: "2026-10-16T09:00:01Z"), [.estimatedAtBeforeRateValidFrom])
        XCTAssertEqual(try issues(until: "2026-10-16T08:59:59Z"), [.rateValidityWindowInverted, .estimatedAtAfterRateValidUntil])
        // Boundaries are not decided; offsets and fractions are compared as exact instants.
        XCTAssertEqual(try issues(until: "2026-10-16T09:00:00Z"), [])
        XCTAssertEqual(try issues(from: "2026-10-16T11:00:00+02:00", until: "2026-10-16T04:00:00-05:00"), [])
        XCTAssertEqual(try issues(from: "2026-10-16T10:00:00+02:00"), [])
        XCTAssertEqual(try issues(from: "2026-10-16T09:00:00.000Z"), [])
        XCTAssertEqual(try issues(from: "2026-10-16T09:00:00.000000001Z"), [.estimatedAtBeforeRateValidFrom])
        XCTAssertEqual(try issues(until: "2026-10-16T08:59:59.999999999Z"), [.rateValidityWindowInverted, .estimatedAtAfterRateValidUntil])
        XCTAssertEqual(try issues(from: "2026-10-16T12:00:00+02:00"), [.estimatedAtBeforeRateValidFrom])
        XCTAssertEqual(try issues(from: "2026-10-16T10:00:00+00:59"), [.estimatedAtBeforeRateValidFrom])
        XCTAssertEqual(try issues(from: "2026-10-16T09:30:00-00:30"), [.estimatedAtBeforeRateValidFrom])
        // Leap-year and month-boundary day arithmetic.
        XCTAssertEqual(try issues(until: "2024-02-29T23:59:59Z"), [.rateValidityWindowInverted, .estimatedAtAfterRateValidUntil])
        XCTAssertEqual(try issues(from: "2026-03-01T00:00:00Z", until: "2026-02-28T23:59:59Z"),
                       [.rateValidityWindowInverted, .estimatedAtAfterRateValidUntil])
        // A reversed recorded window is reported without being repaired.
        let inverted = try inspection(bookChanges: [
            (["rates", "0", "valid_from"], .string("2026-10-17T00:00:00Z")),
            (["rates", "0", "valid_until"], .string("2026-10-15T00:00:00Z")),
        ])
        XCTAssertEqual(inverted.lines[0].issues, [.rateValidityWindowInverted, .estimatedAtBeforeRateValidFrom,
                                                  .estimatedAtAfterRateValidUntil])
        XCTAssertEqual(inverted.lines[1].issues, [])
        XCTAssertEqual(inverted.lines[0].candidateRate?.validFrom, "2026-10-17T00:00:00Z")
        XCTAssertEqual(inverted.lines[0].candidateRate?.validUntil, "2026-10-15T00:00:00Z")
        XCTAssertTrue(inverted.limitations.contains(.rateApplicabilityNotAssessed))
    }

    func testIssueAndLineValuesAreComparable() throws {
        let first = try inspection(bookChanges: [(["rates", "0", "unit_price", "amount"], .string("8.00"))])
        let second = try inspection(bookChanges: [(["rates", "0", "unit_price", "amount"], .string("8.00"))])
        XCTAssertEqual(first.lines, second.lines)
        XCTAssertNotEqual(first.lines[0], first.lines[1])
        XCTAssertEqual(Set(first.lines[0].issues), [.unitPriceAmountValueDiffers])
    }

    func testLargeMoneyTextStaysExactAndDoesNotRepairTotals() throws {
        let amount = String(repeating: "9", count: 200) + ".123456789012"
        let result = try inspection(estimateChanges: [(["line_items", "0", "unit_price", "amount"], .string(amount))],
            bookChanges: [(["rates", "0", "unit_price", "amount"], .string(amount))])
        XCTAssertEqual(result.lines[0].issues, [])
        XCTAssertEqual(result.lines[0].line.unitPrice.amount, amount)
        XCTAssertEqual(result.lines[0].candidateRate?.unitPrice.amount.rawValue, amount)
        XCTAssertEqual(result.lines[0].line.amount.amount, "576.00")
        XCTAssertEqual(result.estimate.total.amount, "578.50")
        XCTAssertTrue(result.limitations.contains(.arithmeticAndCoverageNotAssessed))
    }

    func testCurrencyDifferencesRemainAtTheirOwnRecordAndLine() throws {
        let result = try inspection(estimateChanges: [(["currency"], .string("EUR")),
            (["line_items", "0", "amount", "currency"], .string("CAD"))],
            bookChanges: [(["rates", "0", "unit_price", "currency"], .string("GBP"))])
        XCTAssertEqual(result.inputIssues, [.estimateCurrencyDiffersFromBuild])
        XCTAssertEqual(result.lines[0].issues, [.estimateCurrencyDiffersFromBuild, .unitPriceCurrencyDiffers,
            .lineUnitPriceCurrencyDiffersFromEstimate, .lineAmountCurrencyDiffersFromEstimate])
        XCTAssertEqual(result.lines[0].candidateRate?.unitPrice.currency, "GBP")
        XCTAssertEqual(result.lines[0].line.unitPrice.currency, "USD")
        XCTAssertEqual(result.lines[0].line.amount.currency, "CAD")
        XCTAssertEqual(result.estimate.currency, "EUR")
        XCTAssertEqual(result.build.value.object?["objectives"]?.object?["currency"], .string("USD"))
    }

    func testDisabledSelectionIsRetainedWithoutInventingActivePricing() throws {
        let result = try inspection(buildChanges: [(["selections", "7", "enabled"], .bool(false))])
        XCTAssertEqual(result.lines[0].candidateSelection?.enabled, false)
        XCTAssertEqual(result.lines[0].issues, [.selectionDisabled])
        XCTAssertNotNil(result.lines[0].candidateRate)
        XCTAssertEqual(result.lines[0].line.amount.amount, "576.00")
    }

    func testRegionAndWindowAreReportedWhileSourceConditionsStayExactDeclarations() throws {
        let conditions: [JSONValue] = [.string("regional offer"), .string(""), .string("regional offer")]
        let result = try inspection(bookChanges: [
            (["rates", "0", "region"], .string("different-region-é")),
            (["rates", "0", "valid_from"], .string("2099-01-02T03:04:05+02:00")),
            (["rates", "0", "valid_until"], .string("2000-01-01T00:00:00Z")),
            (["rates", "0", "conditions"], .array(conditions)),
            (["rates", "0", "provenance", "source_uri"], .string("https://example.invalid/rates?version=1")),
            (["rates", "0", "provenance", "verification_status"], .string("verified")),
        ])
        let rate = try XCTUnwrap(result.lines[0].candidateRate)
        XCTAssertEqual(result.lines[0].issues, [.rateRegionDiffersFromBuildObjective, .rateValidityWindowInverted,
            .estimatedAtBeforeRateValidFrom, .estimatedAtAfterRateValidUntil])
        XCTAssertEqual(rate.region, "different-region-é")
        XCTAssertEqual(rate.validFrom, "2099-01-02T03:04:05+02:00")
        XCTAssertEqual(rate.validUntil, "2000-01-01T00:00:00Z")
        XCTAssertEqual(rate.conditions, ["regional offer", "", "regional offer"])
        XCTAssertEqual(rate.provenance.sourceURI, "https://example.invalid/rates?version=1")
        XCTAssertEqual(rate.provenance.checkedAt, "2026-10-16T09:00:00Z")
        XCTAssertEqual(rate.provenance.verificationStatus, .verified) // A reported label only.
        XCTAssertTrue(result.limitations.contains(.rateApplicabilityNotAssessed))
        XCTAssertTrue(result.limitations.contains(.sourceDeclarationsNotVerified))
    }

    func testOptionalAbsenceEmptyTextAndEmptyConditionsRemainDistinct() throws {
        let absent = try inspection(bookChanges: [(["rates", "0", "region"], nil),
            (["rates", "0", "provenance", "notes"], nil)])
        let empty = try inspection(bookChanges: [(["rates", "0", "region"], .string("")),
            (["rates", "0", "conditions"], .array([])), (["rates", "0", "provenance", "notes"], .string(""))])
        XCTAssertNil(absent.lines[0].candidateRate?.region)
        XCTAssertNil(absent.lines[0].candidateRate?.conditions)
        XCTAssertNil(absent.lines[0].candidateRate?.provenance.notes)
        XCTAssertEqual(empty.lines[0].candidateRate?.region, "")
        XCTAssertEqual(empty.lines[0].candidateRate?.conditions, [])
        XCTAssertEqual(empty.lines[0].candidateRate?.provenance.notes, "")
        XCTAssertNil(empty.lines[0].candidateRate?.validUntil)
        XCTAssertNil(empty.lines[0].candidateRate?.provenance.sourceURI)
    }

    func testSamePricebookIDDifferentRevisionNeverProvesTheProducerRevision() throws {
        let first = try inspection()
        let later = try inspection(bookChanges: [(["revision"], .number(2)),
            (["captured_at"], .string("2026-10-19T12:00:00Z")),
            (["rates", "0", "conditions"], .array([.string("new recorded condition")]))])
        XCTAssertEqual(first.inputIssues, [])
        XCTAssertEqual(later.inputIssues, [])
        XCTAssertEqual(first.pricebook?.revision, 1)
        XCTAssertEqual(later.pricebook?.revision, 2)
        XCTAssertEqual(later.pricebook?.capturedAt, "2026-10-19T12:00:00Z")
        XCTAssertEqual(first.estimate.value, later.estimate.value)
        XCTAssertEqual(first.limitations, later.limitations)
        XCTAssertTrue(later.limitations.contains(.pricebookRevisionNotRecorded))
        XCTAssertEqual(later.lines[0].candidateRate?.conditions, ["new recorded condition"])
    }

    func testZeroAndIncludedWordsDoNotEstablishFreeEvidence() throws {
        let result = try inspection(estimateChanges: [(["line_items", "0", "unit_price", "amount"], .string("0.0000"))],
            bookChanges: [(["rates", "0", "unit_price", "amount"], .string("0.0000")),
                (["rates", "0", "conditions"], .array([.string("free and included, as claimed by fixture")])),
                (["rates", "0", "provenance", "verification_status"], .string("unverified"))])
        XCTAssertEqual(result.lines[0].issues, [])
        XCTAssertEqual(result.lines[0].candidateRate?.unitPrice.amount.rawValue, "0.0000")
        XCTAssertEqual(result.lines[0].candidateRate?.provenance.verificationStatus, .unverified)
        XCTAssertNil(result.lines[0].candidateRate?.provenance.sourceURI)
        XCTAssertTrue(result.limitations.contains(.sourceDeclarationsNotVerified))
        XCTAssertTrue(result.limitations.contains(.rateApplicabilityNotAssessed))
    }

    func testEmptyPricedLinesDoNotManufactureRowsForUnpricedSelections() throws {
        let record = try estimate([(["line_items"], .array([])), (["coverage"], .string("partial")),
            (["unpriced_selection_ids"], .array([.string("sel_storage"), .string("sel_absent")]))])
        let result = RecordedCostRateProvenance(build: try build(), estimate: record, pricebook: nil)
        XCTAssertEqual(result.lines.count, 0)
        XCTAssertEqual(result.inputIssues, [.pricebookNotSupplied])
        XCTAssertEqual(result.estimate.unpricedSelectionIDs, ["sel_storage", "sel_absent"])
        XCTAssertEqual(result.estimate.total.amount, "578.50")
        XCTAssertEqual(result.estimate.value, record.value)
    }

    func testPrivateTextAndEveryRecordedSelectionFieldRemainLocalAndUnchanged() throws {
        let result = try inspection(buildChanges: [(["owner_ref"], .string("PRIVATE owner")),
            (["selections", "7", "notes"], .string("PRIVATE selection note"))],
            estimateChanges: [(["warnings"], .array([.string("PRIVATE warning"), .string("PRIVATE warning")])),
                (["line_items", "0", "assumptions"], .array([.string("PRIVATE assumption"), .string("")]))],
            bookChanges: [(["rates", "0", "provenance", "notes"], .string("PRIVATE source note"))])
        XCTAssertEqual(result.lines[0].candidateSelection?.value, result.build.value.object?["selections"]?.array?[7])
        XCTAssertEqual(result.lines[0].candidateSelection?.value.object?["notes"], .string("PRIVATE selection note"))
        XCTAssertEqual(result.lines[0].candidateRate?.provenance.notes, "PRIVATE source note")
        XCTAssertEqual(result.lines[0].line.assumptions, ["PRIVATE assumption", ""])
        XCTAssertEqual(result.estimate.warnings, ["PRIVATE warning", "PRIVATE warning"])
        XCTAssertEqual(try CostEstimateRecord.decode(result.estimate.encoded()).value, result.estimate.value)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: result.build.encoded()).value, result.build.value)
    }

    func testReportedTotalsCoverageUsageAndMethodsAreNotRecomputed() throws {
        let result = try inspection(estimateChanges: [(["total", "amount"], .string("1.0000")),
            (["coverage"], .string("unknown")), (["period_days"], .number(365)),
            (["line_items", "0", "quantity"], .string("0")),
            (["line_items", "0", "amount", "amount"], .string("99999.0")),
            (["line_items", "0", "method"], .string("manual_override")),
            (["line_items", "0", "confidence"], .string("high"))])
        XCTAssertEqual(result.lines[0].issues, [])
        XCTAssertEqual(result.estimate.total.amount, "1.0000")
        XCTAssertEqual(result.estimate.coverage, .unknown)
        XCTAssertEqual(result.estimate.periodDays, 365)
        XCTAssertEqual(result.lines[0].line.quantity, "0")
        XCTAssertEqual(result.lines[0].line.amount.amount, "99999.0")
        XCTAssertEqual(result.lines[0].line.method, .manualOverride)
        XCTAssertEqual(result.lines[0].line.confidence, .high)
        XCTAssertTrue(result.limitations.contains(.arithmeticAndCoverageNotAssessed))
    }

    func testUnreferencedDuplicateRecordsDoNotMakeTheReferencedIDsAmbiguous() throws {
        var selections = try XCTUnwrap(fixture("build").object?["selections"]?.array)
        selections.append(selections[0])
        var rates = try XCTUnwrap(fixture("pricebook").object?["rates"]?.array)
        var other = try XCTUnwrap(rates[0].object); other["id"] = .string("rate.unreferenced")
        rates.append(contentsOf: [.object(other), .object(other)])
        let result = try inspection(buildChanges: [(["selections"], .array(selections))],
                                    bookChanges: [(["rates"], .array(rates))])
        XCTAssertTrue(result.lines.allSatisfy { $0.issues.isEmpty })
        XCTAssertEqual(result.lines.map(\.rateMatchCount), [1, 1])
        XCTAssertEqual(result.lines.map(\.selectionMatchCount), [1, 1])
        XCTAssertEqual(result.pricebook?.rates.count, 4)
        XCTAssertEqual(result.build.value.object?["selections"]?.array?.count, 30)
    }
}
