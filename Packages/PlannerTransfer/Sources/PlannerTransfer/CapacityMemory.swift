import Foundation

/// Opt-in normalized CD-2 accounting. It never searches for placement, edits a Build, or claims measured fit.
public struct CapacityMemory: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let basis: CapacityBasis
    private let deployment: CapacityDeployment
    public let mode: CapacityCoverageMode
    public let components: CapacityRecords<CapacityMemoryComponent>
    public let devices: CapacityRecords<CapacityDevice>
    public let pools: CapacityRecords<CapacityPool>
    public let consumers: CapacityRecords<CapacityConsumer>
    public let allocations: CapacityRecords<CapacityAllocation>
    public let scenarios: CapacityRecords<CapacityScenario>
    public let limits: CapacityRecords<CapacityIndependentLimit>
    public let transitions: CapacityCoverage
    public var description: String { "CapacityMemory" }
    public var debugDescription: String { description }

    public init(basis: CapacityBasis, deployment: CapacityDeployment, profile: String,
                mode: CapacityCoverageMode, components: CapacityRecords<CapacityMemoryComponent>,
                devices: CapacityRecords<CapacityDevice>, pools: CapacityRecords<CapacityPool>,
                consumers: CapacityRecords<CapacityConsumer>, allocations: CapacityRecords<CapacityAllocation>,
                scenarios: CapacityRecords<CapacityScenario>, limits: CapacityRecords<CapacityIndependentLimit>,
                transitions: CapacityCoverage) throws {
        guard deployment.basis.sha256 == basis.sha256 else { throw CapacityError.contradictoryInput }
        guard contextExact(profile, CapacityBasis.logicalProfile) else { throw CapacityError.unsupportedProfile }
        for (coverage, kind) in [
            (components.coverage, CapacityCoverageKind.servingComponents),
            (devices.coverage, .hardwareInstances), (pools.coverage, .physicalPoolMap),
            (consumers.coverage, .consumers), (allocations.coverage, .chargeTerms),
            (scenarios.coverage, .scenarios), (limits.coverage, .independentCeilings),
            (transitions, .transitions)
        ] {
            try requireCapacityMemoryCoverage(coverage, kind: kind, basis: basis)
        }
        guard scenarios.records.count <= 64,
              scenarios.records.reduce(0, { $0 + $1.rows.count }) <= 4096,
              scenarios.records.reduce(0, { total, scenario in
                  total + scenario.rows.reduce(0, { $0 + $1.access.count })
              }) <= 8192 else { throw CapacityError.unsupportedNativeLimit }
        if mode == .conservativeAllResident && scenarios.records.count > 1 {
            throw CapacityError.contradictoryInput
        }
        self.basis = basis; self.deployment = deployment; self.mode = mode
        self.components = components; self.devices = devices; self.pools = pools
        self.consumers = consumers; self.allocations = allocations; self.scenarios = scenarios
        self.limits = limits; self.transitions = transitions
        try preflight()
    }

    /// Admit all supplied references before disabled, changed-basis, inapplicable or failure shortcuts.
    private func preflight() throws {
        let servingKinds = ["model", "embedding_model", "fine_tuned_model", "vector_database"]
        let enabledServing = Set(basis.selections.filter {
            $0.enabled && servingKinds.contains($0.kind)
        }.map { Data($0.id.utf8) })
        if components.ids.provided {
            guard let names = components.ids.strings,
                  Set(names.map { Data($0.utf8) }).isSuperset(of: enabledServing) else {
                throw CapacityError.contradictoryInput
            }
        }
        for component in components.records {
            guard let selected = basis.selection(id: component.id) else { throw CapacityError.contradictoryInput }
            guard servingKinds.contains(selected.kind) else { throw CapacityError.invalidDomain }
        }
        for device in devices.records {
            if let id = device.selectionID.text, basis.selection(id: id) == nil {
                throw CapacityError.contradictoryInput
            }
            if let pool = device.poolID.text { try pools.reference(pool) }
        }
        var physical = Set<[Data]>()
        var memberships: [Data: Data] = [:]
        for pool in pools.records {
            if let tuple = pool.physicalTuple, !physical.insert(tuple).inserted {
                throw CapacityError.contradictoryInput
            }
            for id in pool.deviceIDs.strings ?? [] {
                try devices.reference(id)
                let key = Data(id.utf8), poolKey = Data(pool.id.utf8)
                if let previous = memberships.updateValue(poolKey, forKey: key), previous != poolKey {
                    throw CapacityError.contradictoryInput
                }
                if let reverse = devices.record(id: id)?.poolID.text, !contextExact(reverse, pool.id) {
                    throw CapacityError.contradictoryInput
                }
            }
        }
        for device in devices.records {
            if let pool = device.poolID.text, let ids = pools.record(id: pool)?.deviceIDs.strings,
               !ids.contains(where: { contextExact($0, device.id) }) {
                throw CapacityError.contradictoryInput
            }
        }
        for consumer in consumers.records {
            if let component = consumer.componentID.text { try components.reference(component) }
            for device in consumer.deviceIDs.strings ?? [] { try devices.reference(device) }
            if let runtime = consumer.binding.runtime, runtime.kind == .modelEngine,
               basis.selection(id: runtime.id) == nil { throw CapacityError.contradictoryInput }
        }
        var extents = Set<[Data]>()
        for allocation in allocations.records {
            if let pool = allocation.poolID.text { try pools.reference(pool) }
            for consumer in allocation.consumerIDs.strings ?? [] { try consumers.reference(consumer) }
            if let pool = allocation.poolID.text, let extent = allocation.extent.text,
               !extents.insert([Data(pool.utf8), Data(extent.utf8)]).inserted {
                throw CapacityError.contradictoryInput
            }
        }
        for scenario in scenarios.records {
            try requireCapacityMemoryCoverage(scenario.coverage, kind: .chargeTerms,
                                              basis: basis, scenario: scenario.id)
            for component in scenario.componentIDs.strings ?? [] { try components.reference(component) }
            for row in scenario.rows {
                try allocations.reference(row.allocationID)
                let knownConsumers = allocations.record(id: row.allocationID)?.consumerIDs.strings
                    .map { Set($0.map { Data($0.utf8) }) }
                for access in row.access {
                    try consumers.reference(access.consumerID)
                    if let knownConsumers, !knownConsumers.contains(Data(access.consumerID.utf8)) {
                        throw CapacityError.contradictoryInput
                    }
                }
            }
        }
        for limit in limits.records {
            try scenarios.reference(limit.scenarioID)
            if let consumer = limit.consumerID.text { try consumers.reference(consumer) }
        }
    }

    public func evaluate(current: CapacityBasis, qualifications q: CapacityQualifications) throws -> CapacityResult {
        let componentInventory = try components.check(basis: current, qualifications: q)
        var checks = [componentInventory]
        guard current.sha256 == basis.sha256 else {
            checks.append(unknown(.physicalMap, pools.coverage.domain, .changedBasis,
                                  [components.ids, pools.ids, allocations.ids, scenarios.ids]))
            return CapacityResult(basis: current, qualifications: q, checks: checks, assumptions: [mode.rawValue])
        }
        let deploymentResult = try deployment.evaluate(current: current, qualifications: q)
        let derived = Dictionary(uniqueKeysWithValues: deploymentResult.components.map {
            (Data($0.selectionID.utf8), $0)
        })
        // Independent consistency/support failures survive an unresolved dependent capacity.
        checks += deploymentResult.result.checks.filter { $0.outcome == .fail }
        var applicability: [Data: CapacityApplicability] = [:]
        var applicabilityChecks: [Data: CapacityCheck] = [:]
        for component in components.records {
            let key = Data(component.id.utf8)
            let use = try q.use(basis: current, answer: component.applicable,
                                fact: .applicability, domain: component.domain)
            let normalized = try component.applicability(basis: current, qualifications: q)
            let selected = basis.selection(id: component.id)
            let actual = derived[key]?.localApplicability
            let applies: CapacityApplicability
            if selected?.enabled == false && normalized == false { applies = .inapplicable }
            else if normalized == true && actual == .applicable { applies = .applicable }
            else if normalized == false && actual == .inapplicable { applies = .inapplicable }
            else { applies = .unknown }
            let evidence = (use.map { [$0] } ?? []) + (derived[key]?.applicabilityEvidence ?? [])
            let check = CapacityCheck(rule: .localHardware, domain: component.domain,
                outcome: applies == .applicable ? .pass : applies == .inapplicable ? .skipped : .unknown,
                reason: applies == .applicable ? .qualified : applies == .inapplicable ? .inapplicable : .missingOrIneligible,
                observations: [component.applicable] + evidence.map { $0.answer }, evidence: evidence)
            checks.append(check); applicabilityChecks[key] = check; applicability[key] = applies
        }
        let applicabilityEvidence = components.records.flatMap {
            applicabilityChecks[Data($0.id.utf8)]?.evidence ?? []
        }
        if componentInventory.outcome == .pass && applicability.values.allSatisfy({ $0 == .inapplicable }) {
            checks.append(CapacityCheck(rule: .memoryPool, domain: pools.coverage.domain,
                outcome: .skipped, reason: .inapplicable,
                evidence: componentInventory.evidence + applicabilityEvidence))
            return CapacityResult(basis: current, qualifications: q, checks: checks, assumptions: [mode.rawValue])
        }

        let inventoryChecks = try [
            devices.check(basis: current, qualifications: q), pools.check(basis: current, qualifications: q),
            consumers.check(basis: current, qualifications: q), allocations.check(basis: current, qualifications: q)
        ]
        let allocationInventory = inventoryChecks[3]
        checks += inventoryChecks
        checks.append(try scenarios.check(basis: current, qualifications: q))
        checks.append(try limits.check(basis: current, qualifications: q))
        checks.append(try transitions.check(basis: current, qualifications: q))
        let transitionUse = try transitions.use(basis: current, qualifications: q)
        if scenarios.records.isEmpty || pools.records.isEmpty {
            checks.append(unknown(.memoryPool, pools.coverage.domain, .incompleteCoverage, [pools.ids, scenarios.ids]))
        }

        var mappedDevices: [Data: CapacityCheck] = [:]
        for device in devices.records {
            let check = try deviceCheck(device, current: current, qualifications: q)
            checks.append(check); mappedDevices[Data(device.id.utf8)] = check
        }
        var poolMapChecks: [Data: CapacityCheck] = [:]
        var poolIdentities: [Data: [CapacityEvidenceUse]] = [:]
        for pool in pools.records {
            let identity = try pool.identity(basis: current, qualifications: q)
            let memberships = try q.use(basis: current, answer: pool.deviceIDs, fact: .inventory, domain: pool.domain)
            let deviceSet = pool.deviceIDs.strings
            let mapKnown = identity != nil && memberships != nil && deviceSet != nil &&
                (deviceSet?.allSatisfy { mappedDevices[Data($0.utf8)]?.outcome == .pass } == true)
            let evidence = (identity ?? []) + (memberships.map { [$0] } ?? []) +
                (deviceSet ?? []).flatMap { mappedDevices[Data($0.utf8)]?.evidence ?? [] }
            let check = CapacityCheck(rule: .physicalMap, domain: pool.domain,
                outcome: mapKnown ? .pass : .unknown, reason: mapKnown ? .qualified : .unknownPhysicalIdentity,
                observations: [pool.addressSpace, pool.partition, pool.tenancy, pool.deviceIDs], evidence: evidence)
            checks.append(check); poolMapChecks[Data(pool.id.utf8)] = check
            poolIdentities[Data(pool.id.utf8)] = identity
        }
        var consumerIdentities: [Data: ConsumerIdentity] = [:]
        for consumer in consumers.records {
            let identity = try consumerIdentity(consumer, applicability: applicability,
                applicabilityChecks: applicabilityChecks, mappedDevices: mappedDevices,
                derived: derived, current: current, qualifications: q)
            checks.append(identity.check); consumerIdentities[Data(consumer.id.utf8)] = identity
        }
        for component in components.records where applicability[Data(component.id.utf8)] == .applicable {
            if !consumers.records.contains(where: {
                capacityExactOptional($0.componentID.text, component.id) &&
                    consumerIdentities[Data($0.id.utf8)]?.evidence != nil
            }) {
                checks.append(unknown(.coverage, component.domain, .incompleteCoverage, [component.applicable, consumers.ids]))
            }
        }

        var scenarioIdentities: [Data: ScenarioIdentity] = [:]
        for scenario in scenarios.records {
            let scenarioDomain = try CapacityDomain.inventory(kind: .scenarios, owner: basis.buildID, scenario: scenario.id)
            let envelope = try q.use(basis: current, answer: scenario.envelope, fact: .workload, domain: scenarioDomain)
            let placed = try q.use(basis: current, answer: scenario.componentIDs, fact: .inventory, domain: scenarioDomain)
            let placedIDs = scenario.componentIDs.strings.map { Set($0.map { Data($0.utf8) }) }
            var scenarioKnown = envelope != nil && placed != nil && placedIDs != nil
            var scenarioUses = [envelope, placed].compactMap { $0 }
            for component in components.records where applicability[Data(component.id.utf8)] == .applicable {
                scenarioUses += applicabilityChecks[Data(component.id.utf8)]?.evidence ?? []
                let placement = try q.use(basis: current, answer: component.placement, fact: .residency, domain: component.domain)
                if let placement { scenarioUses.append(placement) } else { scenarioKnown = false }
                let required = mode == .conservativeAllResident || component.placement.text == "always"
                if required && placedIDs?.contains(Data(component.id.utf8)) != true { scenarioKnown = false }
            }
            let scenarioCoverage = try scenario.coverage.check(basis: current, qualifications: q)
            checks.append(scenarioCoverage)
            scenarioIdentities[Data(scenario.id.utf8)] = ScenarioIdentity(
                known: scenarioKnown, placed: placedIDs ?? [], evidence: scenarioUses)
            if !scenarioKnown {
                checks.append(CapacityCheck(rule: .coverage, domain: scenarioDomain, outcome: .unknown,
                    reason: .incompleteCoverage, observations: [scenario.envelope, scenario.componentIDs], evidence: scenarioUses))
            }
            var charges: [Data: [QualifiedCharge]] = [:]
            var chargePoolOrder: [Data] = []
            var excludedUses: [Data?: [CapacityEvidenceUse]] = [:]
            var allExcludedUses: [CapacityEvidenceUse] = []
            var requiredPoolUses: [Data: [CapacityEvidenceUse]] = [:]
            var requiredPools = Set<Data>()
            for consumer in consumers.records {
                guard let identity = consumerIdentities[Data(consumer.id.utf8)]?.evidence,
                      let component = consumer.componentID.text,
                      placedIDs?.contains(Data(component.utf8)) == true else { continue }
                for device in consumer.deviceIDs.strings ?? [] {
                    if let pool = devices.record(id: device)?.poolID.text {
                        let key = Data(pool.utf8)
                        requiredPools.insert(key)
                        requiredPoolUses[key, default: []] += identity + (mappedDevices[Data(device.utf8)]?.evidence ?? [])
                    }
                }
            }
            var incompletePools = Set<Data>()
            var unscopedCharge = !allocations.ids.provided
            for allocation in allocations.records {
                let poolID = allocation.poolID.text
                let poolKey = poolID.map { Data($0.utf8) }
                let domain = try CapacityDomain.allocation(pool: poolID, allocation: allocation.id, scenario: scenario.id)
                guard let row = scenario.row(allocationID: allocation.id) else {
                    if let poolKey { incompletePools.insert(poolKey) } else { unscopedCharge = true }
                    checks.append(unknown(.memoryPool, domain, .missingAllocation, allocation.observations))
                    continue
                }
                let observations = allocation.observations + row.observations
                let residency = try q.use(basis: current, answer: row.residency, fact: .residency, domain: domain)
                if row.residency.text == "excluded", let residency, scenarioKnown,
                   mode == .qualifiedScenarios, let transitionUse {
                    let evidence = [residency, transitionUse] + scenarioUses
                    excludedUses[poolKey, default: []] += evidence; allExcludedUses += evidence
                    checks.append(CapacityCheck(rule: .memoryPool, domain: domain, outcome: .skipped,
                        reason: .inapplicable, observations: observations, evidence: evidence))
                    continue
                }
                let consumersForCharge = allocation.consumerIDs.strings
                let identities = consumersForCharge?.map { consumerIdentities[Data($0.utf8)] }
                let active = consumersForCharge?.contains { id in
                    guard let component = consumers.record(id: id)?.componentID.text else { return false }
                    return applicability[Data(component.utf8)] == .applicable &&
                        placedIDs?.contains(Data(component.utf8)) == true
                } == true
                let physical = allocation.nonOverlapping.boolean == true
                    ? try capacityMemoryUses(basis: current, qualifications: q, answers: allocation.observations,
                                             fact: .allocationIdentity, domain: domain) : nil
                let upper = try row.liveBytes.qualifiedUpper(basis: current, qualifications: q, domain: domain)
                let chargeIdentityKnown = poolID != nil && poolID.flatMap { pools.record(id: $0) } != nil &&
                    physical != nil && residency != nil && row.residency.text == "resident" &&
                    scenarioKnown && active && identities != nil &&
                    identities?.allSatisfy({ $0?.evidence != nil }) == true
                if chargeIdentityKnown, let poolKey { requiredPools.insert(poolKey) }

                // Access is an independent condition; successful byte arithmetic supplies no access evidence.
                if row.residency.text == "resident", let residency, let poolID {
                    for consumerID in consumersForCharge ?? [] {
                        let runtime = consumers.record(id: consumerID)?.binding.domain
                        let access = row.access.first { contextExact($0.consumerID, consumerID) }
                        let accessDomain = try runtime.map {
                            try CapacityDomain.access(pool: poolID, allocation: allocation.id,
                                scenario: scenario.id, consumer: consumerID, runtime: $0)
                        }
                        let use: CapacityEvidenceUse?
                        if let access, let accessDomain {
                            use = try q.use(basis: current, answer: access.allowed, fact: .access, domain: accessDomain)
                        } else { use = nil }
                        let known = use == nil ? nil : access?.allowed.boolean
                        checks.append(CapacityCheck(rule: .runtimeAccess, domain: accessDomain ?? domain,
                            outcome: known == true ? .pass : known == false ? .fail : .unknown,
                            reason: known == nil ? .unknownAccess : .qualified,
                            observations: [row.residency, access?.allowed].compactMap { $0 },
                            evidence: [residency, use].compactMap { $0 }))
                    }
                }
                if chargeIdentityKnown, let upper, let physical, let residency, let poolKey {
                    var evidence = physical + upper.evidence + [residency]
                    for identity in identities ?? [] { evidence += identity?.evidence ?? [] }
                    evidence += scenarioUses
                    if charges[poolKey] == nil { chargePoolOrder.append(poolKey) }
                    charges[poolKey, default: []].append(QualifiedCharge(id: allocation.id, upper: upper.value, evidence: evidence))
                } else {
                    if let poolKey { incompletePools.insert(poolKey) } else { unscopedCharge = true }
                    checks.append(unknown(.memoryPool, domain, .unknownResidency, observations))
                }
            }

            // An unused pool requires every supplied consumer to be assigned or qualified out of this scenario.
            var consumerScopeUses: [[CapacityEvidenceUse]?] = []
            for consumer in consumers.records {
                if let evidence = consumerIdentities[Data(consumer.id.utf8)]?.evidence {
                    consumerScopeUses.append(evidence)
                    continue
                }
                let componentUse: CapacityEvidenceUse?
                if let runtime = consumer.binding.domain {
                    componentUse = try q.use(basis: current, answer: consumer.componentID, fact: .inventory, domain: runtime)
                } else { componentUse = nil }
                if let componentUse, let component = consumer.componentID.text {
                    let key = Data(component.utf8)
                    if applicability[key] == .inapplicable ||
                        (scenarioKnown && applicability[key] == .applicable && !(placedIDs ?? []).contains(key)) {
                        consumerScopeUses.append([componentUse] + (applicabilityChecks[key]?.evidence ?? []) + scenarioUses)
                        continue
                    }
                }
                consumerScopeUses.append(nil)
            }
            let activeComponentsCovered = components.records.allSatisfy { component in
                let key = Data(component.id.utf8)
                return applicability[key] != .applicable || !(placedIDs ?? []).contains(key) ||
                    consumers.records.contains {
                        capacityExactOptional($0.componentID.text, component.id) &&
                            consumerIdentities[Data($0.id.utf8)]?.evidence != nil
                    }
            }
            for pool in pools.records {
                let key = Data(pool.id.utf8)
                let qualified = charges[key] ?? []
                var sum = CapacityByteCount.zero
                for charge in qualified { sum = try sum.adding(charge.upper) }
                let budget = try pool.budget.qualified(basis: current, qualifications: q, domain: pool.domain)
                let identity = poolIdentities[key]
                let requiredPool = requiredPools.contains(key)
                let witness = requiredPool && budget != nil && identity != nil && scenarioKnown
                let qualifiedUnused = !requiredPool && scenarioKnown && !unscopedCharge &&
                    componentInventory.outcome == .pass &&
                    applicability.values.allSatisfy({ $0 != .unknown }) &&
                    consumerScopeUses.allSatisfy({ $0 != nil }) && activeComponentsCovered &&
                    poolMapChecks.values.allSatisfy({ $0.outcome == .pass }) &&
                    inventoryChecks.allSatisfy({ $0.outcome == .pass }) &&
                    scenarioCoverage.outcome == .pass && incompletePools.isEmpty
                let incomplete = unscopedCharge || incompletePools.contains(key) ||
                    scenarioCoverage.outcome != .pass || allocationInventory.outcome != .pass
                let outcome: CapacityOutcome
                if qualifiedUnused { outcome = .skipped }
                else if witness, let budget, try !budget.fits(sum) { outcome = .fail }
                else if !witness || incomplete { outcome = .unknown }
                else { outcome = .pass }
                var evidence: [CapacityEvidenceUse]
                if qualifiedUnused {
                    evidence = scenarioUses + componentInventory.evidence + applicabilityEvidence
                    evidence += inventoryChecks.flatMap { $0.evidence } + scenarioCoverage.evidence
                    evidence += pools.records.flatMap { poolMapChecks[Data($0.id.utf8)]?.evidence ?? [] }
                    evidence += consumerScopeUses.flatMap { $0 ?? [] }
                    evidence += chargePoolOrder.flatMap { charges[$0] ?? [] }.flatMap { $0.evidence }
                    evidence += allExcludedUses
                } else {
                    evidence = (identity ?? []) + (budget?.evidence ?? []) + (requiredPoolUses[key] ?? [])
                    evidence += qualified.flatMap { $0.evidence } + scenarioUses
                    if outcome != .fail {
                        evidence += allocationInventory.evidence + scenarioCoverage.evidence
                        evidence += (excludedUses[key] ?? []) + (excludedUses[nil] ?? [])
                    }
                }
                checks.append(CapacityCheck(rule: .memoryPool,
                    domain: try .poolScenario(physical: pool.domain, scenario: scenario.id),
                    outcome: outcome,
                    reason: outcome == .fail ? .overUpperBoundBudget : outcome == .pass ? .qualified :
                        outcome == .skipped ? .inapplicable : .missingOrIneligible,
                    observations: pool.observations, evidence: evidence,
                    chargeIDs: qualified.map { $0.id }, demandUpper: witness ? sum : nil,
                    capacityLower: budget?.capacityLower, reserveUpper: budget?.reserveUpper,
                    mayNotFit: outcome == .fail))
            }
        }
        for limit in limits.records {
            checks.append(try limitCheck(limit, consumerIdentities: consumerIdentities,
                scenarioIdentities: scenarioIdentities, current: current, qualifications: q))
        }
        return CapacityResult(basis: current, qualifications: q, checks: checks, assumptions: [mode.rawValue])
    }

    private func deviceCheck(_ device: CapacityDevice, current: CapacityBasis,
                             qualifications q: CapacityQualifications) throws -> CapacityCheck {
        let domain = try CapacityDomain.device(device.id)
        let selected = device.selectionID.text.flatMap { basis.selection(id: $0) }
        let pool = device.poolID.text.flatMap { pools.record(id: $0) }
        let catalog = selected.flatMap { basis.catalogItem(forSelectionID: $0.id) }
        let use = try capacityMemoryUses(basis: current, qualifications: q,
            answers: [device.selectionID, device.poolID], fact: .inventory, domain: domain)
        let reciprocal = try pool.flatMap {
            try q.use(basis: current, answer: $0.deviceIDs, fact: .inventory, domain: $0.domain)
        }
        let outcome: CapacityOutcome
        if use == nil { outcome = .unknown }
        else if let selected, !selected.enabled || !["accelerator", "compute_profile"].contains(selected.kind) ||
            (catalog != nil && catalog?.object?["kind"]?.string != selected.kind) { outcome = .fail }
        else if selected == nil || catalog == nil || reciprocal == nil { outcome = .unknown }
        else { outcome = .pass }
        return CapacityCheck(rule: .physicalMap, domain: domain, outcome: outcome,
            reason: outcome == .fail ? .wrongKindOrDisabled : outcome == .pass ? .qualified : .unknownPhysicalIdentity,
            observations: [device.selectionID, device.poolID] + (pool.map { [$0.deviceIDs] } ?? []),
            evidence: (use ?? []) + (reciprocal.map { [$0] } ?? []))
    }

    private struct ConsumerIdentity: Sendable {
        let check: CapacityCheck
        let evidence: [CapacityEvidenceUse]?
    }
    private struct QualifiedCharge: Sendable {
        let id: String
        let upper: CapacityByteCount
        let evidence: [CapacityEvidenceUse]
    }
    private struct ScenarioIdentity: Sendable {
        let known: Bool
        let placed: Set<Data>
        let evidence: [CapacityEvidenceUse]
    }

    private func consumerIdentity(_ consumer: CapacityConsumer,
        applicability: [Data: CapacityApplicability], applicabilityChecks: [Data: CapacityCheck],
        mappedDevices: [Data: CapacityCheck], derived: [Data: CapacityComponentMode],
        current: CapacityBasis, qualifications q: CapacityQualifications) throws -> ConsumerIdentity {
        let domain = try consumer.binding.domain ?? .component(consumer.id)
        let runtime = consumer.binding.runtime
        let component = consumer.componentID.text.flatMap { basis.selection(id: $0) }
        let source = consumer.binding.sourceInput.flatMap { current.input(named: $0) }
        let uses = try capacityMemoryUses(basis: current, qualifications: q,
                                         answers: consumer.observations, fact: .inventory, domain: domain)
        let selected = runtime.flatMap { $0.kind == .modelEngine ? basis.selection(id: $0.id) : nil }
        let serving = component.flatMap { derived[Data($0.id.utf8)]?.serving }
        let bindingsKnown = serving != nil && serving?.lineage.outcome == .pass &&
            serving?.checks.contains(where: { $0.outcome == .fail || $0.outcome == .unknown }) == false
        let engineMatches: Bool
        if let runtime {
            if runtime.kind == .modelEngine, let engines = serving?.engine?.resolved, engines.count == 1 {
                engineMatches = contextExact(engines[0].id, runtime.id)
            } else {
                engineMatches = runtime.kind == .serviceRuntime && serving?.engine?.check.outcome == .skipped
            }
        } else { engineMatches = false }
        let selectedDeviceIDs = Set((serving?.devices?.resolved ?? []).map { Data($0.id.utf8) })
        let deviceBindingsMatch = consumer.deviceIDs.strings?.allSatisfy { id in
            guard let selection = devices.record(id: id)?.selectionID.text else { return false }
            return selectedDeviceIDs.contains(Data(selection.utf8))
        } == true
        let wrongRuntime: Bool
        if let runtime, let component {
            wrongRuntime = (runtime.kind == .serviceRuntime && component.kind != "vector_database") ||
                (runtime.kind == .modelEngine && component.kind == "vector_database") ||
                (selected != nil && (selected?.kind != "inference_engine" || selected?.enabled != true))
        } else { wrongRuntime = false }
        let known = uses != nil && bindingsKnown && engineMatches && deviceBindingsMatch &&
            capacityExactOptional(consumer.operation.text, basis.operation) && component != nil &&
            component.map({ applicability[Data($0.id.utf8)] == .applicable }) == true &&
            consumer.deviceIDs.strings?.allSatisfy({ mappedDevices[Data($0.utf8)]?.outcome == .pass }) == true &&
            source?.kind == .engineBuilds && runtime != nil &&
            (runtime?.kind == .serviceRuntime ||
                (selected != nil && selected.flatMap { basis.catalogItem(forSelectionID: $0.id) } != nil))
        let outcome: CapacityOutcome = uses != nil && wrongRuntime ? .fail : known ? .pass : .unknown
        var evidence = (uses ?? []) + (serving?.checks ?? []).flatMap { $0.evidence }
        evidence += (consumer.deviceIDs.strings ?? []).flatMap { mappedDevices[Data($0.utf8)]?.evidence ?? [] }
        evidence += component.flatMap { applicabilityChecks[Data($0.id.utf8)]?.evidence } ?? []
        let check = CapacityCheck(rule: .binding, domain: domain, outcome: outcome,
            reason: outcome == .fail ? .wrongKindOrDisabled : outcome == .pass ? .qualified : .missingOrIneligible,
            observations: consumer.observations, evidence: evidence)
        return ConsumerIdentity(check: check, evidence: outcome == .pass ? evidence : nil)
    }

    private func limitCheck(_ limit: CapacityIndependentLimit,
        consumerIdentities: [Data: ConsumerIdentity], scenarioIdentities: [Data: ScenarioIdentity],
        current: CapacityBasis, qualifications q: CapacityQualifications) throws -> CapacityCheck {
        let runtime = limit.binding.domain
        let domain: CapacityDomain
        if let runtime { domain = try .ceiling(limit: limit.id, scenario: limit.scenarioID, runtime: runtime) }
        else { domain = try .inventory(kind: .independentCeilings, owner: basis.buildID, scenario: limit.scenarioID) }
        let applicability = try q.use(basis: current, answer: limit.applicable, fact: .applicability, domain: domain)
        if let applicability, limit.applicable.boolean == false {
            return CapacityCheck(rule: .independentCeiling, domain: domain, outcome: .skipped,
                reason: .inapplicable, observations: limit.observations, evidence: [applicability])
        }
        let consumerID = limit.consumerID.text
        let consumer = consumerID.flatMap { consumers.record(id: $0) }
        let identity = try capacityMemoryUses(basis: current, qualifications: q,
            answers: [limit.consumerID, limit.binding.answer, limit.accountingDefinition], fact: .ceiling, domain: domain)
        let coverage = limit.accountingComplete.boolean == true
            ? try q.use(basis: current, answer: limit.accountingComplete, fact: .coverage, domain: domain) : nil
        let demand = try limit.demand.qualifiedUpper(basis: current, qualifications: q, domain: domain)
        let budget = try limit.budget.qualified(basis: current, qualifications: q, domain: domain)
        let scenario = scenarioIdentities[Data(limit.scenarioID.utf8)]
        let consumerUses = consumerID.flatMap { consumerIdentities[Data($0.utf8)]?.evidence }
        let placed = consumer?.componentID.text.map { scenario?.placed.contains(Data($0.utf8)) == true } == true
        let known = applicability != nil && limit.applicable.boolean == true && identity != nil &&
            coverage != nil && runtime != nil && consumer?.binding.domain == runtime &&
            consumerUses != nil && scenario?.known == true && placed && demand != nil && budget != nil
        let outcome: CapacityOutcome
        if known, let budget, let demand { outcome = try budget.fits(demand.value) ? .pass : .fail }
        else { outcome = .unknown }
        var evidence = [applicability, coverage].compactMap { $0 } + (identity ?? [])
        evidence += (demand?.evidence ?? []) + (budget?.evidence ?? []) + (consumerUses ?? []) + (scenario?.evidence ?? [])
        return CapacityCheck(rule: .independentCeiling, domain: domain, outcome: outcome,
            reason: outcome == .fail ? .overUpperBoundBudget : outcome == .pass ? .qualified : .missingOrIneligible,
            observations: limit.observations, evidence: evidence,
            demandUpper: known ? demand?.value : nil, capacityLower: known ? budget?.capacityLower : nil,
            reserveUpper: known ? budget?.reserveUpper : nil, mayNotFit: outcome == .fail)
    }

    private func unknown(_ rule: CapacityRule, _ domain: CapacityDomain, _ reason: CapacityReason,
                         _ observations: [CapacityBoundAnswer]) -> CapacityCheck {
        CapacityCheck(rule: rule, domain: domain, outcome: .unknown, reason: reason, observations: observations)
    }
}
