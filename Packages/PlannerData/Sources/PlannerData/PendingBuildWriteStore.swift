import Foundation
import CSQLite

/// Diagnostics contain no request bodies, identifiers, credentials, SQL or paths.
public enum PendingWriteError: Error, Equatable, Sendable {
    case database(Int32), unsupportedSchema(Int), foreignDatabase, corruptRecord
    case invalidIntent, identityConflict, capacityExceeded, staleSession, missing, blocked, notPending
}

/// A caller-supplied local isolation label, not a credential or proof of server authority.
/// Equality uses the original UTF-8 bytes, including canonically equivalent spellings.
public struct PendingWritePartition: Equatable, Sendable {
    fileprivate let environmentBytes: Data
    fileprivate let authorityBytes: Data
    public var environment: String { String(decoding: environmentBytes, as: UTF8.self) }
    public var authority: String { String(decoding: authorityBytes, as: UTF8.self) }

    public init(environment: String, authority: String) throws {
        try self.init(environmentBytes: Data(environment.utf8), authorityBytes: Data(authority.utf8))
    }

    fileprivate init(environmentBytes: Data, authorityBytes: Data) throws {
        guard validQueueIdentifier(environmentBytes), validQueueIdentifier(authorityBytes) else {
            throw PendingWriteError.invalidIntent
        }
        self.environmentBytes = environmentBytes
        self.authorityBytes = authorityBytes
    }
}

public enum PendingBuildWriteMethod: Int64, Equatable, Sendable { case create = 1, update = 2 }

/// The governed service adapter must validate the BuildSnapshot before enqueueing.
/// This value snapshots bytes; it does not parse, repair or rewrite that contract.
public struct PendingBuildWrite: Equatable, Sendable {
    public static let maximumBodyBytes = 1_048_576
    fileprivate let operationBytes: Data
    fileprivate let buildBytes: Data
    fileprivate let keyBytes: Data
    fileprivate let preconditionBytes: Data?
    public let method: PendingBuildWriteMethod
    public let body: Data
    public var operationID: String { String(decoding: operationBytes, as: UTF8.self) }
    public var buildID: String { String(decoding: buildBytes, as: UTF8.self) }
    public var idempotencyKey: String { String(decoding: keyBytes, as: UTF8.self) }
    public var ifMatch: String? { preconditionBytes.map { String(decoding: $0, as: UTF8.self) } }

    public init(operationID: String, method: PendingBuildWriteMethod, buildID: String,
                idempotencyKey: String, ifMatch: String? = nil, body: Data) throws {
        try self.init(operationBytes: Data(operationID.utf8), method: method,
                      buildBytes: Data(buildID.utf8), keyBytes: Data(idempotencyKey.utf8),
                      preconditionBytes: ifMatch.map { Data($0.utf8) }, body: body)
    }

    fileprivate init(operationBytes: Data, method: PendingBuildWriteMethod, buildBytes: Data,
                     keyBytes: Data, preconditionBytes: Data?, body: Data) throws {
        guard validQueueIdentifier(operationBytes), validQueueIdentifier(buildBytes),
              validQueueIdentifier(keyBytes), !body.isEmpty, body.count <= Self.maximumBodyBytes else {
            throw PendingWriteError.invalidIntent
        }
        switch method {
        case .create:
            guard preconditionBytes == nil else { throw PendingWriteError.invalidIntent }
        case .update:
            // The frozen API requires a quoted current revision, not a wildcard
            // or weak ETag. Preserve its digits without integer conversion.
            guard let bytes = preconditionBytes, bytes.count >= 3, bytes.count <= 1024,
                  bytes.first == 34, bytes.last == 34,
                  bytes.dropFirst().dropLast().allSatisfy({ (48...57).contains($0) }),
                  bytes[bytes.index(after: bytes.startIndex)] != 48 else {
                throw PendingWriteError.invalidIntent
            }
        }
        self.operationBytes = operationBytes
        self.method = method
        self.buildBytes = buildBytes
        self.keyBytes = keyBytes
        self.preconditionBytes = preconditionBytes
        // Detach even Data backed by caller-owned NSMutableData/no-copy storage.
        self.body = body.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
    }
}

