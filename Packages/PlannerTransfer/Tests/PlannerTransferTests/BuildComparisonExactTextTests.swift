import Foundation
import XCTest
@testable import PlannerTransfer

final class BuildComparisonExactTextTests: XCTestCase {
    private let composedVersion = "release-\u{00E9}"
    private let decomposedVersion = "release-e\u{0301}"

    private func snapshot(version: String, revision: Decimal) throws -> BuildSnapshot {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "build", withExtension: "json")!)
        var parser = try JSONParser(data)
        var fields = try XCTUnwrap(parser.parse().object)
        fields["revision"] = .number(revision)
        fields["selections"] = .array(try XCTUnwrap(fields["selections"]?.array).map { value in
            var selection = value.object!
            if selection["id"] == .string("sel_model") {
                selection["catalog_item_version"] = .string(version)
            }
            return .object(selection)
        })
        return try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(fields)))
    }

    func testDistinctUnicodeVersionPinsAppearAsARevisionDifference() throws {
        XCTAssertEqual(composedVersion, decomposedVersion, "The probe must exercise Swift canonical equality.")
        XCTAssertNotEqual(Array(composedVersion.utf8), Array(decomposedVersion.utf8))
        let before = try snapshot(version: composedVersion, revision: 1)
        let after = try snapshot(version: decomposedVersion, revision: 2)
        let result = try BuildComparison.compare(before, after)
        XCTAssertEqual(result.differences.count, 1)
        let difference = try XCTUnwrap(result.differences.first)
        XCTAssertEqual(difference.path, ["selections", "sel_model", "catalog_item_version"])
        guard case .value(.string(let old)) = difference.before,
              case .value(.string(let new)) = difference.after else {
            return XCTFail("Both public version pins must remain available.")
        }
        XCTAssertEqual(Array(old.utf8), Array(composedVersion.utf8))
        XCTAssertEqual(Array(new.utf8), Array(decomposedVersion.utf8))
    }

    func testDistinctUnicodeVersionPinsCannotClaimOneImmutableRevision() throws {
        let before = try snapshot(version: composedVersion, revision: 1)
        let after = try snapshot(version: decomposedVersion, revision: 1)
        XCTAssertThrowsError(try BuildComparison.compare(before, after)) {
            XCTAssertEqual($0 as? BuildComparisonError, .conflictingRevisionIdentity)
        }
    }

    func testDistinctUnicodeScopesRemainVisibleInsideAnArray() throws {
        var fields = try XCTUnwrap(snapshot(version: "release-1", revision: 1).value.object)
        func settingScope(_ scope: String) throws -> BuildSnapshot {
            fields["selections"] = .array(try XCTUnwrap(fields["selections"]?.array).map { value in
                var selection = value.object!
                if selection["id"] == .string("sel_tool") {
                    var settings = selection["settings"]!.object!
                    settings["allowed_scopes"] = .array([.string(scope)])
                    selection["settings"] = .object(settings)
                }
                return .object(selection)
            })
            return try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(fields)))
        }
        let before = try settingScope(composedVersion)
        fields["revision"] = .number(2)
        let after = try settingScope(decomposedVersion)
        let result = try BuildComparison.compare(before, after)
        XCTAssertEqual(result.differences.count, 1)
        let difference = try XCTUnwrap(result.differences.first)
        XCTAssertEqual(difference.path, ["selections", "sel_tool", "settings", "allowed_scopes"])
        guard case .value(.array(let old)) = difference.before,
              case .value(.array(let new)) = difference.after else {
            return XCTFail("The changed public scope array must remain available.")
        }
        XCTAssertEqual(old.count, 1)
        XCTAssertEqual(new.count, 1)
        XCTAssertEqual(Array(try XCTUnwrap(old.first?.string).utf8), Array(composedVersion.utf8))
        XCTAssertEqual(Array(try XCTUnwrap(new.first?.string).utf8), Array(decomposedVersion.utf8))
    }

    func testDistinctUnicodePrivateKeysConflictWithoutLeakingIntoAnotherRevision() throws {
        var fields = try XCTUnwrap(snapshot(version: "release-1", revision: 1).value.object)
        func withPrivateKey(_ key: String) throws -> BuildSnapshot {
            fields["extensions"] = .object(["x_private": .object([key: .string("PRIVATE-METADATA")])])
            return try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(fields)))
        }
        let before = try withPrivateKey(composedVersion)
        let sameRevision = try withPrivateKey(decomposedVersion)
        XCTAssertThrowsError(try BuildComparison.compare(before, sameRevision)) {
            XCTAssertEqual($0 as? BuildComparisonError, .conflictingRevisionIdentity)
            XCTAssertFalse(String(describing: $0).contains("PRIVATE-METADATA"))
        }
        fields["revision"] = .number(2)
        let after = try withPrivateKey(decomposedVersion)
        let result = try BuildComparison.compare(before, after)
        XCTAssertTrue(result.differences.isEmpty)
        XCTAssertFalse(String(describing: result).contains("PRIVATE-METADATA"))
        XCTAssertFalse(String(describing: result).contains("x_private"))
    }

    func testEquivalentEscapesNumbersWhitespaceAndObjectOrderPreserveRevisionIdentity() throws {
        let before = try snapshot(version: composedVersion, revision: 1)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ordered = try encoder.encode(before.value)
        var text = String(decoding: ordered, as: UTF8.self)
        XCTAssertTrue(text.contains(composedVersion))
        XCTAssertTrue(text.contains(#""revision":1"#))
        text = text.replacingOccurrences(of: composedVersion, with: #"release-\u00e9"#)
            .replacingOccurrences(of: #""revision":1"#, with: #""revision":1.0e0"#)
        let alternate = Data(("\n\t" + text + "\n").utf8)
        XCTAssertNotEqual(ordered, alternate)
        let after = try BuildTransfer.snapshot(fromDraftJSON: alternate)
        let result = try BuildComparison.compare(before, after)
        XCTAssertTrue(result.differences.isEmpty)
        XCTAssertEqual(before.value, after.value)
        XCTAssertEqual(result.before, result.after)
    }
}
