import Foundation

public enum CapacityCoverageMode: String, Sendable {
    case conservativeAllResident = "conservative_all_resident"
    case qualifiedScenarios = "qualified_scenarios"
}

public protocol CapacityIdentifiedRecord: Sendable { var id: String { get } }

/// The original inventory state and its separate completeness assessment remain independent.
/// Partial records can support a failure witness without turning an unresolved inventory into empty.
public struct CapacityRecords<Record: CapacityIdentifiedRecord>: Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    public let ids: CapacityBoundAnswer
    public let records: [Record]
    public let coverage: CapacityCoverage
    private let byID: [Data: Record]
    public var description: String { "CapacityRecords" }
    public var debugDescription: String { description }

    public init(ids: CapacityBoundAnswer, records: [Record], coverage: CapacityCoverage) throws {
        try requireCapacityField(ids, .textSet)
        guard records.count <= 1024 else { throw CapacityError.unsupportedNativeLimit }
        var indexed: [Data: Record] = [:]
        for record in records {
            try capacityIdentity(record.id)
            guard indexed.updateValue(record, forKey: Data(record.id.utf8)) == nil else {
                throw CapacityError.duplicateIdentity
            }
        }
        if ids.provided {
            guard let names = ids.strings else { throw CapacityError.invalidProvidedValue }
            for name in names { try capacityIdentity(name) }
            guard Set(names.map { Data($0.utf8) }) == Set(indexed.keys) else {
                throw CapacityError.contradictoryInput
            }
        }
        self.ids = ids; self.records = records; self.coverage = coverage; byID = indexed
    }

    public func record(id: String) -> Record? {
        guard id.utf8.count <= 4096 else { return nil }
        return byID[Data(id.utf8)]
    }
    func reference(_ id: String) throws {
        try capacityIdentity(id)
        guard byID[Data(id.utf8)] != nil else { throw CapacityError.contradictoryInput }
    }
    func check(basis: CapacityBasis, qualifications: CapacityQualifications) throws -> CapacityCheck {
        let inventory = try qualifications.use(basis: basis, answer: ids, fact: .inventory, domain: coverage.domain)
        let complete = try coverage.use(basis: basis, qualifications: qualifications)
        let known = inventory != nil && complete != nil
        return CapacityCheck(rule: .coverage, domain: coverage.domain, outcome: known ? .pass : .unknown,
            reason: known ? .qualified : .incompleteCoverage,
            observations: [ids, coverage.claim], evidence: [inventory, complete].compactMap { $0 })
    }
}

public struct CapacityMemoryComponent: CapacityIdentifiedRecord,
    CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let applicable: CapacityBoundAnswer
    public let placement: CapacityBoundAnswer
    public let domain: CapacityDomain
    public var description: String { "CapacityMemoryComponent" }
    public var debugDescription: String { description }

    public init(id: String, applicable: CapacityBoundAnswer, placement: CapacityBoundAnswer) throws {
        try requireCapacityField(applicable, .boolean)
        try requireCapacityField(placement, .placement)
        self.id = id; self.applicable = applicable; self.placement = placement
        domain = try .component(id)
    }
    func applicability(basis: CapacityBasis, qualifications: CapacityQualifications) throws -> Bool? {
        guard try qualifications.use(basis: basis, answer: applicable,
                                      fact: .applicability, domain: domain) != nil else { return nil }
        return applicable.boolean
    }
}

public struct CapacityDevice: CapacityIdentifiedRecord, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let selectionID: CapacityBoundAnswer
    public let poolID: CapacityBoundAnswer
    public var description: String { "CapacityDevice" }
    public var debugDescription: String { description }

    public init(id: String, selectionID: CapacityBoundAnswer, poolID: CapacityBoundAnswer) throws {
        try capacityIdentity(id)
        try requireCapacityField(selectionID, .text)
        try requireCapacityField(poolID, .text)
        self.id = id; self.selectionID = selectionID; self.poolID = poolID
    }
}

