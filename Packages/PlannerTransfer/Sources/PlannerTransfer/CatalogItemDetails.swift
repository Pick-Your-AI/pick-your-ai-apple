import Foundation

/// The types present in the unchanged frozen-v1 catalog specifications. Array
/// elements retain their order; this display projection performs no conversion.
public enum CatalogDetailFieldType: String, Equatable, Sendable {
    case string, number, integer, boolean
    case stringArray = "array of strings"
}

/// Missing, empty and explicitly unknown facts remain distinct from supplied
/// false and zero. A supplied value is still only a declaration, not evidence.
public enum CatalogDetailValueState: Equatable, Sendable {
    case missing, explicitUnknown, emptyText, emptyCollection, containsUnknown, supplied
}

public struct CatalogDetailField: Equatable, Sendable {
    public let name: String
    public let type: CatalogDetailFieldType
    public let value: JSONValue?
    public let state: CatalogDetailValueState

    fileprivate init(name: String, definition: JSONValue, value: JSONValue?) throws {
        self.name = name
        switch definition.object?["type"]?.string {
        case "string": type = .string
        case "number": type = .number
        case "integer": type = .integer
        case "boolean": type = .boolean
        case "array" where definition.object?["items"]?.object?["type"]?.string == "string":
            type = .stringArray
        default: throw TransferError.unavailableSchema
        }
        self.value = value
        switch value {
        case nil: state = .missing
        case .some(.string("unknown")): state = .explicitUnknown
        case .some(.string("")): state = .emptyText
        case .some(.array(let items)) where items.isEmpty: state = .emptyCollection
        case .some(.array(let items)) where items.contains(.string("unknown")) || items.contains(.string("")):
            state = .containsUnknown
        default: state = .supplied
        }
    }
}

/// Raw frozen provenance only. A declared "verified" status is never promoted
/// to an inspected or independently verified display grade by this projection.
/// A syntactically valid source URI is not authorization to open that URI.
public struct CatalogDetailProvenance: Equatable, Sendable, CustomStringConvertible {
    public let sourceURI: String?
    public let checkedAt: String
    public let originalVerificationStatus: String
    public let notes: String?

    fileprivate init(_ value: JSONValue) throws {
        guard let fields = value.object,
              let checkedAt = fields["checked_at"]?.string,
              let status = fields["verification_status"]?.string else {
            throw TransferError.schemaViolation
        }
        sourceURI = fields["source_uri"]?.string
        self.checkedAt = checkedAt
        originalVerificationStatus = status
        notes = fields["notes"]?.string
    }

    public var description: String { "CatalogDetailProvenance" }
}

/// An immutable typed projection of one already validated catalog item. It
/// preserves the exact item and every source record, and enumerates optional
/// fields from the same bundled schema used by the decoder. It does not choose
/// a current version, join a provider offering, assess a source, or infer prices.
public struct CatalogItemDetails: Equatable, Sendable, CustomStringConvertible {
    private static let schema = try? FrozenValidator(schemaNames: ["catalog-item", "common"])
        .schemas["catalog-item.schema.json"]

    public let item: CatalogItem
    public let specifications: [CatalogDetailField]
    public let license: [CatalogDetailField]
    public let provenance: [CatalogDetailProvenance]
    public let descriptionText: String?
    public let updatedAt: String

    /// CatalogItem has no unchecked public initializer. The original byte,
    /// depth, node, numeric and schema boundaries therefore precede projection.
    public init(item: CatalogItem) throws {
        guard let schema = Self.schema,
              let definitions = schema.object?["$defs"]?.object,
              let specification = definitions["spec_" + item.kind.rawValue]?.object?["properties"]?.object,
              let licenseDefinition = schema.object?["properties"]?.object?["license"]?.object?["properties"]?.object,
              let value = item.value.object,
              let sources = value["provenance"]?.array,
              let updatedAt = value["updated_at"]?.string else { throw TransferError.unavailableSchema }

        func fields(_ definitions: [String: JSONValue], _ values: [String: JSONValue]) throws -> [CatalogDetailField] {
            try definitions.keys.sorted().map { key in
                try CatalogDetailField(name: key, definition: definitions[key]!, value: values[key])
            }
        }
        self.item = item
        specifications = try fields(specification, item.spec)
        license = try fields(licenseDefinition, value["license"]?.object ?? [:])
        provenance = try sources.map(CatalogDetailProvenance.init)
        descriptionText = value["description"]?.string
        self.updatedAt = updatedAt
    }

    public var description: String { "CatalogItemDetails" }
}
