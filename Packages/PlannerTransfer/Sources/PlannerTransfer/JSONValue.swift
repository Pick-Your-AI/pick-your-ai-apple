import Foundation

/// Lossless strings, bounded exact decimal numbers, and no Foundation Boolean/number bridging.
public indirect enum JSONValue: Equatable, Sendable, Encodable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Decimal), bool(Bool), null
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
    var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    var string: String? { if case .string(let v) = self { v } else { nil } }
    var number: Decimal? { if case .number(let v) = self { v } else { nil } }
}

/// Diagnostics deliberately contain neither source keys nor payload values.
public enum TransferError: Error, Equatable, Sendable {
    case oversized, malformed, tooDeep, tooComplex, duplicateKey, unsupportedVersion, schemaViolation
    case sensitiveContent, unsupportedNumber, invalidFork, unavailableSchema
}

/// A byte bound precedes allocation/parsing; depth and duplicate keys are checked before decoding.
struct JSONParser {
    let bytes: [UInt8]
    var index = 0
    var nodes = 0
    init(_ data: Data) throws {
        guard data.count <= BuildTransfer.maximumBytes else { throw TransferError.oversized }
        bytes = Array(data)
    }
    mutating func parse() throws -> JSONValue {
        let result = try value(depth: 0); whitespace()
        guard index == bytes.count else { throw TransferError.malformed }
        return result
    }
    mutating func whitespace() { while index < bytes.count && [9,10,13,32].contains(bytes[index]) { index += 1 } }
    mutating func consume(_ byte: UInt8) -> Bool {
        whitespace(); guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
    mutating func string() throws -> String {
        whitespace(); let start = index
        guard consume(34) else { throw TransferError.malformed }
        while index < bytes.count {
            let b = bytes[index]; index += 1
            if b == 92 { guard index < bytes.count else { break }; index += 1 }
            else if b == 34 {
                guard let value = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) else { throw TransferError.malformed }
                return value
            }
        }
        throw TransferError.malformed
    }
    mutating func value(depth: Int) throws -> JSONValue {
        guard depth <= 48 else { throw TransferError.tooDeep }
        nodes += 1
        guard nodes <= 16_384 else { throw TransferError.tooComplex }
        whitespace(); guard index < bytes.count else { throw TransferError.malformed }
        if bytes[index] == 34 { return .string(try string()) }
        if consume(123) {
            var result: [String: JSONValue] = [:]
            if consume(125) { return .object(result) }
            repeat {
                let key = try string()
                guard result[key] == nil else { throw TransferError.duplicateKey }
                guard consume(58) else { throw TransferError.malformed }
                result[key] = try value(depth: depth + 1)
                if consume(125) { return .object(result) }
            } while consume(44)
            throw TransferError.malformed
        }
        if consume(91) {
            var result: [JSONValue] = []
            if consume(93) { return .array(result) }
            repeat {
                result.append(try value(depth: depth + 1))
                if consume(93) { return .array(result) }
            } while consume(44)
            throw TransferError.malformed
        }
        for (word, result) in [("true", JSONValue.bool(true)), ("false", .bool(false)), ("null", .null)] {
            let literal = Array(word.utf8)
            if bytes[index...].starts(with: literal) { index += literal.count; return result }
        }
        let start = index
        while index < bytes.count && ![9,10,13,32,44,93,125].contains(bytes[index]) { index += 1 }
        let token = String(decoding: bytes[start..<index], as: UTF8.self)
        guard token.range(of: #"\A-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?\z"#, options: .regularExpression) != nil else { throw TransferError.malformed }
        // Explicit interoperable numeric subset: prevents precision rounding in Decimal/JavaScript.
        guard token.filter({ $0.isNumber }).count <= 15,
              let number = Decimal(string: token, locale: Locale(identifier: "en_US_POSIX")),
              !number.isNaN, abs(number) <= Decimal(9_007_199_254_740_991),
              number == 0 || abs(number) >= Decimal(string: "0.000000000001")! else { throw TransferError.unsupportedNumber }
        return .number(number)
    }
}
