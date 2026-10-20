import Foundation
import XCTest
@testable import PlannerTransfer

/// Typed expectations from the accepted CD-2 worked table; U is exactly 1,000,000,000 bytes.
/// These synthetic caller assessments are not a portable wire corpus or measured hardware evidence.
final class CapacityWorkedExampleTests: XCTestCase {
    private func u(_ count: Int) -> String { String(count * 1_000_000_000) }

    private func twoOnDemand() throws -> CapacityMemoryDraft {
        let draft = try CapacityMemoryDraft()
        try draft.input.serving("sel_second")
        draft.consumers.append(CapacityTestConsumer(id: "consumer.2", component: "sel_second"))
        draft.pools[0].capacity = u(24); draft.pools[0].reserve = u(4)
        draft.allocations[0].bytes = u(14)
        draft.allocations.append(CapacityTestAllocation(id: "allocation.2", consumers: ["consumer.2"], bytes: u(8)))
        draft.input.put("/components/sel_model/placement", "on_demand")
        draft.input.put("/components/sel_second/placement", "on_demand")
        return draft
    }

    private func hostOffload(staging: Bool = false) throws -> CapacityMemoryDraft {
        let draft = try CapacityMemoryDraft()
        try draft.addDevice(CapacityTestDevice(id: "device.cpu", selection: "sel_cpu", pool: "pool.host"), kind: "compute_profile")
        draft.pools[0].capacity = u(16)
        draft.pools.append(CapacityTestPool(id: "pool.host", devices: ["device.cpu"], capacity: u(32), reserve: u(4)))
        draft.consumers[0].devices = ["device.1", "device.cpu"]
        draft.allocations[0].bytes = u(12)
        draft.allocations.append(CapacityTestAllocation(id: "allocation.host", pool: "pool.host", bytes: u(18), term: "host-offload"))
        if staging {
            draft.allocations.append(CapacityTestAllocation(id: "allocation.staging", pool: "pool.host", bytes: u(16), term: "transfer-staging"))
        }
        return draft
    }

    private func vectorService() throws -> CapacityMemoryDraft {
        let draft = try CapacityMemoryDraft(componentKind: "vector_database", engine: nil)
        draft.pools[0].capacity = u(24)
        draft.consumers[0].runtime = draft.input.runtime(id: "vector-runtime.1", kind: "service_runtime", build: "vector-build.1")
        draft.allocations[0].bytes = u(14); draft.allocations[0].term = "resident-index"
        draft.allocations.append(CapacityTestAllocation(id: "allocation.compaction", bytes: u(8), term: "temporary-compaction"))
        draft.mode = .qualifiedScenarios
        draft.scenarios = [CapacityTestScenario(excluded: ["allocation.compaction"]),
                           CapacityTestScenario(id: "scenario.compaction")]
        return draft
    }

    func testE01OnePoolChargesBothTermsAndReserveOnce() throws {
        let draft = try CapacityMemoryDraft()
        draft.pools[0].capacity = u(24); draft.pools[0].reserve = u(2)
        draft.allocations[0].bytes = u(14)
        draft.allocations.append(CapacityTestAllocation(id: "allocation.runtime", bytes: u(6), term: "runtime"))
        let result = try draft.freeze().result(), pool = try XCTUnwrap(result.testPoolChecks.first)
        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(pool.demandUpper?.decimal, u(20)); XCTAssertEqual(pool.reserveUpper?.decimal, u(2))
        XCTAssertEqual(pool.capacityLower?.decimal, u(24)); XCTAssertEqual(pool.chargeIDs.count, 2)
    }

    func testE02KnownUpperBoundExcessProducesMayNotFit() throws {
        let draft = try CapacityMemoryDraft()
        draft.pools[0].capacity = u(24); draft.allocations[0].bytes = u(18)
        draft.allocations.append(CapacityTestAllocation(id: "allocation.runtime", bytes: u(8), term: "runtime"))
        let pool = try XCTUnwrap(draft.freeze().result().testPoolChecks.first)
        XCTAssertEqual(pool.demandUpper?.decimal, u(26)); XCTAssertEqual(pool.outcome, .fail)
        XCTAssertEqual(pool.reason, .overUpperBoundBudget); XCTAssertTrue(pool.mayNotFit)
    }

