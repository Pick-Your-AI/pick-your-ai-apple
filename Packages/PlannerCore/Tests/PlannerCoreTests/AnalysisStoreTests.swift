import XCTest
@testable import PlannerCore

// XCTest discovery crosses concurrency boundaries. This final test class has no
// mutable stored fields; all stores, tasks and request state are method-local.
final class AnalysisStoreTests: XCTestCase, @unchecked Sendable {
    private func identity(
        build: String = "build-a", revision: String = "1", catalog: String = "catalog-1"
    ) -> AnalysisIdentity {
        AnalysisIdentity(buildID: build, revision: revision, versionLocks: ["catalog": catalog])
    }

    func testThreeRevisionsCompleteOutOfOrder() async {
        let store = AnalysisStore<String>()
        let first = await store.begin(for: identity(revision: "1"))
        let second = await store.begin(for: identity(revision: "2"))
        let third = await store.begin(for: identity(revision: "3"))
        let acceptedThird = await store.receive("third", identity: third.identity, for: third)
        let acceptedFirst = await store.receive("first", identity: first.identity, for: first)
        let acceptedSecond = await store.receive("second", identity: second.identity, for: second)
        XCTAssertTrue(acceptedThird)
        XCTAssertFalse(acceptedFirst)
        XCTAssertFalse(acceptedSecond)
        let state = await store.state
        XCTAssertEqual(state, .current(request: third, value: "third"))
    }

    func testChangingBuildInvalidatesResultEvenAtSameRevision() async {
        let store = AnalysisStore<String>()
        let first = await store.begin(for: identity())
        await store.receive("old", identity: first.identity, for: first)
        let other = identity(build: "build-b")
        await store.select(other)
        let state = await store.state
        XCTAssertEqual(state, .unavailable(identity: other, reason: .notRequested))
        let accepted = await store.receive("late", identity: first.identity, for: first)
        XCTAssertFalse(accepted)
    }

    func testChangedLocksInvalidatePendingAndCurrentResults() async {
        let store = AnalysisStore<String>()
        let first = await store.begin(for: identity())
        let changed = identity(catalog: "catalog-2")
        await store.select(changed)
        let acceptedOld = await store.receive("old catalog", identity: first.identity, for: first)
        XCTAssertFalse(acceptedOld)
        let second = await store.begin(for: changed)
        await store.receive("new catalog", identity: second.identity, for: second)
        await store.select(identity(catalog: "catalog-3"))
        let state = await store.state
        XCTAssertEqual(state, .unavailable(identity: identity(catalog: "catalog-3"), reason: .notRequested))
    }

    func testSameRevisionRetryHasNewGeneration() async {
        let store = AnalysisStore<String>()
        let first = await store.begin(for: identity())
        let retry = await store.begin(for: identity())
        XCTAssertNotEqual(first.generation, retry.generation)
        let oldAccepted = await store.receive("old", identity: first.identity, for: first)
        let pending = await store.state
        XCTAssertFalse(oldAccepted)
        XCTAssertEqual(pending, .pending(retry))
        await store.receive("retry", identity: retry.identity, for: retry)
        let duplicate = await store.receive("duplicate", identity: retry.identity, for: retry)
        XCTAssertFalse(duplicate)
        let state = await store.state
        XCTAssertEqual(state, .current(request: retry, value: "retry"))
    }

    func testLateCancelAndFailureCannotEraseNewResult() async {
        let store = AnalysisStore<String>()
        let old = await store.begin(for: identity())
        let current = await store.begin(for: identity())
        await store.receive("current", identity: current.identity, for: current)
        let cancelled = await store.cancel(old)
        let failed = await store.fail(old)
        let lateCurrentFailure = await store.fail(current)
        XCTAssertFalse(cancelled)
        XCTAssertFalse(failed)
        XCTAssertFalse(lateCurrentFailure)
        let state = await store.state
        XCTAssertEqual(state, .current(request: current, value: "current"))
    }

