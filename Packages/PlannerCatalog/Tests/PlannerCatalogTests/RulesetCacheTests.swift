import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import PlannerCatalog

private enum RulesFixtureError: Error { case rejected, unexpectedDownload }

private actor RulesDownloadGate {
    private var started = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Data, Never>?
    func fetch() async -> Data {
        started = true
        for observer in observers { observer.resume() }
        observers.removeAll()
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release(_ bytes: Data) { continuation?.resume(returning: bytes); continuation = nil }
}

final class RulesetCacheTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func file(_ directory: URL) -> URL { directory.appendingPathComponent("rules-preview-v1.json") }
    private static func identity(_ version: String = "1.0.0", id: String = "rules.synthetic",
                                 publishedAt: String = "2026-10-19T00:00:00Z") -> RulesetIdentity {
        RulesetIdentity(schemaVersion: "1.0.0", id: id, version: version, publishedAt: publishedAt)
    }
    private func placeholder(_ version: String = "1.0.0") -> RulesetPin {
        RulesetPin(identity: Self.identity(version), sha256: String(repeating: "0", count: 64))
    }
    // This controlled decoder tests the required validation seam and storage
    // mechanics. It is not the unadopted PlannerTransfer Ruleset validator.
    private static func header(_ data: Data) throws -> RulesetIdentity {
        try JSONDecoder().decode(RulesetIdentity.self, from: data)
    }
    private func cache(_ url: URL, count: Int = 32, bytes: Int? = nil,
                       artifactBytes: Int = 512 * 1_024,
                       validator: @escaping RulesetCache.Validator = RulesetCacheTests.header) throws -> RulesetCache {
        try RulesetCache(directory: url, maximumArtifactBytes: artifactBytes,
                         maximumRulesets: count, maximumCacheBytes: bytes, validateContract: validator)
    }
    private func fixture(_ version: String = "1.0.0", padding: Int = 0) throws -> (RulesetPin, Data) {
        #if !canImport(CryptoKit)
        throw XCTSkip("Actual CryptoKit hashing and rules persistence require the configured macOS suite")
        #else
        let identity = Self.identity(version)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // Keep non-normalized whitespace to prove the original bytes survive.
        let bytes = Data(String(repeating: " ", count: padding + 1).utf8) + (try encoder.encode(identity)) + Data("\n".utf8)
        return (RulesetPin(identity: identity, sha256: try CatalogCache.sha256(bytes)), bytes)
        #endif
    }
    private func expect(_ expected: RulesetCacheError, _ operation: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? RulesetCacheError, expected, file: file, line: line) }
    }
    private func changed(_ bytes: Data, _ edit: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        try edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    func testIdentityAndPinEqualityAndHashingPreserveExactBytes() {
        let composed = "\u{e9}", decomposed = "e\u{301}"
        XCTAssertEqual(composed, decomposed) // Demonstrate the ordinary Swift comparison.
        // Public value semantics remain exact even before a receiver admits a pin.
        for field in 0..<4 {
            var a = ["1.0.0", "rules.synthetic", "1.0.0", "2026-10-19T00:00:00Z"]
            var b = a; a[field] = composed; b[field] = decomposed
            let first = RulesetIdentity(schemaVersion: a[0], id: a[1], version: a[2], publishedAt: a[3])
            let second = RulesetIdentity(schemaVersion: b[0], id: b[1], version: b[2], publishedAt: b[3])
            XCTAssertNotEqual(first, second)
            XCTAssertEqual(Set([first, second, first]).count, 2)
            XCTAssertEqual(Set([RulesetPin(identity: first, sha256: "0"), RulesetPin(identity: second, sha256: "0")]).count, 2)
        }
        let first = RulesetPin(identity: Self.identity(), sha256: composed)
        let second = RulesetPin(identity: Self.identity(), sha256: decomposed)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 2)
        XCTAssertNotEqual(Self.identity("01.0.0"), Self.identity("1.0.0"))
    }

    func testConfigurationPinAndProductionGuardsHaveNoSideEffects() async throws {
        let url = try directory().appendingPathComponent("missing")
        for artifactBytes in [0, -1, Int.max] {
            XCTAssertThrowsError(try cache(url, artifactBytes: artifactBytes)) {
                XCTAssertEqual($0 as? RulesetCacheError, .invalidConfiguration)
            }
        }
        for count in [0, 129] { XCTAssertThrowsError(try cache(url, count: count)) }
        for bytes in [0, -1, Int.max] { XCTAssertThrowsError(try cache(url, bytes: bytes)) }
        let store = try cache(url)
        let pin = placeholder()
        await expect(.productionReceiptUnavailable) { _ = try await store.load(pin, mode: .production) }
        await expect(.productionReceiptUnavailable) {
            try await store.retain(pin, mode: .production) { throw RulesFixtureError.unexpectedDownload }
        }
        for invalid in [RulesetPin(identity: Self.identity(""), sha256: pin.sha256),
                        RulesetPin(identity: Self.identity(id: ""), sha256: pin.sha256),
                        RulesetPin(identity: Self.identity(publishedAt: ""), sha256: pin.sha256),
                        RulesetPin(identity: pin.identity, sha256: String(repeating: "A", count: 64))] {
            await expect(.invalidPin) { _ = try await store.load(invalid, mode: .syntheticPreview) }
        }
        await expect(.invalidConfiguration) {
            try await store.retain(pin, mode: .syntheticPreview, now: Date(timeIntervalSinceReferenceDate: .infinity)) {
                throw RulesFixtureError.unexpectedDownload
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testMissingRulesDoNotReadRewriteOrInferPairCacheContents() async throws {
        let url = try directory(), pair = url.appendingPathComponent("active-preview-v1.json")
        // Namespace controls intentionally do not claim full pair validity.
        for bytes in [Data("legacy pair bytes".utf8), Data("{\"storageVersion\":2,\"records\":[]}".utf8)] {
            try bytes.write(to: pair)
            let result = try await cache(url).load(placeholder(), mode: .syntheticPreview)
            XCTAssertNil(result)
            XCTAssertEqual(try Data(contentsOf: pair), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: file(url).path))
        }
    }

    func testBoundedReaderRejectsCorruptVersionsDirectoriesFIFOsAndLargeTargets() async throws {
        let url = try directory(), target = file(url)
        let store = try cache(url, bytes: 128)
        let cases: [(Data, RulesetCacheError)] = [
            (Data("{\"storageVersion\":\"2\",\"records\":[]}".utf8), .unsupportedStorageVersion),
            (Data("{\"storageVersion\":1.0000000000000001,\"records\":[]}".utf8), .corruptCache),
            (Data("{\"storageVersion\":\"1\",\"records\":[]}".utf8), .corruptCache),
            (Data("broken".utf8), .corruptCache), (Data(repeating: 32, count: 129), .oversizedCache)
        ]
        for (bytes, error) in cases {
            try bytes.write(to: target)
            await expect(error) { _ = try await store.load(self.placeholder(), mode: .syntheticPreview) }
            XCTAssertEqual(try Data(contentsOf: target), bytes)
        }
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        await expect(.corruptCache) { _ = try await store.load(self.placeholder(), mode: .syntheticPreview) }
        try FileManager.default.removeItem(at: target)
        XCTAssertEqual(mkfifo(target.path, mode_t(0o600)), 0)
        await expect(.corruptCache) { _ = try await store.load(self.placeholder(), mode: .syntheticPreview) }
        try FileManager.default.removeItem(at: target)
        let large = url.appendingPathComponent("oversized")
        let bytes = Data(repeating: 32, count: 129); try bytes.write(to: large)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: large)
        await expect(.oversizedCache) { _ = try await store.load(self.placeholder(), mode: .syntheticPreview) }
        XCTAssertEqual(try Data(contentsOf: large), bytes)
    }

    func testOriginalRulesHistorySurvivesRestartAndExactRepeatsReuseCapacity() async throws {
        let url = try directory(), store = try cache(url, count: 3)
        let (a, first) = try fixture(), (b, second) = try fixture("2.0.0"), (c, leadingZero) = try fixture("01.0.0")
        let firstDate = Date(timeIntervalSinceReferenceDate: 10), secondDate = Date(timeIntervalSinceReferenceDate: 20)
        try await store.retain(a, mode: .syntheticPreview, now: firstDate) { first }
        try await store.retain(b, mode: .syntheticPreview, now: secondDate) { second }
        try await store.retain(c, mode: .syntheticPreview, now: secondDate) { leadingZero }
        let reopened = try cache(url, count: 3)
        let original = try await reopened.load(a, mode: .syntheticPreview)
        XCTAssertEqual(original?.bytes, first); XCTAssertEqual(original?.cachedAt, firstDate)
        XCTAssertTrue(try XCTUnwrap(original).isSynthetic)
        if case .unknown = try XCTUnwrap(original).currentChecks {} else { XCTFail("Cached rules do not qualify current checks") }
        XCTAssertEqual(original?.age(at: Date(timeIntervalSinceReferenceDate: 15)), 5)
        try await reopened.retain(a, mode: .syntheticPreview, now: secondDate) { first }
        let repeated = try await reopened.load(a, mode: .syntheticPreview)
        let other = try await reopened.load(b, mode: .syntheticPreview)
        let distinct = try await reopened.load(c, mode: .syntheticPreview)
        XCTAssertEqual(repeated?.bytes, first); XCTAssertEqual(repeated?.cachedAt, secondDate)
        XCTAssertEqual(other?.bytes, second); XCTAssertEqual(other?.cachedAt, secondDate)
        XCTAssertEqual(distinct?.bytes, leadingZero)
        let absent = try await reopened.load(placeholder("3.0.0"), mode: .syntheticPreview)
        XCTAssertNil(absent)
    }

    func testImmutableMetadataConflictsPreserveTheCommittedVersion() async throws {
        let url = try directory(), store = try cache(url)
        let (pin, bytes) = try fixture(); try await store.retain(pin, mode: .syntheticPreview) { bytes }
        let original = try Data(contentsOf: file(url))
        let changedDate = RulesetPin(identity: Self.identity(publishedAt: "2026-10-19T01:00:00Z"), sha256: pin.sha256)
        let changedHash = RulesetPin(identity: pin.identity, sha256: String(repeating: "0", count: 64))
        for conflict in [changedDate, changedHash] {
            await expect(.immutableVersionConflict) { _ = try await store.load(conflict, mode: .syntheticPreview) }
            await expect(.immutableVersionConflict) {
                try await store.retain(conflict, mode: .syntheticPreview) { throw RulesFixtureError.unexpectedDownload }
            }
            XCTAssertEqual(try Data(contentsOf: file(url)), original)
        }
    }

    func testDigestIdentityValidatorAndArtifactFailuresPreserveHistory() async throws {
        let url = try directory(), store = try cache(url)
        let (a, first) = try fixture(), (b, second) = try fixture("2.0.0")
        try await store.retain(a, mode: .syntheticPreview) { first }
        let original = try Data(contentsOf: file(url))
        await expect(.digestMismatch) { try await store.retain(b, mode: .syntheticPreview) { first } }
        let wrongIdentity = try cache(url, validator: { data in
            let value = try Self.header(data)
            return value.version == "2.0.0" ? Self.identity("3.0.0") : value
        })
        await expect(.incompatibleIdentity) { try await wrongIdentity.retain(b, mode: .syntheticPreview) { second } }
        let rejecting = try cache(url, validator: { data in
            let value = try Self.header(data)
            if value.version == "2.0.0" { throw RulesFixtureError.rejected }
            return value
        })
        do { try await rejecting.retain(b, mode: .syntheticPreview) { second }; XCTFail("Required validator was bypassed") }
        catch { XCTAssertTrue(error is RulesFixtureError) }
        let (largePin, large) = try fixture("2.0.0", padding: 100)
        let small = try cache(url, artifactBytes: first.count)
        await expect(.oversizedCache) { try await small.retain(largePin, mode: .syntheticPreview) { large } }
        XCTAssertEqual(try Data(contentsOf: file(url)), original)
        try await store.retain(b, mode: .syntheticPreview) { second }
        let recovered = try await store.load(b, mode: .syntheticPreview)
        XCTAssertEqual(recovered?.bytes, second)
    }

    func testWholeHistoryValidationRejectsCorruptionAndAllowsExplicitRecovery() async throws {
        let url = try directory(), store = try cache(url)
        let (a, first) = try fixture(), (b, second) = try fixture("2.0.0")
        try await store.retain(a, mode: .syntheticPreview) { first }
        try await store.retain(b, mode: .syntheticPreview) { second }
        let original = try Data(contentsOf: file(url))
        let corrupt = try changed(original) { object in
            var records = try XCTUnwrap(object["records"] as? [[String: Any]])
            records[1]["bytes"] = first.base64EncodedString(); object["records"] = records
        }
        try corrupt.write(to: file(url))
        await expect(.digestMismatch) { _ = try await store.load(a, mode: .syntheticPreview) }
        await expect(.digestMismatch) {
            try await store.retain(a, mode: .syntheticPreview) { throw RulesFixtureError.unexpectedDownload }
        }
        XCTAssertEqual(try Data(contentsOf: file(url)), corrupt)
        try original.write(to: file(url))
        let strict = try cache(url, validator: { data in
            let value = try Self.header(data)
            if value.version == "2.0.0" { throw RulesFixtureError.rejected }
            return value
        })
        do { _ = try await strict.load(a, mode: .syntheticPreview); XCTFail("History must be revalidated") }
        catch { XCTAssertTrue(error is RulesFixtureError) }
        XCTAssertEqual(try Data(contentsOf: file(url)), original)
        let duplicate = try changed(original) { object in
            let records = try XCTUnwrap(object["records"] as? [[String: Any]])
            object["records"] = [records[0], records[0]]
        }
        try duplicate.write(to: file(url))
        await expect(.corruptCache) { _ = try await store.load(a, mode: .syntheticPreview) }
        XCTAssertEqual(try Data(contentsOf: file(url)), duplicate)
        try original.write(to: file(url))
        let restored = try await store.load(a, mode: .syntheticPreview)
        XCTAssertEqual(restored?.bytes, first)
    }

    func testQuotaBoundariesRejectWithoutEvictionAndPermitExactRecovery() async throws {
        let url = try directory(), reference = try directory()
        let (a, first) = try fixture(), (b, second) = try fixture("2.0.0")
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let store = try cache(url, count: 1)
        try await store.retain(a, mode: .syntheticPreview, now: date) { first }
        let original = try Data(contentsOf: file(url))
        await expect(.historyLimitReached) {
            try await store.retain(b, mode: .syntheticPreview, now: date) { throw RulesFixtureError.unexpectedDownload }
        }
        try await store.retain(a, mode: .syntheticPreview, now: date) { first }
        XCTAssertEqual(try Data(contentsOf: file(url)), original)
        let control = try cache(reference)
        try await control.retain(a, mode: .syntheticPreview, now: date) { first }
        try await control.retain(b, mode: .syntheticPreview, now: date) { second }
        let complete = try Data(contentsOf: file(reference))
        let below = try cache(url, bytes: complete.count - 1)
        await expect(.oversizedCache) { try await below.retain(b, mode: .syntheticPreview, now: date) { second } }
        XCTAssertEqual(try Data(contentsOf: file(url)), original)
        let exact = try cache(url, bytes: complete.count)
        try await exact.retain(b, mode: .syntheticPreview, now: date) { second }
        XCTAssertEqual(try Data(contentsOf: file(url)), complete)
        let readable = try await exact.load(a, mode: .syntheticPreview)
        XCTAssertEqual(readable?.bytes, first)
        let tooSmall = try cache(url, bytes: complete.count - 1)
        await expect(.oversizedCache) { _ = try await tooSmall.load(a, mode: .syntheticPreview) }
        XCTAssertEqual(try Data(contentsOf: file(url)), complete)
    }

    func testSuspendedCancellationAndConcurrentRetentionPreserveThenRetry() async throws {
        let url = try directory(), store = try cache(url)
        let (a, first) = try fixture(), (b, second) = try fixture("2.0.0")
        try await store.retain(a, mode: .syntheticPreview) { first }
        let original = try Data(contentsOf: file(url)), gate = RulesDownloadGate()
        let pending = Task { try await store.retain(b, mode: .syntheticPreview) { await gate.fetch() } }
        await gate.waitForStart()
        await expect(.retentionInProgress) {
            try await store.retain(a, mode: .syntheticPreview) { throw RulesFixtureError.unexpectedDownload }
        }
        pending.cancel(); await gate.release(second)
        do { try await pending.value; XCTFail("Cancelled retention committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: file(url)), original)
        try await store.retain(b, mode: .syntheticPreview) { second }
        let restored = try await store.load(a, mode: .syntheticPreview)
        XCTAssertEqual(restored?.bytes, first)
    }

    func testFilesystemFailureKeepsRecoveryBytesAndAllowsRetry() async throws {
        let root = try directory(), url = root.appendingPathComponent("cache"), backup = root.appendingPathComponent("backup")
        let store = try cache(url), (a, first) = try fixture(), (b, second) = try fixture("2.0.0")
        try await store.retain(a, mode: .syntheticPreview) { first }
        let original = try Data(contentsOf: file(url)), gate = RulesDownloadGate()
        let pending = Task { try await store.retain(b, mode: .syntheticPreview) { await gate.fetch() } }
        await gate.waitForStart()
        // Controlled external filesystem fault after the old envelope was read.
        // Keep its actual bytes in backup; a file cannot become the cache directory.
        try FileManager.default.moveItem(at: url, to: backup)
        let obstruction = Data("write blocked".utf8); try obstruction.write(to: url)
        await gate.release(second)
        do { try await pending.value; XCTFail("Publication unexpectedly succeeded") } catch {}
        XCTAssertEqual(try Data(contentsOf: file(backup)), original)
        XCTAssertEqual(try Data(contentsOf: url), obstruction)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: backup, to: url)
        try await store.retain(b, mode: .syntheticPreview) { second }
        let restored = try await store.load(a, mode: .syntheticPreview)
        XCTAssertEqual(restored?.bytes, first)
    }
}
