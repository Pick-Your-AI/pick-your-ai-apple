import Foundation
import XCTest
@testable import PlannerTransfer

private struct CostVector: Decodable {
    let name: String
    let path: [String]
    let operation: String
    let json: String?
    let canonicalValid: Bool
    let clientValid: Bool
}

final class CostEstimateRecordTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "cost-estimate", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func string(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try XCTUnwrap(String(data: encoder.encode(value), encoding: .utf8))
    }

    // Preserve raw replacement JSON so integral-number subset cases reach the
    // public decoder without an intervening JSONSerialization/Double conversion.
    private func render(_ value: JSONValue, path: ArraySlice<String>, replacement: String?, remove: Bool) throws -> String {
        guard let key = path.first else { return try XCTUnwrap(replacement) }
        if let object = value.object {
            var keys = Set(object.keys)
            if path.count == 1 && !remove { keys.insert(key) }
            guard keys.contains(key) else { throw TransferError.malformed }
            let fields: [String] = try keys.sorted().compactMap { current in
                if current == key && path.count == 1 && remove { return nil }
                let content: String
                if current == key {
                    if path.count == 1 { content = try XCTUnwrap(replacement) }
                    else { content = try render(XCTUnwrap(object[current]), path: path.dropFirst(), replacement: replacement, remove: remove) }
                } else { content = try string(XCTUnwrap(object[current])) }
                return try string(.string(current)) + ":" + content
            }
            return "{" + fields.joined(separator: ",") + "}"
        }
        let array = try XCTUnwrap(value.array)
        let index = try XCTUnwrap(Int(key))
        guard array.indices.contains(index) else { throw TransferError.malformed }
        let elements: [String] = try array.enumerated().compactMap { current, item in
            if current == index {
                if path.count == 1 { return remove ? nil : try XCTUnwrap(replacement) }
                return try render(item, path: path.dropFirst(), replacement: replacement, remove: remove)
            }
            return try string(item)
        }
        return "[" + elements.joined(separator: ",") + "]"
    }

    private func mutated(_ data: Data, path: [String], json: String? = nil, remove: Bool = false) throws -> Data {
        var parser = try JSONParser(data)
        return try Data(render(parser.parse(), path: path[...], replacement: json, remove: remove).utf8)
    }

    func testCanonicalRecordRetainsEveryFieldAndDecimalSpelling() throws {
        let data = try fixture()
        let record = try CostEstimateRecord.decode(data)
        XCTAssertEqual(record.id, "estimate.fixture.1")
        XCTAssertEqual(record.buildID, "build.fixture.1")
        XCTAssertEqual(record.buildRevision, Decimal(1))
        XCTAssertEqual(record.pricebookID, "prices.fixture.1")
        XCTAssertEqual(record.estimatedAt, "2026-10-16T09:00:00Z")
        XCTAssertEqual(record.periodDays, Decimal(30))
        XCTAssertEqual(record.currency, "USD")
        XCTAssertEqual(record.lineItems.count, 2)
        let line = try XCTUnwrap(record.lineItems.first)
        XCTAssertEqual(line.id, "line.compute_profile.fixture")
        XCTAssertEqual(line.selectionID, "sel_compute_profile")
        XCTAssertEqual(line.priceRateID, "rate.compute_profile.fixture")
        XCTAssertEqual(line.meter, .gpuHour)
        XCTAssertEqual(line.quantity, "720")
        XCTAssertEqual(line.unitPrice.amount, "0.80")
        XCTAssertEqual(line.unitPrice.currency, "USD")
        XCTAssertEqual(line.amount.amount, "576.00")
        XCTAssertEqual(line.amount.currency, "USD")
        XCTAssertEqual(line.method, .workloadProjection)
        XCTAssertEqual(line.confidence, .low)
        XCTAssertEqual(line.assumptions, ["FIXTURE ONLY: usage and pricing are illustrative."])
        XCTAssertEqual(record.lineItems[1].meter, .storageGBMonth)
        XCTAssertEqual(record.subtotal.amount, "578.50")
        XCTAssertEqual(record.tax.amount, "0.00")
        XCTAssertEqual(record.total.amount, "578.50")
        XCTAssertEqual([record.subtotal.currency, record.tax.currency, record.total.currency], ["USD", "USD", "USD"])
        XCTAssertEqual(record.coverage, .complete)
        XCTAssertEqual(record.unpricedSelectionIDs, [])
        XCTAssertEqual(record.warnings, ["Example treats non-metered test fixtures as included; does not estimate real licensing, taxes, network egress or training usage."])
        var parser = try JSONParser(data)
        XCTAssertEqual(record.value, try parser.parse())
        XCTAssertEqual(try CostEstimateRecord.decode(record.encoded()), record)
    }

    func testSharedCanonicalCostVectorsUseActualRawNumberTokens() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "cost-conformance", withExtension: "json"))
        let vectors = try JSONDecoder().decode([CostVector].self, from: Data(contentsOf: url))
        let original = try fixture()
        XCTAssertEqual(vectors.count, 520)
        var meters = Set<CostEstimateMeter>()
        var methods = Set<CostEstimateMethod>()
        var confidence = Set<CostEstimateConfidence>()
        var coverage = Set<CostEstimateCoverage>()
        for vector in vectors {
            let data = vector.operation == "none" ? original : try mutated(original, path: vector.path, json: vector.json, remove: vector.operation == "remove")
            do {
                let record = try CostEstimateRecord.decode(data)
                XCTAssertTrue(vector.clientValid, vector.name)
                meters.formUnion(record.lineItems.map(\.meter))
                methods.formUnion(record.lineItems.map(\.method))
                confidence.formUnion(record.lineItems.map(\.confidence))
                coverage.insert(record.coverage)
                var parser = try JSONParser(data)
                XCTAssertEqual(record.value, try parser.parse(), vector.name)
                XCTAssertEqual(try CostEstimateRecord.decode(record.encoded()), record, vector.name)
            } catch {
                XCTAssertFalse(vector.clientValid, "\(vector.name): \(error)")
                XCTAssertNotNil(error as? TransferError, vector.name)
            }
        }
        XCTAssertEqual(meters, Set(CostEstimateMeter.allCases))
        XCTAssertEqual(methods, Set(CostEstimateMethod.allCases))
        XCTAssertEqual(confidence, Set(CostEstimateConfidence.allCases))
        XCTAssertEqual(coverage, Set(CostEstimateCoverage.allCases))
        XCTAssertEqual(vectors.filter { $0.canonicalValid != $0.clientValid }.count, 27)
    }

    func testLongDecimalStringsStayExactWithoutNumericConversion() throws {
        let long = String(repeating: "9", count: 200) + ".123456789012"
        var data = try mutated(fixture(), path: ["build_revision"], json: "1e3")
        data = try mutated(data, path: ["period_days"], json: "9e15")
        for path in [["subtotal", "amount"], ["total", "amount"], ["line_items", "0", "quantity"],
                     ["line_items", "0", "unit_price", "amount"], ["line_items", "0", "amount", "amount"]] {
            data = try mutated(data, path: path, json: string(.string(long)))
        }
        data = try mutated(data, path: ["tax", "amount"], json: #""0.000000000000""#)
        let record = try CostEstimateRecord.decode(data)
        XCTAssertEqual(record.buildRevision, Decimal(1_000))
        XCTAssertEqual(record.periodDays, Decimal(string: "9000000000000000", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(record.subtotal.amount, long)
        XCTAssertEqual(record.total.amount, long)
        XCTAssertEqual(record.lineItems[0].quantity, long)
        XCTAssertEqual(record.lineItems[0].unitPrice.amount, long)
        XCTAssertEqual(record.lineItems[0].amount.amount, long)
        XCTAssertEqual(record.tax.amount, "0.000000000000")
        XCTAssertEqual(try CostEstimateRecord.decode(record.encoded()), record)
    }

    func testReportedAmountsCurrenciesCoverageAndIdentityAreNotQualified() throws {
        var data = try mutated(fixture(), path: ["total", "amount"], json: #""1.0000""#)
        data = try mutated(data, path: ["line_items", "0", "amount", "amount"], json: #""0""#)
        data = try mutated(data, path: ["line_items", "0", "amount", "currency"], json: #""EUR""#)
        data = try mutated(data, path: ["unpriced_selection_ids"], json: #"["sel_storage","sel_missing"]"#)
        data = try mutated(data, path: ["estimated_at"], json: #""2099-01-01T00:00:00Z""#)
        data = try mutated(data, path: ["build_id"], json: #""build.other""#)
        data = try mutated(data, path: ["pricebook_id"], json: #""prices.other""#)
        for coverage in CostEstimateCoverage.allCases {
            let selected = try mutated(data, path: ["coverage"], json: string(.string(coverage.rawValue)))
            let record = try CostEstimateRecord.decode(selected)
            XCTAssertEqual(record.buildID, "build.other")
            XCTAssertEqual(record.pricebookID, "prices.other")
            XCTAssertEqual(record.estimatedAt, "2099-01-01T00:00:00Z")
            XCTAssertEqual(record.total.amount, "1.0000")
            XCTAssertEqual(record.subtotal.amount, "578.50")
            XCTAssertEqual(record.lineItems[0].amount.amount, "0")
            XCTAssertEqual(record.lineItems[0].amount.currency, "EUR")
            XCTAssertEqual(record.currency, "USD")
            XCTAssertEqual(record.coverage, coverage)
            XCTAssertEqual(record.unpricedSelectionIDs, ["sel_storage", "sel_missing"])
            XCTAssertEqual(try CostEstimateRecord.decode(record.encoded()), record)
        }
    }

    func testArrayOrderDuplicateRowsAndPrivateTextArePreserved() throws {
        let original = try CostEstimateRecord.decode(fixture())
        let reordered = JSONValue.array([original.lineItems[1].value, original.lineItems[0].value, original.lineItems[1].value])
        var data = try mutated(fixture(), path: ["line_items"], json: string(reordered))
        data = try mutated(data, path: ["warnings"], json: #"["PRIVATE-PAYLOAD ☃","","PRIVATE-PAYLOAD ☃"]"#)
        data = try mutated(data, path: ["line_items", "0", "assumptions"], json: #"["","PRIVATE-ASSUMPTION",""]"#)
        data = try mutated(data, path: ["unpriced_selection_ids"], json: #"["sel_z","sel_a"]"#)
        let record = try CostEstimateRecord.decode(data)
        XCTAssertEqual(record.lineItems.map(\.id), ["line.storage.fixture", "line.compute_profile.fixture", "line.storage.fixture"])
        XCTAssertEqual(record.warnings, ["PRIVATE-PAYLOAD ☃", "", "PRIVATE-PAYLOAD ☃"])
        XCTAssertEqual(record.lineItems[0].assumptions, ["", "PRIVATE-ASSUMPTION", ""])
        XCTAssertEqual(record.unpricedSelectionIDs, ["sel_z", "sel_a"])
        XCTAssertEqual(try CostEstimateRecord.decode(record.encoded()), record)
        let empty = try CostEstimateRecord.decode(mutated(data, path: ["line_items"], json: "[]"))
        XCTAssertEqual(empty.lineItems, [])
        XCTAssertEqual(empty.total.amount, record.total.amount)
        XCTAssertThrowsError(try CostEstimateRecord.decode(mutated(data, path: ["line_items"], remove: true)))
        XCTAssertThrowsError(try CostEstimateRecord.decode(mutated(data, path: ["unpriced_selection_ids"], json: #"["sel_same","sel_same"]"#)))
    }

    func testDuplicateRootAndMoneyKeysIncludingEscapedAliasesFail() throws {
        let original = try XCTUnwrap(String(data: fixture(), encoding: .utf8))
        for (key, alias, replacement) in [("coverage", "coverage", #""partial""#),
                                          ("coverage", #"co\u0076erage"#, #""partial""#),
                                          ("amount", "amount", #""0""#),
                                          ("amount", #"\u0061mount"#, #""0""#)] {
            let duplicate = original.replacingOccurrences(of: "\"\(key)\":", with: "\"\(alias)\":\(replacement),\"\(key)\":")
            XCTAssertNotEqual(duplicate, original)
            XCTAssertThrowsError(try CostEstimateRecord.decode(Data(duplicate.utf8))) {
                XCTAssertEqual($0 as? TransferError, .duplicateKey)
            }
        }
    }

    func testByteDepthAndAggregateLimitsApplyBeforeSchemaAdmission() throws {
        XCTAssertThrowsError(try CostEstimateRecord.decode(Data(repeating: 32, count: BuildTransfer.maximumBytes + 1))) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        let nested = String(repeating: "[", count: 50) + "0" + String(repeating: "]", count: 50)
        XCTAssertThrowsError(try CostEstimateRecord.decode(Data(nested.utf8))) {
            XCTAssertEqual($0 as? TransferError, .tooDeep)
        }
        let warnings = "[" + Array(repeating: "\"\"", count: 16_384).joined(separator: ",") + "]"
        let data = try mutated(fixture(), path: ["warnings"], json: warnings)
        XCTAssertLessThan(data.count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try CostEstimateRecord.decode(data)) {
            XCTAssertEqual($0 as? TransferError, .tooComplex)
        }
    }

    func testMalformedAndUnsupportedInputsHavePayloadFreeErrors() throws {
        let original = try fixture()
        let invalid: [(Data, TransferError)] = [
            (try mutated(original, path: ["schema_version"], json: #""2.0.0""#), .unsupportedVersion),
            (try mutated(original, path: ["private_future_field"], json: #""PRIVATE-PAYLOAD""#), .schemaViolation),
            (try mutated(original, path: ["build_revision"], json: "1234567890123456"), .unsupportedNumber),
            (try mutated(original, path: ["period_days"], json: "1e999"), .unsupportedNumber),
            (try mutated(original, path: ["period_days"], json: "NaN"), .malformed),
            (try mutated(original, path: ["period_days"], json: "01"), .malformed),
            (try mutated(original, path: ["total", "amount"], json: #""PRIVATE-PAYLOAD""#), .schemaViolation),
            (original + Data(" false".utf8), .malformed),
            (Data([0xff]), .malformed)
        ]
        for (data, expected) in invalid {
            XCTAssertThrowsError(try CostEstimateRecord.decode(data)) { error in
                XCTAssertEqual(error as? TransferError, expected)
                XCTAssertFalse(String(describing: error).contains("PRIVATE-PAYLOAD"))
                XCTAssertFalse(String(describing: error).contains("private_future_field"))
            }
        }
    }

    func testNormalizedOutputRetainsValueAndTheSameByteLimit() throws {
        let warning = "[\"" + String(repeating: "/", count: 270_000) + "\"]"
        let data = try mutated(fixture(), path: ["warnings"], json: warning)
        XCTAssertLessThan(data.count, BuildTransfer.maximumBytes)
        let record = try CostEstimateRecord.decode(data)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertGreaterThan(try encoder.encode(record.value).count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try record.encoded()) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        XCTAssertEqual(try CostEstimateRecord.decode(data), record)
    }
}
