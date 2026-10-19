import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum RulesetCacheError: Error, Equatable {
    case invalidConfiguration, invalidPin, incompatibleIdentity, digestMismatch
    case immutableVersionConflict, historyLimitReached, oversizedCache
    case corruptCache, unsupportedStorageVersion, retentionInProgress
    case productionReceiptUnavailable
}

/// Frozen Ruleset metadata, not a catalog integer revision or a promotion receipt.
public struct RulesetIdentity: Codable, Hashable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let version: String
    public let publishedAt: String

    public init(schemaVersion: String, id: String, version: String, publishedAt: String) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.version = version
        self.publishedAt = publishedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", id, version, publishedAt = "published_at"
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.schemaVersion.utf8.elementsEqual(rhs.schemaVersion.utf8)
            && lhs.id.utf8.elementsEqual(rhs.id.utf8)
            && lhs.version.utf8.elementsEqual(rhs.version.utf8)
            && lhs.publishedAt.utf8.elementsEqual(rhs.publishedAt.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Array(schemaVersion.utf8))
        hasher.combine(Array(id.utf8))
        hasher.combine(Array(version.utf8))
        hasher.combine(Array(publishedAt.utf8))
    }
}

public struct RulesetPin: Codable, Hashable, Sendable {
    public let identity: RulesetIdentity
    public let sha256: String

    public init(identity: RulesetIdentity, sha256: String) {
        self.identity = identity
        self.sha256 = sha256
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity && lhs.sha256.utf8.elementsEqual(rhs.sha256.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
        hasher.combine(Array(sha256.utf8))
    }
}

public struct CachedRuleset: Sendable {
    public let pin: RulesetPin
    public let bytes: Data
    public let cachedAt: Date
    public var isSynthetic: Bool { true }
    public var currentChecks: CurrentChecks { .unknown }
    public func age(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(cachedAt)) }
}

private struct RulesetVersionKey: Hashable {
    let schema: [UInt8]
    let id: [UInt8]
    let version: [UInt8]
    init(_ pin: RulesetPin) {
        schema = Array(pin.identity.schemaVersion.utf8)
        id = Array(pin.identity.id.utf8)
        version = Array(pin.identity.version.utf8)
    }
}

private struct RulesetRecord: Codable {
    let pin: RulesetPin
    let bytes: Data
    let cachedAt: Date
    let synthetic: Bool
}

private struct RulesetEnvelope: Codable {
    // A string discriminator cannot round a future fractional JSON number to 1.
    let storageVersion: String
    var records: [RulesetRecord]
}

