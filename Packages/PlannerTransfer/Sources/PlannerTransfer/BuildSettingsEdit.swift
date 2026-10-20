import Foundation
import PlannerCore

/// A field from the bundled frozen contract, not a caller-defined JSON path.
/// Its definition describes representation and admission, not compatibility or
/// catalog-specific capability. No unit conversion or default is supplied.
public struct BuildEditableField: Sendable {
    public enum Scope: Equatable, Sendable {
        case selection(CatalogKind)
        case objectives
    }
    public enum ValueType: String, Sendable {
        case string, integer, number, boolean, array
    }
    public let scope: Scope
    public let name: String
    public let valueType: ValueType
    public let required: Bool
    public let definition: JSONValue
    fileprivate let schema: JSONValue
    fileprivate let document: String

    /// Stable UTF-8 name order. An empty settings object has no editable fields.
    public static func settings(for kind: CatalogKind) throws -> [Self] {
        try fields(scope: .selection(kind))
    }
    public static func objectives() throws -> [Self] {
        try fields(scope: .objectives)
    }
    private static func fields(scope: Scope) throws -> [Self] {
        let validator = try FrozenValidator()
        let document: String
        let container: JSONValue?
        switch scope {
        case .selection(let kind):
            document = "selection.schema.json"
            container = validator.schemas[document]?.object?["$defs"]?.object?["settings_" + kind.rawValue]
        case .objectives:
            document = "build.schema.json"
            container = validator.schemas[document]?.object?["properties"]?.object?["objectives"]
        }
        guard let container = container?.object,
              container["additionalProperties"] == .bool(false),
              let properties = container["properties"]?.object else { throw TransferError.unavailableSchema }
        let required = container["required"]?.array ?? []
        return try properties.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { name in
            let schema = properties[name]!
            let definition = try resolve(schema, document: document, validator: validator)
            guard let type = definition.object?["type"]?.string,
                  let valueType = ValueType(rawValue: type) else { throw TransferError.unavailableSchema }
            return Self(scope: scope, name: name, valueType: valueType,
                        required: required.contains(.string(name)), definition: definition,
                        schema: schema, document: document)
        }
    }
    /// Only the fixed bundled references are used. The original schema remains
    /// the validator input; this resolution supplies display metadata only.
    private static func resolve(_ schema: JSONValue, document: String, validator: FrozenValidator) throws -> JSONValue {
        guard let ref = schema.object?["$ref"]?.string else { return schema }
        let parts = ref.split(separator: "#", omittingEmptySubsequences: false)
        let file = parts[0].isEmpty ? document : String(parts[0])
        guard parts.count == 2, var target = validator.schemas[file] else { throw TransferError.unavailableSchema }
        for key in parts[1].split(separator: "/") {
            guard let next = target.object?[String(key)] else { throw TransferError.unavailableSchema }
            target = next
        }
        guard target.object?["$ref"] == nil else { throw TransferError.unavailableSchema }
        return target
    }
}

/// The existing bounded JSON decoder admits the supplied value before an edit
/// can retain it. A missing property uses `remove`, distinct from JSON null.
public struct BuildEditValue: Equatable, Sendable {
    public let value: JSONValue
    public init(json: Data) throws {
        var parser = try JSONParser(json)
        value = try parser.parse()
    }
}

public enum BuildFieldChange: Sendable {
    case set(BuildEditableField, BuildEditValue)
    case remove(BuildEditableField)
    fileprivate var field: BuildEditableField {
        switch self { case .set(let field, _), .remove(let field): field }
    }
}

public enum BuildSettingsTarget: Sendable {
    case selectionSettings(selectionID: String)
    case objectives
}

/// Resolved before/after inputs belong to the caller. Settings, names and this
/// Apple client never infer a deployment or production decision here.
public struct BuildEditEnvironment: Equatable, Sendable {
    public let mode: DependencyInvalidation.Mode?
    public let production: Bool?
    public init(mode: DependencyInvalidation.Mode?, production: Bool?) {
        self.mode = mode; self.production = production
    }
}

public enum BuildSettingsEditError: Error, Equatable, Sendable {
    case emptyChanges, duplicateField, fieldScopeMismatch, requiredField
    case missingSelection, ambiguousSelectionIdentity, unchangedValues
    case graphMismatch, unsupportedRevision
}

