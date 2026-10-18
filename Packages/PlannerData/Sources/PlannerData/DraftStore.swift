import Foundation
import CSQLite

/// Errors never include SQL, file paths, workload text, or database messages.
public enum DraftStoreError: Error, Equatable, Sendable {
    case database(Int32), unsupportedSchema(Int), conflict, missing, corruptRecord, invalidDraft
}

/// Local editor state, not a contract BuildSnapshot. Even {} is a valid draft.
public struct DraftRecord: Equatable, Sendable {
    public let id: UUID
    public let revision: Int
    public let title: String
    public let payload: Data
    public let restoredFrom: Int?
    /// Stored draft/history never implies current compatibility, pricing or approval.
    public var analysisIsCurrent: Bool { false }
}

public struct DraftPage: Sendable {
    public let records: [DraftRecord]
    /// Unreadable rows are retained in storage; a caller must disclose this count.
    public let unreadableCount: Int
}

package enum StorageFaultPoint: Sendable { case afterHistoryWrite, beforeCommit, duringMigration }

// The connection is private to a DraftStore actor after construction. It is never
// shared across actors; FULLMUTEX also protects SQLite during initialization/deinit.
private final class Connection: @unchecked Sendable {
    let handle: OpaquePointer
    init(path: String) throws {
        var db: OpaquePointer?
        let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw DraftStoreError.database(result)
        }
        handle = db
        sqlite3_busy_timeout(handle, 2_000)
    }
    deinit { sqlite3_close(handle) }
    func exec(_ sql: String) throws {
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw DraftStoreError.database(result) }
    }
    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw DraftStoreError.database(result) }
        return statement
    }
    func scalar(_ sql: String) throws -> Int {
        let stmt = try prepare(sql); defer { sqlite3_finalize(stmt) }
        let result = sqlite3_step(stmt)
        guard result == SQLITE_ROW else { throw DraftStoreError.database(result) }
        return Int(sqlite3_column_int64(stmt, 0))
    }
}

