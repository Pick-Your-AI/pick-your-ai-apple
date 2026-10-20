import Foundation

public enum CapacityRole: String, Sendable {
    case host, device
    case engine = "serving_engine"
    case base = "base_artifact"
    case draftTarget = "speculative_draft"
    var relation: String {
        switch self {
        case .host, .device: return "runs_on"
        case .engine: return "served_by"
        case .base: return "derived_from"
        case .draftTarget: return "feeds"
        }
    }
    var single: Bool { self != .device }
    var targetKinds: Set<String> {
        switch self {
        case .host: return ["hosting_platform"]
        case .device: return ["accelerator", "compute_profile"]
        case .engine: return ["inference_engine"]
        case .base, .draftTarget: return ["model", "fine_tuned_model"]
        }
    }
}

/// Metadata describes an existing frozen edge. It cannot supply another graph or endpoints.
public struct CapacityLinkMeaning: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let linkID: String
    public let role: CapacityBoundAnswer
    public let operation: CapacityBoundAnswer
    public var description: String { "CapacityLinkMeaning" }
    public var debugDescription: String { description }
    public init(linkID: String, role: CapacityBoundAnswer, operation: CapacityBoundAnswer) throws {
        try capacityIdentity(linkID)
        try requireCapacityField(role, .role); try requireCapacityField(operation, .text)
        self.linkID = linkID; self.role = role; self.operation = operation
    }
}

public struct CapacityBinding: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let check: CapacityCheck
    /// Original graph order is retained; it is never a winner-selection rule.
    public let candidates: [CapacitySelection]
    public let resolved: [CapacitySelection]
    public var description: String { "CapacityBinding" }
    public var debugDescription: String { description }
}

public struct CapacityArtifactFacts: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let selectionID: String
    public let artifactKind: CapacityBoundAnswer
    public let baseVersion: CapacityBoundAnswer
    public let baseRequired: CapacityBoundAnswer
    public var description: String { "CapacityArtifactFacts" }
    public var debugDescription: String { description }
    public init(selectionID: String, artifactKind: CapacityBoundAnswer,
                baseVersion: CapacityBoundAnswer, baseRequired: CapacityBoundAnswer) throws {
        try capacityIdentity(selectionID)
        try requireCapacityField(artifactKind, .artifactKind)
        try requireCapacityField(baseVersion, .text); try requireCapacityField(baseRequired, .boolean)
        guard artifactKind.text != "adapter" || baseRequired.boolean != false else {
            throw CapacityError.contradictoryInput
        }
        self.selectionID = selectionID; self.artifactKind = artifactKind
        self.baseVersion = baseVersion; self.baseRequired = baseRequired
    }
}

public struct CapacityLineage: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let artifacts: [CapacitySelection]
    public let checks: [CapacityCheck]
    public let servingArtifact: CapacitySelection?
    public var outcome: CapacityOutcome {
        if checks.contains(where: { $0.outcome == .fail }) { return .fail }
        return servingArtifact == nil ? .unknown : .pass
    }
    public var description: String { "CapacityLineage" }
    public var debugDescription: String { description }
}

