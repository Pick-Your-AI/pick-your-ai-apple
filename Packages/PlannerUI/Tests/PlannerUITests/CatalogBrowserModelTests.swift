import Foundation
import XCTest
import PlannerCatalog
import PlannerTransfer
@testable import PlannerUI

private actor ControlledCatalogSource: CatalogBrowsingSource {
    enum Failure: Error { case unavailable }
    let index: CatalogSearchIndex
    private var failNext = false
    private var pauseNext = false
    private var suspended = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0
    init(index: CatalogSearchIndex) { self.index = index }
    func failNextPage() { failNext = true }
    func pauseNextResponse() { pauseNext = true }
    func waitUntilSuspended() async {
        if suspended { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func releaseResponse() {
        releaseWaiter?.resume(); releaseWaiter = nil; suspended = false
    }
    func page(filters: CatalogBrowserFilters, limit: Int, after: CatalogPageToken?) async throws -> CatalogSearchPage {
        callCount += 1
        if failNext { failNext = false; throw Failure.unavailable }
        let result = try await index.search(query: filters.query, kinds: filters.kinds, limit: limit,
                                            sort: filters.sort.indexSort, after: after)
        if pauseNext {
            pauseNext = false; suspended = true
            entryWaiter?.resume(); entryWaiter = nil
            // Deliberately ignore cancellation, as a completed network or cache
            // read may still resume after the user changes their search.
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        return result
    }
}

@MainActor
final class CatalogBrowserModelTests: XCTestCase {
    private func identity(_ revision: Int = 1) -> ArtifactIdentity {
        ArtifactIdentity(schemaVersion: "1.0.0", id: "catalog.synthetic.browser", revision: revision,
                         capturedAt: "2026-10-18T00:00:00Z")
    }
    private func entries() -> [CatalogSearchEntry] {
        [CatalogSearchEntry(id: "cat.alpha", version: "1", kind: "model", title: "Alpha"),
         CatalogSearchEntry(id: "cat.alpha", version: "2", kind: "model", title: "ALPHA"),
         CatalogSearchEntry(id: "cat.cafe", version: "1", kind: "context_policy", title: "Café"),
         CatalogSearchEntry(id: "cat.zeta", version: "1", kind: "accelerator", title: "Zeta")]
    }
    private func fixture(preferences: CatalogFilterPreferences? = nil) async throws -> (CatalogSearchIndex, ControlledCatalogSource, CatalogBrowserModel) {
        let index = CatalogSearchIndex()
        try await index.install(identity: identity(), entries: entries())
        let source = ControlledCatalogSource(index: index)
        let model = CatalogBrowserModel(source: source, availableKinds: ["model", "context_policy", "accelerator"],
                                        preferences: preferences, pageSize: 2)
        return (index, source, model)
    }

    func testBundledPreviewValidatesAllKindsAndRemainsVisiblySynthetic() async throws {
        let data = try BundledCatalogPreviewSource.fixtureData()
        let snapshot = try CatalogSnapshot.decode(data)
        XCTAssertEqual(Set(snapshot.items.map(\.kind)), Set(CatalogKind.allCases))
        let source = BundledCatalogPreviewSource()
        let page = try await source.page(filters: CatalogBrowserFilters(), limit: 100, after: nil)
        XCTAssertEqual(page.identity.id, "catalog.fixture.1")
        XCTAssertEqual(page.identity.revision, 1)
        XCTAssertEqual(page.totalCount, 29)
        XCTAssertNil(page.next)
        XCTAssertTrue(page.entries.allSatisfy { $0.title.hasPrefix("FICTIONAL ") && $0.version == "2026.10-demo" })
        XCTAssertEqual(Set(page.entries.map(\.kind)), Set(BundledCatalogPreviewSource.availableKinds))
    }

    func testConcurrentPreviewLoadsPreserveBothIssuedPageTokens() async throws {
        let source = BundledCatalogPreviewSource()
        async let first = source.page(filters: CatalogBrowserFilters(), limit: 2, after: nil)
        async let other = source.page(filters: CatalogBrowserFilters(), limit: 2, after: nil)
        let (a, b) = try await (first, other)
        let aNext = try await source.page(filters: CatalogBrowserFilters(), limit: 2, after: XCTUnwrap(a.next))
        let bNext = try await source.page(filters: CatalogBrowserFilters(), limit: 2, after: XCTUnwrap(b.next))
        XCTAssertEqual(a.entries, b.entries)
        XCTAssertEqual(aNext.entries, bNext.entries)
        XCTAssertEqual(aNext.identity, a.identity)
    }

    func testCombinedFiltersSortCountsAndDistinctVersionPinsPersistAcrossRecreation() async throws {
        let suite = "CatalogBrowserTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unrelated value", forKey: "otherSetting")
        let preferences = CatalogFilterPreferences(defaults: defaults)
        let (_, source, model) = try await fixture(preferences: preferences)
        model.setKind("model", included: true)
        model.setQuery(" ALPHA ")
        model.setSort(.kind)
        await model.waitForCurrentRequest()
        XCTAssertEqual(model.rows.map { $0.item.version }, ["1", "2"])
        XCTAssertEqual(Set(model.rows.map(\.id)).count, 2)
        XCTAssertEqual(model.totalCount, 2)
        XCTAssertFalse(model.canLoadMore)
        let restored = CatalogBrowserModel(source: source, availableKinds: ["model"],
                                            preferences: CatalogFilterPreferences(defaults: defaults), pageSize: 2)
        XCTAssertEqual(restored.filters, model.filters)
        restored.loadIfNeeded(); await restored.waitForCurrentRequest()
        XCTAssertEqual(restored.rows, model.rows)
        restored.clearFilters(); await restored.waitForCurrentRequest()
        XCTAssertTrue(restored.filters.isDefault)
        XCTAssertEqual(restored.totalCount, 4)
        XCTAssertEqual(restored.rows.count, 2)
        XCTAssertTrue(restored.canLoadMore)
        XCTAssertEqual(defaults.string(forKey: "otherSetting"), "unrelated value")
    }

    func testFailedNextPageRetainsRowsCountFiltersAndCursorUntilRetrySucceeds() async throws {
        let (_, source, model) = try await fixture()
        model.setSort(.kind); await model.waitForCurrentRequest()
        let rows = model.rows, filters = model.filters, pin = model.snapshot
        await source.failNextPage()
        model.loadMore(); await model.waitForCurrentRequest()
        XCTAssertEqual(model.notice, .unavailable)
        XCTAssertEqual(model.rows, rows)
        XCTAssertEqual(model.filters, filters)
        XCTAssertEqual(model.snapshot, pin)
        XCTAssertEqual(model.totalCount, 4)
        XCTAssertFalse(model.canLoadMore)
        XCTAssertTrue(model.canRetry)
        model.retry(); await model.waitForCurrentRequest()
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.rows.count, 4)
        XCTAssertEqual(model.rows.prefix(rows.count), rows[...])
        XCTAssertEqual(Set(model.rows.map(\.id)).count, 4)
        XCTAssertEqual(model.rows.map { $0.item.kind }, ["accelerator", "context_policy", "model", "model"])
        XCTAssertFalse(model.canLoadMore)
    }

    func testLateCancellationIgnoringResponseCannotReplaceNewerFiltersOrRows() async throws {
        let (_, source, model) = try await fixture()
        await source.pauseNextResponse()
        model.reload()
        await source.waitUntilSuspended()
        let older = try XCTUnwrap(model.pendingRequest)
        model.setQuery("Zeta")
        await model.waitForCurrentRequest()
        XCTAssertEqual(model.rows.map { $0.item.id }, ["cat.zeta"])
        await source.releaseResponse()
        await older.value
        XCTAssertEqual(model.filters.query, "Zeta")
        XCTAssertEqual(model.rows.map { $0.item.id }, ["cat.zeta"])
        XCTAssertEqual(model.totalCount, 1)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.notice)
    }

    func testChangedCatalogResetsWholePageCollectionAndRetryKeepsFilters() async throws {
        let (index, _, model) = try await fixture()
        model.setSort(.kind); await model.waitForCurrentRequest()
        let filters = model.filters
        let replacement = CatalogSearchEntry(id: "cat.new", version: "2", kind: "model", title: "New")
        try await index.install(identity: identity(2), entries: [replacement])
        model.loadMore(); await model.waitForCurrentRequest()
        XCTAssertEqual(model.notice, .catalogChanged)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.totalCount, 0)
        XCTAssertEqual(model.filters, filters)
        model.retry(); await model.waitForCurrentRequest()
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.rows.map(\.item), [replacement])
        XCTAssertEqual(model.snapshot, identity(2))
        XCTAssertEqual(model.totalCount, 1)
    }

    func testInvalidStoredAndEditedFiltersNeverReachSourceOrOverwriteLastValidPreferences() async throws {
        let suite = "CatalogBrowserTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(repeating: 0, count: 8_193), forKey: "catalogBrowserFilters.v1")
        let preferences = CatalogFilterPreferences(defaults: defaults)
        let (_, source, model) = try await fixture(preferences: preferences)
        XCTAssertTrue(model.filters.isDefault)
        model.setQuery("Alpha"); await model.waitForCurrentRequest()
        let calls = await source.callCount
        model.setQuery(String(repeating: "x", count: 1_025))
        XCTAssertEqual(model.notice, .invalidFilters)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.canRetry)
        XCTAssertTrue(model.rows.isEmpty)
        let after = await source.callCount
        XCTAssertEqual(after, calls)
        XCTAssertEqual(preferences.read().query, "Alpha")
        model.clearFilters(); await model.waitForCurrentRequest()
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.totalCount, 4)
    }

    func testUnavailableFirstPageAndEmptyResultsAreDifferentStates() async throws {
        let (_, source, model) = try await fixture()
        await source.failNextPage()
        model.loadIfNeeded(); await model.waitForCurrentRequest()
        XCTAssertEqual(model.notice, .unavailable)
        XCTAssertNil(model.snapshot)
        model.retry(); await model.waitForCurrentRequest()
        XCTAssertNotNil(model.snapshot)
        XCTAssertNil(model.notice)
        model.setQuery("No matching synthetic component"); await model.waitForCurrentRequest()
        XCTAssertNotNil(model.snapshot)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.totalCount, 0)
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.canRetry)
    }
}
