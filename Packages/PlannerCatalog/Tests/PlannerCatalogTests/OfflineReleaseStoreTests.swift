import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import PlannerCatalog

private enum OfflineFixtureError: Error { case interrupted, validation, gateTimeout }
private enum OfflineValidationStage: Sendable { case catalog, ruleset }

// Only the synchronous fixture validator waits here; all waits have a deadline.
// This makes an actual cache actor read suspend the selector at its await seam.
private final class OfflineValidationGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var armed: OfflineValidationStage?
    private var entered = false
    private var released = true
    func arm(_ stage: OfflineValidationStage = .catalog) {
        condition.lock(); defer { condition.unlock() }
        armed = stage; entered = false; released = false
    }
    func release() {
        condition.lock(); defer { condition.unlock() }
        released = true; condition.broadcast()
    }
    private func hasEntered() -> Bool {
        condition.lock(); defer { condition.unlock() }
        return entered
    }
    func waitForEntry() async throws {
        for _ in 0..<300 {
            if hasEntered() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw OfflineFixtureError.gateTimeout
    }
    private func pause(_ stage: OfflineValidationStage) throws {
        condition.lock()
        defer { condition.unlock() }
        if armed == stage {
            armed = nil; entered = true
            let deadline = Date().addingTimeInterval(10)
            while !released {
                if !condition.wait(until: deadline) { throw OfflineFixtureError.gateTimeout }
            }
        }
    }
    func validate(_ kind: CatalogArtifact, _ bytes: Data) throws {
        if kind == .catalog { try pause(.catalog) }
        _ = try JSONDecoder().decode(ArtifactIdentity.self, from: bytes)
    }
    func rules(_ bytes: Data) throws -> RulesetIdentity {
        try pause(.ruleset)
        return try JSONDecoder().decode(RulesetIdentity.self, from: bytes)
    }
}

private struct OfflineFixture: Sendable {
    let selection: OfflineReleaseSelection
    let artifacts: [CatalogArtifact: Data]
    let rules: Data
}

private struct OfflineEnvironment: Sendable {
    let directory: URL
    let pairs: CatalogCache
    let rules: RulesetCache
    let store: OfflineReleaseStore
    var selectionDirectory: URL { directory.appendingPathComponent("selection") }
    var selectionFile: URL { selectionDirectory.appendingPathComponent("offline-selection-preview-v1.json") }
    var pairFile: URL { directory.appendingPathComponent("pairs/active-preview-v1.json") }
    var rulesFile: URL { directory.appendingPathComponent("rules/rules-preview-v1.json") }
}

final class OfflineReleaseStoreTests: XCTestCase, @unchecked Sendable {
    private let firstDate = Date(timeIntervalSince1970: 1_792_000_000)
    private let laterDate = Date(timeIntervalSince1970: 1_792_000_100)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("offline-selector-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeEnvironment(_ root: URL? = nil, gate: OfflineValidationGate? = nil) throws -> OfflineEnvironment {
        let root = try root ?? directory()
        // These controlled header validators test cache/selection mechanics.
        // They are not the pending full frozen Ruleset adapter owned by PR 214.
        let pair = try CatalogCache(directory: root.appendingPathComponent("pairs")) { kind, bytes in
            if let gate { try gate.validate(kind, bytes) }
            else { _ = try JSONDecoder().decode(ArtifactIdentity.self, from: bytes) }
        }
        let rules = try RulesetCache(directory: root.appendingPathComponent("rules")) { bytes in
            if let gate { return try gate.rules(bytes) }
            return try JSONDecoder().decode(RulesetIdentity.self, from: bytes)
        }
        let store = try OfflineReleaseStore(directory: root.appendingPathComponent("selection"),
                                            catalogCache: pair, rulesetCache: rules)
        return OfflineEnvironment(directory: root, pairs: pair, rules: rules, store: store)
    }

