import Foundation

public enum CapacityAnswerState: String, Sendable {
    case provided, unknown, missing, withheld
    case notApplicable = "not_applicable"
}

public enum CapacityAnswerCause: String, Sendable {
    case none, direct, ancestor, withheldDescendant
}

/// An immutable observation. Only the preserving reader constructs one.
public struct CapacityAnswer: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let state: CapacityAnswerState
    public let field: CapacityAnswerField
    public let requestedPath: String
    public let sourcePath: String?
    public let cause: CapacityAnswerCause
    public let assumption: Bool?
    public let presetSource: String?
    public let value: CapacityAnswerValue?
    public let originalSHA256: String
    public var description: String { "CapacityAnswer" }
    public var debugDescription: String { description }

    public var byteCount: CapacityByteCount? {
        guard field == .byteCount, let text = value?.string else { return nil }
        return try? CapacityByteCount(decimal: text)
    }
}

private struct CapacityPointer: Sendable {
    let original: String
    let tokens: [Data]

    init(_ path: String) throws {
        guard path.utf8.count <= 16_384 else { throw CapacityError.unsupportedNativeLimit }
        let bytes = Array(path.utf8)
        guard bytes.first == 47 else { throw CapacityError.invalidPointer }
        let raw = bytes.dropFirst().split(separator: 47, omittingEmptySubsequences: false)
        guard raw.count <= 128 else { throw CapacityError.unsupportedNativeLimit }
        var decoded: [Data] = []
        for part in raw {
            let bytes = Array(part)
            var token = Data(), index = 0
            while index < bytes.count {
                if bytes[index] == 126 {
                    guard index + 1 < bytes.count else { throw CapacityError.invalidPointer }
                    switch bytes[index + 1] {
                    case 48: token.append(126)
                    case 49: token.append(47)
                    default: throw CapacityError.invalidPointer
                    }
                    index += 2
                } else { token.append(bytes[index]); index += 1 }
            }
            decoded.append(token)
        }
        original = path
        tokens = decoded
    }

    func covers(_ other: Self) -> Bool {
        tokens.count <= other.tokens.count && zip(tokens, other.tokens).allSatisfy { pair in pair.0 == pair.1 }
    }
}

private struct CapacityStoredAnswer: Sendable {
    let pointer: CapacityPointer
    let state: CapacityAnswerState
    let value: ContextWire?
    let assumption: Bool?
    let source: String?
}

