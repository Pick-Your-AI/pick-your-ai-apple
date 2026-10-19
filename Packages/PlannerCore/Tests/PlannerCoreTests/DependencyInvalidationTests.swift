import XCTest
@testable import PlannerCore

final class DependencyInvalidationTests: XCTestCase {
    // Synthetic client kinds, not a second frozen-v1 catalog enumeration.
    private enum Kind: String, DependencyParticipantKind {
        case deploymentMode, model, contextPolicy, accelerator, knowledgeBase, tool, unrelated
        case ragPipeline, agentFramework, trainingFramework, trainingCompute, trainingDataset, fineTunedModel
    }
    private typealias Edge = DependencyInvalidation.Edge<Kind>
    private typealias Selection = DependencyInvalidation.Selection<Kind>
    private typealias Context = DependencyInvalidation.Context<Kind>
    private typealias Activity = DependencyInvalidation.Activity

    private func selection(_ kind: Kind, _ id: String? = nil, enabled: Bool = true) -> Selection {
        Selection(id: id ?? "selection_\(kind.rawValue)", kind: kind, enabled: enabled)
    }

    private func context(_ mode: DependencyInvalidation.Mode? = .api,
                         selections: [Selection] = [], production: Bool? = false) -> Context {
        Context(selections: selections, mode: mode, production: production)
    }

    private func edge(_ activation: DependencyInvalidation.Activation,
                      _ dependent: Kind = .accelerator, _ dependency: Kind = .model) -> Edge {
        Edge(dependentKind: dependent, dependsOnKind: dependency, activation: activation)
    }

    func testServingModeActivationUsesExplicitUnknownAndHybrid() {
        let modes: [DependencyInvalidation.Mode?] = [nil, .api, .selfHosted, .hybrid]
        let expected: [Activity] = [.unknown, .inactive, .active, .active]
        for activation in [DependencyInvalidation.Activation.selfHosted, .nonAPI] {
            for (mode, result) in zip(modes, expected) {
                XCTAssertEqual(DependencyInvalidation.activity(of: edge(activation), in: context(mode)), result)
            }
        }
        XCTAssertEqual(DependencyInvalidation.activity(of: edge(.always), in: context(nil, production: nil)), .active)
    }

    func testProductionIsUnknownWithoutAnExplicitDecision() {
        for (production, expected) in [(Bool?.none, Activity.unknown), (false, .inactive), (true, .active)] {
            XCTAssertEqual(DependencyInvalidation.activity(of: edge(.productionOnly),
                in: context(production: production)), expected)
        }
    }

    func testIfSelectedNeedsBothEnabledEndpoints() {
        let cases: [([Selection], Activity)] = [
            ([], .inactive), ([selection(.model)], .inactive), ([selection(.accelerator)], .inactive),
            ([selection(.model), selection(.accelerator)], .active),
            ([selection(.model), selection(.accelerator, enabled: false)], .inactive),
            ([selection(.model, enabled: false), selection(.accelerator)], .inactive)
        ]
        for (selections, expected) in cases {
            XCTAssertEqual(DependencyInvalidation.activity(of: edge(.ifSelected),
                in: context(selections: selections)), expected)
        }
    }

    func testOptionalActivationUsesEnabledRoleMembershipAndAnyT5Kind() {
        let roles: [(DependencyInvalidation.Activation, [Kind])] = [
            (.ragEnabled, [.ragPipeline]), (.agentsEnabled, [.agentFramework]),
            (.fineTuningEnabled, [.trainingFramework, .trainingCompute, .trainingDataset, .fineTunedModel])
        ]
        for (activation, kinds) in roles {
            XCTAssertEqual(DependencyInvalidation.activity(of: edge(activation), in: context()), .inactive)
            for kind in kinds {
                XCTAssertEqual(DependencyInvalidation.activity(of: edge(activation),
                    in: context(selections: [selection(kind)])), .active)
                XCTAssertEqual(DependencyInvalidation.activity(of: edge(activation),
                    in: context(selections: [selection(kind, enabled: false)])), .inactive)
            }
        }
    }

    func testModeOnlyChangeReachesNonincidentAcceleratorModelInBothDirections() {
        let selections = [selection(.deploymentMode), selection(.model), selection(.accelerator)]
        let api = context(.api, selections: selections)
        let local = context(.selfHosted, selections: selections)
        for (before, after, old, new) in [(api, local, Activity.inactive, Activity.active),
                                          (local, api, .active, .inactive)] {
            let result = DependencyInvalidation.affectedParticipants(edges: [edge(.selfHosted)],
                changedKinds: [.deploymentMode], before: before, after: after)
            XCTAssertEqual(result.changedKinds, [.deploymentMode])
            XCTAssertEqual(result.affectedKinds, [.deploymentMode, .accelerator, .model])
            XCTAssertEqual(result.affectedSelectionIDs, selections.map(\.id))
            XCTAssertEqual(result.participatingEdges.map(\.edgeIndex), [0])
            XCTAssertEqual(result.participatingEdges.first?.before, old)
            XCTAssertEqual(result.participatingEdges.first?.after, new)
        }
    }

