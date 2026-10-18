import Foundation

public enum PriceMeter: String, Codable, CaseIterable, Sendable {
    case inputTokens1M = "input_tokens_1m", outputTokens1M = "output_tokens_1m"
    case cachedInputTokens1M = "cached_input_tokens_1m", embeddingTokens1M = "embedding_tokens_1m"
    case request, gpuHour = "gpu_hour", cpuHour = "cpu_hour", storageGBMonth = "storage_gb_month"
    case vectorGBMonth = "vector_gb_month", agentRun = "agent_run", seatMonth = "seat_month"
    case licenseMonth = "license_month", oneTime = "one_time"
}
public enum PriceType: String, Codable, Sendable { case list, contract, estimate }
public enum PriceVerification: String, Codable, Sendable {
    case verified, userSupplied = "user_supplied", estimated, unverified
}

// Syntactic absolute ASCII URI boundary; no network fetch, trust or source-use assertion.
private func priceSourceURI(_ value: String) -> Bool {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
    guard !value.isEmpty, value.unicodeScalars.allSatisfy({ allowed.contains($0) }),
          contractMatches(value, "\\A[A-Za-z][A-Za-z0-9+.-]*:"),
          value.range(of: "%[^0-9A-Fa-f]|%[0-9A-Fa-f](?:[^0-9A-Fa-f]|$)|%$", options: .regularExpression) == nil,
          URLComponents(string: value)?.scheme != nil,
          URLComponents(string: value)?.url?.absoluteString == value else { return false }
    return true
}

private struct PricebookWire: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let revision: Int
    public let capturedAt: String
    public let rates: [PriceRate]
    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id = "id"
        case revision = "revision"
        case capturedAt = "captured_at"
        case rates = "rates"
    }
    public init(from decoder: Decoder) throws {
        try contractKeys(decoder, ["schema_version", "id", "revision", "captured_at", "rates"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        id = try c.decode(String.self, forKey: .id)
        revision = try c.decode(Int.self, forKey: .revision)
        capturedAt = try c.decode(String.self, forKey: .capturedAt)
        rates = try c.decode([PriceRate].self, forKey: .rates)

        guard schemaVersion == "1.0.0", contractID(id), revision >= 1,
              contractTimestamp(capturedAt), !rates.isEmpty
        else { throw contractReject(decoder, "Invalid frozen-v1 pricebook identity, version, timestamp or empty rates") }
    }
}

public struct PriceRate: Codable, Equatable, Sendable {
    public let id: String
    public let catalogItemID: String
    public let catalogItemVersion: String
    public let meter: PriceMeter
    public let region: String?
    public let unitPrice: ContractMoney
    public let validFrom: String
    public let validUntil: String?
    public let provenance: PriceProvenance
    public let conditions: [String]?
    public let priceType: PriceType
    private enum CodingKeys: String, CodingKey {
        case id = "id"
        case catalogItemID = "catalog_item_id"
        case catalogItemVersion = "catalog_item_version"
        case meter = "meter"
        case region = "region"
        case unitPrice = "unit_price"
        case validFrom = "valid_from"
        case validUntil = "valid_until"
        case provenance = "provenance"
        case conditions = "conditions"
        case priceType = "price_type"
    }
    public init(from decoder: Decoder) throws {
        try contractKeys(decoder, ["id", "catalog_item_id", "catalog_item_version", "meter", "region", "unit_price", "valid_from", "valid_until", "provenance", "conditions", "price_type"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        catalogItemID = try c.decode(String.self, forKey: .catalogItemID)
        catalogItemVersion = try c.decode(String.self, forKey: .catalogItemVersion)
        meter = try c.decode(PriceMeter.self, forKey: .meter)
        region = c.contains(.region) ? try c.decode(String.self, forKey: .region) : nil
        unitPrice = try c.decode(ContractMoney.self, forKey: .unitPrice)
        validFrom = try c.decode(String.self, forKey: .validFrom)
        validUntil = c.contains(.validUntil) ? try c.decode(String.self, forKey: .validUntil) : nil
        provenance = try c.decode(PriceProvenance.self, forKey: .provenance)
        conditions = c.contains(.conditions) ? try c.decode([String].self, forKey: .conditions) : nil
        priceType = try c.decode(PriceType.self, forKey: .priceType)

        guard contractID(id), contractID(catalogItemID), !catalogItemVersion.isEmpty,
              contractTimestamp(validFrom), validUntil.map(contractTimestamp) ?? true
        else { throw contractReject(decoder, "Invalid frozen-v1 rate identity, version or timestamp") }
    }
}

public struct PriceProvenance: Codable, Equatable, Sendable {
    public let sourceURI: String?
    public let checkedAt: String
    public let verificationStatus: PriceVerification
    public let notes: String?
    private enum CodingKeys: String, CodingKey {
        case sourceURI = "source_uri"
        case checkedAt = "checked_at"
        case verificationStatus = "verification_status"
        case notes = "notes"
    }
    public init(from decoder: Decoder) throws {
        try contractKeys(decoder, ["source_uri", "checked_at", "verification_status", "notes"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceURI = c.contains(.sourceURI) ? try c.decode(String.self, forKey: .sourceURI) : nil
        checkedAt = try c.decode(String.self, forKey: .checkedAt)
        verificationStatus = try c.decode(PriceVerification.self, forKey: .verificationStatus)
        notes = c.contains(.notes) ? try c.decode(String.self, forKey: .notes) : nil

        guard contractTimestamp(checkedAt), sourceURI.map(priceSourceURI) ?? true
        else { throw contractReject(decoder, "Invalid provenance timestamp or absolute ASCII source URI") }
    }
}

/// Frozen-v1 pricebook transport, not a pricing evaluator or a live quote.
/// Provenance absence/unverified state is preserved without promoting trust.
public struct Pricebook: Encodable, Equatable, Sendable {
    public enum BoundaryError: Error, Equatable, Sendable { case payloadTooLarge }
    public static let maximumPayloadBytes = 4 * 1024 * 1024
    public let schemaVersion: String
    public let id: String
    public let revision: Int
    public let capturedAt: String
    public let rates: [PriceRate]
    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id = "id"
        case revision = "revision"
        case capturedAt = "captured_at"
        case rates = "rates"
    }
    private init(_ wire: PricebookWire) {
        schemaVersion = wire.schemaVersion
        id = wire.id
        revision = wire.revision
        capturedAt = wire.capturedAt
        rates = wire.rates
    }
    /// Integers use Int; decimal strings retain their spelling and arbitrary integer
    /// precision. Timestamps use Gregorian years 0001...9999 without leap seconds.
    /// These and the byte bound are client limits, not changes to frozen v1.
    public static func decode(_ data: Data) throws -> Pricebook {
        guard data.count <= maximumPayloadBytes else { throw BoundaryError.payloadTooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw ContractJSONError.invalidUTF8 }
        try ContractJSONPreflight.validate(text)
        return try Pricebook(JSONDecoder().decode(PricebookWire.self, from: data))
    }
}
