import Foundation
import XCTest
import PlannerCore
import PlannerData
@testable import PlannerTransfer

/// Synthetic frozen fixtures; these are transition and ownership tests, not
/// compatibility evaluations, catalog approvals or native interface receipts.
private enum TierFixtures {
    static let later = "2026-10-20T04:30:00Z"
    static let unknown = OptionalTierEnvironment(mode: nil, production: nil)
    static let resolved = OptionalTierEnvironment(mode: .selfHosted, production: true)

    static func encoded(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        var parser = try JSONParser(Data(contentsOf: url))
        return try parser.parse()
    }

    static func build(_ changes: [String: JSONValue] = [:]) throws -> BuildSnapshot {
        var object = try fixture("build").object!
        for (key, value) in changes { object[key] = value }
        return try BuildTransfer.snapshot(fromDraftJSON: encoded(.object(object)))
    }

    static func catalog(_ value: JSONValue? = nil) throws -> CatalogSnapshot {
        try CatalogSnapshot.decode(encoded(value ?? fixture("catalog")))
    }

    static func graph(_ value: JSONValue? = nil) throws -> DependencyGraph {
        try DependencyGraph.decode(encoded(value ?? fixture("dependency-graph")))
    }

    static func transition(
        build: BuildSnapshot? = nil, catalog: CatalogSnapshot? = nil, graph: DependencyGraph? = nil,
        tiers: Set<OptionalBuildTier> = Set(OptionalBuildTier.allCases), enabled: Bool = false,
        environment: OptionalTierEnvironment = resolved, updatedAt: String = later
    ) throws -> OptionalTierTransition {
        try .prepare(build: build ?? self.build(), catalog: catalog ?? self.catalog(), graph: graph ?? self.graph(),
                     tiers: tiers, enabled: enabled, environment: environment, updatedAt: updatedAt)
    }

    static func replacing(_ build: BuildSnapshot, selectionID: String, field: String, value: JSONValue) throws -> BuildSnapshot {
        var object = build.value.object!, rows = object["selections"]!.array!
        let index = try XCTUnwrap(rows.firstIndex { $0.object!["id"] == .string(selectionID) })
        var row = rows[index].object!; row[field] = value; rows[index] = .object(row)
        object["selections"] = .array(rows)
        return try BuildTransfer.snapshot(fromDraftJSON: encoded(.object(object)))
    }

    static func owner(draftID: UUID = UUID(), revision: Int = 1) throws -> OptionalTierTransitionOwner {
        try .init(storeID: UUID(), draftID: draftID, draftRevision: revision, selectionSessionID: UUID())
    }

    static func confirm(_ review: OptionalTierTransitionReview, on session: OptionalTierTransitionSession,
                        owner: OptionalTierTransitionOwner? = nil, build: BuildSnapshot? = nil,
                        catalog: CatalogSnapshot? = nil, graph: DependencyGraph? = nil,
                        environment: OptionalTierEnvironment? = nil, transition: OptionalTierTransition? = nil)
        async throws -> BuildSnapshot {
        let t = review.transition
        return try await session.confirm(review, currentOwner: owner ?? review.owner, currentBuild: build ?? t.original,
            currentCatalog: catalog ?? t.catalog, currentGraph: graph ?? t.graph,
            currentEnvironment: environment ?? t.environment, currentTransition: transition ?? t)
    }
}

