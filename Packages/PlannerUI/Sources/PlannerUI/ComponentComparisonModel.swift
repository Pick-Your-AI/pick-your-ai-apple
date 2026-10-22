import Foundation
import SwiftUI
import PlannerCatalog
import PlannerTransfer

public enum ComponentComparisonError: Error, Equatable, Sendable {
    case invalidCatalogPin, conflictingCatalog, conflictingRecord, selectionLimit, sourceUnavailable

    public var message: String {
        switch self {
        case .invalidCatalogPin: "This component has no usable exact catalog pin. Your comparison is preserved."
        case .conflictingCatalog: "Different bytes claimed the same catalog revision. Your existing comparison is preserved; this revision cannot be mixed."
        case .conflictingRecord: "Different content claimed the same component and catalog pin. The existing record is preserved; inspect the source before retrying."
        case .selectionLimit: "A comparison holds two to four components. Remove one before adding another."
        case .sourceUnavailable: "The exact component could not be added. Your comparison and browsing state are preserved; retry its details when ready."
        }
    }
}

/// Immutable input from a catalog consumer. The caller must establish membership
/// in these exact catalog bytes before constructing this value. A syntactically
/// valid pin alone is neither a membership proof nor production publication approval.
public struct ComponentComparisonCandidate: Identifiable, Equatable, Sendable, CustomStringConvertible {
    public struct ID: Hashable, Sendable {
        // UTF-8 identity keeps differently encoded versions and captured strings
        // distinct; Swift String's canonical Unicode equivalence is not a pin rule.
        fileprivate let parts: [Data]
    }

    public let details: CatalogItemDetails
    public let catalog: ArtifactPin
    public let id: ID
    /// Normalized item representation, not the original snapshot's byte hash.
    public let encodedItem: Data

    public init(item: CatalogItem, catalog: ArtifactPin) throws {
        let identity = catalog.identity
        guard catalog.kind == .catalog, identity.schemaVersion == "1.0.0",
              identity.id.range(of: #"\A[a-z][a-z0-9._:-]{2,119}\z"#, options: .regularExpression) != nil,
              identity.revision > 0, !identity.capturedAt.isEmpty, identity.capturedAt.utf8.count <= 128,
              catalog.sha256.range(of: #"\A[a-f0-9]{64}\z"#, options: .regularExpression) != nil else {
            throw ComponentComparisonError.invalidCatalogPin
        }
        details = try CatalogItemDetails(item: item)
        self.catalog = catalog
        encodedItem = try item.encoded()
        id = ID(parts: [item.id, item.version, item.kind.rawValue, identity.schemaVersion,
                       identity.id, String(identity.revision), identity.capturedAt, catalog.sha256]
            .map { Data($0.utf8) })
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.encodedItem == rhs.encodedItem
    }
    fileprivate var catalogVersion: [Data] {
        [catalog.identity.schemaVersion, catalog.identity.id, String(catalog.identity.revision)].map { Data($0.utf8) }
    }
    fileprivate var catalogBytes: [Data] {
        catalogVersion + [Data(catalog.identity.capturedAt.utf8), Data(catalog.sha256.utf8)]
    }
    fileprivate var itemVersion: [Data] { [Data(details.item.id.utf8), Data(details.item.version.utf8)] }
    public var description: String { "ComponentComparisonCandidate" }
}

public enum ComponentComparisonSection: String, CaseIterable, Identifiable, Sendable {
    case identity = "Identity and conditions"
    case specifications = "Recorded specifications"
    case license = "License declarations"
    case evidence = "Evidence and additional conditions"
    public var id: String { rawValue }
}

public enum ComponentComparisonAvailability: Equatable, Sendable {
    case notApplicable, missing, explicitUnknown, emptyText, emptyCollection, containsUnknown, recorded

