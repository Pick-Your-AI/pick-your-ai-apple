import Foundation
import XCTest
@testable import PlannerTransfer

final class BuildTransferTests: XCTestCase {
    func fixture() throws -> [String: JSONValue] {
        var parser = try JSONParser(Data(contentsOf: Bundle.module.url(forResource: "build", withExtension: "json")!))
        return try XCTUnwrap(parser.parse().object)
    }
    func encode(_ object: [String: JSONValue]) throws -> Data { try JSONEncoder().encode(JSONValue.object(object)) }
    func publicSource() throws -> [String: JSONValue] {
        var source = try fixture()
        source["selections"] = .array(source["selections"]!.array!.map { selection in
            var item = selection.object!
            var settings = item["settings"]!.object!
            // Explicit synthetic input without a private infrastructure index name.
            settings.removeValue(forKey: "index_name")
            item["settings"] = .object(settings)
            return .object(item)
        })
        return source
    }
    func publicFixture() throws -> Data {
        try BuildTransfer.export(BuildTransfer.snapshot(fromDraftJSON: encode(publicSource())), publicOwnerAlias: "public.alias")
    }
    func testCanonicalConformanceCorpus() throws {
        var parser = try JSONParser(Data(contentsOf: Bundle.module.url(forResource: "conformance", withExtension: "json")!))
        let cases = try XCTUnwrap(parser.parse().array)
        XCTAssertEqual(cases.count, 129)
        let validator = try FrozenValidator()
        for item in cases {
            let object = item.object!
            let schemaName = object["schema"]!.string!
            let expected = object["valid"]! == .bool(true)
            do {
                try validator.check(object["payload"]!, schema: validator.schemas[schemaName]!, document: schemaName)
                XCTAssertTrue(expected, object["name"]!.string!)
            } catch {
                XCTAssertFalse(expected, object["name"]!.string!)
            }
        }
    }
    func testCanonicalFixtureAndExactLockPreservation() throws {
        let original = try fixture()
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: encode(original))
        XCTAssertEqual(snapshot.locks, original["locks"])
        let preview = try BuildTransfer.preview(publicFixture())
        let fork = try preview.fork(localOwner: "local.test", timestamp: "2026-10-18T12:00:00Z")
        XCTAssertNotEqual(fork.id, snapshot.id)
        XCTAssertEqual(fork.locks, snapshot.locks)
        XCTAssertEqual(fork.value.object?["selections"], preview.snapshot.value.object?["selections"])
        XCTAssertEqual(fork.value.object?["revision"], .number(1))
        XCTAssertEqual(fork.value.object?["lifecycle"], .string("draft"))
        XCTAssertEqual(fork.value.object?["owner_ref"], .string("local.test"))
        XCTAssertEqual(snapshot.value, .object(original))
    }
    func testEmptyDraftRejectedWithoutMutation() throws {
        let draft = Data(#"{"name":"An unfinished draft","selections":[]}"#.utf8)
        let before = draft
        XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: draft))
        XCTAssertEqual(draft, before)
        var complete = try fixture(); complete["selections"] = .array([])
        XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: encode(complete)))
    }
    func testLocalSnapshotEncodingPreservesPrivateFieldsAndReopensExactly() throws {
        var source = try fixture()
        var selections = try XCTUnwrap(source["selections"]?.array)
        var selection = try XCTUnwrap(selections.first?.object)
        selection["notes"] = .string("Private local workload notes")
        selections[0] = .object(selection)
        source["selections"] = .array(selections)
        source["extensions"] = .object(["x_private": .string("Private local metadata")])
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: encode(source))
        let reopened = try BuildTransfer.snapshot(fromDraftJSON: snapshot.encoded())
        XCTAssertEqual(reopened, snapshot)
        XCTAssertEqual(reopened.value, .object(source))
        XCTAssertEqual(reopened.locks, source["locks"])
        // A successful local serialization must not silently become a disclosure
        // projection, and private fields still cannot pass the import boundary.
        XCTAssertThrowsError(try BuildTransfer.preview(snapshot.encoded())) {
            XCTAssertEqual($0 as? TransferError, .sensitiveContent)
        }
    }
    func testSnapshotEncodingRejectsExpansionPastItsDecodeLimit() throws {
        var source = try fixture()
        source["extensions"] = .object(["x_padding": .string(String(repeating: "/", count: 270_000))])
        let object = try JSONSerialization.jsonObject(with: encode(source))
        let compact = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertLessThan(compact.count, BuildTransfer.maximumBytes)
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: compact)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertGreaterThan(try encoder.encode(snapshot.value).count, BuildTransfer.maximumBytes)
        XCTAssertThrowsError(try snapshot.encoded()) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        // Rejection leaves the original validated immutable value and its input
        // available; it does not return bytes that a persistence reader cannot use.
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: compact), snapshot)
    }
    func testAll29SelectionKindsUseTheirConditionalSettings() throws {
        let validator = try FrozenValidator()
        let schema = try XCTUnwrap(validator.schemas["selection.schema.json"])
        let kinds = try XCTUnwrap(schema.object?["properties"]?.object?["kind"]?.object?["enum"]?.array)
        XCTAssertEqual(kinds.count, 29)
        // Required settings are generated from the frozen schema, not alternate client enums.
        for kind in kinds {
            let settingsSchema = schema.object?["$defs"]?.object?["settings_" + kind.string!]!
            let settings = try minimal(settingsSchema!, document: schema)
            var selection: [String: JSONValue] = ["id": .string("sel_test"), "kind": kind, "catalog_item_id": .string("catalog.test"), "catalog_item_version": .string("1"), "role": .string("primary"), "enabled": .bool(true), "settings": settings]
            try validator.check(.object(selection), schema: schema, document: "selection.schema.json")
            var bad = settings.object!; bad["unrecognized"] = .bool(true); selection["settings"] = .object(bad)
            XCTAssertThrowsError(try validator.check(.object(selection), schema: schema, document: "selection.schema.json"), kind.string!)
            selection["settings"] = settings; selection["enabled"] = .number(1)
            XCTAssertThrowsError(try validator.check(.object(selection), schema: schema, document: "selection.schema.json"))
        }
    }
    private func minimal(_ schema: JSONValue, document: JSONValue) throws -> JSONValue {
        let s = schema.object!
        if let options = s["enum"]?.array { return options[0] }
        if let ref = s["$ref"]?.string {
            if ref.contains("secret_ref") { return .string("secret://test/reference") }
            throw TransferError.unavailableSchema
        }
        switch s["type"]?.string {
        case "object":
            var result: [String: JSONValue] = [:]
            for key in s["required"]?.array ?? [] { result[key.string!] = try minimal(s["properties"]!.object![key.string!]!, document: document) }
            return .object(result)
        case "array": return .array([])
        case "integer", "number": return .number(s["minimum"]?.number ?? 1)
        case "boolean": return .bool(false)
        case "string":
            if s["format"] == .string("uri") { return .string("https://example.invalid/test") }
            return .string("test")
        default: throw TransferError.unavailableSchema
        }
    }
    func testMaliciousBoundariesAndRedactedErrors() throws {
        for bytes in [Data(repeating: 32, count: BuildTransfer.maximumBytes + 1), Data(#"{"a":1,"\u0061":2}"#.utf8), Data((String(repeating: "[", count: 50) + "0" + String(repeating: "]", count: 50)).utf8), Data(#"{"secret":"do-not-echo"}"#.utf8), Data(#"{"schema_version":"2.0.0"}"#.utf8), Data([0xff]), Data(#"{"x":1e999}"#.utf8)] {
            XCTAssertThrowsError(try BuildTransfer.preview(bytes)) { error in XCTAssertFalse(String(describing: error).contains("do-not-echo")) }
        }
    }
    func testUnknownFieldsDecimalTypesDatesAndEnums() throws {
        let original = try fixture()
        for (key, value) in [("unexpected", JSONValue.bool(true)), ("revision", .bool(true)), ("lifecycle", .string("approved")), ("created_at", .string("2026-02-30T00:00:00Z")), ("id", .string("build.bad\n"))] {
            var bad = original; bad[key] = value
            XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: encode(bad)))
        }
        var bad = original; bad.removeValue(forKey: "locks")
        XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: encode(bad)))
        var objectives = original["objectives"]!.object!; objectives["monthly_budget_amount"] = .number(100)
        bad = original; bad["objectives"] = .object(objectives)
        XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: encode(bad)))
    }
    func testPrivateProjectionAndSecretReferences() throws {
        var original = try publicSource(); original["extensions"] = .object(["x_private": .string("PRIVATE")])
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: encode(original))
        XCTAssertThrowsError(try BuildTransfer.preview(snapshot.encoded()))
        let output = try BuildTransfer.export(snapshot, publicOwnerAlias: "public.alias")
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("PRIVATE"))
        XCTAssertEqual(try BuildTransfer.preview(output).snapshot.value.object?["owner_ref"], .string("public.alias"))
        var object = try BuildTransfer.preview(output).snapshot.value.object!
        object["name"] = .string("secret://private/ref")
        let secret = try BuildTransfer.snapshot(fromDraftJSON: encode(object))
        XCTAssertThrowsError(try BuildTransfer.export(secret, publicOwnerAlias: "public.alias"))
        XCTAssertThrowsError(try BuildTransfer.preview(secret.encoded()))
    }
    func testResourceAndPrivateInfrastructureLimits() throws {
        let many = Data(("[" + Array(repeating: "0", count: 16_384).joined(separator: ",") + "]").utf8)
        XCTAssertThrowsError(try BuildTransfer.preview(many)) { XCTAssertEqual($0 as? TransferError, .tooComplex) }
        for uri in ["https://example.invalid/a%20b?x=1&y=2#fragment", "mailto:test@example.invalid", "urn:example:test", "file:///tmp/example"] {
            XCTAssertTrue(FrozenValidator.uri(uri), uri)
        }
        XCTAssertFalse(FrozenValidator.uri("http://[::1]/")) // Documented unsupported subset.
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: encode(fixture()))
        // The canonical synthetic fixture has an index_name; do not leak private infrastructure.
        XCTAssertThrowsError(try BuildTransfer.export(snapshot, publicOwnerAlias: "public.alias")) { XCTAssertEqual($0 as? TransferError, .sensitiveContent) }
    }
    func testEnvelopeAndUntrustedOwner() throws {
        let snapshot = try BuildTransfer.preview(publicFixture()).snapshot
        var envelope: [String: JSONValue] = ["format": .string("pickyour.ai/build-export"), "formatVersion": .number(1), "exportedAt": .string("2026-10-18T00:00:00Z"), "contract": .object(["version": .string("1.0.0"), "sourceSha": .string(String(repeating: "a", count: 40))]), "dataMode": .string("fixture"), "build": snapshot.value]
        XCTAssertEqual(try BuildTransfer.preview(encode(envelope)).usesSyntheticData, true)
        envelope["formatVersion"] = .number(2)
        XCTAssertThrowsError(try BuildTransfer.preview(encode(envelope)))
        XCTAssertThrowsError(try BuildTransfer.preview(publicFixture()).fork(localOwner: "", timestamp: "2026-10-18T00:00:00Z"))
    }
}


