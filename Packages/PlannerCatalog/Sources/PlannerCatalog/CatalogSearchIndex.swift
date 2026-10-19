import Foundation

/// A display projection supplied only AFTER the receiver validates canonical catalog
/// records. These are local view fields, not a new publisher schema or API protocol.
public struct CatalogSearchEntry: Equatable, Sendable {
    public let id: String
    public let version: String
    public let kind: String
    public let title: String
    public init(id: String, version: String, kind: String, title: String) {
        self.id = id; self.version = version; self.kind = kind; self.title = title
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id.utf8.elementsEqual(rhs.id.utf8) &&
        lhs.version.utf8.elementsEqual(rhs.version.utf8) &&
        lhs.kind.utf8.elementsEqual(rhs.kind.utf8) &&
        lhs.title.utf8.elementsEqual(rhs.title.utf8)
    }
}

public enum CatalogSearchError: Error, Equatable, Sendable {
    case invalidSnapshot, invalidQuery, snapshotUnavailable, stalePage, mismatchedPage
    case immutableIdentityConflict
}

/// Local display order only. Neither case ranks compatibility, evidence, or price.
public enum CatalogSearchSort: Equatable, Sendable {
    case title, kind
}

/// Opaque in-process pagination state. It is neither persisted nor accepted from a
/// remote service; only the issuing index can create valid tokens.
public struct CatalogPageToken: Sendable {
    fileprivate let generation: UUID
    fileprivate let offset: Int
    fileprivate let query: String
    fileprivate let kinds: Set<String>
    fileprivate let limit: Int
    fileprivate let sort: CatalogSearchSort
}

public struct CatalogSearchPage: Sendable {
    public let identity: ArtifactIdentity
    public let entries: [CatalogSearchEntry]
    public let totalCount: Int
    public let next: CatalogPageToken?
}

/// One bounded, immutable snapshot is searched at a time. Refresh invalidates old
/// tokens instead of appending results from different releases. This actor has no
/// network, cache promotion, persistence, evidence grading, or compatibility logic.
public actor CatalogSearchIndex {
    private struct EntryKey: Hashable {
        let id: [UInt8]
        let version: [UInt8]
        init(_ entry: CatalogSearchEntry) {
            id = Array(entry.id.utf8); version = Array(entry.version.utf8)
        }
    }
    private struct IndexedEntry: Sendable {
        let entry: CatalogSearchEntry
        let search: String
        let title: String
    }
    private var identity: ArtifactIdentity?
    private var entries: [IndexedEntry] = []
    private var generation = UUID()
    public init() {}

    public func install(identity: ArtifactIdentity, entries: [CatalogSearchEntry]) throws {
        guard identity.schemaVersion == "1.0.0", identity.revision >= 1,
              !identity.id.isEmpty, identity.id.utf8.count <= 256,
              !identity.capturedAt.isEmpty, identity.capturedAt.utf8.count <= 128,
              entries.count <= 10_000,
              entries.allSatisfy({ entry in
                  !entry.id.isEmpty && entry.id.utf8.count <= 256 &&
                  !entry.version.isEmpty && entry.version.utf8.count <= 128 &&
                  !entry.kind.isEmpty && entry.kind.utf8.count <= 64 &&
                  !entry.title.isEmpty && entry.title.utf8.count <= 1_024
              }), Set(entries.map(EntryKey.init)).count == entries.count else {
            throw CatalogSearchError.invalidSnapshot
        }
        let indexed = entries.map { entry in
            IndexedEntry(entry: entry, search: Self.normalize(entry.title + " " + entry.id + " " + entry.kind),
                         title: Self.normalize(entry.title))
        }.sorted { a, b in
            if a.title != b.title { return a.title < b.title }
            if a.entry.kind != b.entry.kind { return a.entry.kind < b.entry.kind }
            return Self.identityOrderedBefore(a.entry, b.entry)
        }
        if let current = self.identity, current.id == identity.id, current.revision == identity.revision {
            guard current == identity, self.entries.map(\.entry) == indexed.map(\.entry) else {
                throw CatalogSearchError.immutableIdentityConflict
            }
            return // Idempotent receipt of the same release preserves valid cursors.
        }
        self.identity = identity
        self.entries = indexed
        generation = UUID()
    }

    public func clear() {
        identity = nil; entries = []; generation = UUID()
    }

    public func search(query: String = "", kinds: Set<String> = [], limit: Int = 50,
                       sort: CatalogSearchSort = .title,
                       after token: CatalogPageToken? = nil) throws -> CatalogSearchPage {
        guard query.utf8.count <= 1_024, (1...100).contains(limit), kinds.count <= 64,
              kinds.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 64 }) else {
            throw CatalogSearchError.invalidQuery
        }
        guard let identity else { throw CatalogSearchError.snapshotUnavailable }
        let query = Self.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if let token {
            guard token.generation == generation else { throw CatalogSearchError.stalePage }
            guard token.query == query, token.kinds == kinds, token.limit == limit, token.sort == sort else {
                throw CatalogSearchError.mismatchedPage
            }
        }
        let filtered = entries.filter { item in
            (kinds.isEmpty || kinds.contains(item.entry.kind)) && (query.isEmpty || item.search.contains(query))
        }
        let matching: [IndexedEntry]
        switch sort {
        case .title:
            matching = filtered // Retain the original folded-title/kind/ID/version order.
        case .kind:
            matching = filtered.sorted { a, b in
                if a.entry.kind != b.entry.kind { return a.entry.kind < b.entry.kind }
                if a.title != b.title { return a.title < b.title }
                return Self.identityOrderedBefore(a.entry, b.entry)
            }
        }
        let start = token?.offset ?? 0
        let end = min(start + limit, matching.count)
        let next = end < matching.count ? CatalogPageToken(generation: generation, offset: end,
            query: query, kinds: kinds, limit: limit, sort: sort) : nil
        return CatalogSearchPage(identity: identity, entries: matching[start..<end].map(\.entry),
                                 totalCount: matching.count, next: next)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func identityOrderedBefore(_ lhs: CatalogSearchEntry, _ rhs: CatalogSearchEntry) -> Bool {
        // Keep the existing display comparison. Canonically equivalent strings
        // still need an exact-byte tie-breaker so distinct pins have stable pages.
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        if !lhs.id.utf8.elementsEqual(rhs.id.utf8) {
            return lhs.id.utf8.lexicographicallyPrecedes(rhs.id.utf8)
        }
        if lhs.version != rhs.version { return lhs.version < rhs.version }
        return lhs.version.utf8.lexicographicallyPrecedes(rhs.version.utf8)
    }
}
