import Foundation
import XCTest
import PlannerCatalog
import PlannerCore
@testable import PlannerTransfer

// Complete, unchanged frozen-v1 examples. These test resources are never product
// defaults, live prices, source-use receipts or permission to activate real data.
private enum CanonicalFixture: String, CaseIterable {
    case build, catalog, pricebook

    var sha256: String {
        switch self {
        case .build: "26762208769a8cf1012b4f33b1c1608556d275187ce21117d0b9632cdf951864"
        case .catalog: "2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8"
        case .pricebook: "716a848822fc2b182d226c597f7e50f4b00a0fe01ba5c03879e858ca6f0c9b46"
        }
    }

    func data() throws -> Data {
        #if !canImport(CryptoKit)
        throw XCTSkip("Exact fixture hashes and cache admission require the Apple CryptoKit lane")
        #else
        let url = try XCTUnwrap(Bundle.module.url(forResource: rawValue, withExtension: "json"))
        let data = try Data(contentsOf: url)
        guard try CatalogCache.sha256(data) == sha256 else {
            throw FixtureAdmissionError.changedCanonicalFixture
        }
        return data
        #endif
    }
}

private enum FixtureAdmissionError: Error {
    case changedCanonicalFixture, unexpectedArtifact
}

private struct CanonicalPair: Sendable {
    let manifest: CacheManifest
    let artifacts: [CatalogArtifact: Data]

    init() throws {
        let catalog = try CanonicalFixture.catalog.data()
        let pricebook = try CanonicalFixture.pricebook.data()
        artifacts = [.catalog: catalog, .pricebook: pricebook]
        manifest = CacheManifest(pins: try CatalogArtifact.allCases.map { kind in
            let bytes = kind == .catalog ? catalog : pricebook
            return ArtifactPin(kind: kind, identity: try JSONDecoder().decode(ArtifactIdentity.self, from: bytes),
                               sha256: try CatalogCache.sha256(bytes))
        })
    }

    func bytes(_ kind: CatalogArtifact) throws -> Data {
        guard let data = artifacts[kind] else { throw FixtureAdmissionError.unexpectedArtifact }
        return data
    }

    // This callback deliberately accepts only the byte-pinned examples. Item and
    // pricebook validation uses the real existing boundaries. It is a fixture
    // oracle, not a new general catalog-snapshot or production-source adapter.
    static func validate(_ kind: CatalogArtifact, _ data: Data) throws {
        let fixture: CanonicalFixture = kind == .catalog ? .catalog : .pricebook
        guard try CatalogCache.sha256(data) == fixture.sha256 else {
            throw FixtureAdmissionError.changedCanonicalFixture
        }
        switch kind {
        case .catalog:
            _ = try catalogItems(data)
        case .pricebook:
            _ = try Pricebook.decode(data)
        }
    }

    static func catalogItems(_ data: Data) throws -> [CatalogItem] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try XCTUnwrap(root["items"] as? [[String: Any]])
        return try items.map { try CatalogItem.decode(JSONSerialization.data(withJSONObject: $0)) }
    }
}

private actor FixtureDownloadRecorder {
    private(set) var calls = 0
    let pair: CanonicalPair
    init(_ pair: CanonicalPair) { self.pair = pair }
    func read(_ kind: CatalogArtifact) throws -> Data {
        calls += 1
        return try pair.bytes(kind)
    }
}

final class SyntheticFixtureAdmissionTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func cache(_ directory: URL) throws -> CatalogCache {
        try CatalogCache(directory: directory) { kind, data in
            try CanonicalPair.validate(kind, data)
        }
    }

    private func assertPreview(_ cache: CatalogCache, equals pair: CanonicalPair) async throws {
        let result = try await cache.load(mode: .syntheticPreview)
        let snapshot = try XCTUnwrap(result)
        XCTAssertEqual(snapshot.manifest, pair.manifest)
        XCTAssertEqual(snapshot.artifacts, pair.artifacts)
        XCTAssertTrue(snapshot.isSynthetic)
        if case .unknown = snapshot.currentChecks {} else {
            XCTFail("Fixture activation cannot establish current compatibility or prices")
        }
    }

    func testCanonicalFixtureBytesMatchFrozenInventory() throws {
        for fixture in CanonicalFixture.allCases {
            // Let an unavailable-platform skip reach XCTest outside its assertion autoclosure.
            let bytes = try fixture.data()
            XCTAssertEqual(try CatalogCache.sha256(bytes), fixture.sha256)
        }
    }

    func testCanonicalArtifactsKeepShapePinsAndSyntheticLabels() throws {
        let build = try BuildTransfer.snapshot(fromDraftJSON: CanonicalFixture.build.data())
        let catalog = try CanonicalPair.catalogItems(CanonicalFixture.catalog.data())
        let pricebook = try Pricebook.decode(CanonicalFixture.pricebook.data())
        XCTAssertEqual(build.id, "build.fixture.1")
        XCTAssertEqual(build.name, "FICTIONAL Full-Stack AI Build")
        XCTAssertEqual(catalog.count, 29)
        XCTAssertEqual(Set(catalog.map(\.kind)), Set(CatalogKind.allCases))
        XCTAssertTrue(catalog.allSatisfy { $0.name.hasPrefix("FICTIONAL ") && $0.version == "2026.10-demo" })
        let catalogIDs = Set(catalog.map(\.id))
        XCTAssertEqual(catalogIDs.count, 29)
        let selections = try XCTUnwrap(build.value.object?["selections"]?.array)
        XCTAssertEqual(selections.count, 29)
        XCTAssertEqual(Set(selections.compactMap { $0.object?["catalog_item_id"]?.string }), catalogIDs)
        XCTAssertTrue(selections.allSatisfy { $0.object?["catalog_item_version"]?.string == "2026.10-demo" })
        let locks = try XCTUnwrap(build.locks.object)
        XCTAssertEqual(locks["catalog_snapshot_id"]?.string, "catalog.fixture.1")
        XCTAssertEqual(locks["pricebook_id"]?.string, pricebook.id)
        XCTAssertEqual(pricebook.id, "prices.fixture.1")
        XCTAssertEqual(Set(pricebook.rates.map(\.id)), Set(["rate.compute_profile.fixture", "rate.storage.fixture"]))
        for rate in pricebook.rates {
            XCTAssertTrue(catalogIDs.contains(rate.catalogItemID))
            XCTAssertEqual(rate.catalogItemVersion, "2026.10-demo")
            XCTAssertEqual(rate.priceType, .estimate)
            XCTAssertEqual(rate.provenance.verificationStatus, .estimated)
            XCTAssertEqual(rate.provenance.notes, "Illustrative price, NOT a live market quote.")
        }
    }

    func testMalformedFullFixturesFailTheirExistingBoundariesAndOriginalsRemainValid() throws {
        let originalBuild = try CanonicalFixture.build.data()
        var build = try XCTUnwrap(JSONSerialization.jsonObject(with: originalBuild) as? [String: Any])
        build["schema_version"] = "0.0.0"
        XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: JSONSerialization.data(withJSONObject: build)))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: CanonicalFixture.catalog.data()) as? [String: Any])
        var item = try XCTUnwrap((catalog["items"] as? [[String: Any]])?.first)
        item["kind"] = "unrecognized_fixture_kind"
        XCTAssertThrowsError(try CatalogItem.decode(JSONSerialization.data(withJSONObject: item)))
        var prices = try XCTUnwrap(JSONSerialization.jsonObject(with: CanonicalFixture.pricebook.data()) as? [String: Any])
        var rates = try XCTUnwrap(prices["rates"] as? [[String: Any]])
        rates[0]["unit_price"] = ["amount": 0.80, "currency": "USD"]
        prices["rates"] = rates
        XCTAssertThrowsError(try Pricebook.decode(JSONSerialization.data(withJSONObject: prices)))
        _ = try BuildTransfer.snapshot(fromDraftJSON: CanonicalFixture.build.data())
        XCTAssertEqual(try CanonicalPair.catalogItems(CanonicalFixture.catalog.data()).count, 29)
        XCTAssertEqual(try Pricebook.decode(CanonicalFixture.pricebook.data()).rates.count, 2)
    }

    func testProductionRejectsFullCanonicalPairBeforeAnyDownload() async throws {
        let pair = try CanonicalPair()
        let store = try cache(directory())
        let recorder = FixtureDownloadRecorder(pair)
        do {
            try await store.refresh(pair.manifest, mode: .production) { try await recorder.read($0) }
            XCTFail("Complete reserved fixtures entered production mode")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .productionReceiptUnavailable) }
        let calls = await recorder.calls
        XCTAssertEqual(calls, 0)
        let missing = try await store.load(mode: .syntheticPreview)
        XCTAssertNil(missing)
        try await store.refresh(pair.manifest, mode: .syntheticPreview) { try pair.bytes($0) }
        try await assertPreview(store, equals: pair)
    }

    func testProductionReadCannotPromotePersistedPreviewAndPreviewStillReopens() async throws {
        let pair = try CanonicalPair()
        let url = try directory()
        try await cache(url).refresh(pair.manifest, mode: .syntheticPreview) { try pair.bytes($0) }
        let stored = url.appendingPathComponent("active-preview-v1.json")
        let before = try Data(contentsOf: stored)
        do {
            _ = try await cache(url).load(mode: .production)
            XCTFail("Restart relabeled a persisted fixture as production")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .productionReceiptUnavailable) }
        XCTAssertEqual(try Data(contentsOf: stored), before)
        try await assertPreview(cache(url), equals: pair)
    }

    func testChangedPriceBytesDoNotReplacePreviewAndExactRetryRecovers() async throws {
        let pair = try CanonicalPair()
        let url = try directory()
        let store = try cache(url)
        try await store.refresh(pair.manifest, mode: .syntheticPreview) { try pair.bytes($0) }
        let original = try pair.bytes(.pricebook)
        let changed = Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "\"0.80\"", with: "\"0.81\"").utf8)
        XCTAssertNotEqual(changed, original)
        _ = try Pricebook.decode(changed) // Still schema-shaped; the immutable byte pin must reject it.
        let stored = url.appendingPathComponent("active-preview-v1.json")
        let before = try Data(contentsOf: stored)
        do {
            try await store.refresh(pair.manifest, mode: .syntheticPreview) { kind in
                if kind == .pricebook { return changed }
                return try pair.bytes(kind)
            }
            XCTFail("Changed price bytes activated under the original pin")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .digestMismatch) }
        XCTAssertEqual(try Data(contentsOf: stored), before)
        try await assertPreview(cache(url), equals: pair)
        try await store.refresh(pair.manifest, mode: .syntheticPreview) { try pair.bytes($0) }
        try await assertPreview(store, equals: pair)
    }

    func testCancellationDuringFullPairDownloadPreservesPreviewAndRetryRecovers() async throws {
        let pair = try CanonicalPair()
        let url = try directory()
        let store = try cache(url)
        try await store.refresh(pair.manifest, mode: .syntheticPreview) { try pair.bytes($0) }
        let stored = url.appendingPathComponent("active-preview-v1.json")
        let before = try Data(contentsOf: stored)
        do {
            try await store.refresh(pair.manifest, mode: .syntheticPreview) { kind in
                if kind == .pricebook { throw CancellationError() }
                return try pair.bytes(kind)
            }
            XCTFail("Cancelled full-pair download committed")
        } catch is CancellationError {} catch { throw error }
        XCTAssertEqual(try Data(contentsOf: stored), before)
        try await assertPreview(cache(url), equals: pair)
        try await store.refresh(pair.manifest, mode: .syntheticPreview) { try pair.bytes($0) }
        try await assertPreview(store, equals: pair)
    }

    func testSyntheticResponseCannotEnterLiveEnvironmentOrCreatePreviewEndpoint() throws {
        for environment in [ClientEnvironment.staging, .production] {
            let configuration = try RuntimeConfiguration(environment: environment, endpoint: "https://fixture.invalid",
                                                         buildIdentity: "synthetic-fixture-admission-test", contractVersion: "1.0.0")
            XCTAssertThrowsError(try configuration.requireMatchingResponse(.synthetic)) {
                XCTAssertEqual($0 as? RuntimeConfigurationError, .wrongResponseEnvironment)
            }
        }
        XCTAssertThrowsError(try RuntimeConfiguration(environment: .preview, endpoint: "https://fixture.invalid",
                                                     buildIdentity: "synthetic-fixture-admission-test", contractVersion: "1.0.0")) {
            XCTAssertEqual($0 as? RuntimeConfigurationError, .previewEndpointForbidden)
        }
        let preview = try RuntimeConfiguration(environment: .preview, endpoint: nil,
                                               buildIdentity: "synthetic-fixture-admission-test", contractVersion: "1.0.0")
        XCTAssertNoThrow(try preview.requireMatchingResponse(.synthetic))
        XCTAssertNil(preview.endpoint)
    }
}
