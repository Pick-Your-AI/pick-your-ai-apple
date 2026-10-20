import Foundation
import XCTest
import PlannerCatalog
@testable import PlannerTransfer

/// Package input admission only: no native form, durable save or live graph claim.
final class BuildDependencyGraphInputTests: XCTestCase, @unchecked Sendable {
    private let expectedSHA256 = "e9b3bca19a9cf8241fd74f6618824882a3413649822add88be1ac93cb3f1bacc"

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func encoded(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func build(graphID: String? = nil, graphRevision: Decimal? = nil) throws -> BuildSnapshot {
        var parser = try JSONParser(fixture("build"))
        var object = try parser.parse().object!
        var locks = object["locks"]!.object!
        if let graphID { locks["dependency_graph_id"] = .string(graphID) }
        if let graphRevision { locks["dependency_graph_revision"] = .number(graphRevision) }
        object["locks"] = .object(locks)
        return try BuildTransfer.snapshot(fromDraftJSON: encoded(.object(object)))
    }

    func testProductionBundleMatchesIndependentFrozenFixtureAndQualification() throws {
        let original = try build()
        let before = try original.encoded()
        let input = try BuildDependencyGraphInput.bundledSynthetic(for: original)
        let frozen = try fixture("dependency-graph")
        XCTAssertEqual(frozen.count, 17_959)
        XCTAssertEqual(try CatalogCache.sha256(frozen), expectedSHA256)
        XCTAssertEqual(input.originalBytes, frozen)
        XCTAssertEqual(input.sha256, expectedSHA256)
        XCTAssertEqual(input.qualification, .frozenSyntheticFixture)
        XCTAssertEqual(input.graph, try DependencyGraph.decode(frozen))
        XCTAssertEqual(input.graph.id, "dependencies.core.1")
        XCTAssertEqual(input.graph.revision, 1)
        XCTAssertEqual(input.graph.edges.count, 59)
        XCTAssertEqual(try original.encoded(), before)
    }

    func testForeignGraphIDIsUnavailableWithoutFallback() throws {
        let foreign = try build(graphID: "dependencies.synthetic.other")
        let before = try foreign.encoded()
        XCTAssertThrowsError(try BuildDependencyGraphInput.bundledSynthetic(for: foreign)) {
            XCTAssertEqual($0 as? BuildDependencyGraphInputError, .graphLockMismatch)
        }
        XCTAssertEqual(try foreign.encoded(), before)
        XCTAssertNoThrow(try BuildDependencyGraphInput.bundledSynthetic(for: build()))
    }

    func testDifferentGraphRevisionsAreUnavailableWithoutNarrowing() throws {
        // The trailing zero keeps this admitted large integer within 15 significant digits.
        for revision in [Decimal(2), try XCTUnwrap(Decimal(string: "9007199254740990"))] {
            let other = try build(graphRevision: revision)
            XCTAssertEqual(other.locks.object?["dependency_graph_revision"], .number(revision))
            let before = try other.encoded()
            XCTAssertThrowsError(try BuildDependencyGraphInput.bundledSynthetic(for: other)) {
                XCTAssertEqual($0 as? BuildDependencyGraphInputError, .graphLockMismatch)
            }
            XCTAssertEqual(try other.encoded(), before)
        }
        let outsideNumericDomain = try XCTUnwrap(Decimal(string: "9007199254740993"))
        XCTAssertThrowsError(try build(graphRevision: outsideNumericDomain)) {
            XCTAssertEqual($0 as? TransferError, .unsupportedNumber)
        }
    }

    func testSchemaValidTamperAtSameIdentityIsRejected() throws {
        let original = try build()
        let frozen = try fixture("dependency-graph")
        let graph = try DependencyGraph.decode(frozen)
        var object = graph.value.object!
        var edges = object["edges"]!.array!
        var first = edges[0].object!
        first["rationale"] = .string(first["rationale"]!.string! + " Changed synthetic rationale.")
        edges[0] = .object(first)
        object["edges"] = .array(edges)
        let changed = try encoded(.object(object))
        let otherwiseAdmitted = try DependencyGraph.decode(changed)
        XCTAssertEqual(otherwiseAdmitted.id, graph.id)
        XCTAssertEqual(otherwiseAdmitted.revision, graph.revision)
        XCTAssertNotEqual(otherwiseAdmitted, graph)
        XCTAssertThrowsError(try BuildDependencyGraphInput.admitBundledSyntheticBytes(changed, for: original)) {
            XCTAssertEqual($0 as? BuildDependencyGraphInputError, .artifactMismatch)
        }
        XCTAssertEqual(try BuildDependencyGraphInput.admitBundledSyntheticBytes(frozen, for: original).graph, graph)
    }

    func testEquivalentJSONSpellingCannotReplacePinnedOriginalBytes() throws {
        let original = try build()
        let frozen = try fixture("dependency-graph")
        var changed = frozen
        changed.append(contentsOf: [32, 10])
        XCTAssertEqual(try DependencyGraph.decode(changed), try DependencyGraph.decode(frozen))
        XCTAssertThrowsError(try BuildDependencyGraphInput.admitBundledSyntheticBytes(changed, for: original)) {
            XCTAssertEqual($0 as? BuildDependencyGraphInputError, .artifactMismatch)
        }
    }

    func testOversizedAndTruncatedInputsCannotProduceAGraph() throws {
        let original = try build()
        XCTAssertThrowsError(try BuildDependencyGraphInput.admitBundledSyntheticBytes(
            Data(repeating: 32, count: BuildTransfer.maximumBytes + 1), for: original
        )) {
            XCTAssertEqual($0 as? BuildDependencyGraphInputError, .oversizedResource)
        }
        var truncated = try fixture("dependency-graph")
        truncated.removeLast(2)
        XCTAssertThrowsError(try DependencyGraph.decode(truncated))
        for invalid in [Data(), Data("not JSON".utf8), truncated] {
            XCTAssertThrowsError(try BuildDependencyGraphInput.admitBundledSyntheticBytes(invalid, for: original)) {
                XCTAssertEqual($0 as? BuildDependencyGraphInputError, .artifactMismatch)
            }
        }
    }

    func testAdmittedBytesAndGraphRemainImmutableAfterCallerMutation() throws {
        let original = try build()
        let before = try original.encoded()
        var supplied = try fixture("dependency-graph")
        let frozen = supplied
        let input = try BuildDependencyGraphInput.admitBundledSyntheticBytes(supplied, for: original)
        let graph = input.graph
        supplied.resetBytes(in: 0..<supplied.count)
        var borrowed = input.originalBytes
        borrowed.removeAll()
        XCTAssertNotEqual(supplied, frozen)
        XCTAssertTrue(borrowed.isEmpty)
        XCTAssertEqual(input.originalBytes, frozen)
        XCTAssertEqual(input.graph, graph)
        XCTAssertEqual(input.sha256, expectedSHA256)
        XCTAssertEqual(input.qualification, .frozenSyntheticFixture)
        XCTAssertEqual(try original.encoded(), before)
    }

    func testAdmittedGraphFeedsTheExistingUncommittedSettingsBoundary() throws {
        let original = try build()
        let before = try original.encoded()
        let input = try BuildDependencyGraphInput.bundledSynthetic(for: original)
        let field = try XCTUnwrap(BuildEditableField.objectives().first { $0.name == "region" })
        let oldRegion = try XCTUnwrap(original.value.object?["objectives"]?.object?["region"]?.string)
        let value = try BuildEditValue(json: encoded(.string(oldRegion + "-synthetic")))
        let unknown = BuildEditEnvironment(mode: nil, production: nil)
        let proposal = try BuildSettingsEdit.prepare(
            build: original, graph: input.graph, target: .objectives,
            changes: [.set(field, value)], before: unknown, after: unknown,
            updatedAt: "2026-10-20T20:00:00Z"
        )
        XCTAssertEqual(proposal.original, original)
        XCTAssertEqual(proposal.graph, input.graph)
        XCTAssertEqual(proposal.proposed.locks, original.locks)
        XCTAssertEqual(proposal.proposed.value.object?["objectives"]?.object?["region"], .string(oldRegion + "-synthetic"))
        guard case .objectivesRequireFullRecheck = proposal.impact else {
            return XCTFail("An objective change requires a new complete check.")
        }
        XCTAssertEqual(try original.encoded(), before)
        XCTAssertEqual(input.originalBytes, try fixture("dependency-graph"))
    }
}
