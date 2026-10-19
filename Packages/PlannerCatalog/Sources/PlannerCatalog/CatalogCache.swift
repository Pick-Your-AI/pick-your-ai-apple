import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum CatalogCacheError: Error, Equatable {
    case unsupportedHashPlatform, invalidManifest, incompatibleIdentity, digestMismatch
    case incompleteRelease, oversizedRelease, corruptCache, productionReceiptUnavailable
    case immutableVersionConflict, historyLimitReached
}

public enum CatalogArtifact: String, Codable, CaseIterable, Sendable {
    case catalog, pricebook
}

/// Identifies existing frozen-v1 fields. This is not an extension to the canonical schema.
public struct ArtifactIdentity: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let revision: Int
    public let capturedAt: String

    public init(schemaVersion: String, id: String, revision: Int, capturedAt: String) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.revision = revision
        self.capturedAt = capturedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", id, revision, capturedAt = "captured_at"
    }
}

public struct ArtifactPin: Codable, Equatable, Sendable {
    public let kind: CatalogArtifact
    public let identity: ArtifactIdentity
    public let sha256: String
    public init(kind: CatalogArtifact, identity: ArtifactIdentity, sha256: String) {
        self.kind = kind
        self.identity = identity
        self.sha256 = sha256
    }
}

/// Internal cache format, never a claimed publisher manifest or promotion receipt.
/// Both artifact pins are committed together; IDs/revisions may differ between artifacts.
public struct CacheManifest: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let pins: [ArtifactPin]
    public init(pins: [ArtifactPin]) {
        self.formatVersion = 1
        self.pins = pins
    }
}

public enum CatalogDataMode: Sendable {
    case syntheticPreview
    /// No canonical publication/rights acceptance adapter is available yet.
    /// Fail closed instead of allowing callers to manufacture an approval boolean.
    case production
}

public struct CachedCatalog: Sendable {
    public let manifest: CacheManifest
    public let artifacts: [CatalogArtifact: Data]
    public let cachedAt: Date
    public let isSynthetic: Bool
    fileprivate let knownPins: [ArtifactPin]
    /// Cached content alone never proves that current compatibility/prices are valid.
    public var currentChecks: CurrentChecks { .unknown }
    public func age(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(cachedAt)) }
}

public enum CurrentChecks: Sendable { case unknown }

private struct CacheRecord: Codable {
    let manifest: CacheManifest
    let artifacts: [String: Data]
    let cachedAt: Date
    let synthetic: Bool
}

/// Storage version 2 intentionally omits version 1's required top-level manifest
/// and artifacts. An older reader must reject it instead of discarding history on
/// its next refresh. The public CacheManifest and frozen artifact bytes stay at v1.
private struct CacheEnvelope: Codable {
    let activeManifest: CacheManifest
    let records: [CacheRecord]
    let knownPins: [ArtifactPin]

    init(activeManifest: CacheManifest, records: [CacheRecord], knownPins: [ArtifactPin]) {
        self.activeManifest = activeManifest
        self.records = records
        self.knownPins = knownPins
    }

