import Foundation
import XCTest
@testable import PlannerTransfer

final class CapacityBindingDeploymentTests: XCTestCase {
    private func draft() throws -> CapacityTestDraft {
        let value = try CapacityTestDraft()
        try value.serving()
        return value
    }

    private func binding(_ draft: CapacityTestDraft, role: CapacityRole = .engine) throws -> CapacityBinding {
        let context = try draft.freeze()
        let graph = try context.graph()
        let requirements = try XCTUnwrap(context.requirements().first)
        let required = role == .engine ? requirements.engine : role == .host ? requirements.host : requirements.devices
        return try graph.resolve(current: context.basis, qualifications: context.qualifications(),
                                 fromSelectionID: requirements.selectionID, role: role, required: required)
    }

    private func deployment(_ draft: CapacityTestDraft,
                            omitting: (CapacityQualification) -> Bool = { _ in false }) throws -> CapacityDeploymentResult {
        let context = try draft.freeze()
        let value = try context.deployment()
        return try value.evaluate(current: context.basis, qualifications: context.qualifications(omitting: omitting))
    }

    private func editFineTunedCatalog(_ draft: CapacityTestDraft, _ edit: (inout [String: Any]) -> Void) throws {
        var items = try XCTUnwrap(draft.catalog["items"] as? [[String: Any]])
        let index = try XCTUnwrap(items.firstIndex { ($0["kind"] as? String) == "fine_tuned_model" })
        var spec = try XCTUnwrap(items[index]["spec"] as? [String: Any])
        edit(&spec); items[index]["spec"] = spec; draft.catalog["items"] = items
    }

    func testUniqueQualifiedRolesResolveTheActualRetainedGraph() throws {
        let fixture = try draft()
        XCTAssertEqual(try binding(fixture).resolved.map(\.id), ["sel_engine"])
        XCTAssertEqual(try binding(fixture, role: .host).resolved.map(\.id), ["sel_host"])
        XCTAssertEqual(try binding(fixture, role: .device).resolved.map(\.id), ["sel_gpu"])
    }

    func testTwoEngineCandidatesStayAmbiguousWhenGraphOrderChanges() throws {
        let fixture = try draft()
        try fixture.selection("second_engine", kind: "inference_engine")
        try fixture.link("second.engine", from: "sel_model", to: "second_engine", role: .engine)
        let first = try binding(fixture)
        XCTAssertEqual(first.check.outcome, .unknown)
        XCTAssertEqual(first.check.reason, .ambiguousBinding)
        XCTAssertTrue(first.resolved.isEmpty)
        var links = try XCTUnwrap(fixture.build["links"] as? [[String: Any]])
        links.reverse(); fixture.build["links"] = links
        let reversed = try binding(fixture)
        XCTAssertEqual(reversed.check.outcome, .unknown)
        XCTAssertEqual(Set(reversed.candidates.map(\.id)), Set(first.candidates.map(\.id)))
        XCTAssertTrue(reversed.resolved.isEmpty)
    }

    func testQualifiedAbsentRequiredAndOptionalRolesRemainFailAndSkipped() throws {
        let fixture = try CapacityTestDraft()
        try fixture.serving(engine: nil)
        XCTAssertEqual(try binding(fixture).check.outcome, .skipped)
        fixture.put("/requires/sel_model/engine", true)
        let value = try binding(fixture)
        XCTAssertEqual(value.check.outcome, .fail)
        XCTAssertEqual(value.check.reason, .requiredBindingAbsent)
    }

    func testUnknownRequirementAndIncompleteRoleCoverageNeverSelectAnEngine() throws {
        for path in ["/requires/sel_model/engine", "/graph/complete", "/links/link.sel_model.engine/role"] {
            let fixture = try draft()
            fixture.state(path, .unknown)
            let result = try binding(fixture)
            XCTAssertEqual(result.check.outcome, .unknown, path)
            XCTAssertTrue(result.resolved.isEmpty, path)
        }
    }

    func testWrongKindAndDisabledTargetsRetainKnownRequiredFailures() throws {
        let disabled = try draft()
        try disabled.editSelection("sel_engine") { $0["enabled"] = false }
        XCTAssertEqual(try binding(disabled).check.outcome, .fail)
        let wrong = try draft()
        var links = try XCTUnwrap(wrong.build["links"] as? [[String: Any]])
        let index = try XCTUnwrap(links.firstIndex { ($0["id"] as? String) == "link.sel_model.engine" })
        links[index]["to_selection_id"] = "sel_host"; wrong.build["links"] = links
        let value = try binding(wrong)
        XCTAssertEqual(value.check.outcome, .fail)
        XCTAssertEqual(value.check.reason, .wrongKindOrDisabled)
    }

