import Foundation
import XCTest
@testable import PlannerCore

final class RawContractJSONTests: XCTestCase {
    private struct VectorBundle: Decodable {
        struct Vector: Decodable {
            let id: String
            let fixture: String
            let valid: Bool
            let replacements: [[String]]
        }
        let cases: [Vector]
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func replacing(_ original: String, _ source: String, _ replacement: String) throws -> Data {
        XCTAssertTrue(original.contains(source), "Raw-wire mutation must match its fixture")
        return Data(original.replacingOccurrences(of: source, with: replacement).utf8)
    }

    func testPricebookRejectsRepeatedIdentityMoneyAndProvenanceKeys() throws {
        let original = try fixture("pricebook")
        for (source, replacement) in [
            (#""id": "prices.fixture.1""#, #""id": "prices.fixture.1", "id": "prices.other.1""#),
            (#""revision": 1"#, #""revision": 1, "\u0072evision": 2"#),
            (#""amount": "0.80""#, #""amount": "0.80", "amount": "9.99""#),
            (#""verification_status": "estimated""#, #""verification_status": "estimated", "verification_status": "verified""#)
        ] {
            XCTAssertThrowsError(try Pricebook.decode(replacing(original, source, replacement)), source) { error in
                XCTAssertEqual(error as? ContractJSONError, .duplicateKey)
            }
        }
    }

    func testEvaluationRejectsRepeatedIdentityResultAndFindingKeys() throws {
        let original = try fixture("evaluation-report")
        for (source, replacement) in [
            (#""build_revision": 1"#, #""build_revision": 1, "build_revision": 2"#),
            (#""result": "valid""#, #""result": "valid", "\u0072esult": "invalid""#),
            (#""outcome": "pass""#, #""outcome": "pass", "outcome": "unknown""#)
        ] {
            XCTAssertThrowsError(try EvaluationReport.decode(replacing(original, source, replacement)), source) { error in
                XCTAssertEqual(error as? ContractJSONError, .duplicateKey)
            }
        }
    }

    private func reportWithObserved(_ rawValue: String) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(fixture("evaluation-report").utf8)) as? [String: Any])
        var finding = try XCTUnwrap((object["findings"] as? [[String: Any]])?.first)
        finding["evidence"] = [["path": "", "observed": "RAW_VALUE_PLACEHOLDER"]]
        object["findings"] = [finding]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        return try replacing(text, #""RAW_VALUE_PLACEHOLDER""#, rawValue)
    }

    func testRepeatedNullAndUnicodeEquivalentEvidenceKeysRejectWithoutEchoingInput() throws {
        for raw in [
            #"{"private-key":null,"private-key":"PRIVATE_VALUE"}"#,
            #"{"\u0061":null,"a":true}"#,
            #"{"é":null,"e\u0301":true}"#
        ] {
            XCTAssertThrowsError(try EvaluationReport.decode(reportWithObserved(raw))) { error in
                XCTAssertEqual(error as? ContractJSONError, .duplicateKey)
                XCTAssertFalse(String(describing: error).contains("private-key"))
                XCTAssertFalse(String(describing: error).contains("PRIVATE_VALUE"))
            }
        }
    }

    func testIndependentObjectsAndStructuralCharactersInsideStringsRemainValid() throws {
        let note = #"A quote: "; a slash: \; punctuation: {"amount":0},[]:; café 🚀"#
        let encoded = String(decoding: try JSONEncoder().encode(note), as: UTF8.self)
        let data = try replacing(fixture("pricebook"), #""Illustrative price, NOT a live market quote.""#, encoded)
        let book = try Pricebook.decode(data)
        XCTAssertEqual(book.rates.count, 2)
        XCTAssertEqual(book.rates[0].provenance.notes, note)
        XCTAssertEqual(book.rates[1].provenance.notes, note)
        XCTAssertEqual(book.rates[0].unitPrice.amount.rawValue, "0.80")
        XCTAssertEqual(book.rates[0].provenance.verificationStatus, .estimated)

        let report = try EvaluationReport.decode(reportWithObserved(#"[{"key":null},{"key":true}]"#))
        XCTAssertEqual(report.findings[0].evidence?[0].observed, .array([.object(["key": .null]), .object(["key": .bool(true)])]))
    }

    func testEscapedUniqueKeysAndExistingIntegerRepresentationsArePreserved() throws {
        let original = try fixture("pricebook")
        for token in ["1", "1.0", "1e0", String(Int.max)] {
            let data = try replacing(original, #""revision": 1"#, #""\u0072evision": "# + token)
            let expected = token == String(Int.max) ? Int.max : 1
            XCTAssertEqual(try Pricebook.decode(data).revision, expected)
        }
    }

    func testInvalidUTF8IsRejected() throws {
        let invalid = Data([0xff])
        XCTAssertThrowsError(try Pricebook.decode(invalid)) { error in
            XCTAssertEqual(error as? ContractJSONError, .invalidUTF8)
        }
        XCTAssertThrowsError(try EvaluationReport.decode(invalid)) { error in
            XCTAssertEqual(error as? EvaluationBoundaryError, .invalidUTF8)
        }
        for malformed in [Data([0xff, 0xfe, 0x7b]), Data([0, 0, 0xfe, 0xff, 0, 0, 0])] {
            XCTAssertThrowsError(try Pricebook.decode(malformed))
        }
    }

    private func pricebookEncodings(_ text: String) throws -> [(String, Data)] {
        var forms: [(String, Data)] = [("UTF-8", Data(text.utf8)), ("UTF-8 BOM", Data([0xef, 0xbb, 0xbf]) + Data(text.utf8))]
        let byteOrders: [(String, String.Encoding, [UInt8])] = [
            ("UTF-16LE", .utf16LittleEndian, [0xff, 0xfe]),
            ("UTF-16BE", .utf16BigEndian, [0xfe, 0xff]),
            ("UTF-32LE", .utf32LittleEndian, [0xff, 0xfe, 0, 0]),
            ("UTF-32BE", .utf32BigEndian, [0, 0, 0xfe, 0xff])
        ]
        for (name, encoding, bom) in byteOrders {
            let encoded = try XCTUnwrap(text.data(using: encoding))
            forms.append((name, encoded))
            // Foundation versions differ on UTF-32LE with BOM. The original
            // decoder remains authoritative; do not require a new accepted form.
            if encoding != .utf32LittleEndian { forms.append((name + " BOM", Data(bom) + encoded)) }
        }
        return forms
    }

    func testEncodingCompatibilityPreservesUTF8BOMAtBothEntryPoints() throws {
        let bom = Data([0xef, 0xbb, 0xbf])
        XCTAssertEqual(try Pricebook.decode(bom + Data(fixture("pricebook").utf8)).id, "prices.fixture.1")
        XCTAssertEqual(try EvaluationReport.decode(bom + Data(fixture("evaluation-report").utf8)).buildRevision, 1)
    }

    func testEncodingCompatibilityPreservesPricebookByteOrdersAndOriginalValues() throws {
        let original = try fixture("pricebook")
        let text = original.replacingOccurrences(of: #""Illustrative price, NOT a live market quote.""#, with: #""café 🚀 \u0000""#)
        for (name, data) in try pricebookEncodings(text) {
            do {
                let book = try Pricebook.decode(data)
                XCTAssertEqual(book.id, "prices.fixture.1", name)
                XCTAssertEqual(book.revision, 1, name)
                XCTAssertEqual(book.rates[0].unitPrice.amount.rawValue, "0.80", name)
                XCTAssertEqual(book.rates[0].provenance.notes, "café 🚀 \u{0}", name)
            } catch { XCTFail("\(name): \(error)") }
        }
    }

    func testEncodingCompatibilityRejectsDuplicateAliasesInEveryPricebookByteOrder() throws {
        let text = try fixture("pricebook").replacingOccurrences(of: #""revision": 1"#, with: #""revision": 1, "\u0072evision": 2"#)
        for (name, data) in try pricebookEncodings(text) {
            XCTAssertThrowsError(try Pricebook.decode(data), name) { error in
                XCTAssertEqual(error as? ContractJSONError, .duplicateKey, name)
            }
        }
        let report = try replacing(fixture("evaluation-report"), #""build_revision": 1"#, #""build_revision": 1, "\u0062uild_revision": 2"#)
        XCTAssertThrowsError(try EvaluationReport.decode(Data([0xef, 0xbb, 0xbf]) + report)) { error in
            XCTAssertEqual(error as? ContractJSONError, .duplicateKey)
        }
    }

    func testEncodingCompatibilityCannotBypassReportNumericLimits() throws {
        for token in ["1e101", "1e-101", "1234567890123456"] {
            let raw = try reportWithObserved(token)
            for prefix in [Data(), Data([0xef, 0xbb, 0xbf])] {
                XCTAssertThrowsError(try EvaluationReport.decode(prefix + raw)) { error in
                    XCTAssertEqual(error as? EvaluationBoundaryError, .unsupportedNumber)
                }
            }
            let text = try XCTUnwrap(String(data: raw, encoding: .utf8))
            for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
                let data = try XCTUnwrap(text.data(using: encoding))
                XCTAssertThrowsError(try EvaluationReport.decode(data), "\(encoding): \(token)") { error in
                    XCTAssertEqual(error as? EvaluationBoundaryError, .invalidUTF8)
                }
            }
        }
    }

    func testEncodingCompatibilityPreservesEscapedNULAndRejectsRawNUL() throws {
        for prefix in [Data(), Data([0xef, 0xbb, 0xbf])] {
            let valid = try reportWithObserved(#""\u0000""#)
            XCTAssertEqual(try EvaluationReport.decode(prefix + valid).findings[0].evidence?[0].observed, .string("\u{0}"))
            let raw = try reportWithObserved("\"\u{0}\"")
            XCTAssertThrowsError(try EvaluationReport.decode(prefix + raw)) { error in
                XCTAssertEqual(error as? EvaluationBoundaryError, .invalidUTF8)
            }
        }
    }

    func testEncodingCompatibilityCapsOriginalBytesBeforeTranscoding() throws {
        let original = try fixture("pricebook")
        let marker = #""Illustrative price, NOT a live market quote.""#
        let range = try XCTUnwrap(original.range(of: marker))
        let count = (Pricebook.maximumPayloadBytes - original.utf16.count * 2) / 2
        let text = original.replacingCharacters(in: range, with: "\"" + String(repeating: "\u{800}", count: count) + "\"")
        var data = try XCTUnwrap(text.data(using: .utf16LittleEndian))
        XCTAssertGreaterThan(text.utf8.count, Pricebook.maximumPayloadBytes)
        XCTAssertLessThan(data.count, Pricebook.maximumPayloadBytes)
        XCTAssertEqual(try Pricebook.decode(data).rates[0].provenance.notes?.unicodeScalars.count, count)
        data.append(Data(repeating: 0, count: Pricebook.maximumPayloadBytes + 1 - data.count))
        XCTAssertThrowsError(try Pricebook.decode(data)) { error in
            XCTAssertEqual(error as? Pricebook.BoundaryError, .payloadTooLarge)
        }
    }

    func testMalformedFramingAndStringEscapesCannotBypassTypedDecoding() throws {
        for raw in ["", "{", "[1,]", #"{"x":"unterminated}"#, "null null", #"{"x":1,}"#, #"{"x" 1}"#] {
            XCTAssertThrowsError(try Pricebook.decode(Data(raw.utf8)))
            XCTAssertThrowsError(try EvaluationReport.decode(Data(raw.utf8)))
        }
        for raw in [#""bad\qescape""#, #""\uD800""#, "\"line\nbreak\""] {
            let data = try replacing(fixture("pricebook"), #""Illustrative price, NOT a live market quote.""#, raw)
            XCTAssertThrowsError(try Pricebook.decode(data))
        }
    }

    func testDepthAndAggregateLimitsIncludeTheRootValue() throws {
        let depth = ContractJSONPreflight.maximumDepth
        let allowedDepth = String(repeating: "[", count: depth) + "null" + String(repeating: "]", count: depth)
        XCTAssertNoThrow(try ContractJSONPreflight.validate(allowedDepth))
        XCTAssertThrowsError(try ContractJSONPreflight.validate("[" + allowedDepth + "]")) { error in
            XCTAssertEqual(error as? ContractJSONError, .tooDeep)
        }

        let values = ContractJSONPreflight.maximumValues
        let atLimit = "[" + String(repeating: "null,", count: values - 2) + "null]"
        XCTAssertNoThrow(try ContractJSONPreflight.validate(atLimit))
        XCTAssertThrowsError(try ContractJSONPreflight.validate("[null," + String(atLimit.dropFirst()))) { error in
            XCTAssertEqual(error as? ContractJSONError, .tooComplex)
        }
    }

    func testBothEntryPointsEnforceComplexityBeforeDecoding() throws {
        let many = "[" + String(repeating: #""", "#, count: ContractJSONPreflight.maximumValues - 1) + #"""]"#
        let pricebook = try replacing(fixture("pricebook"), #""price_type": "estimate""#, #""price_type": "estimate", "conditions": "# + many)
        XCTAssertLessThan(pricebook.count, Pricebook.maximumPayloadBytes)
        XCTAssertThrowsError(try Pricebook.decode(pricebook)) { error in
            XCTAssertEqual(error as? ContractJSONError, .tooComplex)
        }
        XCTAssertThrowsError(try EvaluationReport.decode(reportWithObserved(many))) { error in
            XCTAssertEqual(error as? ContractJSONError, .tooComplex)
        }
    }

    func testBothEntryPointsEnforceDepthBeforeUnknownFieldValidation() throws {
        let depth = ContractJSONPreflight.maximumDepth + 1
        let nested = String(repeating: "[", count: depth) + "null" + String(repeating: "]", count: depth)
        for name in ["pricebook", "evaluation-report"] {
            let raw = try fixture(name)
            let data = Data((#"{"unsupported":"# + nested + "," + raw.dropFirst()).utf8)
            XCTAssertThrowsError(try name == "pricebook" ? Pricebook.decode(data).id : EvaluationReport.decode(data).id) { error in
                XCTAssertEqual(error as? ContractJSONError, .tooDeep)
            }
        }
    }

    func testPricebookByteLimitStillAllowsWhitespaceWithoutCountingValues() throws {
        var data = Data(try fixture("pricebook").utf8)
        data.append(Data(repeating: 0x20, count: Pricebook.maximumPayloadBytes - data.count))
        XCTAssertEqual(try Pricebook.decode(data).id, "prices.fixture.1")
        data.append(0x20)
        XCTAssertThrowsError(try Pricebook.decode(data)) { error in
            XCTAssertEqual(error as? Pricebook.BoundaryError, .payloadTooLarge)
        }
    }

    func testSharedRawWireVectorsAreNeverParsedBeforeTheBoundary() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "raw-contract-vectors", withExtension: "json"))
        let bundle = try JSONDecoder().decode(VectorBundle.self, from: Data(contentsOf: url))
        XCTAssertEqual(bundle.cases.count, 20)
        for vector in bundle.cases {
            var raw = try fixture(vector.fixture)
            for replacement in vector.replacements {
                XCTAssertEqual(replacement.count, 2)
                guard replacement.count == 2 else { continue }
                XCTAssertTrue(raw.contains(replacement[0]), vector.id)
                raw = raw.replacingOccurrences(of: replacement[0], with: replacement[1])
            }
            let data = Data(raw.utf8)
            func decode() throws {
                switch vector.fixture {
                case "pricebook": _ = try Pricebook.decode(data)
                case "evaluation-report": _ = try EvaluationReport.decode(data)
                default: XCTFail("Unknown raw-wire fixture")
                }
            }
            if vector.valid { XCTAssertNoThrow(try decode(), vector.id) }
            else { XCTAssertThrowsError(try decode(), vector.id) }
        }
    }
}
