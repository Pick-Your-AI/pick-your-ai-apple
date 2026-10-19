import Foundation
import XCTest
import PlannerCatalog
import PlannerTransfer
@testable import PlannerUI

private actor SourceReviewCatalogSource: CatalogDetailSource {
    let value: CatalogPinnedDetails
    private(set) var requests: [CatalogBrowserRow] = []
    init(_ value: CatalogPinnedDetails) { self.value = value }
    func details(for row: CatalogBrowserRow) async throws -> CatalogPinnedDetails {
        requests.append(row)
        return value
    }
}

@MainActor
final class CatalogSourceReviewModelTests: XCTestCase {
    private func record(_ uri: String?, date: String = "2026-10-16T09:00:00Z",
                        status: String = "unverified", notes: String = "Synthetic source declaration") -> JSONValue {
        var fields: [String: JSONValue] = [
            "checked_at": .string(date), "verification_status": .string(status), "notes": .string(notes)
        ]
        if let uri { fields["source_uri"] = .string(uri) }
        return .object(fields)
    }

    private func fixture(_ records: [JSONValue], version: String? = nil) async throws
        -> (CatalogBrowserRow, CatalogPinnedDetails, SourceReviewCatalogSource) {
        let bundled = BundledCatalogPreviewSource()
        let page = try await bundled.page(filters: CatalogBrowserFilters(), limit: 100, after: nil)
        let original = try XCTUnwrap(page.entries.first { $0.kind == "model" })
        let originalRow = CatalogBrowserRow(item: original, snapshot: page.identity)
        let resolved = try await bundled.details(for: originalRow)
        guard case .object(var fields) = resolved.details.item.value else {
            throw CatalogSearchError.snapshotUnavailable
        }
        fields["provenance"] = .array(records)
        if let version { fields["version"] = .string(version) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let item = try CatalogItem.decode(encoder.encode(JSONValue.object(fields)))
        let snapshot = version == nil ? page.identity : ArtifactIdentity(
            schemaVersion: page.identity.schemaVersion, id: page.identity.id,
            revision: 2, capturedAt: page.identity.capturedAt)
        let row = CatalogBrowserRow(item: CatalogSearchEntry(
            id: item.id, version: item.version, kind: item.kind.rawValue, title: item.name), snapshot: snapshot)
        // Controlled model specimens preserve the shape of a qualified result.
        // They do not qualify these edited bytes as a production catalog release.
        let result = try CatalogPinnedDetails(details: CatalogItemDetails(item: item), snapshot: snapshot,
            sha256: version == nil ? resolved.sha256 : String(repeating: "b", count: 64))
        return (row, result, SourceReviewCatalogSource(result))
    }

    private func approvedPolicy() throws -> CatalogSourceLinkPolicy {
        try CatalogSourceLinkPolicy(allowedHosts: ["docs.example.com"])
    }

    private func load(_ model: CatalogDetailsModel) async {
        model.loadIfNeeded()
        await model.waitForCurrentRequest()
    }

    func testSourceReviewRequiresLoadedVisibleRecordAndExactConfirmation() async throws {
        let raw = "https://docs.example.com/spec?amount=0#conditions"
        let (row, result, source) = try await fixture([record(raw)])
        let model = CatalogDetailsModel(row: row, source: source, sourceLinkPolicy: try approvedPolicy())
        model.inspectSource(at: 0)
        XCTAssertNil(model.sourceReview)
        await load(model)
        XCTAssertEqual(model.result, result)
        XCTAssertNil(model.sourceReview)
        model.inspectSource(at: 0)
        let review = try XCTUnwrap(model.sourceReview)
        guard case .confirmation(let link) = review.state else { return XCTFail("Explicit confirmation is required") }
        XCTAssertEqual(link.host, "docs.example.com")
        XCTAssertEqual(link.url.absoluteString, raw)
        XCTAssertNil(model.sourceToOpen(reviewID: UUID()))
        XCTAssertEqual(model.sourceReview, review)
        let opening = try XCTUnwrap(model.sourceToOpen(reviewID: review.id))
        XCTAssertEqual(opening.id, review.id)
        XCTAssertEqual(opening.url.absoluteString, raw)
        XCTAssertEqual(model.sourceReview?.state, .opening)
        XCTAssertNil(model.sourceToOpen(reviewID: review.id))
        model.completeSourceOpen(reviewID: review.id, accepted: true)
        XCTAssertEqual(model.sourceReview?.state, .handedOff)
        XCTAssertNil(model.sourceToOpen(reviewID: review.id))
        XCTAssertEqual(model.row, row)
        XCTAssertEqual(model.result, result)
        let requests = await source.requests
        XCTAssertEqual(requests, [row])
    }

    func testDefaultPolicyAndMissingOrUnsafeSourcesNeverOfferAnOpening() async throws {
        let records = [record(nil), record("https://docs.example.com/spec"), record("javascript:alert(1)")]
        let (row, result, source) = try await fixture(records)
        let model = CatalogDetailsModel(row: row, source: source)
        await load(model)
        let expected: [CatalogSourceReviewState] = [
            .missing, .rejected(.disallowedAuthority), .rejected(.disallowedScheme)
        ]
        for index in records.indices {
            model.inspectSource(at: index)
            let review = try XCTUnwrap(model.sourceReview)
            XCTAssertEqual(review.sourceIndex, index)
            XCTAssertEqual(review.state, expected[index])
            XCTAssertNil(model.sourceToOpen(reviewID: review.id))
        }
        XCTAssertEqual(model.result, result)
        XCTAssertEqual(model.result?.details.provenance[2].sourceURI, "javascript:alert(1)")
        XCTAssertEqual(model.row, row)
    }

    func testSourceReviewReplacementAndClosureRetireCapturedActionsAndCallbacks() async throws {
        let (row, result, source) = try await fixture([
            record("https://docs.example.com/first"), record("https://docs.example.com/second")
        ])
        let model = CatalogDetailsModel(row: row, source: source, sourceLinkPolicy: try approvedPolicy())
        await load(model)
        model.inspectSource(at: 0)
        let first = try XCTUnwrap(model.sourceReview)
        _ = try XCTUnwrap(model.sourceToOpen(reviewID: first.id))
        model.inspectSource(at: 1)
        let second = try XCTUnwrap(model.sourceReview)
        XCTAssertNotEqual(first.id, second.id)
        model.completeSourceOpen(reviewID: first.id, accepted: true)
        model.closeSourceReview(id: first.id)
        XCTAssertNil(model.sourceToOpen(reviewID: first.id))
        XCTAssertEqual(model.sourceReview, second)
        // A callback cannot complete a confirmation that has not been consumed.
        model.completeSourceOpen(reviewID: second.id, accepted: true)
        XCTAssertEqual(model.sourceReview, second)
        model.closeSourceReview(id: second.id)
        XCTAssertNil(model.sourceReview)
        XCTAssertNil(model.sourceToOpen(reviewID: second.id))
        model.inspectSource(at: 1)
        XCTAssertNotEqual(model.sourceReview?.id, second.id)
        XCTAssertEqual(model.result, result)
    }

    func testRejectedSystemHandoffRequiresFreshExplicitReviewToRetry() async throws {
        let (row, result, source) = try await fixture([record("https://docs.example.com/spec")])
        let model = CatalogDetailsModel(row: row, source: source, sourceLinkPolicy: try approvedPolicy())
        await load(model)
        model.inspectSource(at: 0)
        let first = try XCTUnwrap(model.sourceReview)
        _ = try XCTUnwrap(model.sourceToOpen(reviewID: first.id))
        model.completeSourceOpen(reviewID: first.id, accepted: false)
        XCTAssertEqual(model.sourceReview?.state, .unavailable)
        XCTAssertNil(model.sourceToOpen(reviewID: first.id))
        model.inspectSource(at: 0)
        let retry = try XCTUnwrap(model.sourceReview)
        XCTAssertNotEqual(retry.id, first.id)
        model.completeSourceOpen(reviewID: first.id, accepted: true)
        XCTAssertEqual(model.sourceReview, retry)
        let secondOpening = try XCTUnwrap(model.sourceToOpen(reviewID: retry.id))
        XCTAssertEqual(secondOpening.url.absoluteString, "https://docs.example.com/spec")
        model.completeSourceOpen(reviewID: retry.id, accepted: true)
        model.completeSourceOpen(reviewID: retry.id, accepted: false)
        XCTAssertEqual(model.sourceReview?.state, .handedOff)
        XCTAssertEqual(model.result, result)
        let requests = await source.requests
        XCTAssertEqual(requests, [row])
    }

    func testClosingDetailsRetiresAllNavigationAndRetainsThePinnedRecord() async throws {
        let (row, result, source) = try await fixture([record("https://docs.example.com/spec")])
        let model = CatalogDetailsModel(row: row, source: source, sourceLinkPolicy: try approvedPolicy())
        await load(model)
        model.inspectSource(at: 0)
        let review = try XCTUnwrap(model.sourceReview)
        _ = try XCTUnwrap(model.sourceToOpen(reviewID: review.id))
        model.close()
        model.completeSourceOpen(reviewID: review.id, accepted: true)
        model.inspectSource(at: 0)
        model.loadMoreSources()
        model.retry()
        model.loadIfNeeded()
        XCTAssertNil(model.sourceReview)
        XCTAssertNil(model.sourceToOpen(reviewID: review.id))
        XCTAssertEqual(model.result, result)
        XCTAssertEqual(model.row, row)
        let requests = await source.requests
        XCTAssertEqual(requests, [row])
    }

    func testSourcePaginationOnlyExposesOrderedRecordsWithoutChangingConsentOrPins() async throws {
        let (row, result, source) = try await fixture((0..<17).map {
            record("https://docs.example.com/source/\($0)", notes: "Ordered record \($0)")
        })
        let model = CatalogDetailsModel(row: row, source: source, sourceLinkPolicy: try approvedPolicy())
        await load(model)
        model.inspectSource(at: 8)
        XCTAssertNil(model.sourceReview)
        model.inspectSource(at: 0)
        let first = try XCTUnwrap(model.sourceReview)
        model.loadMoreSources()
        XCTAssertEqual(model.provenanceLimit, 16)
        XCTAssertEqual(model.sourceReview, first)
        model.inspectSource(at: 15)
        let fifteenth = try XCTUnwrap(model.sourceReview)
        guard case .confirmation(let link) = fifteenth.state else { return XCTFail("Visible source needs confirmation") }
        XCTAssertEqual(link.url.absoluteString, "https://docs.example.com/source/15")
        for invalid in [Int.min, -1, 16, Int.max] { model.inspectSource(at: invalid) }
        XCTAssertEqual(model.sourceReview, fifteenth)
        model.loadMoreSources()
        model.inspectSource(at: 16)
        let final = try XCTUnwrap(model.sourceReview)
        XCTAssertEqual(final.sourceIndex, 16)
        XCTAssertNotEqual(final.id, fifteenth.id)
        XCTAssertEqual(model.provenanceLimit, 17)
        XCTAssertEqual(model.result, result)
        XCTAssertEqual(model.row, row)
    }

    func testStaleContradictoryProvenanceNeverBecomesVerifiedByAnAcceptedHandoff() async throws {
        let records = [
            record("https://docs.example.com/older", date: "2020-01-01T00:00:00Z", status: "verified",
                   notes: "Recorded claim: 24 GB; precision condition absent."),
            record("https://docs.example.com/newer", date: "2026-01-01T00:00:00Z", status: "unverified",
                   notes: "Conflicting recorded claim: 48 GB; condition unknown.")
        ]
        let (row, result, source) = try await fixture(records)
        let model = CatalogDetailsModel(row: row, source: source, sourceLinkPolicy: try approvedPolicy())
        await load(model)
        model.inspectSource(at: 0)
        let review = try XCTUnwrap(model.sourceReview)
        _ = try XCTUnwrap(model.sourceToOpen(reviewID: review.id))
        model.completeSourceOpen(reviewID: review.id, accepted: true)
        XCTAssertEqual(model.sourceReview?.state, .handedOff)
        XCTAssertEqual(model.result, result)
        XCTAssertEqual(model.result?.details.provenance.map(\.checkedAt),
                       ["2020-01-01T00:00:00Z", "2026-01-01T00:00:00Z"])
        XCTAssertEqual(model.result?.details.provenance.map(\.originalVerificationStatus),
                       ["verified", "unverified"])
        XCTAssertEqual(model.result?.details.provenance.map(\.notes), result.details.provenance.map(\.notes))
        XCTAssertEqual(model.row, row)
    }

    func testARecreatedVersionCannotUseThePreviousDetailReviewOrHandoff() async throws {
        let records = [record("https://docs.example.com/spec")]
        let (oldRow, _, oldSource) = try await fixture(records)
        let old = CatalogDetailsModel(row: oldRow, source: oldSource, sourceLinkPolicy: try approvedPolicy())
        await load(old)
        old.inspectSource(at: 0)
        let oldReview = try XCTUnwrap(old.sourceReview)
        _ = try XCTUnwrap(old.sourceToOpen(reviewID: oldReview.id))
        old.close()

        let (row, result, source) = try await fixture(records, version: "2026.10-review-test")
        let current = CatalogDetailsModel(row: row, source: source, sourceLinkPolicy: try approvedPolicy())
        await load(current)
        XCTAssertNotEqual(CatalogDetailsIdentity(row), CatalogDetailsIdentity(oldRow))
        XCTAssertNil(current.sourceToOpen(reviewID: oldReview.id))
        current.inspectSource(at: 0)
        let review = try XCTUnwrap(current.sourceReview)
        old.completeSourceOpen(reviewID: oldReview.id, accepted: true)
        current.completeSourceOpen(reviewID: oldReview.id, accepted: false)
        current.closeSourceReview(id: oldReview.id)
        XCTAssertEqual(current.sourceReview, review)
        XCTAssertEqual(current.result, result)
        XCTAssertEqual(current.row, row)
        XCTAssertNil(old.sourceReview)
    }
}
