import Foundation

public enum CapacityOutcome: String, Sendable { case pass, fail, unknown, skipped }
public enum CapacityRule: String, Sendable {
    case deployment, localHardware, remoteCapacity, binding, adapterEngine, physicalMap
    case memoryPool, independentCeiling, runtimeAccess, coverage, workload
}
public enum CapacityReason: String, Sendable {
    case qualified, inapplicable, missingOrIneligible, changedBasis, incompleteCoverage
    case requiredBindingAbsent, ambiguousBinding, wrongKindOrDisabled, missingCatalogVersion
    case baseArtifactMismatch, bindingCycle, unknownResponsibility, unknownCapacity
    case overUpperBoundBudget, unknownPhysicalIdentity, unknownAccess, unknownResidency
    case missingAllocation, unknownAdmission
}

/// One scoped result retains the observations and exact evidence actually used by that check.
public struct CapacityCheck: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let rule: CapacityRule
    public let domain: CapacityDomain
    public let outcome: CapacityOutcome
    public let reason: CapacityReason
    public let observations: [CapacityBoundAnswer]
    public let evidence: [CapacityEvidenceUse]
    public let chargeIDs: [String]
    public let demandUpper: CapacityByteCount?
    public let capacityLower: CapacityByteCount?
    public let reserveUpper: CapacityByteCount?
    public let mayNotFit: Bool
    public var checkedOnly: Bool { evidence.contains { $0.checkedOnly } }
    public let severity = "error"
    public let onUnknown = "review"
    public var description: String { "CapacityCheck" }
    public var debugDescription: String { description }

    init(rule: CapacityRule, domain: CapacityDomain, outcome: CapacityOutcome, reason: CapacityReason,
         observations: [CapacityBoundAnswer] = [], evidence: [CapacityEvidenceUse] = [],
         chargeIDs: [String] = [], demandUpper: CapacityByteCount? = nil,
         capacityLower: CapacityByteCount? = nil, reserveUpper: CapacityByteCount? = nil,
         mayNotFit: Bool = false) {
        self.rule = rule; self.domain = domain; self.outcome = outcome; self.reason = reason
        self.observations = observations; self.evidence = evidence; self.chargeIDs = chargeIDs
        self.demandUpper = demandUpper; self.capacityLower = capacityLower; self.reserveUpper = reserveUpper
        self.mayNotFit = mayNotFit
    }
}

/// Arithmetic is conditional capacity evidence; it supplies no support, runtime or measured-fit verdict.
public struct CapacityResult: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let basisSHA256: String
    public let qualificationsSHA256: String
    public let checks: [CapacityCheck]
    public let assumptions: [String]
    public let outcome: CapacityOutcome
    public var conditionalCapacity: Bool {
        checks.contains { $0.rule == .memoryPool || $0.rule == .independentCeiling }
    }
    public var checkedOnly: Bool { checks.contains { $0.checkedOnly } }
    public let severity = "error"
    public let onUnknown = "review"
    public var description: String { "CapacityResult" }
    public var debugDescription: String { description }

    init(basis: CapacityBasis, qualifications: CapacityQualifications, checks: [CapacityCheck],
         assumptions: [String] = []) {
        basisSHA256 = basis.sha256; qualificationsSHA256 = qualifications.sha256
        self.checks = checks; self.assumptions = assumptions
        outcome = aggregateCapacity(checks.filter { $0.rule != .coverage || $0.outcome != .pass }.map { $0.outcome })
    }
}

func aggregateCapacity(_ outcomes: [CapacityOutcome]) -> CapacityOutcome {
    if outcomes.contains(.fail) { return .fail }
    if outcomes.isEmpty || outcomes.contains(.unknown) { return .unknown }
    if outcomes.contains(.pass) { return .pass }
    return .skipped
}

/// A separate qualified completeness claim; a nonempty array cannot stand in for coverage.
public struct CapacityCoverage: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let kind: CapacityCoverageKind
    public let owner: String
    public let scenario: String?
    public let claim: CapacityBoundAnswer
    public let domain: CapacityDomain
    public var description: String { "CapacityCoverage" }
    public var debugDescription: String { description }

    public init(kind: CapacityCoverageKind, owner: String, scenario: String? = nil,
                claim: CapacityBoundAnswer) throws {
        try requireCapacityField(claim, .boolean)
        self.kind = kind; self.owner = owner; self.scenario = scenario; self.claim = claim
        domain = try .inventory(kind: kind, owner: owner, scenario: scenario)
    }

    func use(basis: CapacityBasis, qualifications: CapacityQualifications) throws -> CapacityEvidenceUse? {
        guard claim.boolean == true else { return nil }
        return try qualifications.use(basis: basis, answer: claim, fact: .coverage, domain: domain)
    }
    func check(basis: CapacityBasis, qualifications: CapacityQualifications) throws -> CapacityCheck {
        let evidence = try use(basis: basis, qualifications: qualifications)
        return CapacityCheck(rule: .coverage, domain: domain, outcome: evidence == nil ? .unknown : .pass,
            reason: evidence == nil ? .incompleteCoverage : .qualified,
            observations: [claim], evidence: evidence.map { [$0] } ?? [])
    }
}