    func testE03UMAHostAndDeviceShareOnePhysicalBudget() throws {
        let draft = try CapacityMemoryDraft()
        try draft.addDevice(CapacityTestDevice(id: "device.cpu", selection: "sel_cpu", pool: "pool.1"), kind: "compute_profile")
        draft.pools[0].devices = ["device.1", "device.cpu"]; draft.pools[0].capacity = u(24)
        draft.consumers[0].devices = ["device.1", "device.cpu"]
        draft.allocations[0].bytes = u(18)
        draft.allocations.append(CapacityTestAllocation(id: "allocation.host", bytes: u(8), term: "host-copy"))
        let pools = try draft.freeze().result().testPoolChecks
        XCTAssertEqual(pools.count, 1); XCTAssertEqual(pools[0].capacityLower?.decimal, u(24))
        XCTAssertEqual(pools[0].demandUpper?.decimal, u(26)); XCTAssertEqual(pools[0].outcome, .fail)
    }

    func testE04DiscreteBudgetsDoNotBecomeOneAdvertisedSum() throws {
        let draft = try CapacityMemoryDraft()
        try draft.addDevice(CapacityTestDevice(id: "device.2", selection: "sel_gpu2", pool: "pool.2"))
        draft.pools[0].capacity = u(24)
        draft.pools.append(CapacityTestPool(id: "pool.2", devices: ["device.2"], capacity: u(24)))
        draft.consumers[0].devices = ["device.1", "device.2"]; draft.allocations[0].bytes = u(30)
        draft.allocations.append(CapacityTestAllocation(id: "allocation.2", pool: "pool.2", bytes: u(6)))
        let pools = try draft.freeze().result().testPoolChecks
        XCTAssertEqual(pools.map(\.outcome), [.fail, .pass])
        XCTAssertEqual(pools.map { $0.capacityLower?.decimal }, [u(24), u(24)])
        XCTAssertEqual(pools.map { $0.demandUpper?.decimal }, [u(30), u(6)])
    }

    func testE05OneSharedAllocationAndTwoActualCopiesHaveDifferentTotals() throws {
        for copied in [false, true] {
            let draft = try CapacityMemoryDraft()
            try draft.input.serving("sel_second")
            draft.scenarios[0].components = ["sel_model", "sel_second"]
            draft.consumers.append(CapacityTestConsumer(id: "consumer.2", component: "sel_second"))
            draft.pools[0].capacity = u(20); draft.pools[0].reserve = u(2)
            draft.allocations[0].bytes = u(8)
            draft.allocations[0].consumers = copied ? ["consumer.1"] : ["consumer.1", "consumer.2"]
            if copied { draft.allocations.append(CapacityTestAllocation(id: "allocation.copy", consumers: ["consumer.2"], bytes: u(8))) }
            draft.allocations.append(CapacityTestAllocation(id: "allocation.other", bytes: u(6), term: "runtime"))
            let pool = try XCTUnwrap(draft.freeze().result().testPoolChecks.first)
            XCTAssertEqual(pool.demandUpper?.decimal, copied ? u(22) : u(14))
            XCTAssertEqual(pool.reserveUpper?.decimal, u(2))
            XCTAssertEqual(pool.outcome, copied ? .fail : .pass)
            XCTAssertEqual(pool.chargeIDs.count, copied ? 3 : 2)
        }
    }

    func testE06BeforeAndAfterReserveBudgetsAgreeAtTheExactBoundary() throws {
        for basis in ["before_reserve", "after_reserve"] {
            for (demand, outcome) in [(u(22), CapacityOutcome.pass), ("22000000001", .fail)] {
                let draft = try CapacityMemoryDraft()
                draft.pools[0].capacity = basis == "before_reserve" ? u(24) : u(22)
                draft.pools[0].reserve = u(2); draft.pools[0].reserveBasis = basis
                draft.allocations[0].bytes = demand
                let pool = try XCTUnwrap(draft.freeze().result().testPoolChecks.first)
                XCTAssertEqual(pool.outcome, outcome); XCTAssertEqual(pool.demandUpper?.decimal, demand)
                XCTAssertEqual(pool.reserveUpper?.decimal, u(2))
            }
        }
    }

