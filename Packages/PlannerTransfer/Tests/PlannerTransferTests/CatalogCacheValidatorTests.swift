import Foundation
import XCTest
import PlannerCatalog
import PlannerCore
@testable import PlannerTransfer

private struct ValidatorCachePair: Sendable {
    let manifest: CacheManifest
    let artifacts: [CatalogArtifact: Data]

    init(catalog: Data, pricebook: Data) throws {
        artifacts = [.catalog: catalog, .pricebook: pricebook]
        manifest = CacheManifest(pins: try CatalogArtifact.allCases.map { kind in
            let data = kind == .catalog ? catalog : pricebook
            return ArtifactPin(kind: kind, identity: try JSONDecoder().decode(ArtifactIdentity.self, from: data),
                               sha256: try CatalogCache.sha256(data))
        })
    }

    func bytes(_ kind: CatalogArtifact) throws -> Data {
        try XCTUnwrap(artifacts[kind])
    }
}

private actor ValidatorDownloadRecorder {
    private(set) var kinds: [CatalogArtifact] = []
    let pair: ValidatorCachePair
    init(_ pair: ValidatorCachePair) { self.pair = pair }
    func read(_ kind: CatalogArtifact) throws -> Data {
        kinds.append(kind)
        return try pair.bytes(kind)
    }
}

