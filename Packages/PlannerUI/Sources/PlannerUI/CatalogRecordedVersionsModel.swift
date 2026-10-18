import Foundation
import SwiftUI
import PlannerCatalog
import PlannerTransfer

/// A local navigation projection from one qualified snapshot. Matching an exact
/// identifier and kind does not infer a variant family, successor or latest item.
struct CatalogRecordedVersionListing: Equatable, Sendable {
    static let maximumVersions = 100
    let anchor: CatalogBrowserRow
    let sha256: String
    let rows: [CatalogBrowserRow]

    static func project(_ snapshot: CatalogSnapshot, anchor: CatalogBrowserRow,
                        sha256: String) throws -> Self {
        guard anchor.snapshot.schemaVersion == "1.0.0",
              snapshot.id == anchor.snapshot.id,
              snapshot.revision == Decimal(anchor.snapshot.revision),
              snapshot.capturedAt == anchor.snapshot.capturedAt else {
            throw CatalogSearchError.snapshotUnavailable
        }
        // A repeated ID/version is ambiguous even if its two declarations use
        // different kinds. Do not hide such a conflict by filtering it away.
        let sameIdentifier = snapshot.items.filter { $0.id == anchor.item.id }
        let identities = sameIdentifier.map { $0.version }
        guard Set(identities).count == identities.count else {
            throw CatalogSearchError.invalidSnapshot
        }
        let matching = sameIdentifier.filter { $0.kind.rawValue == anchor.item.kind }
        guard (1...maximumVersions).contains(matching.count) else {
            throw CatalogSearchError.invalidSnapshot
        }
        let rows = matching.map { item in
            CatalogBrowserRow(item: CatalogSearchEntry(id: item.id, version: item.version,
                kind: item.kind.rawValue, title: item.name), snapshot: anchor.snapshot)
        }.sorted { $0.item.version < $1.item.version }
        let listing = Self(anchor: anchor, sha256: sha256, rows: rows)
        guard listing.isValid(for: anchor, sha256: sha256) else {
            throw CatalogSearchError.snapshotUnavailable
        }
        return listing
    }

    func isValid(for selected: CatalogBrowserRow, sha256 expectedHash: String) -> Bool {
        anchor == selected && sha256 == expectedHash &&
        !selected.item.id.isEmpty && selected.item.id.utf8.count <= 256 &&
        !selected.item.kind.isEmpty && selected.item.kind.utf8.count <= 64 &&
        sha256.range(of: #"\A[a-f0-9]{64}\z"#, options: .regularExpression) != nil &&
        (1...Self.maximumVersions).contains(rows.count) &&
        Set(rows.map(\.id)).count == rows.count &&
        rows.filter({ $0 == selected }).count == 1 &&
        rows.allSatisfy { row in
            row.snapshot == selected.snapshot && row.item.id == selected.item.id &&
            row.item.kind == selected.item.kind && !row.item.version.isEmpty &&
            row.item.version.utf8.count <= 128 && !row.item.title.isEmpty &&
            row.item.title.utf8.count <= 1_024
        }
    }
}

/// Receives an exact, already loaded detail pin before requesting other versions.
/// It cannot change a build, fetch a different release, or dispatch a source URL.
@MainActor
final class CatalogRecordedVersionsModel: ObservableObject {
    let row: CatalogBrowserRow
    @Published private(set) var result: CatalogRecordedVersionListing?
    @Published private(set) var isLoading = false
    @Published private(set) var unavailable = false
    private let source: any CatalogDetailSource
    private var pinnedDetails: CatalogPinnedDetails?
    private var requestID = UUID()
    private var active = true
    private var invalidated = false
    private(set) var pendingRequest: Task<Void, Never>?

    init(row: CatalogBrowserRow, source: any CatalogDetailSource) {
        self.row = row; self.source = source
    }

    var otherVersions: [CatalogBrowserRow] {
        (result?.rows ?? []).filter { $0 != row }.sorted { $0.item.version < $1.item.version }
    }
    var canRetry: Bool { active && !invalidated && unavailable && !isLoading && pinnedDetails != nil }

    func loadIfNeeded(details: CatalogPinnedDetails) {
        guard active, !invalidated else { return }
        if let pinnedDetails {
            // A new detail/hash cannot silently reuse an old version list, even
            // when its displayed ID and version happen to be unchanged.
            if pinnedDetails != details { invalidate() }
            return
        }
        let item = details.details.item
        guard details.snapshot == row.snapshot, item.id == row.item.id,
              item.version == row.item.version, item.kind.rawValue == row.item.kind,
              item.name == row.item.title,
              details.sha256.range(of: #"\A[a-f0-9]{64}\z"#, options: .regularExpression) != nil else {
            invalidate(); return
        }
        pinnedDetails = details
        load()
    }

    func retry() {
        guard canRetry else { return }
        load()
    }

    private func load() {
        guard let pinnedDetails else { return }
        pendingRequest?.cancel()
        let request = UUID(), row = row, source = source
        requestID = request; isLoading = true; unavailable = false
        pendingRequest = Task { [weak self] in
            do {
                let listing = try await source.recordedVersions(for: row, snapshotSHA256: pinnedDetails.sha256)
                guard let self, self.active, !self.invalidated,
                      self.requestID == request, !Task.isCancelled else { return }
                guard listing.isValid(for: row, sha256: pinnedDetails.sha256) else {
                    self.result = nil; self.isLoading = false; self.unavailable = true; return
                }
                self.result = listing; self.isLoading = false
            } catch {
                guard let self, self.active, !self.invalidated,
                      self.requestID == request, !Task.isCancelled else { return }
                self.result = nil; self.isLoading = false; self.unavailable = true
            }
        }
    }

    /// A retained row or a changed title/catalog pin cannot authorize navigation.
    /// The containing browser separately checks that this detail is still shown.
    func selection(for candidate: CatalogBrowserRow) -> CatalogBrowserRow? {
        guard active, !invalidated, !isLoading, !unavailable,
              let result, let pinnedDetails,
              result.isValid(for: row, sha256: pinnedDetails.sha256),
              candidate != row, result.rows.contains(candidate) else { return nil }
        return candidate
    }

    func rejectSelection() { guard active else { return }; invalidate() }

    private func invalidate() {
        invalidated = true; requestID = UUID(); pendingRequest?.cancel()
        result = nil; isLoading = false; unavailable = true
    }

    func close() {
        active = false; requestID = UUID(); pendingRequest?.cancel(); isLoading = false
    }

    func waitForCurrentRequest() async { await pendingRequest?.value }
}