    func testEveryNonincidentModeUnknownTransitionHasAnExplicitDisposition() {
        typealias Mode = DependencyInvalidation.Mode
        let cases: [(Mode?, Mode?, Bool)] = [
            (nil, nil, false), (nil, .api, true), (nil, .selfHosted, true),
            (.api, nil, true), (.api, .api, false), (.api, .selfHosted, true),
            (.selfHosted, nil, true), (.selfHosted, .api, true), (.selfHosted, .selfHosted, false)
        ]
        for (old, new, participates) in cases {
            let result = DependencyInvalidation.affectedParticipants(edges: [edge(.selfHosted)],
                changedKinds: [.deploymentMode], before: context(old), after: context(new))
            XCTAssertEqual(result.participatingEdges.count, participates ? 1 : 0)
            XCTAssertEqual(result.affectedKinds.contains(.accelerator), participates)
            XCTAssertEqual(result.changedKinds, [.deploymentMode])
        }
    }

    func testStableUnknownIsConservativeOnlyForAnIncidentChange() {
        let unknown = context(nil, production: nil)
        let edges = [edge(.selfHosted), edge(.productionOnly, .tool, .knowledgeBase)]
        let result = DependencyInvalidation.affectedParticipants(edges: edges,
            changedKinds: [.model], before: unknown, after: unknown)
        XCTAssertEqual(result.participatingEdges.map(\.edgeIndex), [0])
        XCTAssertEqual(result.participatingEdges.first?.before, .unknown)
        XCTAssertEqual(result.participatingEdges.first?.after, .unknown)
        XCTAssertEqual(result.affectedKinds, [.model, .accelerator])
    }

    func testInactiveIncidentEdgeDoesNotExpandButChangedIdentityRemainsAffected() {
        let old = context(selections: [selection(.model), selection(.accelerator)])
        let result = DependencyInvalidation.affectedParticipants(edges: [edge(.selfHosted)],
            changedKinds: [.model], before: old, after: old)
        XCTAssertTrue(result.participatingEdges.isEmpty)
        XCTAssertEqual(result.affectedKinds, [.model])
        XCTAssertEqual(result.affectedSelectionIDs, ["selection_model"])
    }

    func testProductionUnknownTransitionReachesRemoteEndpoints() {
        let transitions: [(Bool?, Bool?)] = [(nil, false), (false, nil), (nil, true), (true, nil), (true, false), (false, true)]
        for (old, new) in transitions {
            let result = DependencyInvalidation.affectedParticipants(edges: [edge(.productionOnly, .tool, .model)],
                changedKinds: [.deploymentMode], before: context(production: old), after: context(production: new))
            XCTAssertEqual(result.affectedKinds, [.deploymentMode, .tool, .model])
            XCTAssertEqual(result.participatingEdges.map(\.edgeIndex), [0])
        }
    }

    func testOptionalDisableAndRemovalRetainOldAndNewAffectedIdentities() {
        let old = context(selections: [selection(.ragPipeline, "rag_old"), selection(.knowledgeBase, "kb_old"),
                                       selection(.model, "model_disabled", enabled: false), selection(.unrelated)])
        let disabled = context(selections: [selection(.ragPipeline, "rag_old", enabled: false),
                                            selection(.knowledgeBase, "kb_new"), selection(.unrelated)])
        let removed = context(selections: [selection(.knowledgeBase, "kb_new"), selection(.unrelated)])
        for after in [disabled, removed] {
            let result = DependencyInvalidation.affectedParticipants(edges: [edge(.ragEnabled, .knowledgeBase, .model)],
                changedKinds: [.ragPipeline], before: old, after: after)
            XCTAssertEqual(result.affectedKinds, [.ragPipeline, .knowledgeBase, .model])
            XCTAssertEqual(result.affectedSelectionIDs, ["rag_old", "kb_old", "model_disabled", "kb_new"])
            XCTAssertEqual(result.participatingEdges.first?.before, .active)
            XCTAssertEqual(result.participatingEdges.first?.after, .inactive)
        }
    }