    public var label: String {
        switch self {
        case .notApplicable: "Not applicable: this field is not defined for this component kind"
        case .missing: "Unknown: not recorded"
        case .explicitUnknown: "Unknown: explicitly recorded as unknown"
        case .emptyText: "Unknown: empty text recorded"
        case .emptyCollection: "Unknown: empty collection recorded"
        case .containsUnknown: "Contains unknown or empty entries; complete declaration retained"
        case .recorded: "Recorded declaration; not independently assessed"
        }
    }
    public var isUnknown: Bool { self != .recorded && self != .notApplicable }
}

public struct ComponentComparisonCell: Equatable, Sendable {
    public let type: String?
    public let availability: ComponentComparisonAvailability
    public let value: JSONValue?
    fileprivate let equalityBytes: Data?
    /// False only when a supplied value could not be encoded for comparison.
    /// A row containing such a cell always reports a difference and unknown information.
    public let isComparable: Bool

    /// `encode` is a test seam; production callers use the normalized encoder.
    init(type: String?, value: JSONValue?, applicable: Bool = true,
         encode: (JSONValue) throws -> Data = { try ComponentComparisonText.encoder().encode($0) }) {
        self.type = type; self.value = value
        if !applicable { availability = .notApplicable }
        else {
            switch value {
            case nil: availability = .missing
            case .some(.string("unknown")): availability = .explicitUnknown
            case .some(.string("")): availability = .emptyText
            case .some(.array(let values)) where values.isEmpty: availability = .emptyCollection
            case .some(.object(let values)) where values.isEmpty: availability = .emptyCollection
            case .some(.array(let values)) where values.contains(.string("unknown")) || values.contains(.string("")):
                availability = .containsUnknown
            default: availability = .recorded
            }
        }
        // An absent value legitimately has no bytes. A supplied value whose
        // encoding fails must not collapse into that same nil state.
        if let value {
            let bytes = try? encode(value)
            equalityBytes = bytes; isComparable = bytes != nil
        } else {
            equalityBytes = nil; isComparable = true
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type && lhs.availability == rhs.availability
            && lhs.isComparable == rhs.isComparable && lhs.equalityBytes == rhs.equalityBytes
    }
}

/// Rows align exact field names and preserve each cell's declared type. This
/// reports declaration differences, never a numeric delta, rank or equivalence
/// between units, currencies, provider offerings or workload conditions.
public struct ComponentComparisonRow: Identifiable, Equatable, Sendable {
    public let section: ComponentComparisonSection
    public let field: String
    public let cells: [ComponentComparisonCell]
    public var id: String { section.rawValue + "/" + field }
    public var differs: Bool {
        guard let first = cells.first else { return false }
        // Unknown is not equal: a value that could not be compared is a difference.
        if cells.contains(where: { !$0.isComparable }) { return true }
        return cells.dropFirst().contains { $0 != first }
    }
    public var hasUnknown: Bool { cells.contains { $0.availability.isUnknown || !$0.isComparable } }
}

public struct ComponentComparisonInspection: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let candidate: ComponentComparisonCandidate
}

/// One local, read-only comparison session. The browser owns this model so that
/// opening/dismissing a comparison cannot reset search filters or inspected rows.
/// No catalog refresh, account, network, builder or durable draft writer enters it.
@MainActor
public final class ComponentComparisonModel: ObservableObject {
    public static let minimumSelection = 2
    public static let maximumSelection = 4
    @Published public private(set) var selections: [ComponentComparisonCandidate] = []
    @Published public private(set) var notice: ComponentComparisonError?
    @Published public private(set) var inspection: ComponentComparisonInspection?
    @Published public var differencesOnly = false
    @Published public var section: ComponentComparisonSection = .specifications

    public init() {}
    public var isReady: Bool { (Self.minimumSelection...Self.maximumSelection).contains(selections.count) }
    public func contains(_ candidate: ComponentComparisonCandidate) -> Bool {
        selections.contains(candidate)
    }