    private enum CodingKeys: String, CodingKey {
        case storageVersion, activeManifest, records, knownPins
        case manifest, artifacts, cachedAt, synthetic
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        knownPins = try values.decode([ArtifactPin].self, forKey: .knownPins)
        if values.contains(.storageVersion) {
            guard try values.decode(Int.self, forKey: .storageVersion) == 2,
                  ![CodingKeys.manifest, .artifacts, .cachedAt, .synthetic].contains(where: values.contains) else {
                throw CatalogCacheError.corruptCache
            }
            activeManifest = try values.decode(CacheManifest.self, forKey: .activeManifest)
            records = try values.decode([CacheRecord].self, forKey: .records)
        } else {
            guard !values.contains(.activeManifest), !values.contains(.records) else {
                throw CatalogCacheError.corruptCache
            }
            // Legacy files retained identities, but only the active pair's bytes.
            // Loading never rewrites them or fabricates unavailable historical data.
            activeManifest = try values.decode(CacheManifest.self, forKey: .manifest)
            records = [CacheRecord(manifest: activeManifest,
                                   artifacts: try values.decode([String: Data].self, forKey: .artifacts),
                                   cachedAt: try values.decode(Date.self, forKey: .cachedAt),
                                   synthetic: try values.decode(Bool.self, forKey: .synthetic))]
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(2, forKey: .storageVersion)
        try values.encode(activeManifest, forKey: .activeManifest)
        try values.encode(records, forKey: .records)
        try values.encode(knownPins, forKey: .knownPins)
    }
}

private struct VersionKey: Hashable {
    let kind: CatalogArtifact
    let schema: String
    let id: String
    let revision: Int
    init(_ pin: ArtifactPin) {
        kind = pin.kind; schema = pin.identity.schemaVersion
        id = pin.identity.id; revision = pin.identity.revision
    }
}

/// A bounded, single-process cache for PUBLIC artifacts. Keep one actor per cache URL.
/// Never store drafts, account data, tokens, or raw evidence here. Account-private caches
/// require a separately accepted isolation policy. No network requests are made here.
public actor CatalogCache {
    public typealias Validator = @Sendable (CatalogArtifact, Data) throws -> Void
    public typealias Downloader = @Sendable (CatalogArtifact) async throws -> Data
    private let directory: URL
    private let maximumArtifactBytes: Int
    private let maximumCachedPairs: Int
    private let maximumEnvelopeBytes: Int
    private let validateContract: Validator
    private var refreshing = false

    public init(directory: URL, maximumArtifactBytes: Int = 8 * 1_024 * 1_024,
                maximumCachedPairs: Int = 32, maximumCacheBytes: Int? = nil,
                validateContract: @escaping Validator) throws {
        guard directory.isFileURL, maximumArtifactBytes > 0,
              maximumArtifactBytes <= 64 * 1_024 * 1_024,
              (1...128).contains(maximumCachedPairs) else {
            throw CatalogCacheError.invalidManifest
        }
        // The default has room for two maximum-size complete pairs plus metadata.
        // The encoded cap also bounds the single-descriptor reader before decoding.
        let envelopeLimit = maximumCacheBytes ?? (maximumArtifactBytes * 6 + 2_097_152)
        guard envelopeLimit > 0, envelopeLimit <= 512 * 1_024 * 1_024 else {
            throw CatalogCacheError.invalidManifest
        }
        self.directory = directory
        self.maximumArtifactBytes = maximumArtifactBytes
        self.maximumCachedPairs = maximumCachedPairs
        self.maximumEnvelopeBytes = envelopeLimit
        self.validateContract = validateContract
    }

    public static func sha256(_ bytes: Data) throws -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #else
        throw CatalogCacheError.unsupportedHashPlatform
        #endif
    }

