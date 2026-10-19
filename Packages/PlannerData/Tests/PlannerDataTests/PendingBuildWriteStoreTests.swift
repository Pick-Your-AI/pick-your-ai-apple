import XCTest
import Foundation
import CSQLite
@testable import PlannerData

final class PendingBuildWriteStoreTests: XCTestCase, @unchecked Sendable {
    private enum Injected: Error { case failure }
    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("pending.sqlite")
    }
    private func partition(_ authority: String = "synthetic-owner", environment: String = "fixture-v1") throws -> PendingWritePartition {
        try PendingWritePartition(environment: environment, authority: authority)
    }
    private func intent(_ id: String = "operation-1", key: String? = nil, build: String = "build-1",
                        method: PendingBuildWriteMethod = .create, precondition: String? = nil,
                        body: Data = Data("{\"decimal\":\"1.000\",\"revision\":1}".utf8)) throws -> PendingBuildWrite {
        try PendingBuildWrite(operationID: id, method: method, buildID: build,
                              idempotencyKey: key ?? "key-" + id, ifMatch: precondition, body: body)
    }
    private func expect(_ expected: PendingWriteError, _ action: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("Expected bounded queue error", file: file, line: line) }
        catch { XCTAssertEqual(error as? PendingWriteError, expected, file: file, line: line) }
    }
    private func expectInjected(_ action: () async throws -> Void,
                                file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("Expected injected commit interruption", file: file, line: line) }
        catch { XCTAssertTrue(error is Injected, file: file, line: line) }
    }
    private func failing(_ url: URL, at selected: PendingWriteFaultPoint) throws -> PendingBuildWriteStore {
        try PendingBuildWriteStore(url: url, fault: { point in
            if point == selected { throw Injected.failure }
        })
    }
    private func sql(_ url: URL, _ sql: String) throws {
        var pointer: OpaquePointer?
        let opened = sqlite3_open(url.path, &pointer)
        defer { sqlite3_close(pointer) }
        guard opened == SQLITE_OK else { throw PendingWriteError.database(opened) }
        let code = sqlite3_exec(pointer, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw PendingWriteError.database(code) }
    }
    private func scalar(_ url: URL, _ sql: String) throws -> Int64 {
        var pointer: OpaquePointer?; var statement: OpaquePointer?
        let opened = sqlite3_open(url.path, &pointer)
        defer { sqlite3_finalize(statement); sqlite3_close(pointer) }
        guard opened == SQLITE_OK else { throw PendingWriteError.database(opened) }
        let prepared = sqlite3_prepare_v2(pointer, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK else { throw PendingWriteError.database(prepared) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW else { throw PendingWriteError.database(code) }
        return sqlite3_column_int64(statement, 0)
    }
    /// Complete files in this synthetic fixture's directory; normal DELETE mode
    /// produces no shared-memory reader marks. WAL tests compare DB/WAL explicitly.
    private func files(_ url: URL) throws -> [String: Data] {
        let children = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(),
                                                                   includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: children.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
    private func interruptedCopy(_ source: URL, update: String) throws -> URL {
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(source.path, &writer), SQLITE_OK)
        defer { sqlite3_close(writer) }
        XCTAssertEqual(sqlite3_exec(writer,
            "PRAGMA cache_size=1; PRAGMA cache_spill=ON; BEGIN IMMEDIATE; " + update, nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_db_cacheflush(writer), SQLITE_OK)
        let journal = URL(fileURLWithPath: source.path + "-journal")
        let bytes = try Data(contentsOf: journal)
        XCTAssertGreaterThan(bytes.count, 512)
        XCTAssertEqual(Array(bytes.prefix(8)), [0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7])
        let copy = try location()
        try FileManager.default.copyItem(at: source, to: copy)
        try FileManager.default.copyItem(at: journal, to: URL(fileURLWithPath: copy.path + "-journal"))
        return copy
    }
    private func futureWAL(versionInMain: Bool, version: Int = 99) throws -> URL {
        let source = try location()
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(source.path, &writer), SQLITE_OK)
        defer { sqlite3_close(writer) }
        if versionInMain {
            XCTAssertEqual(sqlite3_exec(writer, "PRAGMA user_version=\(version); CREATE TABLE sentinel(value BLOB)", nil, nil, nil), SQLITE_OK)
        }
        XCTAssertEqual(sqlite3_exec(writer, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;", nil, nil, nil), SQLITE_OK)
        let update = versionInMain ? "INSERT INTO sentinel VALUES(X'010203')" : "CREATE TABLE sentinel(value BLOB); PRAGMA user_version=\(version); INSERT INTO sentinel VALUES(X'010203')"
        XCTAssertEqual(sqlite3_exec(writer, update, nil, nil, nil), SQLITE_OK)
        let copy = try location()
        try FileManager.default.copyItem(at: source, to: copy)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: source.path + "-wal"),
                                        to: URL(fileURLWithPath: copy.path + "-wal"))
        return copy
    }

    func testIntentSurvivesReopenWithExactBodyAndPrecondition() async throws {
        let url = try location(); let owner = try partition()
        let store = try PendingBuildWriteStore(url: url)
        let session = try await store.activate(owner)
        let write = try intent(method: .update, precondition: "\"9007199254740993\"")
        let saved = try await store.enqueue(write, session: session)
        XCTAssertEqual(saved.sequence, 1); XCTAssertEqual(saved.state, .pending)
        let reopened = try PendingBuildWriteStore(url: url)
        let current = try await reopened.activate(owner)
        let records = try await reopened.records(session: current)
        XCTAssertEqual(records, [saved]); XCTAssertEqual(records[0].write.body, write.body)
        XCTAssertEqual(Data(records[0].write.ifMatch!.utf8), Data("\"9007199254740993\"".utf8))
        await expect(.staleSession) { _ = try await store.records(session: session) }
    }

    func testCallerAndReturnedDataCannotMutateIntent() async throws {
        let original = Data(("{\"exact\":\"" + String(repeating: "1", count: 2048) + "\"}").utf8)
        let backing = NSMutableData(data: original)
        let bridged = try intent(body: Data(referencing: backing))
        backing.resetBytes(in: NSRange(location: 0, length: backing.length))
        XCTAssertEqual(bridged.body, original)
        let write: PendingBuildWrite
        do {
            let storage = UnsafeMutableRawPointer.allocate(byteCount: original.count, alignment: 1)
            defer { storage.deallocate() }
            original.withUnsafeBytes { storage.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            let alias = Data(bytesNoCopy: storage, count: original.count, deallocator: .none)
            write = try intent(body: alias)
            storage.initializeMemory(as: UInt8.self, repeating: 0, count: original.count)
            XCTAssertNotEqual(alias, original) // Prove this fixture really aliases caller memory.
            XCTAssertEqual(write.body, original)
        }
        let store = try PendingBuildWriteStore(url: location())
        let session = try await store.activate(partition())
        let saved = try await store.enqueue(write, session: session)
        var returned = saved.write.body; returned[0] = 0
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows[0].write.body, original); XCTAssertNotEqual(returned, original)
    }

    func testExactUTF8ValueEqualityAndSQLiteIdentity() async throws {
        let composed = "\u{00e9}"; let decomposed = "e\u{0301}"
        XCTAssertEqual(composed, decomposed) // Swift's String equality is not this queue's identity rule.
        let first = try intent(composed, key: composed, build: composed)
        let second = try intent(decomposed, key: decomposed, build: decomposed)
        XCTAssertNotEqual(first, second)
        let store = try PendingBuildWriteStore(url: location())
        let session = try await store.activate(partition())
        try await store.enqueue(first, session: session); try await store.enqueue(second, session: session)
        let one = try await store.beginAttempt(operationID: composed, session: session)
        let two = try await store.beginAttempt(operationID: decomposed, session: session)
        XCTAssertEqual(one.write, first); XCTAssertEqual(two.write, second)
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows.map(\.write), [first, second]); XCTAssertEqual(rows.map(\.sequence), [1, 2])
    }

    func testExactUTF8PartitionsDoNotShareReadsOrCallbacks() async throws {
        let composed = "\u{00e9}"; let decomposed = "e\u{0301}"
        for environmentChanges in [false, true] {
            let a = try partition(composed, environment: composed)
            let b = try partition(environmentChanges ? composed : decomposed,
                                  environment: environmentChanges ? decomposed : composed)
            XCTAssertNotEqual(a, b)
            let store = try PendingBuildWriteStore(url: location())
            let first = try await store.activate(a)
            try await store.enqueue(intent(), session: first)
            let attempt = try await store.beginAttempt(operationID: "operation-1", session: first)
            let second = try await store.activate(b)
            let hidden = try await store.records(session: second); XCTAssertTrue(hidden.isEmpty)
            let accepted = try await store.recordOutcome(.confirmed, for: attempt); XCTAssertFalse(accepted)
            let restored = try await store.activate(a)
            let rows = try await store.records(session: restored); XCTAssertEqual(rows[0].state, .uncertain)
        }
    }

    func testIdenticalEnqueueAtCapacityReturnsExistingRecord() async throws {
        let url = try location(); let limits = try PendingWriteLimits(maximumRecords: 1, maximumTotalBodyBytes: 100)
        let store = try PendingBuildWriteStore(url: url, limits: limits)
        let session = try await store.activate(partition()); let write = try intent()
        let original = try await store.enqueue(write, session: session)
        let before = try files(url)
        let duplicate = try await store.enqueue(write, session: session)
        XCTAssertEqual(duplicate, original); XCTAssertEqual(try files(url), before)
        await expect(.capacityExceeded) { _ = try await store.enqueue(self.intent("other"), session: session) }
        XCTAssertEqual(try files(url), before)
    }

    func testChangedDuplicateIntentIsRejectedWithoutAnyFileChange() async throws {
        let url = try location(); let store = try PendingBuildWriteStore(url: url)
        let session = try await store.activate(partition())
        let original = try intent(method: .update, precondition: "\"7\"")
        try await store.enqueue(original, session: session)
        let variants = [
            try intent(method: .update, precondition: "\"8\""),
            try intent(key: "different", method: .update, precondition: "\"7\""),
            try intent(build: "different", method: .update, precondition: "\"7\""),
            try intent(method: .update, precondition: "\"7\"", body: Data("{\"changed\":true}".utf8)),
            try intent(), try intent("different", key: original.idempotencyKey)
        ]
        let before = try files(url)
        for variant in variants {
            await expect(.identityConflict) { _ = try await store.enqueue(variant, session: session) }
            XCTAssertEqual(try files(url), before)
        }
    }

    func testReusedKeyOrOperationAcrossPartitionRejectsWithoutDisclosure() async throws {
        let url = try location(); let store = try PendingBuildWriteStore(url: url); let write = try intent()
        let a = try await store.activate(partition("a")); try await store.enqueue(write, session: a)
        let b = try await store.activate(partition("b")); let before = try files(url)
        for variant in [write, try intent("another", key: write.idempotencyKey), try intent(key: "another")] {
            await expect(.identityConflict) { _ = try await store.enqueue(variant, session: b) }
        }
        let rows = try await store.records(session: b)
        XCTAssertTrue(rows.isEmpty); XCTAssertEqual(try files(url), before)
    }

    func testInvalidIntentAndLimitBounds() throws {
        for invalid in ["", "line\nbreak", "nul\0byte", String(repeating: "x", count: 1025)] {
            XCTAssertThrowsError(try intent(invalid))
            XCTAssertThrowsError(try intent(key: invalid))
            XCTAssertThrowsError(try intent(build: invalid))
            XCTAssertThrowsError(try partition(invalid))
            XCTAssertThrowsError(try partition(environment: invalid))
        }
        for precondition in [nil, "", "7", "*", "W/\"7\"", "\"0\"", "\"01\"", "\"-1\"", "\"١\"", "\"1\n\""] as [String?] {
            XCTAssertThrowsError(try intent(method: .update, precondition: precondition))
        }
        XCTAssertThrowsError(try intent(precondition: "\"1\""))
        XCTAssertThrowsError(try intent(body: Data()))
        XCTAssertThrowsError(try intent(body: Data(repeating: 1, count: PendingBuildWrite.maximumBodyBytes + 1)))
        XCTAssertThrowsError(try PendingWriteLimits(maximumRecords: 0))
        XCTAssertThrowsError(try PendingWriteLimits(maximumRecords: 4097))
        XCTAssertThrowsError(try PendingWriteLimits(maximumTotalBodyBytes: 0))
        XCTAssertThrowsError(try PendingWriteLimits(maximumTotalBodyBytes: 67_108_865))
        let exact = try intent(method: .update, precondition: "\"123456789012345678901234567890\"")
        XCTAssertEqual(exact.ifMatch, "\"123456789012345678901234567890\"")
    }

    func testBodyAndAggregateLimitsRetainConfirmedRecords() async throws {
        let url = try location(); let limits = try PendingWriteLimits(maximumTotalBodyBytes: 4)
        let store = try PendingBuildWriteStore(url: url, limits: limits)
        let session = try await store.activate(partition())
        let write = try intent(body: Data([1, 2, 3, 4]))
        try await store.enqueue(write, session: session)
        let attempt = try await store.beginAttempt(operationID: write.operationID, session: session)
        let accepted = try await store.recordOutcome(.confirmed, for: attempt); XCTAssertTrue(accepted)
        let before = try files(url)
        await expect(.capacityExceeded) { _ = try await store.enqueue(self.intent("two", body: Data([5])), session: session) }
        XCTAssertEqual(try files(url), before)
        let duplicate = try await store.enqueue(write, session: session); XCTAssertEqual(duplicate.state, .confirmed)
    }

    func testOpeningParallelHandleDoesNotInvalidateLiveAttempt() async throws {
        let url = try location(); let store = try PendingBuildWriteStore(url: url)
        let session = try await store.activate(partition())
        try await store.enqueue(intent(), session: session)
        let attempt = try await store.beginAttempt(operationID: "operation-1", session: session)
        let parallel = try PendingBuildWriteStore(url: url)
        await expect(.staleSession) { _ = try await parallel.records(session: session) }
        let accepted = try await store.recordOutcome(.confirmed, for: attempt); XCTAssertTrue(accepted)
        let rows = try await store.records(session: session); XCTAssertEqual(rows[0].state, .confirmed)
    }

    func testParallelActivationAtomicallyInvalidatesOldSessionAndCallback() async throws {
        let url = try location(); let first = try PendingBuildWriteStore(url: url)
        let a = try await first.activate(partition()); try await first.enqueue(intent(), session: a)
        let oldAttempt = try await first.beginAttempt(operationID: "operation-1", session: a)
        let second = try PendingBuildWriteStore(url: url); let b = try await second.activate(partition())
        let before = try files(url)
        await expect(.staleSession) { _ = try await first.enqueue(self.intent("late"), session: a) }
        await expect(.staleSession) { _ = try await first.records(session: a) }
        let accepted = try await first.recordOutcome(.confirmed, for: oldAttempt); XCTAssertFalse(accepted)
        let rows = try await second.records(session: b)
        XCTAssertEqual(rows[0].state, .uncertain); XCTAssertEqual(rows[0].attemptID, oldAttempt.attemptID)
        XCTAssertEqual(try files(url), before)
    }

    func testSwitchAwayAndBackCannotReviveOldToken() async throws {
        let url = try location(); let store = try PendingBuildWriteStore(url: url); let owner = try partition("a")
        let a = try await store.activate(owner); try await store.enqueue(intent(), session: a)
        let attempt = try await store.beginAttempt(operationID: "operation-1", session: a)
        let b = try await store.activate(partition("b")); try await store.deactivate(b)
        let nextA = try await store.activate(owner); let before = try files(url)
        XCTAssertNotEqual(a, nextA)
        await expect(.staleSession) { try await store.deactivate(a) }
        let accepted = try await store.recordOutcome(.confirmed, for: attempt); XCTAssertFalse(accepted)
        await expect(.notPending) { _ = try await store.beginAttempt(operationID: "operation-1", session: nextA) }
        XCTAssertEqual(try files(url), before)
    }

    func testReopenRecoversCommittedAttemptAsUncertainWithoutResend() async throws {
        let url = try location(); let store = try PendingBuildWriteStore(url: url)
        let session = try await store.activate(partition()); let write = try intent()
        try await store.enqueue(write, session: session)
        let attempt = try await store.beginAttempt(operationID: write.operationID, session: session)
        let reopened = try PendingBuildWriteStore(url: url)
        let current = try await reopened.activate(partition())
        let rows = try await reopened.records(session: current)
        XCTAssertEqual(rows[0].write, write); XCTAssertEqual(rows[0].attemptID, attempt.attemptID)
        XCTAssertEqual(rows[0].state, .uncertain)
        let before = try files(url)
        await expect(.notPending) { _ = try await reopened.beginAttempt(operationID: write.operationID, session: current) }
        let accepted = try await reopened.recordOutcome(.confirmed, for: attempt); XCTAssertFalse(accepted)
        XCTAssertEqual(try files(url), before)
    }

    func testForeignStoreCannotUseSessionOrAttempt() async throws {
        let first = try PendingBuildWriteStore(url: location()); let otherURL = try location()
        let other = try PendingBuildWriteStore(url: otherURL)
        let session = try await first.activate(partition()); try await first.enqueue(intent(), session: session)
        let attempt = try await first.beginAttempt(operationID: "operation-1", session: session)
        _ = try await other.activate(partition()); let before = try files(otherURL)
        await expect(.staleSession) { _ = try await other.enqueue(self.intent(), session: session) }
        let accepted = try await other.recordOutcome(.confirmed, for: attempt); XCTAssertFalse(accepted)
        XCTAssertEqual(try files(otherURL), before)
    }

    func testSameBuildWaitsForConfirmationWhileOtherBuildCanProceed() async throws {
        let store = try PendingBuildWriteStore(url: location()); let session = try await store.activate(partition())
        try await store.enqueue(intent("first"), session: session)
        try await store.enqueue(intent("second", method: .update, precondition: "\"1\""), session: session)
        try await store.enqueue(intent("other", build: "independent"), session: session)
        await expect(.blocked) { _ = try await store.beginAttempt(operationID: "second", session: session) }
        let other = try await store.beginAttempt(operationID: "other", session: session)
        XCTAssertEqual(other.write.buildID, "independent")
        let first = try await store.beginAttempt(operationID: "first", session: session)
        await expect(.blocked) { _ = try await store.beginAttempt(operationID: "second", session: session) }
        let accepted = try await store.recordOutcome(.confirmed, for: first); XCTAssertTrue(accepted)
        let second = try await store.beginAttempt(operationID: "second", session: session)
        XCTAssertEqual(second.write.ifMatch, "\"1\""); XCTAssertNotEqual(first.attemptID, second.attemptID)
    }

    func testConflictInvalidAndUncertainRetainImmutableIntentAndBlockFollowers() async throws {
        for (outcome, state) in [(PendingWriteOutcome.conflict, PendingWriteState.conflict), (.invalid, .invalid), (.uncertain, .uncertain)] {
            let url = try location(); let store = try PendingBuildWriteStore(url: url)
            let session = try await store.activate(partition()); let write = try intent()
            try await store.enqueue(write, session: session); try await store.enqueue(intent("next"), session: session)
            let attempt = try await store.beginAttempt(operationID: write.operationID, session: session)
            let accepted = try await store.recordOutcome(outcome, for: attempt); XCTAssertTrue(accepted)
            let rows = try await store.records(session: session)
            XCTAssertEqual(rows[0].state, state); XCTAssertEqual(rows[0].write, write)
            let before = try files(url)
            await expect(.notPending) { _ = try await store.beginAttempt(operationID: write.operationID, session: session) }
            await expect(.blocked) { _ = try await store.beginAttempt(operationID: "next", session: session) }
            XCTAssertEqual(try files(url), before)
        }
    }

    func testDuplicateCompletionAndDuplicateAttemptDoNotWrite() async throws {
        let url = try location(); let store = try PendingBuildWriteStore(url: url)
        let session = try await store.activate(partition()); try await store.enqueue(intent(), session: session)
        let attempt = try await store.beginAttempt(operationID: "operation-1", session: session)
        let during = try files(url)
        await expect(.notPending) { _ = try await store.beginAttempt(operationID: "operation-1", session: session) }
        XCTAssertEqual(try files(url), during)
        let accepted = try await store.recordOutcome(.confirmed, for: attempt); XCTAssertTrue(accepted)
        let after = try files(url)
        for outcome in [PendingWriteOutcome.confirmed, .conflict, .invalid, .uncertain] {
            let duplicate = try await store.recordOutcome(outcome, for: attempt); XCTAssertFalse(duplicate)
        }
        XCTAssertEqual(try files(url), after)
    }

    func testFailedEnqueueCommitRollsBackEverything() async throws {
        let url = try location(); let store = try failing(url, at: .beforeEnqueueCommit)
        let session = try await store.activate(partition()); let before = try files(url)
        await expectInjected { _ = try await store.enqueue(self.intent(), session: session) }
        let rows = try await store.records(session: session); XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(try files(url), before)
    }

    func testFailedAttemptCommitLeavesPendingIntentUnchanged() async throws {
        let url = try location(); let store = try failing(url, at: .beforeAttemptCommit)
        let session = try await store.activate(partition()); let saved = try await store.enqueue(intent(), session: session)
        let before = try files(url)
        await expectInjected { _ = try await store.beginAttempt(operationID: "operation-1", session: session) }
        let rows = try await store.records(session: session); XCTAssertEqual(rows, [saved])
        XCTAssertEqual(try files(url), before)
    }

    func testFailedActivationCommitPreservesGenerationAndAttempt() async throws {
        let url = try location(); let live = try PendingBuildWriteStore(url: url)
        let session = try await live.activate(partition()); try await live.enqueue(intent(), session: session)
        let attempt = try await live.beginAttempt(operationID: "operation-1", session: session)
        let other = try failing(url, at: .beforeActivationCommit); let before = try files(url)
        await expectInjected { _ = try await other.activate(self.partition("other")) }
        XCTAssertEqual(try files(url), before)
        let rows = try await live.records(session: session); XCTAssertEqual(rows[0].state, .attempting)
        let accepted = try await live.recordOutcome(.confirmed, for: attempt); XCTAssertTrue(accepted)
    }

    func testFailedOutcomeCommitPreservesAttempt() async throws {
        let url = try location(); let store = try failing(url, at: .beforeOutcomeCommit)
        let session = try await store.activate(partition()); try await store.enqueue(intent(), session: session)
        let attempt = try await store.beginAttempt(operationID: "operation-1", session: session); let before = try files(url)
        await expectInjected { _ = try await store.recordOutcome(.confirmed, for: attempt) }
        XCTAssertEqual(try files(url), before)
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows[0].state, .attempting); XCTAssertEqual(rows[0].attemptID, attempt.attemptID)
    }

    func testFailedDeactivationCommitRetainsLiveSession() async throws {
        let url = try location(); let store = try failing(url, at: .beforeDeactivationCommit)
        let session = try await store.activate(partition()); try await store.enqueue(intent(), session: session)
        let attempt = try await store.beginAttempt(operationID: "operation-1", session: session); let before = try files(url)
        await expectInjected { try await store.deactivate(session) }
        XCTAssertEqual(try files(url), before)
        let accepted = try await store.recordOutcome(.confirmed, for: attempt); XCTAssertTrue(accepted)
    }

    func testActualSQLiteFullRetainsQueueThenUnconstrainedReopenRecovers() async throws {
        let url = try location(); let seeded = try PendingBuildWriteStore(url: url)
        let session = try await seeded.activate(partition()); let write = try intent()
        try await seeded.enqueue(write, session: session)
        let pages = try scalar(url, "PRAGMA page_count")
        let constrained = try PendingBuildWriteStore(url: url, maximumPages: Int(pages), fault: { _ in })
        let current = try await constrained.activate(partition())
        let large = try intent("large", body: Data(repeating: 42, count: 500_000)); let before = try files(url)
        await expect(.database(SQLITE_FULL)) { _ = try await constrained.enqueue(large, session: current) }
        XCTAssertEqual(try files(url), before)
        let rows = try await constrained.records(session: current); XCTAssertEqual(rows.map(\.write), [write])
        let recovered = try PendingBuildWriteStore(url: url); let next = try await recovered.activate(partition())
        let appended = try await recovered.enqueue(large, session: next); XCTAssertEqual(appended.sequence, 2)
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM pragma_integrity_check WHERE integrity_check != 'ok'"), 0)
    }

    func testUnsupportedQueueWALRetainsDatabaseAndWALBytes() throws {
        let url = try futureWAL(versionInMain: true); let wal = URL(fileURLWithPath: url.path + "-wal")
        let original = try Data(contentsOf: url); let pending = try Data(contentsOf: wal)
        XCTAssertThrowsError(try PendingBuildWriteStore(url: url)) { XCTAssertEqual($0 as? PendingWriteError, .unsupportedSchema(99)) }
        XCTAssertEqual(try Data(contentsOf: url), original); XCTAssertEqual(try Data(contentsOf: wal), pending)
    }

    func testFutureVersionOnlyInOrphanedWALIsRejected() throws {
        let url = try futureWAL(versionInMain: false); let wal = URL(fileURLWithPath: url.path + "-wal")
        let original = try Data(contentsOf: url); let pending = try Data(contentsOf: wal)
        XCTAssertEqual(Array(original[60..<64]), [0, 0, 0, 0])
        XCTAssertThrowsError(try PendingBuildWriteStore(url: url)) { XCTAssertEqual($0 as? PendingWriteError, .unsupportedSchema(99)) }
        XCTAssertEqual(try Data(contentsOf: url), original); XCTAssertEqual(try Data(contentsOf: wal), pending)
    }

    func testForeignApplicationInOrphanedWALKeepsOriginalBytes() throws {
        let url = try futureWAL(versionInMain: false, version: 1)
        let wal = URL(fileURLWithPath: url.path + "-wal")
        let original = try Data(contentsOf: url); let pending = try Data(contentsOf: wal)
        XCTAssertThrowsError(try PendingBuildWriteStore(url: url)) { XCTAssertEqual($0 as? PendingWriteError, .foreignDatabase) }
        XCTAssertEqual(try Data(contentsOf: url), original); XCTAssertEqual(try Data(contentsOf: wal), pending)
    }

    func testSupportedWALQueueRemainsReadableAndWritable() async throws {
        let url = try location(); let write = try intent()
        do {
            let store = try PendingBuildWriteStore(url: url)
            let session = try await store.activate(partition())
            try await store.enqueue(write, session: session)
        }
        try sql(url, "PRAGMA journal_mode=WAL; UPDATE queue_writes SET body=body")
        let reopened = try PendingBuildWriteStore(url: url)
        let current = try await reopened.activate(partition())
        let rows = try await reopened.records(session: current); XCTAssertEqual(rows.map(\.write), [write])
        let next = try await reopened.enqueue(intent("next"), session: current)
        XCTAssertEqual(next.sequence, 2)
        XCTAssertEqual(try scalar(url, "SELECT count(*) FROM pragma_integrity_check WHERE integrity_check != 'ok'"), 0)
    }

    func testSupportedHotRollbackJournalRecoversBeforeQueueRead() async throws {
        let source = try location(); let store = try PendingBuildWriteStore(url: source)
        let session = try await store.activate(partition()); let write = try intent()
        try await store.enqueue(write, session: session)
        let copy = try interruptedCopy(source, update: "UPDATE queue_writes SET body=zeroblob(1048576)")
        let recovered = try PendingBuildWriteStore(url: copy); let current = try await recovered.activate(partition())
        let rows = try await recovered.records(session: current)
        XCTAssertEqual(rows.map(\.write), [write]); XCTAssertEqual(rows[0].state, .pending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path + "-journal"))
    }

    func testRollbackRestoresCommittedFutureVersionBeforeRejection() async throws {
        let source = try location(); let store = try PendingBuildWriteStore(url: source)
        let session = try await store.activate(partition()); try await store.enqueue(intent(), session: session)
        try sql(source, "PRAGMA user_version=99")
        let copy = try interruptedCopy(source, update: "PRAGMA user_version=1; UPDATE queue_writes SET body=zeroblob(1048576)")
        // Cache flushing excludes page 1. Construct the interrupted page-1 write
        // directly on this synthetic copy; never open it through SQLite first.
        // The retained hot journal must restore the committed version and body.
        let journal = URL(fileURLWithPath: copy.path + "-journal")
        let rollback = try Data(contentsOf: journal)
        var interrupted = try Data(contentsOf: copy)
        interrupted.replaceSubrange(60..<64, with: Data([0, 0, 0, 1]))
        try interrupted.write(to: copy)
        XCTAssertEqual(try Data(contentsOf: journal), rollback)
        XCTAssertEqual(Array(try Data(contentsOf: copy)[60..<64]), [0, 0, 0, 1])
        XCTAssertThrowsError(try PendingBuildWriteStore(url: copy)) { XCTAssertEqual($0 as? PendingWriteError, .unsupportedSchema(99)) }
        XCTAssertEqual(try scalar(copy, "PRAGMA user_version"), 99)
        XCTAssertEqual(try scalar(copy, "SELECT length(body) FROM queue_writes"), Int64(try intent().body.count))
    }

    func testDraftAndForeignDatabaseAreNeverAdopted() async throws {
        let draftURL = try location(); let drafts = try DraftStore(url: draftURL); let id = UUID()
        try await drafts.save(id: id, expectedRevision: nil, title: "Synthetic draft", payload: Data("{}".utf8))
        let before = try files(draftURL)
        XCTAssertThrowsError(try PendingBuildWriteStore(url: draftURL))
        XCTAssertEqual(try files(draftURL), before)
        let retained = try await drafts.read(id: id); XCTAssertEqual(retained.revision, 1)
        for version in [0, 1] {
            let foreign = try location()
            try sql(foreign, "CREATE TABLE important(value BLOB); INSERT INTO important VALUES(X'010203'); PRAGMA user_version=\(version)")
            let bytes = try files(foreign)
            XCTAssertThrowsError(try PendingBuildWriteStore(url: foreign)) { XCTAssertEqual($0 as? PendingWriteError, .foreignDatabase) }
            XCTAssertEqual(try files(foreign), bytes)
        }
    }

    func testCorruptDatabaseIsRetainedWithoutSensitiveDiagnostics() throws {
        let url = try location(); let payload = Data("private-request-marker-not-sqlite".utf8)
        try payload.write(to: url)
        do { _ = try PendingBuildWriteStore(url: url); XCTFail("Expected corrupt database rejection") }
        catch {
            XCTAssertFalse(String(describing: error).contains(url.path))
            XCTAssertFalse(String(describing: error).contains("private-request-marker"))
        }
        XCTAssertEqual(try Data(contentsOf: url), payload)
    }

    func testCorruptPredecessorCannotBeSkippedForDispatch() async throws {
        for mutation in ["body=X''", "build_id=CAST(X'ff' AS BLOB)", "state=99", "operation_id='wrong-type'"] {
            let url = try location(); let store = try PendingBuildWriteStore(url: url)
            let session = try await store.activate(partition())
            try await store.enqueue(intent("first"), session: session); try await store.enqueue(intent("next"), session: session)
            try sql(url, "UPDATE queue_writes SET " + mutation + " WHERE sequence=1")
            let before = try files(url)
            await expect(.corruptRecord) { _ = try await store.beginAttempt(operationID: "next", session: session) }
            await expect(.corruptRecord) { _ = try await store.records(session: session) }
            await expect(.corruptRecord) { _ = try await store.enqueue(self.intent("later"), session: session) }
            XCTAssertEqual(try files(url), before)
        }
    }

    func testMalformedSessionOrAttemptMetadataBlocksAllWrites() async throws {
        for mutation in [
            "UPDATE queue_session SET generation=X'ff'",
            "UPDATE queue_session SET authority=NULL",
            "UPDATE queue_writes SET attempt_id=NULL",
            "UPDATE queue_writes SET attempt_generation=X'ff'"
        ] {
            let url = try location(); let store = try PendingBuildWriteStore(url: url)
            let session = try await store.activate(partition()); try await store.enqueue(intent(), session: session)
            _ = try await store.beginAttempt(operationID: "operation-1", session: session)
            try sql(url, mutation); let before = try files(url)
            await expect(.corruptRecord) { _ = try await store.activate(self.partition("other")) }
            await expect(.corruptRecord) { _ = try await store.records(session: session) }
            XCTAssertEqual(try files(url), before)
        }
    }

    func testCapacityAcrossPartitionsIsGlobalAndNeverEvicts() async throws {
        let url = try location(); let limits = try PendingWriteLimits(maximumRecords: 1)
        let store = try PendingBuildWriteStore(url: url, limits: limits)
        let first = try await store.activate(partition("a")); let write = try intent()
        try await store.enqueue(write, session: first)
        let other = try await store.activate(partition("b")); let before = try files(url)
        await expect(.capacityExceeded) { _ = try await store.enqueue(self.intent("second"), session: other) }
        XCTAssertEqual(try files(url), before)
        let again = try await store.activate(partition("a")); let rows = try await store.records(session: again)
        XCTAssertEqual(rows.map(\.write), [write])
    }

    func testConcurrentEnqueueAndActivationHaveOneConsistentCommitOrder() async throws {
        let url = try location(); let first = try PendingBuildWriteStore(url: url)
        let second = try PendingBuildWriteStore(url: url); let owner = try partition()
        let old = try await first.activate(owner); let write = try intent()
        let enqueue = Task { try await first.enqueue(write, session: old) }
        let activation = Task { try await second.activate(owner) }
        let current = try await activation.value
        let committed: Bool
        do { _ = try await enqueue.value; committed = true }
        catch { XCTAssertEqual(error as? PendingWriteError, .staleSession); committed = false }
        let rows = try await second.records(session: current)
        XCTAssertEqual(rows.map(\.write), committed ? [write] : [])
        XCTAssertTrue(rows.allSatisfy { $0.state == .pending })
        await expect(.staleSession) { _ = try await first.records(session: old) }
    }
}
