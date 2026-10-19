import Foundation

public enum DependencyRelationship: String, CaseIterable, Sendable {
    case requires, constrains, informs, produces
}

public enum DependencyActivation: String, CaseIterable, Sendable {
    case always
    case selfHosted = "self_hosted"
    case nonAPI = "non_api"
    case ragEnabled = "rag_enabled"
    case agentsEnabled = "agents_enabled"
    case fineTuningEnabled = "fine_tuning_enabled"
    case ifSelected = "if_selected"
    case productionOnly = "production_only"
}

/// One directed frozen-v1 relationship. The activation is an uninterpreted source
/// label; decoding does not activate an edge or approve compatibility policy.
public struct DependencyEdge: Sendable, Equatable {
    public let id: String
    public let dependentKind: CatalogKind
    public let dependsOnKind: CatalogKind
    public let relationship: DependencyRelationship
    public let activation: DependencyActivation
    public let rationale: String

    fileprivate init(_ value: JSONValue) throws {
        guard let fields = value.object,
              let id = fields["id"]?.string,
              let rawDependent = fields["dependent_kind"]?.string,
              let dependent = CatalogKind(rawValue: rawDependent),
              let rawDependency = fields["depends_on_kind"]?.string,
              let dependency = CatalogKind(rawValue: rawDependency),
              let rawRelationship = fields["relationship"]?.string,
              let relationship = DependencyRelationship(rawValue: rawRelationship),
              let rawActivation = fields["activation"]?.string,
              let activation = DependencyActivation(rawValue: rawActivation),
              let rationale = fields["rationale"]?.string else { throw TransferError.schemaViolation }
        self.id = id
        dependentKind = dependent
        dependsOnKind = dependency
        self.relationship = relationship
        self.activation = activation
        self.rationale = rationale
    }
}

/// An immutable, structurally validated frozen-v1 graph. Order, repeated identities
/// and self/cyclic relationships are retained because the schema does not reject
/// them. Consumers must qualify executable graph policy separately.
public struct DependencyGraph: Sendable, Equatable {
    private static let validator = try? FrozenValidator(schemaNames: ["dependency-graph", "common"])
    public let value: JSONValue
    public let edges: [DependencyEdge]
    private init(value: JSONValue, edges: [DependencyEdge]) { self.value = value; self.edges = edges }

    public var id: String { value.object!["id"]!.string! }
    public var revision: Decimal { value.object!["revision"]!.number! }

    /// Applies the shared byte/depth/node/numeric limits to the complete document
    /// before validating every field. A malformed edge rejects the entire graph.
    public static func decode(_ data: Data) throws -> Self {
        var parser = try JSONParser(data)
        let value = try parser.parse()
        guard value.object?["schema_version"] == .string("1.0.0") else { throw TransferError.unsupportedVersion }
        guard let validator = Self.validator,
              let schema = validator.schemas["dependency-graph.schema.json"] else { throw TransferError.unavailableSchema }
        try validator.check(value, schema: schema, document: "dependency-graph.schema.json")
        guard let values = value.object?["edges"]?.array else { throw TransferError.schemaViolation }
        return Self(value: value, edges: try values.map(DependencyEdge.init))
    }

    /// Local serialization only; no sharing or source-use authority is conferred.
    /// Reparse exact output so normalization cannot return unreopenable bytes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        var parser = try JSONParser(data)
        guard try parser.parse() == value else { throw TransferError.unsupportedNumber }
        return data
    }
}