private func validQueueIdentifier(_ bytes: Data) -> Bool {
    !bytes.isEmpty && bytes.count <= 1024 && String(data: bytes, encoding: .utf8) != nil
        && bytes.allSatisfy { $0 >= 32 && $0 != 127 }
}

/// Growth limits are local resource bounds, not a service retention/expiry policy.
/// Existing records are never evicted to make room, including confirmed records.
public struct PendingWriteLimits: Sendable {
    public let maximumRecords: Int
    public let maximumTotalBodyBytes: Int
    public init(maximumRecords: Int = 256, maximumTotalBodyBytes: Int = 16_777_216) throws {
        guard (1...4096).contains(maximumRecords), (1...67_108_864).contains(maximumTotalBodyBytes) else {
            throw PendingWriteError.invalidIntent
        }
        self.maximumRecords = maximumRecords
        self.maximumTotalBodyBytes = maximumTotalBodyBytes
    }
}

public enum PendingWriteState: Int64, Equatable, Sendable {
    case pending = 0, attempting, confirmed, conflict, invalid, uncertain
}

/// Supplied only by an adapter that has validated the response for this exact attempt.
/// An HTTP status alone, a timeout, or a missing receipt is not remote confirmation.
public enum PendingWriteOutcome: Sendable { case confirmed, conflict, invalid, uncertain }

public struct PendingWriteRecord: Equatable, Sendable {
    public let sequence: Int64
    public let partition: PendingWritePartition
    public let write: PendingBuildWrite
    public let state: PendingWriteState
    public let attemptID: UUID?
    fileprivate let attemptGeneration: UUID?
}

/// Only explicit activation issues a token. Opening a database never activates it.
public struct PendingWriteSession: Equatable, Sendable {
    public let partition: PendingWritePartition
    fileprivate let generation: UUID
    fileprivate let instance: UUID
}

/// Obtained after the durable attempt transition commits, before any future network handoff.
public struct PendingWriteAttempt: Equatable, Sendable {
    public let partition: PendingWritePartition
    public let write: PendingBuildWrite
    public let attemptID: UUID
    fileprivate let generation: UUID
    fileprivate let instance: UUID
}

package enum PendingWriteFaultPoint: Equatable, Sendable {
    case beforeActivationCommit, beforeEnqueueCommit, beforeAttemptCommit
    case beforeOutcomeCommit, beforeDeactivationCommit
}

// A separate application ID prevents a draft or unrelated SQLite file being
// adopted as a queue. There is no migration from another library's schema.
private let queueApplicationID = 0x50595131
private let queueSessionSQL = """
CREATE TABLE queue_session (
    id INTEGER PRIMARY KEY CHECK(id = 1),
    environment BLOB, authority BLOB, generation BLOB
)
"""
private let queueWritesSQL = """
CREATE TABLE queue_writes (
    sequence INTEGER PRIMARY KEY CHECK(sequence > 0),
    operation_id BLOB NOT NULL UNIQUE, environment BLOB NOT NULL, authority BLOB NOT NULL,
    method INTEGER NOT NULL, build_id BLOB NOT NULL, idempotency_key BLOB NOT NULL UNIQUE,
    precondition BLOB, body BLOB NOT NULL, state INTEGER NOT NULL,
    attempt_id BLOB, attempt_generation BLOB
)
"""

