import Foundation
import Observation
import PlannerCore
import PlannerTransfer
import XCTest
@testable import PlannerUI

/// Frozen synthetic build/report bytes; no evaluator, network, or fake Core store.
@MainActor
final class EvaluationAnalysisModelTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func report(_ changes: [String: Any] = [:]) throws -> EvaluationReport {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("evaluation-analysis-report")) as? [String: Any])
        for (key, value) in changes { object[key] = value }
        return try EvaluationReport.decode(JSONSerialization.data(withJSONObject: object))
    }

    // Independently supplied expected inputs, never taken from the response.
    private func identity(revision: Int = 1) -> AnalysisIdentity {
        .frozenV1Evaluation(buildID: "build.fixture.1", buildRevision: revision,
            catalogSnapshotID: "catalog.fixture.1", rulesetID: "rules.fixture.1", rulesetVersion: "1.0.0",
            dependencyGraphID: "dependencies.core.1", dependencyGraphRevision: 1)
    }

    private func begin(_ model: EvaluationAnalysisModel) async throws -> AnalysisRequest {
        let request = await model.begin()
        return try XCTUnwrap(request)
    }

    // Keep XCTest's legacy, non-Sendable Result inside its nonisolated call.
    // Only the immutable Boolean outcome crosses back to this test's MainActor.
    private nonisolated static func wasFulfilled(_ expectation: XCTestExpectation) async -> Bool {
        await XCTWaiter.fulfillment(of: [expectation], timeout: 5) == .completed
    }

    /// The MainActor operation reaches its first suspension before this helper
    /// resumes. A Core queue barrier then controls arrival order without sleeps.
    private func launched<Value: Sendable>(
        _ operation: @escaping @MainActor () async -> Value
    ) async -> Task<Value, Never> {
        let started = expectation(description: "MainActor operation started")
        let task = Task { started.fulfill(); return await operation() }
        let arrived = await Self.wasFulfilled(started)
        XCTAssertTrue(arrived)
        return task
    }

    func testNoSelectionCannotBeginOrDisplayAReportAndObservationTracksCurrentness() async throws {
        let model = EvaluationAnalysisModel()
        let absent = await model.begin()
        XCTAssertNil(absent)
        XCTAssertEqual(model.presentation(for: nil), .unavailable(.notRequested))
        XCTAssertEqual(model.presentation(for: identity()), .unavailable(.notRequested))
        let changed = expectation(description: "Observable presentation changes")
        withObservationTracking {
            _ = model.presentation(for: identity())
        } onChange: {
            changed.fulfill()
        }
        model.select(identity())
        let notified = await Self.wasFulfilled(changed)
        XCTAssertTrue(notified)
        let request = try await begin(model)
        let value = try report()
        let accepted = await model.receive(value, for: request)
        XCTAssertTrue(accepted)
        XCTAssertEqual(model.presentation(for: identity()), .current(value))
        XCTAssertEqual(value.findings.count, 45)
        XCTAssertEqual(value.findings.filter { $0.outcome == .skipped }.count, 4)
        XCTAssertEqual(value.deploymentReadiness, .needsReview)
        XCTAssertEqual(model.presentation(for: identity(revision: 2)), .unavailable(.notRequested))
        XCTAssertEqual(model.presentation(for: nil), .unavailable(.notRequested))
    }

    func testEveryForeignResponsePinKeepsMatchingRequestPendingThenRecovers() async throws {
        let model = EvaluationAnalysisModel()
        model.select(identity())
        let request = try await begin(model)
        let mismatches: [(String, Any)] = [
            ("build_id", "build.other"), ("build_revision", 2),
            ("catalog_snapshot_id", "catalog.other"), ("ruleset_id", "rules.other"),
            ("ruleset_version", "1.0.1"), ("dependency_graph_id", "dependencies.other"),
            ("dependency_graph_revision", 2)
        ]
        for (key, value) in mismatches {
            let accepted = await model.receive(try report([key: value]), for: request)
            XCTAssertFalse(accepted, key)
            XCTAssertEqual(model.presentation(for: identity()), .pending, key)
        }
        let value = try report()
        let accepted = await model.receive(value, for: request)
        XCTAssertTrue(accepted)
        XCTAssertEqual(model.presentation(for: identity()), .current(value))
    }

    func testThreeRevisionsReconnectCompleteOutOfOrderWithoutLateCancellationErasingCurrent() async throws {
        let model = EvaluationAnalysisModel()
        var requests: [AnalysisRequest] = []
        for revision in 1...3 {
            model.select(identity(revision: revision))
            requests.append(try await begin(model))
        }
        model.disconnect()
        XCTAssertEqual(model.presentation(for: identity(revision: 3)), .unavailable(.disconnected))
        let resumed = try await begin(model)
        XCTAssertNotEqual(resumed, requests[2])
        let third = try report(["build_revision": 3])
        let retiredThird = await model.receive(third, for: requests[2])
        XCTAssertFalse(retiredThird)
        let latest = await model.receive(third, for: resumed)
        XCTAssertTrue(latest)
        // Complete revisions in explicit order 3, 1, 2 after reconnection.
        for revision in 1...2 {
            let stale = await model.receive(try report(["build_revision": revision]), for: requests[revision - 1])
            XCTAssertFalse(stale)
        }
        for request in requests + [resumed] {
            let cancelled = await model.cancel(request)
            let failed = await model.fail(request)
            XCTAssertFalse(cancelled)
            XCTAssertFalse(failed)
        }
        XCTAssertEqual(model.presentation(for: identity(revision: 3)), .current(third))
    }

    func testRetryRejectsForeignTokensAndDuplicateCompletionsWithoutRewritingClaims() async throws {
        let model = EvaluationAnalysisModel()
        model.select(identity())
        let old = try await begin(model)
        let retry = try await begin(model)
        let foreignStore = AnalysisStore<EvaluationReport>()
        let foreign = await foreignStore.begin(for: identity())
        let value = try report(["result": "indeterminate", "deployment_readiness": "blocked"])
        for request in [old, foreign] {
            let accepted = await model.receive(value, for: request)
            let cancelled = await model.cancel(request)
            let failed = await model.fail(request)
            XCTAssertFalse(accepted)
            XCTAssertFalse(cancelled)
            XCTAssertFalse(failed)
        }
        XCTAssertEqual(model.presentation(for: identity()), .pending)
        let accepted = await model.receive(value, for: retry)
        XCTAssertTrue(accepted)
        let duplicate = await model.receive(try report(["id": "evaluation.other"]), for: retry)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(model.presentation(for: identity()), .current(value))
        XCTAssertEqual(value.result, .indeterminate)
        XCTAssertEqual(value.deploymentReadiness, .blocked)
    }

    func testSelectionClearsVisibleResultBeforeBlockedCoreTransitionAndSamePinsNeedExplicitOwnerClear() async throws {
        let model = EvaluationAnalysisModel()
        model.select(identity())
        let request = try await begin(model)
        let value = try report()
        _ = await model.receive(value, for: request)
        model.select(identity()) // Same wire inputs, same local owner.
        XCTAssertEqual(model.presentation(for: identity()), .current(value))
        let gate = AnalysisCommandGate()
        model.enqueue { await gate.hold() }
        await gate.waitUntilEntered()
        model.select(identity(revision: 2))
        XCTAssertEqual(model.presentation(for: identity()), .unavailable(.notRequested))
        XCTAssertEqual(model.presentation(for: identity(revision: 2)), .unavailable(.notRequested))
        model.clear()
        model.select(identity()) // A different local row may carry the same wire pins.
        XCTAssertEqual(model.presentation(for: identity()), .unavailable(.notRequested))
        await gate.open()
        let fresh = try await begin(model)
        let oldAccepted = await model.receive(value, for: request)
        let freshAccepted = await model.receive(value, for: fresh)
        XCTAssertFalse(oldAccepted)
        XCTAssertTrue(freshAccepted)
    }

    func testSupersededQueuedBeginCannotInstallItsTokenForTheLaterSelection() async throws {
        let model = EvaluationAnalysisModel()
        model.select(identity())
        let gate = AnalysisCommandGate()
        model.enqueue { await gate.hold() }
        await gate.waitUntilEntered()
        let first = await launched { await model.begin() }
        XCTAssertEqual(model.presentation(for: self.identity()), .pending)
        model.select(identity(revision: 2))
        let second = await launched { await model.begin() }
        await gate.open()
        let obsolete = await first.value
        let current = await second.value
        XCTAssertNil(obsolete)
        let request = try XCTUnwrap(current)
        XCTAssertEqual(request.identity, identity(revision: 2))
        let value = try report(["build_revision": 2])
        let accepted = await model.receive(value, for: request)
        XCTAssertTrue(accepted)
        XCTAssertEqual(model.presentation(for: identity(revision: 2)), .current(value))
    }

    func testQueuedCompletionCannotReturnAfterDisconnectAndClearAsCurrent() async throws {
        let model = EvaluationAnalysisModel()
        model.select(identity())
        let request = try await begin(model)
        let value = try report()
        let gate = AnalysisCommandGate()
        model.enqueue { await gate.hold() }
        await gate.waitUntilEntered()
        let completion = await launched { await model.receive(value, for: request) }
        model.disconnect()
        XCTAssertEqual(model.presentation(for: identity()), .unavailable(.disconnected))
        model.clear()
        model.select(identity())
        await gate.open()
        let accepted = await completion.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(model.presentation(for: identity()), .unavailable(.notRequested))
        let retry = try await begin(model)
        let recovered = await model.receive(value, for: retry)
        XCTAssertTrue(recovered)
    }

    func testCoreCompletionWinsBeforeQueuedCancellationAndRetainsCurrentReport() async throws {
        let model = EvaluationAnalysisModel()
        model.select(identity())
        let request = try await begin(model)
        let value = try report()
        let gate = AnalysisCommandGate()
        model.enqueue { await gate.hold() }
        await gate.waitUntilEntered()
        let completion = await launched { await model.receive(value, for: request) }
        let cancellation = await launched { await model.cancel(request) }
        await gate.open()
        let accepted = await completion.value
        let cancelled = await cancellation.value
        XCTAssertTrue(accepted)
        XCTAssertFalse(cancelled)
        XCTAssertEqual(model.presentation(for: identity()), .current(value))
    }

    func testCoreCancellationWinsBeforeCompletionThenRetryRecovers() async throws {
        let model = EvaluationAnalysisModel()
        model.select(identity())
        let request = try await begin(model)
        let value = try report()
        let gate = AnalysisCommandGate()
        model.enqueue { await gate.hold() }
        await gate.waitUntilEntered()
        let cancellation = await launched { await model.cancel(request) }
        let completion = await launched { await model.receive(value, for: request) }
        await gate.open()
        let cancelled = await cancellation.value
        let accepted = await completion.value
        XCTAssertTrue(cancelled)
        XCTAssertFalse(accepted)
        XCTAssertEqual(model.presentation(for: identity()), .unavailable(.cancelled))
        let retry = try await begin(model)
        let recovered = await model.receive(value, for: retry)
        XCTAssertTrue(recovered)
    }

    func testCancelledBeginStillDrainsItsCoreCommandAndCannotReturnATransportToken() async throws {
        let model = EvaluationAnalysisModel()
        model.select(identity())
        let gate = AnalysisCommandGate()
        model.enqueue { await gate.hold() }
        await gate.waitUntilEntered()
        let cancelled = await launched { await model.begin() }
        cancelled.cancel()
        await gate.open()
        let token = await cancelled.value
        XCTAssertNil(token)
        XCTAssertEqual(model.presentation(for: identity()), .unavailable(.cancelled))
        let request = try await begin(model)
        let accepted = await model.receive(try report(), for: request)
        XCTAssertTrue(accepted)
    }

    func testFailureIsRetryableAndObsoleteFailureCannotClearTheLatestMatchingResult() async throws {
        let model = EvaluationAnalysisModel()
        model.select(identity())
        let failedRequest = try await begin(model)
        let failed = await model.fail(failedRequest)
        XCTAssertTrue(failed)
        XCTAssertEqual(model.presentation(for: identity()), .unavailable(.failed))
        let retry = try await begin(model)
        let value = try report()
        let accepted = await model.receive(value, for: retry)
        let staleFailure = await model.fail(failedRequest)
        XCTAssertTrue(accepted)
        XCTAssertFalse(staleFailure)
        XCTAssertEqual(model.presentation(for: identity()), .current(value))
    }

    func testVisibleIdentityRequiresExactTextAndCompletePinsEvenWhenModelIsCurrent() async throws {
        let model = EvaluationAnalysisModel()
        let canonical = identity()
        model.select(canonical)
        let request = try await begin(model)
        _ = await model.receive(try report(), for: request)
        var extra = canonical.versionLocks
        extra["unrecognized_pin"] = "must-not-be-dropped"
        let expanded = AnalysisIdentity(buildID: canonical.buildID, revision: canonical.revision, versionLocks: extra)
        XCTAssertEqual(model.presentation(for: expanded), .unavailable(.notRequested))
        let composed = AnalysisIdentity(buildID: "build.caf\u{e9}", revision: "1", versionLocks: canonical.versionLocks)
        let decomposed = AnalysisIdentity(buildID: "build.cafe\u{301}", revision: "1", versionLocks: canonical.versionLocks)
        model.select(composed)
        _ = try await begin(model)
        // The generic identity boundary preserves exact text. Frozen v1 report
        // IDs are ASCII; do not fabricate a valid non-ASCII wire report here.
        XCTAssertEqual(model.presentation(for: decomposed), .unavailable(.notRequested))
        XCTAssertEqual(model.presentation(for: composed), .pending)
    }

    func testValidatedBuildProjectionUsesWireRevisionAndAllFivePinsWithoutMutatingBytes() async throws {
        let bytes = try fixture("evaluation-analysis-build")
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: bytes)
        let before = try snapshot.encoded()
        XCTAssertEqual(snapshot.evaluationAnalysisIdentity, identity())
        XCTAssertEqual(try snapshot.encoded(), before)
        // DOCUMENTED LIMIT, not desired behavior: the frozen-v1 report wire cannot
        // carry pricebook_id, so builds differing only in it share one identity.
        // Mutate the admitted exact values without a binary floating-point
        // dictionary round trip changing unrelated fractional fixture tokens.
        guard case .object(var build) = snapshot.value,
              case .object(var locks)? = build["locks"] else {
            return XCTFail("Expected the complete synthetic build object and locks")
        }
        locks["pricebook_id"] = .string("prices.other")
        build["locks"] = .object(locks)
        let pricebookOnly = try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(build)))
        XCTAssertEqual(pricebookOnly.evaluationAnalysisIdentity, snapshot.evaluationAnalysisIdentity,
                       "Documented limit: pricebook_id is not representable in the report identity")
        build["revision"] = .number(7)
        let changed = try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(build)))
        XCTAssertEqual(changed.evaluationAnalysisIdentity, identity(revision: 7))
        XCTAssertEqual(snapshot.evaluationAnalysisIdentity, identity())
    }

    func testLargeSupportedWireRevisionAndChangedSelectedPinsAreProjectedExactly() async throws {
        let original = try BuildTransfer.snapshot(fromDraftJSON: fixture("evaluation-analysis-build"))
        guard case .object(var build) = original.value,
              case .object(var locks)? = build["locks"] else {
            return XCTFail("Expected the complete synthetic build object and locks")
        }
        let largeFifteenDigitRevision = 999_999_999_999_999
        build["revision"] = .number(Decimal(largeFifteenDigitRevision))
        locks["dependency_graph_revision"] = .number(Decimal(largeFifteenDigitRevision))
        locks["catalog_snapshot_id"] = .string("catalog.selected")
        locks["ruleset_id"] = .string("rules.selected")
        locks["ruleset_version"] = .string("2.0.0")
        locks["dependency_graph_id"] = .string("dependencies.selected")
        build["locks"] = .object(locks)
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(build)))
        XCTAssertEqual(snapshot.evaluationAnalysisIdentity, .frozenV1Evaluation(
            buildID: "build.fixture.1", buildRevision: largeFifteenDigitRevision,
            catalogSnapshotID: "catalog.selected", rulesetID: "rules.selected", rulesetVersion: "2.0.0",
            dependencyGraphID: "dependencies.selected", dependencyGraphRevision: largeFifteenDigitRevision))
    }
}

private actor AnalysisCommandGate {
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func hold() async {
        entered = true
        for continuation in entryWaiters { continuation.resume() }
        entryWaiters.removeAll()
        await withCheckedContinuation { waiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() { waiter?.resume(); waiter = nil }
}
