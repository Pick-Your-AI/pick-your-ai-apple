import Foundation
import SwiftUI
import PlannerCatalog

public enum CatalogBrowserSort: String, CaseIterable, Codable, Hashable, Sendable {
    case title, kind
    var indexSort: CatalogSearchSort { self == .title ? .title : .kind }
    public var title: String { self == .title ? "Name" : "Kind" }
}

/// Local search preferences only. No draft, selection, credential or page cursor
/// is stored here; continuation tokens belong to one live index generation.
public struct CatalogBrowserFilters: Codable, Equatable, Sendable {
    public var query: String
    public var kinds: Set<String>
    public var sort: CatalogBrowserSort
    public init(query: String = "", kinds: Set<String> = [], sort: CatalogBrowserSort = .title) {
        self.query = query; self.kinds = kinds; self.sort = sort
    }
    var isValid: Bool {
        query.utf8.count <= 1_024 && kinds.count <= 64 &&
        kinds.allSatisfy { !$0.isEmpty && $0.utf8.count <= 64 }
    }
    public var isDefault: Bool { self == Self() }
}

@MainActor
public final class CatalogFilterPreferences {
    private struct Envelope: Codable { let version: Int; let filters: CatalogBrowserFilters }
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "catalogBrowserFilters.v1") {
        self.defaults = defaults; self.key = key
    }
    func read() -> CatalogBrowserFilters {
        guard let data = defaults.data(forKey: key), data.count <= 8_192,
              let value = try? JSONDecoder().decode(Envelope.self, from: data),
              value.version == 1, value.filters.isValid else { return CatalogBrowserFilters() }
        return value.filters
    }
    func write(_ filters: CatalogBrowserFilters) {
        guard filters.isValid,
              let data = try? JSONEncoder().encode(Envelope(version: 1, filters: filters)),
              data.count <= 8_192 else { return }
        defaults.set(data, forKey: key)
    }
}

/// The source returns display projections after canonical catalog validation.
/// It has no access to the draft editor or its durable storage.
public protocol CatalogBrowsingSource: Sendable {
    func page(filters: CatalogBrowserFilters, limit: Int, after: CatalogPageToken?) async throws -> CatalogSearchPage
}

public actor IndexedCatalogBrowsingSource: CatalogBrowsingSource {
    private let index: CatalogSearchIndex
    public init(index: CatalogSearchIndex) { self.index = index }
    public func page(filters: CatalogBrowserFilters, limit: Int, after: CatalogPageToken?) async throws -> CatalogSearchPage {
        try await index.search(query: filters.query, kinds: filters.kinds, limit: limit,
                               sort: filters.sort.indexSort, after: after)
    }
}

public struct CatalogBrowserRow: Identifiable, Equatable, Sendable {
    public struct ID: Hashable, Sendable {
        public let catalogItemID: String
        public let version: String

        // Catalog pins preserve original bytes; display-string equivalence must
        // not collapse distinct versions in pagination or SwiftUI row identity.
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.catalogItemID.utf8.elementsEqual(rhs.catalogItemID.utf8) &&
            lhs.version.utf8.elementsEqual(rhs.version.utf8)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(Array(catalogItemID.utf8))
            hasher.combine(Array(version.utf8))
        }
    }
    public let item: CatalogSearchEntry
    public let snapshot: ArtifactIdentity
    public var id: ID { ID(catalogItemID: item.id, version: item.version) }
}

public enum CatalogBrowserNotice: Equatable, Sendable {
    case invalidFilters, unavailable, catalogChanged
    public var message: String {
        switch self {
        case .invalidFilters: "The search is too long or a filter is invalid. Shorten it and try again."
        case .unavailable: "Results could not be loaded. Your filters and any already loaded results are preserved. Retry when ready."
        case .catalogChanged: "The catalog changed. Reload results to browse one consistent version; your filters are preserved."
        }
    }
}

/// Keeps asynchronous pages bound to the exact current filter request. Failed
/// next pages retain prior rows; changed releases reset the whole page collection.
@MainActor
public final class CatalogBrowserModel: ObservableObject {
    @Published public private(set) var filters: CatalogBrowserFilters
    @Published public private(set) var rows: [CatalogBrowserRow] = []
    @Published public private(set) var totalCount = 0
    @Published public private(set) var snapshot: ArtifactIdentity?
    @Published public private(set) var isLoading = false
    @Published public private(set) var notice: CatalogBrowserNotice?
    public let availableKinds: [String]
    private let source: any CatalogBrowsingSource
    private let preferences: CatalogFilterPreferences?
    private let pageSize: Int
    private var next: CatalogPageToken?
    private var requestID = UUID()
    private(set) var pendingRequest: Task<Void, Never>?
    private var attemptedInitialLoad = false
    private var retryNextPage = false

