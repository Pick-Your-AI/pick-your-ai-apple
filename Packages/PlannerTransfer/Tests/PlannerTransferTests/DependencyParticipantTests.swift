import Foundation
import PlannerCore
import XCTest
@testable import PlannerTransfer

final class DependencyParticipantTests: XCTestCase {
    private typealias Context = DependencyInvalidation.Context<CatalogKind>
    private typealias Selection = DependencyInvalidation.Selection<CatalogKind>

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json")))
    }

    private func context(_ mode: DependencyInvalidation.Mode? = .api,
                         kinds: [CatalogKind] = [], production: Bool? = false) -> Context {
        Context(selections: kinds.map { Selection(id: "selection_\($0.rawValue)", kind: $0, enabled: true) },
                mode: mode, production: production)
    }

    private func graphWithEdges(_ rows: [[String: Any]]) throws -> DependencyGraph {
        var source = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("dependency-graph")) as? [String: Any])
        source["edges"] = rows
        return try DependencyGraph.decode(JSONSerialization.data(withJSONObject: source, options: .sortedKeys))
    }

    private func row(_ id: String, _ activation: String, dependent: String = "accelerator",
                     dependency: String = "model", relationship: String = "constrains") -> [String: Any] {
        ["id": id, "dependent_kind": dependent, "depends_on_kind": dependency,
         "relationship": relationship, "activation": activation, "rationale": "Synthetic participant probe"]
    }

    func testActualFrozenModeOnlyEdgeReachesBothEndpointsAndKeepsGraphIdentity() throws {
        let graph = try DependencyGraph.decode(fixture("dependency-graph"))
        let original = try graph.encoded()
        let index = try XCTUnwrap(graph.edges.firstIndex { $0.id == "dep.accelerator.model" })
        XCTAssertEqual(graph.edges[index].dependentKind, .accelerator)
        XCTAssertEqual(graph.edges[index].dependsOnKind, .model)
        XCTAssertEqual(graph.edges[index].activation, .selfHosted)
        let api = context(.api, kinds: [.deploymentMode, .model, .accelerator])
        let local = context(.selfHosted, kinds: [.deploymentMode, .model, .accelerator])
        for (before, after) in [(api, local), (local, api)] {
            let plan = graph.affectedParticipants(changedKinds: [.deploymentMode], before: before, after: after)
            XCTAssertEqual(plan.graphID, graph.id)
            XCTAssertEqual(plan.graphRevision, graph.revision)
            XCTAssertEqual(plan.participants.changedKinds, [.deploymentMode])
            XCTAssertTrue(plan.participants.participatingEdges.contains { $0.edgeIndex == index })
            XCTAssertTrue(plan.participants.affectedKinds.isSuperset(of: [.accelerator, .model]))
            XCTAssertEqual(plan.participants.affectedSelectionIDs,
                           ["selection_deployment_mode", "selection_model", "selection_accelerator"])
        }
        XCTAssertEqual(try graph.encoded(), original)
        XCTAssertEqual(graph.edges.count, 59)
    }

    func testEachFrozenActivationHasItsOwnExplicitAdapterBehavior() throws {
        let labels = DependencyActivation.allCases
        let graph = try graphWithEdges(labels.enumerated().map { row("dep.synthetic.\($0.offset)", $0.element.rawValue) })
        let before = context()
        let cases: [(Context, Set<DependencyActivation>)] = [
            (context(.managed), [.nonAPI]),
            (context(.selfHosted), [.selfHosted, .nonAPI]),
            (context(.hybrid), [.selfHosted, .nonAPI]),
            (context(kinds: [.ragPipeline]), [.ragEnabled]),
            (context(kinds: [.agentFramework]), [.agentsEnabled]),
            (context(kinds: [.trainingFramework]), [.fineTuningEnabled]),
            (context(kinds: [.trainingCompute]), [.fineTuningEnabled]),
            (context(kinds: [.trainingDataset]), [.fineTuningEnabled]),
            (context(kinds: [.fineTunedModel]), [.fineTuningEnabled]),
            (context(kinds: [.model, .accelerator]), [.ifSelected]),
            (context(production: true), [.productionOnly]),
            (context(nil, production: nil), [.selfHosted, .nonAPI, .productionOnly])
        ]
        for (after, expected) in cases {
            let plan = graph.affectedParticipants(changedKinds: [], before: before, after: after)
            let actual = Set(plan.participants.participatingEdges.map { graph.edges[$0.edgeIndex].activation })
            XCTAssertEqual(actual, expected)
        }
        let all = context(.hybrid, kinds: CatalogKind.allCases, production: true)
        let incident = graph.affectedParticipants(changedKinds: [.model], before: all, after: all)
        XCTAssertEqual(incident.participants.participatingEdges.map(\.edgeIndex), Array(labels.indices))
        XCTAssertTrue(incident.participants.participatingEdges.allSatisfy { $0.before == .active && $0.after == .active })
    }

    func testGraphDuplicatesCyclesAndRelationshipLabelsRemainSourceEvidence() throws {
        let rows = [row("dep.same", "always", dependent: "model", dependency: "context_policy", relationship: "requires"),
                    row("dep.reverse", "always", dependent: "context_policy", dependency: "model", relationship: "informs"),
                    row("dep.same", "always", dependent: "model", dependency: "context_policy", relationship: "produces"),
                    row("dep.self", "always", dependent: "model", dependency: "model")]
        let graph = try graphWithEdges(rows)
        let original = try graph.encoded()
        let value = context(kinds: [.model, .contextPolicy])
        let plan = graph.affectedParticipants(changedKinds: [.model], before: value, after: value)
        XCTAssertEqual(plan.participants.participatingEdges.map(\.edgeIndex), [0, 1, 2, 3])
        XCTAssertEqual(plan.participants.affectedKinds, [.model, .contextPolicy])
        XCTAssertEqual(graph.edges.map(\.id), ["dep.same", "dep.reverse", "dep.same", "dep.self"])
        XCTAssertEqual(graph.edges.map(\.relationship), [.requires, .informs, .produces, .constrains])
        XCTAssertEqual(try graph.encoded(), original)
    }

    func testValidatedBuildContextRetainsDisabledAndRemovedSelectionIdentities() throws {
        let data = try fixture("build")
        let original = try BuildTransfer.snapshot(fromDraftJSON: data)
        // Retain exact fixture decimals; Foundation's NSNumber bridge can change
        // fractional digits before the bounded JSON parser sees the new draft.
        var root = try XCTUnwrap(original.value.object)
        var rows = try XCTUnwrap(root["selections"]?.array)
        XCTAssertGreaterThan(rows.count, 2)
        var first = try XCTUnwrap(rows[0].object)
        let removed = try XCTUnwrap(rows[1].object)
        let oldID = try XCTUnwrap(first["id"]?.string)
        let removedID = try XCTUnwrap(removed["id"]?.string)
        let oldKind = try XCTUnwrap(CatalogKind(rawValue: XCTUnwrap(first["kind"]?.string)))
        let removedKind = try XCTUnwrap(CatalogKind(rawValue: XCTUnwrap(removed["kind"]?.string)))
        first["enabled"] = .bool(false)
        rows[0] = .object(first)
        rows.remove(at: 1)
        root["selections"] = .array(rows)
        root["revision"] = .number(2)
        let changed = try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(root)))
        XCTAssertEqual(changed.value, .object(root))
        let before = original.dependencyContext(mode: nil, production: nil)
        let after = changed.dependencyContext(mode: nil, production: nil)
        XCTAssertNil(before.mode)
        XCTAssertNil(before.production)
        XCTAssertEqual(after.selections.first?.id, oldID)
        XCTAssertEqual(after.selections.first?.enabled, false)
        XCTAssertFalse(after.selections.contains { $0.id == removedID })
        let graph = try DependencyGraph.decode(fixture("dependency-graph"))
        let plan = graph.affectedParticipants(changedKinds: [oldKind, removedKind], before: before, after: after)
        XCTAssertTrue(plan.participants.affectedSelectionIDs.contains(oldID))
        XCTAssertTrue(plan.participants.affectedSelectionIDs.contains(removedID))
        XCTAssertEqual(before.selections.count, rows.count + 1)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: original.encoded()), original)
    }

    func testMalformedBuildAndGraphStillRejectBeforeAnyAdapterProjection() throws {
        var build = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("build")) as? [String: Any])
        var selections = try XCTUnwrap(build["selections"] as? [[String: Any]])
        selections[0]["enabled"] = NSNull()
        build["selections"] = selections
        XCTAssertThrowsError(try BuildTransfer.snapshot(fromDraftJSON: JSONSerialization.data(withJSONObject: build)))
        XCTAssertThrowsError(try graphWithEdges([row("dep.bad", "future_activation")]))
        let original = try BuildTransfer.snapshot(fromDraftJSON: fixture("build"))
        XCTAssertFalse(original.dependencyContext(mode: nil, production: nil).selections.isEmpty)
    }
}
