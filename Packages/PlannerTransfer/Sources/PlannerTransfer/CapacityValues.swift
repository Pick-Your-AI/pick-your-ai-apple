import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Diagnostics contain a fixed category, never an original value, identifier or source.
public enum CapacityError: String, Error, Sendable, CustomStringConvertible {
    case invalidJSON, invalidShape, invalidIdentity, duplicateIdentity, invalidPointer, invalidDomain
    case overlappingAnswers, invalidProvidedValue, unsupportedProfile, declaredBytesMismatch
    case invalidFrozenBuild, invalidFrozenCatalog, danglingReference, contradictoryInput
    case unsupportedNativeLimit, unsupportedNativeNumber, unsupportedNativeUnicode
    case unsupportedHashPlatform

    public var description: String { "CapacityError.\(rawValue)" }
}

/// CD-2 ByteCount is a canonical decimal string. It is not a JSON-number or unit alias.
public struct CapacityByteCount: Sendable, Hashable, Comparable, CustomStringConvertible,
    CustomDebugStringConvertible {
    public let decimal: String
    public static let maximumDigits = 4096
    public static let zero = Self(canonical: "0")
    public var description: String { "CapacityByteCount" }
    public var debugDescription: String { description }

    public init(decimal: String) throws {
        guard !decimal.isEmpty else { throw CapacityError.invalidProvidedValue }
        guard decimal.utf8.count <= Self.maximumDigits else { throw CapacityError.unsupportedNativeLimit }
        let bytes = Array(decimal.utf8)
        guard bytes.allSatisfy({ (48...57).contains($0) }),
              bytes.count == 1 || bytes.first != 48 else {
            throw CapacityError.invalidProvidedValue
        }
        self.decimal = decimal
    }

    private init(canonical: String) { decimal = canonical }

    public static func < (left: Self, right: Self) -> Bool {
        let lhs = left.decimal.utf8, rhs = right.decimal.utf8
        return lhs.count == rhs.count ? lhs.lexicographicallyPrecedes(rhs) : lhs.count < rhs.count
    }

    public func adding(_ other: Self) throws -> Self {
        let lhs = Array(decimal.utf8.reversed()), rhs = Array(other.decimal.utf8.reversed())
        var result: [UInt8] = [], carry = 0
        for index in 0..<max(lhs.count, rhs.count) {
            let sum = (index < lhs.count ? Int(lhs[index] - 48) : 0)
                + (index < rhs.count ? Int(rhs[index] - 48) : 0) + carry
            result.append(UInt8(sum % 10) + 48)
            carry = sum / 10
        }
        if carry != 0 { result.append(UInt8(carry) + 48) }
        guard result.count <= Self.maximumDigits else { throw CapacityError.unsupportedNativeLimit }
        return Self(canonical: String(decoding: result.reversed(), as: UTF8.self))
    }
}

/// Explicit value access preserves token kind and exact UTF-8 keys. Automatic output is redacted.
public struct CapacityAnswerValue: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Kind: String, Sendable { case object, array, string, number, boolean, null }
    let wire: ContextWire
    init(_ wire: ContextWire) { self.wire = wire }
    public var description: String { "CapacityAnswerValue" }
    public var debugDescription: String { description }

    public var kind: Kind {
        switch wire {
        case .object: return .object
        case .array: return .array
        case .string: return .string
        case .number: return .number
        case .boolean: return .boolean
        case .null: return .null
        }
    }
    public var string: String? { if case .string(let value) = wire { return value }; return nil }
    public var boolean: Bool? { if case .boolean(let value) = wire { return value }; return nil }
    public var originalNumberToken: String? {
        if case .number(let value, _) = wire { return value }; return nil
    }
    public var isIntegerToken: Bool {
        if case .number(_, let integer) = wire { return integer }; return false
    }
    public var array: [Self]? {
        if case .array(let values) = wire { return values.map(Self.init) }; return nil
    }
    public var objectKeys: [String]? {
        guard case .object(let fields) = wire else { return nil }
        return fields.keys.sorted(by: { $0.lexicographicallyPrecedes($1) })
            .map { String(decoding: $0, as: UTF8.self) }
    }
    public func value(forExactKey key: String) -> Self? {
        guard key.utf8.count <= 512 * 1024, case .object(let fields) = wire,
              let value = fields[Data(key.utf8)] else { return nil }
        return Self(value)
    }
}

/// These are the consumer's fixed known-value schemas, never schemas supplied by an answer.
public enum CapacityAnswerField: String, Sendable {
    case boolean, text, nullableText, textSet, byteCount, positiveInteger
    case placement, residency, reserveBasis, admissionUnit, runtimeBinding
    case runtimeOperator, capacityMode, artifactKind, role, quantityTrace