    private func placeholder(_ revision: Int = 1) -> OfflineReleaseSelection {
        let digest = String(repeating: "0", count: 64)
        let pins = CatalogArtifact.allCases.map { kind in
            ArtifactPin(kind: kind,
                        identity: ArtifactIdentity(schemaVersion: "1.0.0", id: "synthetic." + kind.rawValue,
                                                   revision: revision, capturedAt: "2026-10-19T00:00:00Z"),
                        sha256: digest)
        }
        let rules = RulesetIdentity(schemaVersion: "1.0.0", id: "synthetic.rules",
                                    version: "1.0.\(revision)", publishedAt: "2026-10-19T00:00:00Z")
        return OfflineReleaseSelection(catalog: CacheManifest(pins: pins), ruleset: RulesetPin(identity: rules, sha256: digest))
    }

    private func fixture(_ revision: Int = 1, catalogID: String? = nil) throws -> OfflineFixture {
        #if !canImport(CryptoKit)
        throw XCTSkip("Actual retained payload/hash/activation execution requires the configured native CryptoKit suite")
        #else
        let request = placeholder(revision), encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var artifacts: [CatalogArtifact: Data] = [:], pins: [ArtifactPin] = []
        for original in request.catalog.pins {
            let identity = ArtifactIdentity(schemaVersion: original.identity.schemaVersion,
                id: original.kind == .catalog ? (catalogID ?? original.identity.id) : original.identity.id,
                revision: original.identity.revision, capturedAt: original.identity.capturedAt)
            let bytes = Data(" \n".utf8) + (try encoder.encode(identity)) + Data("\n".utf8)
            artifacts[original.kind] = bytes
            pins.append(ArtifactPin(kind: original.kind, identity: identity, sha256: try CatalogCache.sha256(bytes)))
        }
        let rules = Data("\n ".utf8) + (try encoder.encode(request.ruleset.identity)) + Data(" \n".utf8)
        let pin = RulesetPin(identity: request.ruleset.identity, sha256: try CatalogCache.sha256(rules))
        return OfflineFixture(selection: OfflineReleaseSelection(catalog: CacheManifest(pins: pins), ruleset: pin),
                              artifacts: artifacts, rules: rules)
        #endif
    }

    private func prepare(_ fixture: OfflineFixture, in environment: OfflineEnvironment, at date: Date) async throws {
        try await environment.pairs.refresh(fixture.selection.catalog, mode: .syntheticPreview, now: date) {
            try XCTUnwrap(fixture.artifacts[$0])
        }
        try await environment.rules.retain(fixture.selection.ruleset, mode: .syntheticPreview, now: date) { fixture.rules }
    }

    private func resources(_ environment: OfflineEnvironment) throws -> [Data] {
        try [Data(contentsOf: environment.pairFile), Data(contentsOf: environment.rulesFile)]
    }

