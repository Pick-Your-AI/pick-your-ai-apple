import Foundation

/// Localizes already validated decimal strings without changing their value or
/// precision. Only the ten individual digits pass through NumberFormatter; the
/// amount itself never passes through a finite-precision numeric representation.
public struct ExactDecimalFormatter: Sendable {
    public enum FormattingError: Error, Equatable {
        case unsupportedNumberingSystem
    }

    public let localeIdentifier: String
    private let digits: [String]
    private let decimalSeparator: String

    /// Captures an explicit locale. Create a new value when the UI locale changes.
    /// No mutable Foundation formatter is retained or shared between tasks.
    public init(locale: Locale) throws {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumIntegerDigits = 1
        formatter.maximumIntegerDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.positivePrefix = ""
        formatter.positiveSuffix = ""

        var symbols: [String] = []
        for digit in 0...9 {
            guard let symbol = formatter.string(from: NSNumber(value: digit)),
                  symbol.unicodeScalars.count == 1,
                  symbol.unicodeScalars.first?.properties.generalCategory == .decimalNumber,
                  symbol.first?.wholeNumberValue == digit else {
                // Algorithmic numerals cannot safely be assembled digit by digit.
                throw FormattingError.unsupportedNumberingSystem
            }
            symbols.append(symbol)
        }
        guard Set(symbols).count == 10,
              let separator = formatter.decimalSeparator, !separator.isEmpty else {
            throw FormattingError.unsupportedNumberingSystem
        }
        localeIdentifier = locale.identifier
        digits = symbols
        decimalSeparator = separator
    }

    /// Preserves every integer/fractional digit, including explicit trailing zeros.
    /// This display string has no grouping or rounding and is never a wire value.
    public func string(from amount: ContractDecimal) -> String {
        var result = ""
        result.reserveCapacity(amount.rawValue.utf8.count)
        for byte in amount.rawValue.utf8 {
            if byte == 46 { result += decimalSeparator }
            else { result += digits[Int(byte - 48)] }
        }
        return result
    }

    /// Keeps the canonical currency code separate from the localized amount. A
    /// caller can lay out both fields in its locale without guessing a symbol,
    /// converting currencies or applying currency-specific fractional rounding.
    public func presentation(for money: ContractMoney) -> ExactMoneyPresentation {
        ExactMoneyPresentation(amount: string(from: money.amount), currencyCode: money.currency)
    }
}

public struct ExactMoneyPresentation: Equatable, Sendable {
    public let amount: String
    public let currencyCode: String

    fileprivate init(amount: String, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode
    }
}