public struct CapacityPool: CapacityIdentifiedRecord, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let addressSpace: CapacityBoundAnswer
    public let partition: CapacityBoundAnswer
    public let tenancy: CapacityBoundAnswer
    public let deviceIDs: CapacityBoundAnswer
    public let budget: CapacityBudget
    public let domain: CapacityDomain
    public var observations: [CapacityBoundAnswer] {
        [addressSpace, partition, tenancy, deviceIDs] + budget.observations
    }
    public var description: String { "CapacityPool" }
    public var debugDescription: String { description }

    public init(id: String, addressSpace: CapacityBoundAnswer, partition: CapacityBoundAnswer,
                tenancy: CapacityBoundAnswer, deviceIDs: CapacityBoundAnswer, budget: CapacityBudget) throws {
        try capacityIdentity(id)
        for answer in [addressSpace, partition, tenancy] { try requireCapacityField(answer, .text) }
        try requireCapacityField(deviceIDs, .textSet)
        self.id = id; self.addressSpace = addressSpace; self.partition = partition
        self.tenancy = tenancy; self.deviceIDs = deviceIDs; self.budget = budget
        domain = try .physical(pool: id, addressSpace: addressSpace.text,
                               partition: partition.text, tenancy: tenancy.text)
    }
    func identity(basis: CapacityBasis, qualifications: CapacityQualifications) throws -> [CapacityEvidenceUse]? {
        try capacityMemoryUses(basis: basis, qualifications: qualifications,
            answers: [addressSpace, partition, tenancy], fact: .physicalIdentity, domain: domain)
    }
    /// The pool label cannot distinguish two records naming the same actual physical tuple.
    var physicalTuple: [Data]? {
        guard let address = addressSpace.text, let partition = partition.text,
              let tenancy = tenancy.text else { return nil }
        return [address, partition, tenancy].map { Data($0.utf8) }
    }
}

/// A closed original Answer<runtime binding>; optional roles require an explicit null or identity.
public struct CapacityRuntimeBinding: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let answer: CapacityBoundAnswer
    public let runtime: CapacityRuntime?
    public let buildID: String?
    public let sourceInput: String?
    public let domain: CapacityDomain?
    public var description: String { "CapacityRuntimeBinding" }
    public var debugDescription: String { description }

    public init(answer: CapacityBoundAnswer) throws {
        try requireCapacityField(answer, .runtimeBinding)
        self.answer = answer
        guard answer.provided else {
            runtime = nil; buildID = nil; sourceInput = nil; domain = nil
            return
        }
        guard let value = answer.observation.value,
              let kind = value.value(forExactKey: "kind")?.string,
              let selectedKind = CapacityRuntimeKind(rawValue: kind),
              let id = value.value(forExactKey: "id")?.string,
              let build = value.value(forExactKey: "build")?.string,
              let source = value.value(forExactKey: "source_input")?.string,
              let instance = value.value(forExactKey: "instance")?.string else {
            throw CapacityError.invalidProvidedValue
        }
        try capacityIdentity(source)
        // All provided references are admitted against the answer's own retained basis before a skip.
        guard let input = answer.basis.input(named: source) else { throw CapacityError.danglingReference }
        guard input.kind == .engineBuilds else { throw CapacityError.invalidDomain }
        if selectedKind == .modelEngine && answer.basis.selection(id: id) == nil {
            throw CapacityError.danglingReference
        }
        let runtime = try CapacityRuntime(kind: selectedKind, id: id)
        self.runtime = runtime; buildID = build; sourceInput = source
        domain = try .runtime(runtime, build: build, instance: instance,
            replica: value.value(forExactKey: "replica")?.string,
            rank: value.value(forExactKey: "rank")?.string,
            admission: value.value(forExactKey: "admission")?.string,
            stage: value.value(forExactKey: "stage")?.string)
    }
}