final class OptionalTierTransitionTests: XCTestCase {
    func testDisablingAllOptionalTiersChangesOnlyEnabledAndDraftMetadata() throws {
        var original = try TierFixtures.build(["lifecycle": .string("ready"),
            "name": .string("Private e\u{301} build"),
            "extensions": .object(["x_private": .string("retained local metadata")])])
        original = try TierFixtures.replacing(original, selectionID: "sel_rag_pipeline", field: "notes",
                                             value: .string("Keep this user's chosen chunk settings"))
        let transition = try TierFixtures.transition(build: original)
        XCTAssertEqual(transition.changes.count, 14)
        XCTAssertEqual(transition.changes.filter { $0.tier == .t3 }.count, 5)
        XCTAssertEqual(transition.changes.filter { $0.tier == .t4 }.count, 5)
        XCTAssertEqual(transition.changes.filter { $0.tier == .t5 }.count, 4)
        XCTAssertTrue(transition.changes.allSatisfy { $0.beforeEnabled && !$0.afterEnabled })
        var restored = transition.proposed.value.object!
        let before = original.value.object!, oldRows = before["selections"]!.array!
        var rows = restored["selections"]!.array!
        let changedIDs = Set(transition.changes.map(\.selectionID))
        XCTAssertEqual(rows.count, oldRows.count)
        for index in rows.indices {
            var row = rows[index].object!
            if changedIDs.contains(row["id"]!.string!) {
                XCTAssertEqual(row["enabled"], .bool(false))
                row["enabled"] = oldRows[index].object!["enabled"]!
                rows[index] = .object(row)
            }
            XCTAssertEqual(rows[index], oldRows[index])
        }
        restored["selections"] = .array(rows)
        XCTAssertEqual(restored["revision"], .number(2))
        XCTAssertEqual(restored["updated_at"], .string(TierFixtures.later))
        XCTAssertEqual(restored["lifecycle"], .string("draft"))
        for key in ["revision", "updated_at", "lifecycle"] { restored[key] = before[key] }
        XCTAssertEqual(.object(restored), original.value)
        XCTAssertEqual(transition.original, original)
        XCTAssertEqual(transition.proposed.locks, original.locks)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: transition.proposed.encoded()), transition.proposed)
    }

    func testReenablingAnAllDisabledFixtureRestoresTheOriginalAllEnabledBytes() throws {
        let disabled = try TierFixtures.transition()
        let enabled = try TierFixtures.transition(build: disabled.proposed, enabled: true)
        XCTAssertEqual(enabled.changes.count, 14)
        XCTAssertTrue(enabled.changes.allSatisfy { !$0.beforeEnabled && $0.afterEnabled })
        var restored = enabled.proposed.value.object!
        for key in ["revision", "updated_at", "lifecycle"] { restored[key] = disabled.original.value.object![key] }
        XCTAssertEqual(.object(restored), disabled.original.value)
        XCTAssertEqual(enabled.proposed.value.object!["revision"], .number(3))
    }

    /// Pins the actual (lossy) semantics: the Build stores only a current
    /// `enabled` flag, so a re-enable cannot tell an individually disabled row
    /// from one disabled by an earlier tier disable. It enables every disabled
    /// retained row in the requested tiers and previews each one.
    func testReenableWidensIndividuallyDisabledRowsAndPreviewsEachOne() throws {
        let individuallyDisabled = ["sel_tool", "sel_memory_store"]
        var mixed = try TierFixtures.build()
        for id in individuallyDisabled {
            mixed = try TierFixtures.replacing(mixed, selectionID: id, field: "enabled", value: .bool(false))
        }
        // Disable then re-enable the whole tier: the prior individual state is not restored.
        let off = try TierFixtures.transition(build: mixed, tiers: [.t4])
        XCTAssertEqual(Set(off.changes.map(\.selectionID)), ["sel_agent_framework", "sel_mcp_server", "sel_integration"])
        let on = try TierFixtures.transition(build: off.proposed, tiers: [.t4], enabled: true)
        XCTAssertEqual(Set(on.changes.map(\.selectionID)),
                       Set(["sel_agent_framework", "sel_mcp_server", "sel_integration"] + individuallyDisabled))
        XCTAssertTrue(on.changes.allSatisfy { !$0.beforeEnabled && $0.afterEnabled })
        for row in on.proposed.value.object!["selections"]!.array! {
            let fields = row.object!
            if individuallyDisabled.contains(fields["id"]!.string!) { XCTAssertEqual(fields["enabled"], .bool(true)) }
        }
        XCTAssertNotEqual(on.proposed.value, mixed.value)
        // Enabling directly from the mixed state also lists exactly the disabled rows.
        let direct = try TierFixtures.transition(build: mixed, tiers: [.t4], enabled: true)
        XCTAssertEqual(direct.changes.map(\.selectionID), individuallyDisabled)
    }

    func testDeployedAndArchivedBuildsAreRefusedAndNeverResurrectedAsDrafts() throws {
        for lifecycle in ["deployed", "archived"] {
            let build = try TierFixtures.build(["lifecycle": .string(lifecycle)])
            for enabled in [false, true] {
                XCTAssertThrowsError(try TierFixtures.transition(build: build, enabled: enabled)) {
                    XCTAssertEqual($0 as? OptionalTierTransitionError, .lifecycleNotEditable)
                }
            }
            XCTAssertEqual(build.value.object!["lifecycle"], .string(lifecycle))
            XCTAssertEqual(build.value.object!["revision"], .number(1))
        }
    }

    func testEditableLifecyclesAreDemotedToDraftAndTheDemotionIsPreviewed() throws {
        for (lifecycle, changes) in [("draft", false), ("validated", true), ("ready", true)] {
            let t = try TierFixtures.transition(build: TierFixtures.build(["lifecycle": .string(lifecycle)]))
            XCTAssertEqual(t.lifecycleBefore, lifecycle)
            XCTAssertEqual(t.lifecycleAfter, "draft")
            XCTAssertEqual(t.lifecycleChanges, changes)
            XCTAssertEqual(t.proposed.value.object!["lifecycle"], .string("draft"))
        }
    }

    func testSingleTierRequestsPreserveOtherOptionalAndAllCoreRows() throws {
        for (tier, count) in [(OptionalBuildTier.t3, 5), (.t4, 5), (.t5, 4)] {
            let t = try TierFixtures.transition(tiers: [tier])
            XCTAssertEqual(t.changes.count, count)
            XCTAssertTrue(t.changes.allSatisfy { $0.tier == tier })
            let changedIDs = Set(t.changes.map(\.selectionID))
            for (before, after) in zip(t.original.value.object!["selections"]!.array!, t.proposed.value.object!["selections"]!.array!) {
                if !changedIDs.contains(before.object!["id"]!.string!) { XCTAssertEqual(after, before) }
            }
        }
    }

    func testMixedActivationChangesOnlyTheExplicitlyRequestedState() throws {
        var mixed = try TierFixtures.build()
        for id in ["sel_tool", "sel_memory_store"] {
            mixed = try TierFixtures.replacing(mixed, selectionID: id, field: "enabled", value: .bool(false))
        }
        let disable = try TierFixtures.transition(build: mixed, tiers: [.t4])
        XCTAssertEqual(disable.changes.map(\.selectionID), ["sel_agent_framework", "sel_mcp_server", "sel_integration"])
        let enable = try TierFixtures.transition(build: mixed, tiers: [.t4], enabled: true)
        XCTAssertEqual(enable.changes.map(\.selectionID), ["sel_tool", "sel_memory_store"])
        XCTAssertEqual(disable.original, enable.original)
        XCTAssertTrue(enable.changes.allSatisfy { !$0.beforeEnabled && $0.afterEnabled })
    }

    func testMultipleSelectionsOfOneKindRemainIndividuallyVisible() throws {
        let initial = try TierFixtures.build(); var rows = initial.value.object!["selections"]!.array!
        var extra = try XCTUnwrap(rows.first { $0.object!["kind"] == .string("rag_pipeline") }).object!
        extra["id"] = .string("sel_rag_secondary"); extra["notes"] = .string("Separate retained choice")
        rows.append(.object(extra))
        let t = try TierFixtures.transition(build: TierFixtures.build(["selections": .array(rows)]), tiers: [.t3])
        XCTAssertEqual(t.changes.count, 6)
        XCTAssertEqual(t.changes.last?.selectionID, "sel_rag_secondary")
        XCTAssertEqual(t.proposed.value.object!["selections"]!.array!.last?.object?["notes"], extra["notes"])
        XCTAssertTrue(t.dependencyPreview.participants.affectedSelectionIDs.contains("sel_rag_secondary"))
    }

    func testAbsentOptionalTiersDoNotCreateSelectionsOrRequirements() throws {
        let initial = try TierFixtures.build()
        let core = initial.value.object!["selections"]!.array!.filter {
            !["data_source", "knowledge_base", "embedding_model", "vector_database", "rag_pipeline",
              "agent_framework", "tool", "mcp_server", "memory_store", "integration",
              "training_framework", "training_compute", "training_dataset", "fine_tuned_model"].contains($0.object!["kind"]!.string!)
        }
        let ids = Set(core.map { $0.object!["id"]!.string! })
        let links = initial.value.object!["links"]!.array!.filter {
            ids.contains($0.object!["from_selection_id"]!.string!) && ids.contains($0.object!["to_selection_id"]!.string!)
        }
        let omitted = try TierFixtures.build(["selections": .array(core), "links": .array(links)])
        for requestedState in [false, true] {
            XCTAssertThrowsError(try TierFixtures.transition(build: omitted, enabled: requestedState)) {
                XCTAssertEqual($0 as? OptionalTierTransitionError, .unchangedSelectionState)
            }
        }
        XCTAssertEqual(omitted.value.object!["selections"], .array(core))
        XCTAssertEqual(core.count, 15)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: omitted.encoded()), omitted)
    }

    func testDisabledBranchesPreviewInactiveWithoutRemovingCoreParticipants() throws {
        let t = try TierFixtures.transition()
        let preview = t.dependencyPreview.participants
        let optionalActivations: [DependencyActivation] = [.ragEnabled, .agentsEnabled, .fineTuningEnabled]
        let indices = t.graph.edges.indices.filter { optionalActivations.contains(t.graph.edges[$0].activation) }
        XCTAssertFalse(indices.isEmpty)
        for index in indices {
            let entry = try XCTUnwrap(preview.participatingEdges.first { $0.edgeIndex == index })
            XCTAssertEqual(entry.before, .active); XCTAssertEqual(entry.after, .inactive)
        }
        XCTAssertEqual(preview.participatingEdges.map(\.edgeIndex), preview.participatingEdges.map(\.edgeIndex).sorted())
        XCTAssertTrue(preview.affectedSelectionIDs.contains("sel_model"))
        XCTAssertTrue(preview.affectedSelectionIDs.contains("sel_evaluation_suite"))
        for id in ["sel_model", "sel_guardrail", "sel_evaluation_suite", "sel_deployment_target", "sel_cost_policy"] {
            let before = t.original.value.object!["selections"]!.array!.first { $0.object!["id"] == .string(id) }
            let after = t.proposed.value.object!["selections"]!.array!.first { $0.object!["id"] == .string(id) }
            XCTAssertEqual(after, before)
        }
        XCTAssertEqual(t.graph.value, try TierFixtures.fixture("dependency-graph"))
    }

    func testUnknownDecisionsStayUnknownAndAlwaysEdgesStayActive() throws {
        var graph = try TierFixtures.fixture("dependency-graph").object!
        func edge(_ id: String, _ dependent: String, _ dependency: String, _ activation: String) -> JSONValue {
            .object(["id": .string(id), "dependent_kind": .string(dependent), "depends_on_kind": .string(dependency),
                     "relationship": .string("requires"), "activation": .string(activation), "rationale": .string("Synthetic boundary")])
        }
        graph["edges"] = .array([
            edge("dep.unknown.host", "rag_pipeline", "model", "self_hosted"),
            edge("dep.unknown.production", "agent_framework", "model", "production_only"),
            edge("dep.unknown.mode", "training_framework", "model", "non_api"),
            edge("dep.always", "guardrail", "rag_pipeline", "always"),
            edge("dep.unrelated", "monitoring_stack", "deployment_target", "production_only")])
        let t = try TierFixtures.transition(graph: TierFixtures.graph(.object(graph)), environment: TierFixtures.unknown)
        let entries = t.dependencyPreview.participants.participatingEdges
        XCTAssertEqual(entries.map(\.edgeIndex), [0, 1, 2, 3])
        for entry in entries.prefix(3) { XCTAssertEqual(entry.before, .unknown); XCTAssertEqual(entry.after, .unknown) }
        XCTAssertEqual(entries[3].before, .active); XCTAssertEqual(entries[3].after, .active)
        XCTAssertNil(t.environment.mode); XCTAssertNil(t.environment.production)
    }

    func testReenablingReactivatesTheGovernedOptionalGraphBranches() throws {
        let off = try TierFixtures.transition()
        let on = try TierFixtures.transition(build: off.proposed, enabled: true)
        for entry in on.dependencyPreview.participants.participatingEdges {
            let activation = on.graph.edges[entry.edgeIndex].activation
            if [.ragEnabled, .agentsEnabled, .fineTuningEnabled].contains(activation) {
                XCTAssertEqual(entry.before, .inactive); XCTAssertEqual(entry.after, .active)
            }
        }
        XCTAssertEqual(on.dependencyPreview.participants.changedKinds, off.dependencyPreview.participants.changedKinds)
    }

    func testCatalogAndBothGraphLockFieldsAreRequired() throws {
        let initial = try TierFixtures.build()
        for (field, value, expected) in [
            ("catalog_snapshot_id", JSONValue.string("catalog.other"), OptionalTierTransitionError.catalogMismatch),
            ("dependency_graph_id", .string("dependencies.other"), .graphMismatch),
            ("dependency_graph_revision", .number(2), .graphMismatch)] {
            var locks = initial.locks.object!; locks[field] = value
            XCTAssertThrowsError(try TierFixtures.transition(build: TierFixtures.build(["locks": .object(locks)]))) {
                XCTAssertEqual($0 as? OptionalTierTransitionError, expected)
            }
        }
    }

    func testDuplicateCatalogAndSelectionIdentitiesAreRejected() throws {
        var release = try TierFixtures.fixture("catalog").object!, items = release["items"]!.array!
        items.append(items[0]); release["items"] = .array(items)
        XCTAssertThrowsError(try TierFixtures.transition(catalog: TierFixtures.catalog(.object(release)))) {
            XCTAssertEqual($0 as? OptionalTierTransitionError, .ambiguousCatalogIdentity)
        }
        var rows = try TierFixtures.build().value.object!["selections"]!.array!; rows.append(rows[0])
        XCTAssertThrowsError(try TierFixtures.transition(build: TierFixtures.build(["selections": .array(rows)]))) {
            XCTAssertEqual($0 as? OptionalTierTransitionError, .ambiguousSelectionIdentity)
        }
    }

    func testMissingOrCrossKindBindingRejectsEvenForProtectedCoreRows() throws {
        let initial = try TierFixtures.build()
        for (id, expected) in [("cat.absent.fixture", OptionalTierTransitionError.missingCatalogItem),
                               ("cat.accelerator.fixture", .differentKind)] {
            let changed = try TierFixtures.replacing(initial, selectionID: "sel_model", field: "catalog_item_id", value: .string(id))
            XCTAssertThrowsError(try TierFixtures.transition(build: changed)) { XCTAssertEqual($0 as? OptionalTierTransitionError, expected) }
            XCTAssertEqual(changed.value.object!["revision"], .number(1))
        }
    }

    func testVersionPinsAreExactUTF8AndDistinctCanonicalSpellingsStayDistinct() throws {
        var release = try TierFixtures.fixture("catalog").object!, items = release["items"]!.array!
        let index = try XCTUnwrap(items.firstIndex { $0.object!["kind"] == .string("rag_pipeline") })
        var old = items[index].object!; old["version"] = .string("fixture-e\u{301}"); items[index] = .object(old)
        var other = old; other["version"] = .string("fixture-\u{e9}"); items.append(.object(other))
        release["items"] = .array(items)
        let catalog = try TierFixtures.catalog(.object(release))
        let selected = try TierFixtures.replacing(TierFixtures.build(), selectionID: "sel_rag_pipeline", field: "catalog_item_version", value: old["version"]!)
        let t = try TierFixtures.transition(build: selected, catalog: catalog, tiers: [.t3])
        let change = try XCTUnwrap(t.changes.first { $0.selectionID == "sel_rag_pipeline" })
        XCTAssertTrue(change.item.version.utf8.elementsEqual("fixture-e\u{301}".utf8))
        items.removeLast(); release["items"] = .array(items)
        let mismatched = try TierFixtures.replacing(selected, selectionID: "sel_rag_pipeline", field: "catalog_item_version", value: other["version"]!)
        XCTAssertThrowsError(try TierFixtures.transition(build: mismatched, catalog: TierFixtures.catalog(.object(release)))) {
            XCTAssertEqual($0 as? OptionalTierTransitionError, .missingCatalogItem)
        }
    }

    func testFrozenCatalogRejectsRelabelingCoreComponentsAsOptional() throws {
        var release = try TierFixtures.fixture("catalog").object!, items = release["items"]!.array!
        let index = try XCTUnwrap(items.firstIndex { $0.object!["kind"] == .string("guardrail") })
        var item = items[index].object!; item["tier"] = .string("T3"); items[index] = .object(item)
        release["items"] = .array(items)
        XCTAssertThrowsError(try TierFixtures.catalog(.object(release))) { XCTAssertEqual($0 as? TransferError, .schemaViolation) }
    }

    func testNoOpAndEmptyRequestsDoNotCreateNewRevisions() throws {
        XCTAssertThrowsError(try TierFixtures.transition(tiers: [])) { XCTAssertEqual($0 as? OptionalTierTransitionError, .emptyTierRequest) }
        XCTAssertThrowsError(try TierFixtures.transition(enabled: true)) { XCTAssertEqual($0 as? OptionalTierTransitionError, .unchangedSelectionState) }
        let disabled = try TierFixtures.transition()
        XCTAssertThrowsError(try TierFixtures.transition(build: disabled.proposed)) { XCTAssertEqual($0 as? OptionalTierTransitionError, .unchangedSelectionState) }
        XCTAssertEqual(disabled.original.value.object!["revision"], .number(1))
        XCTAssertEqual(disabled.proposed.value.object!["revision"], .number(2))
    }

    func testTimestampAndExactNumericReopeningBoundsRemainEnforced() throws {
        XCTAssertThrowsError(try TierFixtures.transition(updatedAt: "not-a-timestamp")) { XCTAssertEqual($0 as? TransferError, .schemaViolation) }
        let boundary = try TierFixtures.build(["revision": .number(Decimal(999_999_999_999_999))])
        XCTAssertEqual(try TierFixtures.transition(build: boundary).proposed.value.object!["revision"], .number(Decimal(1_000_000_000_000_000)))
        let tooPreciseAfterIncrement = try TierFixtures.build(["revision": .number(Decimal(9_007_199_254_740_990))])
        XCTAssertThrowsError(try TierFixtures.transition(build: tooPreciseAfterIncrement)) { XCTAssertEqual($0 as? TransferError, .unsupportedNumber) }
    }
}