    /// Downloads into memory, validates the complete pair, and atomically replaces one
    /// envelope. Cancellation/failure before the commit leaves the last release intact.
    /// The commit is synchronous; cancellation arriving after its boundary does not undo it.
    /// A second concurrent refresh is rejected rather than letting a late older refresh win.
    public func refresh(_ manifest: CacheManifest, mode: CatalogDataMode,
                        now: Date = Date(), download: Downloader) async throws {
        try requirePreview(mode)
        try validateManifest(manifest)
        guard !refreshing else { throw CatalogCacheError.incompleteRelease }
        refreshing = true
        defer { refreshing = false }
        let previous = try loadEnvelope()
        var records = previous?.records ?? []
        var known = previous?.knownPins ?? []
        for pin in manifest.pins {
            if let previous = known.first(where: { VersionKey($0) == VersionKey(pin) }) {
                guard previous == pin else { throw CatalogCacheError.immutableVersionConflict }
            } else { known.append(pin) }
        }
        guard known.count <= 2_048 else { throw CatalogCacheError.historyLimitReached }
        let existing = records.firstIndex { samePair($0.manifest, manifest) }
        guard existing != nil || records.count < maximumCachedPairs else {
            throw CatalogCacheError.historyLimitReached
        }
        var artifacts: [CatalogArtifact: Data] = [:]
        for pin in manifest.pins {
            try Task.checkCancellation()
            let bytes = try await download(pin.kind)
            try Task.checkCancellation()
            try validate(bytes, pin: pin)
            artifacts[pin.kind] = bytes
        }
        try Task.checkCancellation()
        let record = CacheRecord(manifest: manifest,
                                 artifacts: Dictionary(uniqueKeysWithValues: artifacts.map { ($0.key.rawValue, $0.value) }),
                                 cachedAt: now, synthetic: true)
        if let existing { records[existing] = record }
        else { records.append(record) }
        let envelope = CacheEnvelope(activeManifest: manifest, records: records, knownPins: known)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let bytes = try encoder.encode(envelope)
        guard bytes.count <= maximumEnvelopeBytes else { throw CatalogCacheError.oversizedRelease }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Task.checkCancellation()
        // Foundation writes an auxiliary file and renames it at the commit boundary.
        // A single file commits the active pair and retained history together.
        #if os(iOS)
        try bytes.write(to: activeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try bytes.write(to: activeURL, options: .atomic)
        #endif
    }

    /// Revalidates the entire envelope, including retained history, on every load.
    /// Corruption is unavailable and preserved; no deletion or promotion occurs.
    public func load(mode: CatalogDataMode) throws -> CachedCatalog? {
        try requirePreview(mode)
        guard let envelope = try loadEnvelope() else { return nil }
        guard let active = envelope.records.first(where: { samePair($0.manifest, envelope.activeManifest) }) else {
            throw CatalogCacheError.corruptCache
        }
        return try snapshot(active, knownPins: envelope.knownPins)
    }

    /// Reads an exact previously retained pair without changing active selection or
    /// cached dates. A clean miss includes legacy versions whose bytes were never
    /// saved, and combinations of individually known pins that were never a pair.
    /// Conflicting metadata for an observed version is an error, never a clean miss.
    public func load(_ manifest: CacheManifest, mode: CatalogDataMode) throws -> CachedCatalog? {
        try requirePreview(mode)
        try validateManifest(manifest)
        guard let envelope = try loadEnvelope() else { return nil }
        for pin in manifest.pins {
            if let known = envelope.knownPins.first(where: { VersionKey($0) == VersionKey(pin) }), known != pin {
                throw CatalogCacheError.immutableVersionConflict
            }
        }
        guard let record = envelope.records.first(where: { samePair($0.manifest, manifest) }) else { return nil }
        return try snapshot(record, knownPins: envelope.knownPins)
    }

    private func loadEnvelope() throws -> CacheEnvelope? {
        guard let bytes = try loadEnvelopeBytes() else { return nil }
        let envelope: CacheEnvelope
        do { envelope = try JSONDecoder().decode(CacheEnvelope.self, from: bytes) }
        catch { throw CatalogCacheError.corruptCache }
        try validateManifest(envelope.activeManifest)
        guard envelope.knownPins.count <= 2_048,
              Set(envelope.knownPins.map(VersionKey.init)).count == envelope.knownPins.count else {
            throw CatalogCacheError.corruptCache
        }
        for pin in envelope.knownPins { try validatePin(pin) }
        guard !envelope.records.isEmpty else { throw CatalogCacheError.corruptCache }
        guard envelope.records.count <= maximumCachedPairs else { throw CatalogCacheError.historyLimitReached }
        for (index, record) in envelope.records.enumerated() {
            guard record.synthetic else { throw CatalogCacheError.productionReceiptUnavailable }
            try validateManifest(record.manifest)
            guard record.manifest.pins.allSatisfy({ envelope.knownPins.contains($0) }),
                  !envelope.records[..<index].contains(where: { samePair($0.manifest, record.manifest) }) else {
                throw CatalogCacheError.corruptCache
            }
            guard Set(record.artifacts.keys) == Set(CatalogArtifact.allCases.map(\.rawValue)) else {
                throw CatalogCacheError.incompleteRelease
            }
            for pin in record.manifest.pins {
                guard let bytes = record.artifacts[pin.kind.rawValue] else { throw CatalogCacheError.incompleteRelease }
                try validate(bytes, pin: pin)
            }
        }
        guard envelope.records.contains(where: { samePair($0.manifest, envelope.activeManifest) }) else {
            throw CatalogCacheError.corruptCache
        }
        return envelope
    }

    private func samePair(_ lhs: CacheManifest, _ rhs: CacheManifest) -> Bool {
        lhs.pins.count == rhs.pins.count && lhs.pins.allSatisfy { rhs.pins.contains($0) }
    }

    private func snapshot(_ record: CacheRecord, knownPins: [ArtifactPin]) throws -> CachedCatalog {
        var artifacts: [CatalogArtifact: Data] = [:]
        for kind in CatalogArtifact.allCases {
            guard let bytes = record.artifacts[kind.rawValue] else { throw CatalogCacheError.incompleteRelease }
            artifacts[kind] = bytes
        }
        return CachedCatalog(manifest: record.manifest, artifacts: artifacts,
                             cachedAt: record.cachedAt, isSynthetic: true, knownPins: knownPins)
    }

    private var activeURL: URL { directory.appendingPathComponent("active-preview-v1.json") }

    private func loadEnvelopeBytes() throws -> Data? {
        // Foundation can report a directory in the same Cocoa error family as an
        // absent file. Capture the actual open errno instead of inferring absence
        // from a broad Cocoa code or from a second path lookup.
        let opened: (descriptor: Int32, failure: Int32) = activeURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return (-1, EINVAL) }
            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
            return (descriptor, descriptor < 0 ? errno : 0)
        }
        guard opened.descriptor >= 0 else {
            if opened.failure == ENOENT { return nil }
            throw CatalogCacheError.corruptCache
        }
        let handle = FileHandle(fileDescriptor: opened.descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        // Check the opened object, not its path. Nonblocking open lets us reject
        // FIFOs without waiting for a writer; only regular files reach the reader.
        var metadata = stat()
        guard fstat(opened.descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw CatalogCacheError.corruptCache
        }

        // Read from one open file rather than checking path metadata and reopening it.
        // The extra byte distinguishes an exact-limit envelope from an oversized one,
        // including when the file grows or the path refers to a larger symlink target.
        var bytes = Data()
        do {
            while bytes.count <= maximumEnvelopeBytes {
                let remaining = maximumEnvelopeBytes + 1 - bytes.count
                guard let chunk = try handle.read(upToCount: min(65_536, remaining)),
                      !chunk.isEmpty else { break }
                bytes.append(chunk)
            }
        } catch { throw CatalogCacheError.corruptCache }
        guard bytes.count <= maximumEnvelopeBytes else {
            throw CatalogCacheError.oversizedRelease
        }
        return bytes
    }

