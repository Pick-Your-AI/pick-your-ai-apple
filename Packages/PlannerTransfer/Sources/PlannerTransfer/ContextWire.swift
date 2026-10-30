import Foundation

/// Errors deliberately exclude the untrusted document, keys, values and sources.
public enum ContextBudgetError: String, Error, Sendable, CustomStringConvertible {
    case invalidJSON, invalidShape, duplicateKey, invalidPointer, overlappingAnswers
    case invalidProvidedValue, invalidScope, answerBytesMismatch
    case unsupportedLimit, unsupportedNumber, unsupportedUnicode, unsupportedHashPlatform

    public var description: String { "ContextBudgetError.\(rawValue)" }
}

// This opt-in CD1-0.1 boundary does not alter the frozen-v1 JSONValue parser.
// Object keys use their UTF-8 bytes: Swift String equality normalizes Unicode.
indirect enum ContextWire: Sendable {
    case object([Data: ContextWire]), array([ContextWire]), string(String)
    case number(String, integer: Bool), boolean(Bool), null

    func object(required: [String], optional: [String] = []) throws -> [Data: ContextWire] {
        guard case .object(let fields) = self else { throw ContextBudgetError.invalidShape }
        let requiredKeys = Set(required.map { Data($0.utf8) })
        let allowed = requiredKeys.union(optional.map { Data($0.utf8) })
        guard requiredKeys.isSubset(of: Set(fields.keys)), Set(fields.keys).isSubset(of: allowed) else {
            throw ContextBudgetError.invalidShape
        }
        return fields
    }

    func string() throws -> String {
        guard case .string(let value) = self else { throw ContextBudgetError.invalidShape }
        return value
    }

    static func parse(_ data: Data) throws -> ContextWire {
        guard data.count <= 512 * 1024 else { throw ContextBudgetError.unsupportedLimit }
        guard String(data: data, encoding: .utf8) != nil else { throw ContextBudgetError.invalidJSON }
        var parser = ContextWireParser(bytes: Array(data))
        let result = try parser.value(depth: 1)
        parser.whitespace()
        guard parser.position == parser.bytes.count else { throw ContextBudgetError.invalidJSON }
        return result
    }
}

extension Dictionary where Key == Data, Value == ContextWire {
    func field(_ name: String) throws -> ContextWire {
        guard let value = self[Data(name.utf8)] else { throw ContextBudgetError.invalidShape }
        return value
    }
}

private struct ContextWireParser {
    let bytes: [UInt8]
    var position = 0
    var nodes = 0

    mutating func whitespace() {
        while position < bytes.count, [9, 10, 13, 32].contains(bytes[position]) { position += 1 }
    }

    mutating func take(_ byte: UInt8) -> Bool {
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    mutating func value(depth: Int) throws -> ContextWire {
        nodes += 1
        guard depth <= 48, nodes <= 16_384 else { throw ContextBudgetError.unsupportedLimit }
        whitespace()
        guard position < bytes.count else { throw ContextBudgetError.invalidJSON }
        switch bytes[position] {
        case 123:
            position += 1
            whitespace()
            var result: [Data: ContextWire] = [:]
            if take(125) { return .object(result) }
            while true {
                whitespace()
                let key = Data(try string().utf8)
                guard result[key] == nil else { throw ContextBudgetError.duplicateKey }
                whitespace()
                guard take(58) else { throw ContextBudgetError.invalidJSON }
                result[key] = try value(depth: depth + 1)
                whitespace()
                if take(125) { return .object(result) }
                guard take(44) else { throw ContextBudgetError.invalidJSON }
            }
        case 91:
            position += 1
            whitespace()
            var result: [ContextWire] = []
            if take(93) { return .array(result) }
            while true {
                result.append(try value(depth: depth + 1))
                whitespace()
                if take(93) { return .array(result) }
                guard take(44) else { throw ContextBudgetError.invalidJSON }
            }
        case 34: return .string(try string())
        case 116: try literal("true"); return .boolean(true)
        case 102: try literal("false"); return .boolean(false)
        case 110: try literal("null"); return .null
        case 45, 48...57: return try number()
        default: throw ContextBudgetError.invalidJSON
        }
    }

    mutating func literal(_ text: String) throws {
        let expected = Array(text.utf8)
        guard bytes.dropFirst(position).starts(with: expected) else { throw ContextBudgetError.invalidJSON }
        position += expected.count
    }

    mutating func string() throws -> String {
        let start = position
        guard take(34) else { throw ContextBudgetError.invalidJSON }
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if byte == 34 {
                do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<position])) }
                catch { throw ContextBudgetError.unsupportedUnicode }
            }
            guard byte >= 32 else { throw ContextBudgetError.invalidJSON }
            if byte == 92 {
                guard position < bytes.count else { throw ContextBudgetError.invalidJSON }
                let escape = bytes[position]
                position += 1
                if escape == 117 {
                    guard position + 4 <= bytes.count,
                          bytes[position..<(position + 4)].allSatisfy({
                              (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                          }) else { throw ContextBudgetError.invalidJSON }
                    position += 4
                } else if ![34, 47, 92, 98, 102, 110, 114, 116].contains(escape) {
                    throw ContextBudgetError.invalidJSON
                }
            }
        }
        throw ContextBudgetError.invalidJSON
    }

    mutating func digits() {
        while position < bytes.count, (48...57).contains(bytes[position]) { position += 1 }
    }

    mutating func number() throws -> ContextWire {
        let start = position
        _ = take(45)
        if !take(48) {
            guard position < bytes.count, (49...57).contains(bytes[position]) else {
                throw ContextBudgetError.invalidJSON
            }
            digits()
        }
        var integer = true
        if take(46) {
            integer = false
            let fraction = position
            digits()
            guard position > fraction else { throw ContextBudgetError.invalidJSON }
        }
        if take(101) || take(69) {
            integer = false
            if !take(43) { _ = take(45) }
            let exponent = position
            digits()
            guard position > exponent else { throw ContextBudgetError.invalidJSON }
        }
        guard position - start <= 4096 else { throw ContextBudgetError.unsupportedLimit }
        let token = String(decoding: bytes[start..<position], as: UTF8.self)
        if !integer { try ContextDecimalToken.validateFloating(token) }
        return .number(token, integer: integer)
    }
}

