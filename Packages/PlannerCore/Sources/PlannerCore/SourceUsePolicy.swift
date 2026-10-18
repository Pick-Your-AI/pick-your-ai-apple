import Foundation

/// Local intake/domain enforcement, not a shared wire schema or legal grant.
/// Canonical input: research #60 rights-validation.md at
/// 92111483b8d52b1b05152391b2d73e9f59ca2fba. No source-specific permission is
/// hardcoded. Trusted intake must resolve current, authentic, applicable receipts.
public enum SourceUseOperation: Hashable, Sendable {
    case appleDisplay, offlineCache, export, automatedRetrieval
}
public enum SourceMaterialKind: Hashable, Sendable { case production, syntheticFixture }
public enum SourceUseValidationError: Error, Equatable { case emptyIdentity, invalidDigest, invalidDate }

private func sourceUseNonblank(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
private func sourceUseHex(_ value: String, count: Int) -> Bool {
    value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}

/// Identifies the exact bytes, claim, source version, snapshot and intended use.
/// Scope identifies the reviewed use context (for example, metadata versus
/// upstream artifact, or a build estimate versus a price-comparison service).
public struct SourceUseRequest: Hashable, Sendable {
    public let sourceID: String
    public let claimID: String
    public let sourceVersion: String
    public let snapshotID: String
    public let claimSHA256: String
    public let operation: SourceUseOperation
    public let scopeID: String
    public let materialKind: SourceMaterialKind

    public init(sourceID: String, claimID: String, sourceVersion: String, snapshotID: String,
                claimSHA256: String, operation: SourceUseOperation, scopeID: String,
                materialKind: SourceMaterialKind) throws {
        guard [sourceID, claimID, sourceVersion, snapshotID, scopeID].allSatisfy(sourceUseNonblank) else {
            throw SourceUseValidationError.emptyIdentity
        }
        guard sourceUseHex(claimSHA256, count: 64) else { throw SourceUseValidationError.invalidDigest }
        self.sourceID = sourceID
        self.claimID = claimID
        self.sourceVersion = sourceVersion
        self.snapshotID = snapshotID
        self.claimSHA256 = claimSHA256
        self.operation = operation
        self.scopeID = scopeID
        self.materialKind = materialKind
    }
}

/// Exact dated row in an immutable research record. A date is provenance, not a
/// guessed expiry/TTL. Rights changes must arrive as updated intake decisions.
public struct SourceRightsRow: Hashable, Sendable {
    public let recordReference: String
    public let recordRevision: String
    public let rowID: String
    public let termsReference: String
    public let termsCheckedDate: String

    public init(recordReference: String, recordRevision: String, rowID: String,
                termsReference: String, termsCheckedDate: String) throws {
        guard [recordReference, rowID, termsReference].allSatisfy(sourceUseNonblank) else {
            throw SourceUseValidationError.emptyIdentity
        }
        guard sourceUseHex(recordRevision, count: 40) else { throw SourceUseValidationError.invalidDigest }
        let bytes = Array(termsCheckedDate.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(termsCheckedDate.prefix(4)), year > 0,
              let month = Int(termsCheckedDate.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(termsCheckedDate.suffix(2)) else { throw SourceUseValidationError.invalidDate }
        let leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...monthDays[month - 1]).contains(day) else { throw SourceUseValidationError.invalidDate }
        self.recordReference = recordReference
        self.recordRevision = recordRevision
        self.rowID = rowID
        self.termsReference = termsReference
        self.termsCheckedDate = termsCheckedDate
    }
}

public enum SourceRightsDisposition: Sendable { case permitted, denied, unknown, revoked }
public enum SourceUseConditions: Sendable {
    /// References the actual review of all terms, notices, attribution and scope
    /// conditions for this exact request. Empty references never authorize use.
    case satisfied(receiptReference: String)
    case unsatisfied, unknown
}
public struct SourceRightsDecision: Sendable {
    public let request: SourceUseRequest
    public let row: SourceRightsRow
    public let disposition: SourceRightsDisposition
    public let conditions: SourceUseConditions
    public init(request: SourceUseRequest, row: SourceRightsRow,
                disposition: SourceRightsDisposition, conditions: SourceUseConditions) {
        self.request = request
        self.row = row
        self.disposition = disposition
        self.conditions = conditions
    }
}

public enum SourcePromotionDisposition: Sendable { case accepted, rejected, pending, revoked }
/// Separate publication/Apple receiving approval for exact claims and use rights.
/// A research merge or evidence grade is not an accepted promotion receipt.
public struct SourcePromotionReceipt: Sendable {
    public let request: SourceUseRequest
    public let rightsRow: SourceRightsRow
    public let receiptReference: String
    public let disposition: SourcePromotionDisposition
    public init(request: SourceUseRequest, rightsRow: SourceRightsRow,
                receiptReference: String, disposition: SourcePromotionDisposition) {
        self.request = request
        self.rightsRow = rightsRow
        self.receiptReference = receiptReference
        self.disposition = disposition
    }
}

public enum SourceUseDenial: Equatable, Sendable {
    case syntheticIdentity, noMatchingRightsDecision, conflictingRightsDecisions, rightsDenied, rightsUnknown, rightsRevoked
    case conditionsUnverified, noMatchingPromotion, conflictingPromotions, promotionNotAccepted, promotionRevoked
}
public struct SourceUseAudit: Equatable, Sendable {
    public let request: SourceUseRequest
    public let rightsRow: SourceRightsRow
    public let conditionsReceiptReference: String
    public let promotionReceiptReference: String
    fileprivate init(request: SourceUseRequest, rightsRow: SourceRightsRow,
                     conditionsReceiptReference: String, promotionReceiptReference: String) {
        self.request = request
        self.rightsRow = rightsRow
        self.conditionsReceiptReference = conditionsReceiptReference
        self.promotionReceiptReference = promotionReceiptReference
    }
}
public enum SourceUseAssessment: Equatable, Sendable {
    case authorized(SourceUseAudit)
    /// May be used only by a separate synthetic test/preview path. This case is
    /// never authorization to activate production data or reuse real source data.
    case syntheticOnly
    case denied(SourceUseDenial)
}

public enum SourceUsePolicy {
    /// Fail-closed exact matching. Intake supplies current complete decisions,
    /// including revocations, rather than selecting an old favorable row. This
    /// synchronous gate does not verify signatures, fetch terms, hash payloads,
    /// perform atomic activation or implement durable revocation propagation.
    public static func assess(_ request: SourceUseRequest, rights: [SourceRightsDecision],
                              promotions: [SourcePromotionReceipt]) -> SourceUseAssessment {
        guard request.materialKind == .production else { return .syntheticOnly }
        guard !FrozenV1SyntheticSourceIdentities.contains(request) else { return .denied(.syntheticIdentity) }
        let decisions = rights.filter { $0.request == request }
        guard !decisions.isEmpty else { return .denied(.noMatchingRightsDecision) }
        if decisions.contains(where: { $0.disposition == .revoked }) { return .denied(.rightsRevoked) }
        guard decisions.count == 1, let decision = decisions.first else { return .denied(.conflictingRightsDecisions) }
        switch decision.disposition {
        case .denied: return .denied(.rightsDenied)
        case .unknown: return .denied(.rightsUnknown)
        case .revoked: return .denied(.rightsRevoked)
        case .permitted: break
        }
        guard case .satisfied(let conditionsReference) = decision.conditions,
              sourceUseNonblank(conditionsReference) else { return .denied(.conditionsUnverified) }
        let approvals = promotions.filter { $0.request == request && $0.rightsRow == decision.row }
        guard !approvals.isEmpty else { return .denied(.noMatchingPromotion) }
        if approvals.contains(where: { $0.disposition == .revoked }) { return .denied(.promotionRevoked) }
        guard approvals.count == 1, let approval = approvals.first else { return .denied(.conflictingPromotions) }
        guard approval.disposition == .accepted, sourceUseNonblank(approval.receiptReference) else {
            return .denied(.promotionNotAccepted)
        }
        return .authorized(SourceUseAudit(request: request, rightsRow: decision.row,
                                        conditionsReceiptReference: conditionsReference,
                                        promotionReceiptReference: approval.receiptReference))
    }
}

/// Exact frozen synthetic catalog identifiers, not a reserved-prefix heuristic.
/// Source: research contracts/v1/examples/catalog.json at
/// 92111483b8d52b1b05152391b2d73e9f59ca2fba, preserved by the frozen import.
/// This defense recognizes known fixtures; authentic intake must still prevent
/// arbitrary synthetic data from being relabeled or assigned new identifiers.
enum FrozenV1SyntheticSourceIdentities {
    static let identifiers: Set<String> = [
        "catalog.fixture.1",
        "cat.workload.fixture",
        "cat.deployment_mode.fixture",
        "cat.model_provider.fixture",
        "cat.model.fixture",
        "cat.context_policy.fixture",
        "cat.hosting_platform.fixture",
        "cat.accelerator.fixture",
        "cat.compute_profile.fixture",
        "cat.inference_engine.fixture",
        "cat.storage.fixture",
        "cat.data_source.fixture",
        "cat.knowledge_base.fixture",
        "cat.embedding_model.fixture",
        "cat.vector_database.fixture",
        "cat.rag_pipeline.fixture",
        "cat.agent_framework.fixture",
        "cat.tool.fixture",
        "cat.mcp_server.fixture",
        "cat.memory_store.fixture",
        "cat.integration.fixture",
        "cat.training_framework.fixture",
        "cat.training_compute.fixture",
        "cat.training_dataset.fixture",
        "cat.fine_tuned_model.fixture",
        "cat.guardrail.fixture",
        "cat.evaluation_suite.fixture",
        "cat.deployment_target.fixture",
        "cat.monitoring_stack.fixture",
        "cat.cost_policy.fixture",
    ]
    static let componentVersions: Set<String> = ["2026.10-demo"]
    static func contains(_ request: SourceUseRequest) -> Bool {
        identifiers.contains(request.sourceID) || identifiers.contains(request.claimID)
            || identifiers.contains(request.snapshotID) || componentVersions.contains(request.sourceVersion)
    }
}