    func testOptionalInvalidTargetIsUnknownRatherThanAnUnqualifiedSkip() throws {
        let fixture = try draft()
        fixture.put("/requires/sel_model/engine", false)
        try fixture.editSelection("sel_engine") { $0["enabled"] = false }
        let value = try binding(fixture)
        XCTAssertEqual(value.check.outcome, .unknown)
        XCTAssertEqual(value.check.reason, .wrongKindOrDisabled)
    }

    func testExactCatalogVersionIsRequiredWithoutAnIDOnlyFallback() throws {
        let fixture = try draft()
        try fixture.editSelection("sel_engine") { $0["catalog_item_version"] = "2026.11-unavailable" }
        let value = try binding(fixture)
        XCTAssertEqual(value.check.outcome, .unknown)
        XCTAssertEqual(value.check.reason, .missingCatalogVersion)
    }

    func testAQualifiedRoleForAnotherOperationDoesNotSupplyTheRequiredRole() throws {
        let fixture = try draft()
        fixture.put("/links/link.sel_model.engine/operation", "training")
        let value = try binding(fixture)
        XCTAssertEqual(value.check.outcome, .fail)
        XCTAssertEqual(value.check.reason, .requiredBindingAbsent)
    }

    func testRoleMetadataCannotInventAnAlternateGraphOrDuplicateAnEdge() throws {
        let fixture = try draft()
        let context = try fixture.freeze()
        let role = try context.answer("/links/link.sel_model.engine/role", .role)
        let operation = try context.answer("/links/link.sel_model.engine/operation", .text)
        let coverage = try context.coverage("/graph/complete", .roleBindings, scenario: context.basis.operation)
        let invented = try CapacityLinkMeaning(linkID: "absent.edge", role: role, operation: operation)
        XCTAssertThrowsError(try CapacityGraph(basis: context.basis, meanings: [invented], coverage: coverage)) {
            XCTAssertEqual($0 as? CapacityError, .danglingReference)
        }
        let actual = try CapacityLinkMeaning(linkID: "link.sel_model.engine", role: role, operation: operation)
        XCTAssertThrowsError(try CapacityGraph(basis: context.basis, meanings: [actual, actual], coverage: coverage)) {
            XCTAssertEqual($0 as? CapacityError, .duplicateIdentity)
        }
    }

    func testAdapterInheritsOnlyTheBoundExactBaseArtifactServingCapabilities() throws {
        let fixture = try CapacityTestDraft()
        try fixture.serving("sel_adapter", kind: "fine_tuned_model", engine: nil, host: nil, devices: [])
        try fixture.serving("sel_base")
        try fixture.link("adapter.base", from: "sel_adapter", to: "sel_base", role: .base)
        fixture.artifact("sel_adapter", kind: "adapter")
        fixture.required[0] = ("sel_adapter", "sel_base")
        for role in ["engine", "host", "devices"] { fixture.put("/requires/sel_adapter/" + role, true) }
        let context = try fixture.freeze()
        let graph = try context.graph(), facts = try context.artifacts()
        let required = try XCTUnwrap(context.requirements().first)
        let value = try graph.serving(current: context.basis, qualifications: context.qualifications(),
                                      requirements: required, artifactFacts: facts)
        XCTAssertEqual(value.lineage.artifacts.map(\.id), ["sel_adapter", "sel_base"])
        XCTAssertEqual(value.lineage.servingArtifact?.id, "sel_base")
        XCTAssertEqual(value.engine?.resolved.map(\.id), ["sel_engine"])
        XCTAssertEqual(value.outcome, .pass)
    }

    func testAdapterBaseVersionMismatchIsAnIndependentFailure() throws {
        let fixture = try CapacityTestDraft()
        try fixture.serving("sel_adapter", kind: "fine_tuned_model", engine: nil, host: nil, devices: [])
        try fixture.serving("sel_base")
        try fixture.link("adapter.base", from: "sel_adapter", to: "sel_base", role: .base)
        fixture.artifact("sel_adapter", kind: "adapter", baseVersion: "different.version")
        let context = try fixture.freeze(), graph = try context.graph(), facts = try context.artifacts()
        let value = try graph.lineage(current: context.basis, qualifications: context.qualifications(),
                                      selectionID: "sel_adapter", facts: facts)
        XCTAssertEqual(value.outcome, .fail)
        XCTAssertNil(value.servingArtifact)
        XCTAssertTrue(value.checks.contains { $0.reason == .baseArtifactMismatch })
    }