final class OptionalTierTransitionSessionTests: XCTestCase, @unchecked Sendable {
    func testConfirmationIsExplicitSingleUseAndForeignSessionsCannotConsumeIt() async throws {
        let t = try TierFixtures.transition(), session = OptionalTierTransitionSession(), foreign = OptionalTierTransitionSession()
        let review = try await session.present(t, owner: TierFixtures.owner())
        do { _ = try await TierFixtures.confirm(review, on: foreign); XCTFail("foreign session") }
        catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
        let result = try await TierFixtures.confirm(review, on: session)
        XCTAssertEqual(result, t.proposed)
        do { _ = try await TierFixtures.confirm(review, on: session); XCTFail("replayed confirmation") }
        catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
    }

    func testPreparationExposesNoSaveableBuildWithoutTheConfirmingSession() async throws {
        let t = try TierFixtures.transition(enabled: false)
        // Previews stay inspectable through the read-only summary.
        XCTAssertEqual(t.changes.count, 14)
        XCTAssertEqual(t.original.value.object!["revision"], .number(1))
        XCTAssertFalse(t.dependencyPreview.participants.affectedSelectionIDs.isEmpty)
        // Package-internal access is intentionally visible to @testable tests, so
        // compile-level privacy is not asserted. Behaviorally: neither a session
        // that never presented it, a dismissed review, nor a replay yields the build.
        let session = OptionalTierTransitionSession(), stranger = OptionalTierTransitionSession()
        let review = try await session.present(t, owner: TierFixtures.owner())
        do { _ = try await TierFixtures.confirm(review, on: stranger); XCTFail("unpresented session") }
        catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
        await session.invalidate()
        do { _ = try await TierFixtures.confirm(review, on: session); XCTFail("dismissed review") }
        catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
        let again = try await session.present(t, owner: TierFixtures.owner())
        let confirmed = try await TierFixtures.confirm(again, on: session)
        XCTAssertEqual(confirmed, t.proposed)
        XCTAssertNotEqual(confirmed, t.original)
    }