public enum BuildSettingsImpact: Sendable {
    /// Direct participation only; inactive/unknown is not an evaluator verdict.
    case selection(DependencyParticipantPlan)
    /// Frozen v1 supplies no field-level objective dependency map. Do not infer
    /// that unrelated old-revision results can be retained as current.
    case objectivesRequireFullRecheck
}

/// An immutable, uncommitted proposal. All analysis bound to the prior Build
/// revision must be retired from current presentation after a successful save.
/// The direct graph preview is not permission to reuse old-revision results.
/// The native owner still supplies current ownership/session identity and uses
/// an expected-revision durable write; this value has no writer or saved state.
public struct BuildSettingsEdit: Sendable {
    public let original: BuildSnapshot
    public let proposed: BuildSnapshot
    public let graph: DependencyGraph
    public let target: BuildSettingsTarget
    public let changedFieldNames: [String]
    public let beforeEnvironment: BuildEditEnvironment
    public let afterEnvironment: BuildEditEnvironment
    public let impact: BuildSettingsImpact

    public static func prepare(
        build: BuildSnapshot, graph: DependencyGraph, target: BuildSettingsTarget,
        changes: [BuildFieldChange], before: BuildEditEnvironment, after: BuildEditEnvironment,
        updatedAt: String
    ) throws -> Self {
        guard !changes.isEmpty else { throw BuildSettingsEditError.emptyChanges }
        let locks = build.locks.object!
        guard locks["dependency_graph_id"] == .string(graph.id),
              locks["dependency_graph_revision"] == .number(graph.revision) else {
            throw BuildSettingsEditError.graphMismatch
        }
        var object = build.value.object!
        var selections = object["selections"]!.array!
        var seen = Set<Data>()
        for selection in selections {
            guard seen.insert(Data(selection.object!["id"]!.string!.utf8)).inserted else {
                throw BuildSettingsEditError.ambiguousSelectionIdentity
            }
        }
        let scope: BuildEditableField.Scope
        let selectedIndex: Int?
        var values: [String: JSONValue]
        switch target {
        case .selectionSettings(let id):
            guard let index = selections.firstIndex(where: { $0.object!["id"] == .string(id) }) else {
                throw BuildSettingsEditError.missingSelection
            }
            let selection = selections[index].object!
            scope = .selection(CatalogKind(rawValue: selection["kind"]!.string!)!)
            selectedIndex = index; values = selection["settings"]!.object!
        case .objectives:
            scope = .objectives; selectedIndex = nil; values = object["objectives"]!.object!
        }
        let validator = try FrozenValidator()
        var fields = Set<Data>()
        var changed: [String] = []
        for change in changes {
            let field = change.field
            guard field.scope == scope else { throw BuildSettingsEditError.fieldScopeMismatch }
            guard fields.insert(Data(field.name.utf8)).inserted else { throw BuildSettingsEditError.duplicateField }
            switch change {
            case .set(_, let input):
                try validator.check(input.value, schema: field.schema, document: field.document)
                if values[field.name] != input.value { values[field.name] = input.value; changed.append(field.name) }
            case .remove:
                guard !field.required else { throw BuildSettingsEditError.requiredField }
                if values.removeValue(forKey: field.name) != nil { changed.append(field.name) }
            }
        }
        guard !changed.isEmpty else { throw BuildSettingsEditError.unchangedValues }
        if let index = selectedIndex {
            var selection = selections[index].object!
            selection["settings"] = .object(values); selections[index] = .object(selection)
            object["selections"] = .array(selections)
        } else { object["objectives"] = .object(values) }
        var revision = object["revision"]!.number!, one = Decimal(1), next = Decimal()
        guard NSDecimalAdd(&next, &revision, &one, .plain) == .noError, next > revision else {
            throw BuildSettingsEditError.unsupportedRevision
        }
        object["revision"] = .number(next)
        object["updated_at"] = .string(updatedAt)
        object["lifecycle"] = .string("draft")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let proposed = try BuildTransfer.snapshot(fromDraftJSON: encoder.encode(JSONValue.object(object)))
        let impact: BuildSettingsImpact
        if case .selection(let kind) = scope {
            impact = .selection(graph.affectedParticipants(changedKinds: [kind],
                before: build.dependencyContext(mode: before.mode, production: before.production),
                after: proposed.dependencyContext(mode: after.mode, production: after.production)))
        } else { impact = .objectivesRequireFullRecheck }
        return Self(original: build, proposed: proposed, graph: graph, target: target,
                    changedFieldNames: changed, beforeEnvironment: before, afterEnvironment: after, impact: impact)
    }
}