public struct CapacityConsumer: CapacityIdentifiedRecord, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let componentID: CapacityBoundAnswer
    public let operation: CapacityBoundAnswer
    public let deviceIDs: CapacityBoundAnswer
    public let binding: CapacityRuntimeBinding
    public var observations: [CapacityBoundAnswer] { [componentID, operation, deviceIDs, binding.answer] }
    public var description: String { "CapacityConsumer" }
    public var debugDescription: String { description }

    public init(id: String, componentID: CapacityBoundAnswer, operation: CapacityBoundAnswer,
                deviceIDs: CapacityBoundAnswer, binding: CapacityRuntimeBinding) throws {
        try capacityIdentity(id)
        try requireCapacityField(componentID, .text)
        try requireCapacityField(operation, .text)
        try requireCapacityField(deviceIDs, .textSet)
        if deviceIDs.provided && deviceIDs.strings?.isEmpty != false { throw CapacityError.contradictoryInput }
        self.id = id; self.componentID = componentID; self.operation = operation
        self.deviceIDs = deviceIDs; self.binding = binding
    }
}

/// One actual storage extent; sharing and non-overlap need their own scoped qualifications.
public struct CapacityAllocation: CapacityIdentifiedRecord, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let poolID: CapacityBoundAnswer
    public let consumerIDs: CapacityBoundAnswer
    public let extent: CapacityBoundAnswer
    public let nonOverlapping: CapacityBoundAnswer
    public let term: CapacityBoundAnswer
    public let method: CapacityBoundAnswer
    public var observations: [CapacityBoundAnswer] { [poolID, consumerIDs, extent, nonOverlapping, term, method] }
    public var description: String { "CapacityAllocation" }
    public var debugDescription: String { description }

    public init(id: String, poolID: CapacityBoundAnswer, consumerIDs: CapacityBoundAnswer,
                extent: CapacityBoundAnswer, nonOverlapping: CapacityBoundAnswer,
                term: CapacityBoundAnswer, method: CapacityBoundAnswer) throws {
        try capacityIdentity(id)
        for answer in [poolID, extent, term, method] { try requireCapacityField(answer, .text) }
        try requireCapacityField(consumerIDs, .textSet)
        try requireCapacityField(nonOverlapping, .boolean)
        if consumerIDs.provided && consumerIDs.strings?.isEmpty != false { throw CapacityError.contradictoryInput }
        self.id = id; self.poolID = poolID; self.consumerIDs = consumerIDs; self.extent = extent
        self.nonOverlapping = nonOverlapping; self.term = term; self.method = method
    }
}

public struct CapacityAllocationAccess: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let consumerID: String
    public let allowed: CapacityBoundAnswer
    public var description: String { "CapacityAllocationAccess" }
    public var debugDescription: String { description }

    public init(consumerID: String, allowed: CapacityBoundAnswer) throws {
        try capacityIdentity(consumerID); try requireCapacityField(allowed, .boolean)
        self.consumerID = consumerID; self.allowed = allowed
    }
}

public struct CapacityResidency: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let allocationID: String
    public let residency: CapacityBoundAnswer
    /// Only a resident charge needs an upper bound; its lower bound remains optional.
    public let liveBytes: CapacityByteRange
    public let access: [CapacityAllocationAccess]
    public var observations: [CapacityBoundAnswer] {
        [residency] + liveBytes.observations + access.map { $0.allowed }
    }
    public var description: String { "CapacityResidency" }
    public var debugDescription: String { description }

    public init(allocationID: String, residency: CapacityBoundAnswer, liveBytes: CapacityByteRange,
                access: [CapacityAllocationAccess]) throws {
        try capacityIdentity(allocationID); try requireCapacityField(residency, .residency)
        guard access.count <= 1024 else { throw CapacityError.unsupportedNativeLimit }
        guard Set(access.map { Data($0.consumerID.utf8) }).count == access.count else {
            throw CapacityError.duplicateIdentity
        }
        self.allocationID = allocationID; self.residency = residency
        self.liveBytes = liveBytes; self.access = access
    }
}

