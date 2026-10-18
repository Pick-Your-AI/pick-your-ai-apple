import Foundation

/// An immutable frozen-v1 external estimate artifact. Structural validation does
/// not verify the estimator, accept its confidence, measure quality or bind it to
/// the currently visible build. Receiving policy must validate the complete tuple.
public struct ResourceEstimate: Sendable, Equatable {
    private static let validator = try? FrozenValidator(schemaNames: ["resource-estimate", "common"])
    public let value: JSONValue
    public let estimates: [JSONValue]
    private init(value: JSONValue, estimates: [JSONValue]) { self.value = value; self.estimates = estimates }

    public var id: String { value.object!["id"]!.string! }
    public var buildID: String { value.object!["build_id"]!.string! }
    public var buildRevision: Decimal { value.object!["build_revision"]!.number! }
    public var generatedAt: String { value.object!["generated_at"]!.string! }

    /// Applies aggregate byte/depth/node/numeric and duplicate-key bounds before
    /// checking the unchanged canonical schema. Decimal values stay exact strings;
    /// order, assumptions, selection IDs and optional source absence are retained.
    public static func decode(_ data: Data) throws -> Self {
        var parser = try JSONParser(data)
        let value = try parser.parse()
        guard let validator = Self.validator else { throw TransferError.unavailableSchema }
        try validator.validateResourceEstimate(value)
        guard let estimates = value.object?["estimates"]?.array else { throw TransferError.schemaViolation }
        return Self(value: value, estimates: estimates)
    }

    /// Return only bytes that reopen under the same limits without changing the
    /// artifact's values. This local serialization does not create evidence.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        var parser = try JSONParser(data)
        guard try parser.parse() == value else { throw TransferError.unsupportedNumber }
        return data
    }
}
