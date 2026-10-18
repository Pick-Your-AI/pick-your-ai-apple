import XCTest
@testable import PlannerCatalog

final class CatalogSearchIndexTests: XCTestCase {
    private func identity(_ revision: Int = 1) -> ArtifactIdentity {
        ArtifactIdentity(schemaVersion: "1.0.0", id: "synthetic.catalog", revision: revision, capturedAt: "2026-10-18T00:00:00Z")
    }
    private func entry(_ id: String, _ title: String, kind: String = "model") -> CatalogSearchEntry {
        CatalogSearchEntry(id: id, version: "1", kind: kind, title: title)
    }
    func testStableSortAndNoDuplicatesAcrossPages() async throws {
        let index = CatalogSearchIndex()
        try await index.install(identity: identity(), entries: [entry("c", "Zeta"), entry("b", "Alpha"), entry("a", "Alpha")])
        let first = try await index.search(limit: 2)
        XCTAssertEqual(first.entries.map(\.id), ["a", "b"])
        XCTAssertEqual(first.totalCount, 3)
        let second = try await index.search(limit: 2, after: XCTUnwrap(first.next))
        XCTAssertEqual(second.entries.map(\.id), ["c"])
        XCTAssertNil(second.next)
        XCTAssertEqual(first.identity, second.identity)
    }
    func testDistinctVersionsRemainSeparateAndCompositeDuplicatesReject() async throws {
        let index = CatalogSearchIndex()
        let first = CatalogSearchEntry(id: "a", version: "1", kind: "model", title: "Alpha")
        let second = CatalogSearchEntry(id: "a", version: "2", kind: "model", title: "Alpha")
        try await index.install(identity: identity(), entries: [second, first])
        let page = try await index.search(limit: 1)
        XCTAssertEqual(page.entries.map(\.version), ["1"])
        let next = try await index.search(limit: 1, after: XCTUnwrap(page.next))
        XCTAssertEqual(next.entries.map(\.version), ["2"])
        try await index.install(identity: identity(), entries: [first, second])
        let conflict = CatalogSearchEntry(id: "a", version: "1", kind: "accelerator", title: "Other kind")
        do { try await index.install(identity: identity(2), entries: [first, conflict]); XCTFail("Duplicate id/version accepted") }
        catch { XCTAssertEqual(error as? CatalogSearchError, .invalidSnapshot) }
    }
    func testRefreshBetweenPagesRejectsOldCursorAndRestartsCleanly() async throws {
        let index = CatalogSearchIndex()
        try await index.install(identity: identity(), entries: [entry("a", "Alpha"), entry("b", "Beta")])
        let old = try await index.search(limit: 1)
        try await index.install(identity: identity(2), entries: [entry("c", "Current")])
        do { _ = try await index.search(limit: 1, after: XCTUnwrap(old.next)); XCTFail("Mixed releases") }
        catch { XCTAssertEqual(error as? CatalogSearchError, .stalePage) }
        let current = try await index.search(limit: 1)
        XCTAssertEqual(current.identity.revision, 2)
        XCTAssertEqual(current.entries.map(\.id), ["c"])
        XCTAssertNil(current.next)
    }
    func testQueryFilterAndPageSizeCannotChangeMidPagination() async throws {
        let index = CatalogSearchIndex()
        try await index.install(identity: identity(), entries: [entry("a", "Alpha"), entry("b", "Beta")])
        let first = try await index.search(limit: 1)
        for (query, kinds, limit) in [("Alpha", Set<String>(), 1), ("", Set(["model"]), 1), ("", Set<String>(), 2)] {
            do { _ = try await index.search(query: query, kinds: kinds, limit: limit, after: XCTUnwrap(first.next)); XCTFail("Query changed") }
            catch { XCTAssertEqual(error as? CatalogSearchError, .mismatchedPage) }
        }
    }
    func testNormalizedSearchAndExactKindFilter() async throws {
        let index = CatalogSearchIndex()
        try await index.install(identity: identity(), entries: [entry("a", "Café Model"), entry("b", "Cafe Device", kind: "device")])
        let page = try await index.search(query: "  CAFE  ", kinds: ["model"])
        XCTAssertEqual(page.entries.map(\.id), ["a"])
        let empty = try await index.search(query: "missing")
        XCTAssertEqual(empty.totalCount, 0)
        XCTAssertTrue(empty.entries.isEmpty)
    }
    func testRejectedRefreshRetainsPriorReleaseAndIdenticalInstallPreservesCursor() async throws {
        let index = CatalogSearchIndex()
        let values = [entry("a", "Alpha"), entry("b", "Beta")]
        try await index.install(identity: identity(), entries: values)
        let first = try await index.search(limit: 1)
        do { try await index.install(identity: identity(), entries: [entry("a", "Changed")]); XCTFail("Immutable identity changed") }
        catch { XCTAssertEqual(error as? CatalogSearchError, .immutableIdentityConflict) }
        try await index.install(identity: identity(), entries: Array(values.reversed()))
        let second = try await index.search(limit: 1, after: XCTUnwrap(first.next))
        XCTAssertEqual(second.entries.map(\.id), ["b"])
    }
    func testMissingSnapshotClearAndForeignCursor() async throws {
        let index = CatalogSearchIndex(), other = CatalogSearchIndex()
        do { _ = try await index.search(); XCTFail("Missing snapshot accepted") }
        catch { XCTAssertEqual(error as? CatalogSearchError, .snapshotUnavailable) }
        let values = [entry("a", "Alpha"), entry("b", "Beta")]
        try await index.install(identity: identity(), entries: values)
        try await other.install(identity: identity(), entries: values)
        let page = try await other.search(limit: 1)
        do { _ = try await index.search(limit: 1, after: XCTUnwrap(page.next)); XCTFail("Foreign cursor accepted") }
        catch { XCTAssertEqual(error as? CatalogSearchError, .stalePage) }
        await index.clear()
        do { _ = try await index.search(); XCTFail("Cleared snapshot accepted") }
        catch { XCTAssertEqual(error as? CatalogSearchError, .snapshotUnavailable) }
    }
    func testSnapshotAndQueryBounds() async throws {
        let index = CatalogSearchIndex()
        for values in [[entry("a", "First"), entry("a", "Duplicate")], [entry("", "Missing id")], [entry("a", String(repeating: "x", count: 1_025))], Array(repeating: entry("a", "Many"), count: 10_001)] {
            do { try await index.install(identity: identity(), entries: values); XCTFail("Invalid snapshot accepted") }
            catch { XCTAssertEqual(error as? CatalogSearchError, .invalidSnapshot) }
        }
        try await index.install(identity: identity(), entries: [])
        for limit in [0, 101] {
            do { _ = try await index.search(limit: limit); XCTFail("Invalid limit accepted") }
            catch { XCTAssertEqual(error as? CatalogSearchError, .invalidQuery) }
        }
        do { _ = try await index.search(query: String(repeating: "x", count: 1_025)); XCTFail("Oversized query accepted") }
        catch { XCTAssertEqual(error as? CatalogSearchError, .invalidQuery) }
    }

