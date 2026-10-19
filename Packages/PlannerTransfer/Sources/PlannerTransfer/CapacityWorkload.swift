import Foundation

/// Exact count arithmetic. Admission still requires an original positive integer token, not a ByteCount string.
public struct CapacityCount: Sendable, Hashable, Comparable, CustomStringConvertible, CustomDebugStringConvertible {
    private let magnitude: CapacityByteCount
    public var decimal: String { magnitude.decimal }
    public static let zero = Self(magnitude: .zero)
    public var description: String { "CapacityCount" }
    public var debugDescription: String { description }

    public init(decimal: String) throws { magnitude = try CapacityByteCount(decimal: decimal) }
    private init(magnitude: CapacityByteCount) { self.magnitude = magnitude }
    public static func < (left: Self, right: Self) -> Bool { left.magnitude < right.magnitude }
    public func adding(_ other: Self) throws -> Self { try Self(magnitude: magnitude.adding(other.magnitude)) }

    /// Base-1e9 limbs keep every intermediate below 1e18 without floating point or fixed-width count coercion.
    public func multiplied(by other: Self) throws -> Self {
        if decimal == "0" || other.decimal == "0" { return .zero }
        guard decimal.utf8.count + other.decimal.utf8.count - 1 <= CapacityByteCount.maximumDigits else {
            throw CapacityError.unsupportedNativeLimit
        }
        let left = Self.limbs(decimal), right = Self.limbs(other.decimal)
        let base: UInt64 = 1_000_000_000
        var result = [UInt64](repeating: 0, count: left.count + right.count)
        for i in left.indices {
            var carry: UInt64 = 0
            for j in right.indices {
                let value = result[i + j] + left[i] * right[j] + carry
                result[i + j] = value % base
                carry = value / base
            }
            result[i + right.count] = carry
        }
        while result.count > 1 && result.last == 0 { result.removeLast() }
        var rendered = String(result.removeLast())
        for limb in result.reversed() {
            let text = String(limb)
            rendered += String(repeating: "0", count: 9 - text.utf8.count) + text
        }
        return try Self(decimal: rendered)
    }
    private static func limbs(_ decimal: String) -> [UInt64] {
        let bytes = Array(decimal.utf8)
        var end = bytes.count, result: [UInt64] = []
        while end > 0 {
            let start = max(0, end - 9)
            var value: UInt64 = 0
            for digit in bytes[start..<end] { value = value * 10 + UInt64(digit - 48) }
            result.append(value); end = start
        }
        return result
    }
}

public struct CapacitySequenceClass: CapacityIdentifiedRecord, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let requests: CapacityBoundAnswer
    public let sequencesPerRequest: CapacityBoundAnswer
    public let sameScopeAllocation: CapacityBoundAnswer
    public var observations: [CapacityBoundAnswer] { [requests, sequencesPerRequest, sameScopeAllocation] }
    public var description: String { "CapacitySequenceClass" }
    public var debugDescription: String { description }

    public init(id: String, requests: CapacityBoundAnswer, sequencesPerRequest: CapacityBoundAnswer,
                sameScopeAllocation: CapacityBoundAnswer) throws {
        try capacityIdentity(id)
        try requireCapacityField(requests, .positiveInteger)
        try requireCapacityField(sequencesPerRequest, .positiveInteger)
        try requireCapacityField(sameScopeAllocation, .boolean)
        self.id = id; self.requests = requests; self.sequencesPerRequest = sequencesPerRequest
        self.sameScopeAllocation = sameScopeAllocation
    }
}

public struct CapacitySequenceAdmission: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let binding: CapacityRuntimeBinding
    public let limit: CapacityBoundAnswer
    public let units: CapacityBoundAnswer
    public let coversAllResidentKV: CapacityBoundAnswer
    public var observations: [CapacityBoundAnswer] { [binding.answer, limit, units, coversAllResidentKV] }
    public var description: String { "CapacitySequenceAdmission" }
    public var debugDescription: String { description }

    public init(binding: CapacityRuntimeBinding, limit: CapacityBoundAnswer, units: CapacityBoundAnswer,
                coversAllResidentKV: CapacityBoundAnswer) throws {
        try requireCapacityField(limit, .positiveInteger)
        try requireCapacityField(units, .admissionUnit)
        try requireCapacityField(coversAllResidentKV, .boolean)
        self.binding = binding; self.limit = limit; self.units = units
        self.coversAllResidentKV = coversAllResidentKV
    }
}

