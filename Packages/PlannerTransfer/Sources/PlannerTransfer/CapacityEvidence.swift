import Foundation

public enum CapacityFact: String, Sendable {
    case runtimeOperator, capacityMode, localVisibility, role, operation, compatibility, applicability
    case normalization, byteBound, physicalIdentity, allocationIdentity, residency, access
    case inventory, coverage, ceiling, workload
}

public enum CapacityCoverageKind: String, Sendable {
    case servingComponents, roleBindings, supportConditions, hardwareInstances, physicalPoolMap
    case consumers, chargeTerms, independentCeilings, scenarios, transitions, workloadStages
}

public enum CapacityRuntimeKind: String, Sendable {
    case modelEngine = "model_engine"
    case serviceRuntime = "service_runtime"
}

public struct CapacityRuntime: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let kind: CapacityRuntimeKind
    public let id: String
    public var description: String { "CapacityRuntime" }
    public var debugDescription: String { description }
    public init(kind: CapacityRuntimeKind, id: String) throws {
        try capacityIdentity(id)
        self.kind = kind; self.id = id
    }
}

/// Closed, framed domains preserve absence and concrete physical/runtime identities.
public struct CapacityDomain: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    enum Kind: String, Sendable {
        case device, poolScenario, access, ceiling, workload, component, link, condition, role
        case physical, runtime, inventory, allocation
    }
    let kind: Kind
    let completePhysical: Bool
    public let sha256: String
    public var description: String { "CapacityDomain" }
    public var debugDescription: String { description }

    private init(_ kind: Kind, _ fields: [(String, String?)]) throws {
        var parts = [Data(kind.rawValue.utf8)]
        for (name, value) in fields {
            if let value { try capacityIdentity(value) }
            parts += [Data(name.utf8), Data([value == nil ? 0 : 1]), Data((value ?? "").utf8)]
        }
        self.kind = kind
        completePhysical = kind != .physical || fields.allSatisfy { $0.1 != nil }
        sha256 = try capacityKey(parts)
    }

    public static func == (left: Self, right: Self) -> Bool { left.sha256 == right.sha256 }
    public func hash(into hasher: inout Hasher) { hasher.combine(sha256) }

    public static func device(_ id: String) throws -> Self { try Self(.device, [("device", id)]) }
    public static func component(_ selection: String) throws -> Self { try Self(.component, [("selection", selection)]) }
    public static func link(_ id: String) throws -> Self { try Self(.link, [("link", id)]) }
    public static func condition(selection: String, condition: String, kind: String) throws -> Self {
        try Self(.condition, [("selection", selection), ("condition", condition), ("kind", kind)])
    }
    public static func role(selection: String, role: String) throws -> Self {
        try Self(.role, [("selection", selection), ("role", role)])
    }
    public static func physical(pool: String, addressSpace: String?, partition: String?, tenancy: String?) throws -> Self {
        try Self(.physical, [("pool", pool), ("address_space", addressSpace), ("partition", partition), ("tenancy", tenancy)])
    }
    public static func runtime(_ runtime: CapacityRuntime, build: String?, instance: String,
                               replica: String? = nil, rank: String? = nil, admission: String? = nil,
                               stage: String? = nil) throws -> Self {
        try Self(.runtime, [("runtime_kind", runtime.kind.rawValue), ("runtime", runtime.id),
                            ("build", build), ("instance", instance), ("replica", replica),
                            ("rank", rank), ("admission", admission), ("stage", stage)])
    }
    public static func poolScenario(physical: Self, scenario: String) throws -> Self {
        guard physical.kind == .physical else { throw CapacityError.invalidDomain }
        return try Self(.poolScenario, [("physical_domain", physical.sha256), ("scenario", scenario)])
    }
    public static func access(pool: String, allocation: String, scenario: String,
                              consumer: String, runtime: Self) throws -> Self {
        guard runtime.kind == .runtime else { throw CapacityError.invalidDomain }
        return try Self(.access, [("pool", pool), ("allocation", allocation), ("scenario", scenario),
                                  ("consumer", consumer), ("runtime_domain", runtime.sha256)])
    }
    public static func ceiling(limit: String, scenario: String, runtime: Self) throws -> Self {
        guard runtime.kind == .runtime else { throw CapacityError.invalidDomain }
        return try Self(.ceiling, [("limit", limit), ("scenario", scenario), ("runtime_domain", runtime.sha256)])
    }
    public static func workload(runtime: Self, workloadClass: String) throws -> Self {
        guard runtime.kind == .runtime else { throw CapacityError.invalidDomain }
        return try Self(.workload, [("runtime_domain", runtime.sha256), ("class", workloadClass)])
    }
    public static func inventory(kind: CapacityCoverageKind, owner: String, scenario: String? = nil) throws -> Self {
        try Self(.inventory, [("inventory_kind", kind.rawValue), ("owner", owner), ("scenario", scenario)])
    }
    public static func allocation(pool: String?, allocation: String, scenario: String) throws -> Self {
        try Self(.allocation, [("pool", pool), ("allocation", allocation), ("scenario", scenario)])
    }
}

