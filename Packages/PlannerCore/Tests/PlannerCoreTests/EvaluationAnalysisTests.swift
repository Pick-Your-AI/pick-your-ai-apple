import Foundation
import XCTest
@testable import PlannerCore

// All report bytes are the frozen synthetic fixture or explicit test mutations.
// This final class has no mutable state shared across XCTest discovery boundaries.
final class EvaluationAnalysisTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "evaluation-report", withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "evaluation-report", withExtension: "json")
        )
        return try Data(contentsOf: url)
    }

    private func report(changing fields: [String: Any] = [:]) throws -> EvaluationReport {
        if fields.isEmpty { return try EvaluationReport.decode(fixture()) }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        for (key, value) in fields { object[key] = value }
        return try EvaluationReport.decode(JSONSerialization.data(withJSONObject: object))
    }

    // Expected inputs are supplied independently of the response under test.
    private func expected(revision: Int = 1) -> AnalysisIdentity {
        .frozenV1Evaluation(
            buildID: "build.fixture.1",
            buildRevision: revision,
            catalogSnapshotID: "catalog.fixture.1",
            rulesetID: "rules.fixture.1",
            rulesetVersion: "1.0.0",
            dependencyGraphID: "dependencies.core.1",
            dependencyGraphRevision: 1
        )
    }

    func testMatchingDecodedReportPreservesOriginalFindingsAndReadiness() async throws {
        let value = try report()
        let store = AnalysisStore<EvaluationReport>()
        let request = await store.begin(for: expected())
        let accepted = await store.receive(value, for: request)
        XCTAssertTrue(accepted)
        let state = await store.state
        XCTAssertEqual(state, .current(request: request, value: value))
        XCTAssertEqual(value.result, .valid)
        XCTAssertEqual(value.deploymentReadiness, .needsReview)
        XCTAssertEqual(value.findings.count, 45)
        XCTAssertEqual(value.findings.filter { $0.outcome == .skipped }.count, 4)
        XCTAssertEqual(value.findings.first?.severity, .error)
        XCTAssertEqual(value, try EvaluationReport.decode(JSONEncoder().encode(value)))
    }

    func testEachDecodedResponseIdentityMismatchRemainsPendingThenRecovers() async throws {
        let store = AnalysisStore<EvaluationReport>()
        let request = await store.begin(for: expected())
        let mismatches: [(String, Any)] = [
            ("build_id", "build.fixture.other"),
            ("build_revision", 2),
            ("catalog_snapshot_id", "catalog.fixture.other"),
            ("ruleset_id", "rules.fixture.other"),
            ("ruleset_version", "1.0.1"),
            ("dependency_graph_id", "dependencies.core.other"),
            ("dependency_graph_revision", 2)
        ]
        for (field, changed) in mismatches {
            let value = try report(changing: [field: changed])
            let accepted = await store.receive(value, for: request)
            XCTAssertFalse(accepted, field)
            let state = await store.state
            XCTAssertEqual(state, .pending(request), field)
        }
        let matching = try report()
        let accepted = await store.receive(matching, for: request)
        XCTAssertTrue(accepted)
        let state = await store.state
        XCTAssertEqual(state, .current(request: request, value: matching))
    }

    func testChangedSelectedPinsInvalidateCurrentReportBeforeAnotherResponse() async throws {
        let store = AnalysisStore<EvaluationReport>()
        let first = await store.begin(for: expected())
        let original = try report()
        let accepted = await store.receive(original, for: first)
        XCTAssertTrue(accepted)
        let newInputs = AnalysisIdentity.frozenV1Evaluation(
            buildID: "build.fixture.1", buildRevision: 1,
            catalogSnapshotID: "catalog.fixture.other",
            rulesetID: "rules.fixture.1", rulesetVersion: "1.0.0",
            dependencyGraphID: "dependencies.core.1", dependencyGraphRevision: 1
        )
        await store.select(newInputs)
        let unavailable = await store.state
        XCTAssertEqual(unavailable, .unavailable(identity: newInputs, reason: .notRequested))
        let current = await store.begin(for: newInputs)
        let oldAccepted = await store.receive(original, for: current)
        XCTAssertFalse(oldAccepted)
        let matching = try report(changing: ["catalog_snapshot_id": "catalog.fixture.other"])
        let currentAccepted = await store.receive(matching, for: current)
        XCTAssertTrue(currentAccepted)
        let state = await store.state
        XCTAssertEqual(state, .current(request: current, value: matching))
    }

    func testThreeDecodedRevisionsAcrossReconnectRejectLateReportsAndCancellation() async throws {
        let store = AnalysisStore<EvaluationReport>()
        let firstReport = try report()
        let secondReport = try report(changing: ["build_revision": 2])
        let thirdReport = try report(changing: ["build_revision": 3])
        let first = await store.begin(for: expected(revision: 1))
        let second = await store.begin(for: expected(revision: 2))
        let disconnectedThird = await store.begin(for: expected(revision: 3))
        await store.disconnect()
        let disconnected = await store.state
        XCTAssertEqual(disconnected, .unavailable(identity: expected(revision: 3), reason: .disconnected))

        let current = await store.begin(for: expected(revision: 3))
        XCTAssertNotEqual(current.generation, disconnectedThird.generation)
        let oldThirdAccepted = await store.receive(thirdReport, for: disconnectedThird)
        XCTAssertFalse(oldThirdAccepted)
        let pending = await store.state
        XCTAssertEqual(pending, .pending(current))
        // Deliver the three revisions in the controlled order 3, 1, 2. No timer
        // or cooperative network cancellation is used to enforce correctness.
        let thirdAccepted = await store.receive(thirdReport, for: current)
        let firstAccepted = await store.receive(firstReport, for: first)
        let secondAccepted = await store.receive(secondReport, for: second)
        XCTAssertTrue(thirdAccepted)
        XCTAssertFalse(firstAccepted)
        XCTAssertFalse(secondAccepted)
        for obsolete in [first, second, disconnectedThird, current] {
            let cancelled = await store.cancel(obsolete)
            let failed = await store.fail(obsolete)
            XCTAssertFalse(cancelled)
            XCTAssertFalse(failed)
        }
        let state = await store.state
        XCTAssertEqual(state, .current(request: current, value: thirdReport))
    }

    func testSameRevisionRetryForeignTokensAndDuplicatesCannotReplaceCurrentReport() async throws {
        let value = try report()
        let store = AnalysisStore<EvaluationReport>()
        let otherStore = AnalysisStore<EvaluationReport>()
        let first = await store.begin(for: expected())
        let retry = await store.begin(for: expected())
        let foreign = await otherStore.begin(for: expected())
        let oldAccepted = await store.receive(value, for: first)
        let foreignAccepted = await store.receive(value, for: foreign)
        XCTAssertFalse(oldAccepted)
        XCTAssertFalse(foreignAccepted)
        let pending = await store.state
        XCTAssertEqual(pending, .pending(retry))
        let accepted = await store.receive(value, for: retry)
        XCTAssertTrue(accepted)
        let replacement = try report(changing: ["id": "evaluation.build.fixture.other"])
        let duplicateAccepted = await store.receive(replacement, for: retry)
        XCTAssertFalse(duplicateAccepted)
        let state = await store.state
        XCTAssertEqual(state, .current(request: retry, value: value))
    }

    func testUnrecognizedExpectedLockIsNotSilentlyDiscarded() async throws {
        let value = try report()
        let canonical = expected()
        var locks = canonical.versionLocks
        locks["unrecognized_input"] = "must-not-be-ignored"
        let complete = AnalysisIdentity(buildID: canonical.buildID, revision: canonical.revision, versionLocks: locks)
        let store = AnalysisStore<EvaluationReport>()
        let request = await store.begin(for: complete)
        let accepted = await store.receive(value, for: request)
        XCTAssertFalse(accepted)
        let state = await store.state
        XCTAssertEqual(state, .pending(request))
    }

    func testOutputMetadataAndUnknownClaimsDoNotAlterInputIdentity() async throws {
        let value = try report(changing: [
            "id": "evaluation.build.fixture.other",
            "evaluated_at": "2026-10-16T10:30:00+01:30",
            "result": "indeterminate",
            "deployment_readiness": "blocked",
            "summary": ["passed": 0, "failed": 0, "unknown": 45, "skipped": 0]
        ])
        let store = AnalysisStore<EvaluationReport>()
        let request = await store.begin(for: expected())
        let accepted = await store.receive(value, for: request)
        XCTAssertTrue(accepted)
        let state = await store.state
        XCTAssertEqual(state, .current(request: request, value: value))
        XCTAssertEqual(value.result, .indeterminate)
        XCTAssertEqual(value.deploymentReadiness, .blocked)
        XCTAssertEqual(value.summary.unknown, 45)
        // The adapter preserves the wire report. It does not manufacture a new
        // summary/findings consistency rule or turn unknown into pass.
        XCTAssertEqual(value.findings.filter { $0.outcome == .skipped }.count, 4)
    }
}