    func testE07AnExplicitQualifiedZeroBudgetAdmitsOnlyZeroLiveDemand() throws {
        for (demand, outcome) in [("0", CapacityOutcome.pass), ("1", .fail)] {
            let draft = try CapacityMemoryDraft()
            draft.pools[0].capacity = "0"; draft.pools[0].reserve = u(2)
            draft.pools[0].reserveBasis = "after_reserve"; draft.allocations[0].bytes = demand
            let fixture = try draft.freeze(), pool = try XCTUnwrap(fixture.result().testPoolChecks.first)
            XCTAssertEqual(pool.capacityLower?.decimal, "0"); XCTAssertEqual(pool.demandUpper?.decimal, demand)
            XCTAssertEqual(pool.outcome, outcome)
            XCTAssertEqual(try fixture.result { $0.key.requestedPath.hasSuffix("/reservation") }
                .testPoolChecks.first?.outcome, .unknown)
        }
    }

    func testE08QualifiedExclusiveLifetimesDifferFromConservativeAllResident() throws {
        let conservative = try twoOnDemand(); conservative.scenarios[0].components = ["sel_model", "sel_second"]
        let all = try XCTUnwrap(conservative.freeze().result().testPoolChecks.first)
        XCTAssertEqual(all.demandUpper?.decimal, u(22)); XCTAssertEqual(all.reserveUpper?.decimal, u(4))
        XCTAssertEqual(all.outcome, .fail)
        let selected = try twoOnDemand(); selected.mode = .qualifiedScenarios
        selected.scenarios = [CapacityTestScenario(excluded: ["allocation.2"]),
            CapacityTestScenario(id: "scenario.2", components: ["sel_second"], excluded: ["allocation.1"])]
        let result = try selected.freeze().result()
        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(result.testPoolChecks.map { $0.demandUpper?.decimal }, [u(14), u(8)])
    }

    func testE09MissingExhaustivenessChargeOrTransitionEvidenceCannotProveFit() throws {
        for missing in ["/memory/scenarios/complete", "/scenarios/scenario.1/complete", "/memory/transitions"] {
            let draft = try twoOnDemand(); draft.mode = .qualifiedScenarios
            draft.scenarios = [CapacityTestScenario(excluded: ["allocation.2"]),
                CapacityTestScenario(id: "scenario.2", components: ["sel_second"], excluded: ["allocation.1"])]
            let fixture = try draft.freeze()
            XCTAssertEqual(try fixture.result().outcome, .pass)
            XCTAssertEqual(try fixture.result { $0.key.requestedPath == missing }.outcome, .unknown, missing)
        }
    }

