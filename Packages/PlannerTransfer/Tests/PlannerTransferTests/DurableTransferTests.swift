import Foundation
import XCTest
import PlannerData
import PlannerTransfer

final class DurableTransferTests: XCTestCase, @unchecked Sendable {
    func testEmptyAutosaveSurvivesRejectedExportAndStoreReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("drafts.sqlite")
        let id = UUID()
        let empty = Data(#"{"selections":[],"locks":{"catalog_snapshot_id":"catalog.pinned"}}"#.utf8)
        let saved = try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "Incomplete", payload: empty)
        let before = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(before, saved)
        XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: before.payload))
        let after = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.payload, empty)
        XCTAssertEqual(after.revision, 1)
        XCTAssertFalse(after.analysisIsCurrent)
        let history = try await DraftStore(url: url).history(id: id)
        XCTAssertEqual(history.records.count, 1)
        // Malicious import preview is likewise unable to change an existing draft.
        XCTAssertThrowsError(try BuildTransfer.preview(Data(#"{"schema_version":"2.0.0","secret":"private"}"#.utf8)))
        let afterImport = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(afterImport, before)
    }
}
