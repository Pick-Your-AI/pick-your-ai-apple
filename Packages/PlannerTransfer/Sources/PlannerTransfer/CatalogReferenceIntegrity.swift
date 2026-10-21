import Foundation

/// A source-to-field rejection for one catalog reference. Fields are public catalog
/// identifiers and frozen-v1 spec field names, never free-form payload text.
public struct CatalogReferenceRejection: Error, Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The target identity resolves to exactly one item, but of a different kind.
        case wrongKind(actual: CatalogKind)
        /// References carry an identity and no version, so more than one item with
        /// that identity (same or different version) leaves the target undetermined.
        case ambiguous(candidateCount: Int)
    }

    public let sourceItemID: String
    public let sourceKind: CatalogKind
    public let field: String
    public let targetID: String
    public let expectedKind: CatalogKind
    public let reason: Reason
}

/// Within-snapshot reference policy for frozen-v1 catalog items. The unchanged
/// catalog-item schema documents each reference field's target kind in a description
/// only, so structural validation alone accepts a reference to the wrong kind.
///
/// Targets absent from the snapshot are not judged here: this policy neither passes
/// nor rejects them, and a receiving release/graph policy must decide. Pricebook
/// rate references and any pair-level check are likewise outside this policy.
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

    /// Throws the first rejection in item order, then sorted field name, then array
    /// order. The whole snapshot is rejected; no partial catalog is produced.
    public static func validate(_ snapshot: CatalogSnapshot) throws {
        var candidates: [String: [CatalogKind]] = [:]
        for item in snapshot.items { candidates[item.id, default: []].append(item.kind) }
        for item in snapshot.items {
            let spec = item.spec
            for field in spec.keys.sorted() {
                guard let expected = expectedKinds[field], let value = spec[field] else { continue }
                let targets = value.string.map { [$0] } ?? (value.array ?? []).compactMap { $0.string }
                for target in targets {
                    guard let kinds = candidates[target] else { continue }
                    let reason: CatalogReferenceRejection.Reason?
                    if kinds.count > 1 { reason = .ambiguous(candidateCount: kinds.count) }
                    else if let actual = kinds.first, actual != expected { reason = .wrongKind(actual: actual) }
                    else { reason = nil }
                    if let reason {
                        throw CatalogReferenceRejection(sourceItemID: item.id, sourceKind: item.kind,
                                                        field: field, targetID: target,
                                                        expectedKind: expected, reason: reason)
                    }
                }
            }
        }
    }
}
