import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum OfflineReleaseStoreError: Error, Equatable {
    case invalidConfiguration, invalidSelection, oversizedSelection
    case corruptSelection, unsupportedStorageVersion, productionReceiptUnavailable
    case missingCatalogPair, missingRuleset, incompatibleResources
    case activationInProgress, publicationFailed
}

/// An explicit local selection of already retained PUBLIC artifacts. This is not
/// a publisher release, graph/build compatibility result, or currentness receipt.
public struct OfflineReleaseSelection: Sendable {
    public let catalog: CacheManifest
    public let ruleset: RulesetPin

    public init(catalog: CacheManifest, ruleset: RulesetPin) {
        self.catalog = catalog
        self.ruleset = ruleset
    }
}

public struct CachedOfflineRelease: Sendable {
    public let selection: OfflineReleaseSelection
    public let catalog: CachedCatalog
    public let ruleset: CachedRuleset
    public let selectedAt: Date
    public var isSynthetic: Bool { true }
    public var currentChecks: CurrentChecks { .unknown }
}

// Private storage uses a string for the integer revision too: decoding a JSON
// number through Double must not round a different selection into a known pin.
private struct OfflineArtifactPin: Codable {
    let kind: CatalogArtifact
    let schema: String
    let id: String
    let revision: String
    let capturedAt: String
    let sha256: String

    init(_ pin: ArtifactPin) {
        kind = pin.kind
        schema = pin.identity.schemaVersion
        id = pin.identity.id
        revision = String(pin.identity.revision)
        capturedAt = pin.identity.capturedAt
        sha256 = pin.sha256
    }

    func pin() throws -> ArtifactPin {
        guard revision.utf8.count <= 20, let value = Int(revision), value >= 1,
              String(value).utf8.elementsEqual(revision.utf8) else {
            throw OfflineReleaseStoreError.corruptSelection
        }
        return ArtifactPin(kind: kind,
                           identity: ArtifactIdentity(schemaVersion: schema, id: id,
                                                      revision: value, capturedAt: capturedAt),
                           sha256: sha256)
    }
}

private struct OfflineSelectionRecord: Codable {
    let storageVersion: String
    let catalog: OfflineArtifactPin
    let pricebook: OfflineArtifactPin
    let ruleset: RulesetPin
    let selectedAt: Date
    let synthetic: Bool

    func selection() throws -> OfflineReleaseSelection {
        guard storageVersion.utf8.elementsEqual("1".utf8) else {
            throw OfflineReleaseStoreError.unsupportedStorageVersion
        }
        guard synthetic, selectedAt.timeIntervalSinceReferenceDate.isFinite,
              catalog.kind == .catalog, pricebook.kind == .pricebook else {
            throw OfflineReleaseStoreError.corruptSelection
        }
        return try OfflineReleaseSelection(catalog: CacheManifest(pins: [catalog.pin(), pricebook.pin()]),
                                           ruleset: ruleset)
    }
}

