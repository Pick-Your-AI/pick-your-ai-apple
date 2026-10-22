import Foundation

/// An immutable frozen-v1 declaration. Status, approvals, evidence references and
/// deployment references are reported input, not verified authority or execution.
public struct DeploymentManifest: Sendable, Equatable {
    private static let validator = try? FrozenValidator(schemaNames: ["deployment-manifest", "common"])
    public let value: JSONValue
    public let approvals: [JSONValue]

    private init(value: JSONValue, approvals: [JSONValue]) {
        self.value = value
        self.approvals = approvals
    }

    public var id: String { value.object!["id"]!.string! }
    public var buildID: String { value.object!["build_id"]!.string! }
    public var buildRevision: Decimal { value.object!["build_revision"]!.number! }
    public var deploymentTargetSelectionID: String { value.object!["deployment_target_selection_id"]!.string! }
    public var status: String { value.object!["status"]!.string! }

    /// Apply the existing byte/depth/node/numeric and duplicate-key limits to the
    /// whole input before the unchanged schema. Every admitted declaration stays
    /// intact, including contradictory approval/status fields and optional absence.
    public static func decode(_ data: Data) throws -> Self {
        var parser = try JSONParser(data)
        let value = try parser.parse()
        guard value.object?["schema_version"] == .string("1.0.0") else {
            throw TransferError.unsupportedVersion
        }
        guard let validator = Self.validator,
              let schema = validator.schemas["deployment-manifest.schema.json"] else {
            throw TransferError.unavailableSchema
        }
        try validator.check(value, schema: schema, document: "deployment-manifest.schema.json")
        guard let approvals = value.object?["approvals"]?.array else { throw TransferError.schemaViolation }
        return Self(value: value, approvals: approvals)
    }

    /// Private local serialization, not redaction or public sharing. Return only
    /// bytes that reopen under the same limits with every admitted value unchanged.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        var parser = try JSONParser(data)
        guard try parser.parse() == value else { throw TransferError.unsupportedNumber }
        return data
    }
}
