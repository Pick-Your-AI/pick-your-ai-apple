import Foundation
import SwiftUI
import XCTest
import PlannerCatalog
import PlannerTransfer
@testable import PlannerUI

@MainActor
final class ComponentComparisonModelTests: XCTestCase {
    private func row(_ model: ComponentComparisonModel, _ section: ComponentComparisonSection,
                     _ field: String) throws -> ComponentComparisonRow {
        try XCTUnwrap(model.rows.first { $0.section == section && $0.field == field })
    }

    func testExplicitSelectionKeepsTwoToFourInOrderAndLimitRecoveryDoesNotReplaceAnyRecord() throws {
        let model = ComponentComparisonModel()
        let candidates = try (1...5).map { try ComponentComparisonFixtures.candidate(id: "cat.compute.\($0)") }
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertFalse(model.isReady)
        XCTAssertTrue(model.add(candidates[0]))
        XCTAssertFalse(model.isReady)
        XCTAssertTrue(model.rows.isEmpty)
        for candidate in candidates[1...3] { XCTAssertTrue(model.add(candidate)); XCTAssertTrue(model.isReady) }
        XCTAssertEqual(model.selections, Array(candidates.prefix(4)))
        XCTAssertFalse(model.add(candidates[4]))
        XCTAssertEqual(model.notice, .selectionLimit)
        XCTAssertEqual(model.selections, Array(candidates.prefix(4)))
        model.remove(candidates[1].id)
        XCTAssertTrue(model.add(candidates[4]))
        XCTAssertEqual(model.selections, [candidates[0], candidates[2], candidates[3], candidates[4]])
        XCTAssertNil(model.notice)
    }

    func testDuplicateSelectionIsIdempotentButChangedRecordCannotClaimTheHeldIdentity() throws {
        let original = try ComponentComparisonFixtures.candidate()
        let conflict = try ComponentComparisonFixtures.candidate(extra: ["description": .string("Changed source claim")])
        let model = ComponentComparisonModel()
        XCTAssertTrue(model.add(original))
        XCTAssertTrue(model.add(original))
        XCTAssertEqual(model.selections, [original])
        XCTAssertFalse(model.contains(conflict))
        XCTAssertFalse(model.add(conflict))
        XCTAssertEqual(model.notice, .conflictingRecord)
        XCTAssertEqual(model.selections, [original])
        XCTAssertEqual(model.selections[0].encodedItem, original.encodedItem)
    }

    func testCrossKindReuseOfOneItemVersionCannotBecomeASecondMemberOfTheSameCatalog() throws {
        let model = ComponentComparisonModel()
        let compute = try ComponentComparisonFixtures.candidate()
        let storage = try ComponentComparisonFixtures.candidate(kind: .storage)
        XCTAssertTrue(model.add(compute))
        XCTAssertFalse(model.add(storage))
        XCTAssertEqual(model.notice, .conflictingRecord)
        XCTAssertEqual(model.selections, [compute])
    }

    func testConflictingCatalogBytesOrCaptureCannotReplaceAnImmutableCatalogRevision() throws {
        let model = ComponentComparisonModel()
        let original = try ComponentComparisonFixtures.candidate()
        XCTAssertTrue(model.add(original))
        model.inspect(original.id)
        let inspection = model.inspection
        for pin in [ComponentComparisonFixtures.pin(hash: String(repeating: "b", count: 64)),
                    ComponentComparisonFixtures.pin(capturedAt: "2026-10-17T09:00:00Z")] {
            let conflict = try ComponentComparisonFixtures.candidate(id: "cat.different", pin: pin)
            XCTAssertFalse(model.add(conflict))
            XCTAssertEqual(model.notice, .conflictingCatalog)
            XCTAssertEqual(model.selections, [original])
            XCTAssertEqual(model.inspection, inspection)
        }
    }

