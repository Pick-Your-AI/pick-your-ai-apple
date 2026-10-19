import Foundation
import XCTest
@testable import PlannerTransfer

final class CatalogItemDetailsTests: XCTestCase {
    private func items() throws -> [CatalogItem] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "catalog", withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        let values = try XCTUnwrap(parser.parse().object?["items"]?.array)
        return try values.map { try CatalogItem.decode(JSONEncoder().encode($0)) }
    }

    private func item(_ kind: CatalogKind, changing update: (inout [String: JSONValue]) -> Void = { _ in }) throws -> CatalogItem {
        var value = try XCTUnwrap(items().first { $0.kind == kind }?.value.object)
        update(&value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try CatalogItem.decode(encoder.encode(JSONValue.object(value)))
    }

    private func field(_ name: String, in fields: [CatalogDetailField]) throws -> CatalogDetailField {
        try XCTUnwrap(fields.first { $0.name == name })
    }

    func testEveryCanonicalKindUsesItsExactSchemaFieldsAndPreservesItemIdentity() throws {
        let schema = try FrozenValidator(schemaNames: ["catalog-item", "common"])
        let definitions = try XCTUnwrap(schema.schemas["catalog-item.schema.json"]?.object?["$defs"]?.object)
        let source = try items()
        XCTAssertEqual(source.count, 29)
        var types = Set<String>()
        for item in source {
            let details = try CatalogItemDetails(item: item)
            XCTAssertEqual(details.item, item)
            let keys = try XCTUnwrap(definitions["spec_" + item.kind.rawValue]?.object?["properties"]?.object).keys.sorted()
            XCTAssertEqual(details.specifications.map(\.name), keys)
            XCTAssertEqual(details.license.map(\.name), ["commercial_use_allowed", "self_hosting_allowed", "spdx_id"])
            for field in details.specifications {
                XCTAssertEqual(field.value, item.spec[field.name])
                types.insert(field.type.rawValue)
            }
            XCTAssertFalse(details.specifications.contains { ["monthly_price", "price", "outcome", "compatibility"].contains($0.name) })
        }
        XCTAssertEqual(types, ["string", "number", "integer", "boolean", "array of strings"])
    }

    func testMissingFalseZeroAndEmptyTextRemainDifferent() throws {
        let model = try CatalogItemDetails(item: item(.model) { value in
            var spec = value["spec"]!.object!
            spec["supports_tool_calling"] = .bool(false)
            spec.removeValue(forKey: "supports_fine_tuning")
            value["spec"] = .object(spec)
            value["license"] = .object(["commercial_use_allowed": .bool(false), "spdx_id": .string("")])
        })
        XCTAssertEqual(try field("supports_tool_calling", in: model.specifications).value, .bool(false))
        XCTAssertEqual(try field("supports_tool_calling", in: model.specifications).state, .supplied)
        XCTAssertEqual(try field("supports_fine_tuning", in: model.specifications).state, .missing)
        XCTAssertEqual(try field("commercial_use_allowed", in: model.license).state, .supplied)
        XCTAssertEqual(try field("self_hosting_allowed", in: model.license).state, .missing)
        XCTAssertEqual(try field("spdx_id", in: model.license).state, .emptyText)
        let workload = try CatalogItemDetails(item: item(.workload) { value in
            var spec = value["spec"]!.object!
            spec["avg_input_tokens"] = .number(0)
            value["spec"] = .object(spec)
        })
        XCTAssertEqual(try field("avg_input_tokens", in: workload.specifications).value, .number(0))
        XCTAssertEqual(try field("avg_input_tokens", in: workload.specifications).state, .supplied)
    }

    func testUnknownAndIncompleteCollectionsRetainTheirExactRecordedContents() throws {
        let provider = try CatalogItemDetails(item: item(.modelProvider) { value in
            var spec = value["spec"]!.object!
            spec["supported_regions"] = .array([.string("eu-test"), .string("unknown"), .string("")])
            value["spec"] = .object(spec)
        })
        let regions = try field("supported_regions", in: provider.specifications)
        XCTAssertEqual(regions.state, .containsUnknown)
        XCTAssertEqual(regions.value, .array([.string("eu-test"), .string("unknown"), .string("")]))
        let deployment = try CatalogItemDetails(item: item(.deploymentMode) { value in
            var spec = value["spec"]!.object!
            spec["allowed_regions"] = .array([])
            value["spec"] = .object(spec)
        })
        XCTAssertEqual(try field("allowed_regions", in: deployment.specifications).state, .emptyCollection)
        let accelerator = try CatalogItemDetails(item: item(.accelerator) { value in
            var spec = value["spec"]!.object!
            spec["vendor"] = .string("unknown")
            value["spec"] = .object(spec)
        })
        XCTAssertEqual(try field("vendor", in: accelerator.specifications).state, .explicitUnknown)
        XCTAssertEqual(try field("vendor", in: accelerator.specifications).value, .string("unknown"))
    }

    func testProvenanceRetainsContradictionsAndRawStatusWithoutCreatingAnEvidenceGrade() throws {
        let sources: JSONValue = .array([
            .object(["source_uri": .string("https://example.invalid/old"), "checked_at": .string("2020-01-01T00:00:00Z"),
                     "verification_status": .string("verified"), "notes": .string("Earlier declaration: available")]),
            .object(["source_uri": .string("javascript:alert(1)"), "checked_at": .string("2026-10-16T09:00:00Z"),
                     "verification_status": .string("unverified"), "notes": .string("Conflicting declaration: unavailable")]),
            .object(["checked_at": .string("2026-10-16T09:00:00Z"), "verification_status": .string("estimated")])
        ])
        let details = try CatalogItemDetails(item: item(.model) { value in
            value["provenance"] = sources
            value["updated_at"] = .string("2020-01-01T00:00:00Z")
        })
        XCTAssertEqual(details.item.value.object?["provenance"], sources)
        XCTAssertEqual(details.provenance.count, 3)
        XCTAssertEqual(details.provenance.map(\.originalVerificationStatus), ["verified", "unverified", "estimated"])
        XCTAssertEqual(details.provenance[0].checkedAt, "2020-01-01T00:00:00Z")
        XCTAssertEqual(details.provenance[1].sourceURI, "javascript:alert(1)")
        XCTAssertEqual(details.provenance[1].notes, "Conflicting declaration: unavailable")
        XCTAssertNil(details.provenance[2].sourceURI)
        XCTAssertNil(details.provenance[2].notes)
        XCTAssertEqual(details.updatedAt, "2020-01-01T00:00:00Z")
        XCTAssertEqual(String(describing: details), "CatalogItemDetails")
        XCTAssertEqual(String(describing: details.provenance[1]), "CatalogDetailProvenance")
    }

    func testAbsentOptionalDeclarationsDoNotAcquireDefaultsOrAuthority() throws {
        let details = try CatalogItemDetails(item: item(.costPolicy) { value in
            value.removeValue(forKey: "license")
            value.removeValue(forKey: "description")
            value["provenance"] = .array([.object(["checked_at": .string("2026-10-16T09:00:00Z"),
                                                    "verification_status": .string("unverified")])])
            value["billing_class"] = .string("free")
        })
        XCTAssertTrue(details.license.allSatisfy { $0.state == .missing && $0.value == nil })
        XCTAssertEqual(details.provenance.count, 1)
        XCTAssertNil(details.provenance[0].sourceURI)
        XCTAssertNil(details.provenance[0].notes)
        XCTAssertEqual(details.updatedAt, "2026-10-16T09:00:00Z")
        XCTAssertNil(details.descriptionText)
        XCTAssertEqual(details.item.billingClass, "free")
        XCTAssertFalse(details.specifications.contains { $0.name.contains("price") })
    }

    func testDistinctVersionsAndExactDecimalValuesDoNotCollapseOrChangeDuringProjection() throws {
        let original = try item(.computeProfile) { value in
            value["version"] = .string("2026.10-demo-older")
            var spec = value["spec"]!.object!
            spec["ram_gb"] = .number(Decimal(string: "123456789.123456")!)
            value["spec"] = .object(spec)
            value["extensions"] = .object(["x_unassessed": .string("not a specification")])
        }
        let newer = try item(.computeProfile) { $0["version"] = .string("2026.10-demo-newer") }
        let details = try CatalogItemDetails(item: original)
        XCTAssertEqual(details.item.id, newer.id)
        XCTAssertNotEqual(details.item.version, newer.version)
        XCTAssertEqual(details.item, original)
        XCTAssertEqual(try field("ram_gb", in: details.specifications).value, .number(Decimal(string: "123456789.123456")!))
        XCTAssertFalse(details.specifications.contains { $0.name == "x_unassessed" })
        XCTAssertEqual(details.item.value.object?["extensions"], .object(["x_unassessed": .string("not a specification")]))
    }
}
