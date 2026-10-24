import Foundation
import PlannerCore
import XCTest
@testable import PlannerTransfer

private struct WireBundle: Decodable {
    let bundleVersion: String
    let contractVersion: String
    let cases: [WireCase]
}

private struct WireCase: Decodable {
    let id: String
    let contract: String
    let schema: String
    let payloadJSON: String
    let valid: Bool
}

final class CrossClientTests: XCTestCase {
    private func vectors() throws -> [WireCase] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "cross-client-v1", withExtension: "json"))
        let bundle = try JSONDecoder().decode(WireBundle.self, from: Data(contentsOf: url))
        XCTAssertEqual(bundle.bundleVersion, "apple-cross-client-1")
        XCTAssertEqual(bundle.contractVersion, "1.0.0")
        XCTAssertEqual(bundle.cases.count, 223)
        XCTAssertEqual(Set(bundle.cases.map(\.id)).count, bundle.cases.count)
        return bundle.cases
    }

    private func value(_ data: Data) throws -> JSONValue {
        var parser = try JSONParser(data)
        return try parser.parse()
    }

    // Existing production decoders and the existing selection validator supply
    // observed behavior. The fixture never implements or replaces a validator.
    private func preservationCheckAfterDecode(_ data: Data, contract: String) throws -> () throws -> Bool {
        switch contract {
        case "BuildSnapshot":
            let decoded = try BuildTransfer.snapshot(fromDraftJSON: data)
            return {
                let original = try self.value(data)
                let reopened = try BuildTransfer.snapshot(fromDraftJSON: decoded.encoded())
                return decoded.value == original && decoded == reopened
            }
        case "CatalogItem":
            let decoded = try CatalogItem.decode(data)
            return {
                let original = try self.value(data)
                let reopened = try CatalogItem.decode(decoded.encoded())
                return decoded.value == original && decoded == reopened
            }
        case "Selection":
            let decoded = try value(data)
            let validator = try FrozenValidator()
            let schema = try XCTUnwrap(validator.schemas["selection.schema.json"])
            try validator.check(decoded, schema: schema, document: "selection.schema.json")
            return {
                let encoded = try JSONEncoder().encode(decoded)
                let reopened = try self.value(encoded)
                try validator.check(reopened, schema: schema, document: "selection.schema.json")
                return decoded == reopened
            }
        case "EvaluationReport":
            let decoded = try EvaluationReport.decode(data)
            return {
                let encoded = try JSONEncoder().encode(decoded)
                let reopened = try EvaluationReport.decode(encoded)
                // Compare typed JSON values: Foundation object equality can
                // otherwise equate the Boolean false with the number zero.
                let originalValue = try self.value(data)
                let encodedValue = try self.value(encoded)
                return decoded == reopened && originalValue == encodedValue
            }
        default:
            XCTFail("Unsupported fixture consumer: \(contract)")
            throw TransferError.unavailableSchema
        }
    }

    private func run(_ contract: String, expectedCount: Int) throws {
        let selected = try vectors().filter { $0.contract == contract }
        XCTAssertEqual(selected.count, expectedCount)
        for vector in selected {
            let bytes = Data(vector.payloadJSON.utf8)
            let accepted: Bool
            let preserved: Bool?
            do {
                let check = try preservationCheckAfterDecode(bytes, contract: contract)
                accepted = true
                // A serialization failure must never masquerade as decoder rejection.
                preserved = (try? check()) ?? false
            } catch {
                accepted = false
                preserved = nil
            }
            XCTAssertEqual(accepted, vector.valid, vector.id)
            if accepted { XCTAssertEqual(preserved, true, vector.id) }
            let observation: [String: Any] = ["bundleVersion": "apple-cross-client-1", "id": vector.id,
                                               "accepted": accepted, "preserved": preserved.map { $0 as Any } ?? NSNull()]
            let encoded = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
            // Keep each observation on XCTest's diagnostic stream before its method finishes.
            let line = "APPLE_WIRE_CASE " + (try XCTUnwrap(String(data: encoded, encoding: .utf8))) + "\n"
            try FileHandle.standardError.write(contentsOf: Data(line.utf8))
        }
    }

    func testBuildGoldenPayloadsRejectUnsupportedVersionsAndPreserveLocksAndRelationships() throws {
        try run("BuildSnapshot", expectedCount: 85)
    }

    func testCatalogGoldenPayloadsPreserveFactsWithoutInventingPlacement() throws {
        try run("CatalogItem", expectedCount: 61)
    }

    func testSelectionGoldenPayloadsPreserveKindsRolesAndExactComponentPins() throws {
        try run("Selection", expectedCount: 33)
    }

    func testReportGoldenPayloadsPreserveUnknownsAndProducerOutcomes() throws {
        try run("EvaluationReport", expectedCount: 44)
    }
}