    func testAdapterCannotDeclareItsBaseRequirementFalse() throws {
        let fixture = try CapacityTestDraft()
        try fixture.serving("sel_adapter", kind: "fine_tuned_model")
        fixture.artifact("sel_adapter", kind: "adapter")
        fixture.put("/artifacts/sel_adapter/required", false)
        let context = try fixture.freeze()
        XCTAssertThrowsError(try context.artifacts()) { XCTAssertEqual($0 as? CapacityError, .contradictoryInput) }
    }

    func testFullMergedArtifactKeepsItsOwnServingGraph() throws {
        let fixture = try CapacityTestDraft()
        try fixture.serving("sel_full", kind: "fine_tuned_model")
        try editFineTunedCatalog(fixture) { $0["adapter_only"] = false }
        fixture.artifact("sel_full", kind: "full")
        let context = try fixture.freeze(), graph = try context.graph(), facts = try context.artifacts()
        let required = try XCTUnwrap(context.requirements().first)
        let value = try graph.serving(current: context.basis, qualifications: context.qualifications(),
                                      requirements: required, artifactFacts: facts)
        XCTAssertEqual(value.lineage.servingArtifact?.id, "sel_full")
        XCTAssertEqual(value.lineage.artifacts.map(\.id), ["sel_full"])
        XCTAssertEqual(value.engine?.resolved.map(\.id), ["sel_engine"])
        XCTAssertEqual(value.outcome, .pass)
    }

    func testCatalogAdapterContradictionCannotBeOverriddenByNormalizedFullLabel() throws {
        let fixture = try CapacityTestDraft()
        try fixture.serving("sel_full", kind: "fine_tuned_model")
        fixture.artifact("sel_full", kind: "full")
        let context = try fixture.freeze(), graph = try context.graph(), facts = try context.artifacts()
        let value = try graph.lineage(current: context.basis, qualifications: context.qualifications(),
                                      selectionID: "sel_full", facts: facts)
        XCTAssertEqual(value.outcome, .fail)
        XCTAssertNil(value.servingArtifact)
    }

    func testExactAdapterCycleIsUnknownAndDoesNotRecurseForever() throws {
        let fixture = try CapacityTestDraft()
        try fixture.selection("adapter_a", kind: "fine_tuned_model")
        try fixture.selection("adapter_b", kind: "fine_tuned_model")
        try editFineTunedCatalog(fixture) { $0["base_model_ref"] = "cat.fine_tuned_model.fixture" }
        try fixture.link("a.base", from: "adapter_a", to: "adapter_b", role: .base)
        try fixture.link("b.base", from: "adapter_b", to: "adapter_a", role: .base)
        fixture.artifact("adapter_a", kind: "adapter"); fixture.artifact("adapter_b", kind: "adapter")
        let context = try fixture.freeze(), graph = try context.graph(), facts = try context.artifacts()
        let value = try graph.lineage(current: context.basis, qualifications: context.qualifications(),
                                      selectionID: "adapter_a", facts: facts)
        XCTAssertEqual(value.outcome, .unknown)
        XCTAssertEqual(value.artifacts.map(\.id), ["adapter_a", "adapter_b"])
        XCTAssertTrue(value.checks.contains { $0.reason == .bindingCycle })
    }

    func testSelfProviderSharedAndManagedModesRemainPerComponent() throws {
        for (runtimeOperator, capacity, expected) in [
            ("self", "dedicated_instances", CapacityMode.selfHosted),
            ("provider", "shared", .api),
            ("provider", "reserved_throughput", .managed),
            ("provider", "dedicated_instances", .managed),
        ] {
            let fixture = try CapacityTestDraft()
            try fixture.serving(runtimeOperator: runtimeOperator, capacity: capacity, exposed: true)
            let value = try deployment(fixture)
            XCTAssertEqual(value.mode, expected)
            XCTAssertEqual(value.components.first?.localApplicability, .applicable)
            XCTAssertEqual(value.result.outcome, .pass)
        }
    }

