import Foundation

/// One source-to-field reference finding. Fields are public catalog identifiers and
/// frozen-v1 spec field names, never free-form payload text.
public struct CatalogReferenceViolation: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The target identity resolves to exactly one item, of a different kind.
        case wrongKind(actual: CatalogKind)
        /// References carry an identity and no version, so more than one item with that
        /// identity (same or different version) leaves the target undetermined. The kinds
        /// of every candidate are listed in snapshot order, so a mismatch is not masked.
        case ambiguous(candidateKinds: [CatalogKind])
        /// No item in the snapshot has the target identity.
        case unresolved
        /// The reference value or array element is not a string. Unreachable while the
        /// frozen schema types these fields as strings; kept so a relaxed schema cannot
        /// turn a malformed reference into a silent pass.
        case malformedReference
    }

    public let sourceItemID: String
    public let sourceKind: CatalogKind
    public let field: String
    /// Zero-based position within an array-valued field; nil for a scalar field.
    public let elementIndex: Int?
    /// Nil only for `.malformedReference`.
    public let targetID: String?
    public let expectedKind: CatalogKind
    public let reason: Reason
}

/// Every reference violation found in one catalog snapshot, in deterministic order
/// (item order, then sorted field name, then array index). The whole snapshot is rejected.
public struct CatalogReferenceRejection: Error, Equatable, Sendable {
    /// The report keeps at most this many violations; the rest are counted, not listed.
    public static let maximumReportedViolations = 64

    public let violations: [CatalogReferenceViolation]
    public let omittedViolationCount: Int
}

/// Within-snapshot reference policy for frozen-v1 catalog items. The unchanged
/// catalog-item schema documents each reference field's target kind in a description
/// only, so structural validation alone accepts a reference to the wrong kind.
///
/// Every reference must resolve to exactly one item of the documented kind. A target
/// absent from the snapshot is rejected, not treated as unknown-but-acceptable. This is
/// an adopted conservative policy, not a canonical-contract rule: see
/// `CATALOG_REFERENCE_REJECTIONS.md` for the evidence and the open decision.
/// Pricebook rate references and any pair-level check are outside this policy.
public enum CatalogReferenceIntegrity {
    /// Mirrors the "Reference to catalog kind ..." descriptions in the bundled
    /// catalog-item schema. `license_ref` is a plain string there and is not listed.
    static let expectedKinds: [String: CatalogKind] = [
        "provider_ref": .modelProvider,
        "accelerator_ref": .accelerator,
        "accelerator_refs": .accelerator,
        "hosting_ref": .hostingPlatform,
        "data_source_refs": .dataSource,
        "tool_refs": .tool,
        "associated_tool_refs": .tool,
        "compute_profile_ref": .computeProfile,
        "storage_ref": .storage,
        "base_model_ref": .model,
        "training_framework_ref": .trainingFramework,
        "training_dataset_ref": .trainingDataset,
        "dataset_refs": .trainingDataset
    ]

    /// Throws one `CatalogReferenceRejection` listing all violations (up to the report
    /// cap) when any exist. No partial catalog is produced.
    public static func validate(_ snapshot: CatalogSnapshot) throws {
        var candidates: [String: [CatalogKind]] = [:]
        for item in snapshot.items { candidates[item.id, default: []].append(item.kind) }
        var violations: [CatalogReferenceViolation] = []
        var total = 0
        for item in snapshot.items {
            let spec = item.spec
            for field in spec.keys.sorted() {
                guard let expected = expectedKinds[field], let value = spec[field] else { continue }
                var elements: [(Int?, JSONValue)] = []
                if let list = value.array {
                    for (index, element) in list.enumerated() { elements.append((index, element)) }
                } else {
                    elements.append((nil, value))
                }
                for (index, element) in elements {
                    let target = element.string
                    let reason: CatalogReferenceViolation.Reason?
                    if let target {
                        let kinds = candidates[target] ?? []
                        if kinds.isEmpty { reason = .unresolved }
                        else if kinds.count > 1 { reason = .ambiguous(candidateKinds: kinds) }
                        else if kinds[0] != expected { reason = .wrongKind(actual: kinds[0]) }
                        else { reason = nil }
                    } else {
                        reason = .malformedReference
                    }
                    guard let reason else { continue }
                    total += 1
                    if violations.count < CatalogReferenceRejection.maximumReportedViolations {
                        violations.append(CatalogReferenceViolation(
                            sourceItemID: item.id, sourceKind: item.kind, field: field,
                            elementIndex: index, targetID: target, expectedKind: expected, reason: reason))
                    }
                }
            }
        }
        if total > 0 {
            throw CatalogReferenceRejection(violations: violations, omittedViolationCount: total - violations.count)
        }
    }
}