final class CatalogCacheValidatorTests: XCTestCase, @unchecked Sendable {
    // Pure decoder cases do not depend on CryptoKit or the byte-pinned fixture
    // admission helper. These remain whole documents, including malformed items.
    private func fixture(_ kind: CatalogArtifact) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: kind.rawValue, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encoded(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func modified(_ kind: CatalogArtifact, revision: Int = 1,
                          _ change: (inout [String: Any]) throws -> Void = { _ in }) throws -> Data {
        var value = try object(fixture(kind))
        value["revision"] = revision
        try change(&value)
        return try encoded(value)
    }

    private func requireHashing() throws {
        #if canImport(CryptoKit)
        _ = try CatalogCache.sha256(Data())
        #else
        throw XCTSkip("Cache persistence and exact byte pins require the Apple CryptoKit lane")
        #endif
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func cache(_ directory: URL) throws -> CatalogCache {
        try CatalogCache(directory: directory,
                         isReplaceableRetainedFailure: FrozenCatalogCacheValidator.isReplaceableRetainedFailure) { kind, data in
            try FrozenCatalogCacheValidator.validate(kind, data)
        }
    }

    private func pair(revision: Int, malformed: CatalogArtifact? = nil,
                      catalogFault: ((inout [String: Any]) throws -> Void)? = nil) throws -> ValidatorCachePair {
        let catalog = try modified(.catalog, revision: revision) { value in
            if malformed == .catalog, let catalogFault {
                try catalogFault(&value)
            } else if malformed == .catalog {
                var items = try XCTUnwrap(value["items"] as? [[String: Any]])
                items[items.count - 1]["kind"] = "unknown_cache_test_kind"
                value["items"] = items
            }
        }
        let pricebook = try modified(.pricebook, revision: revision) { value in
            if malformed == .pricebook {
                var rates = try XCTUnwrap(value["rates"] as? [[String: Any]])
                rates[rates.count - 1].removeValue(forKey: "provenance")
                value["rates"] = rates
            }
        }
        return try ValidatorCachePair(catalog: catalog, pricebook: pricebook)
    }

    private func assertSnapshot(_ snapshot: CachedCatalog?, equals pair: ValidatorCachePair, at date: Date,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let value = try XCTUnwrap(snapshot, file: file, line: line)
        XCTAssertEqual(value.manifest, pair.manifest, file: file, line: line)
        XCTAssertEqual(value.artifacts, pair.artifacts, file: file, line: line)
        XCTAssertEqual(value.cachedAt, date, file: file, line: line)
        XCTAssertTrue(value.isSynthetic, file: file, line: line)
        if case .unknown = value.currentChecks {} else {
            XCTFail("Structural validation cannot establish current checks", file: file, line: line)
        }
    }

    func testCompleteWholeArtifactsRetainOriginalWhitespaceAndEncoding() throws {
        for kind in CatalogArtifact.allCases {
            let raw = try fixture(kind)
            let framed = Data(" \n\t".utf8) + raw + Data("\r\n".utf8)
            let before = framed
            XCTAssertNoThrow(try FrozenCatalogCacheValidator.validate(kind, framed))
            XCTAssertEqual(framed, before)
        }
        // Keep Pricebook's existing Foundation UTF-16 input support; the bridge
        // must not substitute the catalog's UTF-8 parser for its own boundary.
        let text = try XCTUnwrap(String(data: fixture(.pricebook), encoding: .utf8))
        let utf16 = Data([0xff, 0xfe]) + (try XCTUnwrap(text.data(using: .utf16LittleEndian)))
        XCTAssertNoThrow(try FrozenCatalogCacheValidator.validate(.pricebook, utf16))
    }

    func testArtifactKindsAndHeaderOnlyDocumentsCannotReplaceWholeValidation() throws {
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, fixture(.pricebook)))
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.pricebook, fixture(.catalog)))
        for kind in CatalogArtifact.allCases {
            let headerOnly = try modified(kind) { value in
                value.removeValue(forKey: kind == .catalog ? "items" : "rates")
            }
            // The cache identity header alone is valid; the full artifact is not.
            XCTAssertNoThrow(try JSONDecoder().decode(ArtifactIdentity.self, from: headerOnly))
            XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(kind, headerOnly))
        }
    }

    func testMalformedNestedKindsUnitsAndRequiredPriceProvenanceAreRejected() throws {
        let wrongKind = try modified(.catalog) { value in
            var items = try XCTUnwrap(value["items"] as? [[String: Any]])
            items[items.count - 1]["kind"] = "unknown_cache_test_kind"
            value["items"] = items
        }
        let wrongUnits = try modified(.catalog) { value in
            var items = try XCTUnwrap(value["items"] as? [[String: Any]])
            let index = try XCTUnwrap(items.firstIndex { $0["kind"] as? String == "accelerator" })
            var spec = try XCTUnwrap(items[index]["spec"] as? [String: Any])
            spec["vram_gb"] = "24 GiB"
            items[index]["spec"] = spec
            value["items"] = items
        }
        for data in [wrongKind, wrongUnits] {
            XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, data)) {
                XCTAssertEqual($0 as? TransferError, .schemaViolation)
            }
        }
        for field in ["provenance", "checked_at", "verification_status"] {
            let data = try modified(.pricebook) { value in
                var rates = try XCTUnwrap(value["rates"] as? [[String: Any]])
                if field == "provenance" { rates[0].removeValue(forKey: field) }
                else {
                    var provenance = try XCTUnwrap(rates[0]["provenance"] as? [String: Any])
                    provenance.removeValue(forKey: field)
                    rates[0]["provenance"] = provenance
                }
                value["rates"] = rates
            }
            XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.pricebook, data)) {
                XCTAssertTrue($0 is DecodingError)
            }
        }
    }

    func testRawDuplicateKeysIncludingEscapedSpellingsReachBothDecoders() throws {
        for kind in CatalogArtifact.allCases {
            let source = try XCTUnwrap(String(data: modified(kind), encoding: .utf8))
            for key in ["captured_at", #"captured_\u0061t"#] {
                let duplicate = source.replacingOccurrences(of: "\"captured_at\":", with:
                    "\"\(key)\":\"2026-10-16T09:00:00Z\",\"captured_at\":")
                XCTAssertNotEqual(duplicate, source)
                XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(kind, Data(duplicate.utf8))) {
                    if kind == .catalog { XCTAssertEqual($0 as? TransferError, .duplicateKey) }
                    else { XCTAssertEqual($0 as? ContractJSONError, .duplicateKey) }
                }
            }
            let field = kind == .catalog ? "kind" : "verification_status"
            let escaped = kind == .catalog ? #"k\u0069nd"# : #"verification_\u0073tatus"#
            let nested = source.replacingOccurrences(of: "\"\(field)\":", with:
                "\"\(escaped)\":\"unverified\",\"\(field)\":")
            XCTAssertNotEqual(nested, source)
            XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(kind, Data(nested.utf8))) {
                if kind == .catalog { XCTAssertEqual($0 as? TransferError, .duplicateKey) }
                else { XCTAssertEqual($0 as? ContractJSONError, .duplicateKey) }
            }
        }
    }

    func testWholeDocumentByteDepthAndNodeBoundsRemainDistinct() throws {
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog,
            Data(repeating: 32, count: BuildTransfer.maximumBytes + 1))) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.pricebook,
            Data(repeating: 32, count: Pricebook.maximumPayloadBytes + 1))) {
            XCTAssertEqual($0 as? Pricebook.BoundaryError, .payloadTooLarge)
        }
        let nested = Data((String(repeating: "[", count: 50) + "0" + String(repeating: "]", count: 50)).utf8)
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, nested)) {
            XCTAssertEqual($0 as? TransferError, .tooDeep)
        }
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.pricebook, nested)) {
            XCTAssertEqual($0 as? ContractJSONError, .tooDeep)
        }
        let catalogNodes = Data(("[" + Array(repeating: "0", count: 16_384).joined(separator: ",") + "]").utf8)
        let priceNodes = Data(("[" + Array(repeating: "0", count: 131_072).joined(separator: ",") + "]").utf8)
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, catalogNodes)) {
            XCTAssertEqual($0 as? TransferError, .tooComplex)
        }
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.pricebook, priceNodes)) {
            XCTAssertEqual($0 as? ContractJSONError, .tooComplex)
        }
    }

    func testValidationPreservesDuplicateIdentitiesAndUnverifiedProvenance() throws {
        let catalog = try modified(.catalog) { value in
            var item = try XCTUnwrap((value["items"] as? [[String: Any]])?.first)
            var provenance = try XCTUnwrap((item["provenance"] as? [[String: Any]])?.first)
            provenance.removeValue(forKey: "source_uri")
            provenance["verification_status"] = "unverified"
            item["provenance"] = [provenance]
            value["items"] = [item, item]
        }
        XCTAssertNoThrow(try FrozenCatalogCacheValidator.validate(.catalog, catalog))
        let snapshot = try CatalogSnapshot.decode(catalog)
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0], snapshot.items[1])
        let provenance = try XCTUnwrap(snapshot.items[0].value.object?["provenance"]?.array)
        XCTAssertEqual(provenance.count, 1)
        let entry = try XCTUnwrap(provenance.first?.object)
        XCTAssertNil(entry["source_uri"])
        XCTAssertEqual(entry["verification_status"]?.string, "unverified")
        // The enclosing nonempty provenance array is required, even though a
        // source URI within a provenance record remains optional.
        for omitProvenance in [true, false] {
            var invalid = try object(catalog)
            var item = try XCTUnwrap((invalid["items"] as? [[String: Any]])?.first)
            if omitProvenance { item.removeValue(forKey: "provenance") }
            else { item["provenance"] = [] }
            invalid["items"] = [item, item]
            XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, encoded(invalid))) {
                XCTAssertEqual($0 as? TransferError, .schemaViolation)
            }
        }
        let prices = try modified(.pricebook) { value in
            var rates = try XCTUnwrap(value["rates"] as? [[String: Any]])
            var provenance = try XCTUnwrap(rates[0]["provenance"] as? [String: Any])
            provenance.removeValue(forKey: "source_uri")
            provenance["verification_status"] = "unverified"
            rates[0]["provenance"] = provenance
            rates[0]["unit_price"] = ["amount": "0.8000", "currency": "USD"]
            value["rates"] = rates
        }
        XCTAssertNoThrow(try FrozenCatalogCacheValidator.validate(.pricebook, prices))
        let rate = try XCTUnwrap(Pricebook.decode(prices).rates.first)
        XCTAssertNil(rate.provenance.sourceURI)
        XCTAssertEqual(rate.provenance.verificationStatus, .unverified)
        XCTAssertEqual(rate.unitPrice.amount.rawValue, "0.8000")
    }

    // Reference-policy fixtures. The unchanged catalog.json resolves every reference to
    // exactly one item of the documented kind, so each fault below is a single edit.
    private static func editItem(_ value: inout [String: Any], id: String,
                                 _ change: (inout [String: Any]) -> Void) throws {
        var items = try XCTUnwrap(value["items"] as? [[String: Any]])
        let index = try XCTUnwrap(items.firstIndex { $0["id"] as? String == id })
        change(&items[index])
        value["items"] = items
    }

    private static func setSpec(_ item: inout [String: Any], _ field: String, _ replacement: Any) {
        var spec = item["spec"] as? [String: Any] ?? [:]
        spec[field] = replacement
        item["spec"] = spec
    }

    private static func violation(
        _ source: String, _ sourceKind: CatalogKind, _ field: String, index: Int? = nil,
        target: String, expected: CatalogKind, _ reason: CatalogReferenceViolation.Reason
    ) -> CatalogReferenceViolation {
        CatalogReferenceViolation(sourceItemID: source, sourceKind: sourceKind, field: field,
                                  elementIndex: index, targetID: target, expectedKind: expected, reason: reason)
    }

    private static func rejection(_ violations: CatalogReferenceViolation...) -> CatalogReferenceRejection {
        CatalogReferenceRejection(violations: violations, omittedViolationCount: 0)
    }

    private static let wrongKindProvider = rejection(violation(
        "cat.model.fixture", .model, "provider_ref", target: "cat.tool.fixture",
        expected: .modelProvider, .wrongKind(actual: .tool)))

    private static func wrongKindProviderFault(_ value: inout [String: Any]) throws {
        try editItem(&value, id: "cat.model.fixture") { setSpec(&$0, "provider_ref", "cat.tool.fixture") }
    }

    // Duplicating the provider makes both of its referrers (document order) ambiguous.
    private static let ambiguousProvider = rejection(
        violation("cat.model.fixture", .model, "provider_ref", target: "cat.model_provider.fixture",
                  expected: .modelProvider, .ambiguous(candidateKinds: [.modelProvider, .modelProvider])),
        violation("cat.embedding_model.fixture", .embeddingModel, "provider_ref",
                  target: "cat.model_provider.fixture", expected: .modelProvider,
                  .ambiguous(candidateKinds: [.modelProvider, .modelProvider])))

    private static func ambiguousProviderFault(_ value: inout [String: Any]) throws {
        var items = try XCTUnwrap(value["items"] as? [[String: Any]])
        var other = try XCTUnwrap(items.first { $0["id"] as? String == "cat.model_provider.fixture" })
        other["version"] = "2026.11-demo"
        items.append(other)
        value["items"] = items
    }

    func testWrongKindReferencesRejectTheWholeCatalogWithSourceToFieldReport() throws {
        let scalar = try modified(.catalog, Self.wrongKindProviderFault)
        // Structural decoding alone still accepts it; the reference policy is the rejecting layer.
        XCTAssertNoThrow(try CatalogSnapshot.decode(scalar))
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, scalar)) {
            XCTAssertEqual($0 as? CatalogReferenceRejection, Self.wrongKindProvider)
        }
        // Each element of an array-valued reference is checked and located, so a valid
        // first element does not hide a later wrong-kind target.
        let array = try modified(.catalog) { value in
            try Self.editItem(&value, id: "cat.hosting_platform.fixture") {
                Self.setSpec(&$0, "accelerator_refs", ["cat.accelerator.fixture", "cat.storage.fixture"])
            }
        }
        XCTAssertNoThrow(try CatalogSnapshot.decode(array))
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, array)) {
            XCTAssertEqual($0 as? CatalogReferenceRejection, Self.rejection(Self.violation(
                "cat.hosting_platform.fixture", .hostingPlatform, "accelerator_refs", index: 1,
                target: "cat.storage.fixture", expected: .accelerator, .wrongKind(actual: .storage))))
        }
    }

    func testAmbiguousReferenceTargetsRejectEvenWhenTheVersionOrContentsAgree() throws {
        let differentVersion = try modified(.catalog, Self.ambiguousProviderFault)
        let sameVersion = try modified(.catalog) { value in
            var items = try XCTUnwrap(value["items"] as? [[String: Any]])
            items.append(try XCTUnwrap(items.first { $0["id"] as? String == "cat.model_provider.fixture" }))
            value["items"] = items
        }
        for data in [differentVersion, sameVersion] {
            XCTAssertNoThrow(try CatalogSnapshot.decode(data))
            XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, data)) {
                XCTAssertEqual($0 as? CatalogReferenceRejection, Self.ambiguousProvider)
            }
        }
    }

    func testAmbiguousTargetWhoseCandidatesAreAllWrongKindReportsTheirKinds() throws {
        let data = try modified(.catalog) { value in
            try Self.wrongKindProviderFault(&value)
            var items = try XCTUnwrap(value["items"] as? [[String: Any]])
            var other = try XCTUnwrap(items.first { $0["id"] as? String == "cat.tool.fixture" })
            other["version"] = "2026.11-demo"
            items.append(other)
            value["items"] = items
        }
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, data)) {
            // Not masked as a plain ambiguity: the report shows no candidate is a model_provider.
            // The duplicate tool also makes its two legitimate referrers ambiguous.
            XCTAssertEqual($0 as? CatalogReferenceRejection, Self.rejection(
                Self.violation("cat.model.fixture", .model, "provider_ref", target: "cat.tool.fixture",
                               expected: .modelProvider, .ambiguous(candidateKinds: [.tool, .tool])),
                Self.violation("cat.mcp_server.fixture", .mcpServer, "tool_refs", index: 0,
                               target: "cat.tool.fixture", expected: .tool, .ambiguous(candidateKinds: [.tool, .tool])),
                Self.violation("cat.integration.fixture", .integration, "associated_tool_refs", index: 0,
                               target: "cat.tool.fixture", expected: .tool, .ambiguous(candidateKinds: [.tool, .tool]))))
        }
    }

    func testUnresolvedReferencesAreAdmittedButListedByAnExplicitQuery() throws {
        // Open policy decision: the cache boundary does not reject a reference whose target is
        // absent from the snapshot (schema-valid maintenance-drill snapshots contain them). It
        // is surfaced by `unresolvedReferences(in:)` rather than hidden or called verified.
        let data = try modified(.catalog) { value in
            try Self.editItem(&value, id: "cat.model.fixture") { Self.setSpec(&$0, "provider_ref", "cat.absent.fixture") }
        }
        XCTAssertNoThrow(try FrozenCatalogCacheValidator.validate(.catalog, data))
        let snapshot = try CatalogSnapshot.decode(data)
        XCTAssertEqual(CatalogReferenceIntegrity.unresolvedReferences(in: snapshot), [Self.violation(
            "cat.model.fixture", .model, "provider_ref", target: "cat.absent.fixture",
            expected: .modelProvider, .unresolved)])
        let intact = try CatalogSnapshot.decode(fixture(.catalog))
        XCTAssertEqual(CatalogReferenceIntegrity.unresolvedReferences(in: intact), [])
        // A dangling reference elsewhere does not hide a wrong-kind violation, and is not in its report.
        let both = try modified(.catalog) { value in
            try Self.editItem(&value, id: "cat.model.fixture") { Self.setSpec(&$0, "provider_ref", "cat.absent.fixture") }
            try Self.editItem(&value, id: "cat.storage.fixture") { Self.setSpec(&$0, "hosting_ref", "cat.tool.fixture") }
        }
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, both)) {
            XCTAssertEqual($0 as? CatalogReferenceRejection, Self.rejection(Self.violation(
                "cat.storage.fixture", .storage, "hosting_ref", target: "cat.tool.fixture",
                expected: .hostingPlatform, .wrongKind(actual: .tool))))
        }
    }

    func testReportCollectsEveryViolationInItemFieldAndIndexOrderAndCapsTheList() throws {
        // Index 2 is an unresolved target: admitted by policy, so it is not in the report.
        let many = try modified(.catalog) { value in
            try Self.wrongKindProviderFault(&value)
            try Self.editItem(&value, id: "cat.hosting_platform.fixture") {
                Self.setSpec(&$0, "accelerator_refs",
                             ["cat.accelerator.fixture", "cat.storage.fixture", "cat.absent.fixture"])
            }
            try Self.editItem(&value, id: "cat.storage.fixture") { Self.setSpec(&$0, "hosting_ref", "cat.tool.fixture") }
        }
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, many)) {
            XCTAssertEqual($0 as? CatalogReferenceRejection, Self.rejection(
                Self.violation("cat.model.fixture", .model, "provider_ref", target: "cat.tool.fixture",
                               expected: .modelProvider, .wrongKind(actual: .tool)),
                Self.violation("cat.hosting_platform.fixture", .hostingPlatform, "accelerator_refs", index: 1,
                               target: "cat.storage.fixture", expected: .accelerator, .wrongKind(actual: .storage)),
                Self.violation("cat.storage.fixture", .storage, "hosting_ref", target: "cat.tool.fixture",
                               expected: .hostingPlatform, .wrongKind(actual: .tool))))
        }
        let limit = CatalogReferenceRejection.maximumReportedViolations
        let extra = (0..<(limit + 6)).map { "cat.storage.extra\($0)" }
        let overflow = try modified(.catalog) { value in
            var items = try XCTUnwrap(value["items"] as? [[String: Any]])
            let storage = try XCTUnwrap(items.first { $0["id"] as? String == "cat.storage.fixture" })
            for id in extra {
                var copy = storage
                copy["id"] = id
                items.append(copy)
            }
            value["items"] = items
            try Self.editItem(&value, id: "cat.hosting_platform.fixture") { Self.setSpec(&$0, "accelerator_refs", extra) }
        }
        XCTAssertThrowsError(try FrozenCatalogCacheValidator.validate(.catalog, overflow)) {
            let report = $0 as? CatalogReferenceRejection
            XCTAssertEqual(report?.violations.count, limit)
            XCTAssertEqual(report?.omittedViolationCount, 6)
            XCTAssertEqual(report?.violations.first?.elementIndex, 0)
            XCTAssertEqual(report?.violations.last?.elementIndex, limit - 1)
            XCTAssertEqual(report?.violations.last?.targetID, extra[limit - 1])
        }
    }

    func testUnreferencedDuplicateIdentitiesRemainAvailableToTheReceivingGraphPolicy() throws {
        let unreferenced = try modified(.catalog) { value in
            var items = try XCTUnwrap(value["items"] as? [[String: Any]])
            var other = try XCTUnwrap(items.first { $0["id"] as? String == "cat.workload.fixture" })
            other["version"] = "2026.11-demo"
            items.append(other)
            value["items"] = items
        }
        XCTAssertNoThrow(try FrozenCatalogCacheValidator.validate(.catalog, unreferenced))
    }

    func testWrongKindReferenceQuarantinesWholeCatalogAndRetainsLastValidCache() async throws {
        try requireHashing()
        try await assertRejectedPairPreservesHistoryAndRecovers(
            .catalog, catalogFault: Self.wrongKindProviderFault, expectedRejection: Self.wrongKindProvider)
    }

    func testAmbiguousReferenceQuarantinesWholeCatalogAndRetainsLastValidCache() async throws {
        try requireHashing()
        try await assertRejectedPairPreservesHistoryAndRecovers(
            .catalog, catalogFault: Self.ambiguousProviderFault, expectedRejection: Self.ambiguousProvider)
    }

    // Admits pairs with the earlier structural-only callback, as a cache written before the
    // reference policy existed could have. Later entries become the active pair.
    private func admitWithoutReferencePolicy(_ entries: [(ValidatorCachePair, Date)], into url: URL) async throws {
        let earlier = try CatalogCache(directory: url) { kind, data in
            switch kind {
            case .catalog: _ = try CatalogSnapshot.decode(data)
            case .pricebook: _ = try Pricebook.decode(data)
            }
        }
        for (pair, date) in entries {
            try await earlier.refresh(pair.manifest, mode: .syntheticPreview, now: date) { try pair.bytes($0) }
        }
    }

    private func assertNotServed(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(error as? CatalogReferenceRejection, Self.wrongKindProvider, file: file, line: line)
    }

    func testValidActivePairLoadsBesideAnOlderPolicyViolatingRecordAndRefreshPrunesIt() async throws {
        try requireHashing()
        let legacy = try pair(revision: 1, malformed: .catalog, catalogFault: Self.wrongKindProviderFault)
        let good = try pair(revision: 2)
        let recovery = try pair(revision: 3)
        let goodDate = Date(timeIntervalSince1970: 200)
        let recoveryDate = Date(timeIntervalSince1970: 300)
        let url = try directory()
        try await admitWithoutReferencePolicy([(legacy, Date(timeIntervalSince1970: 100)), (good, goodDate)], into: url)
        let stored = url.appendingPathComponent("active-preview-v1.json")
        let before = try Data(contentsOf: stored)

        let current = try cache(url)
        // An offline device keeps its valid active pair; the violating record is never served.
        try assertSnapshot(try await current.load(mode: .syntheticPreview), equals: good, at: goodDate)
        try assertSnapshot(try await current.load(good.manifest, mode: .syntheticPreview), equals: good, at: goodDate)
        do {
            _ = try await current.load(legacy.manifest, mode: .syntheticPreview)
            XCTFail("A policy-violating retained pair was served")
        } catch { assertNotServed(error) }
        XCTAssertEqual(try Data(contentsOf: stored), before, "Loads must not write")

        // A failed refresh changes nothing; a good one prunes the violating record atomically.
        struct Offline: Error {}
        do {
            try await current.refresh(recovery.manifest, mode: .syntheticPreview) { _ in throw Offline() }
            XCTFail("Unexpected offline success")
        } catch { XCTAssertTrue(error is Offline) }
        XCTAssertEqual(try Data(contentsOf: stored), before)
        try await current.refresh(recovery.manifest, mode: .syntheticPreview, now: recoveryDate) { try recovery.bytes($0) }
        try assertSnapshot(try await current.load(mode: .syntheticPreview), equals: recovery, at: recoveryDate)
        try assertSnapshot(try await current.load(good.manifest, mode: .syntheticPreview), equals: good, at: goodDate)
        let pruned = try await current.load(legacy.manifest, mode: .syntheticPreview)
        XCTAssertNil(pruned)
    }

    func testActivePairFailingTheReferencePolicyIsNeverServedButRefreshReplacesIt() async throws {
        try requireHashing()
        let good = try pair(revision: 1)
        let legacy = try pair(revision: 2, malformed: .catalog, catalogFault: Self.wrongKindProviderFault)
        let recovery = try pair(revision: 3)
        let goodDate = Date(timeIntervalSince1970: 100)
        let recoveryDate = Date(timeIntervalSince1970: 300)
        let url = try directory()
        try await admitWithoutReferencePolicy([(good, goodDate), (legacy, Date(timeIntervalSince1970: 200))], into: url)
        let stored = url.appendingPathComponent("active-preview-v1.json")
        let before = try Data(contentsOf: stored)

        let current = try cache(url)
        do {
            _ = try await current.load(mode: .syntheticPreview)
            XCTFail("An active pair failing the reference policy was served")
        } catch { assertNotServed(error) }
        do {
            _ = try await current.load(legacy.manifest, mode: .syntheticPreview)
            XCTFail("A policy-violating retained pair was served")
        } catch { assertNotServed(error) }
        // The older valid pair stays readable.
        try assertSnapshot(try await current.load(good.manifest, mode: .syntheticPreview), equals: good, at: goodDate)
        XCTAssertEqual(try Data(contentsOf: stored), before)

        try await current.refresh(recovery.manifest, mode: .syntheticPreview, now: recoveryDate) { try recovery.bytes($0) }
        try assertSnapshot(try await current.load(mode: .syntheticPreview), equals: recovery, at: recoveryDate)
        try assertSnapshot(try await current.load(good.manifest, mode: .syntheticPreview), equals: good, at: goodDate)
        let pruned = try await current.load(legacy.manifest, mode: .syntheticPreview)
        XCTAssertNil(pruned)
        // The pruned version stays immutable: different bytes for its pin are still refused.
        let conflicting = ArtifactPin(kind: .catalog, identity: legacy.manifest.pins[0].identity,
                                      sha256: String(repeating: "0", count: 64))
        let conflict = CacheManifest(pins: [conflicting] + legacy.manifest.pins.dropFirst())
        do {
            _ = try await current.load(conflict, mode: .syntheticPreview)
            XCTFail("A conflicting pin for a pruned version was treated as a clean miss")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .immutableVersionConflict) }
    }

    func testPruningDoesNotHideAnActiveManifestThatNamesNoStoredRecord() async throws {
        try requireHashing()
        let good = try pair(revision: 1)
        let legacy = try pair(revision: 2, malformed: .catalog, catalogFault: Self.wrongKindProviderFault)
        let unknown = try pair(revision: 5)
        let recovery = try pair(revision: 3)
        let url = try directory()
        try await admitWithoutReferencePolicy([(good, Date(timeIntervalSince1970: 100)),
                                               (legacy, Date(timeIntervalSince1970: 200))], into: url)
        let stored = url.appendingPathComponent("active-preview-v1.json")
        var envelope = try object(Data(contentsOf: stored))
        envelope["activeManifest"] = try object(JSONEncoder().encode(unknown.manifest))
        let corrupt = try encoded(envelope)
        try corrupt.write(to: stored, options: .atomic)

        // One record is prunable, but the corrupt active manifest must still be reported.
        let current = try cache(url)
        do {
            _ = try await current.load(mode: .syntheticPreview)
            XCTFail("A corrupt active manifest was served")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .corruptCache) }
        do {
            try await current.refresh(recovery.manifest, mode: .syntheticPreview) { try recovery.bytes($0) }
            XCTFail("Refresh proceeded over a corrupt envelope")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .corruptCache) }
        XCTAssertEqual(try Data(contentsOf: stored), corrupt)
    }

    func testValidatedPairPersistsOriginalBytesAndReopensWithoutPromotion() async throws {
        try requireHashing()
        let pair = try ValidatorCachePair(catalog: Data(" \n".utf8) + fixture(.catalog),
                                          pricebook: fixture(.pricebook) + Data("\t\n".utf8))
        let url = try directory()
        let store = try cache(url)
        let recorder = ValidatorDownloadRecorder(pair)
        do {
            try await store.refresh(pair.manifest, mode: .production) { try await recorder.read($0) }
            XCTFail("Schema validation granted production activation")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .productionReceiptUnavailable) }
        let deniedKinds = await recorder.kinds
        XCTAssertEqual(deniedKinds, [])
        let date = Date(timeIntervalSince1970: 1_234)
        try await store.refresh(pair.manifest, mode: .syntheticPreview, now: date) { try await recorder.read($0) }
        let downloaded = await recorder.kinds
        XCTAssertEqual(downloaded, CatalogArtifact.allCases)
        let stored = url.appendingPathComponent("active-preview-v1.json")
        let before = try Data(contentsOf: stored)
        let reopened = try cache(url)
        let active = try await reopened.load(mode: .syntheticPreview)
        try assertSnapshot(active, equals: pair, at: date)
        do {
            _ = try await reopened.load(mode: .production)
            XCTFail("Reopening a validated preview granted production authority")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .productionReceiptUnavailable) }
        XCTAssertEqual(try Data(contentsOf: stored), before)
    }

    func testValidHashMalformedCatalogPreservesHistoryAndRecovers() async throws {
        try requireHashing()
        try await assertRejectedPairPreservesHistoryAndRecovers(.catalog)
    }

    func testValidCatalogThenValidHashMalformedPricebookPreservesHistoryAndRecovers() async throws {
        try requireHashing()
        try await assertRejectedPairPreservesHistoryAndRecovers(.pricebook)
    }

    private func assertRejectedPairPreservesHistoryAndRecovers(
        _ kind: CatalogArtifact, catalogFault: ((inout [String: Any]) throws -> Void)? = nil,
        expectedRejection: CatalogReferenceRejection? = nil
    ) async throws {
        let first = try pair(revision: 1)
        let active = try pair(revision: 2)
        let malformed = try pair(revision: 3, malformed: kind, catalogFault: catalogFault)
        let recovery = try pair(revision: 4)
        let firstDate = Date(timeIntervalSince1970: 100)
        let activeDate = Date(timeIntervalSince1970: 200)
        let recoveryDate = Date(timeIntervalSince1970: 400)
        let url = try directory()
        let store = try cache(url)
        try await store.refresh(first.manifest, mode: .syntheticPreview, now: firstDate) { try first.bytes($0) }
        try await store.refresh(active.manifest, mode: .syntheticPreview, now: activeDate) { try active.bytes($0) }
        let stored = url.appendingPathComponent("active-preview-v1.json")
        let before = try Data(contentsOf: stored)
        for pin in malformed.manifest.pins {
            let bytes = try malformed.bytes(pin.kind)
            XCTAssertEqual(try CatalogCache.sha256(bytes), pin.sha256)
            XCTAssertEqual(try JSONDecoder().decode(ArtifactIdentity.self, from: bytes), pin.identity)
            XCTAssertEqual(pin.identity.revision, 3)
        }
        let recorder = ValidatorDownloadRecorder(malformed)
        do {
            try await store.refresh(malformed.manifest, mode: .syntheticPreview) { try await recorder.read($0) }
            XCTFail("Hash-valid malformed artifact replaced a retained pair")
        } catch {
            if let expectedRejection { XCTAssertEqual(error as? CatalogReferenceRejection, expectedRejection) }
            else if kind == .catalog { XCTAssertEqual(error as? TransferError, .schemaViolation) }
            else { XCTAssertTrue(error is DecodingError) }
        }
        let downloaded = await recorder.kinds
        XCTAssertEqual(downloaded, kind == .catalog ? [.catalog] : CatalogArtifact.allCases)
        XCTAssertEqual(try Data(contentsOf: stored), before)
        let reopened = try cache(url)
        let current = try await reopened.load(mode: .syntheticPreview)
        let historical = try await reopened.load(first.manifest, mode: .syntheticPreview)
        let rejected = try await reopened.load(malformed.manifest, mode: .syntheticPreview)
        try assertSnapshot(current, equals: active, at: activeDate)
        try assertSnapshot(historical, equals: first, at: firstDate)
        XCTAssertNil(rejected)
        XCTAssertEqual(try Data(contentsOf: stored), before)
        try await reopened.refresh(recovery.manifest, mode: .syntheticPreview, now: recoveryDate) { try recovery.bytes($0) }
        let recovered = try await reopened.load(mode: .syntheticPreview)
        let retained = try await reopened.load(active.manifest, mode: .syntheticPreview)
        try assertSnapshot(recovered, equals: recovery, at: recoveryDate)
        try assertSnapshot(retained, equals: active, at: activeDate)
    }

    func testContractInvalidRetainedHistoryBlocksReadsAndRefreshWithoutDeletingBytes() async throws {
        try requireHashing()
        let first = try pair(revision: 1)
        let active = try pair(revision: 2)
        let malformed = try pair(revision: 1, malformed: .catalog)
        let missing = try pair(revision: 3)
        let firstDate = Date(timeIntervalSince1970: 100)
        let activeDate = Date(timeIntervalSince1970: 200)
        let url = try directory()
        let store = try cache(url)
        try await store.refresh(first.manifest, mode: .syntheticPreview, now: firstDate) { try first.bytes($0) }
        try await store.refresh(active.manifest, mode: .syntheticPreview, now: activeDate) { try active.bytes($0) }
        let stored = url.appendingPathComponent("active-preview-v1.json")
        let before = try Data(contentsOf: stored)
        var envelope = try object(before)
        var records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 2)
        let activeRecord = try encoded(records[1])
        let activeManifest = try encoded(XCTUnwrap(envelope["activeManifest"]))
        records[0]["manifest"] = try object(JSONEncoder().encode(malformed.manifest))
        records[0]["artifacts"] = Dictionary(uniqueKeysWithValues:
            malformed.artifacts.map { ($0.key.rawValue, $0.value.base64EncodedString()) })
        var known = try XCTUnwrap(envelope["knownPins"] as? [[String: Any]])
        let oldPin = try XCTUnwrap(known.firstIndex {
            $0["kind"] as? String == "catalog" && ($0["identity"] as? [String: Any])?["revision"] as? Int == 1
        })
        let badPin = try XCTUnwrap(malformed.manifest.pins.first { $0.kind == .catalog })
        known[oldPin] = try object(JSONEncoder().encode(badPin))
        envelope["records"] = records
        envelope["knownPins"] = known
        XCTAssertEqual(try encoded(records[1]), activeRecord)
        XCTAssertEqual(try encoded(XCTUnwrap(envelope["activeManifest"])), activeManifest)
        XCTAssertEqual(try CatalogCache.sha256(malformed.bytes(.catalog)), badPin.sha256)
        XCTAssertEqual(try JSONDecoder().decode(ArtifactIdentity.self, from: malformed.bytes(.catalog)), badPin.identity)
        // This test alone edits the envelope. It keeps hashes, headers and known
        // pins self-consistent so only whole-contract validation can reject it.
        let corrupt = try encoded(envelope)
        try corrupt.write(to: stored, options: .atomic)
        let reopened = try cache(url)
        do {
            _ = try await reopened.load(mode: .syntheticPreview)
            XCTFail("Active read ignored contract-invalid retained history")
        } catch { XCTAssertEqual(error as? TransferError, .schemaViolation) }
        for requested in [first.manifest, active.manifest, missing.manifest] {
            do {
                _ = try await reopened.load(requested, mode: .syntheticPreview)
                XCTFail("Historical or missing lookup ignored invalid retained history")
            } catch { XCTAssertEqual(error as? TransferError, .schemaViolation) }
        }
        let recorder = ValidatorDownloadRecorder(missing)
        do {
            try await reopened.refresh(missing.manifest, mode: .syntheticPreview) { try await recorder.read($0) }
            XCTFail("Refresh discarded invalid retained history")
        } catch { XCTAssertEqual(error as? TransferError, .schemaViolation) }
        let downloaded = await recorder.kinds
        XCTAssertEqual(downloaded, [])
        XCTAssertEqual(try Data(contentsOf: stored), corrupt)
        // Explicit fixture restoration is not automatic cache repair. The cache
        // preserved the failing bytes and did not evict either retained release.
        try before.write(to: stored, options: .atomic)
        let restored = try cache(url)
        let current = try await restored.load(mode: .syntheticPreview)
        let historical = try await restored.load(first.manifest, mode: .syntheticPreview)
        try assertSnapshot(current, equals: active, at: activeDate)
        try assertSnapshot(historical, equals: first, at: firstDate)
        XCTAssertEqual(try Data(contentsOf: stored), before)
    }
}