    func testDismissalAndSameContentReopeningDoNotReviveOldCallbacks() async throws {
        let t = try TierFixtures.transition(), owner = try TierFixtures.owner(), session = OptionalTierTransitionSession()
        let first = await session.present(t, owner: owner); await session.invalidate()
        do { _ = try await TierFixtures.confirm(first, on: session); XCTFail("dismissed confirmation") }
        catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
        let second = await session.present(t, owner: owner)
        do { _ = try await TierFixtures.confirm(first, on: session); XCTFail("old callback") }
        catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
        let result = try await TierFixtures.confirm(second, on: session)
        XCTAssertEqual(result, t.proposed)
    }

    func testSupersedingPresentationRejectsOldProposalWithoutRetiringNewOne() async throws {
        let first = try TierFixtures.transition(tiers: [.t3]), second = try TierFixtures.transition(tiers: [.t4])
        let owner = try TierFixtures.owner(), session = OptionalTierTransitionSession()
        let old = await session.present(first, owner: owner), current = await session.present(second, owner: owner)
        do { _ = try await TierFixtures.confirm(old, on: session); XCTFail("superseded proposal") }
        catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
        let result = try await TierFixtures.confirm(current, on: session)
        XCTAssertEqual(result, second.proposed)
    }

    func testActualStoreDraftRevisionAndSelectionSessionMustStillMatch() async throws {
        let t = try TierFixtures.transition(), owner = try TierFixtures.owner()
        let variants = try [
            OptionalTierTransitionOwner(storeID: UUID(), draftID: owner.draftID, draftRevision: 1, selectionSessionID: owner.selectionSessionID),
            OptionalTierTransitionOwner(storeID: owner.storeID, draftID: UUID(), draftRevision: 1, selectionSessionID: owner.selectionSessionID),
            OptionalTierTransitionOwner(storeID: owner.storeID, draftID: owner.draftID, draftRevision: 2, selectionSessionID: owner.selectionSessionID),
            OptionalTierTransitionOwner(storeID: owner.storeID, draftID: owner.draftID, draftRevision: 1, selectionSessionID: UUID())]
        for variant in variants {
            let session = OptionalTierTransitionSession(), review = await session.present(t, owner: owner)
            do { _ = try await TierFixtures.confirm(review, on: session, owner: variant); XCTFail("foreign current owner") }
            catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
            do { _ = try await TierFixtures.confirm(review, on: session); XCTFail("failed owner check revived") }
            catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
        }
        for invalid in [0, -1] {
            XCTAssertThrowsError(try TierFixtures.owner(revision: invalid)) { XCTAssertEqual($0 as? OptionalTierTransitionError, .invalidLocalOwner) }
        }
    }

