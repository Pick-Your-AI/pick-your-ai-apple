import Foundation
import XCTest
@testable import PlannerTransfer

private struct QualityVector: Decodable {
    let name: String
    let path: [String]
    let operation: String
    let json: String?
    let canonicalValid: Bool
    let clientValid: Bool
}

final class QualityEvaluationRunTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "quality-evaluation-run", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func string(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try XCTUnwrap(String(data: encoder.encode(value), encoding: .utf8))
    }

    // Render a mutation without parsing its raw replacement number through
    // JSONSerialization/Double first. The public decoder must see the actual token.
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

    func testCanonicalRecordRetainsIdentityAndEverySupportedField() throws {
        let data = try fixture()
        let run = try QualityEvaluationRun.decode(data)
        XCTAssertEqual(run.id, "quality.fixture.1")
        XCTAssertEqual(run.buildID, "build.fixture.1")
        XCTAssertEqual(run.buildRevision, Decimal(1))
        XCTAssertEqual(run.evaluationSuiteSelectionID, "sel_evaluation_suite")
        XCTAssertEqual(run.startedAt, "2026-10-16T09:00:00Z")
        XCTAssertEqual(run.finishedAt, run.startedAt)
        XCTAssertEqual(run.status, .passed)
        XCTAssertEqual(run.evaluatorVersion, "0.0-fixture")
        XCTAssertEqual(run.datasetRevision, "fixture-synthetic-dataset-v1")
        XCTAssertEqual(run.sampleSize, Decimal(100))
        XCTAssertEqual(run.artifacts, [])
        XCTAssertEqual(run.notes, ["TEST FIXTURE: synthetic score, not an actual evaluation."])
        let measurement = try XCTUnwrap(run.measurements.first)
        XCTAssertEqual(run.measurements.count, 1)
        XCTAssertEqual(measurement.metric, "answer_quality")
        XCTAssertEqual(measurement.observed, Decimal(string: "0.91"))
        XCTAssertEqual(measurement.threshold, Decimal(string: "0.85"))
        XCTAssertEqual(measurement.comparator, .gte)
        XCTAssertEqual(measurement.unit, "score")
        XCTAssertTrue(measurement.passed)
        var original = try JSONParser(data)
        XCTAssertEqual(run.value, try original.parse())
        XCTAssertEqual(try QualityEvaluationRun.decode(run.encoded()), run)
    }

    func testSharedCanonicalQualityConformanceVectorsUseRawNumericTokens() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "quality-conformance", withExtension: "json"))
        let cases = try JSONDecoder().decode([QualityVector].self, from: Data(contentsOf: url))
        let original = try fixture()
        XCTAssertEqual(cases.count, 202)
        var statuses = Set<QualityEvaluationStatus>()
        var comparators = Set<QualityMeasurementComparator>()
        for vector in cases {
            let data = vector.operation == "none" ? original : try mutated(original, path: vector.path, json: vector.json, remove: vector.operation == "remove")
            do {
                let run = try QualityEvaluationRun.decode(data)
                XCTAssertTrue(vector.clientValid, vector.name)
                statuses.insert(run.status)
                comparators.formUnion(run.measurements.map(\.comparator))
                var source = try JSONParser(data)
                XCTAssertEqual(run.value, try source.parse(), vector.name)
                XCTAssertEqual(try QualityEvaluationRun.decode(run.encoded()), run, vector.name)
            } catch {
                XCTAssertFalse(vector.clientValid, "\(vector.name): \(error)")
                XCTAssertNotNil(error as? TransferError, vector.name)
            }
        }
        XCTAssertEqual(statuses, Set(QualityEvaluationStatus.allCases))
        XCTAssertEqual(comparators, Set(QualityMeasurementComparator.allCases))
        XCTAssertEqual(cases.filter { $0.canonicalValid != $0.clientValid }.count, 18)
    }

    func testOptionalAbsenceRemainsDistinctFromEmptyArraysAndStrings() throws {
        let original = try fixture()
        let noNotes = try QualityEvaluationRun.decode(mutated(original, path: ["notes"], remove: true))
        let emptyNotes = try QualityEvaluationRun.decode(mutated(original, path: ["notes"], json: "[]"))
        let emptyNote = try QualityEvaluationRun.decode(mutated(original, path: ["notes"], json: "[\"\"]"))
        XCTAssertNil(noNotes.notes)
        XCTAssertEqual(emptyNotes.notes, [])
        XCTAssertEqual(emptyNote.notes, [""])
        XCTAssertNotEqual(noNotes, emptyNotes)
        XCTAssertNotEqual(emptyNotes, emptyNote)
        let noUnit = try QualityEvaluationRun.decode(mutated(original, path: ["measurements", "0", "unit"], remove: true))
        let emptyUnit = try QualityEvaluationRun.decode(mutated(original, path: ["measurements", "0", "unit"], json: "\"\""))
        XCTAssertNil(try XCTUnwrap(noUnit.measurements.first).unit)
        XCTAssertEqual(try XCTUnwrap(emptyUnit.measurements.first).unit, "")
        XCTAssertNotEqual(noUnit, emptyUnit)
        for run in [noNotes, emptyNotes, emptyNote, noUnit, emptyUnit] {
            XCTAssertEqual(try QualityEvaluationRun.decode(run.encoded()), run)
        }
    }

    func testRecordedLabelsChronologyDuplicatesAndPrivateTextAreNotReinterpreted() throws {
        var data = try mutated(fixture(), path: ["measurements"], json: #"[{"metric":"same","observed":-9,"threshold":99,"comparator":"eq","passed":true},{"metric":"same","observed":10,"threshold":99,"comparator":"gte","passed":false}]"#)
        data = try mutated(data, path: ["finished_at"], json: #""2026-10-15T00:00:00Z""#)
        data = try mutated(data, path: ["artifacts"], json: #"["urn:example:private","file:///tmp/private.json","urn:example:private"]"#)
        data = try mutated(data, path: ["notes"], json: #"["PRIVATE-PAYLOAD","", "PRIVATE-PAYLOAD"]"#)
        let run = try QualityEvaluationRun.decode(data)
        XCTAssertEqual(run.status, .passed)
        XCTAssertEqual(run.finishedAt, "2026-10-15T00:00:00Z")
        XCTAssertEqual(run.measurements.map(\.metric), ["same", "same"])
        XCTAssertEqual(run.measurements.map(\.observed), [Decimal(-9), Decimal(10)])
        XCTAssertEqual(run.measurements.map(\.passed), [true, false])
        XCTAssertEqual(run.measurements.map(\.comparator), [.eq, .gte])
        XCTAssertEqual(run.artifacts, ["urn:example:private", "file:///tmp/private.json", "urn:example:private"])
        XCTAssertEqual(run.notes, ["PRIVATE-PAYLOAD", "", "PRIVATE-PAYLOAD"])
        XCTAssertEqual(try QualityEvaluationRun.decode(run.encoded()), run)
    }

    func testNumericViewsRemainExactWithoutNarrowingOrRounding() throws {
        var data = try mutated(fixture(), path: ["build_revision"], json: "1e3")
        data = try mutated(data, path: ["sample_size"], json: "9e15")
        data = try mutated(data, path: ["measurements", "0", "observed"], json: "1.23456789e-12")
        data = try mutated(data, path: ["measurements", "0", "threshold"], json: "-123456789.012345")
        let run = try QualityEvaluationRun.decode(data)
        let locale = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(run.buildRevision, Decimal(1_000))
        XCTAssertEqual(run.sampleSize, Decimal(string: "9000000000000000", locale: locale))
        XCTAssertEqual(run.measurements[0].observed, Decimal(string: "0.00000000000123456789", locale: locale))
        XCTAssertEqual(run.measurements[0].threshold, Decimal(string: "-123456789.012345", locale: locale))
        XCTAssertEqual(try QualityEvaluationRun.decode(run.encoded()), run)
    }

    func testDuplicateRootAndMeasurementKeysIncludingEscapedAliasesFail() throws {
        let original = try XCTUnwrap(String(data: fixture(), encoding: .utf8))
        for (key, alias, value) in [("status", "status", "\"failed\""),
                                    ("status", #"st\u0061tus"#, "\"failed\""),
                                    ("observed", "observed", "0"),
                                    ("observed", #"obser\u0076ed"#, "0")] {
            let duplicate = original.replacingOccurrences(of: "\"\(key)\":", with: "\"\(alias)\":\(value),\"\(key)\":")
            XCTAssertNotEqual(duplicate, original)
            XCTAssertThrowsError(try QualityEvaluationRun.decode(Data(duplicate.utf8))) {
                XCTAssertEqual($0 as? TransferError, .duplicateKey)
            }
        }
    }

    func testByteDepthAndAggregateNodeLimitsApplyBeforeSchemaAcceptance() throws {
        XCTAssertThrowsError(try QualityEvaluationRun.decode(Data(repeating: 32, count: BuildTransfer.maximumBytes + 1))) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        let nested = String(repeating: "[", count: 50) + "0" + String(repeating: "]", count: 50)
        XCTAssertThrowsError(try QualityEvaluationRun.decode(Data(nested.utf8))) {
            XCTAssertEqual($0 as? TransferError, .tooDeep)
        }
        let notes = "[" + Array(repeating: "\"\"", count: 16_384).joined(separator: ",") + "]"
        let data = try mutated(fixture(), path: ["notes"], json: notes)
        XCTAssertLessThan(data.count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try QualityEvaluationRun.decode(data)) {
            XCTAssertEqual($0 as? TransferError, .tooComplex)
        }
    }

    func testUnsupportedAndMalformedInputReturnsPayloadFreeErrors() throws {
        let original = try fixture()
        let invalid: [(Data, TransferError)] = [
            (try mutated(original, path: ["schema_version"], json: "\"2.0.0\""), .unsupportedVersion),
            (try mutated(original, path: ["private_future_field"], json: "\"PRIVATE-PAYLOAD\""), .schemaViolation),
            (try mutated(original, path: ["measurements", "0", "observed"], json: "1.234567890123456"), .unsupportedNumber),
            (try mutated(original, path: ["measurements", "0", "observed"], json: "1e999"), .unsupportedNumber),
            (try mutated(original, path: ["measurements", "0", "observed"], json: "NaN"), .malformed),
            (try mutated(original, path: ["measurements", "0", "observed"], json: "01"), .malformed),
            (original + Data(" false".utf8), .malformed),
            (Data([0xff]), .malformed)
        ]
        for (data, expected) in invalid {
            XCTAssertThrowsError(try QualityEvaluationRun.decode(data)) { error in
                XCTAssertEqual(error as? TransferError, expected)
                XCTAssertFalse(String(describing: error).contains("PRIVATE-PAYLOAD"))
                XCTAssertFalse(String(describing: error).contains("private_future_field"))
            }
        }
    }

    func testNormalizedOutputCannotExceedTheDecoderLimitOrChangeTheValue() throws {
        let notes = "[\"" + String(repeating: "/", count: 270_000) + "\"]"
        let compact = try mutated(fixture(), path: ["notes"], json: notes)
        XCTAssertLessThan(compact.count, BuildTransfer.maximumBytes)
        let run = try QualityEvaluationRun.decode(compact)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertGreaterThan(try encoder.encode(run.value).count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try run.encoded()) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        XCTAssertEqual(try QualityEvaluationRun.decode(compact), run)
    }
}
