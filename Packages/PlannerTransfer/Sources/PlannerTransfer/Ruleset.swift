import Foundation

/// Immutable, structurally validated frozen-v1 rules. Decoding neither evaluates
/// expressions nor accepts the publisher, policy, compatibility or source rights.
public struct Ruleset: Sendable, Equatable {
    private static let validator = try? FrozenValidator(schemaNames: ["ruleset", "common"])
    public let value: JSONValue
    public let rules: [JSONValue]
    private init(value: JSONValue, rules: [JSONValue]) { self.value = value; self.rules = rules }

    public var id: String { value.object!["id"]!.string! }
    public var version: String { value.object!["version"]!.string! }
    public var publishedAt: String { value.object!["published_at"]!.string! }

    /// The parser bounds the entire artifact before schema validation. Every
    /// expression/operand must match exactly one frozen alternative. Rule order,
    /// repeated identities, literals and unknown-policy declarations are retained;
    /// a receiving evaluator remains responsible for its own accepted semantics.
    public static func decode(_ data: Data) throws -> Self {
        var parser = try JSONParser(data)
        let value = try parser.parse()
        guard let validator = Self.validator else { throw TransferError.unavailableSchema }
        try validator.validateRuleset(value)
        guard let rules = value.object?["rules"]?.array else { throw TransferError.schemaViolation }
        return Self(value: value, rules: rules)
    }

    /// Reopening must admit the exact normalized bytes without rounding or
    /// exceeding the same aggregate limits as the original input.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        var parser = try JSONParser(data)
        guard try parser.parse() == value else { throw TransferError.unsupportedNumber }
        return data
    }
}
