import Foundation

/// The original source identity is displayed for each side; a comparison never
/// changes either snapshot or treats a fork as its source revision.
public struct ComparedBuildIdentity: Equatable, Sendable {
    public let id: String
    public let revision: String
    public let name: String
    fileprivate init(_ snapshot: BuildSnapshot) {
        id = snapshot.id; name = snapshot.name
        revision = NSDecimalNumber(decimal: snapshot.value.object!["revision"]!.number!).stringValue
    }
}

/// Absent is distinct from a present zero, false, empty collection or null. Hidden
/// values retain no private payload in the comparison result or its diagnostics.
public enum ComparedFieldValue: Equatable, Sendable {
    case absent
    case hidden
    case value(JSONValue)
}

public struct BuildDifference: Equatable, Sendable {
    /// Local display coordinates, not a replacement wire format or JSON Pointer.
    /// Selection/link IDs occupy their own path segment, so punctuation is unambiguous.
    public let path: [String]
    public let selectionKind: String?
    /// Display grouping from canonical docs/CONTRACT_MAPPING.md. No dependency,
    /// capability or inclusion rule is inferred from a tier label.
    public var tier: String? {
        switch selectionKind {
        case "workload", "deployment_mode": return "T0"
        case "model_provider", "model", "context_policy": return "T1"
        case "hosting_platform", "accelerator", "compute_profile", "inference_engine", "storage": return "T2"
        case "data_source", "knowledge_base", "embedding_model", "vector_database", "rag_pipeline": return "T3"
        case "agent_framework", "tool", "mcp_server", "memory_store", "integration": return "T4"
        case "training_framework", "training_compute", "training_dataset", "fine_tuned_model": return "T5"
        case "guardrail", "evaluation_suite", "deployment_target", "monitoring_stack", "cost_policy": return "T6"
        default: return nil
        }
    }
    public let before: ComparedFieldValue
    public let after: ComparedFieldValue
}

public enum BuildComparisonError: Error, Equatable, Sendable {
    case ambiguousSelectionIdentity, ambiguousLinkIdentity, conflictingRevisionIdentity
    case tooManyDifferences
}

public struct BuildComparison: Equatable, Sendable {
    public let before: ComparedBuildIdentity
    public let after: ComparedBuildIdentity
    public let differences: [BuildDifference]
    /// This boundary compares configuration only. No measurement or estimate is
    /// inferred, transplanted, ranked or treated as current from imported metadata.
    public var evidenceNotice: String {
        "Quality, capacity, compatibility, and cost are not compared. Each build needs its own qualified evidence with matching workload, versions, units, and conditions. Missing evidence is unknown."
    }
    public static let maximumDifferences = 2_048

    /// Both inputs must already have passed the frozen-v1 snapshot boundary.
    /// Selection and link ordering has no semantic effect; their canonical IDs do.
    public static func compare(_ before: BuildSnapshot, _ after: BuildSnapshot) throws -> BuildComparison {
        let left = before.value.object!, right = after.value.object!
        let leftSelections = try keyed(left["selections"]!, error: .ambiguousSelectionIdentity)
        let rightSelections = try keyed(right["selections"]!, error: .ambiguousSelectionIdentity)
        let leftLinks = try keyed(left["links"]!, error: .ambiguousLinkIdentity)
        let rightLinks = try keyed(right["links"]!, error: .ambiguousLinkIdentity)
        var leftMetadata = left, rightMetadata = right
        leftMetadata.removeValue(forKey: "selections"); leftMetadata.removeValue(forKey: "links")
        rightMetadata.removeValue(forKey: "selections"); rightMetadata.removeValue(forKey: "links")
        if before.id == after.id, left["revision"] == right["revision"],
           leftMetadata != rightMetadata || leftSelections != rightSelections || leftLinks != rightLinks {
            throw BuildComparisonError.conflictingRevisionIdentity
        }
        var differences: [BuildDifference] = []
        // Owner, timestamps, lifecycle claims, names and extensions are not evidence
        // or configuration. Names and identities are available separately above.
        for key in ["objectives", "locks", "policy"] {
            try compareValue(left[key], right[key], path: [key], kind: nil, fieldName: key, output: &differences)
        }
        for id in Set(leftSelections.keys).union(rightSelections.keys).sorted() {
            let a = leftSelections[id], b = rightSelections[id]
            // If the kind itself changes, its before/after values remain a diff row.
            let kind = b?.object?["kind"]?.string ?? a?.object?["kind"]?.string
            try compareValue(a, b, path: ["selections", id], kind: kind, fieldName: nil, output: &differences)
        }
        for id in Set(leftLinks.keys).union(rightLinks.keys).sorted() {
            try compareValue(leftLinks[id], rightLinks[id], path: ["links", id], kind: nil, fieldName: nil, output: &differences)
        }
        return BuildComparison(before: ComparedBuildIdentity(before), after: ComparedBuildIdentity(after), differences: differences)
    }