public struct CapacitySequenceResult: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let result: CapacityResult
    public let expandedDemand: CapacityCount?
    public let residentSequences: CapacityCount?
    public let admissionKnown: Bool
    public let conservativeFallback: Bool
    public var description: String { "CapacitySequenceResult" }
    public var debugDescription: String { description }
}

/// R*E demand belongs to one actual engine/build/instance/replica/admission/stage domain.
/// This does not infer token geometry, KV bytes, stage maxima or runtime support from a request cap.
public struct CapacityWorkload: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let basis: CapacityBasis
    private let graph: CapacityGraph
    private let servingRequirements: CapacityServingRequirements
    private let artifactFacts: [CapacityArtifactFacts]
    public let binding: CapacityRuntimeBinding
    public let operation: CapacityBoundAnswer
    public let applicable: CapacityBoundAnswer
    public let classes: CapacityRecords<CapacitySequenceClass>
    public let admission: CapacitySequenceAdmission
    public let expandedFallbackCoversAllResident: CapacityBoundAnswer
    public var description: String { "CapacityWorkload" }
    public var debugDescription: String { description }

    public init(basis: CapacityBasis, graph: CapacityGraph, servingRequirements: CapacityServingRequirements,
                artifactFacts: [CapacityArtifactFacts], binding: CapacityRuntimeBinding,
                operation: CapacityBoundAnswer, applicable: CapacityBoundAnswer,
                classes: CapacityRecords<CapacitySequenceClass>, admission: CapacitySequenceAdmission,
                expandedFallbackCoversAllResident: CapacityBoundAnswer) throws {
        _ = try admitCapacityArtifactFacts(basis: basis, facts: artifactFacts)
        guard graph.basis.sha256 == basis.sha256 else { throw CapacityError.contradictoryInput }
        guard basis.selection(id: servingRequirements.selectionID) != nil else { throw CapacityError.danglingReference }
        try requireCapacityField(operation, .text); try requireCapacityField(applicable, .boolean)
        try requireCapacityField(expandedFallbackCoversAllResident, .boolean)
        try requireCapacityMemoryCoverage(classes.coverage, kind: .workloadStages,
                                          basis: basis, scenario: basis.operation)
        for runtime in [binding.runtime, admission.binding.runtime].compactMap({ $0 }) {
            if runtime.kind == .modelEngine && basis.selection(id: runtime.id) == nil {
                throw CapacityError.contradictoryInput
            }
        }
        self.basis = basis; self.graph = graph; self.servingRequirements = servingRequirements
        self.artifactFacts = artifactFacts; self.binding = binding; self.operation = operation
        self.applicable = applicable; self.classes = classes; self.admission = admission
        self.expandedFallbackCoversAllResident = expandedFallbackCoversAllResident
    }

    public func evaluate(current: CapacityBasis, qualifications q: CapacityQualifications) throws -> CapacitySequenceResult {
        let domain = try binding.domain ?? .component(servingRequirements.selectionID)
        var observations = [binding.answer, operation, applicable, expandedFallbackCoversAllResident,
                            classes.ids, classes.coverage.claim]
        observations += classes.records.flatMap { $0.observations } + admission.observations
        var evidence: [CapacityEvidenceUse] = [], prerequisites: [CapacityCheck] = []
        func result(_ outcome: CapacityOutcome, _ reason: CapacityReason, expanded: CapacityCount? = nil,
                    resident: CapacityCount? = nil, known: Bool = false, fallback: Bool = false) -> CapacitySequenceResult {
            let check = CapacityCheck(rule: .workload, domain: domain, outcome: outcome, reason: reason,
                                      observations: observations, evidence: evidence)
            return CapacitySequenceResult(result: CapacityResult(basis: current, qualifications: q,
                checks: prerequisites + [check], assumptions: fallback ? ["qualified_expanded_demand_fallback"] : []),
                expandedDemand: expanded, residentSequences: resident, admissionKnown: known, conservativeFallback: fallback)
        }
        guard current.sha256 == basis.sha256 else { return result(.unknown, .changedBasis) }
        guard let applicability = try q.use(basis: current, answer: applicable, fact: .applicability, domain: domain) else {
            return result(.unknown, .missingOrIneligible)
        }
        evidence.append(applicability)
        if applicable.boolean == false { return result(.skipped, .inapplicable) }
        let scope = try capacityMemoryUses(basis: current, qualifications: q,
                                          answers: [binding.answer, operation], fact: .workload, domain: domain)
        let source = binding.sourceInput.flatMap { current.input(named: $0) }
        let serving = try graph.serving(current: current, qualifications: q,
                                       requirements: servingRequirements, artifactFacts: artifactFacts)
        prerequisites += serving.checks
        let selectedRuntime = binding.runtime.flatMap { $0.kind == .modelEngine ? basis.selection(id: $0.id) : nil }
        if let scope, capacityExactOptional(operation.text, basis.operation), let selectedRuntime,
           selectedRuntime.kind != "inference_engine" || !selectedRuntime.enabled {
            prerequisites.append(CapacityCheck(rule: .binding, domain: domain, outcome: .fail,
                reason: .wrongKindOrDisabled, observations: [binding.answer, operation], evidence: scope))
        }
        let exactEngine = binding.runtime?.kind == .modelEngine && serving.engine?.check.outcome == .pass &&
            serving.engine?.resolved.count == 1 &&
            capacityExactOptional(serving.engine?.resolved.first?.id, binding.runtime?.id)
        guard let scope, binding.domain != nil, capacityExactOptional(operation.text, basis.operation),
              source?.kind == .engineBuilds, exactEngine,
              !serving.checks.contains(where: { $0.outcome == .fail || $0.outcome == .unknown }) else {
            return result(.unknown, .missingOrIneligible)
        }
        evidence += scope + serving.checks.flatMap { $0.evidence }
        let inventory = try classes.check(basis: current, qualifications: q)
        guard inventory.outcome == .pass, !classes.records.isEmpty else { return result(.unknown, .incompleteCoverage) }
        evidence += inventory.evidence
        var expanded = CapacityCount.zero
        for item in classes.records {
            let classDomain = try CapacityDomain.workload(runtime: domain, workloadClass: item.id)
            guard let uses = try capacityMemoryUses(basis: current, qualifications: q,
                    answers: item.observations, fact: .workload, domain: classDomain),
                  item.sameScopeAllocation.boolean == true else { return result(.unknown, .missingOrIneligible) }
            evidence += uses
            let requests = try count(item.requests), sequences = try count(item.sequencesPerRequest)
            expanded = try expanded.adding(requests.multiplied(by: sequences))
        }
        let admissionUses = try capacityMemoryUses(basis: current, qualifications: q,
            answers: admission.observations, fact: .workload, domain: domain)
        let knownAdmission = admissionUses != nil && admission.binding.domain == binding.domain &&
            admission.units.text == "sequences" && admission.coversAllResidentKV.boolean == true
        if knownAdmission, let admissionUses {
            evidence += admissionUses
            let limit = try count(admission.limit)
            return result(.pass, .qualified, expanded: expanded, resident: min(expanded, limit), known: true)
        }
        // A wrong-domain, request-unit or per-step cap cannot reduce the resident demand.
        if let fallback = try q.use(basis: current, answer: expandedFallbackCoversAllResident,
                                   fact: .workload, domain: domain),
           expandedFallbackCoversAllResident.boolean == true {
            evidence.append(fallback)
            return result(.unknown, .unknownAdmission, expanded: expanded, resident: expanded, fallback: true)
        }
        return result(.unknown, .unknownAdmission, expanded: expanded)
    }

    private func count(_ answer: CapacityBoundAnswer) throws -> CapacityCount {
        guard answer.provided, answer.field == .positiveInteger,
              answer.observation.value?.isIntegerToken == true,
              let token = answer.observation.value?.originalNumberToken else { throw CapacityError.invalidProvidedValue }
        return try CapacityCount(decimal: token)
    }
}
