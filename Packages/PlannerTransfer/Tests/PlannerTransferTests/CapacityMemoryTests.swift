import Foundation
import XCTest
@testable import PlannerTransfer

final class CapacityMemoryTests: XCTestCase {
    func testQualifiedSinglePoolPreservesOriginalInputsAndConditionalResult() throws {
        let f = try CapacityMemoryDraft().freeze()
        let result = try f.result(), pool = try XCTUnwrap(result.testPoolChecks.first)
        XCTAssertEqual(result.outcome, .pass); XCTAssertTrue(result.conditionalCapacity)
        XCTAssertEqual(result.basisSHA256, f.context.basis.sha256)
        XCTAssertEqual(pool.demandUpper?.decimal, "18"); XCTAssertEqual(pool.capacityLower?.decimal, "24")
        XCTAssertEqual(pool.reserveUpper?.decimal, "0"); XCTAssertEqual(pool.chargeIDs, ["allocation.1"])
        XCTAssertFalse(pool.mayNotFit); XCTAssertTrue(result.checkedOnly == false)
        XCTAssertEqual(f.context.answers.originalBytes, f.context.basis.input(named: "answers")?.originalBytes)
        XCTAssertEqual(f.context.answers.originalSHA256, f.context.basis.input(named: "answers")?.sha256)
        XCTAssertEqual(result.severity, "error"); XCTAssertEqual(result.onUnknown, "review")
    }

    func testUMAChargesHostAndDeviceAllocationsAgainstOneExact24GiBPool() throws {
        let d = try CapacityMemoryDraft()
        try d.addDevice(CapacityTestDevice(id: "device.cpu", selection: "sel_cpu", pool: "pool.1"), kind: "compute_profile")
        d.pools[0].devices = ["device.1", "device.cpu"]; d.pools[0].capacity = "25769803776"
        d.consumers[0].devices = ["device.1", "device.cpu"]
        d.allocations[0].bytes = "19327352832" // 18 * 2^30
        d.allocations.append(CapacityTestAllocation(id: "allocation.host", bytes: "8589934592", term: "host-copy"))
        let result = try d.freeze().result(), pool = try XCTUnwrap(result.testPoolChecks.first)
        XCTAssertEqual(result.outcome, .fail); XCTAssertEqual(pool.outcome, .fail)
        XCTAssertEqual(pool.demandUpper?.decimal, "27917287424") // (18 + 8) * 2^30
        XCTAssertEqual(pool.capacityLower?.decimal, "25769803776"); XCTAssertTrue(pool.mayNotFit)
    }

    func testDiscretePoolsCannotBorrowEachOthersAdvertisedCapacity() throws {
        let d = try CapacityMemoryDraft()
        try d.addDevice(CapacityTestDevice(id: "device.2", selection: "sel_gpu2", pool: "pool.2"))
        d.pools[0].capacity = "25769803776"
        d.pools.append(CapacityTestPool(id: "pool.2", devices: ["device.2"], capacity: "25769803776"))
        d.consumers[0].devices = ["device.1", "device.2"]
        d.allocations[0].bytes = "32212254720" // 30 GiB
        d.allocations.append(CapacityTestAllocation(id: "allocation.2", pool: "pool.2", bytes: "6442450944"))
        let pools = try d.freeze().result().testPoolChecks
        XCTAssertEqual(pools.map { $0.outcome }, [.fail, .pass])
        XCTAssertEqual(pools.map { $0.demandUpper?.decimal }, ["32212254720", "6442450944"])
        XCTAssertEqual(pools.map { $0.capacityLower?.decimal }, ["25769803776", "25769803776"])
    }