/// Reads one exact operation's role meanings on the retained Build graph.
public struct CapacityGraph: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let basis: CapacityBasis
    public let coverage: CapacityCoverage
    private let meanings: [Data: CapacityLinkMeaning]
    public var description: String { "CapacityGraph" }
    public var debugDescription: String { description }

    public init(basis: CapacityBasis, meanings: [CapacityLinkMeaning], coverage: CapacityCoverage) throws {
        guard meanings.count <= CapacityBasis.maximumLinks else { throw CapacityError.unsupportedNativeLimit }
        guard coverage.kind == .roleBindings, contextExact(coverage.owner, basis.buildID),
              capacityExactOptional(coverage.scenario, basis.operation) else { throw CapacityError.invalidDomain }
        let links = Set(basis.links.map { Data($0.id.utf8) })
        var index: [Data: CapacityLinkMeaning] = [:]
        for meaning in meanings {
            let key = Data(meaning.linkID.utf8)
            guard links.contains(key) else { throw CapacityError.danglingReference }
            guard index.updateValue(meaning, forKey: key) == nil else { throw CapacityError.duplicateIdentity }
        }
        self.basis = basis; self.coverage = coverage; self.meanings = index
    }

    public func resolve(current: CapacityBasis, qualifications: CapacityQualifications,
                        fromSelectionID: String, role: CapacityRole,
                        required: CapacityBoundAnswer) throws -> CapacityBinding {
        try capacityIdentity(fromSelectionID); try requireCapacityField(required, .boolean)
        guard let from = basis.selection(id: fromSelectionID) else { throw CapacityError.danglingReference }
        let domain = try CapacityDomain.role(selection: fromSelectionID, role: role.rawValue)
        var observations = [required, coverage.claim], evidence: [CapacityEvidenceUse] = []
        var candidates: [CapacitySelection] = [], selected: [CapacitySelection] = []
        var incomplete = false, invalidTarget = false
        let fromCatalog = basis.catalogItem(forSelectionID: from.id)
        var missingVersion = fromCatalog == nil
        let requiredUse = try qualifications.use(basis: current, answer: required, fact: .applicability, domain: domain)
        let coverageUse = try coverage.use(basis: current, qualifications: qualifications)
        evidence += [requiredUse, coverageUse].compactMap { $0 }
        for link in basis.links where contextExact(link.fromSelectionID, fromSelectionID) && link.relation == role.relation {
            guard let target = basis.selection(id: link.toSelectionID) else { throw CapacityError.danglingReference }
            guard let meaning = meanings[Data(link.id.utf8)] else {
                incomplete = true; candidates.append(target); continue
            }
            observations += [meaning.role, meaning.operation]
            let linkDomain = try CapacityDomain.link(link.id)
            let roleUse = try qualifications.use(basis: current, answer: meaning.role, fact: .role, domain: linkDomain)
            let operationUse = try qualifications.use(basis: current, answer: meaning.operation, fact: .operation, domain: linkDomain)
            guard let roleUse, let operationUse else {
                incomplete = true; candidates.append(target); continue
            }
            evidence += [roleUse, operationUse]
            guard meaning.role.text == role.rawValue,
                  capacityExactOptional(meaning.operation.text, basis.operation) else { continue }
            candidates.append(target); selected.append(target)
            if !target.enabled || !role.targetKinds.contains(target.kind) { invalidTarget = true }
            if let catalog = basis.catalogItem(forSelectionID: target.id) {
                if catalog.object?["kind"]?.string != target.kind { invalidTarget = true }
            } else { missingVersion = true }
        }
        func result(_ outcome: CapacityOutcome, _ reason: CapacityReason) -> CapacityBinding {
            CapacityBinding(check: CapacityCheck(rule: .binding, domain: domain, outcome: outcome,
                reason: reason, observations: observations, evidence: evidence),
                candidates: candidates, resolved: outcome == .pass ? selected : [])
        }
        guard basis.sha256 == current.sha256 else { return result(.unknown, .changedBasis) }
        if let catalog = fromCatalog, catalog.object?["kind"]?.string != from.kind {
            return result(.fail, .wrongKindOrDisabled)
        }
        guard from.enabled else { return result(.skipped, .inapplicable) }
        guard requiredUse != nil else { return result(.unknown, .missingOrIneligible) }
        if invalidTarget { return result(required.boolean == true ? .fail : .unknown, .wrongKindOrDisabled) }
        if role.single && candidates.count > 1 { return result(.unknown, .ambiguousBinding) }
        if incomplete || coverageUse == nil { return result(.unknown, .incompleteCoverage) }
        if selected.isEmpty {
            return result(required.boolean == true ? .fail : .skipped,
                          required.boolean == true ? .requiredBindingAbsent : .inapplicable)
        }
        if missingVersion { return result(.unknown, .missingCatalogVersion) }
        return result(.pass, .qualified)
    }

    /// A full/merged artifact keeps its own capabilities; only an explicit adapter follows a base.
    public func lineage(current: CapacityBasis, qualifications: CapacityQualifications,
                        selectionID: String, facts: [CapacityArtifactFacts]) throws -> CapacityLineage {
        let bySelection = try admitCapacityArtifactFacts(basis: basis, facts: facts)
        guard var selected = basis.selection(id: selectionID) else { throw CapacityError.danglingReference }
        var path: [CapacitySelection] = [], checks: [CapacityCheck] = [], visited = Set<Data>()
        var usedObservations: [CapacityBoundAnswer] = [], usedEvidence: [CapacityEvidenceUse] = []
        func check(_ rule: CapacityRule, _ domain: CapacityDomain, _ outcome: CapacityOutcome,
                   _ reason: CapacityReason, observations: [CapacityBoundAnswer] = [],
                   evidence: [CapacityEvidenceUse] = []) -> CapacityCheck {
            CapacityCheck(rule: rule, domain: domain, outcome: outcome, reason: reason,
                observations: usedObservations + observations, evidence: usedEvidence + evidence)
        }
        func unknown(_ reason: CapacityReason) throws -> CapacityLineage {
            checks.append(check(.adapterEngine, try .component(selected.id), .unknown, reason))
            return CapacityLineage(artifacts: path, checks: checks, servingArtifact: nil)
        }
        guard current.sha256 == basis.sha256 else { return try unknown(.changedBasis) }
        while true {
            guard visited.insert(Data(selected.id.utf8)).inserted else { return try unknown(.bindingCycle) }
            path.append(selected)
            guard let catalog = basis.catalogItem(forSelectionID: selected.id) else {
                return try unknown(.missingCatalogVersion)
            }
            let domain = try CapacityDomain.component(selected.id)
            guard catalog.object?["kind"]?.string == selected.kind else {
                checks.append(check(.adapterEngine, domain, .fail, .wrongKindOrDisabled))
                return CapacityLineage(artifacts: path, checks: checks, servingArtifact: nil)
            }
            guard selected.kind == "fine_tuned_model" else {
                return CapacityLineage(artifacts: path, checks: checks, servingArtifact: selected)
            }
            guard let fact = bySelection[Data(selected.id.utf8)] else { return try unknown(.missingOrIneligible) }
            usedObservations.append(fact.artifactKind)
            guard let kindUse = try qualifications.use(basis: current, answer: fact.artifactKind,
                fact: .compatibility, domain: domain) else { return try unknown(.missingOrIneligible) }
            usedEvidence.append(kindUse)
            let adapter = fact.artifactKind.text == "adapter"
            if let recorded = catalog.object?["spec"]?.object?["adapter_only"],
               case .bool(let flag) = recorded, flag != adapter {
                checks.append(check(.adapterEngine, domain, .fail, .baseArtifactMismatch))
                return CapacityLineage(artifacts: path, checks: checks, servingArtifact: nil)
            }
            guard adapter else {
                checks.append(check(.adapterEngine, domain, .pass, .qualified))
                return CapacityLineage(artifacts: path, checks: checks, servingArtifact: selected)
            }
            let base = try resolve(current: current, qualifications: qualifications,
                fromSelectionID: selected.id, role: .base, required: fact.baseRequired)
            checks.append(check(base.check.rule, base.check.domain, base.check.outcome, base.check.reason,
                observations: base.check.observations, evidence: base.check.evidence))
            guard base.check.outcome == .pass else {
                return CapacityLineage(artifacts: path, checks: checks, servingArtifact: nil)
            }
            usedObservations += base.check.observations; usedEvidence += base.check.evidence
            guard base.resolved.count == 1, let target = base.resolved.first else { throw CapacityError.contradictoryInput }
            guard capacityExactOptional(catalog.object?["spec"]?.object?["base_model_ref"]?.string, target.catalogItemID) else {
                checks.append(check(.adapterEngine, domain, .fail, .baseArtifactMismatch))
                return CapacityLineage(artifacts: path, checks: checks, servingArtifact: nil)
            }
            usedObservations.append(fact.baseVersion)
            guard let versionUse = try qualifications.use(basis: current, answer: fact.baseVersion,
                fact: .compatibility, domain: domain) else { return try unknown(.missingCatalogVersion) }
            usedEvidence.append(versionUse)
            guard capacityExactOptional(fact.baseVersion.text, target.catalogItemVersion) else {
                checks.append(check(.adapterEngine, domain, .fail, .baseArtifactMismatch))
                return CapacityLineage(artifacts: path, checks: checks, servingArtifact: nil)
            }
            checks.append(check(.adapterEngine, domain, .pass, .qualified))
            selected = target
        }
    }
}

