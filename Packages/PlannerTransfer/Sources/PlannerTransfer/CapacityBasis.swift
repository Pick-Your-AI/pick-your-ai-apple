import Foundation

/// Named originals are retained categories, not evidence eligibility or publisher attestation.
public enum CapacityInputKind: String, Sendable {
    case catalog, answers, hardware, deployment, workloadStages, engineBuilds
    case normalization, sourcePolicy, qualification
}

public struct CapacityInput: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let maximumBytes = 256 * 1024
    public let name: String
    public let kind: CapacityInputKind
    public let originalBytes: Data
    public let sha256: String
    public var description: String { "CapacityInput" }
    public var debugDescription: String { description }

    public init(name: String, kind: CapacityInputKind, originalBytes: Data,
                declaredSHA256: String? = nil) throws {
        try capacityIdentity(name)
        guard originalBytes.count <= Self.maximumBytes else { throw CapacityError.unsupportedNativeLimit }
        let hash = try capacityDigest(originalBytes)
        try capacityCheckDigest(declaredSHA256, actual: hash)
        self.name = name; self.kind = kind; self.originalBytes = originalBytes; sha256 = hash
    }
}

public struct CapacitySelection: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let kind: String
    public let enabled: Bool
    public let catalogItemID: String
    public let catalogItemVersion: String
    public var description: String { "CapacitySelection" }
    public var debugDescription: String { description }
}

public struct CapacityLink: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let fromSelectionID: String
    public let toSelectionID: String
    public let relation: String
    public let recordedRequired: Bool?
    public var description: String { "CapacityLink" }
    public var debugDescription: String { description }
}

