import Foundation
import XCTest
@testable import PlannerCore

final class EvaluationJSONEqualityTests: XCTestCase {
    private func report(_ json: String?, field: String = "observed") throws -> EvaluationReport {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "evaluation-report", withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "evaluation-report", withExtension: "json")
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var findings = try XCTUnwrap(object["findings"] as? [[String: Any]])
        var evidence: [String: Any] = ["path": "synthetic.exact-json"]
        if json != nil { evidence[field] = "EXACT_JSON_EQUALITY_TOKEN" }
        findings[0]["evidence"] = [evidence]
        object["findings"] = findings
        var text = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
        if let json {
            let marker = "\"EXACT_JSON_EQUALITY_TOKEN\""
            XCTAssertEqual(text.components(separatedBy: marker).count, 2)
            text = text.replacingOccurrences(of: marker, with: json)
        }
        return try EvaluationReport.decode(Data(text.utf8))
    }

    private func observed(_ report: EvaluationReport) throws -> EvaluationJSONValue {
        try XCTUnwrap(report.findings.first?.evidence?.first?.observed)
    }

    func testStringEvidenceDistinguishesCanonicalUnicodeSpellings() throws {
        let pairs = [
            (#""\u00e9""#, #""e\u0301""#),
            (#""\uac00""#, #""\u1100\u1161""#)
        ]
        for (leftJSON, rightJSON) in pairs {
            let left = try observed(report(leftJSON))
            let right = try observed(report(rightJSON))
            guard case .string(let leftText) = left, case .string(let rightText) = right else {
                return XCTFail("The fixture must decode as two strings")
            }
            XCTAssertEqual(leftText, rightText) // Swift text equivalence is the regression control.
            XCTAssertFalse(leftText.utf8.elementsEqual(rightText.utf8))
            XCTAssertNotEqual(left, right)
            XCTAssertNotEqual(right, left)
        }
    }

    func testObjectMemberEvidenceDistinguishesCanonicalUnicodeSpellings() throws {
        let left = try observed(report(#"{"\u00e9":true,"safe":null}"#))
        let right = try observed(report(#"{"e\u0301":true,"safe":null}"#))
        guard case .object(let leftObject) = left, case .object(let rightObject) = right else {
            return XCTFail("The fixture must decode as two objects")
        }
        XCTAssertEqual(leftObject.count, 2)
        XCTAssertEqual(rightObject.count, 2)
        let leftKey = try XCTUnwrap(leftObject.keys.first { $0 != "safe" })
        let rightKey = try XCTUnwrap(rightObject.keys.first { $0 != "safe" })
        XCTAssertEqual(leftKey, rightKey)
        XCTAssertFalse(leftKey.utf8.elementsEqual(rightKey.utf8))
        XCTAssertNotEqual(left, right)
        XCTAssertNotEqual(right, left)
    }

    func testNestedEvidenceChangesRemainVisibleInDecodedReports() throws {
        let pairs = [
            (#"{"items":[{"value":"\u00e9"}]}"#, #"{"items":[{"value":"e\u0301"}]}"#),
            (#"{"items":[{"\u00e9":{"value":true}}]}"#, #"{"items":[{"e\u0301":{"value":true}}]}"#)
        ]
        for field in ["observed", "expected"] {
            for (leftJSON, rightJSON) in pairs {
                let left = try report(leftJSON, field: field)
                let right = try report(rightJSON, field: field)
                XCTAssertEqual(left.findings.count, right.findings.count)
                XCTAssertEqual(left.summary, right.summary)
                XCTAssertEqual(left.result, right.result)
                XCTAssertEqual(left.deploymentReadiness, right.deploymentReadiness)
                XCTAssertNotEqual(left.findings[0].evidence, right.findings[0].evidence)
                XCTAssertNotEqual(left, right)
                XCTAssertNotEqual(right, left)
                let leftRoundTrip = try EvaluationReport.decode(JSONEncoder().encode(left))
                let rightRoundTrip = try EvaluationReport.decode(JSONEncoder().encode(right))
                XCTAssertEqual(leftRoundTrip, left)
                XCTAssertEqual(rightRoundTrip, right)
                XCTAssertNotEqual(leftRoundTrip, rightRoundTrip)
            }
        }
    }

    func testEquivalentJSONEscapesRetainEqualDecodedValues() throws {
        let pairs = [
            (#""\u00e9""#, "\"\u{00e9}\""),
            (#""e\u0301""#, "\"e\u{0301}\""),
            (#""a\\b""#, #""a\u005Cb""#),
            (#"{"\u00e9":true}"#, "{\"\u{00e9}\":true}")
        ]
        for (leftJSON, rightJSON) in pairs {
            let left = try report(leftJSON)
            let right = try report(rightJSON)
            XCTAssertEqual(try observed(left), try observed(right))
            XCTAssertEqual(left, right)
            XCTAssertEqual(right, left)
        }
    }

    func testObjectOrderAndEquivalentDecimalValuesRemainEqual() throws {
        let left = try report(#"{"a":1.00,"b":[true,null,"\u00e9"],"zero":-0}"#)
        let right = try report(#"{"zero":0,"b":[true,null,"\u00e9"],"a":1e0}"#)
        XCTAssertEqual(try observed(left), try observed(right))
        XCTAssertEqual(left, right)
        XCTAssertEqual(right, left)
        XCTAssertEqual(left, try EvaluationReport.decode(JSONEncoder().encode(left)))
    }

    func testArrayOrderTypesAndAbsentNullRemainDistinct() throws {
        let pairs = [
            ("null", "false"), ("true", "1"), ("1", #""1""#),
            ("[true,null]", "[null,true]"), ("{}", "[]"),
            ("[false]", "[false,false]"), (#"{"x":true}"#, #"{"x":false}"#)
        ]
        for (leftJSON, rightJSON) in pairs {
            XCTAssertNotEqual(try observed(report(leftJSON)), try observed(report(rightJSON)))
        }
        let absent = try report(nil)
        let explicitNull = try report("null")
        XCTAssertNil(absent.findings[0].evidence?[0].observed)
        XCTAssertEqual(explicitNull.findings[0].evidence?[0].observed, .null)
        XCTAssertNotEqual(absent, explicitNull)
    }

    func testEquivalentDuplicateKeysRemainRejectedBeforeDictionaryCollapse() throws {
        for json in [
            #"{"\u00e9":true,"e\u0301":false}"#,
            #"{"name":true,"\u006eame":false}"#,
            #"{"items":[{"\u00e9":true,"e\u0301":false}]}"#
        ] {
            XCTAssertThrowsError(try report(json)) { error in
                XCTAssertEqual(error as? ContractJSONError, .duplicateKey)
            }
        }
    }
}
