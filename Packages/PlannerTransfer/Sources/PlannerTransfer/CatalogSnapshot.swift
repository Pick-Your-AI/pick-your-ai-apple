import Foundation

/// An immutable frozen-v1 catalog envelope. Structural validation grants no
/// publication, source-use, compatibility, freshness or cache-activation authority.
public struct CatalogSnapshot: Sendable, Equatable {
    private static let validator = try? FrozenValidator(schemaNames: ["catalog-snapshot", "catalog-item", "common"])
    public let value: JSONValue
    public let items: [CatalogItem]
    private init(value: JSONValue, items: [CatalogItem]) { self.value = value; self.items = items }

    public var id: String { value.object!["id"]!.string! }
    public var revision: Decimal { value.object!["revision"]!.number! }
    public var capturedAt: String { value.object!["captured_at"]!.string! }

    /// Applies the existing byte/depth/node/numeric limits to the entire document
    /// before validating its envelope and every item. No partial catalog escapes.
    /// Order and duplicate identities are preserved: graph/release consumers must
    /// apply their own identity policy rather than silently dropping source facts.
    public static func decode(_ data: Data) throws -> Self {
        var parser = try JSONParser(data)
        let value = try parser.parse()
        guard let validator = Self.validator else { throw TransferError.unavailableSchema }
        try validator.validateCatalogSnapshot(value)
        guard let values = value.object?["items"]?.array else { throw TransferError.schemaViolation }
        let items = try values.map { try CatalogItem.validatingParsedValue($0) }
        return Self(value: value, items: items)
    }

    /// Local serialization only. Recheck the exact bytes because normalization can
    /// expand otherwise valid compact input beyond the same reopening bounds.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        var parser = try JSONParser(data)
        guard try parser.parse() == value else { throw TransferError.unsupportedNumber }
        return data
    }
}