    private func expect(_ expected: OfflineReleaseStoreError, _ operation: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? OfflineReleaseStoreError, expected, file: file, line: line) }
    }

    private func requireRelease(_ store: OfflineReleaseStore) async throws -> CachedOfflineRelease {
        let value = try await store.load(mode: .syntheticPreview)
        return try XCTUnwrap(value)
    }

    private func changed(_ bytes: Data, _ edit: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        try edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    func testMissingSelectionAndResourcesDoNotCreateOrInferState() async throws {
        let environment = try makeEnvironment()
        let missing = try await environment.store.load(mode: .syntheticPreview)
        XCTAssertNil(missing)
        await expect(.missingCatalogPair) {
            _ = try await environment.store.activate(self.placeholder(), mode: .syntheticPreview)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: environment.directory.path), [])
    }

    func testConfigurationRequestAndProductionGuardsHaveNoSideEffects() async throws {
        let environment = try makeEnvironment()
        for size in [0, -1, 65_537, Int.max] {
            XCTAssertThrowsError(try OfflineReleaseStore(directory: environment.selectionDirectory,
                catalogCache: environment.pairs, rulesetCache: environment.rules, maximumSelectionBytes: size))
        }
        XCTAssertThrowsError(try OfflineReleaseStore(directory: XCTUnwrap(URL(string: "https://example.invalid/cache")),
            catalogCache: environment.pairs, rulesetCache: environment.rules))
        await expect(.productionReceiptUnavailable) { _ = try await environment.store.load(mode: .production) }
        await expect(.productionReceiptUnavailable) {
            _ = try await environment.store.activate(self.placeholder(), mode: .production)
        }
        let invalid = OfflineReleaseSelection(catalog: CacheManifest(pins: []), ruleset: placeholder().ruleset)
        await expect(.invalidSelection) { _ = try await environment.store.activate(invalid, mode: .syntheticPreview) }
        await expect(.invalidSelection) {
            _ = try await environment.store.activate(self.placeholder(), mode: .syntheticPreview,
                                                  now: Date(timeIntervalSinceReferenceDate: .infinity))
        }
        let long = RulesetPin(identity: RulesetIdentity(schemaVersion: "1.0.0", id: "synthetic.rules",
            version: String(repeating: "a", count: 257), publishedAt: "2026-10-19T00:00:00Z"), sha256: placeholder().ruleset.sha256)
        await expect(.invalidSelection) {
            _ = try await environment.store.activate(OfflineReleaseSelection(catalog: self.placeholder().catalog, ruleset: long),
                                                  mode: .syntheticPreview)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: environment.directory.path), [])
    }

    func testBoundedReaderRejectsMalformedDirectoryFIFOAndOversizedTargets() async throws {
        let environment = try makeEnvironment()
        try FileManager.default.createDirectory(at: environment.selectionDirectory, withIntermediateDirectories: true)
        let malformed = Data("{".utf8)
        try malformed.write(to: environment.selectionFile)
        await expect(.corruptSelection) { _ = try await environment.store.load(mode: .syntheticPreview) }
        XCTAssertEqual(try Data(contentsOf: environment.selectionFile), malformed)
        try FileManager.default.removeItem(at: environment.selectionFile)
        try FileManager.default.createDirectory(at: environment.selectionFile, withIntermediateDirectories: false)
        await expect(.corruptSelection) { _ = try await environment.store.load(mode: .syntheticPreview) }
        try FileManager.default.removeItem(at: environment.selectionFile)
        XCTAssertEqual(mkfifo(environment.selectionFile.path, mode_t(0o600)), 0)
        await expect(.corruptSelection) { _ = try await environment.store.load(mode: .syntheticPreview) }
        try FileManager.default.removeItem(at: environment.selectionFile)
        let target = environment.directory.appendingPathComponent("oversized")
        try Data(repeating: 0x20, count: 16 * 1_024 + 1).write(to: target)
        try FileManager.default.createSymbolicLink(at: environment.selectionFile, withDestinationURL: target)
        await expect(.oversizedSelection) { _ = try await environment.store.load(mode: .syntheticPreview) }
        XCTAssertEqual(try Data(contentsOf: target).count, 16 * 1_024 + 1)
    }

    func testAlreadyCancelledActivationDoesNotCreateState() async throws {
        let environment = try makeEnvironment(), request = placeholder()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await environment.store.activate(request, mode: .syntheticPreview)
        }
        do { _ = try await task.value; XCTFail("Cancelled activation was accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: environment.directory.path), [])
    }

    func testSelectionRequiresExplicitActivationAndPreservesAllOriginalBytesAfterRestart() async throws {
        let environment = try makeEnvironment(), a = try fixture()
        try await prepare(a, in: environment, at: firstDate)
        let before = try resources(environment)
        let missing = try await environment.store.load(mode: .syntheticPreview)
        XCTAssertNil(missing)
        // A finite future selection clock remains metadata, never currentness proof.
        let futureSelectionDate = Date(timeIntervalSince1970: 4_102_444_800)
        let activated = try await environment.store.activate(a.selection, mode: .syntheticPreview, now: futureSelectionDate)
        XCTAssertEqual(activated.catalog.artifacts, a.artifacts)
        XCTAssertEqual(activated.ruleset.bytes, a.rules)
        XCTAssertEqual(activated.catalog.cachedAt, firstDate)
        XCTAssertEqual(activated.ruleset.cachedAt, firstDate)
        XCTAssertEqual(activated.selectedAt, futureSelectionDate)
        XCTAssertTrue(activated.isSynthetic)
        if case .unknown = activated.currentChecks {} else { XCTFail("Cached bytes claimed current checks") }
        let original = try Data(contentsOf: environment.selectionFile)
        let restarted = try self.makeEnvironment(environment.directory)
        let loaded = try await requireRelease(restarted.store)
        XCTAssertEqual(loaded.catalog.artifacts, a.artifacts)
        XCTAssertEqual(loaded.ruleset.bytes, a.rules)
        XCTAssertEqual(loaded.selectedAt, futureSelectionDate)
        XCTAssertEqual(try resources(environment), before)
        XCTAssertEqual(try Data(contentsOf: environment.selectionFile), original)
    }

    func testLaterPreparationCannotReplaceSelectedTupleAndExactRepeatDoesNotRefreshItsDate() async throws {
        let environment = try makeEnvironment(), a = try fixture(), b = try fixture(2)
        try await prepare(a, in: environment, at: firstDate)
        _ = try await environment.store.activate(a.selection, mode: .syntheticPreview, now: firstDate)
        let original = try Data(contentsOf: environment.selectionFile)
        try await prepare(b, in: environment, at: laterDate)
        let before = try resources(environment)
        let loaded = try await requireRelease(environment.store)
        XCTAssertEqual(loaded.catalog.artifacts, a.artifacts)
        XCTAssertEqual(loaded.ruleset.bytes, a.rules)
        let reordered = OfflineReleaseSelection(catalog: CacheManifest(pins: Array(a.selection.catalog.pins.reversed())),
                                                 ruleset: a.selection.ruleset)
        let repeated = try await environment.store.activate(reordered, mode: .syntheticPreview, now: laterDate)
        XCTAssertEqual(repeated.selectedAt, firstDate)
        XCTAssertEqual(try Data(contentsOf: environment.selectionFile), original)
        XCTAssertEqual(try resources(environment), before)
        let latestPair = try await environment.pairs.load(mode: .syntheticPreview)
        XCTAssertEqual(latestPair?.artifacts, b.artifacts)
        _ = try await environment.store.activate(b.selection, mode: .syntheticPreview, now: laterDate)
        let restarted = try self.makeEnvironment(environment.directory)
        let selectedB = try await requireRelease(restarted.store)
        XCTAssertEqual(selectedB.catalog.artifacts, b.artifacts)
        XCTAssertEqual(selectedB.ruleset.bytes, b.rules)
        XCTAssertEqual(try resources(environment), before)
    }

    func testFailedRulesPreparationAndUncommittedPairCannotReplaceOldSelection() async throws {
        let environment = try makeEnvironment(), a = try fixture(), b = try fixture(2)
        try await prepare(a, in: environment, at: firstDate)
        _ = try await environment.store.activate(a.selection, mode: .syntheticPreview, now: firstDate)
        let original = try Data(contentsOf: environment.selectionFile)
        try await environment.pairs.refresh(b.selection.catalog, mode: .syntheticPreview) { try XCTUnwrap(b.artifacts[$0]) }
        do {
            try await environment.rules.retain(b.selection.ruleset, mode: .syntheticPreview) { throw OfflineFixtureError.interrupted }
            XCTFail("Interrupted preparation succeeded")
        } catch { XCTAssertTrue(error is OfflineFixtureError) }
        let afterPreparation = try resources(environment)
        await expect(.missingRuleset) { _ = try await environment.store.activate(b.selection, mode: .syntheticPreview) }
        let mixed = CacheManifest(pins: [a.selection.catalog.pins[0], b.selection.catalog.pins[1]])
        await expect(.missingCatalogPair) {
            _ = try await environment.store.activate(OfflineReleaseSelection(catalog: mixed, ruleset: a.selection.ruleset), mode: .syntheticPreview)
        }
        XCTAssertEqual(try resources(environment), afterPreparation)
        XCTAssertEqual(try Data(contentsOf: environment.selectionFile), original)
        let restarted = try self.makeEnvironment(environment.directory)
        let selectedA = try await requireRelease(restarted.store)
        XCTAssertEqual(selectedA.catalog.artifacts, a.artifacts)
        XCTAssertEqual(selectedA.ruleset.bytes, a.rules)
        try await environment.rules.retain(b.selection.ruleset, mode: .syntheticPreview) { b.rules }
        _ = try await environment.store.activate(b.selection, mode: .syntheticPreview)
        let selectedB = try await restarted.store.load(mode: .syntheticPreview)
        XCTAssertEqual(selectedB?.catalog.artifacts, b.artifacts)
        XCTAssertEqual(selectedB?.ruleset.bytes, b.rules)
    }

    // The permissive header fixture deliberately exercises a noncanonical ID alias;
    // this is an extra returned-metadata guard, not an admitted canonical ID example.
    func testConflictingPinsAndExactMetadataAliasesCannotReplaceSelection() async throws {
        let environment = try makeEnvironment(), a = try fixture(catalogID: "synthetic.caf\u{e9}")
        try await prepare(a, in: environment, at: firstDate)
        _ = try await environment.store.activate(a.selection, mode: .syntheticPreview)
        let original = try Data(contentsOf: environment.selectionFile), before = try resources(environment)
        let pin = a.selection.catalog.pins[0]
        let changed = ArtifactPin(kind: pin.kind,
            identity: ArtifactIdentity(schemaVersion: pin.identity.schemaVersion, id: "synthetic.cafe\u{301}",
                                       revision: pin.identity.revision, capturedAt: pin.identity.capturedAt), sha256: pin.sha256)
        let alias = OfflineReleaseSelection(catalog: CacheManifest(pins: [changed, a.selection.catalog.pins[1]]), ruleset: a.selection.ruleset)
        await expect(.incompatibleResources) { _ = try await environment.store.activate(alias, mode: .syntheticPreview) }
        let conflicting = RulesetPin(identity: a.selection.ruleset.identity, sha256: String(repeating: "1", count: 64))
        do {
            _ = try await environment.store.activate(OfflineReleaseSelection(catalog: a.selection.catalog, ruleset: conflicting), mode: .syntheticPreview)
            XCTFail("Conflicting observed rules pin accepted")
        } catch { XCTAssertEqual(error as? RulesetCacheError, .immutableVersionConflict) }
        XCTAssertEqual(try resources(environment), before)
        XCTAssertEqual(try Data(contentsOf: environment.selectionFile), original)
    }

    func testMissingAndCorruptRetainedResourcesRemainUnavailableUntilExplicitRestoration() async throws {
        let environment = try makeEnvironment(), a = try fixture()
        try await prepare(a, in: environment, at: firstDate)
        _ = try await environment.store.activate(a.selection, mode: .syntheticPreview)
        let original = try Data(contentsOf: environment.selectionFile), before = try resources(environment)
        try FileManager.default.removeItem(at: environment.rulesFile)
        await expect(.missingRuleset) { _ = try await environment.store.load(mode: .syntheticPreview) }
        XCTAssertEqual(try Data(contentsOf: environment.selectionFile), original)
        try Data("{".utf8).write(to: environment.rulesFile)
        do { _ = try await environment.store.load(mode: .syntheticPreview); XCTFail("Corrupt rules returned") }
        catch { XCTAssertEqual(error as? RulesetCacheError, .corruptCache) }
        try before[1].write(to: environment.rulesFile)
        let restored = try await environment.store.load(mode: .syntheticPreview)
        XCTAssertEqual(restored?.ruleset.bytes, a.rules)
        XCTAssertEqual(try resources(environment), before)
        XCTAssertEqual(try Data(contentsOf: environment.selectionFile), original)
    }

    func testFutureFormatsWrongKindsAndNoncanonicalRevisionStringsArePreserved() async throws {
        let environment = try makeEnvironment(), a = try fixture()
        try await prepare(a, in: environment, at: firstDate)
        _ = try await environment.store.activate(a.selection, mode: .syntheticPreview)
        let original = try Data(contentsOf: environment.selectionFile), before = try resources(environment)
        let mutations: [(inout [String: Any]) throws -> Void] = [
            { $0["storageVersion"] = "2" }, { $0["storageVersion"] = 1 }, { $0["synthetic"] = false },
            { object in var pin = try XCTUnwrap(object["catalog"] as? [String: Any]); pin["kind"] = "pricebook"; object["catalog"] = pin },
            { object in var pin = try XCTUnwrap(object["catalog"] as? [String: Any]); pin["revision"] = "01"; object["catalog"] = pin },
            { object in var pin = try XCTUnwrap(object["catalog"] as? [String: Any]); pin["revision"] = "1.00000000000000000001"; object["catalog"] = pin },
            { object in var pin = try XCTUnwrap(object["catalog"] as? [String: Any]); pin["revision"] = 1; object["catalog"] = pin },
        ]
        for mutation in mutations {
            let invalid = try changed(original, mutation); try invalid.write(to: environment.selectionFile)
            do { _ = try await environment.store.load(mode: .syntheticPreview); XCTFail("Unsupported record loaded") } catch {}
            do { _ = try await environment.store.activate(a.selection, mode: .syntheticPreview); XCTFail("Unsupported record overwritten") } catch {}
            XCTAssertEqual(try Data(contentsOf: environment.selectionFile), invalid)
        }
        try original.write(to: environment.selectionFile)
        let restored = try await environment.store.load(mode: .syntheticPreview)
        XCTAssertEqual(restored?.catalog.artifacts, a.artifacts)
        XCTAssertEqual(try resources(environment), before)
    }

    func testExactEncodedByteLimitRejectsWithoutMutationAndPermitsRecovery() async throws {
        let environment = try makeEnvironment(), a = try fixture()
        try await prepare(a, in: environment, at: firstDate)
        _ = try await environment.store.activate(a.selection, mode: .syntheticPreview, now: firstDate)
        let original = try Data(contentsOf: environment.selectionFile), before = try resources(environment)
        let exact = try OfflineReleaseStore(directory: environment.selectionDirectory, catalogCache: environment.pairs,
                                            rulesetCache: environment.rules, maximumSelectionBytes: original.count)
        let small = try OfflineReleaseStore(directory: environment.selectionDirectory, catalogCache: environment.pairs,
                                            rulesetCache: environment.rules, maximumSelectionBytes: original.count - 1)
        await expect(.oversizedSelection) { _ = try await small.load(mode: .syntheticPreview) }
        await expect(.oversizedSelection) { _ = try await small.activate(a.selection, mode: .syntheticPreview, now: self.firstDate) }
        let recovered = try await exact.activate(a.selection, mode: .syntheticPreview, now: laterDate)
        XCTAssertEqual(recovered.selectedAt, firstDate)
        XCTAssertEqual(try Data(contentsOf: environment.selectionFile), original)
        XCTAssertEqual(try resources(environment), before)
    }

    func testCancellationAtEachCacheReadAndOverlapPreserveSelectionAndPermitRetry() async throws {
        for stage in [OfflineValidationStage.catalog, .ruleset] {
            let gate = OfflineValidationGate(), environment = try makeEnvironment(gate: gate)
            let a = try fixture(), b = try fixture(2)
            try await prepare(a, in: environment, at: firstDate)
            try await prepare(b, in: environment, at: laterDate)
            _ = try await environment.store.activate(a.selection, mode: .syntheticPreview)
            let original = try Data(contentsOf: environment.selectionFile), before = try resources(environment)
            gate.arm(stage)
            let pending = Task { try await environment.store.activate(b.selection, mode: .syntheticPreview) }
            do {
                try await gate.waitForEntry()
                await expect(.activationInProgress) { _ = try await environment.store.activate(a.selection, mode: .syntheticPreview) }
                pending.cancel(); gate.release()
                do { _ = try await pending.value; XCTFail("Cancelled activation committed at \(stage)") }
                catch { XCTAssertTrue(error is CancellationError) }
            } catch { pending.cancel(); gate.release(); _ = await pending.result; throw error }
            XCTAssertEqual(try resources(environment), before)
            XCTAssertEqual(try Data(contentsOf: environment.selectionFile), original)
            let restarted = try makeEnvironment(environment.directory)
            let selectedA = try await requireRelease(restarted.store)
            XCTAssertEqual(selectedA.catalog.artifacts, a.artifacts)
            XCTAssertEqual(selectedA.ruleset.bytes, a.rules)
            _ = try await environment.store.activate(b.selection, mode: .syntheticPreview)
            let selectedB = try await restarted.store.load(mode: .syntheticPreview)
            XCTAssertEqual(selectedB?.catalog.artifacts, b.artifacts)
            XCTAssertEqual(selectedB?.ruleset.bytes, b.rules)
            XCTAssertEqual(try resources(environment), before)
        }
    }

    func testPublicationFailurePreservesRecoveryBytesAndDoesNotWriteEitherCache() async throws {
        let gate = OfflineValidationGate(), environment = try makeEnvironment(gate: gate)
        let a = try fixture(), b = try fixture(2)
        try await prepare(a, in: environment, at: firstDate)
        try await prepare(b, in: environment, at: laterDate)
        _ = try await environment.store.activate(a.selection, mode: .syntheticPreview)
        let original = try Data(contentsOf: environment.selectionFile), before = try resources(environment)
        let backup = environment.directory.appendingPathComponent("selection-backup"), obstruction = Data("blocked".utf8)
        gate.arm()
        let pending = Task { _ = try await environment.store.activate(b.selection, mode: .syntheticPreview) }
        do {
            try await gate.waitForEntry()
            // Controlled external obstruction after the prior selection was read.
            // Its actual file remains intact in backup, as in the existing cache fault tests.
            try FileManager.default.moveItem(at: environment.selectionDirectory, to: backup)
            try obstruction.write(to: environment.selectionDirectory)
            gate.release()
            do { _ = try await pending.value; XCTFail("Obstructed publication succeeded") }
            catch { XCTAssertEqual(error as? OfflineReleaseStoreError, .publicationFailed) }
        } catch { pending.cancel(); gate.release(); _ = await pending.result; throw error }
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent(environment.selectionFile.lastPathComponent)), original)
        XCTAssertEqual(try Data(contentsOf: environment.selectionDirectory), obstruction)
        XCTAssertEqual(try resources(environment), before)
        try FileManager.default.removeItem(at: environment.selectionDirectory)
        try FileManager.default.moveItem(at: backup, to: environment.selectionDirectory)
        _ = try await environment.store.activate(b.selection, mode: .syntheticPreview)
        let selectedB = try await environment.store.load(mode: .syntheticPreview)
        XCTAssertEqual(selectedB?.catalog.artifacts, b.artifacts)
        XCTAssertEqual(try resources(environment), before)
    }
}
