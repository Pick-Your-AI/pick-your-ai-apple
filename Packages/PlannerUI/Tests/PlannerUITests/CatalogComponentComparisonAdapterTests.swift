import Foundation
import XCTest
import PlannerCatalog
import PlannerTransfer
@testable import PlannerUI

@MainActor
final class CatalogComponentComparisonAdapterTests: XCTestCase {
    func testQualifiedBundledDetailAddsExactRecordWithoutChangingFiltersRowsOrSourceReview() async throws {
        let source = BundledCatalogPreviewSource()
        let browser = CatalogBrowserModel(source: source, availableKinds: BundledCatalogPreviewSource.availableKinds)
        browser.setQuery("compute")
        browser.setKind("compute_profile", included: true)
        browser.setSort(.kind)
        await browser.waitForCurrentRequest()
        let row = try XCTUnwrap(browser.rows.first)
        let filters = browser.filters, rows = browser.rows, snapshot = browser.snapshot
        let detail = CatalogDetailsModel(row: row, source: source)
        detail.loadIfNeeded(); await detail.waitForCurrentRequest()
        let original = try XCTUnwrap(detail.result)
        detail.inspectSource(at: 0)
        let review = try XCTUnwrap(detail.sourceReview)
        let comparison = ComponentComparisonModel()
        XCTAssertTrue(detail.addToComparison(comparison))
        XCTAssertTrue(detail.addToComparison(comparison))
        let selected = try XCTUnwrap(comparison.selections.first)
        XCTAssertEqual(comparison.selections.count, 1)
        XCTAssertEqual(selected.details, original.details)
        XCTAssertEqual(selected.catalog.identity, row.snapshot)
        XCTAssertEqual(selected.catalog.sha256, BundledCatalogPreviewSource.expectedSHA256)
        XCTAssertEqual(selected.encodedItem, try original.details.item.encoded())
        XCTAssertEqual(browser.filters, filters); XCTAssertEqual(browser.rows, rows); XCTAssertEqual(browser.snapshot, snapshot)
        XCTAssertEqual(detail.row, row); XCTAssertEqual(detail.result, original); XCTAssertEqual(detail.sourceReview, review)
        detail.close()
        XCTAssertEqual(comparison.selections, [selected])
        XCTAssertEqual(browser.filters, filters); XCTAssertEqual(browser.rows, rows)
    }

    func testUnavailableDetailRetryAddsOnlyItsRecoveredPinAndClosedActionsRemainRetired() async throws {
        let held = try ComponentComparisonFixtures.candidate(id: "cat.held")
        let candidate = try ComponentComparisonFixtures.candidate(id: "cat.recovered")
        let source = ComparisonAdapterSource(candidate: candidate)
        let detail = CatalogDetailsModel(row: Self.row(candidate), source: source)
        let comparison = ComponentComparisonModel(); comparison.add(held)
        detail.loadIfNeeded(); await detail.waitForCurrentRequest()
        XCTAssertTrue(detail.unavailable); XCTAssertNil(detail.result)
        XCTAssertFalse(detail.addToComparison(comparison))
        XCTAssertEqual(comparison.notice, .sourceUnavailable); XCTAssertEqual(comparison.selections, [held])
        await source.configure(fail: false)
        detail.retry(); await detail.waitForCurrentRequest()
        XCTAssertTrue(detail.addToComparison(comparison))
        XCTAssertEqual(comparison.selections, [held, candidate]); XCTAssertNil(comparison.notice)
        detail.close()
        XCTAssertFalse(detail.addToComparison(comparison))
        XCTAssertEqual(comparison.selections, [held, candidate])
    }

    func testDismissedCancellationIgnoringDetailCannotPublishThroughARetainedAddAction() async throws {
        let held = try ComponentComparisonFixtures.candidate(id: "cat.held")
        let candidate = try ComponentComparisonFixtures.candidate(id: "cat.late")
        let source = ComparisonAdapterSource(candidate: candidate)
        await source.configure(fail: false, suspend: true)
        let detail = CatalogDetailsModel(row: Self.row(candidate), source: source)
        let comparison = ComponentComparisonModel(); comparison.add(held)
        detail.loadIfNeeded()
        await source.waitForRequest()
        XCTAssertFalse(detail.addToComparison(comparison))
        detail.close()
        await source.resumeRequest()
        await detail.waitForCurrentRequest()
        XCTAssertNil(detail.result); XCTAssertFalse(detail.isLoading)
        XCTAssertFalse(detail.addToComparison(comparison))
        XCTAssertEqual(comparison.selections, [held]); XCTAssertNil(comparison.inspection)
    }

    func testByteDifferentVersionCannotCrossTheAdapterThroughCanonicalStringEquivalence() async throws {
        let requested = try ComponentComparisonFixtures.candidate(version: "caf\u{e9}")
        let received = try ComponentComparisonFixtures.candidate(version: "cafe\u{301}")
        XCTAssertEqual(requested.details.item.version, received.details.item.version)
        XCTAssertNotEqual(Data(requested.details.item.version.utf8), Data(received.details.item.version.utf8))
        let source = ComparisonAdapterSource(candidate: received)
        await source.configure(fail: false)
        let detail = CatalogDetailsModel(row: Self.row(requested), source: source)
        detail.loadIfNeeded(); await detail.waitForCurrentRequest()
        // The pre-existing display loader compares Swift strings. The new Add
        // boundary must still require the complete displayed UTF-8 identity.
        XCTAssertNotNil(detail.result)
        let comparison = ComponentComparisonModel()
        XCTAssertFalse(detail.addToComparison(comparison))
        XCTAssertTrue(comparison.selections.isEmpty)
        XCTAssertEqual(comparison.notice, .sourceUnavailable)
    }

    private static func row(_ candidate: ComponentComparisonCandidate) -> CatalogBrowserRow {
        let item = candidate.details.item
        return CatalogBrowserRow(item: CatalogSearchEntry(id: item.id, version: item.version, kind: item.kind.rawValue, title: item.name),
                                 snapshot: candidate.catalog.identity)
    }
}

private actor ComparisonAdapterSource: CatalogDetailSource {
    private let value: CatalogPinnedDetails
    private var fail = true
    private var suspend = false
    private var didEnter = false
    private var entered: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<CatalogPinnedDetails, any Error>?

    init(candidate: ComponentComparisonCandidate) {
        value = CatalogPinnedDetails(details: candidate.details, snapshot: candidate.catalog.identity, sha256: candidate.catalog.sha256)
    }
    func configure(fail: Bool, suspend: Bool = false) { self.fail = fail; self.suspend = suspend }
    func details(for row: CatalogBrowserRow) async throws -> CatalogPinnedDetails {
        if fail { throw CatalogSearchError.snapshotUnavailable }
        if !suspend { return value }
        didEnter = true; entered?.resume(); entered = nil
        // Deliberately ignore cancellation; only the real detail model can retire publication.
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func waitForRequest() async {
        if didEnter { return }
        await withCheckedContinuation { entered = $0 }
    }
    func resumeRequest() { waiting?.resume(returning: value); waiting = nil }
}