    func testOpaqueProviderSkipsLocalHardwareButKeepsRemoteCapacityUnknown() throws {
        let fixture = try CapacityTestDraft()
        try fixture.serving(runtimeOperator: "provider", capacity: "shared", exposed: false)
        fixture.condition("sel_gpu", id: "local-support", kind: .localHardware, satisfied: false)
        let value = try deployment(fixture)
        XCTAssertEqual(value.mode, .api)
        XCTAssertEqual(value.components.first?.localApplicability, .inapplicable)
        XCTAssertEqual(value.result.outcome, .unknown)
        XCTAssertTrue(value.result.checks.contains { $0.rule == .localHardware && $0.outcome == .skipped })
        XCTAssertTrue(value.result.checks.contains { $0.rule == .remoteCapacity && $0.outcome == .unknown })
        XCTAssertFalse(value.result.checks.contains { $0.rule == .localHardware && $0.outcome == .fail })
    }

    func testProviderUnknownCapacityOrExposureNeverBecomesAConclusiveLocalSkip() throws {
        for path in ["/deployment/sel_model/capacity", "/deployment/sel_model/exposed"] {
            let fixture = try CapacityTestDraft()
            try fixture.serving(runtimeOperator: "provider", capacity: "shared", exposed: false)
            fixture.state(path, .unknown)
            let value = try deployment(fixture)
            XCTAssertEqual(value.components.first?.localApplicability, .unknown, path)
            XCTAssertEqual(value.result.outcome, .unknown, path)
        }
    }

    func testHybridBuildKeepsLocalDatabaseHardwareConditionsActive() throws {
        let fixture = try CapacityTestDraft()
        try fixture.serving("remote_model", runtimeOperator: "provider", capacity: "shared", exposed: false,
                            engine: nil, host: nil, devices: [])
        try fixture.serving("local_database", kind: "vector_database")
        fixture.condition("sel_gpu", id: "database-capability", kind: .localHardware, satisfied: false)
        let value = try deployment(fixture)
        XCTAssertEqual(value.mode, .hybrid)
        XCTAssertEqual(value.result.outcome, .fail)
        XCTAssertEqual(value.components.first { $0.selectionID == "local_database" }?.localApplicability, .applicable)
        XCTAssertTrue(value.result.checks.contains { $0.rule == .localHardware && $0.outcome == .fail })
    }

    func testProviderOpacityCannotEraseIndependentServiceOrArtifactFailures() throws {
        for kind in [CapacityConditionKind.serviceSupport, .artifactSupport] {
            let fixture = try CapacityTestDraft()
            try fixture.serving(runtimeOperator: "provider", capacity: "shared", exposed: false)
            fixture.condition("sel_model", id: "independent-support", kind: kind, satisfied: false)
            let value = try deployment(fixture)
            XCTAssertEqual(value.result.outcome, .fail)
            XCTAssertTrue(value.result.checks.contains { $0.rule == .remoteCapacity && $0.outcome == .unknown })
            XCTAssertTrue(value.result.checks.contains { $0.rule == .runtimeAccess && $0.outcome == .fail })
        }
    }

    func testIncompleteSupportInventoryBlocksAnOtherwiseQualifiedDeployment() throws {
        let fixture = try draft()
        fixture.state("/conditions/sel_engine/complete", .unknown)
        let value = try deployment(fixture)
        XCTAssertEqual(value.mode, .selfHosted)
        XCTAssertEqual(value.result.outcome, .unknown)
    }

    func testProvidedSupportInventoryMustMatchEveryConditionBeforeOpacitySkip() throws {
        let fixture = try CapacityTestDraft()
        try fixture.serving(runtimeOperator: "provider", capacity: "shared", exposed: false)
        fixture.condition("sel_model", id: "known", kind: .serviceSupport, satisfied: false)
        fixture.put("/conditions/sel_model/ids", [])
        XCTAssertThrowsError(try deployment(fixture)) { XCTAssertEqual($0 as? CapacityError, .contradictoryInput) }
    }

    func testUnqualifiedModeFactsRemainUnknownDespitePresetAttribution() throws {
        let value = try deployment(draft()) { $0.key.fact == .runtimeOperator }
        XCTAssertEqual(value.mode, .unknown)
        XCTAssertEqual(value.result.outcome, .unknown)
    }

    func testQualifiedEmptyServingMembershipSkipsWithoutInventingAComponent() throws {
        let fixture = try CapacityTestDraft()
        try fixture.selection("host", kind: "hosting_platform")
        try fixture.selection("engine", kind: "inference_engine")
        let value = try deployment(fixture)
        XCTAssertTrue(value.components.isEmpty)
        XCTAssertEqual(value.result.outcome, .skipped)
        XCTAssertEqual(value.mode, .unknown)
    }
}