    public init(source: any CatalogBrowsingSource, availableKinds: [String],
                preferences: CatalogFilterPreferences? = nil, pageSize: Int = 25) {
        self.source = source; self.preferences = preferences
        self.availableKinds = Array(Set(availableKinds)).sorted()
        self.pageSize = min(100, max(1, pageSize))
        self.filters = preferences?.read() ?? CatalogBrowserFilters()
    }

    public var canLoadMore: Bool { next != nil && !isLoading && notice == nil }
    public var canRetry: Bool { notice != nil && notice != .invalidFilters && !isLoading }
    public var visibleKinds: [String] { Array(Set(availableKinds).union(filters.kinds)).sorted() }

    public func loadIfNeeded() {
        guard !attemptedInitialLoad else { return }
        reload()
    }
    public func setQuery(_ query: String) {
        var value = filters; value.query = query; apply(value)
    }
    public func setKind(_ kind: String, included: Bool) {
        var value = filters
        if included { value.kinds.insert(kind) } else { value.kinds.remove(kind) }
        apply(value)
    }
    public func setSort(_ sort: CatalogBrowserSort) {
        var value = filters; value.sort = sort; apply(value)
    }
    public func clearFilters() { apply(CatalogBrowserFilters()) }

    private func apply(_ value: CatalogBrowserFilters) {
        guard value != filters else { return }
        filters = value
        if value.isValid { preferences?.write(value) }
        reload()
    }

    public func reload() {
        attemptedInitialLoad = true
        pendingRequest?.cancel(); requestID = UUID()
        rows = []; totalCount = 0; snapshot = nil; next = nil
        notice = nil; retryNextPage = false; isLoading = false
        guard filters.isValid else { notice = .invalidFilters; return }
        startPage(after: nil, append: false)
    }

    public func loadMore() {
        guard canLoadMore, let next else { return }
        startPage(after: next, append: true)
    }

    public func retry() {
        guard canRetry else { return }
        if retryNextPage, let next { startPage(after: next, append: true) }
        else { reload() }
    }

    private func startPage(after token: CatalogPageToken?, append: Bool) {
        pendingRequest?.cancel()
        let request = UUID(); requestID = request
        let requestedFilters = filters
        let source = self.source, pageSize = self.pageSize
        isLoading = true; notice = nil; retryNextPage = append
        pendingRequest = Task { [weak self] in
            do {
                let page = try await source.page(filters: requestedFilters, limit: pageSize, after: token)
                guard let self, self.requestID == request else { return }
                if append, self.snapshot != page.identity {
                    self.invalidateChangedCatalog(); return
                }
                let received = page.entries.map { CatalogBrowserRow(item: $0, snapshot: page.identity) }
                let combined = append ? self.rows + received : received
                guard Set(combined.map(\.id)).count == combined.count,
                      combined.count <= page.totalCount, page.totalCount <= 10_000,
                      page.next != nil || combined.count == page.totalCount,
                      !append || page.totalCount == self.totalCount else {
                    self.isLoading = false; self.notice = .unavailable; return
                }
                self.rows = combined; self.totalCount = page.totalCount
                self.snapshot = page.identity; self.next = page.next
                self.isLoading = false; self.notice = nil; self.retryNextPage = false
            } catch {
                guard let self, self.requestID == request else { return }
                if let error = error as? CatalogSearchError, error == .stalePage || error == .mismatchedPage {
                    self.invalidateChangedCatalog()
                } else {
                    self.isLoading = false; self.notice = .unavailable
                }
            }
        }
    }

    private func invalidateChangedCatalog() {
        rows = []; totalCount = 0; snapshot = nil; next = nil
        isLoading = false; retryNextPage = false; notice = .catalogChanged
    }

    // Tests await actual task completion, including a cancellation-ignoring source;
    // no arbitrary sleeps or production timing changes are necessary.
    func waitForCurrentRequest() async { await pendingRequest?.value }
}
