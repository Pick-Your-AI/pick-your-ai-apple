import Foundation

public enum CapacityMode: String, Sendable { case selfHosted, managed, api, hybrid, unknown }
public enum CapacityApplicability: String, Sendable { case applicable, inapplicable, unknown }
public enum CapacityConditionKind: String, Sendable { case localHardware, serviceSupport, artifactSupport }

public struct CapacityDeploymentRow: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let selectionID: String
    public let runtimeOperator: CapacityBoundAnswer
    public let capacityMode: CapacityBoundAnswer
    public let exposedHardware: CapacityBoundAnswer
    public var description: String { "CapacityDeploymentRow" }
    public var debugDescription: String { description }
    public init(selectionID: String, runtimeOperator: CapacityBoundAnswer,
                capacityMode: CapacityBoundAnswer, exposedHardware: CapacityBoundAnswer) throws {
        try capacityIdentity(selectionID)
        try requireCapacityField(runtimeOperator, .runtimeOperator)
        try requireCapacityField(capacityMode, .capacityMode); try requireCapacityField(exposedHardware, .boolean)
        self.selectionID = selectionID; self.runtimeOperator = runtimeOperator
        self.capacityMode = capacityMode; self.exposedHardware = exposedHardware
    }
}

/// An operation-specific normalized technical condition; this consumer performs no rights assessment.
public struct CapacitySupportCondition: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let selectionID: String
    public let conditionID: String
    public let kind: CapacityConditionKind
    public let applicable: CapacityBoundAnswer
    public let satisfied: CapacityBoundAnswer
    public let domain: CapacityDomain
    public var description: String { "CapacitySupportCondition" }
    public var debugDescription: String { description }
    public init(selectionID: String, conditionID: String, kind: CapacityConditionKind,
                applicable: CapacityBoundAnswer, satisfied: CapacityBoundAnswer) throws {
        try capacityIdentity(selectionID); try capacityIdentity(conditionID)
        try requireCapacityField(applicable, .boolean); try requireCapacityField(satisfied, .boolean)
        self.selectionID = selectionID; self.conditionID = conditionID; self.kind = kind
        self.applicable = applicable; self.satisfied = satisfied
        domain = try .condition(selection: selectionID, condition: conditionID, kind: kind.rawValue)
    }
    func check(basis: CapacityBasis, qualifications: CapacityQualifications) throws -> CapacityCheck {
        let applies = try qualifications.use(basis: basis, answer: applicable, fact: .applicability, domain: domain)
        let result = try qualifications.use(basis: basis, answer: satisfied, fact: .compatibility, domain: domain)
        let outcome: CapacityOutcome
        if applies == nil { outcome = .unknown }
        else if applicable.boolean == false { outcome = .skipped }
        else if result == nil { outcome = .unknown }
        else { outcome = satisfied.boolean == true ? .pass : .fail }
        let evidence = [applies].compactMap { $0 }
            + (applies != nil && applicable.boolean == true ? [result].compactMap { $0 } : [])
        return CapacityCheck(rule: kind == .localHardware ? .localHardware : .runtimeAccess,
            domain: domain, outcome: outcome,
            reason: outcome == .unknown ? .missingOrIneligible : outcome == .skipped ? .inapplicable : .qualified,
            observations: [applicable, satisfied], evidence: evidence)
    }
}

public struct CapacityConditionInventory: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let ids: CapacityBoundAnswer
    public let coverage: CapacityCoverage
    public var description: String { "CapacityConditionInventory" }
    public var debugDescription: String { description }
    public init(ids: CapacityBoundAnswer, coverage: CapacityCoverage) throws {
        try requireCapacityField(ids, .textSet); self.ids = ids; self.coverage = coverage
    }
    func check(basis: CapacityBasis, qualifications: CapacityQualifications) throws -> CapacityCheck {
        let inventory = try qualifications.use(basis: basis, answer: ids, fact: .inventory, domain: coverage.domain)
        let complete = try coverage.use(basis: basis, qualifications: qualifications)
        let known = inventory != nil && complete != nil
        return CapacityCheck(rule: .coverage, domain: coverage.domain, outcome: known ? .pass : .unknown,
            reason: known ? .qualified : .incompleteCoverage, observations: [ids, coverage.claim],
            evidence: [inventory, complete].compactMap { $0 })
    }
}