public struct CapacityScenario: CapacityIdentifiedRecord, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let envelope: CapacityBoundAnswer
    public let componentIDs: CapacityBoundAnswer
    public let rows: [CapacityResidency]
    public let coverage: CapacityCoverage
    private let byAllocation: [Data: CapacityResidency]
    public var description: String { "CapacityScenario" }
    public var debugDescription: String { description }

    public init(id: String, envelope: CapacityBoundAnswer, componentIDs: CapacityBoundAnswer,
                rows: [CapacityResidency], coverage: CapacityCoverage) throws {
        try capacityIdentity(id)
        try requireCapacityField(envelope, .text); try requireCapacityField(componentIDs, .textSet)
        guard rows.count <= 1024 else { throw CapacityError.unsupportedNativeLimit }
        var indexed: [Data: CapacityResidency] = [:]
        for row in rows {
            guard indexed.updateValue(row, forKey: Data(row.allocationID.utf8)) == nil else {
                throw CapacityError.duplicateIdentity
            }
        }
        guard coverage.kind == .chargeTerms, capacityExactOptional(coverage.scenario, id) else {
            throw CapacityError.invalidDomain
        }
        self.id = id; self.envelope = envelope; self.componentIDs = componentIDs
        self.rows = rows; self.coverage = coverage; byAllocation = indexed
    }
    public func row(allocationID: String) -> CapacityResidency? {
        guard allocationID.utf8.count <= 4096 else { return nil }
        return byAllocation[Data(allocationID.utf8)]
    }
}

/// Independently normalized demand for one actual scenario/runtime quota; no equal-rank split is inferred.
public struct CapacityIndependentLimit: CapacityIdentifiedRecord,
    CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let scenarioID: String
    public let consumerID: CapacityBoundAnswer
    public let binding: CapacityRuntimeBinding
    public let applicable: CapacityBoundAnswer
    public let demand: CapacityByteRange
    public let budget: CapacityBudget
    public let accountingDefinition: CapacityBoundAnswer
    public let accountingComplete: CapacityBoundAnswer
    public var observations: [CapacityBoundAnswer] {
        [consumerID, binding.answer, applicable, accountingDefinition, accountingComplete]
            + demand.observations + budget.observations
    }
    public var description: String { "CapacityIndependentLimit" }
    public var debugDescription: String { description }

    public init(id: String, scenarioID: String, consumerID: CapacityBoundAnswer,
                binding: CapacityRuntimeBinding, applicable: CapacityBoundAnswer,
                demand: CapacityByteRange, budget: CapacityBudget,
                accountingDefinition: CapacityBoundAnswer, accountingComplete: CapacityBoundAnswer) throws {
        try capacityIdentity(id); try capacityIdentity(scenarioID)
        try requireCapacityField(consumerID, .text); try requireCapacityField(applicable, .boolean)
        try requireCapacityField(accountingDefinition, .text); try requireCapacityField(accountingComplete, .boolean)
        self.id = id; self.scenarioID = scenarioID; self.consumerID = consumerID; self.binding = binding
        self.applicable = applicable; self.demand = demand; self.budget = budget
        self.accountingDefinition = accountingDefinition; self.accountingComplete = accountingComplete
    }
}

func capacityMemoryUses(basis: CapacityBasis, qualifications: CapacityQualifications,
                        answers: [CapacityBoundAnswer], fact: CapacityFact,
                        domain: CapacityDomain) throws -> [CapacityEvidenceUse]? {
    var result: [CapacityEvidenceUse] = []
    for answer in answers {
        guard let use = try qualifications.use(basis: basis, answer: answer, fact: fact, domain: domain) else {
            return nil
        }
        result.append(use)
    }
    return result
}

func requireCapacityMemoryCoverage(_ coverage: CapacityCoverage, kind: CapacityCoverageKind,
                                   basis: CapacityBasis, scenario: String? = nil) throws {
    guard coverage.kind == kind, contextExact(coverage.owner, basis.buildID),
          capacityExactOptional(coverage.scenario, scenario) else { throw CapacityError.invalidDomain }
}
