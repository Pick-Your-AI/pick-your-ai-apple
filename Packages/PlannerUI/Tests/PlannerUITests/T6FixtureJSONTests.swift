import Foundation
import XCTest
@testable import PlannerTransfer

/// Test-only mutation bridge. Parse the original fixture through the existing
/// exact Transfer reader, retaining Decimal rather than NSNumber/Double values.
/// Existing mutation closures may still use dictionaries, arrays and exact Ints.
enum T6FixtureJSON {
    enum Failure: Error, Equatable { case expectedObject, unsupportedScalar }

    static func object(_ data: Data) throws -> [String: Any] {
        var parser = try JSONParser(data)
        guard case .object(let fields) = try parser.parse() else { throw Failure.expectedObject }
        return fields.mapValues(foundationValue)
    }

    static func data(_ fields: [String: Any]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(exactValue(fields))
    }

    private static func foundationValue(_ value: JSONValue) -> Any {
        switch value {
        case .object(let fields): return fields.mapValues(foundationValue)
        case .array(let values): return values.map(foundationValue)
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        }
    }

    private static func exactValue(_ value: Any) throws -> JSONValue {
        // Runtime type checks precede bridgeable scalar casts. In particular,
        // NSNumber, NSDecimalNumber, Double and Float must not become a Bool,
        // Int or Decimal merely because Foundation permits a bridging cast.
        if type(of: value) == Bool.self, let value = value as? Bool { return .bool(value) }
        if type(of: value) == Int.self, let value = value as? Int { return .number(Decimal(value)) }
        if type(of: value) == Decimal.self, let value = value as? Decimal { return .number(value) }
        if type(of: value) == String.self, let value = value as? String { return .string(value) }
        if value is NSNull { return .null }
        if let fields = value as? [String: Any] {
            return .object(try fields.mapValues(exactValue))
        }
        if let values = value as? [Any] {
            return .array(try values.map(exactValue))
        }
        throw Failure.unsupportedScalar
    }
}

@MainActor
final class T6FixtureJSONTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func assertFractions(_ snapshot: BuildSnapshot,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = try XCTUnwrap(snapshot.value.object?["selections"]?.array, file: file, line: line)
        let evaluation = try XCTUnwrap(rows.first { $0.object?["id"] == .string("sel_evaluation_suite") },
                                       file: file, line: line)
        let monitoring = try XCTUnwrap(rows.first { $0.object?["id"] == .string("sel_monitoring_stack") },
                                       file: file, line: line)
        XCTAssertEqual(evaluation.object?["settings"]?.object?["minimum_score"],
                       .number(try XCTUnwrap(Decimal(string: "0.85"))), file: file, line: line)
        XCTAssertEqual(monitoring.object?["settings"]?.object?["sample_rate"],
                       .number(try XCTUnwrap(Decimal(string: "0.1"))), file: file, line: line)
    }

    func testOriginalT6BuildIsAdmittedWithoutFoundationRoundTrip() throws {
        let original = try fixture("t6-build")
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: original)
        try assertFractions(snapshot)
        XCTAssertEqual(original, try fixture("t6-build"))
    }

    func testNoOpFixtureEncodingPreservesTheCompleteBuild() throws {
        let original = try fixture("t6-build")
        let before = try BuildTransfer.snapshot(fromDraftJSON: original)
        let after = try BuildTransfer.snapshot(fromDraftJSON: T6FixtureJSON.data(T6FixtureJSON.object(original)))
        XCTAssertEqual(after, before)
        try assertFractions(after)
        XCTAssertEqual(original, try fixture("t6-build"))
    }

    func testUnrelatedMutationPreservesBothOriginalFractions() throws {
        let original = try fixture("t6-build")
        let before = try BuildTransfer.snapshot(fromDraftJSON: original)
        var fields = try T6FixtureJSON.object(original)
        fields["id"] = "build.fixture.changed-identity-only"
        let after = try BuildTransfer.snapshot(fromDraftJSON: T6FixtureJSON.data(fields))
        var expected = try XCTUnwrap(before.value.object)
        expected["id"] = .string("build.fixture.changed-identity-only")
        XCTAssertEqual(after.value, .object(expected))
        try assertFractions(after)
        XCTAssertEqual(original, try fixture("t6-build"))
    }

    func testQualityFixtureEncodingPreservesThresholdAndFalseFlag() throws {
        let original = try fixture("t6-quality-evaluation-run")
        let before = try QualityEvaluationRun.decode(original)
        let after = try QualityEvaluationRun.decode(T6FixtureJSON.data(T6FixtureJSON.object(original)))
        XCTAssertEqual(after.value, before.value)
        XCTAssertEqual(after.measurements.first?.threshold, Decimal(string: "0.85"))
        XCTAssertEqual(after.measurements.first?.observed, 0)
        XCTAssertEqual(after.measurements.first?.passed, false)
        XCTAssertEqual(original, try fixture("t6-quality-evaluation-run"))
    }

    func testFloatingAndBridgedNumbersAreRejectedWithoutCoercion() throws {
        let unsupported: [Any] = [Double(0.85), Float(0.1), NSNumber(value: true),
                                  NSNumber(value: 7), NSDecimalNumber(string: "0.85")]
        for value in unsupported {
            XCTAssertThrowsError(try T6FixtureJSON.data(["nested": ["value": value]])) {
                XCTAssertEqual($0 as? T6FixtureJSON.Failure, .unsupportedScalar)
            }
        }
    }

    func testBooleanIntegerDecimalAndNullRemainDistinct() throws {
        let decimal = try XCTUnwrap(Decimal(string: "0.85"))
        let fields: [String: Any] = ["true": true, "false": false, "one": 1, "zero": 0,
                                    "decimal": decimal, "null": NSNull(),
                                    "nested": [false, 1, decimal] as [Any]]
        var parser = try JSONParser(T6FixtureJSON.data(fields))
        XCTAssertEqual(try parser.parse(), .object([
            "true": .bool(true), "false": .bool(false), "one": .number(1), "zero": .number(0),
            "decimal": .number(decimal), "null": .null,
            "nested": .array([.bool(false), .number(1), .number(decimal)]),
        ]))
    }
}
