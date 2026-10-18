import Foundation
import XCTest
@testable import PlannerCatalog

final class CatalogCacheTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // Synthetic HEADER-ONLY fixtures exercise cache mechanics, not schema conformance.
    private func fixture(_ revision: Int = 1) throws -> (CacheManifest, [CatalogArtifact: Data]) {
        #if !canImport(CryptoKit)
        throw XCTSkip("CryptoKit hashing requires Apple SDK; behavioral tests run on macOS CI")
        #else
        var artifacts: [CatalogArtifact: Data] = [:]
        var pins: [ArtifactPin] = []
        for kind in CatalogArtifact.allCases {
            let identity = ArtifactIdentity(schemaVersion: "1.0.0", id: "synthetic-demo-\(kind.rawValue)",
                                            revision: revision, capturedAt: "2026-10-18T00:00:00Z")
            let data = try JSONEncoder().encode(identity)
            artifacts[kind] = data
            pins.append(ArtifactPin(kind: kind, identity: identity, sha256: try CatalogCache.sha256(data)))
        }
        return (CacheManifest(pins: pins), artifacts)
        #endif
    }

    private func cache(_ directory: URL, limit: Int = 8 * 1_024 * 1_024) throws -> CatalogCache {
        try CatalogCache(directory: directory, maximumArtifactBytes: limit, validateContract: { _, _ in })
    }

    func testMissingCacheIsUnavailable() async throws {
        let store = try cache(directory())
        let value = try await store.load(mode: .syntheticPreview)
        XCTAssertNil(value)
    }

    func testMissingCacheDirectoryIsUnavailableWithoutCreatingIt() async throws {
        let parent = try directory()
        let missing = parent.appendingPathComponent("not-created")
        let store = try cache(missing)
        let value = try await store.load(mode: .syntheticPreview)
        XCTAssertNil(value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testDirectoryAtEnvelopePathRemainsCorruptAndPreserved() async throws {
        let url = try directory()
        let file = url.appendingPathComponent("active-preview-v1.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do {
            _ = try await cache(url).load(mode: .syntheticPreview)
            XCTFail("A directory was accepted as an absent or valid cache")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .corruptCache) }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeDirectory)
    }

    func testProductionRejectsEvenEmptyCacheAndEmptyManifest() async throws {
        let store = try cache(directory())
        do {
            _ = try await store.load(mode: .production)
            XCTFail("Production must require the missing real receipt")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .productionReceiptUnavailable) }
        do {
            try await store.refresh(CacheManifest(pins: []), mode: .production) { _ in
                XCTFail("Production must fail before downloading any reserved demo IDs")
                return Data()
            }
            XCTFail("Production activated")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .productionReceiptUnavailable) }
    }

    func testInvalidManifestFailsBeforeDownload() async throws {
        let store = try cache(directory())
        do {
            try await store.refresh(CacheManifest(pins: []), mode: .syntheticPreview) { _ in
                XCTFail("Invalid manifest must not download")
                return Data()
            }
            XCTFail("Invalid manifest activated")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .invalidManifest) }
    }

    func testRestartPreservesPairAgeAndUnknownChecks() async throws {
        let url = try directory()
        let (manifest, data) = try fixture()
        let date = Date(timeIntervalSince1970: 100)
        try await cache(url).refresh(manifest, mode: .syntheticPreview, now: date) { data[$0]! }
        let loaded = try await cache(url).load(mode: .syntheticPreview)
        let restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.manifest, manifest)
        XCTAssertEqual(restored.artifacts, data)
        XCTAssertEqual(restored.cachedAt, date)
        XCTAssertEqual(restored.age(at: Date(timeIntervalSince1970: 130)), 30)
        XCTAssertEqual(restored.age(at: Date(timeIntervalSince1970: 90)), 0)
        XCTAssertTrue(restored.isSynthetic)
        do {
            _ = try await cache(url).load(mode: .production)
            XCTFail("Stored reserved demo IDs entered real-data mode")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .productionReceiptUnavailable) }
        if case .unknown = restored.currentChecks {} else { XCTFail("Cache must not imply current checks passed") }
    }

    func testCorruptDownloadRetainsEntireOldPairAndCanRetry() async throws {
        let url = try directory()
        let (old, oldData) = try fixture()
        let (next, nextData) = try fixture(2)
        let store = try cache(url)
        try await store.refresh(old, mode: .syntheticPreview) { oldData[$0]! }
        do {
            try await store.refresh(next, mode: .syntheticPreview) {
                $0 == .pricebook ? Data("corrupt".utf8) : nextData[$0]!
            }
            XCTFail("Corrupt release activated")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .digestMismatch) }
        let restored = try await cache(url).load(mode: .syntheticPreview)
        XCTAssertEqual(restored?.manifest, old)
        XCTAssertEqual(restored?.artifacts, oldData)
        try await store.refresh(next, mode: .syntheticPreview) { nextData[$0]! }
        let retried = try await store.load(mode: .syntheticPreview)
        XCTAssertEqual(retried?.artifacts, nextData)
    }

    func testPartialDownloadFailureAndCancellationRetainOldRelease() async throws {
        let url = try directory()
        let (old, oldData) = try fixture()
        let (next, nextData) = try fixture(2)
        let store = try cache(url)
        try await store.refresh(old, mode: .syntheticPreview) { oldData[$0]! }
        do {
            try await store.refresh(next, mode: .syntheticPreview) {
                if $0 == .pricebook { throw CancellationError() }
                return nextData[$0]!
            }
            XCTFail("Cancelled refresh activated")
        } catch is CancellationError {} catch { throw error }
        let restored = try await cache(url).load(mode: .syntheticPreview)
        XCTAssertEqual(restored?.artifacts, oldData)
        // Retry after cancellation and duplicate delivery are both safe.
        for _ in 0..<2 { try await store.refresh(next, mode: .syntheticPreview) { nextData[$0]! } }
        let retried = try await store.load(mode: .syntheticPreview)
        XCTAssertEqual(retried?.manifest, next)
    }

    func testIdentityMustMatchEvenWithCorrectHash() async throws {
        let (manifest, data) = try fixture()
        let other = ArtifactIdentity(schemaVersion: "1.0.0", id: "synthetic-other", revision: 1,
                                     capturedAt: "2026-10-18T00:00:00Z")
        let changed = CacheManifest(pins: [ArtifactPin(kind: .catalog, identity: other, sha256: manifest.pins[0].sha256), manifest.pins[1]])
        let store = try cache(directory())
        do {
            try await store.refresh(changed, mode: .syntheticPreview) { data[$0]! }
            XCTFail("Wrong identity activated")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .incompatibleIdentity) }
    }

    func testDuplicatePinsRejected() async throws {
        let (manifest, data) = try fixture()
        let store = try cache(directory())
        do {
            try await store.refresh(CacheManifest(pins: [manifest.pins[0], manifest.pins[0]]), mode: .syntheticPreview) { data[$0]! }
            XCTFail("Duplicate pins activated")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .invalidManifest) }
    }

    func testOversizedArtifactRejected() async throws {
        let (manifest, data) = try fixture()
        let store = try cache(directory(), limit: 1)
        do {
            try await store.refresh(manifest, mode: .syntheticPreview) { data[$0]! }
            XCTFail("Oversized release activated")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .oversizedRelease) }
    }

    func testContractValidatorFailureLeavesOldBytesIntact() async throws {
        let url = try directory()
        let (manifest, data) = try fixture()
        try await cache(url).refresh(manifest, mode: .syntheticPreview) { data[$0]! }
        let before = try Data(contentsOf: url.appendingPathComponent("active-preview-v1.json"))
        let rejecting = try CatalogCache(directory: url) { _, _ in throw CatalogCacheError.incompatibleIdentity }
        do {
            try await rejecting.refresh(manifest, mode: .syntheticPreview) { data[$0]! }
            XCTFail("Invalid contract activated")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .incompatibleIdentity) }
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("active-preview-v1.json")), before)
        do {
            _ = try await rejecting.load(mode: .syntheticPreview)
            XCTFail("Load skipped contract validation")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .incompatibleIdentity) }
    }

    func testStoredBytesTamperedWithoutDigestUpdateAreRejected() async throws {
        let url = try directory()
        let (manifest, data) = try fixture()
        let store = try cache(url)
        try await store.refresh(manifest, mode: .syntheticPreview) { data[$0]! }
        let file = url.appendingPathComponent("active-preview-v1.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var artifacts = try XCTUnwrap(json["artifacts"] as? [String: String])
        artifacts["catalog"] = Data("tampered".utf8).base64EncodedString()
        json["artifacts"] = artifacts
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        do {
            _ = try await cache(url).load(mode: .syntheticPreview)
            XCTFail("Tampered cache returned")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .digestMismatch) }
    }

    func testTruncatedEnvelopeIsUnavailableAndNotDeleted() async throws {
        let url = try directory()
        let file = url.appendingPathComponent("active-preview-v1.json")
        let truncated = Data("{\"manifest\":".utf8)
        try truncated.write(to: file)
        do {
            _ = try await cache(url).load(mode: .syntheticPreview)
            XCTFail("Truncated release returned")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .corruptCache) }
        XCTAssertEqual(try Data(contentsOf: file), truncated)
    }

    func testSHA256KnownVector() throws {
        #if canImport(CryptoKit)
        XCTAssertEqual(try CatalogCache.sha256(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #else
        XCTAssertThrowsError(try CatalogCache.sha256(Data())) {
            XCTAssertEqual($0 as? CatalogCacheError, .unsupportedHashPlatform)
        }
        #endif
    }
}

private actor DownloadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered = false
    private var observer: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        observer?.resume()
        observer = nil
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

extension CatalogCacheTests {
    func testActualTaskCancellationAndOverlappingRefresh() async throws {
        let url = try directory()
        let store = try cache(url)
        let (old, oldData) = try fixture()
        let (next, nextData) = try fixture(2)
        try await store.refresh(old, mode: .syntheticPreview) { oldData[$0]! }
        let gate = DownloadGate()
        let task = Task {
            try await store.refresh(next, mode: .syntheticPreview) { kind in
                if kind == .pricebook { await gate.pause() }
                return nextData[kind]!
            }
        }
        await gate.waitForEntry()
        let during = try await store.load(mode: .syntheticPreview)
        XCTAssertEqual(during?.artifacts, oldData)
        do {
            try await store.refresh(next, mode: .syntheticPreview) { nextData[$0]! }
            XCTFail("Overlapping refresh must not race activation")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .incompleteRelease) }
        task.cancel()
        await gate.release()
        do { try await task.value; XCTFail("Cancelled task activated") }
        catch is CancellationError {} catch { throw error }
        let after = try await cache(url).load(mode: .syntheticPreview)
        XCTAssertEqual(after?.artifacts, oldData)
        try await store.refresh(next, mode: .syntheticPreview) { nextData[$0]! }
        let retried = try await cache(url).load(mode: .syntheticPreview)
        XCTAssertEqual(retried?.manifest, next)
    }

    func testAtomicWriteFailurePreservesPreviouslyStoredFile() async throws {
        let url = try directory()
        let store = try cache(url)
        let (manifest, data) = try fixture()
        try await store.refresh(manifest, mode: .syntheticPreview) { data[$0]! }
        let file = url.appendingPathComponent("active-preview-v1.json")
        let before = try Data(contentsOf: file)
        // Deterministic filesystem failure: a file is supplied as the cache directory.
        let impossible = try cache(file)
        do {
            try await impossible.refresh(manifest, mode: .syntheticPreview) { data[$0]! }
            XCTFail("Writing beneath a regular file succeeded")
        } catch { /* The filesystem error is expected; no old bytes are modified. */ }
        XCTAssertEqual(try Data(contentsOf: file), before)
    }
}