/// Keep one actor per app-controlled selection directory. Activation only reads
/// the supplied cache actors; it never refreshes, retains, evicts or rewrites
/// their data. Callers prepare resources separately, then explicitly select the
/// complete tuple. Missing/corrupt retained resources never fall back to latest.
public actor OfflineReleaseStore {
    private let directory: URL
    private let catalogCache: CatalogCache
    private let rulesetCache: RulesetCache
    private let maximumSelectionBytes: Int
    private var activating = false

    public init(directory: URL, catalogCache: CatalogCache, rulesetCache: RulesetCache,
                maximumSelectionBytes: Int = 16 * 1_024) throws {
        guard directory.isFileURL, (1...(64 * 1_024)).contains(maximumSelectionBytes) else {
            throw OfflineReleaseStoreError.invalidConfiguration
        }
        self.directory = directory
        self.catalogCache = catalogCache
        self.rulesetCache = rulesetCache
        self.maximumSelectionBytes = maximumSelectionBytes
    }

    /// Returns one captured selection, revalidated through both exact-history
    /// readers. Another activation may finish while this read awaits a cache;
    /// the returned tuple still belongs wholly to the initially read selection.
    public func load(mode: CatalogDataMode) async throws -> CachedOfflineRelease? {
        try requirePreview(mode)
        try Task.checkCancellation()
        guard let record = try readRecord() else { return nil }
        return try await resolve(record.selection(), selectedAt: record.selectedAt, mode: mode)
    }

    /// Selects only a complete, validated tuple. Failure/cancellation before the
    /// synchronous atomic replacement preserves the old selection. Cancellation
    /// arriving after that commit does not undo it. Exact repeats keep their
    /// original selection date and bytes; they are not freshness updates.
    @discardableResult
    public func activate(_ selection: OfflineReleaseSelection, mode: CatalogDataMode,
                         now: Date = Date()) async throws -> CachedOfflineRelease {
        try requirePreview(mode)
        try validate(selection)
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            throw OfflineReleaseStoreError.invalidSelection
        }
        try Task.checkCancellation()
        guard !activating else { throw OfflineReleaseStoreError.activationInProgress }
        activating = true
        defer { activating = false }
        // A future/corrupt selection must not be overwritten by a blind retry.
        let previous = try readRecord()
        let oldSelection = try previous?.selection()
        if let oldSelection { try validate(oldSelection) }
        let identical = oldSelection.map { sameSelection($0, selection) } ?? false
        let chosen = identical ? oldSelection! : selection
        let selectedAt = identical ? previous!.selectedAt : now
        let catalog = selection.catalog.pins.first { $0.kind == .catalog }!
        let pricebook = selection.catalog.pins.first { $0.kind == .pricebook }!
        let record = OfflineSelectionRecord(storageVersion: "1", catalog: OfflineArtifactPin(catalog),
                                            pricebook: OfflineArtifactPin(pricebook), ruleset: selection.ruleset,
                                            selectedAt: selectedAt, synthetic: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(record)
        guard encoded.count <= maximumSelectionBytes else { throw OfflineReleaseStoreError.oversizedSelection }
        let result = try await resolve(chosen, selectedAt: selectedAt, mode: mode)
        try Task.checkCancellation()
        if identical { return result }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Task.checkCancellation()
            #if os(iOS)
            try encoded.write(to: selectionURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try encoded.write(to: selectionURL, options: .atomic)
            #endif
        } catch is CancellationError { throw CancellationError() }
        catch { throw OfflineReleaseStoreError.publicationFailed }
        return result
    }

    private var selectionURL: URL { directory.appendingPathComponent("offline-selection-preview-v1.json") }

    private func requirePreview(_ mode: CatalogDataMode) throws {
        if case .production = mode { throw OfflineReleaseStoreError.productionReceiptUnavailable }
    }

    private func validate(_ selection: OfflineReleaseSelection) throws {
        guard selection.catalog.formatVersion == 1, selection.catalog.pins.count == 2,
              Set(selection.catalog.pins.map(\.kind)) == Set(CatalogArtifact.allCases),
              selection.catalog.pins.allSatisfy({ pin in
                  let value = pin.identity
                  return value.schemaVersion.utf8.elementsEqual("1.0.0".utf8) && value.revision >= 1
                      && !value.id.isEmpty && value.id.utf8.count <= 256
                      && !value.capturedAt.isEmpty && value.capturedAt.utf8.count <= 128
                      && validDigest(pin.sha256)
              }) else { throw OfflineReleaseStoreError.invalidSelection }
        let rules = selection.ruleset.identity
        guard rules.schemaVersion.utf8.elementsEqual("1.0.0".utf8),
              !rules.id.isEmpty, rules.id.utf8.count <= 256,
              !rules.version.isEmpty, rules.version.utf8.count <= 256,
              !rules.publishedAt.isEmpty, rules.publishedAt.utf8.count <= 128,
              validDigest(selection.ruleset.sha256) else { throw OfflineReleaseStoreError.invalidSelection }
        // These mirror bounded request admission, not full frozen-schema checks.
        // The existing cache readers revalidate their original retained bytes.
    }

    private func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private func samePin(_ lhs: ArtifactPin, _ rhs: ArtifactPin) -> Bool {
        lhs.kind == rhs.kind && lhs.identity.revision == rhs.identity.revision
            && lhs.identity.schemaVersion.utf8.elementsEqual(rhs.identity.schemaVersion.utf8)
            && lhs.identity.id.utf8.elementsEqual(rhs.identity.id.utf8)
            && lhs.identity.capturedAt.utf8.elementsEqual(rhs.identity.capturedAt.utf8)
            && lhs.sha256.utf8.elementsEqual(rhs.sha256.utf8)
    }

    private func sameSelection(_ lhs: OfflineReleaseSelection, _ rhs: OfflineReleaseSelection) -> Bool {
        lhs.catalog.formatVersion == rhs.catalog.formatVersion
            && lhs.catalog.pins.count == 2 && rhs.catalog.pins.count == 2
            && lhs.catalog.pins.allSatisfy { a in rhs.catalog.pins.contains { samePin(a, $0) } }
            && lhs.ruleset == rhs.ruleset
    }

    private func resolve(_ selection: OfflineReleaseSelection, selectedAt: Date,
                         mode: CatalogDataMode) async throws -> CachedOfflineRelease {
        try validate(selection)
        try Task.checkCancellation()
        guard let catalog = try await catalogCache.load(selection.catalog, mode: mode) else {
            throw OfflineReleaseStoreError.missingCatalogPair
        }
        try Task.checkCancellation()
        guard let rules = try await rulesetCache.load(selection.ruleset, mode: mode) else {
            throw OfflineReleaseStoreError.missingRuleset
        }
        try Task.checkCancellation()
        let loaded = OfflineReleaseSelection(catalog: catalog.manifest, ruleset: rules.pin)
        guard catalog.isSynthetic, catalog.artifacts.count == 2,
              sameSelection(selection, loaded) else { throw OfflineReleaseStoreError.incompatibleResources }
        return CachedOfflineRelease(selection: selection, catalog: catalog, ruleset: rules, selectedAt: selectedAt)
    }

    private func readRecord() throws -> OfflineSelectionRecord? {
        let opened: (descriptor: Int32, failure: Int32) = selectionURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return (-1, EINVAL) }
            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
            return (descriptor, descriptor < 0 ? errno : 0)
        }
        guard opened.descriptor >= 0 else {
            if opened.failure == ENOENT { return nil }
            throw OfflineReleaseStoreError.corruptSelection
        }
        let handle = FileHandle(fileDescriptor: opened.descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(opened.descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw OfflineReleaseStoreError.corruptSelection
        }
        var bytes = Data()
        do {
            while bytes.count <= maximumSelectionBytes {
                let remaining = maximumSelectionBytes + 1 - bytes.count
                guard let chunk = try handle.read(upToCount: min(65_536, remaining)), !chunk.isEmpty else { break }
                bytes.append(chunk)
            }
        } catch { throw OfflineReleaseStoreError.corruptSelection }
        guard bytes.count <= maximumSelectionBytes else { throw OfflineReleaseStoreError.oversizedSelection }
        let record: OfflineSelectionRecord
        do { record = try JSONDecoder().decode(OfflineSelectionRecord.self, from: bytes) }
        catch { throw OfflineReleaseStoreError.corruptSelection }
        try validate(record.selection())
        return record
    }
}
