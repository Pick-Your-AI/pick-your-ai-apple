import XCTest
import Foundation
@testable import PlannerData

final class PendingBuildWriteDispatcherTests: XCTestCase, @unchecked Sendable {
    private enum FixtureFailure: Error { case commit, lostAcknowledgement }

    /// Explicit test release, intentionally unaffected by Task cancellation.
    /// Cancellation tests decide when their synthetic adapter checks cancellation.
    private actor Signal {
        private var released = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if released { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            guard !released else { return }
            released = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    private actor Calls {
        private var values: [PendingWriteAttempt] = []
        func record(_ attempt: PendingWriteAttempt) { values.append(attempt) }
        func snapshot() -> [PendingWriteAttempt] { values }
    }

    /// A labelled fault observer, not a backend or an idempotency implementation.
    /// One synthetic effect precedes the missing response; there is no receipt API.
    private actor LostAcknowledgementFixture {
        private var invocations: [PendingWriteAttempt] = []
        private var effects: [PendingBuildWrite] = []

        func perform(_ attempt: PendingWriteAttempt) throws -> PendingWriteOutcome {
            invocations.append(attempt)
            effects.append(attempt.write)
            throw FixtureFailure.lostAcknowledgement
        }

        func snapshot() -> ([PendingWriteAttempt], [PendingBuildWrite]) { (invocations, effects) }
    }

    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("dispatch.sqlite")
    }

    private func partition(_ authority: String = "synthetic-owner") throws -> PendingWritePartition {
        try PendingWritePartition(environment: "fixture-only", authority: authority)
    }

    // Payloads are byte-preservation fixtures, not adopted BuildSnapshot responses.
    private func intent(_ id: String = "operation-1", build: String = "build-1",
                        method: PendingBuildWriteMethod = .create, ifMatch: String? = nil,
                        body: Data = Data(#"{"synthetic":true}"#.utf8)) throws -> PendingBuildWrite {
        try PendingBuildWrite(operationID: id, method: method, buildID: build,
                              idempotencyKey: "key-" + id, ifMatch: ifMatch, body: body)
    }

    private func files(_ url: URL) throws -> [String: Data] {
        let children = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(),
                                                                   includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: children.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    private func fail(_ expected: PendingWriteFaultPoint, at url: URL) throws -> PendingBuildWriteStore {
        try PendingBuildWriteStore(url: url, fault: { point in
            if point == expected { throw FixtureFailure.commit }
        })
    }

    private func expect(_ expected: PendingWriteError, _ action: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("Expected bounded queue error", file: file, line: line) }
        catch { XCTAssertEqual(error as? PendingWriteError, expected, file: file, line: line) }
    }

    private func expectCommitFailure(_ action: () async throws -> Void,
                                     file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("Expected commit interruption", file: file, line: line) }
        catch { XCTAssertTrue(error is FixtureFailure, file: file, line: line) }
    }

    private func assertRecorded(_ result: PendingBuildWriteDispatchResult, as state: PendingWriteState,
                                file: StaticString = #filePath, line: UInt = #line) {
        switch (result, state) {
        case (.recorded(.confirmed), .confirmed), (.recorded(.conflict), .conflict),
             (.recorded(.invalid), .invalid), (.recorded(.uncertain), .uncertain):
            return
        default:
            XCTFail("Expected the exact locally recorded outcome", file: file, line: line)
        }
    }

    private func releaseAtTeardown(_ signal: Signal, task: Task<PendingBuildWriteDispatchResult, Error>) {
        addTeardownBlock {
            task.cancel()
            await signal.release()
            _ = try? await task.value
        }
    }

    func testAdapterReceivesOnlyCommittedExactAttempt() async throws {
        let url = try location()
        let store = try PendingBuildWriteStore(url: url)
        let owner = try PendingWritePartition(environment: "fixture-e\u{301}", authority: "owner-e\u{301}")
        let session = try await store.activate(owner)
        let body = Data(#"{ "synthetic":true, "revision":9007199254740994, "rate":1.2300e+4 }"#.utf8)
        let write = try PendingBuildWrite(operationID: "operation-e\u{301}", method: .update,
                                          buildID: "build-e\u{301}", idempotencyKey: "key-e\u{301}",
                                          ifMatch: "\"9007199254740993\"", body: body)
        try await store.enqueue(write, session: session)
        let calls = Calls()
        let dispatcher = PendingBuildWriteDispatcher(store: store)

        let result = try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
            let rows = try await store.records(session: session)
            let durable = try XCTUnwrap(rows.first)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(durable.state, .attempting)
            XCTAssertEqual(durable.attemptID, attempt.attemptID)
            XCTAssertEqual(durable.write, write)
            XCTAssertEqual(attempt.partition, owner)
            XCTAssertEqual(attempt.write, write)
            XCTAssertEqual(attempt.write.body, body)
            XCTAssertEqual(Data(attempt.write.ifMatch!.utf8), Data("\"9007199254740993\"".utf8))
            XCTAssertEqual(Data(attempt.write.idempotencyKey.utf8), Data("key-e\u{301}".utf8))
            await calls.record(attempt)
            return .confirmed
        }

        assertRecorded(result, as: .confirmed)
        let observed = await calls.snapshot()
        XCTAssertEqual(observed.count, 1)
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows[0].state, .confirmed)
        XCTAssertEqual(rows[0].write, write)
        XCTAssertEqual(rows[0].attemptID, observed[0].attemptID)
    }

