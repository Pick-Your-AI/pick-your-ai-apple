import Foundation
import XCTest
@testable import PlannerTransfer

private struct RulesetVector: Decodable {
    let name: String
    let json: String
    let canonicalValid: Bool
    let clientValid: Bool
}

final class RulesetTests: XCTestCase {
    private func fixture(singleRule: Bool = false) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ruleset", withExtension: "json"))
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        if singleRule { value["rules"] = Array(try XCTUnwrap(value["rules"] as? [[String: Any]]).prefix(1)) }
        return value
    }

    private func encoded(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }

    func testCompleteCanonicalRulesetPreservesMetadataEveryRuleAndRoundTrip() throws {
        let source = try fixture()
        let data = try encoded(source)
        let ruleset = try Ruleset.decode(data)
        XCTAssertEqual(ruleset.id, "rules.fixture.1")
        XCTAssertEqual(ruleset.version, "1.0.0")
        XCTAssertEqual(ruleset.publishedAt, "2026-10-16T09:00:00Z")
        XCTAssertEqual(ruleset.rules.count, 45)
        let rules = try XCTUnwrap(source["rules"] as? [[String: Any]])
        XCTAssertEqual(ruleset.rules.map { $0.object?["id"]?.string },
                       rules.map { $0["id"] as? String })
        var parser = try JSONParser(data)
        XCTAssertEqual(ruleset.value, try parser.parse())
        XCTAssertEqual(try Ruleset.decode(ruleset.encoded()), ruleset)
    }

    func testSharedCanonicalSyntaxVectorsRejectEveryMalformedAlternative() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ruleset-conformance", withExtension: "json"))
        let cases = try JSONDecoder().decode([RulesetVector].self, from: Data(contentsOf: url))
        XCTAssertEqual(cases.count, 321)
        XCTAssertEqual(Set(cases.map(\.name)).count, cases.count)
        for vector in cases {
            // Replay the exact shared JSON string without Foundation number
            // bridging or mutation/serialization between corpus and decoder.
            let data = Data(vector.json.utf8)
            do {
                let ruleset = try Ruleset.decode(data)
                XCTAssertTrue(vector.clientValid, vector.name)
                var parser = try JSONParser(data)
                XCTAssertEqual(ruleset.value, try parser.parse(), vector.name)
                XCTAssertEqual(try Ruleset.decode(ruleset.encoded()), ruleset, vector.name)
            } catch {
                XCTAssertFalse(vector.clientValid, "\(vector.name): \(error)")
            }
        }
        XCTAssertEqual(cases.filter { $0.canonicalValid != $0.clientValid }.count, 3)
    }

    func testOneOfRequiresExactlyOneMatchAndPropagatesSchemaFailures() throws {
        let validator = try FrozenValidator(schemaNames: ["ruleset", "common"])
        let unrestricted = JSONValue.object([:])
        let string = JSONValue.object(["type": .string("string")])
        func check(_ value: JSONValue, _ alternatives: [JSONValue]) throws {
            try validator.check(value, schema: .object(["oneOf": .array(alternatives)]),
                                document: "ruleset.schema.json")
        }
        XCTAssertNoThrow(try check(.null, [unrestricted, string]))
        for (value, alternatives) in [
            (JSONValue.null, [string]),
            (.string("matches twice"), [unrestricted, string]),
            (.null, [unrestricted, unrestricted]),
            (.null, [])
        ] {
            XCTAssertThrowsError(try check(value, alternatives)) {
                XCTAssertEqual($0 as? TransferError, .schemaViolation)
            }
        }
        let missing = JSONValue.object(["$ref": .string("missing.schema.json")])
        for alternatives in [[unrestricted, missing], [missing, unrestricted]] {
            XCTAssertThrowsError(try check(.null, alternatives)) {
                XCTAssertEqual($0 as? TransferError, .unavailableSchema)
            }
        }
    }

    func testUnknownPolicyAndLiteralValuesRemainUnevaluatedAndUnchanged() throws {
        var source = try fixture(singleRule: true)
        var rule = try XCTUnwrap((source["rules"] as? [[String: Any]])?.first)
        rule["owner"] = nil
        rule["on_unknown"] = "defer"
        rule["severity"] = "info"
        rule["applies_when"] = ["op": "exists", "value": ["literal": false]] as [String: Any]
        rule["assert"] = ["op": "eq", "left": ["literal": NSNull()], "right": ["literal": true]] as [String: Any]
        source["rules"] = [rule]
        let ruleset = try Ruleset.decode(encoded(source))
        let retained = try XCTUnwrap(ruleset.rules.first?.object)
        XCTAssertNil(retained["owner"])
        XCTAssertEqual(retained["on_unknown"], .string("defer"))
        XCTAssertEqual(retained["severity"], .string("info"))
        XCTAssertEqual(retained["applies_when"]?.object?["value"]?.object?["literal"], .bool(false))
        XCTAssertEqual(retained["assert"]?.object?["left"]?.object?["literal"], JSONValue.null)
        XCTAssertEqual(retained["assert"]?.object?["right"]?.object?["literal"], .bool(true))
        XCTAssertEqual(try Ruleset.decode(ruleset.encoded()), ruleset)
    }

    func testRepeatedRuleIdentitiesAndOrderRemainAvailableForReceivingPolicy() throws {
        var source = try fixture(singleRule: true)
        let one = try XCTUnwrap((source["rules"] as? [[String: Any]])?.first)
        var two = one; two["message"] = "Different synthetic statement."
        source["rules"] = [one, two, one]
        let ruleset = try Ruleset.decode(encoded(source))
        XCTAssertEqual(ruleset.rules.count, 3)
        XCTAssertEqual(ruleset.rules[0], ruleset.rules[2])
        XCTAssertNotEqual(ruleset.rules[0], ruleset.rules[1])
        XCTAssertEqual(ruleset.rules[0].object?["id"], ruleset.rules[1].object?["id"])
        XCTAssertEqual(ruleset.rules[1].object?["message"], .string("Different synthetic statement."))
        XCTAssertEqual(try Ruleset.decode(ruleset.encoded()), ruleset)
    }

    func testDuplicateMetadataAndEscapedExpressionKeysAreRejected() throws {
        let original = try XCTUnwrap(String(data: encoded(fixture(singleRule: true)), encoding: .utf8))
        for key in ["published_at", #"published_\u0061t"#] {
            let duplicate = original.replacingOccurrences(of: "\"published_at\":",
                with: "\"\(key)\":\"2026-10-18T00:00:00Z\",\"published_at\":")
            XCTAssertNotEqual(original, duplicate)
            XCTAssertThrowsError(try Ruleset.decode(Data(duplicate.utf8))) {
                XCTAssertEqual($0 as? TransferError, .duplicateKey)
            }
        }
        let nested = original.replacingOccurrences(of: "\"op\":", with: #""\u006fp":"exists","op":"#)
        XCTAssertNotEqual(original, nested)
        XCTAssertThrowsError(try Ruleset.decode(Data(nested.utf8))) {
            XCTAssertEqual($0 as? TransferError, .duplicateKey)
        }
    }

    func testWholeArtifactBoundsApplyAcrossIndividuallyAdmissibleRules() throws {
        var source = try fixture(singleRule: true)
        var rule = try XCTUnwrap((source["rules"] as? [[String: Any]])?.first)
        rule["assert"] = ["op": "exists", "value": ["literal": String(repeating: "a", count: 270_000)]] as [String: Any]
        source["rules"] = [rule]
        XCTAssertNoThrow(try Ruleset.decode(encoded(source)))
        source["rules"] = [rule, rule]
        XCTAssertThrowsError(try Ruleset.decode(encoded(source))) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        rule["assert"] = ["op": "exists", "value": ["literal": Array(repeating: NSNull(), count: 9_000)]] as [String: Any]
        source["rules"] = [rule]
        XCTAssertNoThrow(try Ruleset.decode(encoded(source)))
        source["rules"] = [rule, rule]
        XCTAssertThrowsError(try Ruleset.decode(encoded(source))) {
            XCTAssertEqual($0 as? TransferError, .tooComplex)
        }
        var expression: [String: Any] = ["op": "exists", "value": ["literal": NSNull()]]
        for _ in 0..<50 { expression = ["op": "not", "arg": expression] }
        rule["assert"] = expression
        source["rules"] = [rule]
        XCTAssertThrowsError(try Ruleset.decode(encoded(source))) {
            XCTAssertEqual($0 as? TransferError, .tooDeep)
        }
    }

    func testEncodingExpansionIsRejectedWithoutChangingTheRuleset() throws {
        var source = try fixture(singleRule: true)
        var rule = try XCTUnwrap((source["rules"] as? [[String: Any]])?.first)
        rule["assert"] = ["op": "exists", "value": ["literal": String(repeating: "/", count: 270_000)]] as [String: Any]
        source["rules"] = [rule]
        let compact = try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertLessThan(compact.count, BuildTransfer.maximumBytes)
        let ruleset = try Ruleset.decode(compact)
        XCTAssertThrowsError(try ruleset.encoded()) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        XCTAssertEqual(try Ruleset.decode(compact), ruleset)
    }
}
