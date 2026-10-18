/// Frozen-v1 nonnegative decimal string with up to twelve fractional digits.
/// Integer precision is unbounded; operations do not use binary floating point
/// or Foundation.Decimal. Decoding and encoding preserve the original spelling.
public struct ContractDecimal: Codable, Comparable, Hashable, Sendable {
    public enum ValidationError: Error, Equatable { case invalidDecimal }

    public let rawValue: String

    public init(_ value: String) throws {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              !parts[0].isEmpty,
              parts[0].utf8.allSatisfy({ (48...57).contains($0) }),
              parts[0].count == 1 || parts[0].first != "0" else {
            throw ValidationError.invalidDecimal
        }
        if parts.count == 2 {
            guard (1...12).contains(parts[1].utf8.count),
                  parts[1].utf8.allSatisfy({ (48...57).contains($0) }) else {
                throw ValidationError.invalidDecimal
            }
        }
        rawValue = value
    }

    private init(validated value: String) { rawValue = value }

    /// Canonical integer digits representing the value scaled by 10^12.
    private var scaledDigits: [UInt8] {
        let parts = rawValue.split(separator: ".")
        let fraction = parts.count == 2 ? Array(parts[1].utf8) : []
        let digits = Array(parts[0].utf8) + fraction + Array(repeating: UInt8(48), count: 12 - fraction.count)
        let first = digits.firstIndex(where: { $0 != 48 }) ?? digits.index(before: digits.endIndex)
        return Array(digits[first...])
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.scaledDigits == rhs.scaledDigits }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let left = lhs.scaledDigits, right = rhs.scaledDigits
        if left.count != right.count { return left.count < right.count }
        return left.lexicographicallyPrecedes(right)
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(scaledDigits) }

    /// Exact addition. The result has canonical spelling without trailing zeros.
    public static func + (lhs: Self, rhs: Self) -> Self {
        let left = Array(lhs.scaledDigits.reversed()), right = Array(rhs.scaledDigits.reversed())
        var result: [UInt8] = []
        var carry: UInt8 = 0
        for index in 0..<max(left.count, right.count) {
            let digit = (index < left.count ? left[index] - 48 : 0)
                + (index < right.count ? right[index] - 48 : 0) + carry
            result.append(digit % 10 + 48)
            carry = digit / 10
        }
        if carry != 0 { result.append(carry + 48) }
        while result.count < 13 { result.append(48) }
        let digits = Array(result.reversed())
        let integer = String(decoding: digits.dropLast(12), as: UTF8.self)
        var fraction = Array(digits.suffix(12))
        while fraction.last == 48 { fraction.removeLast() }
        let suffix = fraction.isEmpty ? "" : "." + String(decoding: fraction, as: UTF8.self)
        return Self(validated: integer + suffix)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do { try self.init(value) }
        catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected frozen-v1 nonnegative decimal string with at most 12 fractional digits")
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
