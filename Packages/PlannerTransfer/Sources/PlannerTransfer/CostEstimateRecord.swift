import Foundation

/// Reported labels from a frozen-v1 estimate; decoding does not assess coverage.
public enum CostEstimateCoverage: String, CaseIterable, Hashable, Sendable {
    case complete, partial, unknown
}

/// The recorded usage meter, without an inferred unit conversion or rate.
public enum CostEstimateMeter: String, CaseIterable, Hashable, Sendable {
    case inputTokens1M = "input_tokens_1m"
    case outputTokens1M = "output_tokens_1m"
    case cachedInputTokens1M = "cached_input_tokens_1m"
    case embeddingTokens1M = "embedding_tokens_1m"
    case request
    case gpuHour = "gpu_hour"
    case cpuHour = "cpu_hour"
    case storageGBMonth = "storage_gb_month"
    case vectorGBMonth = "vector_gb_month"
    case agentRun = "agent_run"
    case seatMonth = "seat_month"
    case licenseMonth = "license_month"
    case oneTime = "one_time"
}

public enum CostEstimateMethod: String, CaseIterable, Hashable, Sendable {
    case measured
    case workloadProjection = "workload_projection"
    case vendorQuote = "vendor_quote"
    case manualOverride = "manual_override"
}

public enum CostEstimateConfidence: String, CaseIterable, Hashable, Sendable {
    case high, medium, low
}

/// Exact recorded decimal text and currency, not a calculated monetary value.
public struct CostEstimateMoney: Sendable, Equatable {
    public let value: JSONValue
    fileprivate init(value: JSONValue) { self.value = value }

    /// Retains all supported digits and trailing zeros; never parsed as Double or Decimal.
    public var amount: String { value.object!["amount"]!.string! }
    public var currency: String { value.object!["currency"]!.string! }
}

/// One immutable recorded item. Its labels and arithmetic are not authenticated.
public struct CostEstimateLineItem: Sendable, Equatable {
    public let value: JSONValue
    fileprivate init(value: JSONValue) { self.value = value }

    public var id: String { value.object!["id"]!.string! }
    public var selectionID: String { value.object!["selection_id"]!.string! }
    public var priceRateID: String { value.object!["price_rate_id"]!.string! }
    public var meter: CostEstimateMeter { CostEstimateMeter(rawValue: value.object!["meter"]!.string!)! }
    public var quantity: String { value.object!["quantity"]!.string! }
    public var unitPrice: CostEstimateMoney { CostEstimateMoney(value: value.object!["unit_price"]!) }
    public var amount: CostEstimateMoney { CostEstimateMoney(value: value.object!["amount"]!) }
    public var method: CostEstimateMethod { CostEstimateMethod(rawValue: value.object!["method"]!.string!)! }
    public var confidence: CostEstimateConfidence { CostEstimateConfidence(rawValue: value.object!["confidence"]!.string!)! }
    public var assumptions: [String] { value.object!["assumptions"]!.array!.map { $0.string! } }
}

/// A bounded, structurally valid frozen-v1 record. It neither prices usage nor
/// verifies rate applicability, coverage, arithmetic, build binding or provenance.
public struct CostEstimateRecord: Sendable, Equatable {
    private static let validator = try? FrozenValidator(schemaNames: ["cost-estimate", "common"])
    public let value: JSONValue
    private init(value: JSONValue) { self.value = value }

    public var id: String { value.object!["id"]!.string! }
    public var buildID: String { value.object!["build_id"]!.string! }
    /// Exact positive integral Decimal within the existing JSON numeric subset.
    public var buildRevision: Decimal { value.object!["build_revision"]!.number! }
    public var pricebookID: String { value.object!["pricebook_id"]!.string! }
    public var estimatedAt: String { value.object!["estimated_at"]!.string! }
    public var periodDays: Decimal { value.object!["period_days"]!.number! }
    public var currency: String { value.object!["currency"]!.string! }
    public var lineItems: [CostEstimateLineItem] {
        value.object!["line_items"]!.array!.map { CostEstimateLineItem(value: $0) }
    }
    public var subtotal: CostEstimateMoney { CostEstimateMoney(value: value.object!["subtotal"]!) }
    public var tax: CostEstimateMoney { CostEstimateMoney(value: value.object!["tax"]!) }
    public var total: CostEstimateMoney { CostEstimateMoney(value: value.object!["total"]!) }
    public var coverage: CostEstimateCoverage { CostEstimateCoverage(rawValue: value.object!["coverage"]!.string!)! }
    public var unpricedSelectionIDs: [String] { value.object!["unpriced_selection_ids"]!.array!.map { $0.string! } }
    public var warnings: [String] { value.object!["warnings"]!.array!.map { $0.string! } }

    public static func decode(_ data: Data) throws -> Self {
        var parser = try JSONParser(data)
        let value = try parser.parse()
        guard let validator = Self.validator else { throw TransferError.unavailableSchema }
        try validator.validateCostEstimate(value)
        return Self(value: value)
    }

    /// Local serialization with the same parser limits and exact semantic value.
    /// This retains private text; it does not sanitize or authorize publication.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        var parser = try JSONParser(data)
        guard try parser.parse() == value else { throw TransferError.unsupportedNumber }
        return data
    }
}