/// One immutable observation bound to the actual named input and complete basis that read it.
public struct CapacityBoundAnswer: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let observation: CapacityAnswer
    public let basis: CapacityBasis
    public let inputName: String
    public let inputSHA256: String
    public var description: String { "CapacityBoundAnswer" }
    public var debugDescription: String { description }
    public var state: CapacityAnswerState { observation.state }
    public var field: CapacityAnswerField { observation.field }
    public var requestedPath: String { observation.requestedPath }
    public var provided: Bool { state == .provided }
    var text: String? { provided ? observation.value?.string : nil }
    var boolean: Bool? { provided ? observation.value?.boolean : nil }
    var byteCount: CapacityByteCount? { provided ? observation.byteCount : nil }
    var strings: [String]? {
        guard provided, field == .textSet, let values = observation.value?.array else { return nil }
        var result: [String] = []
        for value in values {
            guard let text = value.string else { return nil }
            result.append(text)
        }
        return result
    }

    fileprivate init(observation: CapacityAnswer, basis: CapacityBasis, input: CapacityInput) {
        self.observation = observation; self.basis = basis
        inputName = input.name; inputSHA256 = input.sha256
    }
    public func qualificationKey(fact: CapacityFact, domain: CapacityDomain) throws -> CapacityEvidenceKey {
        try CapacityEvidenceKey(answer: self, fact: fact, domain: domain)
    }
}

/// A key cannot be constructed from an invented answer or an unbound digest.
public struct CapacityEvidenceKey: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    let boundBasis: CapacityBasis
    public let basisSHA256: String
    public let inputName: String
    public let inputSHA256: String
    public let requestedPath: String
    public let field: CapacityAnswerField
    public let fact: CapacityFact
    public let domain: CapacityDomain
    public let sha256: String
    public var description: String { "CapacityEvidenceKey" }
    public var debugDescription: String { description }

    fileprivate init(answer: CapacityBoundAnswer, fact: CapacityFact, domain: CapacityDomain) throws {
        guard let input = answer.basis.input(named: answer.inputName), input.kind == .answers else {
            throw CapacityError.invalidDomain
        }
        try capacityCheckDigest(answer.inputSHA256, actual: input.sha256)
        boundBasis = answer.basis; basisSHA256 = answer.basis.sha256
        inputName = answer.inputName; inputSHA256 = input.sha256
        requestedPath = answer.requestedPath; field = answer.field; self.fact = fact; self.domain = domain
        sha256 = try capacityKey([CapacityBasis.profile, basisSHA256, inputName, inputSHA256,
                                  requestedPath, field.rawValue, fact.rawValue, domain.sha256].map { Data($0.utf8) })
    }
    public static func == (left: Self, right: Self) -> Bool { left.sha256 == right.sha256 }
    public func hash(into hasher: inout Hasher) { hasher.combine(sha256) }
}

public enum CapacityEligibility: String, Sendable { case qualified, ineligible, unknown }

/// An explicit normalized source-policy assessment, not authentication by a content hash.
public struct CapacityQualification: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let key: CapacityEvidenceKey
    public let eligibility: CapacityEligibility
    public let evidenceInputName: String
    public let evidenceSHA256: String
    public let conflictRankResolved: Bool?
    public let checkedOnly: Bool
    public var description: String { "CapacityQualification" }
    public var debugDescription: String { description }

    public init(key: CapacityEvidenceKey, eligibility: CapacityEligibility, evidenceInputName: String,
                evidenceSHA256: String, conflictRankResolved: Bool?, checkedOnly: Bool) throws {
        try capacityIdentity(evidenceInputName)
        guard let input = key.boundBasis.input(named: evidenceInputName),
              input.kind == .qualification || input.kind == .sourcePolicy else {
            throw CapacityError.invalidDomain
        }
        // Every supplied record is checked now, including qualifications never consumed later.
        try capacityCheckDigest(evidenceSHA256, actual: input.sha256)
        self.key = key; self.eligibility = eligibility; self.evidenceInputName = evidenceInputName
        self.evidenceSHA256 = evidenceSHA256; self.conflictRankResolved = conflictRankResolved
        self.checkedOnly = checkedOnly
    }
}

