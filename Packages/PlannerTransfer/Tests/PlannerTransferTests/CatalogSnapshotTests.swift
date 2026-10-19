import Foundation
import XCTest
@testable import PlannerTransfer

private struct CatalogSnapshotVector: Decodable {
    let name: String
    let path: [String]
    let operation: String
    let json: String?
    let canonicalValid: Bool
    let clientValid: Bool
}

final class CatalogSnapshotTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "catalog", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func encoded(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }

    func testWholeCanonicalCatalogPreservesMetadataOrderAndEveryKind() throws {
        let source = try fixture()
        let data = try encoded(source)
        let snapshot = try CatalogSnapshot.decode(data)
        let originalItems = try XCTUnwrap(source["items"] as? [[String: Any]])
        XCTAssertEqual(snapshot.id, source["id"] as? String)
        XCTAssertEqual(snapshot.capturedAt, source["captured_at"] as? String)
        XCTAssertEqual(snapshot.revision, 1)
        XCTAssertEqual(snapshot.items.map(\.id), try originalItems.map { try XCTUnwrap($0["id"] as? String) })
        XCTAssertEqual(Set(snapshot.items.map(\.kind)), Set(CatalogKind.allCases))
        var parser = try JSONParser(data)
        XCTAssertEqual(snapshot.value, try parser.parse())
        XCTAssertEqual(try CatalogSnapshot.decode(snapshot.encoded()), snapshot)
    }

    func testSharedCanonicalEnvelopeVectorsAndAllOrNothingAdmission() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "catalog-snapshot-conformance", withExtension: "json"))
        let cases = try JSONDecoder().decode([CatalogSnapshotVector].self, from: Data(contentsOf: url))
        XCTAssertEqual(cases.count, 77)
        let source = try fixture()
        for vector in cases {
            let payload: Any
            if vector.operation == "none" { payload = source }
            else {
                let replacement = try vector.json.map {
                    try JSONSerialization.jsonObject(with: Data($0.utf8), options: [.fragmentsAllowed])
                }
                payload = try mutate(source, path: vector.path[...], replacement: replacement,
                                     remove: vector.operation == "remove")
            }
            let data = try encoded(payload)
            do {
                let decoded = try CatalogSnapshot.decode(data)
                XCTAssertTrue(vector.clientValid, vector.name)
                var parser = try JSONParser(data)
                XCTAssertEqual(decoded.value, try parser.parse(), vector.name)
                XCTAssertEqual(try CatalogSnapshot.decode(decoded.encoded()), decoded, vector.name)
            } catch {
                XCTAssertFalse(vector.clientValid, "\(vector.name): \(error)")
            }
        }
        XCTAssertEqual(cases.filter { $0.canonicalValid != $0.clientValid }.count, 2)
        // A malformed item yields no partial replacement and cannot mutate a
        // previously admitted immutable catalog or its revision metadata.
        XCTAssertEqual(try CatalogSnapshot.decode(encoded(source)).items.count, 29)
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

    func testDuplicateEnvelopeAndNestedEscapedKeysAreRejected() throws {
        let source = try XCTUnwrap(String(data: encoded(fixture()), encoding: .utf8))
        for key in ["captured_at", #"captured_\u0061t"#] {
            let duplicate = source.replacingOccurrences(of: "\"captured_at\":", with: "\"\(key)\":\"2026-10-18T00:00:00Z\",\"captured_at\":")
            XCTAssertNotEqual(duplicate, source)
            XCTAssertThrowsError(try CatalogSnapshot.decode(Data(duplicate.utf8))) {
                XCTAssertEqual($0 as? TransferError, .duplicateKey)
            }
        }
        let nested = source.replacingOccurrences(of: "\"kind\":", with: #""k\u0069nd":"workload","kind":"#)
        XCTAssertNotEqual(nested, source)
        XCTAssertThrowsError(try CatalogSnapshot.decode(Data(nested.utf8))) {
            XCTAssertEqual($0 as? TransferError, .duplicateKey)
        }
    }

    func testWholeDocumentLimitsCannotBeEvadedByIndividuallyAdmissibleItems() throws {
        var source = try fixture()
        var item = try XCTUnwrap((source["items"] as? [[String: Any]])?.first)
        item["extensions"] = ["x_padding": String(repeating: "a", count: 270_000)]
        XCTAssertNoThrow(try CatalogItem.decode(encoded(item)))
        source["items"] = [item, item]
        XCTAssertThrowsError(try CatalogSnapshot.decode(encoded(source))) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        item["extensions"] = ["x_nodes": Array(repeating: NSNull(), count: 9_000)]
        XCTAssertNoThrow(try CatalogItem.decode(encoded(item)))
        source["items"] = [item, item]
        XCTAssertThrowsError(try CatalogSnapshot.decode(encoded(source))) {
            XCTAssertEqual($0 as? TransferError, .tooComplex)
        }
        let nested = String(repeating: "[", count: 50) + "0" + String(repeating: "]", count: 50)
        XCTAssertThrowsError(try CatalogSnapshot.decode(Data(nested.utf8))) {
            XCTAssertEqual($0 as? TransferError, .tooDeep)
        }
    }

    func testDuplicateIdentityIsPreservedForTheReceivingGraphPolicy() throws {
        var source = try fixture()
        let item = try XCTUnwrap((source["items"] as? [[String: Any]])?.first)
        var conflicting = item; conflicting["name"] = "Different source claim"
        source["items"] = [item, conflicting, item]
        let snapshot = try CatalogSnapshot.decode(encoded(source))
        XCTAssertEqual(snapshot.items.count, 3)
        XCTAssertEqual(Set(snapshot.items.map(\.id)).count, 1)
        XCTAssertEqual(snapshot.items[1].name, "Different source claim")
        XCTAssertNotEqual(snapshot.items[0], snapshot.items[1])
        XCTAssertEqual(snapshot.items[0], snapshot.items[2])
        XCTAssertEqual(try CatalogSnapshot.decode(snapshot.encoded()), snapshot)
    }

    func testEncodingRejectsExpansionWithoutChangingTheSnapshot() throws {
        var source = try fixture()
        var item = try XCTUnwrap((source["items"] as? [[String: Any]])?.first)
        item["extensions"] = ["x_padding": String(repeating: "/", count: 270_000)]
        source["items"] = [item]
        let compact = try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertLessThan(compact.count, BuildTransfer.maximumBytes)
        let snapshot = try CatalogSnapshot.decode(compact)
        XCTAssertThrowsError(try snapshot.encoded()) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        XCTAssertEqual(try CatalogSnapshot.decode(compact), snapshot)
    }
}