    func testSamePinsWithChangedBuildCatalogOrGraphContentRevokeConfirmation() async throws {
        let t = try TierFixtures.transition()
        let changedBuild = try TierFixtures.build(["name": .string("A newer user edit")])
        var catalog = t.catalog.value.object!, items = catalog["items"]!.array!
        var item = items[0].object!; item["name"] = .string("Different same-pin source"); items[0] = .object(item); catalog["items"] = .array(items)
        var graph = t.graph.value.object!, edges = graph["edges"]!.array!
        var edge = edges[0].object!; edge["rationale"] = .string("Different same-pin graph"); edges[0] = .object(edge); graph["edges"] = .array(edges)
        let cases = [(changedBuild, t.catalog, t.graph), (t.original, try TierFixtures.catalog(.object(catalog)), t.graph),
                     (t.original, t.catalog, try TierFixtures.graph(.object(graph)))]
        for (build, catalog, graph) in cases {
            let session = OptionalTierTransitionSession(), review = try await session.present(t, owner: TierFixtures.owner())
            do { _ = try await TierFixtures.confirm(review, on: session, build: build, catalog: catalog, graph: graph); XCTFail("changed exact inputs") }
            catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
            do { _ = try await TierFixtures.confirm(review, on: session); XCTFail("failed freshness revived") }
            catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
        }
    }