    func testDifferentExactVersionsAndCatalogRevisionsRemainSeparateSelections() throws {
        let model = ComponentComparisonModel()
        let original = try ComponentComparisonFixtures.candidate(version: "1.0")
        let nextVersion = try ComponentComparisonFixtures.candidate(version: "2.0")
        let newCatalog = try ComponentComparisonFixtures.candidate(version: "1.0",
            pin: ComponentComparisonFixtures.pin(revision: 2, hash: String(repeating: "b", count: 64)))
        for candidate in [original, nextVersion, newCatalog] { XCTAssertTrue(model.add(candidate)) }
        XCTAssertEqual(Set(model.selections.map(\.id)).count, 3)
        XCTAssertEqual(model.selections.map(\.catalog), [original.catalog, nextVersion.catalog, newCatalog.catalog])
        XCTAssertEqual(try row(model, .identity, "version").cells.map(\.value), [.string("1.0"), .string("2.0"), .string("1.0")])
        XCTAssertTrue(try row(model, .identity, "version").differs)
    }

    func testUnicodeEquivalentVersionSpellingsStayByteDistinctWithoutLosingTheirDisplay() throws {
        let composed = try ComponentComparisonFixtures.candidate(version: "caf\u{e9}")
        let decomposed = try ComponentComparisonFixtures.candidate(version: "cafe\u{301}")
        let model = ComponentComparisonModel()
        XCTAssertTrue(model.add(composed)); XCTAssertTrue(model.add(decomposed))
        XCTAssertNotEqual(composed.id, decomposed.id)
        XCTAssertEqual(model.selections.count, 2)
        XCTAssertTrue(try row(model, .identity, "version").differs)
        XCTAssertEqual(Data(ComponentComparisonText.literal(composed.details.item.version).utf8), Data("\"caf\u{e9}\"".utf8))
        XCTAssertEqual(Data(ComponentComparisonText.literal(decomposed.details.item.version).utf8), Data("\"cafe\u{301}\"".utf8))
    }

    func testExactDecimalZeroAndFalseRemainRecordedInsteadOfMissingOrRounded() throws {
        let decimal = try XCTUnwrap(Decimal(string: "1234567.89012345", locale: Locale(identifier: "en_US_POSIX")))
        let a = try ComponentComparisonFixtures.candidate(spec: ["ram_gb": .number(decimal), "disk_gb": .number(0)],
            extra: ["license": .object(["commercial_use_allowed": .bool(false)])])
        let b = try ComponentComparisonFixtures.candidate(id: "cat.second", spec: ["ram_gb": .number(0)],
            extra: ["license": .object(["commercial_use_allowed": .bool(true)])])
        let model = ComponentComparisonModel(); model.add(a); model.add(b)
        let ram = try row(model, .specifications, "ram_gb")
        XCTAssertEqual(ram.cells.map(\.value), [.number(decimal), .number(0)])
        XCTAssertEqual(ram.cells.map(\.availability), [.recorded, .recorded])
        XCTAssertEqual(ComponentComparisonText.value(try XCTUnwrap(ram.cells[0].value)), "1234567.89012345")
        let disk = try row(model, .specifications, "disk_gb")
        XCTAssertEqual(disk.cells.map(\.availability), [.recorded, .missing])
        XCTAssertEqual(disk.cells.map(\.value), [.number(0), nil])
        let license = try row(model, .license, "commercial_use_allowed")
        XCTAssertEqual(license.cells.map(\.value), [.bool(false), .bool(true)])
        XCTAssertEqual(license.cells.map(\.availability), [.recorded, .recorded])
    }

    func testMissingExplicitUnknownEmptyAndSuppliedDeclarationsHaveDifferentStates() throws {
        let variants: [[String: JSONValue]] = [[:], ["region": .string("unknown")], ["region": .string("")], ["region": .string("fixture-west")]]
        let model = ComponentComparisonModel()
        for (index, spec) in variants.enumerated() {
            model.add(try ComponentComparisonFixtures.candidate(id: "cat.storage.\(index)", kind: .storage, spec: spec))
        }
        let region = try row(model, .specifications, "region")
        XCTAssertEqual(region.cells.map(\.availability), [.missing, .explicitUnknown, .emptyText, .recorded])
        XCTAssertEqual(region.cells.map(\.value), [nil, .string("unknown"), .string(""), .string("fixture-west")])
        XCTAssertTrue(region.hasUnknown); XCTAssertTrue(region.differs)
        XCTAssertEqual(try row(model, .license, "commercial_use_allowed").cells.map(\.availability), Array(repeating: .missing, count: 4))
    }