public struct CapacityEvidenceUse: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let answer: CapacityBoundAnswer
    public let qualification: CapacityQualification
    public var checkedOnly: Bool { qualification.checkedOnly }
    public var description: String { "CapacityEvidenceUse" }
    public var debugDescription: String { description }
    fileprivate init(answer: CapacityBoundAnswer, qualification: CapacityQualification) {
        self.answer = answer; self.qualification = qualification
    }
}

/// Changed claims, conflicts and attribution produce a distinct dependent-result identity.
public struct CapacityQualifications: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let maximumEntries = 8192
    private let records: [String: CapacityQualification]
    public let sha256: String
    public var description: String { "CapacityQualifications" }
    public var debugDescription: String { description }

    public init(_ qualifications: [CapacityQualification]) throws {
        guard qualifications.count <= Self.maximumEntries else { throw CapacityError.unsupportedNativeLimit }
        var records: [String: CapacityQualification] = [:]
        for item in qualifications {
            guard records.updateValue(item, forKey: item.key.sha256) == nil else {
                throw CapacityError.duplicateIdentity
            }
        }
        var parts: [Data] = []
        for key in records.keys.sorted() {
            guard let item = records[key] else { throw CapacityError.invalidIdentity }
            parts += [Data(key.utf8), Data(item.eligibility.rawValue.utf8), Data(item.evidenceInputName.utf8),
                      Data(item.evidenceSHA256.utf8),
                      Data([item.conflictRankResolved.map { $0 ? 2 : 1 } ?? 0]),
                      Data([item.checkedOnly ? 1 : 0])]
        }
        self.records = records; sha256 = try capacityKey(parts)
    }

    public func eligibility(basis: CapacityBasis, answer: CapacityBoundAnswer, fact: CapacityFact,
                            domain: CapacityDomain) throws -> CapacityEligibility {
        guard basis.sha256 == answer.basis.sha256 else { return .unknown }
        guard fact != .physicalIdentity || domain.completePhysical else { return .unknown }
        let key = try answer.qualificationKey(fact: fact, domain: domain)
        guard let record = records[key.sha256], record.conflictRankResolved == true else { return .unknown }
        return record.eligibility
    }

    public func use(basis: CapacityBasis, answer: CapacityBoundAnswer, fact: CapacityFact,
                    domain: CapacityDomain) throws -> CapacityEvidenceUse? {
        guard answer.provided,
              try eligibility(basis: basis, answer: answer, fact: fact, domain: domain) == .qualified else { return nil }
        let key = try answer.qualificationKey(fact: fact, domain: domain)
        guard let record = records[key.sha256] else { throw CapacityError.invalidIdentity }
        return CapacityEvidenceUse(answer: answer, qualification: record)
    }
}

/// Reads the named CD1-0.2 original once and retains its original attribution and byte binding.
public struct CapacityAnswers: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let basis: CapacityBasis
    public let inputName: String
    public var originalBytes: Data { index.originalBytes }
    public var originalSHA256: String { index.originalSHA256 }
    private let input: CapacityInput
    private let index: CapacityAnswerIndex
    public var description: String { "CapacityAnswers" }
    public var debugDescription: String { description }

    public init(basis: CapacityBasis, inputName: String) throws {
        guard let input = basis.input(named: inputName), input.kind == .answers else {
            throw CapacityError.invalidDomain
        }
        self.basis = basis; self.inputName = inputName; self.input = input
        index = try CapacityAnswerIndex(originalBytes: input.originalBytes, declaredSHA256: input.sha256)
    }

    public func read(path: String, as field: CapacityAnswerField) throws -> CapacityBoundAnswer {
        CapacityBoundAnswer(observation: try index.read(path: path, as: field), basis: basis, input: input)
    }
}

func requireCapacityField(_ answer: CapacityBoundAnswer, _ field: CapacityAnswerField) throws {
    guard answer.field == field else { throw CapacityError.invalidProvidedValue }
}