    @discardableResult
    public func add(_ candidate: ComponentComparisonCandidate) -> Bool {
        if selections.contains(where: { $0.catalogVersion == candidate.catalogVersion && $0.catalogBytes != candidate.catalogBytes }) {
            notice = .conflictingCatalog; return false
        }
        if let held = selections.first(where: { $0.catalogBytes == candidate.catalogBytes && $0.itemVersion == candidate.itemVersion }) {
            guard held == candidate else { notice = .conflictingRecord; return false }
            notice = nil; return true
        }
        guard selections.count < Self.maximumSelection else { notice = .selectionLimit; return false }
        selections.append(candidate); notice = nil
        return true
    }

    public func remove(_ id: ComponentComparisonCandidate.ID) {
        guard selections.contains(where: { $0.id == id }) else { return }
        selections.removeAll { $0.id == id }
        if inspection?.candidate.id == id { inspection = nil }
        notice = nil
    }

    public func clear() {
        selections = []; inspection = nil; notice = nil
        // Presentation preferences survive explicit selection reset.
    }

    public func reportUnavailable() { notice = .sourceUnavailable }
    public func dismissNotice() { notice = nil }

    public func inspect(_ id: ComponentComparisonCandidate.ID) {
        guard let candidate = selections.first(where: { $0.id == id }) else { return }
        inspection = ComponentComparisonInspection(id: UUID(), candidate: candidate)
    }

    public func closeInspection(_ id: UUID) {
        guard inspection?.id == id else { return }
        inspection = nil
    }

    public var rows: [ComponentComparisonRow] {
        guard isReady else { return [] }
        func object(_ value: JSONValue) -> [String: JSONValue] {
            if case .object(let values) = value { return values }; return [:]
        }
        let objects = selections.map { object($0.details.item.value) }
        var result: [ComponentComparisonRow] = []
        func append(_ group: ComponentComparisonSection, _ key: String, _ type: String) {
            result.append(ComponentComparisonRow(section: group, field: key,
                cells: objects.map { ComponentComparisonCell(type: type, value: $0[key]) }))
        }
        for key in ["schema_version", "id", "kind", "tier", "name", "version", "status", "billing_class", "updated_at"] {
            append(.identity, key, "string")
        }
        func appendFields(_ group: ComponentComparisonSection, _ fields: [[CatalogDetailField]]) {
            let names = Set(fields.flatMap { $0.map(\.name) }).sorted()
            for name in names {
                let cells = fields.map { itemFields -> ComponentComparisonCell in
                    guard let field = itemFields.first(where: { $0.name == name }) else {
                        return ComponentComparisonCell(type: nil, value: nil, applicable: false)
                    }
                    return ComponentComparisonCell(type: field.type.rawValue, value: field.value)
                }
                result.append(ComponentComparisonRow(section: group, field: name, cells: cells))
            }
        }
        appendFields(.specifications, selections.map { $0.details.specifications })
        appendFields(.license, selections.map { $0.details.license })
        append(.evidence, "description", "string")
        append(.evidence, "tags", "array of strings")
        append(.evidence, "provenance", "array of source records")
        append(.evidence, "extensions", "namespaced declarations; no inferred semantics")
        return result
    }

    public var visibleRows: [ComponentComparisonRow] {
        rows.filter { $0.section == section && (!differencesOnly || $0.differs) }
    }
}

/// Complete bounded-contract text, never Markdown or a navigation target. JSON
/// type/quotes and visible control escapes prevent values impersonating state
/// labels. No display truncation, localization, rounding or unit conversion occurs.
enum ComponentComparisonText {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
    static func literal(_ text: String) -> String { value(.string(text)) }
    static func value(_ value: JSONValue) -> String {
        guard let data = try? encoder().encode(value) else { return "Value unavailable" }
        return escapeControls(String(decoding: data, as: UTF8.self))
    }
    static func record(_ candidate: ComponentComparisonCandidate) -> String {
        escapeControls(String(decoding: candidate.encodedItem, as: UTF8.self))
    }
    private static func escapeControls(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                "\\u{" + String(scalar.value, radix: 16) + "}"
            default: String(scalar)
            }
        }.joined()
    }
}