    func testCancelledTaskCannotPublishAfterRetry() async {
        let store = AnalysisStore<String>()
        let old = await store.begin(for: identity())
        // A continuation controls completion order without timing or sleeps.
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate.stream { break }
            // Deliberately ignore cancellation, as a late transport callback may.
            return await store.receive("cancelled transport", identity: old.identity, for: old)
        }
        let cancelled = await store.cancel(old)
        XCTAssertTrue(cancelled)
        let cancelledState = await store.state
        XCTAssertEqual(cancelledState, .unavailable(identity: identity(), reason: .cancelled))
        let retry = await store.begin(for: identity())
        await store.receive("retry", identity: retry.identity, for: retry)
        task.cancel()
        gate.continuation.yield(())
        gate.continuation.finish()
        let accepted = await task.value
        XCTAssertFalse(accepted)
        let state = await store.state
        XCTAssertEqual(state, .current(request: retry, value: "retry"))
    }

    func testClearAndReconnectRejectOldCallbacks() async {
        let store = AnalysisStore<String>()
        let original = await store.begin(for: identity())
        await store.clear()
        let cleared = await store.state
        XCTAssertEqual(cleared, .unavailable(identity: nil, reason: .notRequested))
        let oldAccepted = await store.receive("old", identity: original.identity, for: original)
        XCTAssertFalse(oldAccepted)
        let connection = await store.begin(for: identity())
        await store.disconnect()
        let disconnected = await store.state
        XCTAssertEqual(disconnected, .unavailable(identity: identity(), reason: .disconnected))
        let retry = await store.begin(for: identity())
        let staleAccepted = await store.receive("disconnected", identity: connection.identity, for: connection)
        let staleCancelled = await store.cancel(connection)
        XCTAssertFalse(staleAccepted)
        XCTAssertFalse(staleCancelled)
        await store.receive("reconnected", identity: retry.identity, for: retry)
        let state = await store.state
        XCTAssertEqual(state, .current(request: retry, value: "reconnected"))
    }

    func testFailureIsExplicitAndRetryCanRecover() async {
        let store = AnalysisStore<String>()
        let request = await store.begin(for: identity())
        let failed = await store.fail(request)
        XCTAssertTrue(failed)
        let state = await store.state
        XCTAssertEqual(state, .unavailable(identity: identity(), reason: .failed))
        let late = await store.receive("late", identity: request.identity, for: request)
        XCTAssertFalse(late)
        let retry = await store.begin(for: identity())
        let accepted = await store.receive("recovered", identity: retry.identity, for: retry)
        XCTAssertTrue(accepted)
    }

    func testIdenticalSelectionPreservesCurrentResultAndForeignStoreCannotSupplyIt() async {
        let store = AnalysisStore<String>()
        let otherStore = AnalysisStore<String>()
        let request = await store.begin(for: identity())
        let foreign = await otherStore.begin(for: identity())
        let accepted = await store.receive("foreign", identity: foreign.identity, for: foreign)
        XCTAssertFalse(accepted)
        await store.receive("valid", identity: request.identity, for: request)
        await store.select(identity())
        let state = await store.state
        XCTAssertEqual(state, .current(request: request, value: "valid"))
    }

    func testMismatchedResponseBuildRevisionAndLocksLeaveRequestPending() async {
        let store = AnalysisStore<String>()
        let requestedIdentity = identity()
        let request = await store.begin(for: requestedIdentity)
        let mismatches = [
            identity(build: "wrong-build"),
            identity(revision: "wrong-revision"),
            identity(catalog: "wrong-catalog"),
            AnalysisIdentity(buildID: "build-a", revision: "1", versionLocks: [:])
        ]
        for responseIdentity in mismatches {
            let accepted = await store.receive(
                "wrong response", identity: responseIdentity, for: request
            )
            XCTAssertFalse(accepted)
            let pending = await store.state
            XCTAssertEqual(pending, .pending(request))
        }
        // A rejected response must not consume the active attempt: a subsequently
        // validated matching result can still complete it.
        let accepted = await store.receive(
            "validated", identity: requestedIdentity, for: request
        )
        XCTAssertTrue(accepted)
        let state = await store.state
        XCTAssertEqual(state, .current(request: request, value: "validated"))
    }

}