public struct CapacityComponentMode: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let selectionID: String
    public let effectiveSelectionID: String?
    public let mode: CapacityMode
    public let localApplicability: CapacityApplicability
    public let serving: CapacityServingBinding?
    public let checks: [CapacityCheck]
    public let applicabilityEvidence: [CapacityEvidenceUse]
    public var description: String { "CapacityComponentMode" }
    public var debugDescription: String { description }
}

public struct CapacityDeploymentResult: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let result: CapacityResult
    public let components: [CapacityComponentMode]
    public let mode: CapacityMode
    public var description: String { "CapacityDeploymentResult" }
    public var debugDescription: String { description }
    init(result: CapacityResult, components: [CapacityComponentMode], servingMembershipKnown: Bool) {
        self.result = result; self.components = components
        if components.isEmpty || components.contains(where: { $0.mode == .unknown }) || !servingMembershipKnown {
            mode = .unknown
        } else if let first = components.first, components.allSatisfy({ $0.mode == first.mode }) {
            mode = first.mode
        } else { mode = .hybrid }
    }
}

/// Per-component responsibility and predicates never use a Build-wide mode to suppress local checks.
public struct CapacityDeployment: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let basis: CapacityBasis
    private let graph: CapacityGraph
    private let rows: [Data: CapacityDeploymentRow]
    private let artifactFacts: [CapacityArtifactFacts]
    private let conditions: [CapacitySupportCondition]
    private let conditionCoverage: [Data: CapacityConditionInventory]
    private let servingCoverage: CapacityCoverage
    private let requirements: [Data: CapacityServingRequirements]
    public var description: String { "CapacityDeployment" }
    public var debugDescription: String { description }

    public init(basis: CapacityBasis, graph: CapacityGraph, rows: [CapacityDeploymentRow],
                artifactFacts: [CapacityArtifactFacts], conditions: [CapacitySupportCondition],
                conditionCoverage: [CapacityConditionInventory], servingCoverage: CapacityCoverage,
                requirements: [CapacityServingRequirements]) throws {
        _ = try admitCapacityArtifactFacts(basis: basis, facts: artifactFacts)
        guard graph.basis.sha256 == basis.sha256 else { throw CapacityError.contradictoryInput }
        guard rows.count <= CapacityBasis.maximumSelections, conditions.count <= 2048,
              conditionCoverage.count <= CapacityBasis.maximumSelections,
              requirements.count <= CapacityBasis.maximumSelections else { throw CapacityError.unsupportedNativeLimit }
        guard servingCoverage.kind == .servingComponents, contextExact(servingCoverage.owner, basis.buildID),
              capacityExactOptional(servingCoverage.scenario, basis.operation) else { throw CapacityError.invalidDomain }
        guard Set(rows.map { Data($0.selectionID.utf8) }).count == rows.count,
              Set(conditions.map { [Data($0.selectionID.utf8), Data($0.conditionID.utf8)] }).count == conditions.count,
              Set(conditionCoverage.map { Data($0.coverage.owner.utf8) }).count == conditionCoverage.count,
              Set(requirements.map { Data($0.selectionID.utf8) }).count == requirements.count else {
            throw CapacityError.duplicateIdentity
        }
        let references = rows.map { $0.selectionID } + conditions.map { $0.selectionID }
            + artifactFacts.map { $0.selectionID } + conditionCoverage.map { $0.coverage.owner }
            + requirements.map { $0.selectionID }
        guard references.allSatisfy({ basis.selection(id: $0) != nil }) else { throw CapacityError.danglingReference }
        for inventory in conditionCoverage {
            let coverage = inventory.coverage
            guard coverage.kind == .supportConditions, capacityExactOptional(coverage.scenario, basis.operation) else {
                throw CapacityError.invalidDomain
            }
            let supplied = Set(conditions.filter { contextExact($0.selectionID, coverage.owner) }.map { Data($0.conditionID.utf8) })
            if let ids = inventory.ids.strings, Set(ids.map { Data($0.utf8) }) != supplied {
                throw CapacityError.contradictoryInput
            }
        }
        self.basis = basis; self.graph = graph; self.artifactFacts = artifactFacts; self.conditions = conditions
        self.servingCoverage = servingCoverage
        self.rows = Dictionary(uniqueKeysWithValues: rows.map { (Data($0.selectionID.utf8), $0) })
        self.conditionCoverage = Dictionary(uniqueKeysWithValues: conditionCoverage.map { (Data($0.coverage.owner.utf8), $0) })
        self.requirements = Dictionary(uniqueKeysWithValues: requirements.map { (Data($0.selectionID.utf8), $0) })
    }

    public func evaluate(current: CapacityBasis, qualifications: CapacityQualifications) throws -> CapacityDeploymentResult {
        var components: [CapacityComponentMode] = []
        var checks = [try servingCoverage.check(basis: current, qualifications: qualifications)]
        let servingKinds: Set<String> = ["model", "embedding_model", "vector_database", "fine_tuned_model"]
        for selection in basis.selections where selection.enabled && servingKinds.contains(selection.kind) {
            let serving: CapacityServingBinding?
            if let required = requirements[Data(selection.id.utf8)] {
                serving = try graph.serving(current: current, qualifications: qualifications,
                    requirements: required, artifactFacts: artifactFacts)
            } else { serving = nil }
            let lineage = try serving?.lineage ?? graph.lineage(current: current, qualifications: qualifications,
                selectionID: selection.id, facts: artifactFacts)
            var componentChecks = serving?.checks ?? lineage.checks
            if serving == nil {
                componentChecks.append(CapacityCheck(rule: .binding, domain: try .component(selection.id),
                    outcome: .unknown, reason: .incompleteCoverage))
            }
            var seenSubjects = Set<Data>()
            let subjects = (lineage.artifacts + (serving?.engine?.resolved ?? [])
                + (serving?.host?.resolved ?? []) + (serving?.devices?.resolved ?? []))
                .filter { seenSubjects.insert(Data($0.id.utf8)).inserted }
            for subject in subjects {
                if let coverage = conditionCoverage[Data(subject.id.utf8)] {
                    componentChecks.append(try coverage.check(basis: current, qualifications: qualifications))
                } else {
                    componentChecks.append(CapacityCheck(rule: .coverage, domain: try .component(subject.id),
                        outcome: .unknown, reason: .incompleteCoverage))
                }
                for condition in conditions where contextExact(condition.selectionID, subject.id) && condition.kind != .localHardware {
                    componentChecks.append(try condition.check(basis: current, qualifications: qualifications))
                }
            }
            let effective = lineage.servingArtifact
            let domain = try CapacityDomain.component(selection.id)
            // Resolving an adapter's effective artifact is itself a prerequisite
            // of inherited responsibility. Retain its actual qualification uses.
            var seenLineageEvidence = Set<String>()
            let lineageEvidence = lineage.checks.flatMap { $0.evidence }.filter {
                seenLineageEvidence.insert($0.qualification.key.sha256).inserted
            }
            guard let effective, let row = rows[Data(effective.id.utf8)], lineage.outcome == .pass else {
                componentChecks.append(CapacityCheck(rule: .deployment, domain: domain, outcome: .unknown,
                    reason: basis.sha256 != current.sha256 ? .changedBasis : .missingOrIneligible))
                components.append(CapacityComponentMode(selectionID: selection.id, effectiveSelectionID: effective?.id,
                    mode: .unknown, localApplicability: .unknown, serving: serving, checks: componentChecks,
                    applicabilityEvidence: lineageEvidence))
                checks += componentChecks; continue
            }
            let effectiveDomain = try CapacityDomain.component(effective.id)
            let operatorUse = try qualifications.use(basis: current, answer: row.runtimeOperator,
                fact: .runtimeOperator, domain: effectiveDomain)
            let capacityUse = try qualifications.use(basis: current, answer: row.capacityMode,
                fact: .capacityMode, domain: effectiveDomain)
            let exposureUse = try qualifications.use(basis: current, answer: row.exposedHardware,
                fact: .localVisibility, domain: effectiveDomain)
            let runtimeOperator = operatorUse != nil ? row.runtimeOperator.text : nil
            let capacityMode = capacityUse != nil ? row.capacityMode.text : nil
            let exposure = exposureUse != nil ? row.exposedHardware.boolean : nil
            let mode: CapacityMode
            if runtimeOperator == "self" { mode = .selfHosted }
            else if runtimeOperator == "provider" && capacityMode == "shared" { mode = .api }
            else if runtimeOperator == "provider" && (capacityMode == "reserved_throughput" || capacityMode == "dedicated_instances") {
                mode = .managed
            } else { mode = .unknown }
            let applies: CapacityApplicability
            if mode == .unknown { applies = .unknown }
            else if mode == .selfHosted || exposure == true { applies = .applicable }
            else if exposure == false { applies = .inapplicable }
            else { applies = .unknown }
            let responsibilityEvidence = lineageEvidence + [operatorUse].compactMap { $0 }
                + (runtimeOperator == "provider" ? [capacityUse].compactMap { $0 } : [])
            let applicabilityEvidence = responsibilityEvidence
                + (runtimeOperator == "provider" ? [exposureUse].compactMap { $0 } : [])
            componentChecks.append(CapacityCheck(rule: .deployment, domain: domain,
                outcome: mode == .unknown ? .unknown : .pass,
                reason: mode == .unknown ? .unknownResponsibility : .qualified,
                observations: [row.runtimeOperator, row.capacityMode, row.exposedHardware],
                evidence: responsibilityEvidence))
            switch applies {
            case .unknown:
                componentChecks.append(CapacityCheck(rule: .localHardware, domain: domain, outcome: .unknown,
                    reason: .unknownResponsibility, observations: [row.exposedHardware], evidence: applicabilityEvidence))
            case .inapplicable:
                componentChecks.append(CapacityCheck(rule: .localHardware, domain: domain, outcome: .skipped,
                    reason: .inapplicable, observations: [row.exposedHardware], evidence: applicabilityEvidence))
                componentChecks.append(CapacityCheck(rule: .remoteCapacity, domain: domain, outcome: .unknown, reason: .unknownCapacity))
            case .applicable:
                for subject in subjects {
                    for condition in conditions where contextExact(condition.selectionID, subject.id) && condition.kind == .localHardware {
                        componentChecks.append(try condition.check(basis: current, qualifications: qualifications))
                    }
                }
            }
            components.append(CapacityComponentMode(selectionID: selection.id, effectiveSelectionID: effective.id,
                mode: mode, localApplicability: applies, serving: serving, checks: componentChecks, applicabilityEvidence: applicabilityEvidence))
            checks += componentChecks
        }
        let coverageUse = try servingCoverage.use(basis: current, qualifications: qualifications)
        if components.isEmpty {
            checks.append(CapacityCheck(rule: .deployment, domain: try .component(basis.buildID),
                outcome: coverageUse == nil ? .unknown : .skipped,
                reason: coverageUse == nil ? .incompleteCoverage : .inapplicable,
                observations: [servingCoverage.claim], evidence: [coverageUse].compactMap { $0 }))
        }
        return CapacityDeploymentResult(result: CapacityResult(basis: current, qualifications: qualifications, checks: checks),
            components: components, servingMembershipKnown: coverageUse != nil)
    }
}
