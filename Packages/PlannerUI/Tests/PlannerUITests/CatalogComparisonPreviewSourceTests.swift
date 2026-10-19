import CryptoKit
import Foundation
import XCTest
import PlannerCatalog
import PlannerTransfer
@testable import PlannerUI

@MainActor
final class CatalogComparisonPreviewSourceTests: XCTestCase {
    func testCanonicalAndComparisonFixturesRetainDistinctExactPinsAndMembers() throws {
        let data = try CatalogComparisonPreviewSource.fixtureData()
        let snapshot = try CatalogComparisonPreviewSource.qualify(data)
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                       "7d5e39193254ad2830f74628aec91a8d95bd782329550f0438d717e4e92dd69e")
        XCTAssertEqual(snapshot.id, "catalog.comparison.examples.v1")
        XCTAssertEqual(snapshot.revision, 1)
        XCTAssertEqual(snapshot.capturedAt, "2026-10-19T00:00:00Z")
        XCTAssertEqual(snapshot.items.map(\.version), (1...5).map { "fixture-v\($0)" })
        XCTAssertEqual(snapshot.items.map(\.kind), [.computeProfile, .computeProfile, .storage, .storage, .computeProfile])
        XCTAssertEqual(snapshot.items[0].id, snapshot.items[1].id)
        let canonical = try BundledCatalogPreviewSource.fixtureData()
        XCTAssertEqual(SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined(),
                       "2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8")
        XCTAssertEqual(try CatalogSnapshot.decode(canonical).items.count, 29)
        XCTAssertNotEqual(canonical, data)
    }

    func testMutatedOversizedAndOriginalCollectionBytesCannotQualifyAsComparison() throws {
        let data = try CatalogComparisonPreviewSource.fixtureData()
        var changed = data; changed[changed.startIndex] = 32
        for invalid in [changed, data + Data([10]), Data(repeating: 32, count: BuildTransfer.maximumBytes + 1),
                        try BundledCatalogPreviewSource.fixtureData()] {
            XCTAssertThrowsError(try CatalogComparisonPreviewSource.qualify(invalid)) {
                XCTAssertEqual($0 as? CatalogSearchError, .invalidSnapshot)
            }
        }
        XCTAssertEqual(try CatalogComparisonPreviewSource.qualify(data).items.count, 5)
    }

    func testTwoExactVersionsPageSeparatelyAndFiltersPreserveWholeMembership() async throws {
        let source = CatalogComparisonPreviewSource()
        let first = try await source.page(filters: CatalogBrowserFilters(), limit: 2, after: nil)
        XCTAssertEqual(first.totalCount, 5)
        XCTAssertEqual(first.entries.map(\.version), ["fixture-v1", "fixture-v2"])
        XCTAssertEqual(first.entries.map(\.id), ["cat.comparison.compute", "cat.comparison.compute"])
        let second = try await source.page(filters: CatalogBrowserFilters(), limit: 2, after: XCTUnwrap(first.next))
        let third = try await source.page(filters: CatalogBrowserFilters(), limit: 2, after: XCTUnwrap(second.next))
        XCTAssertEqual((first.entries + second.entries + third.entries).map(\.version), (1...5).map { "fixture-v\($0)" })
        XCTAssertNil(third.next)
        let storage = try await source.page(filters: CatalogBrowserFilters(query: "FICTIONAL", kinds: ["storage"], sort: .kind), limit: 25, after: nil)
        XCTAssertEqual(storage.entries.map(\.version), ["fixture-v3", "fixture-v4"])
        let empty = try await source.page(filters: CatalogBrowserFilters(query: "no such record"), limit: 25, after: nil)
        XCTAssertEqual(empty.totalCount, 0); XCTAssertTrue(empty.entries.isEmpty)
        do {
            _ = try await source.page(filters: CatalogBrowserFilters(query: "other"), limit: 2, after: first.next)
            XCTFail("A different query cannot reuse the original continuation")
        } catch { XCTAssertEqual(error as? CatalogSearchError, .mismatchedPage) }
    }

    func testDetailsRejectEveryMismatchedItemAndCatalogPinBeforeAdmission() async throws {
        let source = CatalogComparisonPreviewSource()
        let page = try await source.page(filters: CatalogBrowserFilters(), limit: 25, after: nil)
        let entry = try XCTUnwrap(page.entries.first)
        let wrongItems = [
            CatalogSearchEntry(id: "cat.absent", version: entry.version, kind: entry.kind, title: entry.title),
            CatalogSearchEntry(id: entry.id, version: "fixture-v999", kind: entry.kind, title: entry.title),
            CatalogSearchEntry(id: entry.id, version: entry.version, kind: "storage", title: entry.title),
            CatalogSearchEntry(id: entry.id, version: entry.version, kind: entry.kind, title: entry.title + " ")
        ]
        let wrongPins = [
            ArtifactIdentity(schemaVersion: "2.0.0", id: page.identity.id, revision: 1, capturedAt: page.identity.capturedAt),
            ArtifactIdentity(schemaVersion: "1.0.0", id: "catalog.fixture.1", revision: 1, capturedAt: page.identity.capturedAt),
            ArtifactIdentity(schemaVersion: "1.0.0", id: page.identity.id, revision: 2, capturedAt: page.identity.capturedAt),
            ArtifactIdentity(schemaVersion: "1.0.0", id: page.identity.id, revision: 1, capturedAt: "2026-10-18T00:00:00Z")
        ]
        for row in wrongItems.map({ CatalogBrowserRow(item: $0, snapshot: page.identity) }) +
                   wrongPins.map({ CatalogBrowserRow(item: entry, snapshot: $0) }) {
            do { _ = try await source.details(for: row); XCTFail("Mismatched source must fail closed") }
            catch { XCTAssertEqual(error as? CatalogSearchError, .snapshotUnavailable) }
        }
        let correct = try await source.details(for: CatalogBrowserRow(item: entry, snapshot: page.identity))
        XCTAssertEqual(correct.details.item.version, "fixture-v1")
        XCTAssertEqual(correct.sha256, CatalogComparisonPreviewSource.expectedSHA256)
    }

    func testConcurrentInitialRequestsDoNotRetireTheFirstExactContinuation() async throws {
        let source = CatalogComparisonPreviewSource()
        async let first = source.page(filters: CatalogBrowserFilters(), limit: 2, after: nil)
        async let concurrent = source.page(filters: CatalogBrowserFilters(), limit: 2, after: nil)
        let (a, b) = try await (first, concurrent)
        XCTAssertEqual(a.entries, b.entries)
        let next = try await source.page(filters: CatalogBrowserFilters(), limit: 2, after: XCTUnwrap(a.next))
        XCTAssertEqual(next.entries.map(\.version), ["fixture-v3", "fixture-v4"])
    }

    func testQualifiedSourceFeedsFourExactUnitStatesAndSelectionLimitRecovery() async throws {
        let source = CatalogComparisonPreviewSource()
        let page = try await source.page(filters: CatalogBrowserFilters(), limit: 25, after: nil)
        let comparison = ComponentComparisonModel()
        var candidates: [ComponentComparisonCandidate] = []
        for entry in page.entries {
            let details = try await source.details(for: CatalogBrowserRow(item: entry, snapshot: page.identity))
            candidates.append(try ComponentComparisonCandidate(item: details.details.item,
                catalog: ArtifactPin(kind: .catalog, identity: details.snapshot, sha256: details.sha256)))
        }
        for candidate in candidates.prefix(4) { XCTAssertTrue(comparison.add(candidate)) }
        let disk = try XCTUnwrap(comparison.rows.first { $0.field == "disk_gb" })
        XCTAssertEqual(disk.cells.map(\.availability), [.recorded, .missing, .notApplicable, .notApplicable])
        XCTAssertEqual(disk.cells[0].value, .number(0))
        let network = try XCTUnwrap(comparison.rows.first { $0.field == "network_gbps" })
        XCTAssertEqual(network.cells.map(\.availability), [.missing, .recorded, .notApplicable, .notApplicable])
        let region = try XCTUnwrap(comparison.rows.first { $0.section == .specifications && $0.field == "region" })
        XCTAssertEqual(region.cells.map(\.availability), [.recorded, .recorded, .explicitUnknown, .emptyText])
        let conditions = try XCTUnwrap(comparison.rows.first { $0.field == "extensions" })
        let units = ["milliseconds/request", "seconds/request", "tokens/second", "requests/second"]
        for index in 0..<4 {
            guard case .object(let extensions) = conditions.cells[index].value,
                  case .object(let tuple) = extensions["x_comparison_example"] else { return XCTFail("Complete conditions must remain an object") }
            XCTAssertEqual(tuple["unit"], .string(units[index]))
            XCTAssertEqual(tuple["amount"], .number(index == 0 ? 1000 : 1))
            XCTAssertEqual(tuple["offering"], .string("unqualified-fixture-v\(index + 1)"))
        }
        let before = comparison.selections
        XCTAssertFalse(comparison.add(candidates[4])); XCTAssertEqual(comparison.notice, .selectionLimit)
        XCTAssertEqual(comparison.selections, before)
        comparison.remove(candidates[1].id)
        XCTAssertTrue(comparison.add(candidates[4]))
        XCTAssertEqual(comparison.selections.map(\.details.item.version), ["fixture-v1", "fixture-v3", "fixture-v4", "fixture-v5"])
        XCTAssertTrue(comparison.selections.allSatisfy { $0.catalog.sha256 == CatalogComparisonPreviewSource.expectedSHA256 })
    }
}
