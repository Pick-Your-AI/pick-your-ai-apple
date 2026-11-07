import Foundation
import XCTest
@testable import PlannerCatalog

final class CatalogCacheHistoryTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // Header-only synthetic bytes isolate retention; the caller's frozen validator
    // remains mandatory. These fixtures do not claim canonical shape or source rights.
    private func fixture(_ revision: Int) throws -> (CacheManifest, [CatalogArtifact: Data]) {
        #if !canImport(CryptoKit)
        throw XCTSkip("CryptoKit hashing requires Apple SDK; retention behavior runs on macOS CI")
        #else
        var pins: [ArtifactPin] = []
        var artifacts: [CatalogArtifact: Data] = [:]
        for kind in CatalogArtifact.allCases {
            let identity = ArtifactIdentity(schemaVersion: "1.0.0", id: "synthetic-history-\(kind.rawValue)",
                                            revision: revision, capturedAt: "2026-10-18T00:00:00Z")
            let bytes = try JSONEncoder().encode(identity)
            pins.append(ArtifactPin(kind: kind, identity: identity, sha256: try CatalogCache.sha256(bytes)))
            artifacts[kind] = bytes
        }
        return (CacheManifest(pins: pins), artifacts)
        #endif
    }

    private func strings(in value: Any) -> Set<String> {
        if let text = value as? String { return [text] }
        if let array = value as? [Any] { return array.reduce(into: []) { $0.formUnion(strings(in: $1)) } }
        if let object = value as? [String: Any] {
            return object.values.reduce(into: []) { $0.formUnion(strings(in: $1)) }
        }
        return []
    }

    private func cache(_ url: URL, pairs: Int = 32, bytes: Int? = nil,
                       artifactBytes: Int = 8 * 1_024 * 1_024) throws -> CatalogCache {
        try CatalogCache(directory: url, maximumArtifactBytes: artifactBytes,
                         maximumCachedPairs: pairs, maximumCacheBytes: bytes,
                         validateContract: { _, _ in })
    }

    private func file(_ url: URL) -> URL { url.appendingPathComponent("active-preview-v1.json") }

    private func placeholder(_ revision: Int = 1) -> CacheManifest {
        CacheManifest(pins: CatalogArtifact.allCases.map {
            ArtifactPin(kind: $0, identity: ArtifactIdentity(schemaVersion: "1.0.0", id: "synthetic-history-\($0.rawValue)",
                        revision: revision, capturedAt: "2026-10-18T00:00:00Z"), sha256: String(repeating: "0", count: 64))
        })
    }

    private func legacy(_ active: CacheManifest, _ artifacts: [CatalogArtifact: Data],
                        known: [ArtifactPin], date: Date) throws -> Data {
        let value = LegacyCacheEnvelope(manifest: active,
            artifacts: Dictionary(uniqueKeysWithValues: artifacts.map { ($0.key.rawValue, $0.value) }),
            cachedAt: date, synthetic: true, knownPins: known)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func json(_ bytes: Data, changing edit: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        try edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: .withoutEscapingSlashes)
    }

    private func assertPair(_ actual: CachedCatalog?, _ manifest: CacheManifest,
                            _ artifacts: [CatalogArtifact: Data], date: Date? = nil,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try XCTUnwrap(actual, file: file, line: line)
        XCTAssertEqual(actual.manifest, manifest, file: file, line: line)
        XCTAssertEqual(actual.artifacts, artifacts, file: file, line: line)
        XCTAssertTrue(actual.isSynthetic, file: file, line: line)
        if let date { XCTAssertEqual(actual.cachedAt, date, file: file, line: line) }
        if case .unknown = actual.currentChecks {} else {
            XCTFail("Retained history must not imply current checks passed", file: file, line: line)
        }
    }

    // This regression uses only the pre-existing public API and is retained for a
    // baseline replay. A version ledger without original bytes cannot satisfy it.
    func testRefreshRetainsOriginalPairBytesAfterLaterActivation() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1)
        let (second, secondBytes) = try fixture(2)
        let store = try CatalogCache(directory: url, validateContract: { _, _ in })
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await store.refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let committed = try Data(contentsOf: url.appendingPathComponent("active-preview-v1.json"))
        let storedStrings = strings(in: try JSONSerialization.jsonObject(with: committed))
        for kind in CatalogArtifact.allCases {
            XCTAssertTrue(storedStrings.contains(firstBytes[kind]!.base64EncodedString()),
                          "Original \(kind.rawValue) bytes disappeared after the next activation")
        }
        let active = try await CatalogCache(directory: url, validateContract: { _, _ in }).load(mode: .syntheticPreview)
        XCTAssertEqual(active?.manifest, second)
        XCTAssertEqual(active?.artifacts, secondBytes)
    }

    func testExactHistoricalLookupAfterRestartDoesNotActivateOrRewrite() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1)
        let (second, secondBytes) = try fixture(2)
        let firstDate = Date(timeIntervalSince1970: 100), secondDate = Date(timeIntervalSince1970: 200)
        try await cache(url).refresh(first, mode: .syntheticPreview, now: firstDate) { firstBytes[$0]! }
        try await cache(url).refresh(second, mode: .syntheticPreview, now: secondDate) { secondBytes[$0]! }
        let before = try Data(contentsOf: file(url))
        let restarted = try cache(url)
        let old = try await restarted.load(first, mode: .syntheticPreview)
        try assertPair(old, first, firstBytes, date: firstDate)
        XCTAssertEqual(old?.age(at: Date(timeIntervalSince1970: 240)), 140)
        let active = try await restarted.load(mode: .syntheticPreview)
        try assertPair(active, second, secondBytes, date: secondDate)
        let currentByPin = try await restarted.load(second, mode: .syntheticPreview)
        try assertPair(currentByPin, second, secondBytes, date: secondDate)
        XCTAssertEqual(try Data(contentsOf: file(url)), before)
    }

    func testReorderedPinsAndReactivationReuseExistingCapacity() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let (third, _) = try fixture(3)
        let store = try cache(url, pairs: 2)
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await store.refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let reversed = CacheManifest(pins: Array(first.pins.reversed()))
        let original = try await store.load(reversed, mode: .syntheticPreview)
        try assertPair(original, first, firstBytes)
        let activeBefore = try await store.load(mode: .syntheticPreview)
        try assertPair(activeBefore, second, secondBytes)
        let date = Date(timeIntervalSince1970: 300)
        for _ in 0..<3 {
            try await store.refresh(reversed, mode: .syntheticPreview, now: date) { firstBytes[$0]! }
        }
        let before = try Data(contentsOf: file(url))
        do {
            try await store.refresh(third, mode: .syntheticPreview) { _ in
                XCTFail("Pair quota must reject before downloading")
                return Data()
            }
            XCTFail("A third distinct pair exceeded the configured capacity")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .historyLimitReached) }
        XCTAssertEqual(try Data(contentsOf: file(url)), before)
        let active = try await cache(url, pairs: 2).load(mode: .syntheticPreview)
        try assertPair(active, reversed, firstBytes, date: date)
        let retained = try await cache(url, pairs: 2).load(second, mode: .syntheticPreview)
        try assertPair(retained, second, secondBytes)
        do { _ = try await cache(url, pairs: 1).load(mode: .syntheticPreview); XCTFail("Lowered capacity discarded history") }
        catch { XCTAssertEqual(error as? CatalogCacheError, .historyLimitReached) }
        XCTAssertEqual(try Data(contentsOf: file(url)), before)
    }

    func testUnknownPairAndUncommittedCombinationAreCleanMisses() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let (unknown, _) = try fixture(3)
        let store = try cache(url)
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await store.refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let before = try Data(contentsOf: file(url))
        let mixed = CacheManifest(pins: [first.pins[0], second.pins[1]])
        for request in [unknown, mixed] {
            let missing = try await store.load(request, mode: .syntheticPreview)
            XCTAssertNil(missing)
        }
        XCTAssertEqual(try Data(contentsOf: file(url)), before)
        let active = try await store.load(mode: .syntheticPreview)
        try assertPair(active, second, secondBytes)
    }

    func testHistoricalIdentityConflictsAreErrorsForLookupAndRefresh() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let store = try cache(url)
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await store.refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let before = try Data(contentsOf: file(url))
        let old = first.pins[0]
        let changedDate = ArtifactIdentity(schemaVersion: old.identity.schemaVersion, id: old.identity.id,
                                          revision: old.identity.revision, capturedAt: "2026-10-19T00:00:00Z")
        let conflicts = [ArtifactPin(kind: old.kind, identity: old.identity, sha256: String(repeating: "0", count: 64)),
                         ArtifactPin(kind: old.kind, identity: changedDate, sha256: old.sha256)]
        for pin in conflicts {
            let request = CacheManifest(pins: [pin, first.pins[1]])
            do { _ = try await store.load(request, mode: .syntheticPreview); XCTFail("Conflict became a clean miss") }
            catch { XCTAssertEqual(error as? CatalogCacheError, .immutableVersionConflict) }
            do {
                try await store.refresh(request, mode: .syntheticPreview) { _ in
                    XCTFail("Conflicting historical identity reached download")
                    return Data()
                }
                XCTFail("Historical metadata changed")
            } catch { XCTAssertEqual(error as? CatalogCacheError, .immutableVersionConflict) }
        }
        XCTAssertEqual(try Data(contentsOf: file(url)), before)
        let retained = try await store.load(first, mode: .syntheticPreview)
        try assertPair(retained, first, firstBytes)
    }

    func testHistoricalMissingAndProductionGuardsDoNotCreateStorage() async throws {
        let root = try directory(), request = placeholder()
        let url = root.appendingPathComponent("missing")
        let store = try cache(url)
        let missing = try await store.load(request, mode: .syntheticPreview)
        XCTAssertNil(missing)
        for request in [request, CacheManifest(pins: [])] {
            do { _ = try await store.load(request, mode: .production); XCTFail("Production historical lookup admitted") }
            catch { XCTAssertEqual(error as? CatalogCacheError, .productionReceiptUnavailable) }
        }
        do {
            _ = try await store.load(CacheManifest(pins: [request.pins[0], request.pins[0]]), mode: .syntheticPreview)
            XCTFail("Duplicate lookup pins accepted")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .invalidManifest) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRetentionConfigurationRejectsInvalidBoundsWithoutStorage() throws {
        let root = try directory(), url = root.appendingPathComponent("missing")
        for pairs in [0, -1, 129] {
            XCTAssertThrowsError(try cache(url, pairs: pairs)) { XCTAssertEqual($0 as? CatalogCacheError, .invalidManifest) }
        }
        for bytes in [0, -1, 512 * 1_024 * 1_024 + 1] {
            XCTAssertThrowsError(try cache(url, bytes: bytes)) { XCTAssertEqual($0 as? CatalogCacheError, .invalidManifest) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLegacyReadIsUnchangedAndFirstSuccessfulRefreshRetainsOnlyAvailableBytes() async throws {
        let url = try directory()
        let (unavailable, _) = try fixture(1), (second, secondBytes) = try fixture(2)
        let (third, thirdBytes) = try fixture(3)
        let date = Date(timeIntervalSince1970: 200)
        let original = try legacy(second, secondBytes, known: unavailable.pins + second.pins, date: date)
        try original.write(to: file(url))
        let store = try cache(url)
        let current = try await store.load(mode: .syntheticPreview)
        try assertPair(current, second, secondBytes, date: date)
        let absent = try await store.load(unavailable, mode: .syntheticPreview)
        XCTAssertNil(absent)
        XCTAssertEqual(try Data(contentsOf: file(url)), original)
        try await store.refresh(third, mode: .syntheticPreview, now: Date(timeIntervalSince1970: 300)) { thirdBytes[$0]! }
        let promoted = try Data(contentsOf: file(url))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: promoted) as? [String: Any])
        XCTAssertEqual(object["storageVersion"] as? Int, 2)
        let restarted = try cache(url)
        let old = try await restarted.load(second, mode: .syntheticPreview)
        try assertPair(old, second, secondBytes, date: date)
        let stillAbsent = try await restarted.load(unavailable, mode: .syntheticPreview)
        XCTAssertNil(stillAbsent)
        let active = try await restarted.load(mode: .syntheticPreview)
        try assertPair(active, third, thirdBytes, date: Date(timeIntervalSince1970: 300))
        // Exact legacy decoder shape from main71db: older clients reject before any
        // refresh or hash validation, so they cannot overwrite away retained history.
        XCTAssertThrowsError(try JSONDecoder().decode(LegacyCacheEnvelope.self, from: promoted)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else { return XCTFail("Unexpected old-reader error: \(error)") }
            XCTAssertEqual(key.stringValue, "manifest")
        }
        XCTAssertEqual(try Data(contentsOf: file(url)), promoted)
    }

    func testFailedAndCanceledFirstMigrationPreserveLegacyBytesAndLedger() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let original = try legacy(first, firstBytes, known: first.pins, date: Date(timeIntervalSince1970: 100))
        try original.write(to: file(url))
        let store = try cache(url)
        for canceled in [false, true] {
            do {
                try await store.refresh(second, mode: .syntheticPreview) { kind in
                    if kind == .pricebook {
                        if canceled { throw CancellationError() }
                        return Data("bad download".utf8)
                    }
                    return secondBytes[kind]!
                }
                XCTFail("Failed legacy migration committed")
            } catch is CancellationError { XCTAssertTrue(canceled) }
            catch { XCTAssertEqual(error as? CatalogCacheError, .digestMismatch); XCTAssertFalse(canceled) }
            XCTAssertEqual(try Data(contentsOf: file(url)), original)
        }
        let retained = try await cache(url).load(first, mode: .syntheticPreview)
        try assertPair(retained, first, firstBytes)
        let absent = try await cache(url).load(second, mode: .syntheticPreview)
        XCTAssertNil(absent)
    }

    func testUnsupportedAndMalformedStorageVersionsArePreservedBeforeDownload() async throws {
        let url = try directory(), request = placeholder()
        let versionValues: [Any] = [3, NSNull(), "2", true]
        for version in versionValues {
            let bytes = try JSONSerialization.data(withJSONObject: ["storageVersion": version, "knownPins": []])
            try bytes.write(to: file(url))
            let store = try cache(url)
            do { _ = try await store.load(request, mode: .syntheticPreview); XCTFail("Unsupported storage admitted") }
            catch { XCTAssertEqual(error as? CatalogCacheError, .corruptCache) }
            do {
                try await store.refresh(request, mode: .syntheticPreview) { _ in
                    XCTFail("Unsupported storage was replaced")
                    return Data()
                }
                XCTFail("Unsupported storage migrated")
            } catch { XCTAssertEqual(error as? CatalogCacheError, .corruptCache) }
            XCTAssertEqual(try Data(contentsOf: file(url)), bytes)
        }

        // The partial envelopes above must remain portable controls. A complete
        // envelope additionally isolates version refusal: otherwise a missing
        // activeManifest/records field can hide an accidentally relaxed guard.
        let digests: [CatalogArtifact: String] = [
            .catalog: "3ed422368acd0a94bc067edb8d99b46f38460c9f677c8d8408b9a9004d70d859",
            .pricebook: "749135f7dc69e851ba4ddbec69f14011937f0af8e09b1fae4d4f254a90da7f53"
        ]
        var pins: [ArtifactPin] = []
        var artifacts: [CatalogArtifact: Data] = [:]
        for kind in CatalogArtifact.allCases {
            let identity = ArtifactIdentity(schemaVersion: "1.0.0", id: "synthetic-history-\(kind.rawValue)",
                                            revision: 1, capturedAt: "2026-10-18T00:00:00Z")
            // Literal bytes and their fixed digests avoid a hashing fallback on
            // Linux. They remain header-only cache-mechanics fixtures.
            let text = #"{"schema_version":"1.0.0","id":"synthetic-history-\#(kind.rawValue)","revision":1,"captured_at":"2026-10-18T00:00:00Z"}"#
            artifacts[kind] = Data(text.utf8)
            pins.append(ArtifactPin(kind: kind, identity: identity, sha256: try XCTUnwrap(digests[kind])))
        }
        let completeRequest = CacheManifest(pins: pins)
        let completeArtifacts = artifacts
        let manifest = try JSONSerialization.jsonObject(with: JSONEncoder().encode(completeRequest))
        let knownPins = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pins))
        let record: [String: Any] = [
            "manifest": manifest,
            "artifacts": Dictionary(uniqueKeysWithValues: completeArtifacts.map { ($0.key.rawValue, $0.value.base64EncodedString()) }),
            "cachedAt": 123, "synthetic": true
        ]
        let object: [String: Any] = [
            "storageVersion": "__CACHE_VERSION__", "activeManifest": manifest,
            "records": [record], "knownPins": knownPins
        ]
        let template = String(decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
        let versionField = #""storageVersion":"__CACHE_VERSION__""#
        XCTAssertEqual(template.components(separatedBy: versionField).count, 2, "Exactly one top-level version field is changed")
        let original = Data(template.replacingOccurrences(of: versionField, with: #""storageVersion":2"#).utf8)
        let completeStore = try cache(url)

        func checkCompleteEnvelopeAdmission() async throws {
            #if canImport(CryptoKit)
            let active = try await completeStore.load(mode: .syntheticPreview)
            try assertPair(active, completeRequest, completeArtifacts, date: Date(timeIntervalSinceReferenceDate: 123))
            let historical = try await completeStore.load(completeRequest, mode: .syntheticPreview)
            try assertPair(historical, completeRequest, completeArtifacts, date: Date(timeIntervalSinceReferenceDate: 123))
            #else
            // This proves only that decoding reached the real hash boundary;
            // unsupportedHashPlatform is never successful cache admission.
            do { _ = try await completeStore.load(mode: .syntheticPreview); XCTFail("Unavailable hashing unexpectedly succeeded") }
            catch { XCTAssertEqual(error as? CatalogCacheError, .unsupportedHashPlatform) }
            do { _ = try await completeStore.load(completeRequest, mode: .syntheticPreview); XCTFail("Unavailable hashing unexpectedly succeeded") }
            catch { XCTAssertEqual(error as? CatalogCacheError, .unsupportedHashPlatform) }
            #endif
            XCTAssertEqual(try Data(contentsOf: file(url)), original)
        }

        try original.write(to: file(url))
        try await checkCompleteEnvelopeAdmission()
        for token in ["3", "null", #""2""#, "true"] {
            let changed = Data(template.replacingOccurrences(of: versionField, with: #""storageVersion":"# + token).utf8)
            try changed.write(to: file(url))
            do { _ = try await completeStore.load(mode: .syntheticPreview); XCTFail("Unsupported complete envelope became active") }
            catch { XCTAssertEqual(error as? CatalogCacheError, .corruptCache, token) }
            XCTAssertEqual(try Data(contentsOf: file(url)), changed)
            do { _ = try await completeStore.load(completeRequest, mode: .syntheticPreview); XCTFail("Unsupported complete history was returned") }
            catch { XCTAssertEqual(error as? CatalogCacheError, .corruptCache, token) }
            XCTAssertEqual(try Data(contentsOf: file(url)), changed)
            do {
                try await completeStore.refresh(completeRequest, mode: .syntheticPreview) { _ in
                    XCTFail("Unsupported complete storage reached download")
                    return Data()
                }
                XCTFail("Unsupported complete storage was replaced")
            } catch { XCTAssertEqual(error as? CatalogCacheError, .corruptCache, token) }
            XCTAssertEqual(try Data(contentsOf: file(url)), changed)
        }
        try original.write(to: file(url))
        try await checkCompleteEnvelopeAdmission()
    }

    func testCorruptHistoricalPayloadBlocksReturnAndRefreshUntilExplicitRecovery() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let store = try cache(url)
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await store.refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let original = try Data(contentsOf: file(url))
        let changed = try json(original) { object in
            var records = try XCTUnwrap(object["records"] as? [[String: Any]])
            var artifacts = try XCTUnwrap(records[0]["artifacts"] as? [String: String])
            artifacts["catalog"] = Data("tampered history".utf8).base64EncodedString()
            records[0]["artifacts"] = artifacts
            object["records"] = records
        }
        try changed.write(to: file(url))
        for request in [first, second] {
            do { _ = try await cache(url).load(request, mode: .syntheticPreview); XCTFail("Corrupt history returned") }
            catch { XCTAssertEqual(error as? CatalogCacheError, .digestMismatch) }
        }
        do { _ = try await store.load(mode: .syntheticPreview); XCTFail("Active load ignored corrupt history") }
        catch { XCTAssertEqual(error as? CatalogCacheError, .digestMismatch) }
        do {
            try await store.refresh(second, mode: .syntheticPreview) { _ in XCTFail("Corrupt history was discarded"); return Data() }
            XCTFail("Corrupt envelope refreshed")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .digestMismatch) }
        XCTAssertEqual(try Data(contentsOf: file(url)), changed)
        try original.write(to: file(url), options: .atomic)
        let restored = try await cache(url).load(first, mode: .syntheticPreview)
        try assertPair(restored, first, firstBytes)
        let active = try await cache(url).load(mode: .syntheticPreview)
        try assertPair(active, second, secondBytes)
        XCTAssertEqual(try Data(contentsOf: file(url)), original)
    }

    func testMalformedHistoryAndMissingActiveRecordAreRejected() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let (unknown, _) = try fixture(3)
        let store = try cache(url)
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await store.refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let original = try Data(contentsOf: file(url))
        let missing = try json(original) { object in
            var records = try XCTUnwrap(object["records"] as? [[String: Any]])
            var artifacts = try XCTUnwrap(records[0]["artifacts"] as? [String: String])
            artifacts.removeValue(forKey: "pricebook")
            records[0]["artifacts"] = artifacts
            object["records"] = records
        }
        let duplicate = try json(original) { object in
            var records = try XCTUnwrap(object["records"] as? [[String: Any]])
            records.append(records[0])
            object["records"] = records
        }
        let missingActive = try json(original) { object in
            object["activeManifest"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(unknown))
        }
        let ambiguousFormat = try json(original) { object in
            object["manifest"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(second))
        }
        for (bytes, expected) in [(missing, CatalogCacheError.incompleteRelease), (duplicate, .corruptCache),
                                  (missingActive, .corruptCache), (ambiguousFormat, .corruptCache)] {
            try bytes.write(to: file(url))
            do { _ = try await store.load(mode: .syntheticPreview); XCTFail("Malformed history admitted") }
            catch { XCTAssertEqual(error as? CatalogCacheError, expected) }
            XCTAssertEqual(try Data(contentsOf: file(url)), bytes)
        }
    }

    func testHistoricalContractValidationCannotBeSkippedByLoadingActivePair() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        try await cache(url).refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await cache(url).refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let before = try Data(contentsOf: file(url))
        let rejecting = try CatalogCache(directory: url) { _, data in
            if try JSONDecoder().decode(ArtifactIdentity.self, from: data).revision == 1 {
                throw CatalogCacheError.incompatibleIdentity
            }
        }
        do { _ = try await rejecting.load(mode: .syntheticPreview); XCTFail("Historical receiver validation skipped") }
        catch { XCTAssertEqual(error as? CatalogCacheError, .incompatibleIdentity) }
        XCTAssertEqual(try Data(contentsOf: file(url)), before)
    }

    func testOversizedAndMismatchedNewArtifactsPreserveBothExistingPairs() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let (third, thirdBytes) = try fixture(3)
        let store = try cache(url, artifactBytes: 1_024)
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await store.refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let before = try Data(contentsOf: file(url))
        do {
            try await store.refresh(third, mode: .syntheticPreview) { kind in
                kind == .catalog ? Data(repeating: 0x20, count: 1_025) : thirdBytes[kind]!
            }
            XCTFail("Oversized artifact committed")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .oversizedRelease) }
        let pin = third.pins[0]
        let wrongIdentity = ArtifactIdentity(schemaVersion: "1.0.0", id: "synthetic-wrong-history-id",
                                             revision: pin.identity.revision, capturedAt: pin.identity.capturedAt)
        let mismatched = CacheManifest(pins: [ArtifactPin(kind: pin.kind, identity: wrongIdentity, sha256: pin.sha256), third.pins[1]])
        do {
            try await store.refresh(mismatched, mode: .syntheticPreview) { thirdBytes[$0]! }
            XCTFail("Correct hash hid an identity mismatch")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .incompatibleIdentity) }
        XCTAssertEqual(try Data(contentsOf: file(url)), before)
        let retained = try await store.load(first, mode: .syntheticPreview)
        try assertPair(retained, first, firstBytes)
        let active = try await store.load(mode: .syntheticPreview)
        try assertPair(active, second, secondBytes)
        let absent = try await store.load(third, mode: .syntheticPreview)
        XCTAssertNil(absent)
    }

    func testFilesystemPublicationFailureRetainsCompleteEnvelopeForRecovery() async throws {
        let root = try directory(), url = root.appendingPathComponent("cache")
        let backup = root.appendingPathComponent("retained-cache")
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let (third, thirdBytes) = try fixture(3)
        let store = try cache(url)
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await store.refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let before = try Data(contentsOf: file(url)), obstruction = Data("synthetic publication obstruction".utf8)
        do {
            try await store.refresh(third, mode: .syntheticPreview) { kind in
                if kind == .catalog {
                    // After the old complete envelope has been validated, make the
                    // destination unwritable as a directory. This is a controlled
                    // filesystem fault, not a device crash or full-disk claim.
                    try FileManager.default.moveItem(at: url, to: backup)
                    try obstruction.write(to: url)
                }
                return thirdBytes[kind]!
            }
            XCTFail("Publication under a regular file succeeded")
        } catch { XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain) }
        XCTAssertEqual(try Data(contentsOf: file(backup)), before)
        XCTAssertEqual(try Data(contentsOf: url), obstruction)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: backup, to: url)
        let retained = try await cache(url).load(first, mode: .syntheticPreview)
        try assertPair(retained, first, firstBytes)
        let active = try await cache(url).load(mode: .syntheticPreview)
        try assertPair(active, second, secondBytes)
        let absent = try await cache(url).load(third, mode: .syntheticPreview)
        XCTAssertNil(absent)
        try await store.refresh(third, mode: .syntheticPreview) { thirdBytes[$0]! }
        let retried = try await cache(url).load(mode: .syntheticPreview)
        try assertPair(retried, third, thirdBytes)
    }

    func testInterruptedThirdDownloadPreservesBothExistingPairsAndRetry() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let (third, thirdBytes) = try fixture(3)
        let store = try cache(url)
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await store.refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let before = try Data(contentsOf: file(url))
        do {
            try await store.refresh(third, mode: .syntheticPreview) { kind in
                if kind == .pricebook { throw URLError(.networkConnectionLost) }
                return thirdBytes[kind]!
            }
            XCTFail("Partial third pair committed")
        } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        XCTAssertEqual(try Data(contentsOf: file(url)), before)
        let retained = try await cache(url).load(first, mode: .syntheticPreview)
        try assertPair(retained, first, firstBytes)
        let active = try await cache(url).load(mode: .syntheticPreview)
        try assertPair(active, second, secondBytes)
        let absent = try await store.load(third, mode: .syntheticPreview)
        XCTAssertNil(absent)
        try await store.refresh(third, mode: .syntheticPreview) { thirdBytes[$0]! }
        let recovered = try await cache(url).load(mode: .syntheticPreview)
        try assertPair(recovered, third, thirdBytes)
        let previous = try await cache(url).load(second, mode: .syntheticPreview)
        try assertPair(previous, second, secondBytes)
    }

    func testTaskCancellationAndOverlappingRefreshPreserveHistoricalReads() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let (third, thirdBytes) = try fixture(3)
        let store = try cache(url)
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        try await store.refresh(second, mode: .syntheticPreview) { secondBytes[$0]! }
        let before = try Data(contentsOf: file(url)), gate = HistoryDownloadGate()
        let refresh = Task {
            try await store.refresh(third, mode: .syntheticPreview) { kind in
                if kind == .pricebook { await gate.pause() }
                return thirdBytes[kind]!
            }
        }
        await gate.waitForEntry()
        let old = try await store.load(first, mode: .syntheticPreview)
        try assertPair(old, first, firstBytes)
        do {
            try await store.refresh(third, mode: .syntheticPreview) { _ in XCTFail("Overlapping download started"); return Data() }
            XCTFail("Overlapping refresh admitted")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .incompleteRelease) }
        refresh.cancel()
        await gate.release()
        do { try await refresh.value; XCTFail("Canceled refresh committed") }
        catch is CancellationError {} catch { throw error }
        XCTAssertEqual(try Data(contentsOf: file(url)), before)
        let active = try await cache(url).load(mode: .syntheticPreview)
        try assertPair(active, second, secondBytes)
        let absent = try await cache(url).load(third, mode: .syntheticPreview)
        XCTAssertNil(absent)
        try await store.refresh(third, mode: .syntheticPreview) { thirdBytes[$0]! }
        let recovered = try await store.load(mode: .syntheticPreview)
        try assertPair(recovered, third, thirdBytes)
    }

    func testEncodedByteQuotaRejectsBeforeCommitAndAcceptsExactCapacity() async throws {
        let probe = try directory(), url = try directory()
        let (first, firstBytes) = try fixture(1), (second, secondBytes) = try fixture(2)
        let date = Date(timeIntervalSince1970: 100)
        try await cache(probe).refresh(first, mode: .syntheticPreview, now: date) { firstBytes[$0]! }
        try await cache(probe).refresh(second, mode: .syntheticPreview, now: date) { secondBytes[$0]! }
        let fullSize = try Data(contentsOf: file(probe)).count
        let constrained = try cache(url, bytes: fullSize - 1)
        try await constrained.refresh(first, mode: .syntheticPreview, now: date) { firstBytes[$0]! }
        let before = try Data(contentsOf: file(url))
        do {
            try await constrained.refresh(second, mode: .syntheticPreview, now: date) { secondBytes[$0]! }
            XCTFail("Encoded history exceeded the cap")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .oversizedRelease) }
        XCTAssertEqual(try Data(contentsOf: file(url)), before)
        let retained = try await constrained.load(first, mode: .syntheticPreview)
        try assertPair(retained, first, firstBytes)
        let absent = try await constrained.load(second, mode: .syntheticPreview)
        XCTAssertNil(absent)
        try await cache(url, bytes: fullSize).refresh(second, mode: .syntheticPreview, now: date) { secondBytes[$0]! }
        XCTAssertEqual(try Data(contentsOf: file(url)).count, fullSize)
        let active = try await cache(url, bytes: fullSize).load(mode: .syntheticPreview)
        try assertPair(active, second, secondBytes)
        let historical = try await cache(url, bytes: fullSize).load(first, mode: .syntheticPreview)
        try assertPair(historical, first, firstBytes)
        let complete = try Data(contentsOf: file(url))
        do { _ = try await constrained.load(first, mode: .syntheticPreview); XCTFail("Lowered byte cap discarded bytes") }
        catch { XCTAssertEqual(error as? CatalogCacheError, .oversizedRelease) }
        XCTAssertEqual(try Data(contentsOf: file(url)), complete)
    }

    func testLegacyKnownPinCapacitySurvivesMigrationAndRejectsNewVersion() async throws {
        let url = try directory()
        let (first, firstBytes) = try fixture(1), (new, _) = try fixture(1_025)
        var known = first.pins
        for revision in 2...1_024 { known.append(contentsOf: placeholder(revision).pins) }
        XCTAssertEqual(known.count, 2_048)
        let original = try legacy(first, firstBytes, known: known, date: Date(timeIntervalSince1970: 100))
        try original.write(to: file(url))
        let store = try cache(url)
        do {
            try await store.refresh(new, mode: .syntheticPreview) { _ in XCTFail("Known-pin quota reached download"); return Data() }
            XCTFail("Known-pin ledger was evicted")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .historyLimitReached) }
        XCTAssertEqual(try Data(contentsOf: file(url)), original)
        try await store.refresh(first, mode: .syntheticPreview) { firstBytes[$0]! }
        let migrated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file(url))) as? [String: Any])
        XCTAssertEqual((migrated["knownPins"] as? [Any])?.count, 2_048)
        let absent = try await cache(url).load(placeholder(2), mode: .syntheticPreview)
        XCTAssertNil(absent)
    }
}

// This is the exact required-field shape of the legacy main71db cache envelope.
private struct LegacyCacheEnvelope: Codable {
    let manifest: CacheManifest
    let artifacts: [String: Data]
    let cachedAt: Date
    let synthetic: Bool
    let knownPins: [ArtifactPin]
}

private actor HistoryDownloadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var entered = false
    func pause() async {
        entered = true
        observer?.resume(); observer = nil
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