    func validate(_ value: ContextWire) throws {
        switch self {
        case .boolean:
            guard case .boolean = value else { throw CapacityError.invalidProvidedValue }
        case .text:
            try Self.nonempty(value)
        case .nullableText:
            switch value {
            case .string, .null: break
            default: throw CapacityError.invalidProvidedValue
            }
        case .textSet:
            guard case .array(let values) = value else { throw CapacityError.invalidProvidedValue }
            var seen = Set<Data>()
            for value in values {
                let text = try Self.nonempty(value)
                guard seen.insert(Data(text.utf8)).inserted else { throw CapacityError.invalidProvidedValue }
            }
        case .byteCount:
            guard case .string(let text) = value else { throw CapacityError.invalidProvidedValue }
            _ = try CapacityByteCount(decimal: text)
        case .positiveInteger:
            guard case .number(let token, integer: true) = value,
                  token != "0", token.utf8.first != 45 else { throw CapacityError.invalidProvidedValue }
        case .placement: try Self.oneOf(value, ["always", "on_demand"])
        case .residency: try Self.oneOf(value, ["resident", "excluded"])
        case .reserveBasis: try Self.oneOf(value, ["before_reserve", "after_reserve"])
        case .admissionUnit: try Self.oneOf(value, ["sequences", "requests", "step_batch"])
        case .runtimeOperator: try Self.oneOf(value, ["self", "provider"])
        case .capacityMode: try Self.oneOf(value, ["shared", "reserved_throughput", "dedicated_instances"])
        case .artifactKind: try Self.oneOf(value, ["adapter", "full"])
        case .role: try Self.oneOf(value, ["host", "device", "serving_engine", "base_artifact", "speculative_draft", "other"])
        case .runtimeBinding:
            let fields = try value.object(required: ["kind", "id", "build", "source_input", "instance",
                                                      "replica", "rank", "admission", "stage"])
            try Self.oneOf(fields.field("kind"), ["model_engine", "service_runtime"])
            for key in ["id", "build", "source_input", "instance"] { try Self.nonempty(fields.field(key)) }
            for key in ["replica", "rank", "admission", "stage"] {
                let item = try fields.field(key)
                if case .null = item { continue }
                try Self.nonempty(item)
            }
        case .quantityTrace:
            let fields = try value.object(required: ["source_quantity", "source_unit", "method", "rounding"])
            for key in ["source_quantity", "source_unit", "method"] { try Self.nonempty(fields.field(key)) }
            try Self.oneOf(fields.field("rounding"), ["exact", "outward"])
        }
    }

    @discardableResult
    private static func nonempty(_ value: ContextWire) throws -> String {
        guard case .string(let text) = value, !text.isEmpty else { throw CapacityError.invalidProvidedValue }
        return text
    }

    private static func oneOf(_ value: ContextWire, _ choices: [String]) throws {
        let text = try nonempty(value)
        guard choices.contains(where: { contextExact($0, text) }) else { throw CapacityError.invalidProvidedValue }
    }
}

func capacityIdentity(_ value: String) throws {
    guard !value.isEmpty else { throw CapacityError.invalidIdentity }
    guard value.utf8.count <= 4096 else { throw CapacityError.unsupportedNativeLimit }
}

func capacityExactOptional(_ left: String?, _ right: String?) -> Bool {
    switch (left, right) {
    case (.none, .none): return true
    case (.some(let left), .some(let right)): return contextExact(left, right)
    default: return false
    }
}

func capacityDigest(_ bytes: Data) throws -> String {
    #if canImport(CryptoKit)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    #else
    throw CapacityError.unsupportedHashPlatform
    #endif
}

func capacityCheckDigest(_ declared: String?, actual: String) throws {
    guard let declared else { return }
    guard declared.utf8.count == 64 else { throw CapacityError.invalidIdentity }
    let bytes = Array(declared.utf8)
    guard bytes.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
        throw CapacityError.invalidIdentity
    }
    guard contextExact(declared, actual) else { throw CapacityError.declaredBytesMismatch }
}

func capacityKey(_ parts: [Data]) throws -> String {
    var data = Data()
    func appendLength(_ count: Int) throws {
        guard let exact = UInt32(exactly: count) else { throw CapacityError.unsupportedNativeLimit }
        var value = exact.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
    try appendLength(parts.count)
    for part in parts { try appendLength(part.count); data.append(part) }
    return try capacityDigest(data)
}

// ContextWire supplies only reviewed JSON token/key preservation. CD1-0.2 owns its envelope below.
func capacityDecode<T>(_ operation: () throws -> T) throws -> T {
    do { return try operation() }
    catch let error as ContextBudgetError {
        switch error {
        case .unsupportedLimit: throw CapacityError.unsupportedNativeLimit
        case .unsupportedNumber: throw CapacityError.unsupportedNativeNumber
        case .unsupportedUnicode: throw CapacityError.unsupportedNativeUnicode
        case .duplicateKey: throw CapacityError.duplicateIdentity
        case .invalidPointer: throw CapacityError.invalidPointer
        case .invalidJSON: throw CapacityError.invalidJSON
        default: throw CapacityError.invalidShape
        }
    }
}
