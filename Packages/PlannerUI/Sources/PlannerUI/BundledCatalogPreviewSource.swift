import CryptoKit
import Foundation
import PlannerCatalog
import PlannerTransfer

/// The exact public synthetic fixture, never a production catalog or a source-use
/// approval adapter. There is no production switch or arbitrary input URL here.
public actor BundledCatalogPreviewSource: CatalogBrowsingSource {
    static let expectedSHA256 = "2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8"
    public static let availableKinds = CatalogKind.allCases.map(\.rawValue).sorted()
    private let index = CatalogSearchIndex()
    private var installed = false
    public init() {}

    static func fixtureData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "catalog-preview", withExtension: "json"),
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
            let snapshot = try CatalogSnapshot.decode(Self.fixtureData())
            guard snapshot.id == "catalog.fixture.1", snapshot.revision == 1,
                  snapshot.items.count == CatalogKind.allCases.count,
                  Set(snapshot.items.map(\.kind)) == Set(CatalogKind.allCases) else {
                throw CatalogSearchError.invalidSnapshot
            }
            let identity = ArtifactIdentity(schemaVersion: "1.0.0", id: snapshot.id,
                                            revision: 1, capturedAt: snapshot.capturedAt)
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
}
