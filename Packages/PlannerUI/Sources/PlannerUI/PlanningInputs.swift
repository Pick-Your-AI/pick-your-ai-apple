import Foundation
import PlannerCore
import PlannerTransfer

/// Local editor fields. Raw, incomplete input never becomes a frozen Build by saving a draft.
public enum PlanningInputField: String, CaseIterable, Hashable, Sendable {
    case region, currency
    case dataClassification = "data_classification"
    case monthlyBudgetAmount = "monthly_budget_amount"
    case requestsPerDay = "requests_per_day"
    case averageInputTokens = "avg_input_tokens"
    case averageOutputTokens = "avg_output_tokens"
    case maximumConcurrency = "max_concurrency"
    case maximumLatencyMilliseconds = "max_latency_ms"

    public var title: String {
        switch self {
        case .region: "Region"
        case .currency: "Currency code"
        case .dataClassification: "Data classification"
        case .monthlyBudgetAmount: "Monthly budget amount"
        case .requestsPerDay: "Requests per day"
        case .averageInputTokens: "Average input tokens per request"
        case .averageOutputTokens: "Average output tokens per request"
        case .maximumConcurrency: "Maximum concurrent requests"
        case .maximumLatencyMilliseconds: "Maximum latency in milliseconds"
        }
    }

    public var unansweredMessage: String {
        switch self {
        case .region: "Unanswered. Region restrictions cannot be applied."
        case .currency: "Unanswered. A budget cannot be interpreted without its currency."
        case .dataClassification: "Unanswered. Data classification restrictions cannot be applied."
        case .monthlyBudgetAmount: "Unanswered. No budget limit is assumed."
        case .requestsPerDay, .averageInputTokens, .averageOutputTokens:
            "Unanswered. Usage is unknown; no zero usage is assumed."
        case .maximumConcurrency: "Unanswered. No concurrency requirement is assumed."
        case .maximumLatencyMilliseconds: "Unanswered. No latency requirement is assumed."
        }
    }

    public func state(of raw: String) -> PlanningInputState {
        guard !raw.isEmpty else { return .unanswered }
        switch self {
        case .region:
            // The frozen contract accepts a nonempty string. Do not invent a region allowlist.
            return .supplied
        case .currency:
            return raw.utf8.count == 3 && raw.utf8.allSatisfy { (65...90).contains($0) }
                ? .supplied : .invalid("Use three uppercase letters, such as USD. Your text is preserved.")
        case .dataClassification:
            return ["public", "internal", "confidential", "restricted"].contains(raw)
                ? .supplied : .invalid("Use public, internal, confidential, or restricted. Your text is preserved.")
        case .monthlyBudgetAmount:
            return (try? ContractDecimal(raw)) != nil ? .supplied
                : .invalid("Use a nonnegative amount, with a decimal point for fractional amounts and at most 12 decimal places; omit symbols and separators. Your text is preserved.")
        case .requestsPerDay, .averageInputTokens, .averageOutputTokens,
             .maximumConcurrency, .maximumLatencyMilliseconds:
            let digits = raw.utf8
            let positive = self == .maximumConcurrency || self == .maximumLatencyMilliseconds
            guard digits.allSatisfy({ (48...57).contains($0) }),
                  !positive || digits.contains(where: { $0 != 48 }) else {
                return .invalid(positive
                    ? "Use a whole number of at least 1 in the stated unit; omit separators and unit text. Your text is preserved."
                    : "Use a whole number of at least 0 in the stated unit; omit separators and unit text. Your text is preserved.")
            }
            // No Int/Double conversion or ungoverned maximum: the frozen integer schema has none.
            return .supplied
        }
    }
}

public enum PlanningInputState: Equatable, Sendable {
    case unanswered, supplied, invalid(String)
}

public enum PlanningCatalogKind: String, Codable, CaseIterable, Hashable, Sendable {
    case workload
    case deploymentMode = "deployment_mode"
    public var title: String { self == .workload ? "Workload" : "Deployment mode" }
}

/// A retained local reference to an explicitly chosen catalog fact, not a Build Selection.
/// The frozen mode lives in a deployment_mode item; it is never inferred from this Apple client.
public struct PlanningCatalogReference: Codable, Equatable, Sendable {
    public let kind: PlanningCatalogKind
    public let itemID: String
    public let itemVersion: String
    public let name: String
    public let catalogSchemaVersion: String
    public let catalogID: String
    public let catalogRevision: Int
    public let capturedAt: String
    public let sha256: String

    init(_ pinned: CatalogPinnedDetails) throws {
        let item = pinned.details.item
        guard let kind = PlanningCatalogKind(rawValue: item.kind.rawValue), item.tier == "T0",
              pinned.snapshot.schemaVersion == "1.0.0" else { throw DraftInputFormatError.unsupported }
        self.kind = kind; itemID = item.id; itemVersion = item.version; name = item.name
        catalogSchemaVersion = pinned.snapshot.schemaVersion
        catalogID = pinned.snapshot.id; catalogRevision = pinned.snapshot.revision
        capturedAt = pinned.snapshot.capturedAt; sha256 = pinned.sha256
        try validate()
    }