extension CatalogCacheTests {
    func testEnvelopeReadDistinguishesExactLimitFromOversizedBytes() async throws {
        let url = try directory()
        let file = url.appendingPathComponent("active-preview-v1.json")
        let store = try cache(url, limit: 1)
        let envelopeLimit = 3 + 2_097_152
        for extraByte in 0...1 {
            // Whitespace is deliberately invalid JSON: exactly-at-limit bytes must
            // reach decoding, while one extra byte must be rejected before decoding.
            let bytes = Data(repeating: 0x20, count: envelopeLimit + extraByte)
            try bytes.write(to: file, options: .atomic)
            do {
                _ = try await store.load(mode: .syntheticPreview)
                XCTFail("Invalid envelope was returned")
            } catch {
                XCTAssertEqual(error as? CatalogCacheError,
                               extraByte == 0 ? .corruptCache : .oversizedRelease)
            }
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testSmallSymlinkCannotBypassEnvelopeReadLimit() async throws {
        let url = try directory()
        let file = url.appendingPathComponent("active-preview-v1.json")
        let target = url.appendingPathComponent("oversized-preview.json")
        let envelopeLimit = 3 + 2_097_152
        let bytes = Data(repeating: 0x20, count: envelopeLimit + 1)
        try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: file.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertLessThan(try XCTUnwrap(attributes[.size] as? NSNumber).intValue, envelopeLimit)

        do {
            _ = try await cache(url, limit: 1).load(mode: .syntheticPreview)
            XCTFail("Oversized symlink target was returned")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .oversizedRelease) }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: file.path), destination)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    func testOversizedEnvelopeCanRecoverAfterExplicitValidByteRestoration() async throws {
        let url = try directory()
        let file = url.appendingPathComponent("active-preview-v1.json")
        let target = url.appendingPathComponent("oversized-preview.json")
        let limit = 1_024
        let store = try cache(url, limit: limit)
        let (manifest, data) = try fixture()
        let date = Date(timeIntervalSince1970: 100)
        try await store.refresh(manifest, mode: .syntheticPreview, now: date) { data[$0]! }
        let original = try Data(contentsOf: file)
        let oversized = Data(repeating: 0x20, count: limit * 3 + 2_097_152 + 1)
        try oversized.write(to: target)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: file.path)