/// Exact pinned PUBLIC rules bytes for synthetic previews. One actor per
/// app-controlled directory; no cross-process coordination or active release.
/// The required validator must validate these same original bytes against the
/// receiver's frozen Ruleset contract and return their decoded identity.
public actor RulesetCache {
    public typealias Validator = @Sendable (Data) throws -> RulesetIdentity
    public typealias Downloader = @Sendable () async throws -> Data
    private let directory: URL
    private let maximumArtifactBytes: Int
    private let maximumRulesets: Int
    private let maximumCacheBytes: Int
    private let validateContract: Validator
    private var retaining = false

    public init(directory: URL, maximumArtifactBytes: Int = 512 * 1_024,
                maximumRulesets: Int = 32, maximumCacheBytes: Int? = nil,
                validateContract: @escaping Validator) throws {
        let cacheLimit = maximumCacheBytes ?? (maximumArtifactBytes > 0 && maximumArtifactBytes <= 64 * 1_024 * 1_024
            ? maximumArtifactBytes * 4 + 1_048_576 : 0)
        guard directory.isFileURL, (1...(64 * 1_024 * 1_024)).contains(maximumArtifactBytes),
              (1...128).contains(maximumRulesets), (1...(512 * 1_024 * 1_024)).contains(cacheLimit) else {
            throw RulesetCacheError.invalidConfiguration
        }
        self.directory = directory
        self.maximumArtifactBytes = maximumArtifactBytes
        self.maximumRulesets = maximumRulesets
        self.maximumCacheBytes = cacheLimit
        self.validateContract = validateContract
    }

    /// Retains the exact original bytes. A repeat refreshes only that pin's date;
    /// it does not select a latest ruleset or activate a catalog/rules/prices tuple.
    /// Failure/cancellation before the synchronous atomic replacement preserves
    /// the prior file. Cancellation after commit does not undo committed history.
    public func retain(_ pin: RulesetPin, mode: CatalogDataMode, now: Date = Date(),
                       download: Downloader) async throws {
        try requirePreview(mode)
        try validatePin(pin)
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw RulesetCacheError.invalidConfiguration }
        try Task.checkCancellation()
        guard !retaining else { throw RulesetCacheError.retentionInProgress }
        retaining = true
        defer { retaining = false }
        var records = try loadEnvelope()?.records ?? []
        let existing = records.firstIndex { RulesetVersionKey($0.pin) == RulesetVersionKey(pin) }
        if let existing {
            guard records[existing].pin == pin else { throw RulesetCacheError.immutableVersionConflict }
        } else if records.count >= maximumRulesets {
            throw RulesetCacheError.historyLimitReached
        }
        let bytes = try await download()
        try Task.checkCancellation()
        try validate(bytes, pin: pin)
        let record = RulesetRecord(pin: pin, bytes: bytes, cachedAt: now, synthetic: true)
        if let existing { records[existing] = record }
        else { records.append(record) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(RulesetEnvelope(storageVersion: "1", records: records))
        guard encoded.count <= maximumCacheBytes else { throw RulesetCacheError.oversizedCache }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Task.checkCancellation()
        #if os(iOS)
        try encoded.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try encoded.write(to: cacheURL, options: .atomic)
        #endif
    }

    /// Revalidates all retained bytes. A missing exact version remains unavailable;
    /// changed metadata for an observed version is an error, never a fallback.
    public func load(_ pin: RulesetPin, mode: CatalogDataMode) throws -> CachedRuleset? {
        try requirePreview(mode)
        try validatePin(pin)
        guard let envelope = try loadEnvelope() else { return nil }
        guard let record = envelope.records.first(where: { RulesetVersionKey($0.pin) == RulesetVersionKey(pin) }) else {
            return nil
        }
        guard record.pin == pin else { throw RulesetCacheError.immutableVersionConflict }
        return CachedRuleset(pin: record.pin, bytes: record.bytes, cachedAt: record.cachedAt)
    }

    private var cacheURL: URL { directory.appendingPathComponent("rules-preview-v1.json") }

    private func requirePreview(_ mode: CatalogDataMode) throws {
        if case .production = mode { throw RulesetCacheError.productionReceiptUnavailable }
    }

    private func validatePin(_ pin: RulesetPin) throws {
        let identity = pin.identity
        guard identity.schemaVersion.utf8.elementsEqual("1.0.0".utf8),
              !identity.id.isEmpty, identity.id.utf8.count <= 256,
              !identity.version.isEmpty, identity.version.utf8.count <= 256,
              !identity.publishedAt.isEmpty, identity.publishedAt.utf8.count <= 128,
              pin.sha256.utf8.count == 64,
              pin.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw RulesetCacheError.invalidPin
        }
        // These are cache request bounds, not a second frozen-contract validator.
        // Full ID/version/date/schema admission belongs to validateContract below.
    }

    private func validate(_ bytes: Data, pin: RulesetPin) throws {
        guard bytes.count <= maximumArtifactBytes else { throw RulesetCacheError.oversizedCache }
        guard try CatalogCache.sha256(bytes).utf8.elementsEqual(pin.sha256.utf8) else {
            throw RulesetCacheError.digestMismatch
        }
        guard try validateContract(bytes) == pin.identity else { throw RulesetCacheError.incompatibleIdentity }
    }

    private func loadEnvelope() throws -> RulesetEnvelope? {
        guard let bytes = try readBytes() else { return nil }
        let envelope: RulesetEnvelope
        do { envelope = try JSONDecoder().decode(RulesetEnvelope.self, from: bytes) }
        catch { throw RulesetCacheError.corruptCache }
        guard envelope.storageVersion.utf8.elementsEqual("1".utf8) else {
            throw RulesetCacheError.unsupportedStorageVersion
        }
        guard !envelope.records.isEmpty else { throw RulesetCacheError.corruptCache }
        guard envelope.records.count <= maximumRulesets else { throw RulesetCacheError.historyLimitReached }
        var versions = Set<RulesetVersionKey>()
        for record in envelope.records {
            try validatePin(record.pin)
            guard record.synthetic else { throw RulesetCacheError.productionReceiptUnavailable }
            guard record.cachedAt.timeIntervalSinceReferenceDate.isFinite,
                  versions.insert(RulesetVersionKey(record.pin)).inserted else {
                throw RulesetCacheError.corruptCache
            }
            try validate(record.bytes, pin: record.pin)
        }
        return envelope
    }

    private func readBytes() throws -> Data? {
        let opened: (descriptor: Int32, failure: Int32) = cacheURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return (-1, EINVAL) }
            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
            return (descriptor, descriptor < 0 ? errno : 0)
        }
        guard opened.descriptor >= 0 else {
            if opened.failure == ENOENT { return nil }
            throw RulesetCacheError.corruptCache
        }
        let handle = FileHandle(fileDescriptor: opened.descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(opened.descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw RulesetCacheError.corruptCache
        }
        var bytes = Data()
        do {
            while bytes.count <= maximumCacheBytes {
                let remaining = maximumCacheBytes + 1 - bytes.count
                guard let chunk = try handle.read(upToCount: min(65_536, remaining)), !chunk.isEmpty else { break }
                bytes.append(chunk)
            }
        } catch { throw RulesetCacheError.corruptCache }
        guard bytes.count <= maximumCacheBytes else { throw RulesetCacheError.oversizedCache }
        return bytes
    }
}