    func testNotApplicableRequiresAnAbsentKindDefinitionAndNeverAnAbsentOptionalValue() throws {
        let model = ComponentComparisonModel()
        model.add(try ComponentComparisonFixtures.candidate())
        model.add(try ComponentComparisonFixtures.candidate(id: "cat.storage", kind: .storage))
        let network = try row(model, .specifications, "network_gbps")
        XCTAssertEqual(network.cells.map(\.availability), [.missing, .notApplicable])
        XCTAssertEqual(network.cells.map(\.type), ["number", nil])
        let capacity = try row(model, .specifications, "max_capacity_gb")
        XCTAssertEqual(capacity.cells.map(\.availability), [.notApplicable, .missing])
        XCTAssertTrue(network.differs); XCTAssertTrue(network.hasUnknown)
    }

    func testFourUnitAndConditionTuplesAreRetainedWithoutConversionRankingOrTransfer() throws {
        let model = ComponentComparisonModel()
        let units = ["milliseconds/request", "seconds/request", "tokens/second", "requests/second"]
        let currencies = ["USD", "EUR", "unknown", "USD"]
        var declarations: [JSONValue] = []
        for index in 0..<4 {
            let declaration: JSONValue = .object(["x_fixture_measurement": .object([
                "amount": .number(index == 0 ? 1000 : 1), "unit": .string(units[index]),
                "currency": .string(currencies[index]), "region": .string("fixture-\(index)"),
                "offering": .string("unqualified-\(index)"), "effective_at": .string("2026-10-\(10 + index)T09:00:00Z")])])
            declarations.append(declaration)
            model.add(try ComponentComparisonFixtures.candidate(id: "cat.variant.\(index)", version: "v\(index)",
                extra: ["extensions": declaration]))
        }
        let conditions = try row(model, .evidence, "extensions")
        XCTAssertEqual(conditions.cells.map(\.value), declarations.map(Optional.some))
        XCTAssertTrue(conditions.differs)
        for index in 0..<4 {
            let literal = ComponentComparisonText.value(try XCTUnwrap(conditions.cells[index].value))
            XCTAssertTrue(literal.contains(units[index]))
            XCTAssertTrue(literal.contains("unqualified-\(index)"))
            XCTAssertEqual(model.selections[index].details.item.version, "v\(index)")
        }
        XCTAssertEqual(model.selections.count, 4)
    }

    func testWholeEvidenceLicenseAndTopLevelConditionsRemainInspectableWithoutAConfidenceUpgrade() throws {
        let sources: JSONValue = .array([
            .object(["checked_at": .string("2020-01-01T00:00:00Z"), "verification_status": .string("verified"),
                     "source_uri": .string("https://docs.example.com/contradiction"), "notes": .string("Conflicting, expired declaration")]),
            .object(["checked_at": .string("2026-10-16T09:00:00Z"), "verification_status": .string("unverified")])])
        let candidate = try ComponentComparisonFixtures.candidate(extra: [
            "description": .string("Serving context is unknown"), "tags": .array([.string("unknown"), .string("")]),
            "provenance": sources, "license": .object(["spdx_id": .string("TEST-ONLY"), "self_hosting_allowed": .bool(false)]),
            "extensions": .object(["x_conditions": .object(["unit": .string("GiB"), "unresolved": .null])])])
        let model = ComponentComparisonModel(); model.add(candidate)
        model.add(try ComponentComparisonFixtures.candidate(id: "cat.other"))
        XCTAssertEqual(try row(model, .evidence, "provenance").cells[0].value, sources)
        XCTAssertEqual(try row(model, .evidence, "tags").cells[0].availability, .containsUnknown)
        XCTAssertEqual(candidate.details.provenance.map(\.originalVerificationStatus), ["verified", "unverified"])
        model.inspect(candidate.id)
        XCTAssertEqual(model.inspection?.candidate.encodedItem, candidate.encodedItem)
        XCTAssertTrue(ComponentComparisonText.record(candidate).contains("Conflicting, expired declaration"))
        let represented = Set(model.rows.filter { $0.section == .identity || $0.section == .evidence }.map(\.field)).union(["spec", "license"])
        if case .object(let values) = candidate.details.item.value { XCTAssertEqual(Set(values.keys).subtracting(represented), []) }
        else { XCTFail("Fixture must be the validated object") }
    }