/// Exact already-normalized ByteCount bounds plus their original unit/method/rounding record.
public struct CapacityByteRange: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let lower: CapacityBoundAnswer?
    public let upper: CapacityBoundAnswer?
    public let trace: CapacityBoundAnswer
    public var observations: [CapacityBoundAnswer] { [lower, upper, trace].compactMap { $0 } }
    public var description: String { "CapacityByteRange" }
    public var debugDescription: String { description }

    public init(lower: CapacityBoundAnswer?, upper: CapacityBoundAnswer?, trace: CapacityBoundAnswer) throws {
        if let lower { try requireCapacityField(lower, .byteCount) }
        if let upper { try requireCapacityField(upper, .byteCount) }
        try requireCapacityField(trace, .quantityTrace)
        if let lo = lower?.byteCount, let hi = upper?.byteCount, lo > hi {
            throw CapacityError.contradictoryInput
        }
        self.lower = lower; self.upper = upper; self.trace = trace
    }
    func qualifiedLower(basis: CapacityBasis, qualifications: CapacityQualifications,
                        domain: CapacityDomain) throws -> CapacityQualifiedBound? {
        try qualified(lower, basis: basis, qualifications: qualifications, domain: domain)
    }
    func qualifiedUpper(basis: CapacityBasis, qualifications: CapacityQualifications,
                        domain: CapacityDomain) throws -> CapacityQualifiedBound? {
        try qualified(upper, basis: basis, qualifications: qualifications, domain: domain)
    }
    private func qualified(_ answer: CapacityBoundAnswer?, basis: CapacityBasis,
                           qualifications: CapacityQualifications, domain: CapacityDomain) throws -> CapacityQualifiedBound? {
        guard let answer,
              let bound = try qualifications.use(basis: basis, answer: answer, fact: .byteBound, domain: domain),
              let normalization = try qualifications.use(basis: basis, answer: trace, fact: .normalization, domain: domain),
              let value = answer.byteCount else { return nil }
        return CapacityQualifiedBound(value: value, evidence: [bound, normalization])
    }
}

struct CapacityQualifiedBound: Sendable {
    let value: CapacityByteCount
    let evidence: [CapacityEvidenceUse]
}

enum CapacityReserveBasis: String, Sendable { case beforeReserve = "before_reserve", afterReserve = "after_reserve" }

/// An original qualified reserve interpretation applies once to one pool or independent quota.
public struct CapacityBudget: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let capacity: CapacityByteRange
    public let reserve: CapacityByteRange
    public let interpretation: CapacityBoundAnswer
    public let reservationTrace: CapacityBoundAnswer
    public var observations: [CapacityBoundAnswer] {
        capacity.observations + reserve.observations + [interpretation, reservationTrace]
    }
    public var description: String { "CapacityBudget" }
    public var debugDescription: String { description }

    public init(capacity: CapacityByteRange, reserve: CapacityByteRange,
                interpretation: CapacityBoundAnswer, reservationTrace: CapacityBoundAnswer) throws {
        try requireCapacityField(interpretation, .reserveBasis)
        try requireCapacityField(reservationTrace, .text)
        self.capacity = capacity; self.reserve = reserve
        self.interpretation = interpretation; self.reservationTrace = reservationTrace
    }
    func qualified(basis: CapacityBasis, qualifications: CapacityQualifications,
                   domain: CapacityDomain) throws -> CapacityQualifiedBudget? {
        guard let capacity = try capacity.qualifiedLower(basis: basis, qualifications: qualifications, domain: domain),
              let reserve = try reserve.qualifiedUpper(basis: basis, qualifications: qualifications, domain: domain),
              let reservation = try qualifications.use(basis: basis, answer: reservationTrace, fact: .normalization, domain: domain),
              let interpretationUse = try qualifications.use(basis: basis, answer: interpretation, fact: .normalization, domain: domain),
              let token = interpretation.text, let selected = CapacityReserveBasis(rawValue: token) else { return nil }
        return CapacityQualifiedBudget(capacityLower: capacity.value, reserveUpper: reserve.value,
            interpretation: selected, evidence: capacity.evidence + reserve.evidence + [reservation, interpretationUse])
    }
}

struct CapacityQualifiedBudget: Sendable {
    let capacityLower: CapacityByteCount
    let reserveUpper: CapacityByteCount
    let interpretation: CapacityReserveBasis
    let evidence: [CapacityEvidenceUse]
    func fits(_ demandUpper: CapacityByteCount) throws -> Bool {
        try demandUpper.adding(interpretation == .beforeReserve ? reserveUpper : .zero) <= capacityLower
    }
}
