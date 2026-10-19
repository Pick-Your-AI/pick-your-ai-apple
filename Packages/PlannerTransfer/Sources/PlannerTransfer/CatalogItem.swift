import Foundation

/// Exact frozen-v1 kind identities; tier and kind-specific spec rules are validated
/// by the unchanged bundled catalog-item schema, never inferred from display names.
public enum CatalogKind: String, CaseIterable, Hashable, Sendable {
    case workload
    case deploymentMode = "deployment_mode"
    case modelProvider = "model_provider"
    case model
    case contextPolicy = "context_policy"
    case hostingPlatform = "hosting_platform"
    case accelerator
    case computeProfile = "compute_profile"
    case inferenceEngine = "inference_engine"
    case storage
    case dataSource = "data_source"
    case knowledgeBase = "knowledge_base"
    case embeddingModel = "embedding_model"
    case vectorDatabase = "vector_database"
    case ragPipeline = "rag_pipeline"
    case agentFramework = "agent_framework"
    case tool
    case mcpServer = "mcp_server"
    case memoryStore = "memory_store"
    case integration
    case trainingFramework = "training_framework"
    case trainingCompute = "training_compute"
    case trainingDataset = "training_dataset"
    case fineTunedModel = "fine_tuned_model"
    case guardrail
    case evaluationSuite = "evaluation_suite"
    case deploymentTarget = "deployment_target"
    case monitoringStack = "monitoring_stack"
    case costPolicy = "cost_policy"
}

/// An immutable catalog fact, not a user selection or an approved catalog release.
/// Only the bounded schema-validating decode boundary can construct this value.
public struct CatalogItem: Sendable, Equatable {
    private static let validator = try? FrozenValidator(schemaNames: ["catalog-item", "common"])
    public let value: JSONValue
    public let kind: CatalogKind
    private init(value: JSONValue, kind: CatalogKind) { self.value = value; self.kind = kind }

    public var id: String { value.object!["id"]!.string! }
    public var name: String { value.object!["name"]!.string! }
    public var version: String { value.object!["version"]!.string! }
    public var tier: String { value.object!["tier"]!.string! }
    public var status: String { value.object!["status"]!.string! }
    public var billingClass: String { value.object!["billing_class"]!.string! }
    public var spec: [String: JSONValue] { value.object!["spec"]!.object! }

    /// Preserves all supported fields, including optional provenance and namespaced
    /// extensions. Schema validity confers no rights, compatibility or freshness.
    public static func decode(_ data: Data) throws -> Self {
        var parser = try JSONParser(data)
        let value = try parser.parse()
        guard let validator = Self.validator else { throw TransferError.unavailableSchema }
        try validator.validateCatalogItem(value)
        guard let rawKind = value.object?["kind"]?.string,
              let kind = CatalogKind(rawValue: rawKind) else { throw TransferError.schemaViolation }
        return Self(value: value, kind: kind)
    }

    /// Local serialization only; not a source-use approval or sanitized sharing API.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        // Normalization can expand valid compact input past the byte/number bounds.
        // Validate the exact output before returning locally persistable bytes.
        var parser = try JSONParser(data)
        guard try parser.parse() == value else { throw TransferError.unsupportedNumber }
        return data
    }
}
