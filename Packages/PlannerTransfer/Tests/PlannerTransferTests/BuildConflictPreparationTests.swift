import Foundation
import XCTest
@testable import PlannerTransfer

/// Fictional local values only. These tests do not contact a service or commit a draft.
final class BuildConflictPreparationTests: XCTestCase, @unchecked Sendable {
    private func build(_ changes: [String: JSONValue] = [:]) throws -> BuildSnapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "build", withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        var object = try XCTUnwrap(parser.parse().object)
        for (key, value) in changes { object[key] = value }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try BuildTransfer.snapshot(fromDraftJSON: encoder.encode(JSONValue.object(object)))
    }

    private func session() throws -> (BuildConflictSession, UUID, BuildSnapshot, BuildSnapshot) {
        let local = try build(["name": .string("Private local edit")])
        let incoming = try build(["name": .string("Private incoming edit")])
        let context = UUID()
        return (try BuildConflictSession(local: local, incoming: incoming, contextID: context),
                context, local, incoming)
    }

    private func stale(_ operation: () async throws -> BuildConflictProposal,
                       file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Expected stale local review", file: file, line: line) }
        catch { XCTAssertEqual(error as? BuildConflictError, .staleReview, file: file, line: line) }
    }

    func testSameRevisionDivergentEditsRetainBothCompleteSnapshots() throws {
        let local = try build(["name": .string("local"), "extensions": .object([
            "x_private": .object(["note": .string("local private text"), "optional": .null])])])
        let incoming = try build(["name": .string("incoming"), "extensions": .object([
            "x_private": .object(["note": .string("incoming private text")])])])
        let localBytes = try local.encoded(), incomingBytes = try incoming.encoded()
        let pair = try BuildConflictPair(local: local, incoming: incoming)
        XCTAssertEqual(pair.local.value.object?["revision"], pair.incoming.value.object?["revision"])
        XCTAssertEqual(try pair.local.encoded(), localBytes)
        XCTAssertEqual(try pair.incoming.encoded(), incomingBytes)
        XCTAssertEqual(pair.differences.map(\.path), ["/extensions/x_private/note", "/extensions/x_private/optional", "/name"])
        XCTAssertEqual(pair.differences[1].localValue, .null)
        XCTAssertNil(pair.differences[1].incomingValue)
    }

    func testDifferencesKeepMissingNullArrayOrderAndEscapedPathsDistinct() throws {
        let left: JSONValue = .object(["x_data": .object([
            "a/b~c": .string("left"), "ordered": .array([.number(1), .number(2)]), "gone": .null])])
        let right: JSONValue = .object(["x_data": .object([
            "a/b~c": .string("right"), "ordered": .array([.number(2), .number(1)]), "new": .null])])
        let pair = try BuildConflictPair(local: build(["extensions": left]), incoming: build(["extensions": right]))
        XCTAssertEqual(pair.differences.map(\.path), ["/extensions/x_data/a~1b~0c", "/extensions/x_data/gone", "/extensions/x_data/new", "/extensions/x_data/ordered"])
        XCTAssertEqual(pair.differences[0].localValue, .string("left"))
        XCTAssertEqual(pair.differences[0].incomingValue, .string("right"))
        XCTAssertEqual(pair.differences[1].localValue, .null); XCTAssertNil(pair.differences[1].incomingValue)
        XCTAssertNil(pair.differences[2].localValue); XCTAssertEqual(pair.differences[2].incomingValue, .null)
        XCTAssertEqual(pair.differences[3].localValue, .array([.number(1), .number(2)]))
        XCTAssertEqual(pair.differences[3].incomingValue, .array([.number(2), .number(1)]))
    }

    func testUnicodeKeysAndValuesUseExactUTF8InsteadOfCanonicalEquivalence() throws {
        let composed = "caf\u{e9}", decomposed = "cafe\u{301}"
        XCTAssertEqual(composed, decomposed) // Native String equality is deliberately insufficient.
        let local = try build(["name": .string(composed), "extensions": .object([
            "x_data": .object([composed: .string("same")])])])
        let incoming = try build(["name": .string(decomposed), "extensions": .object([
            "x_data": .object([decomposed: .string("same")])])])
        let differences = try BuildConflictPair(local: local, incoming: incoming).differences
        XCTAssertEqual(differences.count, 3)
        XCTAssertEqual(Array(differences[0].path.utf8), Array(("/extensions/x_data/" + decomposed).utf8))
        XCTAssertEqual(Array(differences[1].path.utf8), Array(("/extensions/x_data/" + composed).utf8))
        XCTAssertNil(differences[0].localValue); XCTAssertNil(differences[1].incomingValue)
        XCTAssertEqual(differences[2].path, "/name")
        XCTAssertNotEqual(differences[2].localValue, differences[2].incomingValue)
    }

    func testIdenticalValuesHaveNoDifferencesAndRemainAvailable() throws {
        let source = try build()
        let pair = try BuildConflictPair(local: source, incoming: source)
        XCTAssertEqual(pair.local, source); XCTAssertEqual(pair.incoming, source)
        XCTAssertTrue(pair.differences.isEmpty)
    }

    func testDifferentBuildAndExactOwnerIdentitiesRejectWithoutMutation() throws {
        let local = try build(["owner_ref": .string("owner.caf\u{e9}")])
        let before = try local.encoded()
        XCTAssertThrowsError(try BuildConflictPair(local: local, incoming: build(["id": .string("build.other")]))) {
            XCTAssertEqual($0 as? BuildConflictError, .differentBuild)
        }
        XCTAssertThrowsError(try BuildConflictPair(local: local, incoming: build(["owner_ref": .string("owner.cafe\u{301}")]))) {
            XCTAssertEqual($0 as? BuildConflictError, .differentOwner)
        }
        XCTAssertEqual(try local.encoded(), before)
    }

    func testExplicitKeepChoicesReturnUnmodifiedSnapshotsAndBothOriginals() async throws {
        let (session, context, local, incoming) = try session()
        for choice in [BuildConflictChoice.keepLocal, .keepIncoming] {
            let review = await session.beginReview()
            let result = try await session.prepare(review, choice: choice, currentContextID: context,
                currentLocal: local, currentIncoming: incoming)
            XCTAssertEqual(result.choice, choice)
            XCTAssertEqual(result.selected, choice == .keepLocal ? local : incoming)
            XCTAssertEqual(result.conflict.local, local); XCTAssertEqual(result.conflict.incoming, incoming)
            XCTAssertEqual(session.conflict, result.conflict)
        }
    }

    func testRevisionOrderingDoesNotSelectAWinnerOrRewriteTheChosenValue() async throws {
        let local = try build(["revision": .number(1), "name": .string("keep my edit")])
        let incoming = try build(["revision": .number(200), "name": .string("newer supplied revision")])
        let context = UUID(), session = try BuildConflictSession(local: local, incoming: incoming, contextID: context)
        let review = await session.beginReview()
        XCTAssertTrue(review.conflict.differences.contains { $0.path == "/revision" })
        let proposal = try await session.prepare(review, choice: .keepLocal, currentContextID: context,
            currentLocal: local, currentIncoming: incoming)
        XCTAssertEqual(proposal.selected, local)
        XCTAssertEqual(proposal.selected.value.object?["revision"], .number(1))
        XCTAssertEqual(proposal.conflict.incoming, incoming)
    }

    func testPreparationIsOneUseButBothInputsSurviveARequiredFreshRetry() async throws {
        let (session, context, local, incoming) = try session()
        let review = await session.beginReview()
        let first = try await session.prepare(review, choice: .keepLocal, currentContextID: context,
            currentLocal: local, currentIncoming: incoming)
        // The caller has NOT committed first.selected. A failed later write cannot
        // make the old decision reusable or remove either source from this session.
        await stale { try await session.prepare(review, choice: .keepIncoming, currentContextID: context,
            currentLocal: local, currentIncoming: incoming) }
        XCTAssertEqual(session.conflict, first.conflict)
        let fresh = await session.beginReview()
        let retry = try await session.prepare(fresh, choice: .keepIncoming, currentContextID: context,
            currentLocal: local, currentIncoming: incoming)
        XCTAssertEqual(retry.selected, incoming)
        XCTAssertEqual(retry.conflict, first.conflict)
    }

    func testCancellationInvalidatesReviewAndRetainsTheCompletePair() async throws {
        let (session, context, local, incoming) = try session()
        let review = await session.beginReview()
        await session.cancelReview()
        await stale { try await session.prepare(review, choice: .keepLocal, currentContextID: context,
            currentLocal: local, currentIncoming: incoming) }
        XCTAssertEqual(session.conflict.local, local); XCTAssertEqual(session.conflict.incoming, incoming)
    }

    func testSupersededReviewCannotConsumeTheCurrentReview() async throws {
        let (session, context, local, incoming) = try session()
        let old = await session.beginReview(), current = await session.beginReview()
        await stale { try await session.prepare(old, choice: .keepLocal, currentContextID: context,
            currentLocal: local, currentIncoming: incoming) }
        let proposal = try await session.prepare(current, choice: .keepIncoming, currentContextID: context,
            currentLocal: local, currentIncoming: incoming)
        XCTAssertEqual(proposal.selected, incoming)
    }

    func testTokenCannotCrossSessionsWithIdenticalInputsAndContext() async throws {
        let (first, context, local, incoming) = try session()
        let second = try BuildConflictSession(local: local, incoming: incoming, contextID: context)
        let foreign = await first.beginReview(), own = await second.beginReview()
        await stale { try await second.prepare(foreign, choice: .keepLocal, currentContextID: context,
            currentLocal: local, currentIncoming: incoming) }
        let proposal = try await second.prepare(own, choice: .keepLocal, currentContextID: context,
            currentLocal: local, currentIncoming: incoming)
        XCTAssertEqual(proposal.selected, local)
    }

    func testChangedLocalValueRetiresReviewEvenIfTheOldValueReturns() async throws {
        let (session, context, local, incoming) = try session()
        let review = await session.beginReview(), changed = try build(["name": .string("another local edit")])
        await stale { try await session.prepare(review, choice: .keepLocal, currentContextID: context,
            currentLocal: changed, currentIncoming: incoming) }
        await stale { try await session.prepare(review, choice: .keepLocal, currentContextID: context,
            currentLocal: local, currentIncoming: incoming) }
        XCTAssertEqual(session.conflict.local, local); XCTAssertEqual(session.conflict.incoming, incoming)
    }

    func testChangedIncomingValueRetiresReviewEvenIfTheOldValueReturns() async throws {
        let (session, context, local, incoming) = try session()
        let review = await session.beginReview(), changed = try build(["name": .string("another incoming edit")])
        await stale { try await session.prepare(review, choice: .keepIncoming, currentContextID: context,
            currentLocal: local, currentIncoming: changed) }
        await stale { try await session.prepare(review, choice: .keepIncoming, currentContextID: context,
            currentLocal: local, currentIncoming: incoming) }
        XCTAssertEqual(session.conflict.local, local); XCTAssertEqual(session.conflict.incoming, incoming)
    }

    func testChangedContextAndAwayBackTransitionCannotReuseReview() async throws {
        let (session, context, local, incoming) = try session()
        let review = await session.beginReview()
        await stale { try await session.prepare(review, choice: .keepLocal, currentContextID: UUID(),
            currentLocal: local, currentIncoming: incoming) }
        await stale { try await session.prepare(review, choice: .keepLocal, currentContextID: context,
            currentLocal: local, currentIncoming: incoming) }
        XCTAssertEqual(session.conflict.local, local); XCTAssertEqual(session.conflict.incoming, incoming)
    }

    func testConcurrentPreparationProducesExactlyOneProposal() async throws {
        let (session, context, local, incoming) = try session()
        let review = await session.beginReview()
        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for choice in [BuildConflictChoice.keepLocal, .keepIncoming] {
                group.addTask {
                    do {
                        _ = try await session.prepare(review, choice: choice, currentContextID: context,
                            currentLocal: local, currentIncoming: incoming)
                        return true
                    } catch { return false }
                }
            }
            var count = 0
            for await success in group { if success { count += 1 } }
            return count
        }
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(session.conflict.local, local); XCTAssertEqual(session.conflict.incoming, incoming)
    }
}