    private func validate() throws {
        guard !itemID.isEmpty, itemID.utf8.count <= 256,
              !itemVersion.isEmpty, itemVersion.utf8.count <= 128,
              !name.isEmpty, name.utf8.count <= 1_024,
              catalogSchemaVersion == "1.0.0",
              !catalogID.isEmpty, catalogID.utf8.count <= 256, catalogRevision >= 1,
              !capturedAt.isEmpty, capturedAt.utf8.count <= 128,
              sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw DraftInputFormatError.unsupported
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, itemID, itemVersion, name, catalogSchemaVersion, catalogID, catalogRevision, capturedAt, sha256
    }
    public init(from decoder: any Decoder) throws {
        try requireDraftKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)),
                             required: Set(CodingKeys.allCases.map(\.rawValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(PlanningCatalogKind.self, forKey: .kind)
        itemID = try container.decode(String.self, forKey: .itemID)
        itemVersion = try container.decode(String.self, forKey: .itemVersion)
        name = try container.decode(String.self, forKey: .name)
        catalogSchemaVersion = try container.decode(String.self, forKey: .catalogSchemaVersion)
        catalogID = try container.decode(String.self, forKey: .catalogID)
        catalogRevision = try container.decode(Int.self, forKey: .catalogRevision)
        capturedAt = try container.decode(String.self, forKey: .capturedAt)
        sha256 = try container.decode(String.self, forKey: .sha256)
        try validate()
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.catalogRevision == rhs.catalogRevision &&
        zip(lhs.textParts, rhs.textParts).allSatisfy { pair in pair.0.utf8.elementsEqual(pair.1.utf8) }
    }
    private var textParts: [String] { [itemID, itemVersion, name, catalogSchemaVersion, catalogID, capturedAt, sha256] }
    var byteCount: Int { textParts.reduce(kind.rawValue.utf8.count + 8) { $0 + $1.utf8.count } }
}

struct PlanningCatalogChoice: Equatable, Sendable {
    let reference: PlanningCatalogReference
    let declaration: String
    init(_ pinned: CatalogPinnedDetails) throws {
        reference = try PlanningCatalogReference(pinned)
        let key = reference.kind == .workload ? "workload_type" : "mode"
        guard case .string(let value)? = pinned.details.item.spec[key] else {
            throw DraftInputFormatError.unsupported
        }
        declaration = value
    }
}

public struct PlanningInputs: Codable, Equatable, Sendable {
    private var values: [String: String] = [:]
    public private(set) var workload: PlanningCatalogReference?
    public private(set) var deploymentMode: PlanningCatalogReference?
    public init() {}

    public subscript(_ field: PlanningInputField) -> String {
        get { values[field.rawValue] ?? "" }
        set { values[field.rawValue] = newValue }
    }
    public func reference(for kind: PlanningCatalogKind) -> PlanningCatalogReference? {
        kind == .workload ? workload : deploymentMode
    }
    @discardableResult
    public mutating func select(_ reference: PlanningCatalogReference?, for kind: PlanningCatalogKind) -> Bool {
        guard reference == nil || reference?.kind == kind else { return false }
        if kind == .workload { workload = reference } else { deploymentMode = reference }
        return true
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.values.count == rhs.values.count && lhs.values.allSatisfy { key, value in
            rhs.values[key].map { value.utf8.elementsEqual($0.utf8) } == true
        } && lhs.workload == rhs.workload && lhs.deploymentMode == rhs.deploymentMode
    }
    var byteCount: Int {
        values.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
            + (workload?.byteCount ?? 0) + (deploymentMode?.byteCount ?? 0)
    }
    func hasSameRawValue(as other: Self, field: PlanningInputField) -> Bool {
        switch (values[field.rawValue], other.values[field.rawValue]) {
        case (nil, nil): true
        case (.some(let a), .some(let b)): a.utf8.elementsEqual(b.utf8)
        default: false
        }
    }
    mutating func restoreRawValue(from other: Self, field: PlanningInputField) {
        values[field.rawValue] = other.values[field.rawValue]
    }

    private enum CodingKeys: String, CodingKey { case values, workload, deploymentMode }
    public init(from decoder: any Decoder) throws {
        try requireDraftKeys(decoder, allowed: ["values", "workload", "deploymentMode"], required: ["values"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        values = try container.decode([String: String].self, forKey: .values)
        guard Set(values.keys).isSubset(of: Set(PlanningInputField.allCases.map(\.rawValue))) else {
            throw DraftInputFormatError.unsupported
        }
        workload = try container.decodeIfPresent(PlanningCatalogReference.self, forKey: .workload)
        deploymentMode = try container.decodeIfPresent(PlanningCatalogReference.self, forKey: .deploymentMode)
        guard workload == nil || workload?.kind == .workload,
              deploymentMode == nil || deploymentMode?.kind == .deploymentMode else {
            throw DraftInputFormatError.unsupported
        }
    }
}

enum DraftInputFormatError: Error { case unsupported }
private struct DraftInputKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
func requireDraftKeys(_ decoder: any Decoder, allowed: Set<String>, required: Set<String>) throws {
    let container = try decoder.container(keyedBy: DraftInputKey.self)
    let keys = Set(container.allKeys.map(\.stringValue))
    guard keys.isSubset(of: allowed), required.isSubset(of: keys) else { throw DraftInputFormatError.unsupported }
}