    func testValuesThatCannotBeEncodedForComparisonNeverCollapseIntoSame() throws {
        struct Unencodable: Error {}
        let value = JSONValue.string("recorded")
        let failing: (JSONValue) throws -> Data = { _ in throw Unencodable() }
        let broken = ComponentComparisonCell(type: "string", value: value, encode: failing)
        let otherBroken = ComponentComparisonCell(type: "string", value: .string("different"), encode: failing)
        let healthy = ComponentComparisonCell(type: "string", value: value)
        let absent = ComponentComparisonCell(type: "string", value: nil)
        XCTAssertFalse(broken.isComparable); XCTAssertTrue(healthy.isComparable); XCTAssertTrue(absent.isComparable)
        // Cell equality stays reflexive; the fail-closed rule is the row's `differs`.
        XCTAssertEqual(broken, broken)
        XCTAssertNotEqual(broken, healthy)
        XCTAssertNotEqual(broken, absent)
        func grid(_ cells: [ComponentComparisonCell]) -> ComponentComparisonRow {
            ComponentComparisonRow(section: .specifications, field: "field", cells: cells)
        }
        XCTAssertTrue(grid([broken, otherBroken]).differs)
        XCTAssertTrue(grid([broken, broken]).differs)
        XCTAssertTrue(grid([healthy, broken]).differs)
        XCTAssertTrue(grid([broken, healthy]).differs)
        XCTAssertTrue(grid([broken, otherBroken]).hasUnknown)
        // Identical supplied declarations that did encode remain the same.
        XCTAssertFalse(grid([healthy, ComponentComparisonCell(type: "string", value: value)]).differs)
    }

    func testEmptyAndUnknownCollectionsDoNotTurnIntoSupportOrNotApplicable() throws {
        let a = try ComponentComparisonFixtures.candidate(extra: ["tags": .array([])])
        let b = try ComponentComparisonFixtures.candidate(id: "cat.other", extra: ["tags": .array([.string("unknown")])])
        let model = ComponentComparisonModel(); model.add(a); model.add(b)
        let tags = try row(model, .evidence, "tags")
        XCTAssertEqual(tags.cells.map(\.availability), [.emptyCollection, .containsUnknown])
        XCTAssertEqual(tags.cells.map(\.value), [.array([]), .array([.string("unknown")])])
        XCTAssertTrue(tags.hasUnknown)
    }

    func testDifferenceFilteringNeverDropsHeldRecordsAndPreferencesSurviveAddFailureRemoveAndClear() throws {
        let a = try ComponentComparisonFixtures.candidate()
        let b = try ComponentComparisonFixtures.candidate(id: "cat.other")
        let model = ComponentComparisonModel(); model.add(a); model.add(b)
        model.section = .specifications; model.differencesOnly = true
        XCTAssertTrue(model.visibleRows.isEmpty)
        XCTAssertEqual(model.selections, [a, b])
        model.section = .identity
        XCTAssertTrue(model.visibleRows.contains { $0.field == "id" })
        XCTAssertFalse(model.visibleRows.contains { $0.field == "version" })
        model.reportUnavailable(); model.remove(b.id)
        XCTAssertTrue(model.differencesOnly); XCTAssertEqual(model.section, .identity)
        model.clear()
        XCTAssertTrue(model.differencesOnly); XCTAssertEqual(model.section, .identity)
        XCTAssertFalse(model.isReady); XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(model.add(a)); XCTAssertTrue(model.add(b))
        XCTAssertEqual(model.selections, [a, b]); XCTAssertTrue(model.differencesOnly)
    }

    func testSourceFailurePreservesExactSelectionAndInspectionUntilAnExplicitRecovery() throws {
        let candidate = try ComponentComparisonFixtures.candidate()
        let model = ComponentComparisonModel(); model.add(candidate); model.inspect(candidate.id)
        let before = model.inspection
        model.reportUnavailable()
        XCTAssertEqual(model.notice, .sourceUnavailable)
        XCTAssertEqual(model.selections, [candidate]); XCTAssertEqual(model.inspection, before)
        XCTAssertFalse(model.isReady)
        model.add(try ComponentComparisonFixtures.candidate(id: "cat.recovery"))
        XCTAssertNil(model.notice); XCTAssertTrue(model.isReady)
        XCTAssertEqual(model.inspection, before)
    }

