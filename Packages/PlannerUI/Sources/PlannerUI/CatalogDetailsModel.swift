import Foundation
import SwiftUI
import PlannerCatalog
import PlannerTransfer

/// The internal preview source has already verified the exact bundled bytes.
/// This result carries that same pin; it confers no production catalog authority.
struct CatalogPinnedDetails: Equatable, Sendable {
    let details: CatalogItemDetails
    let snapshot: ArtifactIdentity
    let sha256: String
}

protocol CatalogDetailSource: Sendable {
    func details(for row: CatalogBrowserRow) async throws -> CatalogPinnedDetails
}

/// A detail sheet must be recreated when any displayed item or catalog pin
/// changes, including a release with the same item ID and version.
struct CatalogDetailsIdentity: Hashable {
    let parts: [String]
    init(_ row: CatalogBrowserRow) {
        parts = [row.item.id, row.item.version, row.item.kind, row.item.title,
                 row.snapshot.schemaVersion, row.snapshot.id, String(row.snapshot.revision), row.snapshot.capturedAt]
    }
}

@MainActor
final class CatalogDetailsModel: ObservableObject {
    let row: CatalogBrowserRow
    @Published private(set) var result: CatalogPinnedDetails?
    @Published private(set) var isLoading = false
    @Published private(set) var unavailable = false
    @Published private(set) var provenanceLimit = 8
    private let source: any CatalogDetailSource
    private var active = true
    private var attempted = false
    private var requestID = UUID()
    private(set) var pendingRequest: Task<Void, Never>?

    init(row: CatalogBrowserRow, source: any CatalogDetailSource) {
        self.row = row; self.source = source
    }

    func loadIfNeeded() {
        guard active, !attempted else { return }
        load()
    }

    func retry() {
        guard active, unavailable, !isLoading else { return }
        load()
    }

    func loadMoreSources() {
        guard active, let result else { return }
        provenanceLimit = min(result.details.provenance.count, provenanceLimit + 8)
    }

    private func load() {
        pendingRequest?.cancel()
        let request = UUID()
        requestID = request; attempted = true; isLoading = true; unavailable = false
        let source = source, row = row
        pendingRequest = Task { [weak self] in
            do {
                let result = try await source.details(for: row)
                guard let self, self.active, self.requestID == request, !Task.isCancelled else { return }
                let item = result.details.item
                guard result.snapshot == row.snapshot,
                      item.id == row.item.id, item.version == row.item.version,
                      item.kind.rawValue == row.item.kind, item.name == row.item.title,
                      result.sha256.range(of: #"\A[a-f0-9]{64}\z"#, options: .regularExpression) != nil else {
                    self.isLoading = false; self.unavailable = true; return
                }
                self.result = result; self.isLoading = false
            } catch {
                guard let self, self.active, self.requestID == request, !Task.isCancelled else { return }
                self.isLoading = false; self.unavailable = true
            }
        }
    }

    func close() {
        active = false; requestID = UUID(); pendingRequest?.cancel(); isLoading = false
    }

    func waitForCurrentRequest() async { await pendingRequest?.value }
}

struct CatalogDetailLiteral: Equatable {
    let text: String
    let truncated: Bool
}

/// Bounded literal display only. URLs remain text, and hidden control/format
/// characters cannot change the direction or structure of a displayed identity.
enum CatalogDetailText {
    static let maximumBytes = 2_048

    static func literal(_ raw: String) -> CatalogDetailLiteral {
        sanitized(raw, escapeBackslash: true)
    }

    private static func sanitized(_ raw: String, escapeBackslash: Bool) -> CatalogDetailLiteral {
        var output = "", bytes = 0
        for scalar in raw.unicodeScalars {
            let category = scalar.properties.generalCategory
            let part: String
            if escapeBackslash && scalar == "\\" {
                part = "\\\\"
            } else if category == .control || category == .format || category == .lineSeparator || category == .paragraphSeparator {
                part = "\\u{" + String(scalar.value, radix: 16) + "}"
            } else { part = String(scalar) }
            let size = part.utf8.count
            guard bytes + size <= maximumBytes else { return CatalogDetailLiteral(text: output, truncated: true) }
            output += part; bytes += size
        }
        return CatalogDetailLiteral(text: output, truncated: false)
    }

    static func value(_ value: JSONValue) -> CatalogDetailLiteral {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return CatalogDetailLiteral(text: "Value unavailable", truncated: false)
        }
        return sanitized(text, escapeBackslash: false)
    }

    static func state(_ state: CatalogDetailValueState) -> String {
        switch state {
        case .missing: "Not recorded"
        case .explicitUnknown: "Explicitly unknown"
        case .emptyText: "Empty text recorded"
        case .emptyCollection: "Empty collection recorded; availability is unknown"
        case .containsUnknown: "Contains unknown or empty entries"
        case .supplied: "Recorded declaration; not independently assessed"
        }
    }
}
