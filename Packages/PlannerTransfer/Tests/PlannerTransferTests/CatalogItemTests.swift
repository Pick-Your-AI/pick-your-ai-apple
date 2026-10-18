import Foundation
import XCTest
@testable import PlannerTransfer

private struct CatalogVector: Decodable {
    let name: String
    let kind: String
    let path: [String]
    let operation: String
    let json: String?
    let canonicalValid: Bool
    let clientValid: Bool
}

final class CatalogItemTests: XCTestCase {
    private func fixture() throws -> [[String: Any]] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "catalog", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(root["items"] as? [[String: Any]])
    }

    private func encoded(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }

    func testAll29CanonicalKindsDecodeWithoutLosingFieldsOrIdentity() throws {
        let items = try fixture()
        XCTAssertEqual(items.count, 29)
        XCTAssertEqual(CatalogKind.allCases.count, 29)
        var kinds = Set<CatalogKind>()
        for item in items {
            let data = try encoded(item)
            let decoded = try CatalogItem.decode(data)
            kinds.insert(decoded.kind)
            XCTAssertEqual(decoded.id, item["id"] as? String)
            XCTAssertEqual(decoded.name, item["name"] as? String)
            XCTAssertEqual(decoded.version, item["version"] as? String)
            XCTAssertEqual(decoded.tier, item["tier"] as? String)
            XCTAssertEqual(decoded.status, item["status"] as? String)
            XCTAssertEqual(decoded.billingClass, item["billing_class"] as? String)
            var parser = try JSONParser(data)
            XCTAssertEqual(decoded.value, try parser.parse())
            XCTAssertEqual(try CatalogItem.decode(decoded.encoded()), decoded)
        }
        XCTAssertEqual(kinds, Set(CatalogKind.allCases))
    }

    func testSharedCanonicalCatalogConformanceVectors() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "catalog-conformance", withExtension: "json"))
        let cases = try JSONDecoder().decode([CatalogVector].self, from: Data(contentsOf: url))
        XCTAssertEqual(cases.count, 1635)
        let items = try Dictionary(uniqueKeysWithValues: fixture().map { (try XCTUnwrap($0["kind"] as? String), $0) })
        for vector in cases {
            let item = try XCTUnwrap(items[vector.kind])
            let payload: Any
            if vector.operation == "none" { payload = item }
            else {
                let replacement = try vector.json.map {
                    try JSONSerialization.jsonObject(with: Data($0.utf8), options: [.fragmentsAllowed])
                }
                payload = try mutate(item, path: vector.path[...], replacement: replacement,
                                     remove: vector.operation == "remove")
            }
            let data = try encoded(payload)
            do {
                let decoded = try CatalogItem.decode(data)
                XCTAssertTrue(vector.clientValid, vector.name)
                var original = try JSONParser(data)
                XCTAssertEqual(decoded.value, try original.parse(), vector.name)
                XCTAssertEqual(try CatalogItem.decode(decoded.encoded()), decoded, vector.name)
            } catch {
                XCTAssertFalse(vector.clientValid, "\(vector.name): \(error)")
            }
        }
        // These are deliberate representation limits, not falsely reported
        // failures of the canonical schema or claimed whole-schema equivalence.
        XCTAssertEqual(cases.filter { $0.canonicalValid != $0.clientValid }.count, 6)
    }

    private func mutate(_ value: Any, path: ArraySlice<String>, replacement: Any?, remove: Bool) throws -> Any {
        guard let key = path.first else { return try XCTUnwrap(replacement) }
        if var object = value as? [String: Any] {
            if path.count == 1 {
                if remove { object.removeValue(forKey: key) }
                else { object[key] = try XCTUnwrap(replacement) }
            } else {
                object[key] = try mutate(XCTUnwrap(object[key]), path: path.dropFirst(), replacement: replacement, remove: remove)
            }
            return object
        }
        var array = try XCTUnwrap(value as? [Any])
        let index = try XCTUnwrap(Int(key))
        guard array.indices.contains(index) else { throw TransferError.malformed }
        if path.count == 1 {
            if remove { array.remove(at: index) }
            else { array[index] = try XCTUnwrap(replacement) }
        } else {
            array[index] = try mutate(array[index], path: path.dropFirst(), replacement: replacement, remove: remove)
        }
        return array
    }

    func testDuplicateKeysAndEscapedAliasesAreRejectedBeforeDecoding() throws {
        let data = try encoded(XCTUnwrap(fixture().first))
        let source = try XCTUnwrap(String(data: data, encoding: .utf8))
        for key in ["kind", #"k\u0069nd"#] {
            let duplicate = source.replacingOccurrences(of: "\"kind\":", with: "\"\(key)\":\"workload\",\"kind\":")
            XCTAssertNotEqual(duplicate, source)
            XCTAssertThrowsError(try CatalogItem.decode(Data(duplicate.utf8))) {
                XCTAssertEqual($0 as? TransferError, .duplicateKey)
            }
        }
    }

    func testCatalogBoundaryKeepsExistingByteDepthAndComplexityLimits() throws {
        XCTAssertThrowsError(try CatalogItem.decode(Data(repeating: 32, count: BuildTransfer.maximumBytes + 1))) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        let nested = String(repeating: "[", count: 50) + "0" + String(repeating: "]", count: 50)
        XCTAssertThrowsError(try CatalogItem.decode(Data(nested.utf8))) {
            XCTAssertEqual($0 as? TransferError, .tooDeep)
        }
        let complex = "[" + Array(repeating: "null", count: 16_384).joined(separator: ",") + "]"
        XCTAssertThrowsError(try CatalogItem.decode(Data(complex.utf8))) {
            XCTAssertEqual($0 as? TransferError, .tooComplex)
        }
    }

    func testEncodingRejectsExpansionPastTheDecodeByteLimit() throws {
        var item = try XCTUnwrap(fixture().first)
        item["extensions"] = ["x_pad": String(repeating: "/", count: 270_000)]
        let compact = try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertLessThan(compact.count, BuildTransfer.maximumBytes)
        let decoded = try CatalogItem.decode(compact)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertGreaterThan(try encoder.encode(decoded.value).count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try decoded.encoded()) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        // A failed serialization leaves the immutable decoded value unchanged.
        XCTAssertEqual(try CatalogItem.decode(compact), decoded)
    }

    func testUnknownBillingAndOptionalFactsStayUninferred() throws {
        var item = try XCTUnwrap(fixture().first { $0["kind"] as? String == "cost_policy" })
        item["billing_class"] = "unknown"
        item["spec"] = ["default_currency": "USD"]
        let decoded = try CatalogItem.decode(encoded(item))
        XCTAssertEqual(decoded.kind, .costPolicy)
        XCTAssertEqual(decoded.billingClass, "unknown")
        XCTAssertEqual(Set(decoded.spec.keys), ["default_currency"])
        XCTAssertNil(decoded.spec["supports_hard_cap"])
        XCTAssertNil(decoded.spec["monthly_budget"])
    }
}