    func testAQualifiedSharedExtentIsChargedOnceAndTwoRealCopiesAreChargedTwice() throws {
        func draft() throws -> CapacityMemoryDraft {
            let d = try CapacityMemoryDraft()
            try d.input.serving("sel_second")
            d.consumers.append(CapacityTestConsumer(id: "consumer.2", component: "sel_second"))
            d.scenarios[0].components = ["sel_model", "sel_second"]
            d.allocations[0].consumers = ["consumer.1", "consumer.2"]
            return d
        }
        let shared = try draft().freeze().result()
        XCTAssertEqual(shared.outcome, .pass)
        XCTAssertEqual(shared.testPoolChecks.first?.demandUpper?.decimal, "18")
        let copied = try draft()
        copied.allocations.append(CapacityTestAllocation(id: "allocation.copy", consumers: ["consumer.2"], term: "copy"))
        let result = try copied.freeze().result()
        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.testPoolChecks.first?.demandUpper?.decimal, "36")
        XCTAssertEqual(result.testPoolChecks.first?.chargeIDs, ["allocation.1", "allocation.copy"])
    }

    func testUnqualifiedSharingDoesNotBecomeAZeroByteFit() throws {
        let f = try CapacityMemoryDraft().freeze()
        let result = try f.result { $0.key.fact == .allocationIdentity && $0.key.requestedPath.hasSuffix("/extent") }
        XCTAssertEqual(result.outcome, .unknown)
        XCTAssertEqual(result.testPoolChecks.first?.outcome, .unknown)
        XCTAssertEqual(result.testPoolChecks.first?.chargeIDs, [])
    }

    func testKnownOverBudgetSubsetSurvivesAnUnknownAdditionalNonnegativeCharge() throws {
        let d = try CapacityMemoryDraft()
        d.allocations[0].bytes = "30"
        d.allocations.append(CapacityTestAllocation(id: "allocation.unknown", bytes: "8", term: "runtime"))
        let f = try d.freeze { $0.state("/scenarios/scenario.1/rows/allocation.unknown/bytes/upper", .unknown) }
        let result = try f.result(), pool = try XCTUnwrap(result.testPoolChecks.first)
        XCTAssertEqual(result.outcome, .fail); XCTAssertEqual(pool.outcome, .fail)
        XCTAssertEqual(pool.demandUpper?.decimal, "30"); XCTAssertEqual(pool.chargeIDs, ["allocation.1"])
        XCTAssertTrue(result.checks.contains { $0.outcome == .unknown && $0.reason == .unknownResidency })
    }

    func testUnknownRuntimeChargeAndWeightsOnlyCoverageCannotEstablishFit() throws {
        let d = try CapacityMemoryDraft()
        d.allocations.append(CapacityTestAllocation(id: "allocation.runtime", bytes: "4", term: "runtime"))
        let unknown = try d.freeze { $0.state("/scenarios/scenario.1/rows/allocation.runtime/bytes/upper", .unknown) }.result()
        XCTAssertEqual(unknown.outcome, .unknown)
        let onlyWeights = try CapacityMemoryDraft().freeze {
            $0.put("/scenarios/scenario.1/complete", false)
        }.result()
        XCTAssertEqual(onlyWeights.outcome, .unknown)
        XCTAssertEqual(onlyWeights.testPoolChecks.first?.outcome, .unknown)
    }

    func testReserveBasisAppliesExactlyOnceAt16GiBAndOneByteAbove() throws {
        for basis in ["before_reserve", "after_reserve"] {
            for (demand, expected) in [("17179869184", CapacityOutcome.pass), ("17179869185", .fail)] {
                let d = try CapacityMemoryDraft()
                d.pools[0].capacity = basis == "before_reserve" ? "25769803776" : "17179869184"
                d.pools[0].reserve = "8589934592"; d.pools[0].reserveBasis = basis
                d.allocations[0].bytes = demand
                let pool = try XCTUnwrap(d.freeze().result().testPoolChecks.first)
                XCTAssertEqual(pool.outcome, expected, basis + ":" + demand)
                XCTAssertEqual(pool.reserveUpper?.decimal, "8589934592")
                XCTAssertEqual(pool.demandUpper?.decimal, demand)
            }
        }
    }

    func testExplicitZeroReserveAndItsInterpretationStillNeedQualification() throws {
        let f = try CapacityMemoryDraft().freeze()
        for suffix in ["/reserve/upper", "/reservation", "/basis"] {
            let result = try f.result { $0.key.requestedPath.hasSuffix(suffix) }
            XCTAssertEqual(result.testPoolChecks.first?.outcome, .unknown, suffix)
        }
        let unresolved = try CapacityMemoryDraft().freeze {
            $0.state("/pools/pool.1/budget/reserve/upper", .missing)
        }.result()
        XCTAssertEqual(unresolved.testPoolChecks.first?.outcome, .unknown)
    }

    func testProvidedInvertedBoundsAndNoncanonicalByteCountsRejectBeforeSkip() throws {
        XCTAssertThrowsError(try CapacityMemoryDraft().freeze {
            $0.put("/scenarios/scenario.1/rows/allocation.1/bytes/lower", "19")
        })
        let invalidValues: [Any] = ["01", "-1", "1.0", "1e3", 18]
        for value in invalidValues {
            let d = try CapacityMemoryDraft()
            XCTAssertThrowsError(try d.freeze {
                $0.put("/components/sel_model/applies", false)
                $0.put("/scenarios/scenario.1/rows/allocation.1/bytes/upper", value)
            })
        }
        XCTAssertEqual(try CapacityMemoryDraft().freeze().result().outcome, .pass)
    }

    func testQualifiedOnDemandScenariosKeepEachLifetimeInsteadOfSummingStageMaxima() throws {
        let d = try CapacityMemoryDraft()
        try d.input.serving("sel_second")
        d.consumers.append(CapacityTestConsumer(id: "consumer.2", component: "sel_second"))
        d.allocations.append(CapacityTestAllocation(id: "allocation.2", consumers: ["consumer.2"]))
        d.mode = .qualifiedScenarios
        d.scenarios = [
            CapacityTestScenario(excluded: ["allocation.2"]),
            CapacityTestScenario(id: "scenario.2", components: ["sel_second"], excluded: ["allocation.1"])
        ]
        let f = try d.freeze {
            $0.put("/components/sel_model/placement", "on_demand")
            $0.put("/components/sel_second/placement", "on_demand")
        }
        let result = try f.result()
        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(result.testPoolChecks.map { $0.demandUpper?.decimal }, ["18", "18"])
        XCTAssertEqual(result.testPoolChecks.map { $0.chargeIDs }, [["allocation.1"], ["allocation.2"]])
        let missingTransitions = try f.result { $0.key.domain == f.memory.transitions.domain }
        XCTAssertEqual(missingTransitions.outcome, .unknown)
    }

    func testAlwaysResidentAndMissingScenarioRowsRetainUnknownCoverage() throws {
        let d = try CapacityMemoryDraft(); d.mode = .qualifiedScenarios
        d.scenarios[0].components = []
        XCTAssertEqual(try d.freeze().result().outcome, .unknown)
        let missing = try CapacityMemoryDraft(); missing.scenarios[0].omittedRows = ["allocation.1"]
        let result = try missing.freeze().result()
        XCTAssertEqual(result.outcome, .unknown)
        XCTAssertTrue(result.checks.contains { $0.reason == .missingAllocation })
    }

    func testUnresolvedInventoryRetainsPartialRecordsWithoutProvingCompleteness() throws {
        let f = try CapacityMemoryDraft().freeze { $0.state("/memory/allocations/ids", .withheld) }
        XCTAssertEqual(f.memory.allocations.records.count, 1)
        let result = try f.result()
        XCTAssertEqual(result.outcome, .unknown)
        XCTAssertEqual(result.testPoolChecks.first?.outcome, .unknown)
        XCTAssertThrowsError(try CapacityMemoryDraft().freeze { $0.put("/memory/allocations/ids", []) })
    }

    func testOpaqueProviderSkipsLocalArithmeticAndKeepsRemoteCapacityUnknown() throws {
        let f = try CapacityMemoryDraft().freeze {
            $0.put("/deployment/sel_model/operator", "provider")
            $0.put("/deployment/sel_model/capacity", "shared")
            $0.put("/deployment/sel_model/exposed", false)
            $0.put("/components/sel_model/applies", false)
        }
        XCTAssertEqual(try f.result().outcome, .skipped)
        let deployment = try f.deployment.evaluate(current: f.context.basis, qualifications: f.context.qualifications())
        XCTAssertEqual(deployment.mode, .api)
        XCTAssertTrue(deployment.result.checks.contains { $0.rule == .remoteCapacity && $0.outcome == .unknown })
        XCTAssertFalse(try f.result().checks.contains { $0.rule == .memoryPool && $0.outcome == .pass })
    }

    func testUnknownProviderCapacityOrExposureCannotSuppressLocalWork() throws {
        for field in ["capacity", "exposed"] {
            let f = try CapacityMemoryDraft().freeze {
                $0.put("/deployment/sel_model/operator", "provider")
                $0.state("/deployment/sel_model/" + field, .unknown)
            }
            XCTAssertEqual(try f.result().outcome, .unknown, field)
        }
        let contradictory = try CapacityMemoryDraft().freeze { $0.put("/components/sel_model/applies", false) }
        XCTAssertEqual(try contradictory.result().outcome, .unknown)
    }

    func testIndependentSupportFailureSurvivesUnknownCapacity() throws {
        let d = try CapacityMemoryDraft()
        d.input.condition("sel_model", id: "service-limit", kind: .serviceSupport, satisfied: false)
        let result = try d.freeze { $0.state("/pools/pool.1/budget/capacity/lower", .unknown) }.result()
        XCTAssertEqual(result.outcome, .fail)
        XCTAssertTrue(result.checks.contains { $0.outcome == .fail && $0.rule != .memoryPool })
        XCTAssertEqual(result.testPoolChecks.first?.outcome, .unknown)
    }

    func testAccessIsIndependentOfSuccessfulMemoryArithmetic() throws {
        let denied = try CapacityMemoryDraft().freeze {
            $0.put("/scenarios/scenario.1/rows/allocation.1/access/consumer.1", false)
        }.result()
        XCTAssertEqual(denied.outcome, .fail)
        XCTAssertEqual(denied.testPoolChecks.first?.outcome, .pass)
        XCTAssertTrue(denied.checks.contains { $0.rule == .runtimeAccess && $0.outcome == .fail })
        let f = try CapacityMemoryDraft().freeze()
        let missing = try f.result { $0.key.fact == .access }
        XCTAssertEqual(missing.outcome, .unknown)
        XCTAssertEqual(missing.testPoolChecks.first?.outcome, .pass)
    }

    func testIndependentRuntimeCeilingDoesNotBorrowThePassingPoolBudget() throws {
        let d = try CapacityMemoryDraft()
        d.limits = [CapacityTestLimit(capacity: "12")]
        let result = try d.freeze().result()
        XCTAssertEqual(result.testPoolChecks.first?.outcome, .pass)
        let ceiling = try XCTUnwrap(result.checks.first { $0.rule == .independentCeiling })
        XCTAssertEqual(ceiling.outcome, .fail); XCTAssertEqual(ceiling.demandUpper?.decimal, "18")
        XCTAssertEqual(ceiling.capacityLower?.decimal, "12"); XCTAssertTrue(ceiling.mayNotFit)
    }

    func testWrongRankCeilingStaysUnknownAndExplicitInapplicableQuotaSkips() throws {
        let d = try CapacityMemoryDraft()
        d.limits = [CapacityTestLimit(runtime: d.input.runtime(rank: "rank.1"))]
        let wrong = try d.freeze().result()
        XCTAssertEqual(wrong.checks.first { $0.rule == .independentCeiling }?.outcome, .unknown)
        let skipped = try CapacityMemoryDraft()
        skipped.limits = [CapacityTestLimit(applicable: false)]
        XCTAssertEqual(try skipped.freeze().result().checks.first { $0.rule == .independentCeiling }?.outcome, .skipped)
    }

    func testSameGraphEngineBindingCannotBeReplacedByAnotherQualifiedRuntime() throws {
        let d = try CapacityMemoryDraft()
        try d.input.selection("sel_other_engine", kind: "inference_engine")
        d.consumers[0].runtime = d.input.runtime(id: "sel_other_engine")
        XCTAssertEqual(try d.freeze().result().outcome, .unknown)
        let wrongKind = try CapacityMemoryDraft()
        wrongKind.consumers[0].runtime = wrongKind.input.runtime(id: "sel_gpu")
        let wrong = try wrongKind.freeze().result()
        XCTAssertEqual(wrong.outcome, .fail)
        XCTAssertTrue(wrong.checks.contains { $0.rule == .binding && $0.reason == .wrongKindOrDisabled && $0.outcome == .fail })
    }

    func testMissingExactCatalogVersionIsUnknownAndKnownDisabledDeviceFails() throws {
        let d = try CapacityMemoryDraft()
        try d.input.editSelection("sel_gpu") { $0["catalog_item_version"] = "missing-exact-version" }
        XCTAssertEqual(try d.freeze().result().outcome, .unknown)
        let disabled = try CapacityMemoryDraft()
        try disabled.input.editSelection("sel_gpu") { $0["enabled"] = false }
        XCTAssertEqual(try disabled.freeze().result().outcome, .fail)
    }

    func testMalformedUnusedRuntimeReferenceRejectsBeforeOpaqueProviderSkip() throws {
        let d = try CapacityMemoryDraft()
        d.limits = [CapacityTestLimit(applicable: false, runtime: d.input.runtime(source: "absent-input"))]
        XCTAssertThrowsError(try d.freeze {
            $0.put("/deployment/sel_model/operator", "provider")
            $0.put("/deployment/sel_model/capacity", "shared")
            $0.put("/deployment/sel_model/exposed", false)
            $0.put("/components/sel_model/applies", false)
        })
    }

    func testDuplicatePhysicalPoolAndStorageExtentAliasesReject() throws {
        let pools = try CapacityMemoryDraft()
        try pools.addDevice(CapacityTestDevice(id: "device.2", selection: "sel_gpu2", pool: "pool.2"))
        pools.pools.append(CapacityTestPool(id: "pool.2", devices: ["device.2"], space: "address-space-pool.1"))
        XCTAssertThrowsError(try pools.freeze())
        let extents = try CapacityMemoryDraft()
        extents.allocations.append(CapacityTestAllocation(id: "allocation.alias", extent: "extent-allocation.1"))
        XCTAssertThrowsError(try extents.freeze())
    }

    func testReciprocalMembershipAndDanglingScenarioReferencesReject() throws {
        XCTAssertThrowsError(try CapacityMemoryDraft().freeze { $0.put("/pools/pool.1/devices", []) })
        XCTAssertThrowsError(try CapacityMemoryDraft().freeze { $0.put("/allocations/allocation.1/pool", "absent-pool") })
        XCTAssertThrowsError(try CapacityMemoryDraft().freeze { $0.put("/scenarios/scenario.1/components", ["absent-component"]) })
        XCTAssertEqual(try CapacityMemoryDraft().freeze().result().outcome, .pass)
    }

    func testChangedWholeBasisCannotReuseOtherwiseQualifiedMemoryEvidence() throws {
        let f = try CapacityMemoryDraft().freeze()
        let changed = try CapacityBasis(originalBuildBytes: f.context.basis.originalBuildBytes,
            operation: "other-operation", normalizationPolicy: "normalization", sourcePolicy: "source-policy",
            inputs: f.context.inputs, catalogInputName: "catalog")
        let result = try f.memory.evaluate(current: changed, qualifications: f.context.qualifications())
        XCTAssertEqual(result.outcome, .unknown)
        XCTAssertEqual(result.basisSHA256, changed.sha256)
        XCTAssertTrue(result.checks.contains { $0.reason == .changedBasis })
        XCTAssertFalse(result.checks.contains { $0.outcome == .pass })
    }

    func testUnresolvedQualificationConflictAndCheckedOnlyEvidenceRemainScoped() throws {
        let f = try CapacityMemoryDraft().freeze()
        let answer = try f.context.answer("/pools/pool.1/budget/capacity/lower", .byteCount)
        let domain = try XCTUnwrap(f.memory.pools.records.first?.domain)
        try f.context.qualify(answer, .byteBound, domain, resolved: nil)
        XCTAssertEqual(try f.result().testPoolChecks.first?.outcome, .unknown)
        try f.context.qualify(answer, .byteBound, domain, resolved: true, checked: true)
        XCTAssertTrue(try f.result().checkedOnly)
        let removed = try f.result { $0.checkedOnly }
        XCTAssertFalse(removed.checkedOnly)
        XCTAssertEqual(removed.testPoolChecks.first?.outcome, .unknown)
    }

    func testAutomaticDescriptionsDoNotExposeOriginalRuntimeOrSourceValues() throws {
        let f = try CapacityMemoryDraft().freeze()
        let descriptions = [String(reflecting: f.memory), String(reflecting: f.memory.consumers),
            String(reflecting: try f.result()), String(reflecting: f.context.basis),
            String(reflecting: f.memory.consumers.records[0].binding)]
        for text in descriptions {
            for original in ["sel_model", "engine-build.1", "preset:apple-capacity-test", "qualification", "instance.1"] {
                XCTAssertFalse(text.contains(original))
            }
        }
        let original = try f.context.answer("/consumers/consumer.1/runtime", .runtimeBinding)
        XCTAssertEqual(original.observation.value?.value(forExactKey: "build")?.string, "engine-build.1")
        XCTAssertEqual(original.observation.presetSource, "preset:apple-capacity-test")
        XCTAssertEqual(original.observation.assumption, true)
    }
}
