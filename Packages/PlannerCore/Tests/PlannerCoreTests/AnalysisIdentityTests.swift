import XCTest
@testable import PlannerCore

// Every actor and request is method-local; discovery shares no mutable test state.
final class AnalysisIdentityTests: XCTestCase, @unchecked Sendable {
    private enum Field: String, CaseIterable { case buildID, revision, lockKey, lockValue }
    private enum Completion: String, CaseIterable { case receive, fail, cancel }
    private struct Pair {
        let label: String
        let requested: AnalysisIdentity
        let other: AnalysisIdentity
    }

    private func identity(_ field: Field, _ text: String) -> AnalysisIdentity {
        var build = "build-a", revision = "1"
        var locks = ["catalog": "catalog-1", "ruleset": "ruleset-1"]
        switch field {
        case .buildID: build = text
        case .revision: revision = text
        case .lockKey: locks = ["catalog.\(text)": "catalog-1", "ruleset": "ruleset-1"]
        case .lockValue: locks["catalog"] = text
        }
        return AnalysisIdentity(buildID: build, revision: revision, versionLocks: locks)
    }

    private func byteDistinctPairs() -> [Pair] {
        let composed = "caf\u{00e9}", decomposed = "cafe\u{0301}"
        return Field.allCases.flatMap { field in
            [
                Pair(label: "\(field.rawValue), composed request", requested: identity(field, composed),
                     other: identity(field, decomposed)),
                Pair(label: "\(field.rawValue), decomposed request", requested: identity(field, decomposed),
                     other: identity(field, composed))
            ]
        }
    }

    private func exactReorderedPair() -> (AnalysisIdentity, AnalysisIdentity) {
        var forward: [String: String] = [:]
        forward["catalog.caf\u{00e9}"] = "version.cafe\u{0301}"
        forward["ruleset"] = "ruleset-1"
        var reverse: [String: String] = [:]
        reverse["ruleset"] = "ruleset-1"
        reverse["catalog.caf\u{00e9}"] = "version.cafe\u{0301}"
        return (
            AnalysisIdentity(buildID: "build.caf\u{00e9}", revision: "1", versionLocks: forward),
            AnalysisIdentity(buildID: "build.caf\u{00e9}", revision: "1", versionLocks: reverse)
        )
    }

    func testCanonicallyEquivalentOpaqueFieldsRemainDifferentInputs() {
        XCTAssertEqual("caf\u{00e9}", "cafe\u{0301}", "Swift text equality is intentionally canonical")
        XCTAssertFalse("caf\u{00e9}".utf8.elementsEqual("cafe\u{0301}".utf8))
        for pair in byteDistinctPairs() {
            XCTAssertNotEqual(pair.requested, pair.other, pair.label)
        }
    }

    func testLockMapOrderHasNoMeaningAndEveryEntryIsRequired() {
        let (first, reordered) = exactReorderedPair()
        XCTAssertEqual(first, reordered)
        var missing = first.versionLocks
        missing.removeValue(forKey: "ruleset")
        XCTAssertNotEqual(first, AnalysisIdentity(buildID: first.buildID, revision: first.revision, versionLocks: missing))
        var changed = first.versionLocks
        changed["ruleset"] = "ruleset-2"
        XCTAssertNotEqual(first, AnalysisIdentity(buildID: first.buildID, revision: first.revision, versionLocks: changed))
        let empty = AnalysisIdentity(buildID: "", revision: "", versionLocks: [:])
        XCTAssertEqual(empty, AnalysisIdentity(buildID: "", revision: "", versionLocks: [:]))
    }

    func testByteDistinctResponseIsRejectedWithoutConsumingRequest() async {
        for pair in byteDistinctPairs() {
            let store = AnalysisStore<String>()
            let request = await store.begin(for: pair.requested)
            let mismatched = await store.receive("mismatched", identity: pair.other, for: request)
            XCTAssertFalse(mismatched, pair.label)
            let pending = await store.state
            XCTAssertEqual(pending, .pending(request), pair.label)
            let recovered = await store.receive("exact", identity: pair.requested, for: request)
            XCTAssertTrue(recovered, pair.label)
            let current = await store.state
            XCTAssertEqual(current, .current(request: request, value: "exact"), pair.label)
        }
    }

    func testByteDistinctSelectionRetiresEachPendingCompletion() async {
        for pair in byteDistinctPairs() {
            for completion in Completion.allCases {
                let message = "\(pair.label): late \(completion.rawValue)"
                let store = AnalysisStore<String>()
                let old = await store.begin(for: pair.requested)
                await store.select(pair.other)
                let applied: Bool
                switch completion {
                case .receive: applied = await store.receive("old", identity: pair.requested, for: old)
                case .fail: applied = await store.fail(old)
                case .cancel: applied = await store.cancel(old)
                }
                XCTAssertFalse(applied, message)
                let invalidated = await store.state
                XCTAssertEqual(invalidated, .unavailable(identity: pair.other, reason: .notRequested), message)
                let next = await store.begin(for: pair.other)
                let accepted = await store.receive("new", identity: pair.other, for: next)
                XCTAssertTrue(accepted, message)
                let current = await store.state
                XCTAssertEqual(current, .current(request: next, value: "new"), message)
            }
        }
    }

    func testByteDistinctSelectionInvalidatesCurrentResult() async {
        for pair in byteDistinctPairs() {
            let store = AnalysisStore<String>()
            let request = await store.begin(for: pair.requested)
            let accepted = await store.receive("old", identity: pair.requested, for: request)
            XCTAssertTrue(accepted, pair.label)
            await store.select(pair.other)
            let invalidated = await store.state
            XCTAssertEqual(invalidated, .unavailable(identity: pair.other, reason: .notRequested), pair.label)
        }
    }

    func testExactReselectionPreservesBothPendingAndCurrentStates() async {
        let (original, reordered) = exactReorderedPair()
        let store = AnalysisStore<String>()
        let request = await store.begin(for: original)
        await store.select(reordered)
        let pending = await store.state
        XCTAssertEqual(pending, .pending(request))
        let accepted = await store.receive("exact", identity: reordered, for: request)
        XCTAssertTrue(accepted)
        await store.select(original)
        let current = await store.state
        XCTAssertEqual(current, .current(request: request, value: "exact"))
    }
}