extension BuildTransferTests {
    func testExponentNumbersRemainAcceptedAfterEncoding() throws {
        for token in ["1e15", "1.23456789e-12", "1000000000000000", "0.00000000000123456789", "1.230000000000000000", "-0", "0e-64", "-0.000e+64"] {
            var parser = try JSONParser(Data(token.utf8))
            let value = try parser.parse()
            var reparsed = try JSONParser(JSONEncoder().encode(value))
            XCTAssertEqual(try reparsed.parse(), value, token)
        }
        for token in ["1e-999", "1e999", "1.234567890123456", "0.0000000000001", "0." + String(repeating: "0", count: 60) + "1e-64"] {
            var parser = try JSONParser(Data(token.utf8))
            XCTAssertThrowsError(try parser.parse(), token)
        }
    }
    func testExponentRevisionSurvivesSnapshotExportAndPreview() throws {
        var source = try publicSource()
        source["revision"] = .number(Decimal(1_000_000_000_000_000))
        let plain = String(decoding: try encode(source), as: UTF8.self)
        let exponent = plain.replacingOccurrences(of: "1000000000000000", with: "1e15")
        XCTAssertNotEqual(plain, exponent)
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: Data(exponent.utf8))
        let exported = try BuildTransfer.export(snapshot, publicOwnerAlias: "public.alias")
        let preview = try BuildTransfer.preview(exported)
        XCTAssertEqual(preview.snapshot.value.object?["revision"], source["revision"])
        XCTAssertEqual(try BuildTransfer.preview(BuildTransfer.export(preview.snapshot, publicOwnerAlias: "public.alias")).snapshot.value,
                       preview.snapshot.value)
    }
}
