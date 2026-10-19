import Foundation
import XCTest
import PlannerCatalog
import PlannerTransfer
@testable import PlannerUI

private actor ControlledCatalogDetailsSource: CatalogDetailSource {
    enum Failure: Error { case unavailable }
    let fallback: CatalogPinnedDetails
    private var responses: [Result<CatalogPinnedDetails, Failure>] = []
    private var pauseNext = false
    private var suspended = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var requests: [CatalogBrowserRow] = []
    init(_ result: CatalogPinnedDetails) { fallback = result }
    func respond(_ value: Result<CatalogPinnedDetails, Failure>) { responses.append(value) }
    func pauseNextResponse() { pauseNext = true }
    func waitUntilSuspended() async {
        if suspended { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func releaseResponse() { releaseWaiter?.resume(); releaseWaiter = nil; suspended = false }
    func details(for row: CatalogBrowserRow) async throws -> CatalogPinnedDetails {
        requests.append(row)
        let response = responses.isEmpty ? .success(fallback) : responses.removeFirst()
        if pauseNext {
            pauseNext = false; suspended = true; entryWaiter?.resume(); entryWaiter = nil
            // A completed file/cache read may ignore cancellation. The receiving
            // sheet must still reject its completion after being dismissed.
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        return try response.get()
    }
}

@MainActor
final class CatalogDetailsModelTests: XCTestCase {
    private func fixture() async throws -> (BundledCatalogPreviewSource, CatalogBrowserRow, CatalogPinnedDetails) {
        let source = BundledCatalogPreviewSource()
        let page = try await source.page(filters: CatalogBrowserFilters(), limit: 100, after: nil)
        let item = try XCTUnwrap(page.entries.first { $0.kind == "model" })
        let row = CatalogBrowserRow(item: item, snapshot: page.identity)
        let resolved = try await source.details(for: row)
        return (source, row, resolved)
    }

    private func revised(_ result: CatalogPinnedDetails, changing update: (inout [String: JSONValue]) -> Void) throws -> CatalogPinnedDetails {
        guard case .object(var fields) = result.details.item.value else { throw ControlledCatalogDetailsSource.Failure.unavailable }
        update(&fields)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let item = try CatalogItem.decode(encoder.encode(JSONValue.object(fields)))
        // This is a controlled presentation test double. Only the real bundled
        // source test below establishes byte qualification for the application.
        return try CatalogPinnedDetails(details: CatalogItemDetails(item: item), snapshot: result.snapshot, sha256: result.sha256)
    }

    func testBundledDetailsResolveAllExactKindsWithoutInvalidatingAnIssuedPage() async throws {
        let source = BundledCatalogPreviewSource()
        let first = try await source.page(filters: CatalogBrowserFilters(), limit: 2, after: nil)
        let all = try await source.page(filters: CatalogBrowserFilters(), limit: 100, after: nil)
        XCTAssertEqual(all.entries.count, 29)
        for item in all.entries {
            let row = CatalogBrowserRow(item: item, snapshot: all.identity)
            let resolved = try await source.details(for: row)
            XCTAssertEqual(resolved.snapshot, row.snapshot)
            XCTAssertEqual(resolved.sha256, BundledCatalogPreviewSource.expectedSHA256)
            XCTAssertEqual(resolved.details.item.id, item.id)
            XCTAssertEqual(resolved.details.item.version, item.version)
            XCTAssertEqual(resolved.details.item.kind.rawValue, item.kind)
            XCTAssertEqual(resolved.details.item.name, item.title)
            XCTAssertFalse(resolved.details.provenance.isEmpty)
        }
        let next = try await source.page(filters: CatalogBrowserFilters(), limit: 2, after: XCTUnwrap(first.next))
        XCTAssertEqual(next.identity, first.identity)
        XCTAssertEqual(next.entries, Array(all.entries.dropFirst(2).prefix(2)))
    }

    func testBundledDetailsRejectForgedRowsAndChangedCatalogPins() async throws {
        let (source, row, _) = try await fixture()
        let invalid = [
            CatalogBrowserRow(item: CatalogSearchEntry(id: "cat.missing", version: row.item.version, kind: row.item.kind, title: row.item.title), snapshot: row.snapshot),
            CatalogBrowserRow(item: CatalogSearchEntry(id: row.item.id, version: "missing-version", kind: row.item.kind, title: row.item.title), snapshot: row.snapshot),
            CatalogBrowserRow(item: CatalogSearchEntry(id: row.item.id, version: row.item.version, kind: "accelerator", title: row.item.title), snapshot: row.snapshot),
            CatalogBrowserRow(item: CatalogSearchEntry(id: row.item.id, version: row.item.version, kind: row.item.kind, title: "Forged name"), snapshot: row.snapshot),
            CatalogBrowserRow(item: row.item, snapshot: ArtifactIdentity(schemaVersion: "1.0.0", id: row.snapshot.id, revision: 2, capturedAt: row.snapshot.capturedAt)),
            CatalogBrowserRow(item: row.item, snapshot: ArtifactIdentity(schemaVersion: "1.0.0", id: "catalog.other", revision: 1, capturedAt: row.snapshot.capturedAt)),
            CatalogBrowserRow(item: row.item, snapshot: ArtifactIdentity(schemaVersion: "1.0.0", id: row.snapshot.id, revision: 1, capturedAt: "2020-01-01T00:00:00Z"))
        ]
        for candidate in invalid {
            do { _ = try await source.details(for: candidate); XCTFail("A forged or changed pin must fail") }
            catch { XCTAssertEqual(error as? CatalogSearchError, .snapshotUnavailable) }
        }
    }

    func testFailureAndRetryKeepTheExactSelectedPin() async throws {
        let (_, row, resolved) = try await fixture()
        let source = ControlledCatalogDetailsSource(resolved)
        await source.respond(.failure(.unavailable))
        let model = CatalogDetailsModel(row: row, source: source)
        model.loadIfNeeded(); await model.waitForCurrentRequest()
        XCTAssertTrue(model.unavailable); XCTAssertFalse(model.isLoading); XCTAssertNil(model.result)
        XCTAssertEqual(model.row, row)
        model.retry(); await model.waitForCurrentRequest()
        XCTAssertFalse(model.unavailable); XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.result, resolved)
        let requests = await source.requests
        XCTAssertEqual(requests, [row, row])
        model.loadIfNeeded(); await model.waitForCurrentRequest()
        let finalRequests = await source.requests
        XCTAssertEqual(finalRequests.count, 2)
    }

    func testMismatchedResolvedIdentityOrHashCannotBecomeVisible() async throws {
        let (_, row, resolved) = try await fixture()
        let wrongName = try revised(resolved) { $0["name"] = .string("Another name") }
        let changedPin = ArtifactIdentity(schemaVersion: "1.0.0", id: row.snapshot.id, revision: 2, capturedAt: row.snapshot.capturedAt)
        for invalid in [wrongName,
                        CatalogPinnedDetails(details: resolved.details, snapshot: changedPin, sha256: resolved.sha256),
                        CatalogPinnedDetails(details: resolved.details, snapshot: row.snapshot, sha256: "invalid-hash")] {
            let model = CatalogDetailsModel(row: row, source: ControlledCatalogDetailsSource(invalid))
            model.loadIfNeeded(); await model.waitForCurrentRequest()
            XCTAssertNil(model.result); XCTAssertTrue(model.unavailable); XCTAssertFalse(model.isLoading)
            XCTAssertEqual(model.row, row)
        }
    }

    func testDismissalRejectsALateCancellationIgnoringResultAndRetiredActions() async throws {
        let (_, row, resolved) = try await fixture()
        let source = ControlledCatalogDetailsSource(resolved)
        await source.pauseNextResponse()
        let retired = CatalogDetailsModel(row: row, source: source)
        retired.loadIfNeeded(); await source.waitUntilSuspended()
        retired.close()
        let current = CatalogDetailsModel(row: row, source: source)
        current.loadIfNeeded(); await current.waitForCurrentRequest()
        await source.releaseResponse(); await retired.waitForCurrentRequest()
        XCTAssertNil(retired.result); XCTAssertFalse(retired.isLoading)
        XCTAssertEqual(current.result, resolved)
        retired.retry(); retired.loadIfNeeded(); retired.loadMoreSources()
        let requests = await source.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(retired.provenanceLimit, 8)
    }

    func testSourcePaginationRetainsEveryRecordAndNeverChangesTheItemPin() async throws {
        let (_, row, resolved) = try await fixture()
        let many = try revised(resolved) { value in
            value["provenance"] = .array((0..<17).map { index in
                .object(["checked_at": .string("2026-10-16T09:00:00Z"), "verification_status": .string("unverified"),
                         "notes": .string("Recorded source \(index)")])
            })
        }
        let model = CatalogDetailsModel(row: row, source: ControlledCatalogDetailsSource(many))
        model.loadIfNeeded(); await model.waitForCurrentRequest()
        XCTAssertEqual(model.provenanceLimit, 8)
        model.loadMoreSources(); XCTAssertEqual(model.provenanceLimit, 16)
        model.loadMoreSources(); XCTAssertEqual(model.provenanceLimit, 17)
        model.loadMoreSources(); XCTAssertEqual(model.provenanceLimit, 17)
        XCTAssertEqual(model.result, many); XCTAssertEqual(model.row, row)
        let expectedNotes: [String?] = (0..<17).map { "Recorded source \($0)" }
        XCTAssertEqual(model.result?.details.provenance.map(\.notes), expectedNotes)
    }

    func testLiteralDisplayEscapesInvisibleControlsAndBoundsCompleteUnicodeScalars() {
        let value = CatalogDetailText.literal("name\n\u{202e}[source](javascript:alert(1))\u{0}")
        XCTAssertEqual(value.text, #"name\u{a}\u{202e}[source](javascript:alert(1))\u{0}"#)
        XCTAssertFalse(value.truncated)
        XCTAssertNotEqual(CatalogDetailText.literal("\u{202e}").text, CatalogDetailText.literal(#"\u{202e}"#).text)
        let long = CatalogDetailText.literal(String(repeating: "🧪", count: 513))
        XCTAssertTrue(long.truncated)
        XCTAssertEqual(long.text.utf8.count, CatalogDetailText.maximumBytes)
        XCTAssertEqual(long.text, String(repeating: "🧪", count: 512))
        let boundary = CatalogDetailText.literal(String(repeating: "a", count: 2_047) + "🧪")
        XCTAssertEqual(boundary.text.utf8.count, 2_047); XCTAssertTrue(boundary.truncated)
        XCTAssertEqual(CatalogDetailText.literal("unknown").text, "unknown")
        XCTAssertEqual(CatalogDetailText.value(.string("unknown")).text, #""unknown""#)
        XCTAssertEqual(CatalogDetailText.value(.bool(false)).text, "false")
        XCTAssertEqual(CatalogDetailText.value(.number(0)).text, "0")
        XCTAssertNotEqual(CatalogDetailText.state(.missing), CatalogDetailText.state(.supplied))
    }

    func testSheetIdentityIncludesTheCatalogReleaseAndCompleteRow() async throws {
        let (_, row, _) = try await fixture()
        let changedPin = ArtifactIdentity(schemaVersion: "1.0.0", id: row.snapshot.id, revision: 2, capturedAt: row.snapshot.capturedAt)
        let changedRow = CatalogSearchEntry(id: row.item.id, version: row.item.version, kind: row.item.kind, title: "Another title")
        XCTAssertNotEqual(CatalogDetailsIdentity(row), CatalogDetailsIdentity(CatalogBrowserRow(item: row.item, snapshot: changedPin)))
        XCTAssertNotEqual(CatalogDetailsIdentity(row), CatalogDetailsIdentity(CatalogBrowserRow(item: changedRow, snapshot: row.snapshot)))
    }
}
