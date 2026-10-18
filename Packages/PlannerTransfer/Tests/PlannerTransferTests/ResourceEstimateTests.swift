import Foundation
import XCTest
@testable import PlannerTransfer

final class ResourceEstimateTests: XCTestCase {
    private func fixture() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "resource-estimate", withExtension: "json")))
    }
    private func object() throws -> [String: JSONValue] {
        var parser = try JSONParser(fixture())
        return try XCTUnwrap(parser.parse().object)
    }
    private func encoded(_ object: [String: JSONValue], compact: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = compact ? [.sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        return try encoder.encode(JSONValue.object(object))
    }
    private func entry(_ object: [String: JSONValue]) throws -> [String: JSONValue] {
        try XCTUnwrap(object["estimates"]?.array?.first?.object)
    }

    func testCanonicalArtifactPreservesBuildEstimatorSelectionIdentityAndRoundTrip() throws {
        let source = try object()
        let estimate = try ResourceEstimate.decode(fixture())
        XCTAssertEqual(estimate.id, "resources.fixture.1")
        XCTAssertEqual(estimate.buildID, "build.fixture.1")
        XCTAssertEqual(estimate.buildRevision, 1)
        XCTAssertEqual(estimate.generatedAt, "2026-10-16T09:00:00Z")
        XCTAssertEqual(estimate.estimates.count, 2)
        XCTAssertEqual(estimate.value, .object(source))
        XCTAssertEqual(estimate.estimates, source["estimates"]?.array)
        XCTAssertEqual(estimate.estimates[0].object?["selection_ids"]?.array,
                       [.string("sel_model"), .string("sel_context_policy"),
                        .string("sel_inference_engine"), .string("sel_accelerator")])
        XCTAssertEqual(try ResourceEstimate.decode(estimate.encoded()), estimate)
    }

    func testSharedCanonicalResourceVectorsAndExplicitClientSubsets() throws {
        struct Vector: Decodable {
            let name: String, json: String
            let canonicalValid: Bool, clientValid: Bool
            let clientLimit: String?
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "resource-estimate-conformance", withExtension: "json"))
        let cases = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
        XCTAssertEqual(cases.count, 223)
        XCTAssertEqual(cases.filter(\.canonicalValid).count, 112)
        XCTAssertEqual(cases.filter(\.clientValid).count, 106)
        XCTAssertEqual(cases.filter { $0.canonicalValid != $0.clientValid }.count, 6)
        for vector in cases {
            if vector.canonicalValid != vector.clientValid { XCTAssertNotNil(vector.clientLimit, vector.name) }
            do {
                let value = try ResourceEstimate.decode(Data(vector.json.utf8))
                XCTAssertTrue(vector.clientValid, vector.name)
                XCTAssertEqual(try ResourceEstimate.decode(value.encoded()), value, vector.name)
            } catch {
                XCTAssertFalse(vector.clientValid, "\(vector.name): \(error)")
            }
        }
    }

    func testDecimalSpellingAndSourceAbsenceRemainExactWithoutBinaryConversion() throws {
        var source = try object()
        var first = try entry(source)
        for quantity in ["0", "0.0", "20.000", "0.000000000001",
                         "9007199254740993.123456789012", String(repeating: "9", count: 300) + ".000000000001"] {
            first["value"] = .string(quantity)
            first.removeValue(forKey: "source_uri")
            source["estimates"] = .array([.object(first)])
            let estimate = try ResourceEstimate.decode(encoded(source))
            let roundTrip = try ResourceEstimate.decode(estimate.encoded())
            XCTAssertEqual(roundTrip.estimates.first?.object?["value"], .string(quantity))
            XCTAssertNil(roundTrip.estimates.first?.object?["source_uri"])
            XCTAssertEqual(roundTrip.value, .object(source))
        }
    }

    func testForeignPartialRepeatedDeclarationsStayUnevaluatedAndInOrder() throws {
        var source = try object()
        var first = try entry(source)
        source["id"] = .string("resources.foreign.2")
        source["build_id"] = .string("build.foreign.7")
        source["build_revision"] = .number(9)
        first["confidence"] = .string("unverified")
        first["assumptions"] = .array([.string("unknown quality"), .string("unknown quality")])
        first["selection_ids"] = .array([.string("sel_other_model"), .string("sel_other_context")])
        // Frozen v1 enumerates units independently of metrics. Admission preserves
        // this declaration; it cannot certify dimensional meaning or tuple match.
        first["unit"] = .string("watt")
        source["estimates"] = .array([.object(first)])
        let partial = try ResourceEstimate.decode(encoded(source))
        XCTAssertEqual(partial.buildID, "build.foreign.7")
        XCTAssertEqual(partial.buildRevision, 9)
        XCTAssertEqual(partial.estimates, [.object(first)])
        XCTAssertEqual(partial.estimates.first?.object?["confidence"], .string("unverified"))
        var second = first; second["estimator_version"] = .string("other-version")
        source["estimates"] = .array([.object(first), .object(second), .object(first)])
        let repeated = try ResourceEstimate.decode(encoded(source))
        XCTAssertEqual(repeated.estimates, source["estimates"]?.array)
        XCTAssertEqual(try ResourceEstimate.decode(repeated.encoded()), repeated)
    }

    func testDuplicateKeysEscapedAliasesAndDuplicateSelectionsAreRejected() throws {
        let text = String(decoding: try encoded(object()), as: UTF8.self)
        for (needle, replacement) in [
            (#""build_id":"build.fixture.1""#, #""build_id":"build.fixture.1","\u0062uild_id":"build.other.2""#),
            (#""value":"20.0""#, #""value":"20.0","\u0076alue":"21.0""#)
        ] {
            let duplicate = text.replacingOccurrences(of: needle, with: replacement)
            XCTAssertNotEqual(duplicate, text)
            XCTAssertThrowsError(try ResourceEstimate.decode(Data(duplicate.utf8))) {
                XCTAssertEqual($0 as? TransferError, .duplicateKey)
            }
        }
        var source = try object(); var first = try entry(source)
        first["selection_ids"] = .array([.string("sel_model"), .string("sel_model")])
        source["estimates"] = .array([.object(first)])
        let duplicate = String(decoding: try encoded(source), as: UTF8.self)
            .replacingOccurrences(of: #"["sel_model","sel_model"]"#, with: #"["sel_model","sel_\u006dodel"]"#)
        XCTAssertTrue(duplicate.contains(#"\u006d"#))
        XCTAssertThrowsError(try ResourceEstimate.decode(Data(duplicate.utf8))) {
            XCTAssertEqual($0 as? TransferError, .schemaViolation)
        }
    }

    func testAggregateBoundsPrecedeSchemaAdmissionAndCoverTheWholeArtifact() throws {
        XCTAssertThrowsError(try ResourceEstimate.decode(Data(repeating: 32, count: BuildTransfer.maximumBytes + 1))) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        let deep = Data((String(repeating: "[", count: 50) + "0" + String(repeating: "]", count: 50)).utf8)
        XCTAssertThrowsError(try ResourceEstimate.decode(deep)) { XCTAssertEqual($0 as? TransferError, .tooDeep) }
        var source = try object(); var first = try entry(source)
        first["metric"] = .string("training.estimated_gpu_hours")
        first["estimator_id"] = .string("a"); first["estimator_version"] = .string("1")
        first["assumptions"] = .array([]); first["selection_ids"] = .array([.string("sel_x")])
        source["estimates"] = .array([.object(first)])
        XCTAssertEqual(try ResourceEstimate.decode(encoded(source)).estimates.count, 1)
        source["estimates"] = .array(Array(repeating: .object(first), count: 1_700))
        let aggregate = try encoded(source)
        XCTAssertLessThan(aggregate.count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try ResourceEstimate.decode(aggregate)) { XCTAssertEqual($0 as? TransferError, .tooComplex) }
    }

    func testEncodingExpansionFailsWithoutChangingTheValidatedEstimate() throws {
        var source = try object(); var first = try entry(source)
        first["assumptions"] = .array([.string(String(repeating: "/", count: 270_000))])
        source["estimates"] = .array([.object(first)])
        let compact = try encoded(source, compact: true)
        XCTAssertLessThan(compact.count, BuildTransfer.maximumBytes)
        let estimate = try ResourceEstimate.decode(compact)
        XCTAssertGreaterThan(try encoded(source).count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try estimate.encoded()) { XCTAssertEqual($0 as? TransferError, .oversized) }
        XCTAssertEqual(estimate.value, .object(source))
        XCTAssertEqual(try ResourceEstimate.decode(compact), estimate)
    }

    func testLateInvalidEntriesVersionsAndSchemaAvailabilityFailWithoutPartialResults() throws {
        var source = try object(); var late = try entry(source)
        late["source_uri"] = .string("do-not-echo-private-input")
        source["estimates"] = .array([.object(try entry(source)), .object(late)])
        let input = try encoded(source); let before = input
        XCTAssertThrowsError(try ResourceEstimate.decode(input)) {
            XCTAssertEqual($0 as? TransferError, .schemaViolation)
            XCTAssertFalse(String(describing: $0).contains("do-not-echo"))
        }
        XCTAssertEqual(input, before)
        source = try object(); source["schema_version"] = .string("2.0.0")
        XCTAssertThrowsError(try ResourceEstimate.decode(encoded(source))) { XCTAssertEqual($0 as? TransferError, .unsupportedVersion) }
        let missingSchema = try FrozenValidator(schemaNames: ["common"])
        XCTAssertThrowsError(try missingSchema.validateResourceEstimate(.object(try object()))) {
            XCTAssertEqual($0 as? TransferError, .unavailableSchema)
        }
    }
}