    func testResolvedEnvironmentAndNewSameContentPreparationRetireConfirmation() async throws {
        let t = try TierFixtures.transition()
        for environment in [TierFixtures.unknown, OptionalTierEnvironment(mode: .api, production: true),
                            OptionalTierEnvironment(mode: .selfHosted, production: false)] {
            let session = OptionalTierTransitionSession(), review = try await session.present(t, owner: TierFixtures.owner())
            do { _ = try await TierFixtures.confirm(review, on: session, environment: environment); XCTFail("changed environment") }
            catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
        }
        let session = OptionalTierTransitionSession(), review = try await session.present(t, owner: TierFixtures.owner())
        let newlyPrepared = try TierFixtures.transition()
        XCTAssertEqual(newlyPrepared.proposed, t.proposed)
        do { _ = try await TierFixtures.confirm(review, on: session, transition: newlyPrepared); XCTFail("new preparation generation") }
        catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
    }

    func testPreviewDismissalAndConfirmationDoNotWriteBeforeExplicitDurableCAS() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("draft.sqlite"), id = UUID(), t = try TierFixtures.transition()
        let original = try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "Retained choices", payload: t.original.encoded())
        let owner = try TierFixtures.owner(draftID: id, revision: original.revision), session = OptionalTierTransitionSession()
        _ = await session.present(t, owner: owner)
        let previewState = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(previewState, original)
        await session.invalidate()
        let dismissedState = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(dismissedState, original)
        let review = await session.present(t, owner: owner)
        let proposed = try await TierFixtures.confirm(review, on: session)
        let confirmedState = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(confirmedState, original)
        let saved = try await DraftStore(url: url).save(id: id, expectedRevision: original.revision, title: original.title, payload: proposed.encoded())
        let reopened = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(reopened, saved); XCTAssertFalse(reopened.analysisIsCurrent)
        XCTAssertEqual(try BuildTransfer.snapshot(fromDraftJSON: reopened.payload), proposed)
        let history = try await DraftStore(url: url).history(id: id)
        XCTAssertEqual(history.records.count, 2)
        XCTAssertTrue(history.records.contains { $0.payload == original.payload })
    }

    func testConcurrentSaveAfterConfirmationWinsWithoutAutomaticRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("draft.sqlite"), id = UUID(), t = try TierFixtures.transition()
        let original = try await DraftStore(url: url).save(id: id, expectedRevision: nil, title: "Original", payload: t.original.encoded())
        let session = OptionalTierTransitionSession(), review = try await session.present(t, owner: TierFixtures.owner(draftID: id, revision: original.revision))
        let proposed = try await TierFixtures.confirm(review, on: session)
        let concurrent = try await DraftStore(url: url).save(id: id, expectedRevision: original.revision, title: "New owner edit", payload: original.payload)
        do { _ = try await DraftStore(url: url).save(id: id, expectedRevision: original.revision, title: original.title, payload: proposed.encoded()); XCTFail("stale durable write") }
        catch { XCTAssertEqual(error as? DraftStoreError, .conflict) }
        let actual = try await DraftStore(url: url).read(id: id)
        XCTAssertEqual(actual, concurrent)
        do { _ = try await TierFixtures.confirm(review, on: session); XCTFail("retry consumed confirmation") }
        catch { XCTAssertEqual(error as? OptionalTierTransitionError, .staleConfirmation) }
        let history = try await DraftStore(url: url).history(id: id)
        XCTAssertEqual(history.records.count, 2)
    }
}