/// Strict opt-in CD1-0.2 input. Original bytes are retained; no CD1-0.1 migration is performed.
public struct CapacityAnswerIndex: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let profile = "cd1-0.2"
    public static let maximumAnswers = 2048
    public let originalBytes: Data
    public let originalSHA256: String
    private let records: [CapacityStoredAnswer]
    public var description: String { "CapacityAnswerIndex" }
    public var debugDescription: String { description }

    public init(originalBytes: Data, declaredSHA256: String? = nil) throws {
        self = try capacityDecode {
            let parsed = try ContextWire.parse(originalBytes)
            let root = try parsed.object(required: ["x_t0_answer_states"])
            let envelope = try root.field("x_t0_answer_states").object(required: ["proposal_version", "answers"])
            let version = try envelope.field("proposal_version").string()
            guard contextExact(version, Self.profile) else { throw CapacityError.unsupportedProfile }
            guard case .object(let answers) = try envelope.field("answers") else { throw CapacityError.invalidShape }
            guard answers.count <= Self.maximumAnswers else { throw CapacityError.unsupportedNativeLimit }
            var records: [CapacityStoredAnswer] = []
            for (key, answer) in answers {
                let pointer = try CapacityPointer(String(decoding: key, as: UTF8.self))
                guard case .object(let fields) = answer,
                      let rawState = fields[Data("state".utf8)],
                      let state = CapacityAnswerState(rawValue: try rawState.string()) else {
                    throw CapacityError.invalidShape
                }
                if state == .provided {
                    let fields = try answer.object(required: ["state", "value", "assumption"], optional: ["source"])
                    guard case .boolean(let assumption) = try fields.field("assumption") else {
                        throw CapacityError.invalidShape
                    }
                    let source: String?
                    if let value = fields[Data("source".utf8)] {
                        let text = try value.string()
                        try Self.validatePresetSource(text)
                        source = text
                    } else { source = nil }
                    records.append(CapacityStoredAnswer(pointer: pointer, state: state,
                        value: try fields.field("value"), assumption: assumption, source: source))
                } else {
                    _ = try answer.object(required: ["state"])
                    records.append(CapacityStoredAnswer(pointer: pointer, state: state,
                        value: nil, assumption: nil, source: nil))
                }
            }
            let paths = Set(records.map { $0.pointer.tokens })
            guard paths.count == records.count else { throw CapacityError.duplicateIdentity }
            for record in records {
                for length in 1..<record.pointer.tokens.count {
                    guard !paths.contains(Array(record.pointer.tokens.prefix(length))) else {
                        throw CapacityError.overlappingAnswers
                    }
                }
            }
            let hash = try capacityDigest(originalBytes)
            try capacityCheckDigest(declaredSHA256, actual: hash)
            return Self(bytes: originalBytes, hash: hash, records: records)
        }
    }

    private init(bytes: Data, hash: String, records: [CapacityStoredAnswer]) {
        originalBytes = bytes; originalSHA256 = hash; self.records = records
    }

    public func read(path: String, as field: CapacityAnswerField) throws -> CapacityAnswer {
        try capacityDecode {
            let requested = try CapacityPointer(path)
            func observed(_ state: CapacityAnswerState, source: CapacityStoredAnswer?,
                          cause: CapacityAnswerCause, value: ContextWire? = nil) -> CapacityAnswer {
                CapacityAnswer(state: state, field: field, requestedPath: path,
                    sourcePath: source?.pointer.original, cause: cause,
                    assumption: state == .provided ? source?.assumption : nil,
                    presetSource: state == .provided ? source?.source : nil,
                    value: value.map(CapacityAnswerValue.init), originalSHA256: originalSHA256)
            }
            guard let record = records.first(where: { $0.pointer.covers(requested) }) else {
                let hidden = records.filter { $0.state == .withheld && requested.covers($0.pointer) }
                    .min { Data($0.pointer.original.utf8).lexicographicallyPrecedes(Data($1.pointer.original.utf8)) }
                if let hidden { return observed(.withheld, source: hidden, cause: .withheldDescendant) }
                return observed(.missing, source: nil, cause: .none)
            }
            let cause: CapacityAnswerCause = record.pointer.tokens.count == requested.tokens.count ? .direct : .ancestor
            guard record.state == .provided, var value = record.value else {
                return observed(record.state, source: record, cause: cause)
            }
            for token in requested.tokens.dropFirst(record.pointer.tokens.count) {
                switch value {
                case .object(let fields):
                    guard let child = fields[token] else { return observed(.missing, source: record, cause: .ancestor) }
                    value = child
                case .array(let items):
                    let bytes = Array(token)
                    guard !bytes.isEmpty, bytes.allSatisfy({ (48...57).contains($0) }),
                          bytes.count == 1 || bytes.first != 48 else { throw CapacityError.invalidPointer }
                    guard let index = Int(String(decoding: bytes, as: UTF8.self)), index < items.count else {
                        return observed(.missing, source: record, cause: .ancestor)
                    }
                    value = items[index]
                default: throw CapacityError.invalidPointer
                }
            }
            try field.validate(value)
            return observed(.provided, source: record, cause: cause, value: value)
        }
    }

    private static func validatePresetSource(_ source: String) throws {
        guard source.utf8.count <= 71 else { throw CapacityError.invalidShape }
        let prefix = Array("preset:".utf8), bytes = Array(source.utf8)
        guard bytes.starts(with: prefix) else { throw CapacityError.invalidShape }
        let suffix = Array(bytes.dropFirst(prefix.count))
        func alphanumeric(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) }
        guard (1...64).contains(suffix.count), alphanumeric(suffix[0]),
              suffix.allSatisfy({ alphanumeric($0) || [45, 46, 95].contains($0) }) else {
            throw CapacityError.invalidShape
        }
    }
}