    func testE10IndependentKnownExcessSurvivesAnUnknownExtraTerm() throws {
        let draft = try CapacityMemoryDraft()
        draft.pools[0].capacity = u(24); draft.allocations[0].bytes = u(30)
        draft.allocations.append(CapacityTestAllocation(id: "allocation.unknown", bytes: u(8), term: "runtime"))
        let result = try draft.freeze { $0.state("/scenarios/scenario.1/rows/allocation.unknown/bytes/upper", .unknown) }.result()
        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.testPoolChecks.first?.demandUpper?.decimal, u(30))
        XCTAssertTrue(result.checks.contains { $0.outcome == .unknown })
    }

    func testE11HostOffloadIsChargedSeparatelyAndAccessRemainsIndependent() throws {
        let fixture = try hostOffload().freeze(), result = try fixture.result()
        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(result.testPoolChecks.map { $0.demandUpper?.decimal }, [u(12), u(18)])
        XCTAssertEqual(result.testPoolChecks.map { $0.reserveUpper?.decimal }, ["0", u(4)])
        XCTAssertEqual(result.testPoolChecks.map { $0.capacityLower?.decimal }, [u(16), u(32)])
        let access = try fixture.result { $0.key.fact == .access }
        XCTAssertEqual(access.outcome, .unknown)
        XCTAssertEqual(access.testPoolChecks.map(\.outcome), [.pass, .pass])
    }

    func testE12CoexistingTransferStagingConsumesTheHostPool() throws {
        let result = try hostOffload(staging: true).freeze().result()
        XCTAssertEqual(result.outcome, .fail)
        XCTAssertEqual(result.testPoolChecks.map(\.outcome), [.pass, .fail])
        let host = try XCTUnwrap(result.testPoolChecks.last)
        XCTAssertEqual(host.demandUpper?.decimal, u(34)); XCTAssertEqual(host.reserveUpper?.decimal, u(4))
        XCTAssertEqual(host.capacityLower?.decimal, u(32))
        XCTAssertEqual(host.chargeIDs, ["allocation.host", "allocation.staging"])
    }

    func testE13TwoReplicasConsumeOnePoolAndExplicitRankQuotasStayIndependent() throws {
        let draft = try CapacityMemoryDraft()
        draft.pools[0].capacity = u(24); draft.allocations[0].bytes = u(14)
        let other = draft.input.runtime(replica: "replica.2", rank: "rank.1")
        draft.consumers.append(CapacityTestConsumer(id: "consumer.replica2", runtime: other))
        draft.allocations.append(CapacityTestAllocation(id: "allocation.replica2", consumers: ["consumer.replica2"], bytes: u(14)))
        draft.limits = [CapacityTestLimit(demand: u(14), capacity: u(8)),
            CapacityTestLimit(id: "limit.2", consumer: "consumer.replica2", demand: u(14), capacity: u(12), runtime: other)]
        let result = try draft.freeze().result()
        XCTAssertEqual(result.testPoolChecks.first?.demandUpper?.decimal, u(28))
        XCTAssertEqual(result.testPoolChecks.first?.outcome, .fail)
        let quotas = result.checks.filter { $0.rule == .independentCeiling }
        XCTAssertEqual(quotas.map(\.outcome), [.fail, .fail])
        XCTAssertEqual(quotas.map { $0.capacityLower?.decimal }, [u(8), u(12)])
    }

    func testE14MissingWithheldUnknownAndLiteralZeroRemainDifferent() throws {
        for state in [CapacityAnswerState.unknown, .missing, .withheld] {
            let draft = try CapacityMemoryDraft(); draft.pools[0].capacity = u(24)
            draft.allocations[0].bytes = u(18)
            draft.allocations.append(CapacityTestAllocation(id: "allocation.runtime", bytes: "0", term: "runtime"))
            XCTAssertEqual(try draft.freeze { $0.state("/scenarios/scenario.1/rows/allocation.runtime/bytes/upper", state) }
                .result().outcome, .unknown)
        }
        let zero = try CapacityMemoryDraft(); zero.pools[0].capacity = u(24); zero.allocations[0].bytes = u(18)
        zero.allocations.append(CapacityTestAllocation(id: "allocation.runtime", bytes: "0", term: "runtime"))
        XCTAssertEqual(try zero.freeze().result().outcome, .pass)
    }

    func testE15ContradictoryOrMalformedNormalizedRecordsRejectBeforeOutcomes() throws {
        let duplicateAllocation = try CapacityMemoryDraft(); duplicateAllocation.allocations.append(duplicateAllocation.allocations[0])
        XCTAssertThrowsError(try duplicateAllocation.freeze())
        let duplicateScenario = try CapacityMemoryDraft(); duplicateScenario.scenarios.append(duplicateScenario.scenarios[0])
        XCTAssertThrowsError(try duplicateScenario.freeze())
        let malformed: [Any] = [18, true, "01", "1.0", "1e3"]
        for value in malformed {
            XCTAssertThrowsError(try CapacityMemoryDraft().freeze {
                $0.put("/components/sel_model/applies", false)
                $0.put("/scenarios/scenario.1/rows/allocation.1/bytes/upper", value)
            })
        }
        XCTAssertThrowsError(try CapacityMemoryDraft().freeze { $0.put("/allocations/allocation.1/pool", "missing-pool") })
        XCTAssertThrowsError(try CapacityMemoryDraft().freeze { $0.put("/pools/pool.1/devices", []) })
    }

    func testE16OtherRuntimeQualificationsAndUnknownKVDoNotEstablishMemoryFit() throws {
        for member in ["build", "replica"] {
            let fixture = try CapacityMemoryDraft().freeze()
            let binding = fixture.memory.consumers.records[0].binding
            let actual = try XCTUnwrap(binding.domain)
            let key = try binding.answer.qualificationKey(fact: .inventory, domain: actual)
            fixture.context.claims.removeValue(forKey: key.sha256)
            let different = try CapacityDomain.runtime(CapacityRuntime(kind: .modelEngine, id: "sel_engine"),
                build: member == "build" ? "other-build" : "engine-build.1", instance: "instance.1",
                replica: member == "replica" ? "other-replica" : "replica.1", rank: "rank.0", admission: "admission.1", stage: "stage.1")
            try fixture.context.qualify(binding.answer, .inventory, different)
            XCTAssertEqual(try fixture.result().outcome, .unknown, member)
        }
        let draft = try CapacityMemoryDraft()
        draft.allocations.append(CapacityTestAllocation(id: "allocation.kv", bytes: "0", term: "kv-cache"))
        XCTAssertEqual(try draft.freeze { $0.state("/scenarios/scenario.1/rows/allocation.kv/bytes/upper", .unknown) }
            .result().outcome, .unknown)
    }

    func testE17OneByteBeyondBinary64ExactIntegerRangeRemainsAnExcess() throws {
        let draft = try CapacityMemoryDraft()
        draft.pools[0].capacity = "9007199254740992"; draft.pools[0].reserveBasis = "after_reserve"
        draft.allocations[0].bytes = "9007199254740993"
        let pool = try XCTUnwrap(draft.freeze().result().testPoolChecks.first)
        XCTAssertEqual(pool.demandUpper?.decimal, "9007199254740993")
        XCTAssertEqual(pool.capacityLower?.decimal, "9007199254740992")
        XCTAssertEqual(pool.outcome, .fail); XCTAssertTrue(pool.mayNotFit)
    }

    func testE18VectorServiceRuntimeKeepsIndexAndTemporaryLifetimesWithoutAnEngine() throws {
        let fixture = try vectorService().freeze(), result = try fixture.result()
        XCTAssertEqual(result.outcome, .pass)
        XCTAssertEqual(result.testPoolChecks.map { $0.demandUpper?.decimal }, [u(14), u(22)])
        XCTAssertEqual(result.testPoolChecks.map { $0.chargeIDs }, [["allocation.1"], ["allocation.1", "allocation.compaction"]])
        let deployment = try fixture.deployment.evaluate(current: fixture.context.basis,
            qualifications: fixture.context.qualifications())
        XCTAssertEqual(deployment.components.first?.serving?.engine?.check.outcome, .skipped)
        XCTAssertEqual(fixture.memory.consumers.records[0].binding.runtime?.kind, .serviceRuntime)
        let opaque = try vectorService().freeze {
            $0.put("/deployment/sel_model/operator", "provider")
            $0.put("/deployment/sel_model/capacity", "shared")
            $0.put("/deployment/sel_model/exposed", false)
            $0.put("/components/sel_model/applies", false)
        }
        XCTAssertEqual(try opaque.result().outcome, .skipped)
        let remote = try opaque.deployment.evaluate(current: opaque.context.basis,
            qualifications: opaque.context.qualifications())
        XCTAssertTrue(remote.result.checks.contains { $0.rule == .remoteCapacity && $0.outcome == .unknown })
        let missing = try vectorService()
        try missing.input.serving("sel_other", kind: "vector_database", engine: nil)
        for index in missing.scenarios.indices { missing.scenarios[index].components.append("sel_other") }
        XCTAssertEqual(try missing.freeze { $0.state("/components/sel_other/placement", .unknown) }.result().outcome, .unknown)
    }
}