    func testInspectionReplacementAndRemovalRetireOnlyTheirCapturedIdentity() throws {
        let a = try ComponentComparisonFixtures.candidate()
        let b = try ComponentComparisonFixtures.candidate(id: "cat.other")
        let model = ComponentComparisonModel(); model.add(a); model.add(b)
        model.inspect(a.id); let first = try XCTUnwrap(model.inspection)
        model.inspect(b.id); let second = try XCTUnwrap(model.inspection)
        model.closeInspection(first.id)
        XCTAssertEqual(model.inspection, second)
        model.remove(a.id); XCTAssertEqual(model.inspection, second)
        model.remove(b.id); XCTAssertNil(model.inspection)
        model.inspect(a.id); XCTAssertNil(model.inspection)
        model.add(a); model.inspect(a.id); model.clear()
        model.closeInspection(second.id); XCTAssertNil(model.inspection); XCTAssertTrue(model.selections.isEmpty)
    }

    func testCapturedInspectionBindingRejectsStaleDismissalAndReplacement() throws {
        let a = try ComponentComparisonFixtures.candidate()
        let b = try ComponentComparisonFixtures.candidate(id: "cat.other")
        let model = ComponentComparisonModel(); model.add(a); model.add(b)
        let view = ComponentComparisonView(model: model)
        let emptyBinding = view.inspectionBinding
        XCTAssertNil(emptyBinding.wrappedValue)

        model.inspect(a.id)
        let first = try XCTUnwrap(model.inspection)
        let firstBinding = view.inspectionBinding
        XCTAssertEqual(firstBinding.wrappedValue, first)
        model.inspect(b.id)
        let second = try XCTUnwrap(model.inspection)
        let secondBinding = view.inspectionBinding
        XCTAssertEqual(secondBinding.wrappedValue, second)
        XCTAssertNil(emptyBinding.wrappedValue); XCTAssertNil(firstBinding.wrappedValue)

        // Exercise the real sheet binding setter after its presentation retires.
        // Neither an earlier dismissal nor a non-nil write may change the new one.
        emptyBinding.wrappedValue = nil
        firstBinding.wrappedValue = nil
        secondBinding.wrappedValue = first
        XCTAssertEqual(model.inspection, second)
        XCTAssertEqual(model.selections, [a, b])

        secondBinding.wrappedValue = nil
        XCTAssertNil(model.inspection)
        model.inspect(b.id)
        let reopened = try XCTUnwrap(model.inspection)
        XCTAssertNotEqual(reopened.id, second.id)
        XCTAssertNil(secondBinding.wrappedValue)
        secondBinding.wrappedValue = nil
        XCTAssertEqual(model.inspection, reopened)
        let reopenedBinding = view.inspectionBinding
        XCTAssertEqual(reopenedBinding.wrappedValue, reopened)
        reopenedBinding.wrappedValue = nil
        XCTAssertNil(model.inspection)
        XCTAssertEqual(model.selections, [a, b])
    }

    func testInvalidCatalogPinsAndInvalidItemsCannotEnterOrReplaceTheComparison() throws {
        let original = try ComponentComparisonFixtures.candidate()
        let model = ComponentComparisonModel(); model.add(original)
        let valid = ComponentComparisonFixtures.pin()
        let pins = [
            ArtifactPin(kind: .pricebook, identity: valid.identity, sha256: valid.sha256),
            ComponentComparisonFixtures.pin(revision: 0),
            ComponentComparisonFixtures.pin(hash: String(repeating: "A", count: 64)),
            ComponentComparisonFixtures.pin(hash: "short"),
            ComponentComparisonFixtures.pin(capturedAt: ""),
            ComponentComparisonFixtures.pin(capturedAt: String(repeating: "x", count: 129)),
            ArtifactPin(kind: .catalog, identity: ArtifactIdentity(schemaVersion: "2.0.0", id: "catalog.fixture", revision: 1, capturedAt: "2026-10-16T09:00:00Z"), sha256: valid.sha256)
        ]
        for pin in pins {
            XCTAssertThrowsError(try ComponentComparisonCandidate(item: original.details.item, catalog: pin)) {
                XCTAssertEqual($0 as? ComponentComparisonError, .invalidCatalogPin)
            }
            XCTAssertEqual(model.selections, [original])
        }
        XCTAssertThrowsError(try ComponentComparisonFixtures.item(spec: ["ram_gb": .string("not a number")]))
        XCTAssertEqual(model.selections, [original])
    }