// Exclusively actor-owned after initialization, including all prepared statements.
private final class PendingWriteConnection: @unchecked Sendable {
    let handle: OpaquePointer
    init(path: String) throws {
        var pointer: OpaquePointer?
        let code = sqlite3_open_v2(path, &pointer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw PendingWriteError.database(code)
        }
        let configuration = planner_sqlite_disable_checkpoint_on_close(pointer)
        guard configuration == SQLITE_OK else {
            sqlite3_close(pointer)
            throw PendingWriteError.database(configuration)
        }
        let timeout = sqlite3_busy_timeout(pointer, 2_000)
        guard timeout == SQLITE_OK else {
            sqlite3_close(pointer)
            throw PendingWriteError.database(timeout)
        }
        handle = pointer
    }
    deinit { sqlite3_close(handle) }
    func exec(_ sql: String) throws {
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw PendingWriteError.database(code) }
    }
    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw PendingWriteError.database(code) }
        return statement
    }
    func scalar(_ sql: String) throws -> Int64 {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_INTEGER else {
            throw PendingWriteError.database(code)
        }
        return sqlite3_column_int64(statement, 0)
    }
    func bind(_ data: Data?, at index: Int32, to statement: OpaquePointer) throws {
        let code: Int32
        if let data {
            code = data.withUnsafeBytes {
                sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count),
                                  unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        } else { code = sqlite3_bind_null(statement, index) }
        guard code == SQLITE_OK else { throw PendingWriteError.database(code) }
    }
    func bind(_ value: Int64, at index: Int32, to statement: OpaquePointer) throws {
        let code = sqlite3_bind_int64(statement, index, value)
        guard code == SQLITE_OK else { throw PendingWriteError.database(code) }
    }
    func done(_ statement: OpaquePointer) throws {
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else { throw PendingWriteError.database(code) }
    }
    /// This may perform ordinary SQLite hot-journal recovery before reading.
    /// It performs no application write or journal reconfiguration on rejection.
    func admit(allowEmpty: Bool) throws -> Bool {
        let version = try scalar("PRAGMA user_version")
        let applicationID = try scalar("PRAGMA application_id")
        guard version == 0 || version == 1 else { throw PendingWriteError.unsupportedSchema(Int(version)) }
        let statement = try prepare("SELECT type, name, sql FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*' ORDER BY name")
        defer { sqlite3_finalize(statement) }
        var objects: [(Data, Data, Data)] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw PendingWriteError.database(code) }
            guard objects.count < 2 else { throw PendingWriteError.foreignDatabase }
            var columns: [Data] = []
            for index in Int32(0)...Int32(2) {
                guard sqlite3_column_type(statement, index) == SQLITE_TEXT,
                      let bytes = sqlite3_column_text(statement, index) else { throw PendingWriteError.foreignDatabase }
                columns.append(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index))))
            }
            objects.append((columns[0], columns[1], columns[2]))
        }
        if version == 0, applicationID == 0, objects.isEmpty, allowEmpty { return true }
        guard version == 1, applicationID == Int64(queueApplicationID), objects.count == 2,
              objects[0].0 == Data("table".utf8), objects[0].1 == Data("queue_session".utf8),
              objects[0].2 == Data(queueSessionSQL.utf8),
              objects[1].0 == Data("table".utf8), objects[1].1 == Data("queue_writes".utf8),
              objects[1].2 == Data(queueWritesSQL.utf8) else { throw PendingWriteError.foreignDatabase }
        return false
    }
}

