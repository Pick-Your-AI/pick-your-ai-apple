import Foundation
import XCTest
@testable import PlannerTransfer

final class BuildComparisonTests: XCTestCase {
    private func fixture() throws -> [String: JSONValue] {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "build", withExtension: "json")!)
        var parser = try JSONParser(data)
        return try XCTUnwrap(parser.parse().object)
    }
    private func snapshot(_ fields: [String: JSONValue]) throws -> BuildSnapshot {
        try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(fields)))
    }
    private func revised(_ fields: [String: JSONValue]) -> [String: JSONValue] {
        var copy = fields; copy["revision"] = .number(2); return copy
    }
    private func setting(_ fields: [String: JSONValue], id: String, key: String, value: JSONValue) -> [String: JSONValue] {
        var copy = fields
        copy["selections"] = .array(fields["selections"]!.array!.map { item in
            var object = item.object!
            if object["id"] == .string(id) {
                var settings = object["settings"]!.object!; settings[key] = value
                object["settings"] = .object(settings)
            }
            return .object(object)
        })
        return copy
    }
    private func renamingSelection(_ fields: [String: JSONValue], from oldID: String, to newID: String) -> [String: JSONValue] {
        var copy = fields
        copy["selections"] = .array(fields["selections"]!.array!.map { item in
            var object = item.object!
            if object["id"] == .string(oldID) { object["id"] = .string(newID) }
            return .object(object)
        })
        copy["links"] = .array(fields["links"]!.array!.map { item in
            var object = item.object!
            for key in ["from_selection_id", "to_selection_id"] where object[key] == .string(oldID) {
                object[key] = .string(newID)
            }
            return .object(object)
        })
        return copy
    }
    private let fieldLikeIDs = ["notes", "extensions", "owner_ref", "endpoint", "secret", "credentials", "api-key"]
    func testSameSnapshotHasNoConfigurationDifferences() throws {
        let value = try snapshot(fixture())
        let result = try BuildComparison.compare(value, value)
        XCTAssertEqual(result.before, result.after)
        XCTAssertTrue(result.differences.isEmpty)
        XCTAssertTrue(result.evidenceNotice.contains("Missing evidence is unknown"))
    }
    func testReorderedSelectionsAndLinksRemainEquivalentAtSameIdentity() throws {
        let source = try fixture()
        var reordered = source
        reordered["selections"] = .array(Array(source["selections"]!.array!.reversed()))
        reordered["links"] = .array(Array(source["links"]!.array!.reversed()))
        let result = try BuildComparison.compare(snapshot(source), snapshot(reordered))
        XCTAssertTrue(result.differences.isEmpty)
    }
    func testExactSettingAndLockChangesArePinnedToEachRevision() throws {
        let source = try fixture()
        var later = setting(revised(source), id: "sel_context_policy", key: "requested_context_tokens", value: .number(8192))
        var locks = later["locks"]!.object!; locks["ruleset_version"] = .string("1.0.1")
        later["locks"] = .object(locks)
        let before = try snapshot(source), after = try snapshot(later)
        let result = try BuildComparison.compare(before, after)
        XCTAssertEqual(result.before.revision, "1")
        XCTAssertEqual(result.after.revision, "2")
        XCTAssertEqual(result.differences.count, 2)
        let setting = try XCTUnwrap(result.differences.first { $0.path.last == "requested_context_tokens" })
        XCTAssertEqual(setting.selectionKind, "context_policy")
        XCTAssertEqual(setting.tier, "T1")
        XCTAssertEqual(setting.before, .value(.number(4096)))
        XCTAssertEqual(setting.after, .value(.number(8192)))
        XCTAssertEqual(before.value, .object(source))
        XCTAssertEqual(after.value, .object(later))
    }
    func testFieldLikeSelectionIDsKeepPublicSettingChanges() throws {
        for id in fieldLikeIDs {
            let source = renamingSelection(try fixture(), from: "sel_context_policy", to: id)
            let after = setting(revised(source), id: id, key: "requested_context_tokens", value: .number(8192))
            let result = try BuildComparison.compare(snapshot(source), snapshot(after))
            XCTAssertEqual(result.differences.count, 1, id)
            let change = try XCTUnwrap(result.differences.first)
            XCTAssertEqual(change.path, ["selections", id, "settings", "requested_context_tokens"], id)
            XCTAssertEqual(change.before, .value(.number(4096)), id)
            XCTAssertEqual(change.after, .value(.number(8192)), id)
            XCTAssertEqual(change.selectionKind, "context_policy", id)
            XCTAssertEqual(change.tier, "T1", id)
        }
    }
    func testAddedAndRemovedFieldLikeSelectionIDsRetainPublicFields() throws {
        let source = try fixture()
        for id in fieldLikeIDs {
            var after = revised(source), added = source["selections"]!.array!.last!.object!
            added["id"] = .string(id)
            added["enabled"] = .bool(false)
            added["notes"] = .string("PRIVATE-ADDED-NOTES")
            added["extensions"] = .object(["x_private": .string("PRIVATE-ADDED-EXTENSION")])
            after["selections"] = .array(source["selections"]!.array! + [.object(added)])
            let beforeSnapshot = try snapshot(source), afterSnapshot = try snapshot(after)
            for (result, isAddition) in [(try BuildComparison.compare(beforeSnapshot, afterSnapshot), true),
                                         (try BuildComparison.compare(afterSnapshot, beforeSnapshot), false)] {
                let changes = result.differences
                let enabled = try XCTUnwrap(changes.first { $0.path == ["selections", id, "enabled"] })
                XCTAssertEqual(enabled.before, isAddition ? .absent : .value(.bool(false)), id)
                XCTAssertEqual(enabled.after, isAddition ? .value(.bool(false)) : .absent, id)
                XCTAssertTrue(changes.contains { $0.path == ["selections", id, "catalog_item_version"] }, id)
                XCTAssertTrue(changes.contains { $0.path == ["selections", id, "role"] }, id)
                XCTAssertFalse(changes.contains { $0.path.last == "notes" || $0.path.last == "extensions" }, id)
                XCTAssertFalse(String(describing: result).contains("PRIVATE-ADDED"), id)
            }
        }
    }
    func testFieldLikeLinkIDsKeepChangesAdditionsAndRemovals() throws {
        for id in fieldLikeIDs {
            var source = try fixture(), links = source["links"]!.array!, link = links[0].object!
            link["id"] = .string(id)
            links[0] = .object(link); source["links"] = .array(links)
            var after = revised(source)
            link["required"] = .bool(false)
            links[0] = .object(link); after["links"] = .array(links)
            let result = try BuildComparison.compare(snapshot(source), snapshot(after))
            XCTAssertEqual(result.differences.count, 1, id)
            let change = try XCTUnwrap(result.differences.first)
            XCTAssertEqual(change.path, ["links", id, "required"], id)
            XCTAssertEqual(change.before, .absent, id)
            XCTAssertEqual(change.after, .value(.bool(false)), id)

            var removed = revised(source)
            removed["links"] = .array(Array(source["links"]!.array!.dropFirst()))
            let beforeSnapshot = try snapshot(source), removedSnapshot = try snapshot(removed)
            for (comparison, isRemoval) in [(try BuildComparison.compare(beforeSnapshot, removedSnapshot), true),
                                            (try BuildComparison.compare(removedSnapshot, beforeSnapshot), false)] {
                let relation = try XCTUnwrap(comparison.differences.first { $0.path == ["links", id, "relation"] })
                XCTAssertEqual(relation.before, isRemoval ? .value(.string("provided_by")) : .absent, id)
                XCTAssertEqual(relation.after, isRemoval ? .absent : .value(.string("provided_by")), id)
            }
        }
    }
    func testFieldLikeIDsDoNotDisableNestedPrivateFieldRedaction() throws {
        for id in fieldLikeIDs {
            let source = renamingSelection(try fixture(), from: "sel_vector_database", to: id)
            var after = setting(revised(source), id: id, key: "index_name", value: .string("PRIVATE-INDEX"))
            after["selections"] = .array(after["selections"]!.array!.map { item in
                var object = item.object!
                if object["id"] == .string(id) {
                    object["notes"] = .string("PRIVATE-NOTES")
                    object["extensions"] = .object(["x_private": .string("PRIVATE-EXTENSION")])
                }
                return .object(object)
            })
            let result = try BuildComparison.compare(snapshot(source), snapshot(after))
            XCTAssertEqual(result.differences.count, 1, id)
            let change = try XCTUnwrap(result.differences.first)
            XCTAssertEqual(change.path, ["selections", id, "settings", "index_name"], id)
            XCTAssertEqual(change.before, .hidden, id)
            XCTAssertEqual(change.after, .hidden, id)
            XCTAssertFalse(String(describing: result).contains("PRIVATE-"), id)
            XCTAssertFalse(String(describing: result).contains("fixture-collection"), id)
        }
    }
    func testAbsentWorkloadIsNeverRenderedAsZero() throws {
        var source = try fixture()
        var objectives = source["objectives"]!.object!; objectives.removeValue(forKey: "requests_per_day")
        source["objectives"] = .object(objectives)
        var after = revised(source); objectives["requests_per_day"] = .number(0)
        after["objectives"] = .object(objectives)
        let result = try BuildComparison.compare(snapshot(source), snapshot(after))
        XCTAssertEqual(result.differences.count, 1)
        XCTAssertEqual(result.differences[0].before, .absent)
        XCTAssertEqual(result.differences[0].after, .value(.number(0)))
    }
    func testAddedAndRemovedSelectionsKeepRolesVersionsAndDisabledState() throws {
        let source = try fixture()
        var after = revised(source)
        var items = source["selections"]!.array!
        var removed = items.removeLast().object!
        XCTAssertEqual(removed["id"], .string("sel_cost_policy"))
        removed["id"] = .string("sel_new_cost_policy"); removed["enabled"] = .bool(false)
        removed["catalog_item_version"] = .string("2026.11-demo")
        items.append(.object(removed)); after["selections"] = .array(items)
        let result = try BuildComparison.compare(snapshot(source), snapshot(after))
        XCTAssertTrue(result.differences.contains { $0.path == ["selections", "sel_cost_policy", "enabled"] && $0.after == .absent })
        XCTAssertTrue(result.differences.contains { $0.path == ["selections", "sel_new_cost_policy", "enabled"] && $0.before == .absent && $0.after == .value(.bool(false)) })
        XCTAssertTrue(result.differences.contains { $0.path == ["selections", "sel_new_cost_policy", "catalog_item_version"] && $0.after == .value(.string("2026.11-demo")) })
        XCTAssertTrue(result.differences.contains { $0.path == ["selections", "sel_new_cost_policy", "role"] })
    }
    func testDecimalStringsAndRelationshipChangesStayExact() throws {
        let source = try fixture()
        var after = revised(source)
        var objectives = source["objectives"]!.object!; objectives["monthly_budget_amount"] = .string("0.000001")
        after["objectives"] = .object(objectives)
        var links = source["links"]!.array!, link = links[0].object!
        link["required"] = .bool(false); links[0] = .object(link); after["links"] = .array(links)
        let result = try BuildComparison.compare(snapshot(source), snapshot(after))
        XCTAssertTrue(result.differences.contains { $0.path.last == "monthly_budget_amount" && $0.after == .value(.string("0.000001")) })
        XCTAssertTrue(result.differences.contains { $0.path.first == "links" && $0.path.last == "required" && $0.before == .absent && $0.after == .value(.bool(false)) })
    }
    func testAmbiguousSelectionAndLinkIDsRejectWithoutPayloadDiagnostic() throws {
        let source = try fixture()
        for (key, expected) in [("selections", BuildComparisonError.ambiguousSelectionIdentity), ("links", .ambiguousLinkIdentity)] {
            var duplicate = revised(source), items = source[key]!.array!
            items.append(items[0]); duplicate[key] = .array(items)
            // The frozen schema can admit repeated IDs; this operation cannot.
            let ambiguous = try snapshot(duplicate)
            XCTAssertThrowsError(try BuildComparison.compare(snapshot(source), ambiguous)) {
                XCTAssertEqual($0 as? BuildComparisonError, expected)
                XCTAssertFalse(String(describing: $0).contains("sel_"))
            }
        }
    }
    func testConflictingContentsAtOneRevisionAreNotAcceptedAsARevisionChange() throws {
        let source = try fixture()
        let changed = setting(source, id: "sel_context_policy", key: "requested_context_tokens", value: .number(8192))
        XCTAssertThrowsError(try BuildComparison.compare(snapshot(source), snapshot(changed))) {
            XCTAssertEqual($0 as? BuildComparisonError, .conflictingRevisionIdentity)
        }
    }
    func testPrivateInfrastructureValuesAreNotRetainedInResult() throws {
        let source = try fixture()
        let after = setting(revised(source), id: "sel_vector_database", key: "index_name", value: .string("PRIVATE-INDEX"))
        let result = try BuildComparison.compare(snapshot(source), snapshot(after))
        XCTAssertEqual(result.differences.count, 1)
        XCTAssertEqual(result.differences[0].before, .hidden)
        XCTAssertEqual(result.differences[0].after, .hidden)
        XCTAssertFalse(String(describing: result).contains("PRIVATE-INDEX"))
        XCTAssertFalse(String(describing: result).contains("fixture-collection"))
    }
    func testForeignMeasurementsInExtensionsAreNeverTransplantedOrRanked() throws {
        var source = try fixture()
        source["extensions"] = .object(["x_measurement": .object(["build_id": .string("build.foreign"), "score": .number(999)])])
        var after = setting(revised(source), id: "sel_model", key: "precision", value: .string("fp32"))
        after["extensions"] = .object(["x_measurement": .object(["build_id": .string("build.other"), "score": .number(1)])])
        let result = try BuildComparison.compare(snapshot(source), snapshot(after))
        XCTAssertEqual(result.differences.count, 1)
        XCTAssertEqual(result.differences[0].path, ["selections", "sel_model", "settings", "precision"])
        XCTAssertFalse(String(describing: result).contains("build.foreign"))
        XCTAssertFalse(String(describing: result).contains("x_measurement"))
        XCTAssertTrue(result.evidenceNotice.contains("not compared"))
    }
    func testForkMetadataNeverChangesConfigurationOrConfersReadiness() throws {
        let source = try fixture()
        var fork = source; fork["id"] = .string("build.local-fork"); fork["owner_ref"] = .string("PRIVATE-OWNER")
        fork["lifecycle"] = .string("ready"); fork["name"] = .string("Comparison copy")
        let result = try BuildComparison.compare(snapshot(source), snapshot(fork))
        XCTAssertNotEqual(result.before.id, result.after.id)
        XCTAssertTrue(result.differences.isEmpty)
        XCTAssertFalse(String(describing: result).contains("PRIVATE-OWNER"))
        XCTAssertTrue(result.evidenceNotice.contains("compatibility"))
    }
    func testLargeComparisonFailsExplicitlyInsteadOfTruncatingChanges() throws {
        let source = try fixture()
        var after = revised(source)
        let template = source["selections"]!.array!.first!.object!
        var added = source["selections"]!.array!
        for index in 0..<400 {
            var item = template; item["id"] = .string("sel_extra_\(index)")
            added.append(.object(item))
        }
        after["selections"] = .array(added)
        XCTAssertThrowsError(try BuildComparison.compare(snapshot(source), snapshot(after))) {
            XCTAssertEqual($0 as? BuildComparisonError, .tooManyDifferences)
        }
    }
}
