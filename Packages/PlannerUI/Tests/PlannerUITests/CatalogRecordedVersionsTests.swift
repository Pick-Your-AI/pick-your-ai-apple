import CryptoKit
import Foundation
import XCTest
import PlannerCatalog
import PlannerTransfer
@testable import PlannerUI

private actor ControlledRecordedVersionSource: CatalogDetailSource {
    enum Failure: Error { case unavailable }
    struct Request: Equatable, Sendable {
        let row: CatalogBrowserRow
        let hash: String
    }
    let details: CatalogPinnedDetails
    let fallback: CatalogRecordedVersionListing
    private var responses: [Result<CatalogRecordedVersionListing, Failure>] = []
    private var pauseNext = false
    private var suspended = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var requests: [Request] = []

    init(details: CatalogPinnedDetails, listing: CatalogRecordedVersionListing) {
        self.details = details; fallback = listing
    }
    func details(for row: CatalogBrowserRow) async throws -> CatalogPinnedDetails { details }
    func respond(_ result: Result<CatalogRecordedVersionListing, Failure>) { responses.append(result) }
    func pauseNextResponse() { pauseNext = true }
    func waitUntilSuspended() async {
        if suspended { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func releaseResponse() { releaseWaiter?.resume(); releaseWaiter = nil; suspended = false }

    func recordedVersions(for row: CatalogBrowserRow, snapshotSHA256: String) async throws -> CatalogRecordedVersionListing {
        requests.append(Request(row: row, hash: snapshotSHA256))
        let result = responses.isEmpty ? .success(fallback) : responses.removeFirst()
        if pauseNext {
            pauseNext = false; suspended = true; entryWaiter?.resume(); entryWaiter = nil
            // Deliberately ignore cancellation to exercise the receiver's guard.
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        return try result.get()
    }
}

/// Decoded synthetic inputs for receiving-model tests, not a product data source.
private struct RecordedVersionFixtureSource: CatalogDetailSource {
    let snapshot: CatalogSnapshot
    let hash: String
    func details(for row: CatalogBrowserRow) async throws -> CatalogPinnedDetails {
        let listing = try CatalogRecordedVersionListing.project(snapshot, anchor: row, sha256: hash)
        guard listing.rows.contains(row),
              let item = snapshot.items.first(where: { $0.id == row.item.id && $0.version == row.item.version }) else {
            throw CatalogSearchError.snapshotUnavailable
        }
        return try CatalogPinnedDetails(details: CatalogItemDetails(item: item), snapshot: row.snapshot, sha256: hash)
    }
    func recordedVersions(for row: CatalogBrowserRow, snapshotSHA256: String) async throws -> CatalogRecordedVersionListing {
        guard hash == snapshotSHA256 else { throw CatalogSearchError.snapshotUnavailable }
        return try CatalogRecordedVersionListing.project(snapshot, anchor: row, sha256: hash)
    }
}

private struct DetailOnlyVersionSource: CatalogDetailSource {
    let result: CatalogPinnedDetails
    func details(for row: CatalogBrowserRow) async throws -> CatalogPinnedDetails { result }
}

@MainActor
final class CatalogRecordedVersionsTests: XCTestCase {
    private func fixture() async throws -> (CatalogBrowserRow, CatalogPinnedDetails) {
        let source = BundledCatalogPreviewSource()
        let page = try await source.page(filters: CatalogBrowserFilters(), limit: 100, after: nil)
        let item = try XCTUnwrap(page.entries.first { $0.kind == "model" })
        let row = CatalogBrowserRow(item: item, snapshot: page.identity)
        return (row, try await source.details(for: row))
    }

    private func item(_ details: CatalogPinnedDetails, version: String, name: String? = nil) throws -> JSONValue {
        guard case .object(var value) = details.details.item.value else { throw CatalogSearchError.invalidSnapshot }
        value["version"] = .string(version)
        if let name { value["name"] = .string(name) }
        return .object(value)
    }

    private func snapshotSource(items: [JSONValue]) throws -> RecordedVersionFixtureSource {
        let original = try CatalogSnapshot.decode(BundledCatalogPreviewSource.fixtureData())
        guard case .object(var value) = original.value else { throw CatalogSearchError.invalidSnapshot }
        value["items"] = .array(items)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(JSONValue.object(value))
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return RecordedVersionFixtureSource(snapshot: try CatalogSnapshot.decode(bytes), hash: hash)
    }

    private func versions() async throws -> (CatalogBrowserRow, CatalogPinnedDetails, CatalogRecordedVersionListing, RecordedVersionFixtureSource) {
        let (row, original) = try await fixture()
        let catalog = try CatalogSnapshot.decode(BundledCatalogPreviewSource.fixtureData())
        let accelerator = try XCTUnwrap(catalog.items.first { $0.kind.rawValue == "accelerator" })
        guard case .object(var otherKind) = accelerator.value,
              case .object(var otherIdentity) = original.details.item.value else { throw CatalogSearchError.invalidSnapshot }
        otherKind["id"] = .string(row.item.id); otherKind["version"] = .string("different-kind")
        otherIdentity["id"] = .string("cat.unrelated.fixture")
        otherIdentity["name"] = .string(row.item.title)
        let source = try snapshotSource(items: [
            try item(original, version: "2", name: "Second recorded model"),
            original.details.item.value,
            try item(original, version: "10", name: "Tenth recorded model"),
            try item(original, version: "unknown", name: "Unqualified version text"),
            .object(otherKind), .object(otherIdentity)
        ])
        let details = try await source.details(for: row)
        let listing = try await source.recordedVersions(for: row, snapshotSHA256: source.hash)
        return (row, details, listing, source)
    }

    func testBundledRecordedVersionsKeepAllKindsAndExistingPageCursor() async throws {
        let source = BundledCatalogPreviewSource()
        let first = try await source.page(filters: CatalogBrowserFilters(), limit: 2, after: nil)
        let all = try await source.page(filters: CatalogBrowserFilters(), limit: 100, after: nil)
        XCTAssertEqual(all.entries.count, 29)
        for item in all.entries {
            let row = CatalogBrowserRow(item: item, snapshot: all.identity)
            let details = try await source.details(for: row)
            let listing = try await source.recordedVersions(for: row, snapshotSHA256: details.sha256)
            XCTAssertEqual(listing.anchor, row)
            XCTAssertEqual(listing.sha256, BundledCatalogPreviewSource.expectedSHA256)
            XCTAssertEqual(listing.rows, [row], "No other recorded version is different from an unavailable listing")
            XCTAssertTrue(listing.isValid(for: row, sha256: details.sha256))
        }
        let next = try await source.page(filters: CatalogBrowserFilters(), limit: 2, after: XCTUnwrap(first.next))
        XCTAssertEqual(next.identity, first.identity)
        XCTAssertEqual(next.entries, Array(all.entries.dropFirst(2).prefix(2)))
    }

    func testBundledRecordedVersionsRejectChangedHashAndForgedAnchor() async throws {
        let (row, details) = try await fixture()
        let source = BundledCatalogPreviewSource()
        let wrongPin = ArtifactIdentity(schemaVersion: "1.0.0", id: row.snapshot.id, revision: 2, capturedAt: row.snapshot.capturedAt)
        let forged = CatalogBrowserRow(item: CatalogSearchEntry(id: row.item.id, version: row.item.version,
            kind: row.item.kind, title: "Forged title"), snapshot: row.snapshot)
        for (anchor, hash) in [(row, String(repeating: "0", count: 64)), (row, "bad-hash"),
                               (forged, details.sha256), (CatalogBrowserRow(item: row.item, snapshot: wrongPin), details.sha256)] {
            do {
                _ = try await source.recordedVersions(for: anchor, snapshotSHA256: hash)
                XCTFail("An unavailable identity or different source hash cannot supply related versions")
            } catch { XCTAssertEqual(error as? CatalogSearchError, .snapshotUnavailable) }
        }
    }

    func testVersionProjectionPreservesOpaqueVersionsAndExplicitDetailNavigation() async throws {
        let (row, details, listing, source) = try await versions()
        XCTAssertEqual(listing.rows.map(\.item.version), ["10", "2", row.item.version, "unknown"])
        XCTAssertTrue(listing.rows.allSatisfy { $0.item.id == row.item.id && $0.item.kind == row.item.kind })
        XCTAssertEqual(source.snapshot.items.count, 6, "Another kind or a matching name does not infer a version relationship")
        let model = CatalogRecordedVersionsModel(row: row, source: source)
        model.loadIfNeeded(details: details); await model.waitForCurrentRequest()
        XCTAssertEqual(model.otherVersions.map(\.item.version), ["10", "2", "unknown"])
        XCTAssertEqual(model.result, listing)
        for version in model.otherVersions {
            let selected = try XCTUnwrap(model.selection(for: version))
            let destination = CatalogDetailsModel(row: selected, source: source)
            destination.loadIfNeeded(); await destination.waitForCurrentRequest()
            XCTAssertEqual(destination.row, version)
            XCTAssertEqual(destination.result?.details.item.id, row.item.id)
            XCTAssertEqual(destination.result?.details.item.version, version.item.version)
            XCTAssertEqual(destination.result?.details.item.name, version.item.title)
            XCTAssertEqual(destination.result?.sha256, details.sha256)
            XCTAssertEqual(destination.result?.snapshot, row.snapshot)
            XCTAssertFalse(destination.unavailable)
            destination.close()
        }
        XCTAssertEqual(model.row, row)
        XCTAssertEqual(model.result, listing)
        XCTAssertEqual(details.details.item.version, row.item.version)
        model.close()
    }

    func testVersionProjectionRejectsAmbiguityAndBoundsCompleteListing() async throws {
        let (row, details) = try await fixture()
        let duplicate = try snapshotSource(items: [details.details.item.value, details.details.item.value])
        XCTAssertThrowsError(try CatalogRecordedVersionListing.project(duplicate.snapshot, anchor: row, sha256: duplicate.hash)) {
            XCTAssertEqual($0 as? CatalogSearchError, .invalidSnapshot)
        }
        let original = try CatalogSnapshot.decode(BundledCatalogPreviewSource.fixtureData())
        let accelerator = try XCTUnwrap(original.items.first { $0.kind.rawValue == "accelerator" })
        guard case .object(var differentKind) = accelerator.value else { throw CatalogSearchError.invalidSnapshot }
        differentKind["id"] = .string(row.item.id); differentKind["version"] = .string(row.item.version)
        let ambiguousKind = try snapshotSource(items: [details.details.item.value, .object(differentKind)])
        XCTAssertThrowsError(try CatalogRecordedVersionListing.project(ambiguousKind.snapshot, anchor: row, sha256: ambiguousKind.hash)) {
            XCTAssertEqual($0 as? CatalogSearchError, .invalidSnapshot)
        }
        let maximum = [details.details.item.value] + (try (1..<100).map { index in
            try item(details, version: "recorded-\(index)")
        })
        let bounded = try snapshotSource(items: maximum)
        let accepted = try CatalogRecordedVersionListing.project(bounded.snapshot, anchor: row, sha256: bounded.hash)
        XCTAssertEqual(accepted.rows.count, 100)
        let excessive = try snapshotSource(items: maximum + [try item(details, version: "recorded-100")])
        XCTAssertThrowsError(try CatalogRecordedVersionListing.project(excessive.snapshot, anchor: row, sha256: excessive.hash)) {
            XCTAssertEqual($0 as? CatalogSearchError, .invalidSnapshot)
        }
        let absent = try snapshotSource(items: [try item(details, version: "different-version")])
        XCTAssertThrowsError(try CatalogRecordedVersionListing.project(absent.snapshot, anchor: row, sha256: absent.hash)) {
            XCTAssertEqual($0 as? CatalogSearchError, .snapshotUnavailable)
        }
    }

    func testOnlyCompleteListedRowsCanRequestInspection() async throws {
        let (row, details, listing, source) = try await versions()
        let model = CatalogRecordedVersionsModel(row: row, source: source)
        XCTAssertNil(model.selection(for: listing.rows[0]))
        model.loadIfNeeded(details: details); await model.waitForCurrentRequest()
        let target = try XCTUnwrap(model.otherVersions.first)
        XCTAssertEqual(model.selection(for: target), target)
        XCTAssertNil(model.selection(for: row))
        let alteredTitle = CatalogBrowserRow(item: CatalogSearchEntry(id: target.item.id, version: target.item.version,
            kind: target.item.kind, title: "Replaced title"), snapshot: target.snapshot)
        let alteredVersion = CatalogBrowserRow(item: CatalogSearchEntry(id: target.item.id, version: "not-in-source",
            kind: target.item.kind, title: target.item.title), snapshot: target.snapshot)
        let alteredPin = CatalogBrowserRow(item: target.item, snapshot: ArtifactIdentity(schemaVersion: "1.0.0",
            id: target.snapshot.id, revision: 2, capturedAt: target.snapshot.capturedAt))
        for forged in [alteredTitle, alteredVersion, alteredPin] { XCTAssertNil(model.selection(for: forged)) }
        model.rejectSelection()
        XCTAssertNil(model.selection(for: target)); XCTAssertNil(model.result)
        XCTAssertTrue(model.unavailable); XCTAssertFalse(model.canRetry)
        XCTAssertEqual(model.row, row)
    }

    func testMalformedListingsCannotBecomeEmptyOrNavigableResults() async throws {
        let (row, details, listing, _) = try await versions()
        let otherPin = ArtifactIdentity(schemaVersion: "1.0.0", id: row.snapshot.id, revision: 2, capturedAt: row.snapshot.capturedAt)
        let wrongKind = CatalogBrowserRow(item: CatalogSearchEntry(id: row.item.id, version: "another",
            kind: "accelerator", title: "Wrong kind"), snapshot: row.snapshot)
        let wrongTitle = CatalogBrowserRow(item: CatalogSearchEntry(id: row.item.id, version: row.item.version,
            kind: row.item.kind, title: "Wrong anchor title"), snapshot: row.snapshot)
        let emptyVersion = CatalogBrowserRow(item: CatalogSearchEntry(id: row.item.id, version: "", kind: row.item.kind,
            title: row.item.title), snapshot: row.snapshot)
        let longVersion = CatalogBrowserRow(item: CatalogSearchEntry(id: row.item.id, version: String(repeating: "v", count: 129),
            kind: row.item.kind, title: row.item.title), snapshot: row.snapshot)
        let longTitle = CatalogBrowserRow(item: CatalogSearchEntry(id: row.item.id, version: "another", kind: row.item.kind,
            title: String(repeating: "x", count: 1_025)), snapshot: row.snapshot)
        let excessive = [row] + (1...100).map { index in
            CatalogBrowserRow(item: CatalogSearchEntry(id: row.item.id, version: "v\(index)", kind: row.item.kind,
                title: "Recorded \(index)"), snapshot: row.snapshot)
        }
        let invalid = [
            CatalogRecordedVersionListing(anchor: row, sha256: String(repeating: "0", count: 64), rows: listing.rows),
            CatalogRecordedVersionListing(anchor: row, sha256: details.sha256, rows: []),
            CatalogRecordedVersionListing(anchor: row, sha256: details.sha256, rows: [row, row]),
            CatalogRecordedVersionListing(anchor: row, sha256: details.sha256, rows: listing.rows.filter { $0 != row }),
            CatalogRecordedVersionListing(anchor: row, sha256: details.sha256, rows: [wrongTitle]),
            CatalogRecordedVersionListing(anchor: row, sha256: details.sha256, rows: [row, wrongKind]),
            CatalogRecordedVersionListing(anchor: row, sha256: details.sha256, rows: [row, emptyVersion]),
            CatalogRecordedVersionListing(anchor: row, sha256: details.sha256, rows: [row, longVersion]),
            CatalogRecordedVersionListing(anchor: row, sha256: details.sha256, rows: [row, longTitle]),
            CatalogRecordedVersionListing(anchor: row, sha256: details.sha256, rows: [row, CatalogBrowserRow(item: listing.rows[0].item, snapshot: otherPin)]),
            CatalogRecordedVersionListing(anchor: CatalogBrowserRow(item: row.item, snapshot: otherPin), sha256: details.sha256, rows: listing.rows),
            CatalogRecordedVersionListing(anchor: row, sha256: details.sha256, rows: excessive)
        ]
        for value in invalid {
            let source = ControlledRecordedVersionSource(details: details, listing: value)
            let model = CatalogRecordedVersionsModel(row: row, source: source)
            model.loadIfNeeded(details: details); await model.waitForCurrentRequest()
            XCTAssertTrue(model.unavailable); XCTAssertFalse(model.isLoading)
            XCTAssertNil(model.result); XCTAssertTrue(model.otherVersions.isEmpty)
            XCTAssertNil(model.selection(for: listing.rows[0]))
            XCTAssertEqual(model.row, row)
            model.close()
        }
    }

    func testFailureRetryPreservesTheExactDetailAndCatalogHash() async throws {
        let (row, details, listing, _) = try await versions()
        let unsupported = CatalogRecordedVersionsModel(row: row, source: DetailOnlyVersionSource(result: details))
        unsupported.loadIfNeeded(details: details); await unsupported.waitForCurrentRequest()
        XCTAssertTrue(unsupported.unavailable); XCTAssertNil(unsupported.result)
        XCTAssertEqual(unsupported.row, row)
        unsupported.close()
        let source = ControlledRecordedVersionSource(details: details, listing: listing)
        await source.respond(.failure(.unavailable))
        let model = CatalogRecordedVersionsModel(row: row, source: source)
        model.loadIfNeeded(details: details); await model.waitForCurrentRequest()
        XCTAssertTrue(model.unavailable); XCTAssertTrue(model.canRetry)
        XCTAssertNil(model.result); XCTAssertEqual(model.row, row)
        model.retry(); await model.waitForCurrentRequest()
        XCTAssertEqual(model.result, listing)
        XCTAssertFalse(model.unavailable); XCTAssertFalse(model.canRetry)
        model.loadIfNeeded(details: details); await model.waitForCurrentRequest()
        let requests = await source.requests
        XCTAssertEqual(requests, [ControlledRecordedVersionSource.Request(row: row, hash: details.sha256),
                                  ControlledRecordedVersionSource.Request(row: row, hash: details.sha256)])
        XCTAssertEqual(details.details.item.id, row.item.id)
        model.close()
    }

    func testDismissalRejectsLateResultsErrorsAndRetiredActions() async throws {
        for fail in [false, true] {
            let (row, details, listing, _) = try await versions()
            let source = ControlledRecordedVersionSource(details: details, listing: listing)
            if fail { await source.respond(.failure(.unavailable)) }
            await source.pauseNextResponse()
            let model = CatalogRecordedVersionsModel(row: row, source: source)
            model.loadIfNeeded(details: details); await source.waitUntilSuspended()
            model.close()
            await source.releaseResponse(); await model.waitForCurrentRequest()
            XCTAssertNil(model.result); XCTAssertFalse(model.isLoading); XCTAssertFalse(model.unavailable)
            XCTAssertNil(model.selection(for: listing.rows[0]))
            model.retry(); model.loadIfNeeded(details: details); model.rejectSelection()
            let requests = await source.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(model.row, row)
        }
    }

    func testChangedDetailPinInvalidatesAnOutstandingVersionRequest() async throws {
        let (row, details, listing, _) = try await versions()
        let source = ControlledRecordedVersionSource(details: details, listing: listing)
        await source.pauseNextResponse()
        let model = CatalogRecordedVersionsModel(row: row, source: source)
        model.loadIfNeeded(details: details); await source.waitUntilSuspended()
        let changed = CatalogPinnedDetails(details: details.details, snapshot: details.snapshot, sha256: String(repeating: "f", count: 64))
        model.loadIfNeeded(details: changed)
        XCTAssertTrue(model.unavailable); XCTAssertFalse(model.canRetry); XCTAssertFalse(model.isLoading)
        await source.releaseResponse(); await model.waitForCurrentRequest()
        XCTAssertNil(model.result); XCTAssertNil(model.selection(for: listing.rows[0]))
        model.retry(); model.loadIfNeeded(details: details)
        let requests = await source.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.hash, details.sha256)
        XCTAssertEqual(model.row, row)
        model.close()
    }
}