/// A bounded, local intent journal. It makes no HTTP request, stores no credentials,
/// and grants no server authority. Use a separate app-owned protected database file.
/// An uncertain operation cannot be resent by this API: receipt lifetime and remote
/// reconciliation must be accepted before an adapter can add such a transition.
public actor PendingBuildWriteStore {
    private let db: PendingWriteConnection
    private let instance = UUID()
    private let limits: PendingWriteLimits
    private let fault: @Sendable (PendingWriteFaultPoint) throws -> Void

    public init(url: URL, limits: PendingWriteLimits? = nil) throws {
        try self.init(url: url, limits: limits, fault: { _ in })
    }

    package init(url: URL, limits: PendingWriteLimits? = nil, maximumPages: Int? = nil,
                 fault: @escaping @Sendable (PendingWriteFaultPoint) throws -> Void) throws {
        guard url.isFileURL, !url.path.utf8.contains(0), maximumPages.map({ $0 > 0 }) ?? true else {
            throw PendingWriteError.invalidIntent
        }
        let selectedLimits: PendingWriteLimits
        if let limits { selectedLimits = limits } else { selectedLimits = try PendingWriteLimits() }
        let db = try PendingWriteConnection(path: url.path)
        _ = try db.admit(allowEmpty: true)
        try db.exec("PRAGMA journal_mode = DELETE; PRAGMA synchronous = FULL;")
        try db.exec("BEGIN IMMEDIATE")
        do {
            if try db.admit(allowEmpty: true) {
                try db.exec(queueSessionSQL)
                try db.exec(queueWritesSQL)
                try db.exec("INSERT INTO queue_session(id) VALUES(1)")
                try db.exec("PRAGMA application_id = \(queueApplicationID); PRAGMA user_version = 1;")
            }
            try db.exec("COMMIT")
        } catch {
            if sqlite3_get_autocommit(db.handle) == 0 { try? db.exec("ROLLBACK") }
            throw error
        }
        if let maximumPages { try db.exec("PRAGMA max_page_count = \(maximumPages)") }
        self.db = db
        self.limits = selectedLimits
        self.fault = fault
    }

    /// An explicit caller lifecycle action. Atomically supersedes every older
    /// generation, even when the caller returns to the same partition later.
    public func activate(_ partition: PendingWritePartition) throws -> PendingWriteSession {
        try transaction {
            _ = try allRecords()
            try db.exec("UPDATE queue_writes SET state = 5 WHERE state = 1")
            let generation = UUID()
            let statement = try db.prepare("UPDATE queue_session SET environment=?, authority=?, generation=? WHERE id=1")
            defer { sqlite3_finalize(statement) }
            try db.bind(partition.environmentBytes, at: 1, to: statement)
            try db.bind(partition.authorityBytes, at: 2, to: statement)
            try db.bind(Data(generation.uuidString.utf8), at: 3, to: statement)
            try db.done(statement)
            try fault(.beforeActivationCommit)
            return PendingWriteSession(partition: partition, generation: generation, instance: instance)
        }
    }

    public func deactivate(_ session: PendingWriteSession) throws {
        try transaction {
            try require(session)
            _ = try allRecords()
            try db.exec("UPDATE queue_writes SET state = 5 WHERE state = 1")
            try db.exec("UPDATE queue_session SET environment=NULL, authority=NULL, generation=NULL WHERE id=1")
            try fault(.beforeDeactivationCommit)
        }
    }

    /// A duplicate is accepted only when every intent byte and partition matches.
    /// This check precedes capacity enforcement and returns no foreign payload.
    @discardableResult
    public func enqueue(_ write: PendingBuildWrite, session: PendingWriteSession) throws -> PendingWriteRecord {
        try transaction {
            try require(session)
            let records = try allRecords()
            if let duplicate = records.first(where: {
                $0.write.operationBytes == write.operationBytes || $0.write.keyBytes == write.keyBytes
            }) {
                guard duplicate.partition == session.partition, duplicate.write == write else {
                    throw PendingWriteError.identityConflict
                }
                return duplicate
            }
            let total = records.reduce(0) { $0 + $1.write.body.count }
            guard records.count < limits.maximumRecords,
                  write.body.count <= limits.maximumTotalBodyBytes - min(total, limits.maximumTotalBodyBytes),
                  (records.last?.sequence ?? 0) < Int64.max else { throw PendingWriteError.capacityExceeded }
            let sequence = (records.last?.sequence ?? 0) + 1
            let statement = try db.prepare("""
                INSERT INTO queue_writes(sequence,operation_id,environment,authority,method,build_id,
                    idempotency_key,precondition,body,state) VALUES(?,?,?,?,?,?,?,?,?,0)
                """)
            defer { sqlite3_finalize(statement) }
            try db.bind(sequence, at: 1, to: statement)
            try db.bind(write.operationBytes, at: 2, to: statement)
            try db.bind(session.partition.environmentBytes, at: 3, to: statement)
            try db.bind(session.partition.authorityBytes, at: 4, to: statement)
            try db.bind(write.method.rawValue, at: 5, to: statement)
            try db.bind(write.buildBytes, at: 6, to: statement)
            try db.bind(write.keyBytes, at: 7, to: statement)
            try db.bind(write.preconditionBytes, at: 8, to: statement)
            try db.bind(write.body, at: 9, to: statement)
            try db.done(statement)
            try fault(.beforeEnqueueCommit)
            return PendingWriteRecord(sequence: sequence, partition: session.partition, write: write,
                                      state: .pending, attemptID: nil, attemptGeneration: nil)
        }
    }

    /// Bounded by the absolute schema limits. Any unreadable row fails the whole
    /// read/dispatch; no predecessor can disappear through best-effort decoding.
    public func records(session: PendingWriteSession) throws -> [PendingWriteRecord] {
        try transaction(write: false) {
            try require(session)
            return try allRecords().filter { $0.partition == session.partition }
        }
    }

    public func beginAttempt(operationID: String, session: PendingWriteSession) throws -> PendingWriteAttempt {
        let identity = Data(operationID.utf8)
        guard validQueueIdentifier(identity) else { throw PendingWriteError.invalidIntent }
        return try transaction {
            try require(session)
            let records = try allRecords()
            guard let record = records.first(where: {
                $0.partition == session.partition && $0.write.operationBytes == identity
            }) else { throw PendingWriteError.missing }
            guard record.state == .pending else { throw PendingWriteError.notPending }
            guard !records.contains(where: {
                $0.partition == record.partition && $0.write.buildBytes == record.write.buildBytes
                    && $0.sequence < record.sequence && $0.state != .confirmed
            }) else { throw PendingWriteError.blocked }
            let attempt = UUID()
            let statement = try db.prepare("UPDATE queue_writes SET state=1, attempt_id=?, attempt_generation=? WHERE sequence=?")
            defer { sqlite3_finalize(statement) }
            try db.bind(Data(attempt.uuidString.utf8), at: 1, to: statement)
            try db.bind(Data(session.generation.uuidString.utf8), at: 2, to: statement)
            try db.bind(record.sequence, at: 3, to: statement)
            try db.done(statement)
            try fault(.beforeAttemptCommit)
            return PendingWriteAttempt(partition: record.partition, write: record.write, attemptID: attempt,
                                       generation: session.generation, instance: instance)
        }
    }

    /// False means a stale, foreign, or already consumed callback; it changes no row.
    /// There is no automatic retry, deletion, precondition refresh or request rewrite.
    @discardableResult
    public func recordOutcome(_ outcome: PendingWriteOutcome, for attempt: PendingWriteAttempt) throws -> Bool {
        guard attempt.instance == instance else { return false }
        return try transaction {
            guard let active = try activePartition(), active.0 == attempt.partition,
                  active.1 == attempt.generation else { return false }
            let records = try allRecords()
            guard let record = records.first(where: {
                $0.partition == attempt.partition && $0.write.operationBytes == attempt.write.operationBytes
            }), record.state == .attempting, record.write == attempt.write,
                record.attemptID == attempt.attemptID, record.attemptGeneration == attempt.generation else { return false }
            let state: PendingWriteState
            switch outcome {
            case .confirmed: state = .confirmed
            case .conflict: state = .conflict
            case .invalid: state = .invalid
            case .uncertain: state = .uncertain
            }
            let statement = try db.prepare("UPDATE queue_writes SET state=? WHERE sequence=?")
            defer { sqlite3_finalize(statement) }
            try db.bind(state.rawValue, at: 1, to: statement)
            try db.bind(record.sequence, at: 2, to: statement)
            try db.done(statement)
            try fault(.beforeOutcomeCommit)
            return true
        }
    }

    private func transaction<T>(write: Bool = true, _ action: () throws -> T) throws -> T {
        try db.exec(write ? "BEGIN IMMEDIATE" : "BEGIN")
        do {
            _ = try db.admit(allowEmpty: false)
            let result = try action()
            try db.exec("COMMIT")
            return result
        } catch {
            if sqlite3_get_autocommit(db.handle) == 0 { try? db.exec("ROLLBACK") }
            throw error
        }
    }

    private func require(_ session: PendingWriteSession) throws {
        guard session.instance == instance, let active = try activePartition(),
              active.0 == session.partition, active.1 == session.generation else { throw PendingWriteError.staleSession }
    }

    private func activePartition() throws -> (PendingWritePartition, UUID)? {
        let statement = try db.prepare("SELECT id, environment, authority, generation FROM queue_session")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_INTEGER,
              sqlite3_column_int64(statement, 0) == 1 else { throw PendingWriteError.corruptRecord }
        let environment = try blob(statement, 1, optional: true, maximum: 1024)
        let authority = try blob(statement, 2, optional: true, maximum: 1024)
        let generation = try blob(statement, 3, optional: true, maximum: 36)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PendingWriteError.corruptRecord }
        if environment == nil, authority == nil, generation == nil { return nil }
        guard let environment, let authority, let generation else { throw PendingWriteError.corruptRecord }
        do {
            return (try PendingWritePartition(environmentBytes: environment, authorityBytes: authority),
                    try uuid(generation))
        } catch { throw PendingWriteError.corruptRecord }
    }

    private func allRecords() throws -> [PendingWriteRecord] {
        let active = try activePartition()
        let statement = try db.prepare("""
            SELECT sequence, operation_id, environment, authority, method, build_id, idempotency_key,
                   precondition, body, state, attempt_id, attempt_generation FROM queue_writes ORDER BY sequence
            """)
        defer { sqlite3_finalize(statement) }
        var records: [PendingWriteRecord] = []
        var totalBytes = 0
        var operations = Set<Data>()
        var keys = Set<Data>()
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw PendingWriteError.database(code) }
            guard records.count < 4096, sqlite3_column_type(statement, 0) == SQLITE_INTEGER,
                  sqlite3_column_type(statement, 4) == SQLITE_INTEGER,
                  sqlite3_column_type(statement, 9) == SQLITE_INTEGER,
                  let method = PendingBuildWriteMethod(rawValue: sqlite3_column_int64(statement, 4)),
                  let state = PendingWriteState(rawValue: sqlite3_column_int64(statement, 9)) else {
                throw PendingWriteError.corruptRecord
            }
            let sequence = sqlite3_column_int64(statement, 0)
            guard sequence > (records.last?.sequence ?? 0) else { throw PendingWriteError.corruptRecord }
            let operation = try requiredBlob(statement, 1)
            let environment = try requiredBlob(statement, 2)
            let authority = try requiredBlob(statement, 3)
            let build = try requiredBlob(statement, 5)
            let key = try requiredBlob(statement, 6)
            let precondition = try blob(statement, 7, optional: true, maximum: 1024)
            let body = try requiredBlob(statement, 8, maximum: PendingBuildWrite.maximumBodyBytes)
            let attemptBytes = try blob(statement, 10, optional: true, maximum: 36)
            let generationBytes = try blob(statement, 11, optional: true, maximum: 36)
            guard operations.insert(operation).inserted, keys.insert(key).inserted else {
                throw PendingWriteError.corruptRecord
            }
            let partition: PendingWritePartition
            let intent: PendingBuildWrite
            do {
                partition = try PendingWritePartition(environmentBytes: environment, authorityBytes: authority)
                intent = try PendingBuildWrite(operationBytes: operation, method: method, buildBytes: build,
                                               keyBytes: key, preconditionBytes: precondition, body: body)
            } catch { throw PendingWriteError.corruptRecord }
            totalBytes += body.count
            guard totalBytes <= 67_108_864 else { throw PendingWriteError.corruptRecord }
            let attempt = try attemptBytes.map { try uuid($0) }
            let generation = try generationBytes.map { try uuid($0) }
            if state == .pending {
                guard attempt == nil, generation == nil else { throw PendingWriteError.corruptRecord }
            } else {
                guard attempt != nil, generation != nil else { throw PendingWriteError.corruptRecord }
            }
            if state == .attempting {
                guard let active, active.0 == partition, active.1 == generation else { throw PendingWriteError.corruptRecord }
            }
            records.append(PendingWriteRecord(sequence: sequence, partition: partition, write: intent,
                                             state: state, attemptID: attempt, attemptGeneration: generation))
        }
        return records
    }

    private func requiredBlob(_ statement: OpaquePointer, _ index: Int32, maximum: Int = 1024) throws -> Data {
        guard let data = try blob(statement, index, optional: false, maximum: maximum) else {
            throw PendingWriteError.corruptRecord
        }
        return data
    }
    private func blob(_ statement: OpaquePointer, _ index: Int32, optional: Bool, maximum: Int) throws -> Data? {
        let type = sqlite3_column_type(statement, index)
        if optional, type == SQLITE_NULL { return nil }
        // Check the storage class before any conversion-capable column accessor.
        guard type == SQLITE_BLOB, let bytes = sqlite3_column_blob(statement, index) else {
            throw PendingWriteError.corruptRecord
        }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, count <= maximum else { throw PendingWriteError.corruptRecord }
        return Data(bytes: bytes, count: count)
    }
    private func uuid(_ bytes: Data) throws -> UUID {
        guard bytes.count == 36, let text = String(data: bytes, encoding: .utf8),
              let value = UUID(uuidString: text), Data(value.uuidString.utf8) == bytes else {
            throw PendingWriteError.corruptRecord
        }
        return value
    }
}