    func testAttemptCommitFailureNeverInvokesAdapter() async throws {
        let url = try location()
        let store = try fail(.beforeAttemptCommit, at: url)
        let session = try await store.activate(partition())
        let write = try intent()
        let saved = try await store.enqueue(write, session: session)
        let before = try files(url)
        let calls = Calls()
        let dispatcher = PendingBuildWriteDispatcher(store: store)

        await expectCommitFailure {
            _ = try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
                await calls.record(attempt)
                return .confirmed
            }
        }

        let observed = await calls.snapshot()
        XCTAssertTrue(observed.isEmpty)
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows, [saved])
        XCTAssertEqual(try files(url), before)
    }

    func testConfirmedAttemptAllowsExplicitSameBuildSuccessor() async throws {
        let store = try PendingBuildWriteStore(url: location())
        let session = try await store.activate(partition())
        let first = try intent()
        let next = try intent("operation-2", method: .update, ifMatch: "\"1\"")
        try await store.enqueue(first, session: session)
        try await store.enqueue(next, session: session)
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        let calls = Calls()

        let firstResult = try await dispatcher.perform(operationID: first.operationID, session: session) { attempt in
            await calls.record(attempt)
            return .confirmed
        }
        assertRecorded(firstResult, as: .confirmed)
        let interim = try await store.records(session: session)
        XCTAssertEqual(interim.map(\.state), [.confirmed, .pending])
        let beforeNext = await calls.snapshot()
        XCTAssertEqual(beforeNext.map(\.write), [first])

        let nextResult = try await dispatcher.perform(operationID: next.operationID, session: session) { attempt in
            await calls.record(attempt)
            return .confirmed
        }
        assertRecorded(nextResult, as: .confirmed)
        let observed = await calls.snapshot()
        XCTAssertEqual(observed.map(\.write), [first, next])
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows.map(\.state), [.confirmed, .confirmed])
    }

    func testLostAcknowledgementStaysUncertainAcrossReopenWithoutResend() async throws {
        let url = try location()
        let owner = try partition()
        let store = try PendingBuildWriteStore(url: url)
        let session = try await store.activate(owner)
        let write = try intent(method: .update, ifMatch: "\"7\"")
        try await store.enqueue(write, session: session)
        let fixture = LostAcknowledgementFixture()
        let dispatcher = PendingBuildWriteDispatcher(store: store)

        let result = try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
            try await fixture.perform(attempt)
        }
        assertRecorded(result, as: .uncertain)
        let original = await fixture.snapshot()
        XCTAssertEqual(original.0.count, 1)
        XCTAssertEqual(original.1, [write])
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows[0].state, .uncertain)
        XCTAssertEqual(rows[0].write, write)
        XCTAssertEqual(rows[0].attemptID, original.0[0].attemptID)

        let reopened = try PendingBuildWriteStore(url: url)
        let current = try await reopened.activate(owner)
        let recovered = try await reopened.records(session: current)
        XCTAssertEqual(recovered, rows)
        let before = try files(url)
        let nextDispatcher = PendingBuildWriteDispatcher(store: reopened)
        await expect(.notPending) {
            _ = try await nextDispatcher.perform(operationID: write.operationID, session: current) { attempt in
                try await fixture.perform(attempt)
            }
        }
        let after = await fixture.snapshot()
        XCTAssertEqual(after.0, original.0)
        XCTAssertEqual(after.1, original.1)
        XCTAssertEqual(try files(url), before)
    }

    func testCancellationBeforeAttemptLeavesPendingWithoutAdapterCall() async throws {
        let url = try location()
        let store = try PendingBuildWriteStore(url: url)
        let session = try await store.activate(partition())
        let write = try intent()
        let saved = try await store.enqueue(write, session: session)
        let before = try files(url)
        let calls = Calls()
        let start = Signal()
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        let task = Task {
            await start.wait()
            return try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
                await calls.record(attempt)
                return .confirmed
            }
        }
        releaseAtTeardown(start, task: task)
        task.cancel()
        await start.release()
        do { _ = try await task.value; XCTFail("Expected cancellation before durable attempt") }
        catch { XCTAssertTrue(error is CancellationError) }
        let observed = await calls.snapshot()
        XCTAssertTrue(observed.isEmpty)
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows, [saved])
        XCTAssertEqual(try files(url), before)
    }

    func testCancellationDuringAttemptCommitNeverInvokesAdapter() async throws {
        let url = try location()
        let store = try PendingBuildWriteStore(url: url, fault: { point in
            if point == .beforeAttemptCommit {
                // This hook runs synchronously in the child operation's task.
                // Return normally so the durable attempt still commits.
                withUnsafeCurrentTask { current in current?.cancel() }
            }
        })
        let session = try await store.activate(partition())
        let write = try intent()
        let saved = try await store.enqueue(write, session: session)
        let calls = Calls()
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        let child = Task {
            let result = try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
                await calls.record(attempt)
                return .confirmed
            }
            return (result, Task.isCancelled)
        }

        let (result, childWasCancelled) = try await child.value
        XCTAssertTrue(childWasCancelled)
        XCTAssertFalse(Task.isCancelled)
        try Task.checkCancellation()
        assertRecorded(result, as: .uncertain)
        let observed = await calls.snapshot()
        XCTAssertTrue(observed.isEmpty)
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows.count, 1)
        let durable = try XCTUnwrap(rows.first)
        XCTAssertEqual(saved.state, .pending)
        XCTAssertEqual(durable.state, .uncertain)
        XCTAssertEqual(durable.write, write)
        XCTAssertNotNil(durable.attemptID)
        let reread = try await store.records(session: session)
        XCTAssertEqual(reread, rows)
    }

    func testCooperativeCancellationAfterHandoffRecordsUncertainty() async throws {
        let store = try PendingBuildWriteStore(url: location())
        let session = try await store.activate(partition())
        let write = try intent()
        try await store.enqueue(write, session: session)
        let calls = Calls()
        let entered = expectation(description: "Synthetic adapter entered")
        let finish = Signal()
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        let task = Task {
            try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
                await calls.record(attempt)
                entered.fulfill()
                await finish.wait()
                try Task.checkCancellation()
                return .confirmed
            }
        }
        releaseAtTeardown(finish, task: task)
        await fulfillment(of: [entered], timeout: 5)
        task.cancel()
        await finish.release()
        let result = try await task.value
        assertRecorded(result, as: .uncertain)
        let observed = await calls.snapshot()
        XCTAssertEqual(observed.count, 1)
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows[0].state, .uncertain)
        XCTAssertEqual(rows[0].write, write)
    }

    func testKnownConfirmationIsRecordedAfterTaskCancellation() async throws {
        let store = try PendingBuildWriteStore(url: location())
        let session = try await store.activate(partition())
        let write = try intent()
        try await store.enqueue(write, session: session)
        let calls = Calls()
        let responseKnown = expectation(description: "Validated synthetic response already obtained")
        let returnResponse = Signal()
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        let task = Task {
            try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
                await calls.record(attempt)
                let knownOutcome = PendingWriteOutcome.confirmed
                responseKnown.fulfill()
                await returnResponse.wait()
                XCTAssertTrue(Task.isCancelled)
                return knownOutcome
            }
        }
        releaseAtTeardown(returnResponse, task: task)
        await fulfillment(of: [responseKnown], timeout: 5)
        task.cancel()
        await returnResponse.release()
        let result = try await task.value
        assertRecorded(result, as: .confirmed)
        let observed = await calls.snapshot()
        XCTAssertEqual(observed.count, 1)
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows[0].state, .confirmed)
        XCTAssertEqual(rows[0].write, write)
    }

    func testDeactivationDuringAdapterWaitRejectsOldOutcome() async throws {
        let url = try location()
        let store = try PendingBuildWriteStore(url: url)
        let oldSession = try await store.activate(partition("old"))
        let oldWrite = try intent()
        try await store.enqueue(oldWrite, session: oldSession)
        let entered = expectation(description: "Old adapter entered")
        let finish = Signal()
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        let task = Task {
            try await dispatcher.perform(operationID: oldWrite.operationID, session: oldSession) { _ in
                entered.fulfill()
                await finish.wait()
                return .confirmed
            }
        }
        releaseAtTeardown(finish, task: task)
        await fulfillment(of: [entered], timeout: 5)
        try await store.deactivate(oldSession)
        let nextSession = try await store.activate(partition("new"))
        let nextWrite = try intent("new-operation", build: "new-build")
        let saved = try await store.enqueue(nextWrite, session: nextSession)
        let before = try files(url)
        await finish.release()
        let result = try await task.value
        guard case .notRecorded = result else { return XCTFail("Old outcome must not be recorded") }
        let rows = try await store.records(session: nextSession)
        XCTAssertEqual(rows, [saved])
        XCTAssertEqual(try files(url), before)
    }

    func testSwitchAwayAndBackCannotReviveSuspendedAdapter() async throws {
        let url = try location()
        let owner = try partition("a")
        let store = try PendingBuildWriteStore(url: url)
        let oldSession = try await store.activate(owner)
        let write = try intent()
        try await store.enqueue(write, session: oldSession)
        let entered = expectation(description: "First A adapter entered")
        let finish = Signal()
        let calls = Calls()
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        let task = Task {
            try await dispatcher.perform(operationID: write.operationID, session: oldSession) { attempt in
                await calls.record(attempt)
                entered.fulfill()
                await finish.wait()
                return .confirmed
            }
        }
        releaseAtTeardown(finish, task: task)
        await fulfillment(of: [entered], timeout: 5)
        let other = try await store.activate(partition("b"))
        try await store.deactivate(other)
        let current = try await store.activate(owner)
        XCTAssertNotEqual(current, oldSession)
        let before = try files(url)
        await finish.release()
        let result = try await task.value
        guard case .notRecorded = result else { return XCTFail("Old A callback must remain retired") }
        let observed = await calls.snapshot()
        XCTAssertEqual(observed.count, 1)
        let rows = try await store.records(session: current)
        XCTAssertEqual(rows[0].state, .uncertain)
        XCTAssertEqual(rows[0].write, write)
        XCTAssertEqual(rows[0].attemptID, observed[0].attemptID)
        await expect(.notPending) {
            _ = try await dispatcher.perform(operationID: write.operationID, session: current) { attempt in
                await calls.record(attempt)
                return .confirmed
            }
        }
        let after = await calls.snapshot()
        XCTAssertEqual(after, observed)
        XCTAssertEqual(try files(url), before)
    }

    func testConcurrentPerformOfSameOperationInvokesAdapterOnlyOnce() async throws {
        let store = try PendingBuildWriteStore(url: location())
        let session = try await store.activate(partition())
        let write = try intent()
        try await store.enqueue(write, session: session)
        let calls = Calls()
        let entered = expectation(description: "First invocation is held")
        let finish = Signal()
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        let first = Task {
            try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
                await calls.record(attempt)
                entered.fulfill()
                await finish.wait()
                return .confirmed
            }
        }
        releaseAtTeardown(finish, task: first)
        await fulfillment(of: [entered], timeout: 5)
        await expect(.notPending) {
            _ = try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
                await calls.record(attempt)
                return .confirmed
            }
        }
        let held = await calls.snapshot()
        XCTAssertEqual(held.count, 1)
        await finish.release()
        let result = try await first.value
        assertRecorded(result, as: .confirmed)
        let finished = await calls.snapshot()
        XCTAssertEqual(finished, held)
    }

    func testHeldBuildBlocksItsSuccessorButNotAnotherBuild() async throws {
        let store = try PendingBuildWriteStore(url: location())
        let session = try await store.activate(partition())
        let first = try intent()
        let next = try intent("next", method: .update, ifMatch: "\"1\"")
        let unrelated = try intent("other", build: "other-build")
        for write in [first, next, unrelated] { try await store.enqueue(write, session: session) }
        let entered = expectation(description: "First build adapter is held")
        let finish = Signal()
        let calls = Calls()
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        let held = Task {
            try await dispatcher.perform(operationID: first.operationID, session: session) { attempt in
                await calls.record(attempt)
                entered.fulfill()
                await finish.wait()
                return .confirmed
            }
        }
        releaseAtTeardown(finish, task: held)
        await fulfillment(of: [entered], timeout: 5)
        await expect(.blocked) {
            _ = try await dispatcher.perform(operationID: next.operationID, session: session) { attempt in
                await calls.record(attempt)
                return .confirmed
            }
        }
        let otherResult = try await dispatcher.perform(operationID: unrelated.operationID, session: session) { attempt in
            await calls.record(attempt)
            return .confirmed
        }
        assertRecorded(otherResult, as: .confirmed)
        let interim = try await store.records(session: session)
        XCTAssertEqual(interim.map(\.state), [.attempting, .pending, .confirmed])
        let observed = await calls.snapshot()
        XCTAssertEqual(observed.map(\.write), [first, unrelated])
        await finish.release()
        let result = try await held.value
        assertRecorded(result, as: .confirmed)
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows.map(\.state), [.confirmed, .pending, .confirmed])
    }

    func testValidatedConflictKeepsIntentAndBlocksFollower() async throws {
        try await assertRejection(.conflict, state: .conflict)
    }

    func testValidatedInvalidKeepsIntentAndBlocksFollower() async throws {
        try await assertRejection(.invalid, state: .invalid)
    }

    private func assertRejection(_ outcome: PendingWriteOutcome, state: PendingWriteState) async throws {
        let url = try location()
        let store = try PendingBuildWriteStore(url: url)
        let session = try await store.activate(partition())
        let first = try intent(method: .update, ifMatch: "\"7\"")
        let next = try intent("next", method: .update, ifMatch: "\"8\"")
        try await store.enqueue(first, session: session)
        try await store.enqueue(next, session: session)
        let calls = Calls()
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        let result = try await dispatcher.perform(operationID: first.operationID, session: session) { attempt in
            await calls.record(attempt)
            return outcome
        }
        assertRecorded(result, as: state)
        let before = try files(url)
        await expect(.blocked) {
            _ = try await dispatcher.perform(operationID: next.operationID, session: session) { attempt in
                await calls.record(attempt)
                return .confirmed
            }
        }
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows.map(\.state), [state, .pending])
        XCTAssertEqual(rows.map(\.write), [first, next])
        let observed = await calls.snapshot()
        XCTAssertEqual(observed.map(\.write), [first])
        XCTAssertEqual(try files(url), before)
    }

    func testOutcomeCommitFailurePropagatesWithoutResend() async throws {
        let url = try location()
        let owner = try partition()
        let store = try fail(.beforeOutcomeCommit, at: url)
        let session = try await store.activate(owner)
        let write = try intent()
        try await store.enqueue(write, session: session)
        let calls = Calls()
        let dispatcher = PendingBuildWriteDispatcher(store: store)
        await expectCommitFailure {
            _ = try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
                await calls.record(attempt)
                return .confirmed
            }
        }
        let observed = await calls.snapshot()
        XCTAssertEqual(observed.count, 1)
        let rows = try await store.records(session: session)
        XCTAssertEqual(rows[0].state, .attempting)
        XCTAssertEqual(rows[0].write, write)
        XCTAssertEqual(rows[0].attemptID, observed[0].attemptID)
        await expect(.notPending) {
            _ = try await dispatcher.perform(operationID: write.operationID, session: session) { attempt in
                await calls.record(attempt)
                return .confirmed
            }
        }
        let reopened = try PendingBuildWriteStore(url: url)
        let current = try await reopened.activate(owner)
        let recovered = try await reopened.records(session: current)
        XCTAssertEqual(recovered[0].state, .uncertain)
        XCTAssertEqual(recovered[0].write, write)
        XCTAssertEqual(recovered[0].attemptID, observed[0].attemptID)
        let after = await calls.snapshot()
        XCTAssertEqual(after, observed)
    }
}