/// Complete original basis for one opt-in operation; changed valid bytes invalidate old qualification.
public struct CapacityBasis: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let profile = "apple-capacity-receiving/0.1"
    public static let logicalProfile = "cd2-physical-pools/0.1.0"
    public static let maximumInputs = 32
    public static let maximumTotalBytes = 2 * 1024 * 1024
    public static let maximumSelections = 512
    public static let maximumLinks = 1024
    public let operation: String
    public let normalizationPolicy: String
    public let sourcePolicy: String
    public let originalBuildBytes: Data
    public let originalBuildSHA256: String
    public let buildID: String
    public let buildRevision: Decimal
    public let selections: [CapacitySelection]
    public let links: [CapacityLink]
    public let catalogInputName: String?
    public let catalogMatchesBuild: Bool
    public let sha256: String
    private let selectionIndex: [Data: CapacitySelection]
    private let inputIndex: [Data: CapacityInput]
    private let catalogItems: [[Data]: JSONValue]
    public var description: String { "CapacityBasis" }
    public var debugDescription: String { description }
    public var inputNames: [String] {
        inputIndex.keys.sorted(by: { $0.lexicographicallyPrecedes($1) })
            .map { String(decoding: $0, as: UTF8.self) }
    }

    public init(originalBuildBytes: Data, operation: String, normalizationPolicy: String,
                sourcePolicy: String, inputs: [CapacityInput], catalogInputName: String? = nil,
                declaredBuildSHA256: String? = nil) throws {
        for value in [operation, normalizationPolicy, sourcePolicy] { try capacityIdentity(value) }
        guard originalBuildBytes.count <= CapacityInput.maximumBytes,
              inputs.count <= Self.maximumInputs,
              originalBuildBytes.count + inputs.reduce(0, { $0 + $1.originalBytes.count }) <= Self.maximumTotalBytes else {
            throw CapacityError.unsupportedNativeLimit
        }
        var inputIndex: [Data: CapacityInput] = [:]
        for input in inputs {
            guard inputIndex.updateValue(input, forKey: Data(input.name.utf8)) == nil else {
                throw CapacityError.duplicateIdentity
            }
        }
        guard inputIndex[Data(normalizationPolicy.utf8)]?.kind == .normalization,
              inputIndex[Data(sourcePolicy.utf8)]?.kind == .sourcePolicy else { throw CapacityError.invalidIdentity }
        let buildHash = try capacityDigest(originalBuildBytes)
        try capacityCheckDigest(declaredBuildSHA256, actual: buildHash)
        let build: BuildSnapshot
        do { build = try BuildTransfer.snapshot(fromDraftJSON: originalBuildBytes) }
        catch { throw CapacityError.invalidFrozenBuild }
        guard let object = build.value.object, let id = object["id"]?.string,
              let revision = object["revision"]?.number, let selected = object["selections"]?.array,
              let rawLinks = object["links"]?.array,
              let catalogLock = object["locks"]?.object?["catalog_snapshot_id"]?.string else {
            throw CapacityError.invalidFrozenBuild
        }
        guard selected.count <= Self.maximumSelections, rawLinks.count <= Self.maximumLinks else {
            throw CapacityError.unsupportedNativeLimit
        }
        var selections: [CapacitySelection] = [], selectionIndex: [Data: CapacitySelection] = [:]
        for value in selected {
            guard let fields = value.object, let id = fields["id"]?.string,
                  let kind = fields["kind"]?.string, let enabledValue = fields["enabled"],
                  case .bool(let enabled) = enabledValue,
                  let item = fields["catalog_item_id"]?.string, let version = fields["catalog_item_version"]?.string else {
                throw CapacityError.invalidFrozenBuild
            }
            let selection = CapacitySelection(id: id, kind: kind, enabled: enabled,
                                               catalogItemID: item, catalogItemVersion: version)
            guard selectionIndex.updateValue(selection, forKey: Data(id.utf8)) == nil else {
                throw CapacityError.duplicateIdentity
            }
            selections.append(selection)
        }
        var links: [CapacityLink] = [], linkIDs = Set<Data>()
        for value in rawLinks {
            guard let fields = value.object, let id = fields["id"]?.string,
                  let from = fields["from_selection_id"]?.string, let to = fields["to_selection_id"]?.string,
                  let relation = fields["relation"]?.string else { throw CapacityError.invalidFrozenBuild }
            guard linkIDs.insert(Data(id.utf8)).inserted else { throw CapacityError.duplicateIdentity }
            guard selectionIndex[Data(from.utf8)] != nil, selectionIndex[Data(to.utf8)] != nil else {
                throw CapacityError.danglingReference
            }
            let required: Bool?
            if let value = fields["required"] {
                guard case .bool(let flag) = value else { throw CapacityError.invalidFrozenBuild }
                required = flag
            } else { required = nil }
            links.append(CapacityLink(id: id, fromSelectionID: from, toSelectionID: to,
                                      relation: relation, recordedRequired: required))
        }
        var catalogMatches = false, items: [[Data]: JSONValue] = [:]
        if let catalogInputName {
            try capacityIdentity(catalogInputName)
            guard let input = inputIndex[Data(catalogInputName.utf8)], input.kind == .catalog else {
                throw CapacityError.invalidFrozenCatalog
            }
            let value: JSONValue
            do {
                var parser = try JSONParser(input.originalBytes)
                value = try parser.parse()
                let validator = try FrozenValidator(schemaNames: ["catalog-snapshot", "catalog-item", "common"])
                guard let schema = validator.schemas["catalog-snapshot.schema.json"] else {
                    throw CapacityError.invalidFrozenCatalog
                }
                try validator.check(value, schema: schema, document: "catalog-snapshot.schema.json")
            } catch { throw CapacityError.invalidFrozenCatalog }
            guard let fields = value.object, let catalogID = fields["id"]?.string,
                  let entries = fields["items"]?.array else { throw CapacityError.invalidFrozenCatalog }
            catalogMatches = contextExact(catalogID, catalogLock)
            for item in entries {
                guard let itemID = item.object?["id"]?.string, let version = item.object?["version"]?.string else {
                    throw CapacityError.invalidFrozenCatalog
                }
                guard items.updateValue(item, forKey: [Data(itemID.utf8), Data(version.utf8)]) == nil else {
                    throw CapacityError.duplicateIdentity
                }
            }
        }
        var parts = [Data(Self.profile.utf8), Data(Self.logicalProfile.utf8), Data(operation.utf8),
                     Data(normalizationPolicy.utf8), Data(sourcePolicy.utf8), originalBuildBytes,
                     Data([catalogInputName == nil ? 0 : 1]), Data((catalogInputName ?? "").utf8)]
        for key in inputIndex.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            guard let input = inputIndex[key] else { throw CapacityError.invalidIdentity }
            parts += [key, Data(input.kind.rawValue.utf8), input.originalBytes]
        }
        self.operation = operation; self.normalizationPolicy = normalizationPolicy; self.sourcePolicy = sourcePolicy
        self.originalBuildBytes = originalBuildBytes; originalBuildSHA256 = buildHash
        buildID = id; buildRevision = revision; self.selections = selections; self.links = links
        self.catalogInputName = catalogInputName; catalogMatchesBuild = catalogMatches
        self.inputIndex = inputIndex; self.selectionIndex = selectionIndex; catalogItems = items
        sha256 = try capacityKey(parts)
    }

    public func input(named name: String) -> CapacityInput? {
        guard name.utf8.count <= 4096 else { return nil }
        return inputIndex[Data(name.utf8)]
    }
    public func selection(id: String) -> CapacitySelection? {
        guard id.utf8.count <= 4096 else { return nil }
        return selectionIndex[Data(id.utf8)]
    }
    /// Exact selected version only; missing catalog scope cannot fall back to an item ID.
    public func catalogItem(forSelectionID id: String) -> JSONValue? {
        guard catalogMatchesBuild, let selection = selection(id: id) else { return nil }
        return catalogItems[[Data(selection.catalogItemID.utf8), Data(selection.catalogItemVersion.utf8)]]
    }
}
