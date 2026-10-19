import CSQLite
import Foundation
import XCTest
@testable import PlannerData

private struct MigrationCorpus: Decodable {
    let fixtureVersion: String
    let canonicalBuildSHA256: String
    let cases: [MigrationCase]
    let unsupportedStorageVersions: [Int]
}

private struct MigrationCase: Decodable {
    let id: String
    let storageVersion: Int
    let draftID: UUID
    let headRevision: Int
    let records: [MigrationRecord]
    let retiredIDs: [UUID]
    let expectedStorageVersion: Int
}

private struct MigrationRecord: Decodable {
    let revision: Int
    let title: String
    let payloadJSON: String
    let restoredFrom: Int?
}

private enum FixtureError: Error { case sqlite(Int32), shape }

// Storage initialization invokes its synchronous fault callback on one connection.
// The lock also makes the counter's Sendable promise explicit for the test hook.
private final class MigrationFault: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let target: Int
    init(target: Int) { self.target = target }
    func next() -> Bool {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count == target
    }
}

final class MigrationFixtureTests: XCTestCase, @unchecked Sendable {
    private func corpus() throws -> MigrationCorpus {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "migration-cases", withExtension: "json"))
        let corpus = try JSONDecoder().decode(MigrationCorpus.self, from: Data(contentsOf: url))
        XCTAssertEqual(corpus.fixtureVersion, "apple-local-migrations-1")
        XCTAssertEqual(corpus.cases.count, 6)
        XCTAssertEqual(Set(corpus.cases.map(\.id)).count, 6)
        XCTAssertEqual(corpus.unsupportedStorageVersions, [-1, 4, 99])
        return corpus
    }

    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("fixture.sqlite")
    }

    private func database<T>(_ url: URL, _ operation: (OpaquePointer) throws -> T) throws -> T {
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard code == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw FixtureError.sqlite(code)
        }
        defer { sqlite3_close(handle) }
        return try operation(handle)
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw FixtureError.sqlite(code) }
    }

    private func scalar(_ url: URL, _ sql: String) throws -> Int {
        try database(url) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw FixtureError.shape
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw FixtureError.shape }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }

    private func seed(_ vector: MigrationCase, at url: URL) throws {
        guard (1...3).contains(vector.storageVersion), vector.expectedStorageVersion == 3,
              !vector.records.isEmpty, vector.records.last?.revision == vector.headRevision else {
            throw FixtureError.shape
        }
        try database(url) { db in
            try execute(db, """
                PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL;
                CREATE TABLE drafts(id TEXT PRIMARY KEY, revision INTEGER NOT NULL);
                CREATE TABLE revisions(draft_id TEXT NOT NULL REFERENCES drafts(id) ON DELETE CASCADE,
                  revision INTEGER NOT NULL, title TEXT NOT NULL, payload BLOB NOT NULL,
                  PRIMARY KEY(draft_id, revision));
                """)
            if vector.storageVersion >= 2 { try execute(db, "ALTER TABLE revisions ADD COLUMN restored_from INTEGER") }
            if vector.storageVersion == 3 { try execute(db, "CREATE TABLE retired_drafts(id TEXT PRIMARY KEY)") }
            try execute(db, "INSERT INTO drafts VALUES(\(quoted(vector.draftID.uuidString)),\(vector.headRevision))")
            for record in vector.records {
                let bytes = Data(record.payloadJSON.utf8).map { String(format: "%02x", $0) }.joined()
                let restored = record.restoredFrom.map(String.init) ?? "NULL"
                let extra = vector.storageVersion >= 2 ? ",\(restored)" : ""
                try execute(db, "INSERT INTO revisions VALUES(\(quoted(vector.draftID.uuidString)),\(record.revision),\(quoted(record.title)),X'\(bytes)'\(extra))")
            }
            for id in vector.retiredIDs { try execute(db, "INSERT INTO retired_drafts VALUES(\(quoted(id.uuidString)))") }
            try execute(db, "PRAGMA user_version=\(vector.storageVersion)")
        }
    }

    private func matches(_ actual: DraftRecord, _ expected: MigrationRecord, id: UUID) -> Bool {
        actual.id == id && actual.revision == expected.revision && actual.title == expected.title &&
        actual.payload == Data(expected.payloadJSON.utf8) && actual.restoredFrom == expected.restoredFrom &&
        !actual.analysisIsCurrent
    }

    private func preserved(_ store: DraftStore, vector: MigrationCase) async throws -> Bool {
        let head = try await store.read(id: vector.draftID)
        let history = try await store.history(id: vector.draftID)
        let expected = vector.records.sorted { $0.revision > $1.revision }
        return matches(head, try XCTUnwrap(expected.first), id: vector.draftID) &&
            history.unreadableCount == 0 && history.records.count == expected.count &&
            zip(history.records, expected).allSatisfy { matches($0.0, $0.1, id: vector.draftID) }
    }

    // These are observed fixture results. A receiver must also require the actual
    // command to succeed and all four exact XCTest methods to pass without skips.
    private func receipt(_ id: String, phase: String, values: [String: Bool]) throws {
        let value: [String: Any] = ["fixtureVersion": "apple-local-migrations-1", "id": id,
                                    "phase": phase, "observed": values]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        // Keep each observation on XCTest's diagnostic stream before its method finishes.
        let line = "APPLE_MIGRATION_CASE " + (try XCTUnwrap(String(data: data, encoding: .utf8))) + "\n"
        try FileHandle.standardError.write(contentsOf: Data(line.utf8))
    }

    func testHistoricalFixturesMigrateAndReopenWithoutRewritingPayloads() async throws {
        for vector in try corpus().cases {
            let url = try location(); try seed(vector, at: url)
            let store = try DraftStore(url: url)
            let first = try await preserved(store, vector: vector)
            let reopened = try await preserved(DraftStore(url: url), vector: vector)
            let version = try scalar(url, "PRAGMA user_version") == vector.expectedStorageVersion
            XCTAssertTrue(first, vector.id); XCTAssertTrue(reopened, vector.id); XCTAssertTrue(version, vector.id)
            for id in vector.retiredIDs {
                do { try await store.save(id: id, expectedRevision: nil, title: "delayed", payload: Data("{}".utf8)); XCTFail(vector.id) }
                catch { XCTAssertEqual(error as? DraftStoreError, .conflict, vector.id) }
            }
            try receipt(vector.id, phase: "migration", values: ["originalRecordsPreserved": first,
                         "reopenedRecordsPreserved": reopened, "expectedStorageVersion": version])
        }
    }

    func testInterruptedFixtureMigrationsRollBackEveryStepBeforeRecovery() async throws {
        for vector in try corpus().cases where vector.storageVersion < 3 {
            for point in 1...(3 - vector.storageVersion) {
                let url = try location(); try seed(vector, at: url)
                let original = try Data(contentsOf: url)
                let fault = MigrationFault(target: point)
                XCTAssertThrowsError(try DraftStore(url: url, fault: {
                    if case .duringMigration = $0, fault.next() { throw DraftStoreError.database(SQLITE_IOERR) }
                })) { XCTAssertEqual($0 as? DraftStoreError, .database(SQLITE_IOERR), vector.id) }
                let bytes = try Data(contentsOf: url) == original
                let version = try scalar(url, "PRAGMA user_version") == vector.storageVersion
                XCTAssertTrue(bytes, vector.id); XCTAssertTrue(version, vector.id)
                let recovered = try await preserved(DraftStore(url: url), vector: vector)
                XCTAssertTrue(recovered, vector.id)
                XCTAssertEqual(try scalar(url, "PRAGMA user_version"), 3, vector.id)
                try receipt("\(vector.id)/step-\(point)", phase: "rollback-retry",
                            values: ["originalDatabaseBytesPreserved": bytes, "originalStorageVersion": version,
                                     "recoveredRecordsPreserved": recovered])
            }
        }
    }

    func testFutureStorageVersionsAreRejectedWithoutResetAndOriginalBackupReopens() async throws {
        let corpus = try corpus()
        let vector = try XCTUnwrap(corpus.cases.first { $0.id == "v3-retired-identity" })
        for version in corpus.unsupportedStorageVersions {
            let url = try location(); try seed(vector, at: url)
            let supportedOriginal = try Data(contentsOf: url)
            try database(url) { try execute($0, "PRAGMA user_version=\(version)") }
            let unsupportedOriginal = try Data(contentsOf: url)
            XCTAssertThrowsError(try DraftStore(url: url)) {
                XCTAssertEqual($0 as? DraftStoreError, .unsupportedSchema(version))
            }
            let unchanged = try Data(contentsOf: url) == unsupportedOriginal
            XCTAssertTrue(unchanged); XCTAssertEqual(try scalar(url, "PRAGMA user_version"), version)
            // Recover a separate copy of the original known-compatible backup;
            // never relabel the unknown database or pretend a downgrade migrated it.
            let recovery = url.deletingLastPathComponent().appendingPathComponent("original-backup.sqlite")
            try supportedOriginal.write(to: recovery)
            let recovered = try await preserved(DraftStore(url: recovery), vector: vector)
            XCTAssertTrue(recovered); XCTAssertEqual(try Data(contentsOf: url), unsupportedOriginal)
            try receipt("storage-version-\(version)", phase: "unsupported-retain",
                        values: ["originalDatabaseBytesPreserved": unchanged, "separateOriginalBackupReopened": recovered])
        }
    }

    func testRestorationAfterMigrationAppendsHistoryAndRejectsStaleRevision() async throws {
        for vector in try corpus().cases where vector.records.count > 1 {
            let url = try location(); try seed(vector, at: url)
            let store = try DraftStore(url: url)
            let original = try await store.history(id: vector.draftID)
            let first = try XCTUnwrap(vector.records.first)
            let restored = try await store.restore(id: vector.draftID, revision: first.revision,
                                                   expectedRevision: vector.headRevision)
            let payload = restored.payload == Data(first.payloadJSON.utf8)
            let appended = restored.revision == vector.headRevision + 1 && restored.restoredFrom == first.revision &&
                restored.title == first.title && !restored.analysisIsCurrent
            XCTAssertTrue(payload, vector.id); XCTAssertTrue(appended, vector.id)
            do {
                try await store.restore(id: vector.draftID, revision: first.revision, expectedRevision: vector.headRevision)
                XCTFail(vector.id)
            } catch { XCTAssertEqual(error as? DraftStoreError, .conflict, vector.id) }
            let after = try await DraftStore(url: url).history(id: vector.draftID)
            let history = after.unreadableCount == 0 && after.records.count == original.records.count + 1 &&
                Array(after.records.dropFirst()) == original.records && after.records.first == restored
            XCTAssertTrue(history, vector.id)
            try receipt(vector.id, phase: "history-restore",
                        values: ["originalPayloadBytesPreserved": payload, "newRevisionAppended": appended,
                                 "originalHistoryPreservedAfterStaleRejection": history])
        }
    }
}
