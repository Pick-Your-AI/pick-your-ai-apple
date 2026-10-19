import Foundation
import XCTest
@testable import PlannerTransfer

struct CapacityTestPool {
    var id = "pool.1"
    var devices = ["device.1"]
    var capacity = "24"
    var reserve = "0"
    var reserveBasis = "before_reserve"
    var space: String?
    var partition = "whole"
    var tenancy = "tenant.1"
}
struct CapacityTestDevice {
    var id = "device.1"
    var selection = "sel_gpu"
    var pool = "pool.1"
}
struct CapacityTestConsumer {
    var id = "consumer.1"
    var component = "sel_model"
    var devices = ["device.1"]
    var runtime: [String: Any]?
}
struct CapacityTestAllocation {
    var id = "allocation.1"
    var pool = "pool.1"
    var consumers = ["consumer.1"]
    var bytes = "18"
    var extent: String?
    var nonOverlapping = true
    var term = "weights"
}
struct CapacityTestScenario {
    var id = "scenario.1"
    var components = ["sel_model"]
    var excluded: [String] = []
    var omittedRows: [String] = []
    var amounts: [String: String] = [:]
}
struct CapacityTestLimit {
    var id = "limit.1"
    var scenario = "scenario.1"
    var consumer = "consumer.1"
    var demand = "18"
    var capacity = "24"
    var reserve = "0"
    var applicable = true
    var runtime: [String: Any]?
}

/// Builds explicit test inputs; expected outcomes are supplied by the individual policy cases.
final class CapacityMemoryDraft {
    let input: CapacityTestDraft
    var pools = [CapacityTestPool()]
    var devices = [CapacityTestDevice()]
    var consumers = [CapacityTestConsumer()]
    var allocations = [CapacityTestAllocation()]
    var scenarios = [CapacityTestScenario()]
    var limits: [CapacityTestLimit] = []
    var mode = CapacityCoverageMode.conservativeAllResident