/// One database per local identity; callers must provide an app-owned, protected
/// directory. No remote writes, snapshot export, account or file-import authority.
public actor DraftStore {
    public static let maximumPayloadBytes = 1_048_576
    private let db: Connection
    private let fault: @Sendable (StorageFaultPoint) throws -> Void

    public init(url: URL) throws {
        try self.init(url: url, fault: { _ in })
    }

    package init(url: URL, maximumPages: Int? = nil, fault: @escaping @Sendable (StorageFaultPoint) throws -> Void) throws {
        guard url.isFileURL else { throw DraftStoreError.invalidDraft }
        let db = try Connection(path: url.path)
        // DELETE journal plus FULL sync: no untracked WAL sidecars to forget during backup.
        try db.exec("PRAGMA foreign_keys = ON; PRAGMA journal_mode = DELETE; PRAGMA synchronous = FULL;")
        try db.exec("BEGIN IMMEDIATE")
        do {
            let version = try db.scalar("PRAGMA user_version")
            guard (0...3).contains(version) else { throw DraftStoreError.unsupportedSchema(version) }
            if version == 0 {
                try db.exec("""
                    CREATE TABLE drafts(id TEXT PRIMARY KEY, revision INTEGER NOT NULL CHECK(revision > 0));
                    CREATE TABLE revisions(
                        draft_id TEXT NOT NULL REFERENCES drafts(id) ON DELETE CASCADE,
                        revision INTEGER NOT NULL CHECK(revision > 0), title TEXT NOT NULL, payload BLOB NOT NULL,
                        PRIMARY KEY(draft_id, revision));
                    PRAGMA user_version = 1;
                    """)
            }
            if version < 2 {
                try db.exec("ALTER TABLE revisions ADD COLUMN restored_from INTEGER")
                try fault(.duringMigration)
                try db.exec("PRAGMA user_version = 2")
            }
            if version < 3 {
                try db.exec("CREATE TABLE retired_drafts(id TEXT PRIMARY KEY)")
                try fault(.duringMigration)
                try db.exec("PRAGMA user_version = 3")
            }
            try db.exec("COMMIT")
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
        if let maximumPages {
            guard maximumPages > 0 else { throw DraftStoreError.invalidDraft }
            try db.exec("PRAGMA max_page_count = \(maximumPages)")
        }
        self.db = db; self.fault = fault
    }

    /// nil expectedRevision means create only. Existing drafts require exact CAS.
    @discardableResult
    public func save(id: UUID, expectedRevision: Int?, title: String, payload: Data) throws -> DraftRecord {
        try transaction { try write(id: id, expected: expectedRevision, title: title, payload: payload, restored: nil) }
    }

    public func read(id: UUID) throws -> DraftRecord {
        let stmt = try db.prepare("""
            SELECT d.id, r.revision, r.title, r.payload, r.restored_from FROM drafts d
            LEFT JOIN revisions r ON r.draft_id=d.id AND r.revision=d.revision WHERE d.id=?
            """)
        defer { sqlite3_finalize(stmt) }
        try bind(id.uuidString, at: 1, to: stmt)
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE { throw DraftStoreError.missing }
        guard result == SQLITE_ROW else { throw DraftStoreError.database(result) }
        return try decode(stmt)
    }

    /// Stable ID ordering and bounded pages. Offset counts unreadable rows too.
    public func list(limit: Int = 100, offset: Int = 0) throws -> DraftPage {
        guard (1...500).contains(limit), offset >= 0 else { throw DraftStoreError.invalidDraft }
        let stmt = try db.prepare("""
            SELECT d.id, r.revision, r.title, r.payload, r.restored_from FROM drafts d
            LEFT JOIN revisions r ON r.draft_id=d.id AND r.revision=d.revision ORDER BY d.id LIMIT ? OFFSET ?
            """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(limit)); sqlite3_bind_int64(stmt, 2, Int64(offset))
        return try page(stmt)
    }

    public func history(id: UUID, limit: Int = 100, offset: Int = 0) throws -> DraftPage {
        guard (1...500).contains(limit), offset >= 0 else { throw DraftStoreError.invalidDraft }
        let stmt = try db.prepare("""
            SELECT draft_id, revision, title, payload, restored_from FROM revisions
            WHERE draft_id=? ORDER BY revision DESC LIMIT ? OFFSET ?
            """)
        defer { sqlite3_finalize(stmt) }
        try bind(id.uuidString, at: 1, to: stmt)
        sqlite3_bind_int64(stmt, 2, Int64(limit)); sqlite3_bind_int64(stmt, 3, Int64(offset))
        return try page(stmt)
    }

    @discardableResult
    public func rename(id: UUID, expectedRevision: Int, title: String) throws -> DraftRecord {
        try transaction {
            let prior = try read(id: id)
            return try write(id: id, expected: expectedRevision, title: title, payload: prior.payload, restored: nil)
        }
    }

    /// Restoration appends history; a stale undo cannot overwrite a newer edit.
    @discardableResult
    public func restore(id: UUID, revision: Int, expectedRevision: Int) throws -> DraftRecord {
        try transaction {
            let stmt = try db.prepare("""
                SELECT draft_id, revision, title, payload, restored_from FROM revisions
                WHERE draft_id=? AND revision=?
                """)
            defer { sqlite3_finalize(stmt) }
            try bind(id.uuidString, at: 1, to: stmt); sqlite3_bind_int64(stmt, 2, Int64(revision))
            let result = sqlite3_step(stmt)
            guard result == SQLITE_ROW else {
                if result == SQLITE_DONE { throw DraftStoreError.missing }
                throw DraftStoreError.database(result)
            }
            let old = try decode(stmt)
            return try write(id: id, expected: expectedRevision, title: old.title, payload: old.payload, restored: revision)
        }
    }

    /// Duplicate preserves local editor bytes, creates a distinct ID and no current analysis.
    public func duplicate(id: UUID, expectedRevision: Int, newID: UUID = UUID()) throws -> DraftRecord {
        try transaction {
            let prior = try read(id: id)
            guard prior.revision == expectedRevision else { throw DraftStoreError.conflict }
            return try write(id: newID, expected: nil, title: prior.title, payload: prior.payload, restored: nil)
        }
    }

    public func delete(id: UUID, expectedRevision: Int) throws {
        try transaction {
            let prior = try read(id: id)
            guard prior.revision == expectedRevision else { throw DraftStoreError.conflict }
            let tombstone = try db.prepare("INSERT INTO retired_drafts(id) VALUES(?)")
            defer { sqlite3_finalize(tombstone) }
            try bind(id.uuidString, at: 1, to: tombstone); try done(tombstone)
            let stmt = try db.prepare("DELETE FROM drafts WHERE id=?")
            defer { sqlite3_finalize(stmt) }
            try bind(id.uuidString, at: 1, to: stmt); try done(stmt)
        }
    }

    private func transaction<T>(_ action: () throws -> T) throws -> T {
        try db.exec("BEGIN IMMEDIATE")
        do {
            let result = try action()
            try fault(.beforeCommit)
            try db.exec("COMMIT")
            return result
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
    }

    private func write(id: UUID, expected: Int?, title: String, payload: Data, restored: Int?) throws -> DraftRecord {
        try Self.validate(title: title, payload: payload)
        let current: DraftRecord?
        do { current = try read(id: id) } catch DraftStoreError.missing { current = nil }
        guard current?.revision == expected else { throw DraftStoreError.conflict }
        if current == nil {
            let retired = try db.prepare("SELECT 1 FROM retired_drafts WHERE id=?")
            defer { sqlite3_finalize(retired) }
            try bind(id.uuidString, at: 1, to: retired)
            let code = sqlite3_step(retired)
            if code == SQLITE_ROW { throw DraftStoreError.conflict }
            guard code == SQLITE_DONE else { throw DraftStoreError.database(code) }
        }
        let oldRevision = current?.revision ?? 0
        guard oldRevision < Int.max else { throw DraftStoreError.invalidDraft }
        let next = oldRevision + 1
        guard restored.map({ $0 > 0 && $0 < next }) ?? true else { throw DraftStoreError.corruptRecord }
        let head = try db.prepare(current == nil ? "INSERT INTO drafts(revision,id) VALUES(?,?)" : "UPDATE drafts SET revision=? WHERE id=?")
        defer { sqlite3_finalize(head) }
        sqlite3_bind_int64(head, 1, Int64(next)); try bind(id.uuidString, at: 2, to: head); try done(head)
        let stmt = try db.prepare("INSERT INTO revisions(draft_id,revision,title,payload,restored_from) VALUES(?,?,?,?,?)")
        defer { sqlite3_finalize(stmt) }
        try bind(id.uuidString, at: 1, to: stmt); sqlite3_bind_int64(stmt, 2, Int64(next))
        try bind(title, at: 3, to: stmt)
        let code = payload.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(payload.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard code == SQLITE_OK else { throw DraftStoreError.database(code) }
        if let restored { sqlite3_bind_int64(stmt, 5, Int64(restored)) }
        else { sqlite3_bind_null(stmt, 5) }
        try done(stmt); try fault(.afterHistoryWrite)
        return DraftRecord(id: id, revision: next, title: title, payload: payload, restoredFrom: restored)
    }

    private static func validate(title: String, payload: Data) throws {
        guard title.utf8.count <= 1024, !title.contains("\0"), !payload.isEmpty,
              payload.count <= maximumPayloadBytes,
              (try? JSONSerialization.jsonObject(with: payload)) is [String: Any] else {
            throw DraftStoreError.invalidDraft
        }
    }
    private func decode(_ stmt: OpaquePointer) throws -> DraftRecord {
        guard sqlite3_column_type(stmt, 0) == SQLITE_TEXT,
              sqlite3_column_type(stmt, 1) == SQLITE_INTEGER,
              sqlite3_column_type(stmt, 2) == SQLITE_TEXT,
              sqlite3_column_type(stmt, 3) == SQLITE_BLOB,
              let rawID = sqlite3_column_text(stmt, 0), let titleBytes = sqlite3_column_text(stmt, 2),
              let idText = String(bytes: UnsafeBufferPointer(start: rawID, count: Int(sqlite3_column_bytes(stmt, 0))), encoding: .utf8),
              let id = UUID(uuidString: idText), idText == id.uuidString,
              let bytes = sqlite3_column_blob(stmt, 3) else { throw DraftStoreError.corruptRecord }
        let length = Int(sqlite3_column_bytes(stmt, 3))
        guard length > 0, length <= Self.maximumPayloadBytes else { throw DraftStoreError.corruptRecord }
        let payload = Data(bytes: bytes, count: length)
        guard let title = String(bytes: UnsafeBufferPointer(start: titleBytes, count: Int(sqlite3_column_bytes(stmt, 2))), encoding: .utf8) else {
            throw DraftStoreError.corruptRecord
        }
        let revision = Int(sqlite3_column_int64(stmt, 1))
        guard [SQLITE_NULL, SQLITE_INTEGER].contains(sqlite3_column_type(stmt, 4)) else { throw DraftStoreError.corruptRecord }
        let restored = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, 4))
        guard revision > 0, restored.map({ $0 > 0 && $0 < revision }) ?? true else { throw DraftStoreError.corruptRecord }
        do { try Self.validate(title: title, payload: payload) } catch { throw DraftStoreError.corruptRecord }
        return DraftRecord(id: id, revision: revision, title: title, payload: payload, restoredFrom: restored)
    }
    private func page(_ stmt: OpaquePointer) throws -> DraftPage {
        var records: [DraftRecord] = []; var unreadable = 0
        while true {
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw DraftStoreError.database(result) }
            do { records.append(try decode(stmt)) }
            catch DraftStoreError.corruptRecord { unreadable += 1 }
        }
        return DraftPage(records: records, unreadableCount: unreadable)
    }
    private func bind(_ text: String, at index: Int32, to statement: OpaquePointer) throws {
        let result = text.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard result == SQLITE_OK else { throw DraftStoreError.database(result) }
    }
    private func done(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw DraftStoreError.database(result) }
    }
}
