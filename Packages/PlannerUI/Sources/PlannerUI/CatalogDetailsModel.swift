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
    // Keep every field boundary and original spelling when SwiftUI keys its
    // StateObject-owning sheet. Canonical String equivalence is not an exact pin.
    let parts: [[UInt8]]
    init(_ row: CatalogBrowserRow) {
        parts = [row.item.id, row.item.version, row.item.kind, row.item.title,
                 row.snapshot.schemaVersion, row.snapshot.id, String(row.snapshot.revision), row.snapshot.capturedAt]
            .map { Array($0.utf8) }
    }
}

@MainActor
final class CatalogDetailsModel: ObservableObject {
    let row: CatalogBrowserRow
    @Published private(set) var result: CatalogPinnedDetails?
    @Published private(set) var isLoading = false
    @Published private(set) var unavailable = false
    @Published private(set) var provenanceLimit = 8
    @Published private(set) var sourceReview: CatalogSourceReview?
    private let source: any CatalogDetailSource
    private let sourceLinkPolicy: CatalogSourceLinkPolicy
    private var active = true
    private var attempted = false
    private var requestID = UUID()
    private(set) var pendingRequest: Task<Void, Never>?

    init(row: CatalogBrowserRow, source: any CatalogDetailSource,
         sourceLinkPolicy: CatalogSourceLinkPolicy = .denyAll) {
        self.row = row; self.source = source; self.sourceLinkPolicy = sourceLinkPolicy
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

    func inspectSource(at index: Int) {
        guard active, let result, index >= 0,
              index < min(provenanceLimit, result.details.provenance.count) else { return }
        let state: CatalogSourceReviewState
        if let raw = result.details.provenance[index].sourceURI {
            switch sourceLinkPolicy.inspect(raw) {
            case .candidate(let link): state = .confirmation(link)
            case .rejected(let reason): state = .rejected(reason)
            }
        } else { state = .missing }
        sourceReview = CatalogSourceReview(id: UUID(), sourceIndex: index, state: state)
    }

    func closeSourceReview(id: UUID) {
        guard active, sourceReview?.id == id else { return }
        sourceReview = nil
    }

    /// Consume one active confirmation. The same recorded URI is checked again
    /// before handing a URL to the view; retained buttons cannot dispatch twice.
    func sourceToOpen(reviewID: UUID) -> CatalogSourceOpening? {
        guard active, let review = sourceReview, review.id == reviewID,
              case .confirmation(let shown) = review.state, let result,
              result.details.provenance.indices.contains(review.sourceIndex),
              let raw = result.details.provenance[review.sourceIndex].sourceURI else { return nil }
        guard case .candidate(let current) = sourceLinkPolicy.inspect(raw), current == shown else { return nil }
        sourceReview = CatalogSourceReview(id: review.id, sourceIndex: review.sourceIndex, state: .opening)
        return CatalogSourceOpening(id: review.id, url: current.url)
    }

    /// System acceptance is a handoff receipt, not evidence that content loaded,
    /// remained on the original host or supports any catalog claim.
    func completeSourceOpen(reviewID: UUID, accepted: Bool) {
        guard active, let review = sourceReview, review.id == reviewID, review.state == .opening else { return }
        sourceReview = CatalogSourceReview(id: review.id, sourceIndex: review.sourceIndex,
                                           state: accepted ? .handedOff : .unavailable)
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
                let resolvedEntry = CatalogSearchEntry(id: item.id, version: item.version,
                    kind: item.kind.rawValue, title: item.name)
                guard result.snapshot == row.snapshot,
                      resolvedEntry == row.item,
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
        active = false; requestID = UUID(); pendingRequest?.cancel(); isLoading = false; sourceReview = nil
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
