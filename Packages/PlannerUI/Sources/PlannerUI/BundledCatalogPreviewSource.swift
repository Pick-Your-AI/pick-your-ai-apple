import CryptoKit
import Foundation
import PlannerCatalog
import PlannerTransfer

/// The exact public synthetic fixture, never a production catalog or a source-use
/// approval adapter. There is no production switch or arbitrary input URL here.
public actor BundledCatalogPreviewSource: CatalogBrowsingSource, CatalogDetailSource {
    static let expectedSHA256 = "2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8"
    public static let availableKinds = CatalogKind.allCases.map(\.rawValue).sorted()
    private let index = CatalogSearchIndex()
    private var installed = false
    private var decodedSnapshot: CatalogSnapshot?
    public init() {}

    // Keep production resources distinguishable from the test target's Fixtures bundle.
    static var resourceBundle: Bundle { Bundle.module }

    static func fixtureData() throws -> Data {
        guard let url = resourceBundle.url(forResource: "catalog-preview", withExtension: "json"),
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= BuildTransfer.maximumBytes else { throw CatalogSearchError.snapshotUnavailable }
        let data = try Data(contentsOf: url)
        guard data.count <= BuildTransfer.maximumBytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedSHA256 else {
            throw CatalogSearchError.invalidSnapshot
        }
        return data
    }

    public func page(filters: CatalogBrowserFilters, limit: Int, after: CatalogPageToken?) async throws -> CatalogSearchPage {
        if !installed {
            // Decoding and indexing run on this actor, away from the UI actor.
            let snapshot = try qualifiedSnapshot()
            let identity = Self.identity(snapshot)
            let entries = snapshot.items.map {
                CatalogSearchEntry(id: $0.id, version: $0.version, kind: $0.kind.rawValue, title: $0.name)
            }
            // Reentrant concurrent first requests use the same index and identical
            // immutable bytes. An idempotent install preserves their page tokens.
            try await index.install(identity: identity, entries: entries)
            installed = true
        }
        return try await index.search(query: filters.query, kinds: filters.kinds, limit: limit,
                                       sort: filters.sort.indexSort, after: after)
    }

    func details(for row: CatalogBrowserRow) async throws -> CatalogPinnedDetails {
        let snapshot = try qualifiedSnapshot()
        let matches = snapshot.items.filter {
            $0.id.utf8.elementsEqual(row.item.id.utf8) && $0.version.utf8.elementsEqual(row.item.version.utf8)
        }
        guard row.snapshot == Self.identity(snapshot),
              matches.count == 1, let item = matches.first,
              CatalogSearchEntry(id: item.id, version: item.version, kind: item.kind.rawValue, title: item.name) == row.item else {
            throw CatalogSearchError.snapshotUnavailable
        }
        return try CatalogPinnedDetails(details: CatalogItemDetails(item: item),
                                        snapshot: Self.identity(snapshot), sha256: Self.expectedSHA256)
    }

    /// Explicit synthetic choices only. Catalog spec defaults never populate draft input fields.
    func planningInputChoices() throws -> [PlanningCatalogChoice] {
        let snapshot = try qualifiedSnapshot()
        return try snapshot.items.filter { $0.kind == .workload || $0.kind == .deploymentMode }.map {
            try PlanningCatalogChoice(CatalogPinnedDetails(details: CatalogItemDetails(item: $0),
                snapshot: Self.identity(snapshot), sha256: Self.expectedSHA256))
        }
    }

    private func qualifiedSnapshot() throws -> CatalogSnapshot {
        if let decodedSnapshot { return decodedSnapshot }
        let snapshot = try CatalogSnapshot.decode(Self.fixtureData())
        guard snapshot.id == "catalog.fixture.1", snapshot.revision == 1,
              snapshot.items.count == CatalogKind.allCases.count,
              Set(snapshot.items.map(\.kind)) == Set(CatalogKind.allCases) else {
            throw CatalogSearchError.invalidSnapshot
        }
        decodedSnapshot = snapshot
        return snapshot
    }

    private static func identity(_ snapshot: CatalogSnapshot) -> ArtifactIdentity {
        ArtifactIdentity(schemaVersion: "1.0.0", id: snapshot.id, revision: 1, capturedAt: snapshot.capturedAt)
    }
}