    func testCompleteLiteralDisplayKeepsTypesLongConditionsAndEscapesInvisibleFormatting() throws {
        let long = String(repeating: "recorded condition ", count: 200)
        let raw = long + "\u{202e}\n\\unknown"
        let literal = ComponentComparisonText.literal(raw)
        XCTAssertTrue(literal.hasPrefix("\"" + long))
        XCTAssertTrue(literal.hasSuffix("\\u{202e}\\n\\\\unknown\""))
        XCTAssertFalse(literal.unicodeScalars.contains { $0.value == 0x202e })
        XCTAssertNotEqual(ComponentComparisonText.value(.number(0)), ComponentComparisonText.value(.string("0")))
        XCTAssertNotEqual(ComponentComparisonText.value(.bool(false)), ComponentComparisonText.value(.string("false")))
        XCTAssertEqual(ComponentComparisonText.value(.null), "null")
        let candidate = try ComponentComparisonFixtures.candidate(extra: ["description": .string(raw)])
        XCTAssertEqual(candidate.description, "ComponentComparisonCandidate")
        XCTAssertTrue(ComponentComparisonText.record(candidate).contains(long))
    }

    func testIndependentSessionsDoNotRestoreAnUnqualifiedImplicitSelection() throws {
        let first = ComponentComparisonModel()
        first.add(try ComponentComparisonFixtures.candidate())
        first.differencesOnly = true
        let second = ComponentComparisonModel()
        XCTAssertTrue(second.selections.isEmpty); XCTAssertFalse(second.isReady)
        XCTAssertNil(second.inspection); XCTAssertNil(second.notice)
        XCTAssertFalse(second.differencesOnly)
        XCTAssertEqual(first.selections.count, 1)
    }
}

/// Synthetic unit-test inputs only. These arbitrary pins exercise identity rules;
/// catalog membership is separately established by the real receiving adapter.
enum ComponentComparisonFixtures {
    static func pin(revision: Int = 1, hash: String = String(repeating: "a", count: 64),
                    capturedAt: String = "2026-10-16T09:00:00Z") -> ArtifactPin {
        ArtifactPin(kind: .catalog,
                    identity: ArtifactIdentity(schemaVersion: "1.0.0", id: "catalog.comparison.fixture", revision: revision, capturedAt: capturedAt),
                    sha256: hash)
    }
    static func candidate(id: String = "cat.compute", version: String = "fixture-v1", kind: CatalogKind = .computeProfile,
                          spec: [String: JSONValue] = [:], extra: [String: JSONValue] = [:],
                          pin: ArtifactPin = ComponentComparisonFixtures.pin()) throws -> ComponentComparisonCandidate {
        try ComponentComparisonCandidate(item: item(id: id, version: version, kind: kind, spec: spec, extra: extra), catalog: pin)
    }
    static func item(id: String = "cat.compute", version: String = "fixture-v1", kind: CatalogKind = .computeProfile,
                     spec changes: [String: JSONValue] = [:], extra: [String: JSONValue] = [:]) throws -> CatalogItem {
        var spec: [String: JSONValue]
        switch kind {
        case .computeProfile:
            spec = ["hosting_ref": .string("cat.host.fixture"), "cpu_cores": .number(4),
                    "ram_gb": .number(8), "region": .string("fixture-east")]
        case .storage: spec = ["storage_type": .string("object")]
        default: throw TransferError.schemaViolation
        }
        spec.merge(changes) { _, value in value }
        var fields: [String: JSONValue] = [
            "schema_version": .string("1.0.0"), "id": .string(id), "kind": .string(kind.rawValue),
            "tier": .string("T2"), "name": .string("Fictional " + id), "version": .string(version),
            "status": .string("preview"), "billing_class": .string("unknown"), "spec": .object(spec),
            "updated_at": .string("2026-10-16T09:00:00Z"),
            "provenance": .array([.object(["checked_at": .string("2026-10-16T09:00:00Z"),
                                           "verification_status": .string("unverified"),
                                           "notes": .string("Fictional test input; no price, compatibility or source approval.")])])
        ]
        fields.merge(extra) { _, value in value }
        return try CatalogItem.decode(ComponentComparisonText.encoder().encode(JSONValue.object(fields)))
    }
}