    func testRemovingOneT5KindDoesNotDisableAnotherEnabledT5Kind() {
        let old = context(selections: [selection(.trainingFramework), selection(.trainingDataset), selection(.model)])
        let remaining = context(selections: [selection(.trainingDataset), selection(.model)])
        let result = DependencyInvalidation.affectedParticipants(edges: [edge(.fineTuningEnabled)],
            changedKinds: [.trainingFramework], before: old, after: remaining)
        XCTAssertTrue(result.participatingEdges.isEmpty)
        XCTAssertEqual(result.affectedSelectionIDs, ["selection_trainingFramework"])
        let disabled = context(selections: [selection(.trainingDataset, enabled: false), selection(.model)])
        let final = DependencyInvalidation.affectedParticipants(edges: [edge(.fineTuningEnabled)],
            changedKinds: [.trainingDataset], before: remaining, after: disabled)
        XCTAssertEqual(final.participatingEdges.map(\.edgeIndex), [0])
        XCTAssertTrue(final.affectedKinds.contains(.accelerator))
    }

    func testAgentActivationCanChangeWithoutEitherEndpointBeingEdited() {
        let old = context(selections: [selection(.agentFramework)])
        let after = context()
        let result = DependencyInvalidation.affectedParticipants(edges: [edge(.agentsEnabled, .tool, .model)],
            changedKinds: [], before: old, after: after)
        XCTAssertTrue(result.changedKinds.isEmpty)
        XCTAssertEqual(result.affectedKinds, [.tool, .model])
        XCTAssertEqual(result.participatingEdges.first?.before, .active)
        XCTAssertEqual(result.participatingEdges.first?.after, .inactive)
    }

    func testCyclesSelfEdgesAndDuplicateRowsRetainFiniteOrderedParticipation() {
        let edges = [edge(.always, .model, .contextPolicy), edge(.always, .contextPolicy, .accelerator),
                     edge(.always, .accelerator, .model), edge(.always, .model, .contextPolicy),
                     edge(.always, .model, .model)]
        let value = context(selections: [selection(.model), selection(.contextPolicy), selection(.accelerator)])
        let result = DependencyInvalidation.affectedParticipants(edges: edges, changedKinds: [.model], before: value, after: value)
        XCTAssertEqual(result.participatingEdges.map(\.edgeIndex), [0, 2, 3, 4])
        XCTAssertEqual(result.affectedKinds, [.model, .contextPolicy, .accelerator])
        XCTAssertEqual(result.affectedSelectionIDs, value.selections.map(\.id))
        let reverse = DependencyInvalidation.affectedParticipants(edges: Array(edges.reversed()),
            changedKinds: [.model], before: value, after: value)
        XCTAssertEqual(reverse.affectedKinds, result.affectedKinds)
        XCTAssertEqual(reverse.affectedSelectionIDs, result.affectedSelectionIDs)
        XCTAssertEqual(edges.count, 5)
    }

    func testNewlyAffectedKindsDoNotBecomeRecursiveSeeds() {
        let edges = [edge(.always, .model, .contextPolicy), edge(.always, .contextPolicy, .accelerator),
                     edge(.always, .accelerator, .unrelated)]
        let value = context()
        for ordered in [edges, Array(edges.reversed())] {
            let result = DependencyInvalidation.affectedParticipants(edges: ordered, changedKinds: [.model], before: value, after: value)
            XCTAssertEqual(result.affectedKinds, [.model, .contextPolicy])
            XCTAssertEqual(result.participatingEdges.count, 1)
        }
    }

    func testAffectedIDsUseStableOldThenNewOrderAndExactBytes() {
        let composed = "selection_\u{00e9}", decomposed = "selection_e\u{0301}"
        let old = context(selections: [selection(.model, "old"), selection(.model, composed), selection(.unrelated, "ignored")])
        let new = context(selections: [selection(.model, "new", enabled: false), selection(.model, "old"), selection(.model, decomposed)])
        let result = DependencyInvalidation.affectedParticipants(edges: [], changedKinds: [.model], before: old, after: new)
        XCTAssertEqual(result.affectedSelectionIDs.map { Array($0.utf8) }, ["old", composed, "new", decomposed].map { Array($0.utf8) })
        XCTAssertNotEqual(selection(.model, composed), selection(.model, decomposed))
        XCTAssertTrue(result.participatingEdges.isEmpty)
    }

    func testContextsAndResultsAreImmutableValueSnapshots() {
        var rows = [selection(.model, "original")]
        let before = context(selections: rows)
        rows[0] = selection(.unrelated, "replacement")
        let after = context(selections: rows)
        let result = DependencyInvalidation.affectedParticipants(edges: [], changedKinds: [.model, .tool], before: before, after: after)
        XCTAssertEqual(before.selections.map(\.id), ["original"])
        XCTAssertEqual(result.affectedSelectionIDs, ["original"])
        XCTAssertEqual(result.affectedKinds, [.model, .tool])
        var copy = result.affectedSelectionIDs
        copy.removeAll()
        XCTAssertEqual(result.affectedSelectionIDs, ["original"])
    }
}