    init() throws { input = try CapacityTestDraft(); try input.serving() }
    func addDevice(_ device: CapacityTestDevice, kind: String = "accelerator") throws {
        devices.append(device)
        try input.selection(device.selection, kind: kind)
        try input.link("link.memory." + device.id, from: "sel_model", to: device.selection, role: .device)
    }
    func freeze(edit: (CapacityTestDraft) throws -> Void = { _ in }) throws -> CapacityMemoryFixture {
        let d = input
        let selected = try XCTUnwrap(d.build["selections"] as? [[String: Any]])
        let componentIDs = try selected.filter {
            ["model", "embedding_model", "fine_tuned_model", "vector_database"].contains($0["kind"] as? String ?? "")
        }.map { try XCTUnwrap($0["id"] as? String) }
        for (prefix, ids) in [
            ("components", componentIDs), ("devices", devices.map { $0.id }),
            ("pools", pools.map { $0.id }), ("consumers", consumers.map { $0.id }),
            ("allocations", allocations.map { $0.id }), ("scenarios", scenarios.map { $0.id }),
            ("limits", limits.map { $0.id })
        ] { d.inventory("/memory/" + prefix, ids: ids) }
        d.put("/memory/transitions", true)
        for device in devices {
            d.put("/devices/" + device.id + "/selection", device.selection)
            d.put("/devices/" + device.id + "/pool", device.pool)
        }
        for pool in pools {
            let p = "/pools/" + pool.id
            d.put(p + "/space", pool.space ?? "address-space-" + pool.id)
            d.put(p + "/partition", pool.partition); d.put(p + "/tenancy", pool.tenancy)
            d.put(p + "/devices", pool.devices); d.budget(p + "/budget", capacity: pool.capacity, reserve: pool.reserve)
            d.put(p + "/budget/basis", pool.reserveBasis)
        }
        for consumer in consumers {
            let p = "/consumers/" + consumer.id
            d.put(p + "/component", consumer.component); d.put(p + "/operation", d.operation)
            d.put(p + "/devices", consumer.devices); d.put(p + "/runtime", consumer.runtime ?? d.runtime())
        }
        for allocation in allocations {
            let p = "/allocations/" + allocation.id
            d.put(p + "/pool", allocation.pool); d.put(p + "/consumers", allocation.consumers)
            d.put(p + "/extent", allocation.extent ?? "extent-" + allocation.id)
            d.put(p + "/non-overlapping", allocation.nonOverlapping)
            d.put(p + "/term", allocation.term); d.put(p + "/method", "synthetic-physical-allocation")
        }
        for scenario in scenarios {
            let p = "/scenarios/" + scenario.id
            d.put(p + "/envelope", "synthetic-scoped-lifetime-" + scenario.id)
            d.put(p + "/components", scenario.components); d.put(p + "/complete", true)
            for allocation in allocations where !scenario.omittedRows.contains(where: { contextExact($0, allocation.id) }) {
                let row = p + "/rows/" + allocation.id
                d.put(row + "/residency", scenario.excluded.contains(where: { contextExact($0, allocation.id) }) ? "excluded" : "resident")
                d.range(row + "/bytes", upper: scenario.amounts[allocation.id] ?? allocation.bytes)
                for consumer in allocation.consumers { d.put(row + "/access/" + consumer, true) }
            }
        }
        for limit in limits {
            let p = "/limits/" + limit.id
            d.put(p + "/consumer", limit.consumer); d.put(p + "/runtime", limit.runtime ?? d.runtime())
            d.put(p + "/applies", limit.applicable); d.put(p + "/definition", "synthetic-independent-accounting")
            d.put(p + "/complete", true); d.range(p + "/demand", upper: limit.demand)
            d.budget(p + "/budget", capacity: limit.capacity, reserve: limit.reserve)
        }
        try edit(d)
        let f = try d.freeze(), deployment = try f.deployment()
        let componentRecords = try componentIDs.map { id in
            let applies = try f.answer("/components/" + id + "/applies", .boolean)
            let placement = try f.answer("/components/" + id + "/placement", .placement)
            let domain = try CapacityDomain.component(id)
            try f.qualify(applies, .applicability, domain); try f.qualify(placement, .residency, domain)
            return try CapacityMemoryComponent(id: id, applicable: applies, placement: placement)
        }
        let deviceRecords = try devices.map { value in
            let p = "/devices/" + value.id, domain = try CapacityDomain.device(value.id)
            let selection = try f.answer(p + "/selection", .text), pool = try f.answer(p + "/pool", .text)
            try f.qualify(selection, .inventory, domain); try f.qualify(pool, .inventory, domain)
            return try CapacityDevice(id: value.id, selectionID: selection, poolID: pool)
        }
        let poolRecords = try pools.map { value in
            let p = "/pools/" + value.id
            let space = try f.answer(p + "/space", .text), partition = try f.answer(p + "/partition", .text)
            let tenancy = try f.answer(p + "/tenancy", .text), ids = try f.answer(p + "/devices", .textSet)
            let domain = try CapacityDomain.physical(pool: value.id, addressSpace: space.text,
                                                     partition: partition.text, tenancy: tenancy.text)
            for answer in [space, partition, tenancy] { try f.qualify(answer, .physicalIdentity, domain) }
            try f.qualify(ids, .inventory, domain)
            return try CapacityPool(id: value.id, addressSpace: space, partition: partition, tenancy: tenancy,
                                    deviceIDs: ids, budget: f.budget(p + "/budget", domain: domain))
        }
        let consumerRecords = try consumers.map { value in
            let p = "/consumers/" + value.id
            let component = try f.answer(p + "/component", .text), operation = try f.answer(p + "/operation", .text)
            let devices = try f.answer(p + "/devices", .textSet)
            let binding = try CapacityRuntimeBinding(answer: f.answer(p + "/runtime", .runtimeBinding))
            let domain = try binding.domain ?? .component(value.id)
            for answer in [component, operation, devices, binding.answer] { try f.qualify(answer, .inventory, domain) }
            return try CapacityConsumer(id: value.id, componentID: component, operation: operation,
                                        deviceIDs: devices, binding: binding)
        }
        let allocationRecords = try allocations.map { value in
            let p = "/allocations/" + value.id
            return try CapacityAllocation(id: value.id, poolID: f.answer(p + "/pool", .text),
                consumerIDs: f.answer(p + "/consumers", .textSet), extent: f.answer(p + "/extent", .text),
                nonOverlapping: f.answer(p + "/non-overlapping", .boolean), term: f.answer(p + "/term", .text),
                method: f.answer(p + "/method", .text))
        }
        let scenarioRecords = try scenarios.map { value in
            let p = "/scenarios/" + value.id
            let envelope = try f.answer(p + "/envelope", .text), ids = try f.answer(p + "/components", .textSet)
            let domain = try CapacityDomain.inventory(kind: .scenarios, owner: f.basis.buildID, scenario: value.id)
            try f.qualify(envelope, .workload, domain); try f.qualify(ids, .inventory, domain)
            let rows = try allocationRecords.filter { allocation in
                !value.omittedRows.contains(where: { contextExact($0, allocation.id) })
            }.map { allocation in
                let prefix = p + "/rows/" + allocation.id, pool = allocation.poolID.text
                let scope = try CapacityDomain.allocation(pool: pool, allocation: allocation.id, scenario: value.id)
                for answer in allocation.observations { try f.qualify(answer, .allocationIdentity, scope) }
                let residency = try f.answer(prefix + "/residency", .residency)
                try f.qualify(residency, .residency, scope)
                let original = try XCTUnwrap(allocations.first { contextExact($0.id, allocation.id) })
                let access = try original.consumers.map { id in
                    let allowed = try f.answer(prefix + "/access/" + id, .boolean)
                    if let pool, let runtime = consumerRecords.first(where: { contextExact($0.id, id) })?.binding.domain {
                        try f.qualify(allowed, .access, .access(pool: pool, allocation: allocation.id,
                                                             scenario: value.id, consumer: id, runtime: runtime))
                    }
                    return try CapacityAllocationAccess(consumerID: id, allowed: allowed)
                }
                return try CapacityResidency(allocationID: allocation.id, residency: residency,
                                             liveBytes: f.range(prefix + "/bytes", domain: scope), access: access)
            }
            return try CapacityScenario(id: value.id, envelope: envelope, componentIDs: ids, rows: rows,
                coverage: f.coverage(p + "/complete", .chargeTerms, scenario: value.id))
        }
        let limitRecords = try limits.map { value in
            let p = "/limits/" + value.id
            let consumer = try f.answer(p + "/consumer", .text)
            let binding = try CapacityRuntimeBinding(answer: f.answer(p + "/runtime", .runtimeBinding))
            let domain: CapacityDomain
            if let runtime = binding.domain { domain = try .ceiling(limit: value.id, scenario: value.scenario, runtime: runtime) }
            else { domain = try .inventory(kind: .independentCeilings, owner: f.basis.buildID, scenario: value.scenario) }
            let applies = try f.answer(p + "/applies", .boolean), definition = try f.answer(p + "/definition", .text)
            let complete = try f.answer(p + "/complete", .boolean)
            try f.qualify(applies, .applicability, domain); try f.qualify(complete, .coverage, domain)
            for answer in [consumer, binding.answer, definition] { try f.qualify(answer, .ceiling, domain) }
            return try CapacityIndependentLimit(id: value.id, scenarioID: value.scenario, consumerID: consumer,
                binding: binding, applicable: applies, demand: f.range(p + "/demand", domain: domain),
                budget: f.budget(p + "/budget", domain: domain), accountingDefinition: definition, accountingComplete: complete)
        }
        let memory = try CapacityMemory(basis: f.basis, deployment: deployment,
            profile: CapacityBasis.logicalProfile, mode: mode,
            components: f.inventory("/memory/components", records: componentRecords, kind: .servingComponents),
            devices: f.inventory("/memory/devices", records: deviceRecords, kind: .hardwareInstances),
            pools: f.inventory("/memory/pools", records: poolRecords, kind: .physicalPoolMap),
            consumers: f.inventory("/memory/consumers", records: consumerRecords, kind: .consumers),
            allocations: f.inventory("/memory/allocations", records: allocationRecords, kind: .chargeTerms),
            scenarios: f.inventory("/memory/scenarios", records: scenarioRecords, kind: .scenarios),
            limits: f.inventory("/memory/limits", records: limitRecords, kind: .independentCeilings),
            transitions: f.coverage("/memory/transitions", .transitions))
        return CapacityMemoryFixture(context: f, deployment: deployment, memory: memory)
    }
}

struct CapacityMemoryFixture {
    let context: CapacityTestContext
    let deployment: CapacityDeployment
    let memory: CapacityMemory
    func result(omitting omit: (CapacityQualification) -> Bool = { _ in false }) throws -> CapacityResult {
        try memory.evaluate(current: context.basis, qualifications: context.qualifications(omitting: omit))
    }
}
extension CapacityResult {
    var testPoolChecks: [CapacityCheck] { checks.filter { $0.rule == .memoryPool && $0.domain.kind == .poolScenario } }
}