func admitCapacityArtifactFacts(basis: CapacityBasis, facts: [CapacityArtifactFacts]) throws -> [Data: CapacityArtifactFacts] {
    guard facts.count <= CapacityBasis.maximumSelections else { throw CapacityError.unsupportedNativeLimit }
    var index: [Data: CapacityArtifactFacts] = [:]
    for fact in facts {
        guard basis.selection(id: fact.selectionID) != nil else { throw CapacityError.danglingReference }
        guard index.updateValue(fact, forKey: Data(fact.selectionID.utf8)) == nil else { throw CapacityError.duplicateIdentity }
    }
    return index
}

public struct CapacityServingRequirements: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let selectionID: String
    public let engine: CapacityBoundAnswer
    public let host: CapacityBoundAnswer
    public let devices: CapacityBoundAnswer
    public var description: String { "CapacityServingRequirements" }
    public var debugDescription: String { description }
    public init(selectionID: String, engine: CapacityBoundAnswer,
                host: CapacityBoundAnswer, devices: CapacityBoundAnswer) throws {
        try capacityIdentity(selectionID)
        for answer in [engine, host, devices] { try requireCapacityField(answer, .boolean) }
        self.selectionID = selectionID; self.engine = engine; self.host = host; self.devices = devices
    }
}

public struct CapacityServingBinding: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let lineage: CapacityLineage
    public let engine: CapacityBinding?
    public let host: CapacityBinding?
    public let devices: CapacityBinding?
    public var checks: [CapacityCheck] { lineage.checks + [engine?.check, host?.check, devices?.check].compactMap { $0 } }
    public var outcome: CapacityOutcome {
        guard lineage.outcome == .pass else { return lineage.outcome }
        return aggregateCapacity([engine?.check, host?.check, devices?.check].compactMap { $0?.outcome })
    }
    public var description: String { "CapacityServingBinding" }
    public var debugDescription: String { description }
}

extension CapacityGraph {
    public func serving(current: CapacityBasis, qualifications: CapacityQualifications,
                        requirements: CapacityServingRequirements,
                        artifactFacts: [CapacityArtifactFacts]) throws -> CapacityServingBinding {
        let lineage = try lineage(current: current, qualifications: qualifications,
            selectionID: requirements.selectionID, facts: artifactFacts)
        guard lineage.outcome == .pass, let subject = lineage.servingArtifact else {
            return CapacityServingBinding(lineage: lineage, engine: nil, host: nil, devices: nil)
        }
        return try CapacityServingBinding(lineage: lineage,
            engine: resolve(current: current, qualifications: qualifications, fromSelectionID: subject.id,
                            role: .engine, required: requirements.engine),
            host: resolve(current: current, qualifications: qualifications, fromSelectionID: subject.id,
                          role: .host, required: requirements.host),
            devices: resolve(current: current, qualifications: qualifications, fromSelectionID: subject.id,
                             role: .device, required: requirements.devices))
    }
}
