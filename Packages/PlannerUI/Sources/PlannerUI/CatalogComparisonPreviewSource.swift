import CryptoKit
import Foundation
import PlannerCatalog
import PlannerTransfer

/// A closed choice of immutable fictional collections. It accepts no arbitrary
/// source, URL, file, credential, build selection or production catalog authority.
public enum CatalogPreviewCollection: Equatable, Sendable {
    case componentKinds, comparisonExamples

    var qualification: String {
        switch self {
        case .componentKinds:
            "Sample data for exploring the planner. These fictional components have no current compatibility assessment or price estimate."
        case .comparisonExamples:
            "Fictional comparison examples: five exact records for exploring units, versions and evidence gaps. These declarations are not measurements, vendor specifications or prices."
        }
    }
}

/// A separate, exact-byte example collection. The original 29-kind preview and
/// its pin remain unchanged. The same validated bytes supply both pages and
/// details, with no inferred family, latest version or cross-record join.
actor CatalogComparisonPreviewSource: CatalogBrowsingSource, CatalogDetailSource {
    static let expectedSHA256 = "7d5e39193254ad2830f74628aec91a8d95bd782329550f0438d717e4e92dd69e"
    static let catalogID = "catalog.comparison.examples.v1"
    static let capturedAt = "2026-10-19T00:00:00Z"
    static let availableKinds = ["compute_profile", "storage"]
    static let expectedMembers = [
        ["cat.comparison.compute", "fixture-v1", "compute_profile", "FICTIONAL Comparison fixture-v1"],
        ["cat.comparison.compute", "fixture-v2", "compute_profile", "FICTIONAL Comparison fixture-v2"],
        ["cat.comparison.storage", "fixture-v3", "storage", "FICTIONAL Comparison fixture-v3"],
        ["cat.comparison.storage", "fixture-v4", "storage", "FICTIONAL Comparison fixture-v4"],
        ["cat.comparison.control", "fixture-v5", "compute_profile", "FICTIONAL Comparison fixture-v5"]
    ]
    private let index = CatalogSearchIndex()
    private var installed = false
    private var decodedSnapshot: CatalogSnapshot?

    static func fixtureData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "catalog-comparison-preview", withExtension: "json"),
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= BuildTransfer.maximumBytes else { throw CatalogSearchError.snapshotUnavailable }
        let data = try Data(contentsOf: url)
        guard data.count <= BuildTransfer.maximumBytes else { throw CatalogSearchError.invalidSnapshot }
        return data
    }

    static func qualify(_ data: Data) throws -> CatalogSnapshot {
        guard data.count <= BuildTransfer.maximumBytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedSHA256 else {
            throw CatalogSearchError.invalidSnapshot
        }
        let snapshot = try CatalogSnapshot.decode(data)
        let members = snapshot.items.map { [$0.id, $0.version, $0.kind.rawValue, $0.name].map { Data($0.utf8) } }
        guard snapshot.id == catalogID, snapshot.revision == 1, snapshot.capturedAt == capturedAt,
              members == expectedMembers.map({ $0.map { Data($0.utf8) } }) else {
            throw CatalogSearchError.invalidSnapshot
        }
        return snapshot
    }

    func page(filters: CatalogBrowserFilters, limit: Int, after: CatalogPageToken?) async throws -> CatalogSearchPage {
        if !installed {
            let snapshot = try qualifiedSnapshot()
            let entries = snapshot.items.map {
                CatalogSearchEntry(id: $0.id, version: $0.version, kind: $0.kind.rawValue, title: $0.name)
            }
            // Concurrent first requests may reenter while installing. Identical
            // immutable bytes use the index's idempotent generation rule.
            try await index.install(identity: Self.identity, entries: entries)
            installed = true
        }
        return try await index.search(query: filters.query, kinds: filters.kinds, limit: limit,
                                      sort: filters.sort.indexSort, after: after)
    }

    func details(for row: CatalogBrowserRow) async throws -> CatalogPinnedDetails {
        let snapshot = try qualifiedSnapshot()
        let rowBytes = [row.item.id, row.item.version, row.item.kind, row.item.title].map { Data($0.utf8) }
        let matches = snapshot.items.filter {
            [$0.id, $0.version, $0.kind.rawValue, $0.name].map { Data($0.utf8) } == rowBytes
        }
        let actualPin = [row.snapshot.schemaVersion, row.snapshot.id, String(row.snapshot.revision), row.snapshot.capturedAt]
        let expectedPin = [Self.identity.schemaVersion, Self.identity.id, String(Self.identity.revision), Self.identity.capturedAt]
        guard actualPin.map({ Data($0.utf8) }) == expectedPin.map({ Data($0.utf8) }),
              matches.count == 1, let item = matches.first else {
            throw CatalogSearchError.snapshotUnavailable
        }
        return try CatalogPinnedDetails(details: CatalogItemDetails(item: item), snapshot: Self.identity, sha256: Self.expectedSHA256)
    }

    static var identity: ArtifactIdentity {
        ArtifactIdentity(schemaVersion: "1.0.0", id: catalogID, revision: 1, capturedAt: capturedAt)
    }
    private func qualifiedSnapshot() throws -> CatalogSnapshot {
        if let decodedSnapshot { return decodedSnapshot }
        let snapshot = try Self.qualify(Self.fixtureData())
        decodedSnapshot = snapshot
        return snapshot
    }
}
