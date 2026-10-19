/// The frozen-v1 money boundary. This does not convert currencies or price usage.
public struct ContractMoney: Codable, Equatable, Sendable {
    public enum ValidationError: Error, Equatable { case invalidCurrency }
    public let amount: ContractDecimal
    public let currency: String

    static func validateCurrency(_ currency: String) throws {
        guard currency.utf8.count == 3, currency.utf8.allSatisfy({ (65...90).contains($0) }) else {
            throw ValidationError.invalidCurrency
        }
    }
    public init(amount: ContractDecimal, currency: String) throws {
        try Self.validateCurrency(currency)
        self.amount = amount
        self.currency = currency
    }
    private enum CodingKeys: String, CodingKey { case amount, currency }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: any Decoder) throws {
        let allFields = try decoder.container(keyedBy: AnyKey.self)
        guard allFields.allKeys.allSatisfy({ $0.stringValue == "amount" || $0.stringValue == "currency" }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected frozen-v1 money field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try values.decode(String.self, forKey: .currency)
        do { try Self.validateCurrency(currency) }
        catch { throw DecodingError.dataCorruptedError(forKey: .currency, in: values, debugDescription: "Expected three uppercase ASCII currency letters") }
        amount = try values.decode(ContractDecimal.self, forKey: .amount)
        self.currency = currency
    }
}

public enum CostCoverage: String, Codable, Sendable { case complete, partial, unknown }
public enum RateApplicability: Sendable { case current, expired, unknown }
public enum BudgetUnknownReason: Equatable, Sendable {
    case staleBuild, unsupportedPeriod, expiredRates, unverifiedRates
    case incompleteCoverage, unpricedSelections, unsupportedMeters, missingTotal, mixedCurrency
}
public enum BudgetAssessment: Equatable, Sendable {
    case satisfied, exceeded
    case unknown(BudgetUnknownReason)
}

/// Client-side assessment of an already-produced canonical estimate. These
/// fields are a projection, not a replacement cost-estimate wire contract.
/// Upstream must establish coverage and rate applicability; absent evidence
/// must be represented explicitly as unknown. No rates are calculated here.
public struct CostSummary: Sendable {
    public let buildID: String
    public let buildRevision: Int
    public let periodDays: Int
    public let currency: String
    public let total: ContractMoney?
    public let coverage: CostCoverage
    public let unpricedSelectionIDs: [String]
    public let unsupportedMeters: [String]
    public let rateApplicability: RateApplicability

    public init(buildID: String, buildRevision: Int, periodDays: Int, currency: String,
                total: ContractMoney?, coverage: CostCoverage, unpricedSelectionIDs: [String],
                unsupportedMeters: [String], rateApplicability: RateApplicability) throws {
        try ContractMoney.validateCurrency(currency)
        self.buildID = buildID
        self.buildRevision = buildRevision
        self.periodDays = periodDays
        self.currency = currency
        self.total = total
        self.coverage = coverage
        self.unpricedSelectionIDs = unpricedSelectionIDs
        self.unsupportedMeters = unsupportedMeters
        self.rateApplicability = rateApplicability
    }

    /// Frozen-v1 monthly metric requires a current complete 30-day estimate.
    /// A satisfied result compares an estimate to a limit, never a guarantee or
    /// an exact quote. Partial subtotals cannot satisfy this gate, even at zero.
    public func assessMonthlyBudget(_ limit: ContractMoney, currentBuildID: String,
                                    currentBuildRevision: Int) -> BudgetAssessment {
        // Build identity is the supplied UTF-8 spelling, not display-text equality.
        guard !currentBuildID.isEmpty, currentBuildRevision > 0,
              buildID.utf8.elementsEqual(currentBuildID.utf8),
              buildRevision == currentBuildRevision else { return .unknown(.staleBuild) }
        guard periodDays == 30 else { return .unknown(.unsupportedPeriod) }
        switch rateApplicability {
        case .expired: return .unknown(.expiredRates)
        case .unknown: return .unknown(.unverifiedRates)
        case .current: break
        }
        guard coverage == .complete else { return .unknown(.incompleteCoverage) }
        guard unpricedSelectionIDs.isEmpty else { return .unknown(.unpricedSelections) }
        guard unsupportedMeters.isEmpty else { return .unknown(.unsupportedMeters) }
        guard let total else { return .unknown(.missingTotal) }
        guard currency == limit.currency, total.currency == currency else { return .unknown(.mixedCurrency) }
        return total.amount <= limit.amount ? .satisfied : .exceeded
    }
}
