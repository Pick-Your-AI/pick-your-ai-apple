import Foundation
import XCTest
import PlannerCatalog
@testable import PlannerTransfer

private enum RulesetBridgeFixtureError: Error { case unexpectedCatalogBytes }

// Test-only representations for deliberate corruption of the existing envelope.
private struct BridgeStoredRuleset: Codable {
    var pin: RulesetPin
    var bytes: Data
    var cachedAt: Date
    var synthetic: Bool
}
private struct BridgeRulesEnvelope: Codable {
    var storageVersion: String
    var records: [BridgeStoredRuleset]
}
private struct BridgePairFixture: Sendable {
    let manifest: CacheManifest
    let bytes: [CatalogArtifact: Data]
}

final class RulesetCacheValidatorTests: XCTestCase, @unchecked Sendable {
    private let firstDate = Date(timeIntervalSince1970: 1_792_000_000)
    private let laterDate = Date(timeIntervalSince1970: 1_792_000_100)

    private func original() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ruleset", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func changed(_ data: Data, _ edit: (inout [String: JSONValue]) throws -> Void) throws -> Data {
        var parser = try JSONParser(data)
        var object = try XCTUnwrap(try parser.parse().object)
        try edit(&object)
        return try encoded(JSONValue.object(object))
    }

    private func source(version: String, publishedAt: String = "2026-10-16T09:00:00Z") throws -> Data {
        try changed(original()) {
            $0["version"] = .string(version)
            $0["published_at"] = .string(publishedAt)
        }
    }

    private func invalidBody(_ data: Data) throws -> Data {
        try changed(data) { object in
            var rules = try XCTUnwrap(object["rules"]?.array)
            var rule = try XCTUnwrap(rules.first?.object)
            rule["assert"] = .object(["op": .string("not")]) // missing required argument
            rules[0] = .object(rule)
            object["rules"] = .array(rules)
        }
    }

    private func requireNativeHashing() throws {
        #if !canImport(CryptoKit)
        throw XCTSkip("Original-byte retention/history/selection execution requires native CryptoKit")
        #endif
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruleset-bridge-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func cache(_ directory: URL) throws -> RulesetCache {
        try RulesetCache(directory: directory) { try FrozenRulesetCacheValidator.identity(for: $0) }
    }

    private func pin(_ data: Data) throws -> RulesetPin {
        RulesetPin(identity: try FrozenRulesetCacheValidator.identity(for: data),
                   sha256: try CatalogCache.sha256(data))
    }

    private func retained(_ cache: RulesetCache, _ pin: RulesetPin) async throws -> CachedRuleset {
        let value = try await cache.load(pin, mode: .syntheticPreview)
        return try XCTUnwrap(value)
    }

    private func pair(_ revision: Int) throws -> BridgePairFixture {
        var pins: [ArtifactPin] = [], bytes: [CatalogArtifact: Data] = [:]
        for kind in CatalogArtifact.allCases {
            let identity = ArtifactIdentity(schemaVersion: "1.0.0", id: "synthetic." + kind.rawValue,
                                            revision: revision, capturedAt: "2026-10-19T00:00:00Z")
            let data = try encoded(identity)
            bytes[kind] = data
            pins.append(ArtifactPin(kind: kind, identity: identity, sha256: try CatalogCache.sha256(data)))
        }
        return BridgePairFixture(manifest: CacheManifest(pins: pins), bytes: bytes)
    }

    private func pairCache(_ directory: URL, allowed: [CatalogArtifact: [Data]]) throws -> CatalogCache {
        // A closed test-only allowlist, not a replacement Catalog/Pricebook schema.
        try CatalogCache(directory: directory) { kind, bytes in
            guard allowed[kind]?.contains(bytes) == true else { throw RulesetBridgeFixtureError.unexpectedCatalogBytes }
        }
    }

    func testCompleteFrozenRulesetReturnsItsAdmittedCacheIdentity() throws {
        let bytes = try original()
        XCTAssertEqual(try Ruleset.decode(bytes).rules.count, 45)
        let identity = try FrozenRulesetCacheValidator.identity(for: bytes)
        XCTAssertEqual(identity, RulesetIdentity(schemaVersion: "1.0.0", id: "rules.fixture.1",
                                                version: "1.0.0", publishedAt: "2026-10-16T09:00:00Z"))
    }

    func testAdmittedVersionAndTimestampSpellingsAreNotNormalized() throws {
        let version = "01.02.003-preview.01", date = "2026-10-16T10:00:00.123+01:00"
        let identity = try FrozenRulesetCacheValidator.identity(for: source(version: version, publishedAt: date))
        XCTAssertEqual(Array(identity.version.utf8), Array(version.utf8))
        XCTAssertEqual(Array(identity.publishedAt.utf8), Array(date.utf8))
    }

    func testPlausibleHeadersAndMalformedNestedRulesDoNotProduceIdentity() throws {
        let header = Data(#"{"schema_version":"1.0.0","id":"rules.fixture.1","version":"1.0.0","published_at":"2026-10-16T09:00:00Z"}"#.utf8)
        for invalid in [header, try invalidBody(original())] {
            XCTAssertThrowsError(try FrozenRulesetCacheValidator.identity(for: invalid)) {
                XCTAssertEqual($0 as? TransferError, .schemaViolation)
            }
        }
    }

    func testWholeDecoderDuplicateKeyAndByteBoundErrorsRemainIntact() throws {
        let text = String(decoding: try source(version: "1.0.0"), as: UTF8.self)
        let duplicate = text.replacingOccurrences(of: #""published_at":"#,
            with: #""published_at":"2026-10-16T09:00:00Z","published_at":"#)
        XCTAssertNotEqual(duplicate, text)
        XCTAssertThrowsError(try FrozenRulesetCacheValidator.identity(for: Data(duplicate.utf8))) {
            XCTAssertEqual($0 as? TransferError, .duplicateKey)
        }
        let oversized = Data(repeating: 0x20, count: BuildTransfer.maximumBytes + 1)
        XCTAssertThrowsError(try FrozenRulesetCacheValidator.identity(for: oversized)) {
            XCTAssertEqual($0 as? TransferError, .oversized)
        }
    }

    func testOriginalBytesAndDistinctLiteralVersionsSurviveCacheRestart() async throws {
        try requireNativeHashing()
        let root = try directory(), store = try cache(root)
        let a = Data(" \n".utf8) + (try original()) + Data("\n ".utf8)
        let b = Data("\t".utf8) + (try source(version: "01.0.0")) + Data("\n".utf8)
        let pa = try pin(a), pb = try pin(b)
        XCTAssertNotEqual(pa.identity, pb.identity)
        try await store.retain(pa, mode: .syntheticPreview, now: firstDate) { a }
        try await store.retain(pb, mode: .syntheticPreview, now: laterDate) { b }
        let file = root.appendingPathComponent("rules-preview-v1.json"), before = try Data(contentsOf: file)
        let reopened = try cache(root)
        let old = try await retained(reopened, pa), newer = try await retained(reopened, pb)
        XCTAssertEqual(old.bytes, a); XCTAssertEqual(newer.bytes, b)
        XCTAssertEqual(old.pin, pa); XCTAssertEqual(newer.pin, pb)
        XCTAssertEqual(old.cachedAt, firstDate); XCTAssertEqual(newer.cachedAt, laterDate)
        XCTAssertTrue(old.isSynthetic)
        if case .unknown = old.currentChecks {} else { XCTFail("Retained rules claimed current checks") }
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testRejectedWholeBodyPreservesHistoryAndPermitsCorrectedRetention() async throws {
        try requireNativeHashing()
        let root = try directory(), store = try cache(root), a = try original(), b = try source(version: "2.0.0")
        let pa = try pin(a), pb = try pin(b), invalid = try invalidBody(b)
        let rejected = RulesetPin(identity: pb.identity, sha256: try CatalogCache.sha256(invalid))
        try await store.retain(pa, mode: .syntheticPreview, now: firstDate) { a }
        let file = root.appendingPathComponent("rules-preview-v1.json"), before = try Data(contentsOf: file)
        do {
            try await store.retain(rejected, mode: .syntheticPreview) { invalid }
            XCTFail("Malformed nested rules were retained from plausible metadata")
        } catch { XCTAssertEqual(error as? TransferError, .schemaViolation) }
        XCTAssertEqual(try Data(contentsOf: file), before)
        let reopened = try cache(root), old = try await retained(reopened, pa)
        XCTAssertEqual(old.bytes, a)
        let missing = try await reopened.load(pb, mode: .syntheticPreview)
        XCTAssertNil(missing)
        try await reopened.retain(pb, mode: .syntheticPreview, now: laterDate) { b }
        let corrected = try await retained(try cache(root), pb)
        XCTAssertEqual(corrected.bytes, b)
    }

    func testMismatchedPinsLeavePriorBytesUnchangedBeforeValidRecovery() async throws {
        try requireNativeHashing()
        let root = try directory(), store = try cache(root), a = try original(), b = try source(version: "2.0.0")
        let pa = try pin(a), pb = try pin(b), identity = pb.identity
        try await store.retain(pa, mode: .syntheticPreview, now: firstDate) { a }
        let file = root.appendingPathComponent("rules-preview-v1.json"), before = try Data(contentsOf: file)
        let wrong: [(RulesetPin, RulesetCacheError)] = [
            (RulesetPin(identity: identity, sha256: String(repeating: "0", count: 64)), .digestMismatch),
            (RulesetPin(identity: RulesetIdentity(schemaVersion: "1.0.0", id: "rules.other.1", version: identity.version,
                                                 publishedAt: identity.publishedAt), sha256: pb.sha256), .incompatibleIdentity),
            (RulesetPin(identity: RulesetIdentity(schemaVersion: "1.0.0", id: identity.id, version: "3.0.0",
                                                 publishedAt: identity.publishedAt), sha256: pb.sha256), .incompatibleIdentity),
            (RulesetPin(identity: RulesetIdentity(schemaVersion: "1.0.0", id: identity.id, version: identity.version,
                                                 publishedAt: "2026-10-16T10:00:00+01:00"), sha256: pb.sha256), .incompatibleIdentity)
        ]
        for (request, expected) in wrong {
            do {
                try await store.retain(request, mode: .syntheticPreview) { b }
                XCTFail("Different original digest or metadata was retained")
            } catch { XCTAssertEqual(error as? RulesetCacheError, expected) }
            XCTAssertEqual(try Data(contentsOf: file), before)
        }
        let old = try await retained(try cache(root), pa)
        XCTAssertEqual(old.bytes, a)
        try await store.retain(pb, mode: .syntheticPreview, now: laterDate) { b }
        let recovered = try await retained(try cache(root), pb)
        XCTAssertEqual(recovered.bytes, b)
    }

    func testEveryRetainedBodyIsValidatedBeforeOtherOrMissingPinReads() async throws {
        try requireNativeHashing()
        let root = try directory(), store = try cache(root), a = try original(), b = try source(version: "2.0.0")
        let pa = try pin(a), pb = try pin(b), missing = try pin(source(version: "3.0.0"))
        try await store.retain(pa, mode: .syntheticPreview) { a }
        try await store.retain(pb, mode: .syntheticPreview) { b }
        let file = root.appendingPathComponent("rules-preview-v1.json"), originalFile = try Data(contentsOf: file)
        var envelope = try JSONDecoder().decode(BridgeRulesEnvelope.self, from: originalFile)
        XCTAssertEqual(envelope.records.count, 2)
        XCTAssertEqual(envelope.records[0].pin, pa)
        let invalid = try invalidBody(a)
        envelope.records[0].bytes = invalid
        envelope.records[0].pin = RulesetPin(identity: pa.identity, sha256: try CatalogCache.sha256(invalid))
        let corrupt = try encoded(envelope)
        try corrupt.write(to: file)
        let reopened = try cache(root)
        for request in [pb, missing] {
            do {
                _ = try await reopened.load(request, mode: .syntheticPreview)
                XCTFail("An older invalid body was ignored when resolving another pin")
            } catch { XCTAssertEqual(error as? TransferError, .schemaViolation) }
            XCTAssertEqual(try Data(contentsOf: file), corrupt)
        }
        // Explicit test restoration; the cache itself neither repairs nor deletes.
        try originalFile.write(to: file)
        let restored = try await retained(try cache(root), pb)
        XCTAssertEqual(restored.bytes, b)
        XCTAssertEqual(try Data(contentsOf: file), originalFile)
    }

    func testFailedRulesPreparationPreservesSelectedReleaseUntilExplicitCorrection() async throws {
        try requireNativeHashing()
        let root = try directory(), a = try pair(1), b = try pair(2)
        var allowed: [CatalogArtifact: [Data]] = [:]
        for kind in CatalogArtifact.allCases {
            allowed[kind] = [try XCTUnwrap(a.bytes[kind]), try XCTUnwrap(b.bytes[kind])]
        }
        let pairsDirectory = root.appendingPathComponent("pairs"), rulesDirectory = root.appendingPathComponent("rules")
        let selectionDirectory = root.appendingPathComponent("selection")
        let pairs = try pairCache(pairsDirectory, allowed: allowed), rules = try cache(rulesDirectory)
        let selector = try OfflineReleaseStore(directory: selectionDirectory, catalogCache: pairs, rulesetCache: rules)
        let ra = try original(), rb = try source(version: "2.0.0"), pa = try pin(ra), pb = try pin(rb)
        let releaseA = OfflineReleaseSelection(catalog: a.manifest, ruleset: pa)
        let releaseB = OfflineReleaseSelection(catalog: b.manifest, ruleset: pb)
        try await pairs.refresh(a.manifest, mode: .syntheticPreview, now: firstDate) { try XCTUnwrap(a.bytes[$0]) }
        try await rules.retain(pa, mode: .syntheticPreview, now: firstDate) { ra }
        _ = try await selector.activate(releaseA, mode: .syntheticPreview, now: firstDate)
        let selectedFile = selectionDirectory.appendingPathComponent("offline-selection-preview-v1.json")
        let pairFile = pairsDirectory.appendingPathComponent("active-preview-v1.json")
        let rulesFile = rulesDirectory.appendingPathComponent("rules-preview-v1.json")
        let selectedABytes = try Data(contentsOf: selectedFile), priorRulesBytes = try Data(contentsOf: rulesFile)

        // Independent pair preparation may change the pair cache; it does not select B.
        try await pairs.refresh(b.manifest, mode: .syntheticPreview, now: laterDate) { try XCTUnwrap(b.bytes[$0]) }
        let preparedPairBytes = try Data(contentsOf: pairFile), invalid = try invalidBody(rb)
        let rejected = RulesetPin(identity: pb.identity, sha256: try CatalogCache.sha256(invalid))
        do {
            try await rules.retain(rejected, mode: .syntheticPreview) { invalid }
            XCTFail("Invalid complete rules were prepared")
        } catch { XCTAssertEqual(error as? TransferError, .schemaViolation) }
        do {
            _ = try await selector.activate(releaseB, mode: .syntheticPreview)
            XCTFail("A tuple without retained valid rules became active")
        } catch { XCTAssertEqual(error as? OfflineReleaseStoreError, .missingRuleset) }
        XCTAssertEqual(try Data(contentsOf: selectedFile), selectedABytes)
        XCTAssertEqual(try Data(contentsOf: pairFile), preparedPairBytes)
        XCTAssertEqual(try Data(contentsOf: rulesFile), priorRulesBytes)

        let reopenedPairs = try pairCache(pairsDirectory, allowed: allowed), reopenedRules = try cache(rulesDirectory)
        let reopened = try OfflineReleaseStore(directory: selectionDirectory, catalogCache: reopenedPairs, rulesetCache: reopenedRules)
        let loadedA = try await reopened.load(mode: .syntheticPreview)
        let retainedA = try XCTUnwrap(loadedA)
        XCTAssertEqual(retainedA.catalog.artifacts, a.bytes)
        XCTAssertEqual(retainedA.ruleset.bytes, ra)
        XCTAssertTrue(retainedA.isSynthetic)
        if case .unknown = retainedA.currentChecks {} else { XCTFail("Selection claimed current checks") }
        XCTAssertEqual(try Data(contentsOf: selectedFile), selectedABytes)

        try await reopenedRules.retain(pb, mode: .syntheticPreview, now: laterDate) { rb }
        _ = try await reopened.activate(releaseB, mode: .syntheticPreview, now: laterDate)
        let loadedB = try await reopened.load(mode: .syntheticPreview)
        let retainedB = try XCTUnwrap(loadedB)
        XCTAssertEqual(retainedB.catalog.artifacts, b.bytes)
        XCTAssertEqual(retainedB.ruleset.bytes, rb)
        XCTAssertEqual(try Data(contentsOf: pairFile), preparedPairBytes)
        XCTAssertNotEqual(try Data(contentsOf: selectedFile), selectedABytes)
    }
}