    private static func keyed(_ value: JSONValue, error: BuildComparisonError) throws -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for item in value.array! {
            let id = item.object!["id"]!.string!
            // Frozen schema validity alone does not guarantee unique graph IDs.
            // Reject ambiguity instead of crashing or silently taking the last row.
            guard result.updateValue(item, forKey: id) == nil else { throw error }
        }
        return result
    }

    private static func compareValue(_ before: JSONValue?, _ after: JSONValue?, path: [String],
                                     kind: String?, fieldName: String?, output: inout [BuildDifference]) throws {
        guard before != after else { return }
        // Display paths also contain record IDs. Only actual field names carry
        // privacy semantics; an ID such as "notes" must not hide a whole record.
        if let key = fieldName {
            // Private annotations have no role in structural comparison. Do not expose
            // their values, child keys, presence, measurements or apparent authority.
            if ["notes", "extensions", "owner_ref"].contains(key) { return }
            if privateKey(key) {
                try append(before == nil ? .absent : .hidden, after == nil ? .absent : .hidden,
                           path: path, kind: kind, output: &output)
                return
            }
        }
        let leftObject = before?.object, rightObject = after?.object
        if (leftObject != nil || before == nil), (rightObject != nil || after == nil),
           leftObject != nil || rightObject != nil {
            let a = leftObject ?? [:], b = rightObject ?? [:]
            let keys = Set(a.keys).union(b.keys).sorted()
            if !keys.isEmpty {
                for child in keys {
                    try compareValue(a[child], b[child], path: path + [child], kind: kind, fieldName: child, output: &output)
                }
                return
            }
        }
        try append(displayValue(before), displayValue(after), path: path, kind: kind, output: &output)
    }

    private static func displayValue(_ value: JSONValue?) -> ComparedFieldValue {
        guard let value else { return .absent }
        return containsPrivateReference(value) ? .hidden : .value(value)
    }
    private static func privateKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
        return ["account_ref", "encryption_key_ref", "approval_ticket", "index_name", "endpoint", "api_base_url", "weights_uri", "artifact_uri"].contains(key) ||
            ["secret", "password", "credential", "apikey", "authorization", "accesstoken", "refreshtoken"].contains(where: normalized.contains)
    }
    private static func containsPrivateReference(_ value: JSONValue) -> Bool {
        switch value {
        case .string(let text): return text.lowercased().contains("secret://")
        case .object(let object): return object.contains { privateKey($0.key) || containsPrivateReference($0.value) }
        case .array(let array): return array.contains(where: containsPrivateReference)
        default: return false
        }
    }
    private static func append(_ before: ComparedFieldValue, _ after: ComparedFieldValue, path: [String],
                               kind: String?, output: inout [BuildDifference]) throws {
        guard output.count < maximumDifferences else { throw BuildComparisonError.tooManyDifferences }
        output.append(BuildDifference(path: path, selectionKind: kind, before: before, after: after))
    }
}