    func testKindSortKeepsStableIdentityAndVersionTiesAcrossPages() async throws {
        let index = CatalogSearchIndex()
        let older = CatalogSearchEntry(id: "same", version: "1", kind: "model", title: "Alpha")
        let newer = CatalogSearchEntry(id: "same", version: "2", kind: "model", title: "ALPHA")
        let device = entry("device", "Zeta", kind: "device")
        let other = entry("other", "Alpha")
        let values = [newer, device, older, other]
        try await index.install(identity: identity(), entries: values)

        let defaultPage = try await index.search()
        let titlePage = try await index.search(sort: .title)
        XCTAssertEqual(defaultPage.entries, titlePage.entries)
        XCTAssertEqual(defaultPage.entries, [other, older, newer, device])
        let first = try await index.search(limit: 2, sort: .kind)
        XCTAssertEqual(first.entries, [device, other])
        XCTAssertEqual(first.totalCount, 4)

        // Reordering the same immutable input must not invalidate either order's token.
        try await index.install(identity: identity(), entries: Array(values.reversed()))
        let second = try await index.search(limit: 2, sort: .kind, after: XCTUnwrap(first.next))
        XCTAssertEqual(second.entries, [older, newer])
        XCTAssertEqual(second.identity, first.identity)
        XCTAssertEqual(second.totalCount, first.totalCount)
        XCTAssertNil(second.next)
    }

    func testChangingSortRejectsOldPageAndRestartUsesRequestedOrder() async throws {
        let index = CatalogSearchIndex()
        let model = entry("model", "Alpha")
        let device = entry("device", "Zeta", kind: "device")
        try await index.install(identity: identity(), entries: [model, device])
        let titlePage = try await index.search(limit: 1)
        do {
            _ = try await index.search(limit: 1, sort: .kind, after: XCTUnwrap(titlePage.next))
            XCTFail("Previous order's page was accepted")
        } catch { XCTAssertEqual(error as? CatalogSearchError, .mismatchedPage) }

        let kindPage = try await index.search(limit: 1, sort: .kind)
        XCTAssertEqual(kindPage.entries, [device])
        do {
            _ = try await index.search(limit: 1, after: XCTUnwrap(kindPage.next))
            XCTFail("Omitting the sort accepted a kind-order page")
        } catch { XCTAssertEqual(error as? CatalogSearchError, .mismatchedPage) }
        let continued = try await index.search(limit: 1, sort: .kind, after: XCTUnwrap(kindPage.next))
        XCTAssertEqual(continued.entries, [model])
        XCTAssertNil(continued.next)
    }

    func testKindSortCombinesQueryAndFiltersWithoutInventingMissingRows() async throws {
        let index = CatalogSearchIndex()
        let model = entry("model", "Café Model")
        let device = entry("device", "Cafe Device", kind: "device")
        try await index.install(identity: identity(), entries: [model, entry("other", "Other"), device])
        let first = try await index.search(query: " CAFE ", kinds: ["model", "device"], limit: 1, sort: .kind)
        XCTAssertEqual(first.entries, [device])
        XCTAssertEqual(first.totalCount, 2)
        let second = try await index.search(query: "cafe", kinds: ["device", "model"], limit: 1,
                                            sort: .kind, after: XCTUnwrap(first.next))
        XCTAssertEqual(second.entries, [model])
        XCTAssertEqual(second.totalCount, 2)
        let empty = try await index.search(query: "cafe", kinds: ["unavailable-kind"], sort: .kind)
        XCTAssertTrue(empty.entries.isEmpty)
        XCTAssertEqual(empty.totalCount, 0)
        XCTAssertNil(empty.next)
    }
}