/// Exact decimal normalization for CD1's binary64 admission rule, not arithmetic.
private struct ContextDecimalToken: Equatable {
    let negative: Bool
    let coefficient: String
    let exponent: Int

    init(_ token: String) throws {
        let parts = token.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw ContextBudgetError.unsupportedNumber }
        let power: Int
        if parts.count == 2 {
            guard let parsed = Int(parts[1]), (-10_000...10_000).contains(parsed) else {
                throw ContextBudgetError.unsupportedNumber
            }
            power = parsed
        } else { power = 0 }
        let sign = parts[0].hasPrefix("-")
        let mantissa = sign ? parts[0].dropFirst() : parts[0][...]
        let fraction = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let fractionalCount = fraction.count == 2 ? fraction[1].count : 0
        var digits = Array(mantissa.utf8.filter { $0 != 46 })
        while digits.count > 1, digits.first == 48 { digits.removeFirst() }
        if digits.allSatisfy({ $0 == 48 }) {
            negative = false; coefficient = "0"; exponent = 0
            return
        }
        var adjusted = power - fractionalCount
        while digits.last == 48 { digits.removeLast(); adjusted += 1 }
        negative = sign
        coefficient = String(decoding: digits, as: UTF8.self)
        exponent = adjusted
    }

    static func validateFloating(_ token: String) throws {
        guard let number = Double(token), number.isFinite else { throw ContextBudgetError.unsupportedNumber }
        let original = try ContextDecimalToken(token)
        guard original == (try ContextDecimalToken(String(number))) else {
            throw ContextBudgetError.unsupportedNumber
        }
        if number.rounded(.towardZero) == number {
            guard original == (try ContextDecimalToken(exactInteger(number))) else {
                throw ContextBudgetError.unsupportedNumber
            }
        }
    }

    // Decode binary64's actual integer, avoiding Decimal/Int overflow and rounding.
    static func exactInteger(_ number: Double) -> String {
        if number == 0 { return "0" }
        let bits = number.bitPattern
        let exponent = Int((bits >> 52) & 0x7ff) - 1023 - 52
        var significand = (bits & 0x000f_ffff_ffff_ffff) | (1 << 52)
        if exponent < 0 { significand >>= -exponent }
        var decimal = Array(String(significand).utf8.reversed()).map { Int($0 - 48) }
        if exponent > 0 {
            for _ in 0..<exponent {
                var carry = 0
                for index in decimal.indices {
                    let doubled = decimal[index] * 2 + carry
                    decimal[index] = doubled % 10; carry = doubled / 10
                }
                if carry > 0 { decimal.append(carry) }
            }
        }
        return (number < 0 ? "-" : "") + String(decoding: decimal.reversed().map { UInt8($0 + 48) }, as: UTF8.self)
    }
}

func contextExact(_ left: String, _ right: String) -> Bool {
    left.utf8.elementsEqual(right.utf8)
}

// Python 3.12 str.isspace / regular-expression \s, including its C0 separators.
func contextHasNonWhitespace(_ value: String) -> Bool {
    value.unicodeScalars.contains { scalar in
        switch scalar.value {
        case 0x09...0x0d, 0x1c...0x20, 0x85, 0xa0, 0x1680,
             0x2000...0x200a, 0x2028...0x2029, 0x202f, 0x205f, 0x3000: return false
        default: return true
        }
    }
}
