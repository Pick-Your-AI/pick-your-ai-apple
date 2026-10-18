import Foundation
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

private struct CacheEnvelope: Codable {
    let manifest: CacheManifest
    let artifacts: [String: Data]
    let cachedAt: Date
    let synthetic: Bool
    let knownPins: [ArtifactPin]
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
    private let validateContract: Validator
    private var refreshing = false

    public init(directory: URL, maximumArtifactBytes: Int = 8 * 1_024 * 1_024,
                validateContract: @escaping Validator) throws {
        guard directory.isFileURL, maximumArtifactBytes > 0,
              maximumArtifactBytes <= 64 * 1_024 * 1_024 else {
            throw CatalogCacheError.invalidManifest
        }
        self.directory = directory
        self.maximumArtifactBytes = maximumArtifactBytes
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
        var known = try load(mode: mode)?.knownPins ?? []
        for pin in manifest.pins {
            if let previous = known.first(where: { VersionKey($0) == VersionKey(pin) }) {
                guard previous == pin else { throw CatalogCacheError.immutableVersionConflict }
            } else { known.append(pin) }
        }
        guard known.count <= 2_048 else { throw CatalogCacheError.historyLimitReached }
        var artifacts: [CatalogArtifact: Data] = [:]
        for pin in manifest.pins {
            try Task.checkCancellation()
            let bytes = try await download(pin.kind)
            try Task.checkCancellation()
            try validate(bytes, pin: pin)
            artifacts[pin.kind] = bytes
        }
        try Task.checkCancellation()
        let envelope = CacheEnvelope(manifest: manifest,
                                     artifacts: Dictionary(uniqueKeysWithValues: artifacts.map { ($0.key.rawValue, $0.value) }),
                                     cachedAt: now, synthetic: true, knownPins: known)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let bytes = try encoder.encode(envelope)
        guard bytes.count <= maximumEnvelopeBytes else { throw CatalogCacheError.oversizedRelease }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Task.checkCancellation()
        // Foundation writes an auxiliary file and renames it at the commit boundary.
        // A single file prevents independently activated catalog/pricebook revisions.
        #if os(iOS)
        try bytes.write(to: activeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try bytes.write(to: activeURL, options: .atomic)
        #endif
    }

    /// Revalidates all bytes and identities on every load. A corrupt active envelope
    /// is unavailable (never a partial release); no deletion or automatic promotion occurs.
    public func load(mode: CatalogDataMode) throws -> CachedCatalog? {
        try requirePreview(mode)
        guard FileManager.default.fileExists(atPath: activeURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: activeURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.intValue <= maximumEnvelopeBytes else {
            throw CatalogCacheError.oversizedRelease
        }
        let envelope: CacheEnvelope
        do { envelope = try JSONDecoder().decode(CacheEnvelope.self, from: Data(contentsOf: activeURL)) }
        catch { throw CatalogCacheError.corruptCache }
        guard envelope.synthetic else { throw CatalogCacheError.productionReceiptUnavailable }
        try validateManifest(envelope.manifest)
        guard envelope.knownPins.count <= 2_048,
              Set(envelope.knownPins.map(VersionKey.init)).count == envelope.knownPins.count else {
            throw CatalogCacheError.corruptCache
        }
        for pin in envelope.knownPins { try validatePin(pin) }
        guard envelope.manifest.pins.allSatisfy({ envelope.knownPins.contains($0) }) else {
            throw CatalogCacheError.corruptCache
        }
        guard Set(envelope.artifacts.keys) == Set(CatalogArtifact.allCases.map(\.rawValue)) else {
            throw CatalogCacheError.incompleteRelease
        }
        var artifacts: [CatalogArtifact: Data] = [:]
        for pin in envelope.manifest.pins {
            guard let bytes = envelope.artifacts[pin.kind.rawValue] else { throw CatalogCacheError.incompleteRelease }
            try validate(bytes, pin: pin)
            artifacts[pin.kind] = bytes
        }
        return CachedCatalog(manifest: envelope.manifest, artifacts: artifacts,
                             cachedAt: envelope.cachedAt, isSynthetic: true, knownPins: envelope.knownPins)
    }

    private var maximumEnvelopeBytes: Int { maximumArtifactBytes * 3 + 2_097_152 }

    private var activeURL: URL { directory.appendingPathComponent("active-preview-v1.json") }

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