    private func requirePreview(_ mode: CatalogDataMode) throws {
        if case .production = mode { throw CatalogCacheError.productionReceiptUnavailable }
    }

    private func validateManifest(_ manifest: CacheManifest) throws {
        guard manifest.formatVersion == 1, manifest.pins.count == CatalogArtifact.allCases.count,
              Set(manifest.pins.map(\.kind)) == Set(CatalogArtifact.allCases) else {
            throw CatalogCacheError.invalidManifest
        }
        for pin in manifest.pins { try validatePin(pin) }
    }

    private func validatePin(_ pin: ArtifactPin) throws {
        guard pin.identity.schemaVersion == "1.0.0", pin.identity.revision >= 1,
                  !pin.identity.id.isEmpty, pin.identity.id.utf8.count <= 256,
                  pin.identity.capturedAt.utf8.count <= 128,
                  pin.sha256.utf8.count == 64,
                  pin.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw CatalogCacheError.invalidManifest
        }
    }

    private func validate(_ bytes: Data, pin: ArtifactPin) throws {
        guard bytes.count <= maximumArtifactBytes else { throw CatalogCacheError.oversizedRelease }
        guard try Self.sha256(bytes) == pin.sha256 else { throw CatalogCacheError.digestMismatch }
        let identity: ArtifactIdentity
        do { identity = try JSONDecoder().decode(ArtifactIdentity.self, from: bytes) }
        catch { throw CatalogCacheError.incompatibleIdentity }
        guard identity == pin.identity else { throw CatalogCacheError.incompatibleIdentity }
        // Identity decoding is NOT full JSON Schema validation. The receiver must supply
        // its frozen-contract validator; there is intentionally no permissive default.
        try validateContract(pin.kind, bytes)
    }
}
