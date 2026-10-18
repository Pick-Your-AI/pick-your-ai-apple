import XCTest
import Foundation
import CSQLite
@testable import PlannerData

final class DraftStoreTests: XCTestCase, @unchecked Sendable {
    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("drafts.sqlite")
    }
    private func sql(_ url: URL, _ statement: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, statement, nil, nil, nil), SQLITE_OK)
    }
    private func scalar(_ url: URL, _ statement: String) throws -> Int {
        var db: OpaquePointer?; var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_finalize(stmt); sqlite3_close(db) }
        XCTAssertEqual(sqlite3_prepare_v2(db, statement, -1, &stmt, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        return Int(sqlite3_column_int64(stmt, 0))
    }
    private func legacy(_ url: URL, id: UUID) throws {
        try sql(url, """
            CREATE TABLE drafts(id TEXT PRIMARY KEY, revision INTEGER NOT NULL);
            CREATE TABLE revisions(draft_id TEXT NOT NULL REFERENCES drafts(id) ON DELETE CASCADE,
              revision INTEGER NOT NULL, title TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(draft_id,revision));
            INSERT INTO drafts VALUES('\(id.uuidString)',1);
            INSERT INTO revisions VALUES('\(id.uuidString)',1,'Legacy',X'7b7d');
            PRAGMA user_version=1;
            """)
    }
    private let empty = Data("{}".utf8)

    func testEmptyDraftSurvivesRestartWithoutInventedContractFields() async throws {
        let url = try location(); let id = UUID()
        let original = try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "", payload: empty)
        let loaded = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(loaded, original); XCTAssertFalse(loaded.analysisIsCurrent)
        XCTAssertEqual(loaded.payload, empty)
    }
    func testExactBytesAndLocksSurviveReopen() async throws {
        let url = try location(); let id = UUID()
        let payload = Data("{\"locks\":{\"catalog\":\"v1\"},\"budget\":\"9007199254740993.01\",\"unknown\":null}".utf8)
        try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "Test", payload: payload)
        let loaded = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(loaded.payload, payload)
    }
    func testCASRejectsStaleWritesAcrossConnections() async throws {
        let url = try location(); let id = UUID(); let first = try DraftStore(url: url); let second = try DraftStore(url: url)
        try await first.save(id: id, expectedRevision: nil, title: "one", payload: empty)
        try await second.save(id: id, expectedRevision: 1, title: "two", payload: empty)
        do { try await first.save(id: id, expectedRevision: 1, title: "stale", payload: empty); XCTFail() }
        catch { XCTAssertEqual(error as? DraftStoreError, .conflict) }
        let current = try await first.read(id: id)
        XCTAssertEqual(current.title, "two")
    }
    func testCreateNeverOverwritesExistingID() async throws {
        let store = try DraftStore(url: location()); let id = UUID()
        try await store.save(id: id, expectedRevision: nil, title: "one", payload: empty)
        do { try await store.save(id: id, expectedRevision: nil, title: "two", payload: empty); XCTFail() }
        catch { XCTAssertEqual(error as? DraftStoreError, .conflict) }
    }
    func testRestoreAppendsHistoryAndRejectsStaleUndo() async throws {
        let store = try DraftStore(url: location()); let id = UUID()
        try await store.save(id: id, expectedRevision: nil, title: "one", payload: empty)
        try await store.save(id: id, expectedRevision: 1, title: "two", payload: Data("{\"edit\":2}".utf8))
        try await store.save(id: id, expectedRevision: 2, title: "three", payload: Data("{\"edit\":3}".utf8))
        do { try await store.restore(id: id, revision: 1, expectedRevision: 2); XCTFail() }
        catch { XCTAssertEqual(error as? DraftStoreError, .conflict) }
        let restored = try await store.restore(id: id, revision: 1, expectedRevision: 3)
        XCTAssertEqual(restored.revision, 4); XCTAssertEqual(restored.restoredFrom, 1)
        XCTAssertFalse(restored.analysisIsCurrent)
        let history = try await store.history(id: id)
        XCTAssertEqual(history.records.map(\.title), ["one", "three", "two", "one"])
    }
    func testRestoreRejectsFutureHistoryWithoutChangingReadableDrafts() async throws {
        let url = try location(); let id = UUID(); let otherID = UUID(); let store = try DraftStore(url: url)
        let original = try await store.save(id: id, expectedRevision: nil, title: "current", payload: empty)
        let other = try await store.save(id: otherID, expectedRevision: nil, title: "unrelated", payload: empty)
        try sql(url, """
            INSERT INTO revisions(draft_id,revision,title,payload,restored_from)
            VALUES('\(id.uuidString)',7,'future',X'7b22667574757265223a377d',NULL)
            """)

        do { try await store.restore(id: id, revision: 7, expectedRevision: 1); XCTFail("Future history must not become a new head") }
        catch { XCTAssertEqual(error as? DraftStoreError, .corruptRecord) }

        XCTAssertEqual(try scalar(url, "SELECT revision FROM drafts WHERE id='\(id.uuidString)'"), 1)
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM revisions WHERE draft_id='\(id.uuidString)'"), 2)
        let reopened = try DraftStore(url: url)
        let retained = try await reopened.read(id: id); XCTAssertEqual(retained, original)
        let unrelated = try await reopened.read(id: otherID); XCTAssertEqual(unrelated, other)

        // A failed corrupt restore must leave the current revision usable as a
        // valid restore source and preserve the damaged history for recovery.
        let restored = try await reopened.restore(id: id, revision: 1, expectedRevision: 1)
        XCTAssertEqual(restored.revision, 2); XCTAssertEqual(restored.restoredFrom, 1)
        XCTAssertEqual(restored.payload, original.payload); XCTAssertEqual(restored.title, original.title)
        let reloaded = try await DraftStore(url: url).read(id: id); XCTAssertEqual(reloaded, restored)
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM revisions WHERE draft_id='\(id.uuidString)' AND revision=7"), 1)
    }
    func testDuplicateCreatesIndependentIdentityAndDeleteIsScoped() async throws {
        let store = try DraftStore(url: location()); let id = UUID()
        let original = try await store.save(id: id, expectedRevision: nil, title: "one", payload: empty)
        let copy = try await store.duplicate(id: id, expectedRevision: 1)
        XCTAssertNotEqual(copy.id, id); XCTAssertEqual(copy.payload, original.payload)
        try await store.delete(id: copy.id, expectedRevision: 1)
        let kept = try await store.read(id: id); XCTAssertEqual(kept, original)
        let history = try await store.history(id: copy.id); XCTAssertTrue(history.records.isEmpty)
    }
    func testRenameCreatesRevisionAndStaleDeleteFails() async throws {
        let store = try DraftStore(url: location()); let id = UUID()
        try await store.save(id: id, expectedRevision: nil, title: "old", payload: empty)
        let renamed = try await store.rename(id: id, expectedRevision: 1, title: "new")
        XCTAssertEqual(renamed.revision, 2); XCTAssertEqual(renamed.payload, empty)
        do { try await store.delete(id: id, expectedRevision: 1); XCTFail() }
        catch { XCTAssertEqual(error as? DraftStoreError, .conflict) }
    }
    func testDeletedIDCannotBeReusedByDelayedCreateOrWrite() async throws {
        let url = try location(); let store = try DraftStore(url: url); let id = UUID()
        try await store.save(id: id, expectedRevision: nil, title: "old", payload: empty)
        try await store.delete(id: id, expectedRevision: 1)
        let reopened = try DraftStore(url: url)
        for expected in [nil, 1] as [Int?] {
            do { try await reopened.save(id: id, expectedRevision: expected, title: "delayed", payload: empty); XCTFail() }
            catch { XCTAssertEqual(error as? DraftStoreError, .conflict) }
        }
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM revisions"), 0)
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM retired_drafts"), 1)
    }
    func testFailedDeleteDoesNotRetireIdentity() async throws {
        let url = try location(); let id = UUID()
        try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "old", payload: empty)
        let failing = try DraftStore(url: url, fault: { if case .beforeCommit = $0 { throw DraftStoreError.database(SQLITE_IOERR) } })
        do { try await failing.delete(id: id, expectedRevision: 1); XCTFail() } catch {}
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM retired_drafts"), 0)
        let edited = try await DraftStore(url: url).save(id: id, expectedRevision: 1, title: "still editable", payload: empty)
        XCTAssertEqual(edited.revision, 2)
    }
    func testVersionTwoMigratesWithoutChangingExistingHistory() async throws {
        let url = try location(); let id = UUID(); try legacy(url, id: id)
        try sql(url, "ALTER TABLE revisions ADD COLUMN restored_from INTEGER; PRAGMA user_version=2;")
        let loaded = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(loaded.title, "Legacy"); XCTAssertEqual(try scalar(url, "PRAGMA user_version"), 3)
    }
    func testInvalidPayloadsAndOversizeAreRejectedWithoutChangingDraft() async throws {
        let store = try DraftStore(url: location()); let id = UUID()
        let old = try await store.save(id: id, expectedRevision: nil, title: "old", payload: empty)
        for data in [Data(), Data("[]".utf8), Data("null".utf8), Data("{bad".utf8), Data(repeating: 32, count: DraftStore.maximumPayloadBytes + 1)] {
            do { try await store.save(id: id, expectedRevision: 1, title: "new", payload: data); XCTFail() }
            catch { XCTAssertEqual(error as? DraftStoreError, .invalidDraft) }
        }
        let actual = try await store.read(id: id); XCTAssertEqual(actual, old)
    }
    func testInvalidTitlesDoNotTruncateOrWrite() async throws {
        let store = try DraftStore(url: location())
        for title in ["a\0b", String(repeating: "😀", count: 257)] {
            do { try await store.save(id: UUID(), expectedRevision: nil, title: title, payload: empty); XCTFail() }
            catch { XCTAssertEqual(error as? DraftStoreError, .invalidDraft) }
        }
    }
    func testFailureAfterHistoryWriteRollsBackAndCanRetry() async throws {
        let url = try location(); let id = UUID()
        try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "old", payload: empty)
        let failing = try DraftStore(url: url, fault: { if case .afterHistoryWrite = $0 { throw DraftStoreError.database(SQLITE_IOERR) } })
        do { try await failing.save(id: id, expectedRevision: 1, title: "new", payload: empty); XCTFail() }
        catch { XCTAssertEqual(error as? DraftStoreError, .database(SQLITE_IOERR)) }
        let reopened = try DraftStore(url: url)
        let loaded = try await reopened.read(id: id); XCTAssertEqual(loaded.revision, 1)
        let retry = try await reopened.save(id: id, expectedRevision: 1, title: "retry", payload: empty)
        XCTAssertEqual(retry.revision, 2)
    }
    func testFailureBeforeCommitRollsBackDelete() async throws {
        let url = try location(); let id = UUID()
        try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "old", payload: empty)
        let failing = try DraftStore(url: url, fault: { if case .beforeCommit = $0 { throw DraftStoreError.database(SQLITE_FULL) } })
        do { try await failing.delete(id: id, expectedRevision: 1); XCTFail() }
        catch { XCTAssertEqual(error as? DraftStoreError, .database(SQLITE_FULL)) }
        let loaded = try await DraftStore(url: url).read(id: id); XCTAssertEqual(loaded.revision, 1)
    }
    func testLegacyMigrationPreservesHistoryAndIsIdempotent() async throws {
        let url = try location(); let id = UUID(); try legacy(url, id: id)
        let first = try await DraftStore(url: url).read(id: id)
        let second = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(first, second); XCTAssertNil(first.restoredFrom)
        XCTAssertEqual(try scalar(url, "PRAGMA user_version"), 3)
    }
    func testInterruptedMigrationRollsBackSchemaThenRecovers() async throws {
        let url = try location(); let id = UUID(); try legacy(url, id: id)
        XCTAssertThrowsError(try DraftStore(url: url, fault: { if case .duringMigration = $0 { throw DraftStoreError.database(SQLITE_IOERR) } }))
        XCTAssertEqual(try scalar(url, "PRAGMA user_version"), 1)
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM pragma_table_info('revisions') WHERE name='restored_from'"), 0)
        let recovered = try await DraftStore(url: url).read(id: id); XCTAssertEqual(recovered.title, "Legacy")
    }
    func testUnknownSchemaNeverResetsDatabase() throws {
        let url = try location(); try sql(url, "CREATE TABLE precious(value TEXT); INSERT INTO precious VALUES('keep'); PRAGMA user_version=99;")
        XCTAssertThrowsError(try DraftStore(url: url)) { XCTAssertEqual($0 as? DraftStoreError, .unsupportedSchema(99)) }
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM precious"), 1)
    }
    func testCorruptDatabaseNeverResetsFile() throws {
        let url = try location(); let original = Data("not a sqlite database".utf8); try original.write(to: url)
        XCTAssertThrowsError(try DraftStore(url: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testLargeLibraryCorruptRowIsolationAndPagination() async throws {
        let url = try location(); let store = try DraftStore(url: url); let bad = UUID(); let good = UUID()
        try await store.save(id: bad, expectedRevision: nil, title: "bad", payload: empty)
        try await store.save(id: good, expectedRevision: nil, title: "good", payload: empty)
        for _ in 0..<501 { try await store.save(id: UUID(), expectedRevision: nil, title: "synthetic", payload: empty) }
        try sql(url, "UPDATE revisions SET payload=X'00' WHERE draft_id='\(bad.uuidString)'")
        let first = try await store.list(limit: 500); let second = try await store.list(limit: 500, offset: 500)
        XCTAssertEqual(first.records.count + second.records.count, 502)
        XCTAssertEqual(first.unreadableCount + second.unreadableCount, 1)
        try await store.rename(id: good, expectedRevision: 1, title: "renamed")
        try await store.delete(id: good, expectedRevision: 2)
        let reopened = try DraftStore(url: url)
        let p1 = try await reopened.list(limit: 500); let p2 = try await reopened.list(limit: 500, offset: 500)
        XCTAssertEqual(p1.records.count + p2.records.count, 501)
        XCTAssertEqual(p1.unreadableCount + p2.unreadableCount, 1)
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM revisions WHERE draft_id='\(bad.uuidString)'"), 1)
    }
    func testMalformedCurrentRowIsNotOverwritten() async throws {
        let url = try location(); let store = try DraftStore(url: url); let id = UUID()
        try await store.save(id: id, expectedRevision: nil, title: "bad", payload: empty)
        try sql(url, "UPDATE revisions SET payload=X'00'")
        do { try await store.save(id: id, expectedRevision: 1, title: "replacement", payload: empty); XCTFail() }
        catch { XCTAssertEqual(error as? DraftStoreError, .corruptRecord) }
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM revisions"), 1)
    }
    func testMissingHistoryIsDisclosedNotSilentlyDropped() async throws {
        let url = try location(); let store = try DraftStore(url: url); let id = UUID()
        try await store.save(id: id, expectedRevision: nil, title: "bad", payload: empty)
        try sql(url, "DELETE FROM revisions")
        let page = try await store.list(); XCTAssertEqual(page.unreadableCount, 1)
    }
    func testSeparateDatabasesDoNotShareIdentity() async throws {
        let first = try DraftStore(url: location()); let second = try DraftStore(url: location()); let id = UUID()
        try await first.save(id: id, expectedRevision: nil, title: "private", payload: empty)
        do { _ = try await second.read(id: id); XCTFail() } catch { XCTAssertEqual(error as? DraftStoreError, .missing) }
    }
    func testActualSQLiteFullRollsBackThenUnconstrainedReopenRecovers() async throws {
        let url = try location(); let id = UUID()
        try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "old", payload: empty)
        let pages = try scalar(url, "PRAGMA page_count")
        let constrained = try DraftStore(url: url, maximumPages: pages, fault: { _ in })
        let large = Data(("{\"content\":\"" + String(repeating: "x", count: 500_000) + "\"}").utf8)
        do { try await constrained.save(id: id, expectedRevision: 1, title: "large", payload: large); XCTFail() }
        catch { XCTAssertEqual(error as? DraftStoreError, .database(SQLITE_FULL)) }
        let reopened = try DraftStore(url: url)
        let retained = try await reopened.read(id: id); XCTAssertEqual(retained.title, "old")
        let retried = try await reopened.save(id: id, expectedRevision: 1, title: "large", payload: large)
        XCTAssertEqual(retried.revision, 2)
    }
    func testCorruptTextAndRestorationTypesAreDisclosed() async throws {
        let url = try location(); let id = UUID(); let store = try DraftStore(url: url)
        try await store.save(id: id, expectedRevision: nil, title: "good", payload: empty)
        for mutation in ["title=CAST(X'610062' AS TEXT)", "title=CAST(X'ff' AS TEXT)", "title='good',restored_from='bad'"] {
            try sql(url, "UPDATE revisions SET " + mutation)
            let page = try await store.list(); XCTAssertEqual(page.unreadableCount, 1)
        }
    }
    func testDatabaseDiagnosticsDoNotContainPayloadOrPath() async throws {
        let url = try location(); try Data("secret-workload".utf8).write(to: url)
        do { _ = try DraftStore(url: url); XCTFail() } catch {
            XCTAssertFalse(String(describing: error).contains("secret-workload"))
            XCTAssertFalse(String(describing: error).contains(url.path))
        }
    }
}