        do {
            _ = try await store.load(mode: .syntheticPreview)
            XCTFail("Oversized replacement was returned")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .oversizedRelease) }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: file.path), destination)
        XCTAssertEqual(try Data(contentsOf: target), oversized)

        // The cache never deletes or repairs corruption. Explicitly restore the
        // original complete envelope, then verify a new actor can recover it.
        try FileManager.default.removeItem(at: file)
        try original.write(to: file, options: .atomic)
        let loaded = try await cache(url, limit: limit).load(mode: .syntheticPreview)
        let restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.manifest, manifest)
        XCTAssertEqual(restored.artifacts, data)
        XCTAssertEqual(restored.cachedAt, date)
        XCTAssertTrue(restored.isSynthetic)
        if case .unknown = restored.currentChecks {} else { XCTFail("Restoration must not imply current checks passed") }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try Data(contentsOf: target), oversized)
    }

    func testPreviouslyObservedVersionCannotChangeBytesAfterRestart() async throws {
        let url = try directory()
        let (first, firstData) = try fixture()
        let (second, secondData) = try fixture(2)
        try await cache(url).refresh(first, mode: .syntheticPreview) { firstData[$0]! }
        try await cache(url).refresh(second, mode: .syntheticPreview) { secondData[$0]! }
        // Same version identity, changed timestamp and recomputed digest: not an update.
        let changedIdentity = ArtifactIdentity(schemaVersion: "1.0.0", id: first.pins[0].identity.id,
                                              revision: 1, capturedAt: "2026-10-19T00:00:00Z")
        let changedBytes = try JSONEncoder().encode(changedIdentity)
        let changedPin = ArtifactPin(kind: .catalog, identity: changedIdentity,
                                     sha256: try CatalogCache.sha256(changedBytes))
        let changed = CacheManifest(pins: [changedPin, first.pins[1]])
        do {
            try await cache(url).refresh(changed, mode: .syntheticPreview) { kind in
                kind == .catalog ? changedBytes : firstData[kind]!
            }
            XCTFail("Historical version changed")
        } catch { XCTAssertEqual(error as? CatalogCacheError, .immutableVersionConflict) }
        let after = try await cache(url).load(mode: .syntheticPreview)
        XCTAssertEqual(after?.manifest, second)
    }

    func testNearLimitArtifactsCanBeLoadedAfterCommit() async throws {
        let url = try directory()
        let (manifest, initial) = try fixture()
        // Question marks generate slashes in base64, exercising JSON escaping expansion.
        let limit = 65_536
        var large: [CatalogArtifact: Data] = [:]
        var pins: [ArtifactPin] = []
        for pin in manifest.pins {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: initial[pin.kind]!) as? [String: Any])
            json["synthetic_padding"] = ""
            let overhead = try JSONSerialization.data(withJSONObject: json).count
            json["synthetic_padding"] = String(repeating: "?", count: limit - overhead)
            let bytes = try JSONSerialization.data(withJSONObject: json)
            XCTAssertEqual(bytes.count, limit)
            XCTAssertTrue(bytes.base64EncodedString().contains("/"))
            large[pin.kind] = bytes
            pins.append(ArtifactPin(kind: pin.kind, identity: pin.identity, sha256: try CatalogCache.sha256(bytes)))
        }
        let fixedLarge = large
        try await cache(url, limit: limit).refresh(CacheManifest(pins: pins), mode: .syntheticPreview) { fixedLarge[$0]! }
        let restored = try await cache(url, limit: limit).load(mode: .syntheticPreview)
        XCTAssertEqual(restored?.artifacts, fixedLarge)
        let encoded = try String(contentsOf: url.appendingPathComponent("active-preview-v1.json"), encoding: .utf8)
        XCTAssertFalse(encoded.contains("\\/"))
    }
}
