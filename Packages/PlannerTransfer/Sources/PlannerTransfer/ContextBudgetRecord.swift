import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// An exact, nonnegative decimal integer. Counts never pass through Double.
public struct ContextTokenCount: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let decimal: String
    public var description: String { decimal }

    public init(decimal: String) throws {
        let bytes = Array(decimal.utf8)
        guard !bytes.isEmpty, bytes.count <= 4096 else { throw ContextBudgetError.unsupportedLimit }
        guard bytes.allSatisfy({ (48...57).contains($0) }) else {
            throw ContextBudgetError.invalidProvidedValue
        }
        let normalized = String(decoding: bytes.drop(while: { $0 == 48 }), as: UTF8.self)
        self.decimal = normalized.isEmpty ? "0" : normalized
    }

    private init(canonical: String) { decimal = canonical }

    public static func < (left: Self, right: Self) -> Bool {
        let lhs = left.decimal.utf8, rhs = right.decimal.utf8
        return lhs.count == rhs.count ? lhs.lexicographicallyPrecedes(rhs) : lhs.count < rhs.count
    }

    fileprivate func adding(_ other: Self) -> Self {
        let left = Array(decimal.utf8.reversed()), right = Array(other.decimal.utf8.reversed())
        var result: [UInt8] = [], carry = 0
        for index in 0..<max(left.count, right.count) {
            let sum = (index < left.count ? Int(left[index] - 48) : 0)
                + (index < right.count ? Int(right[index] - 48) : 0) + carry
            result.append(UInt8(sum % 10 + 48)); carry = sum / 10
        }
        if carry > 0 { result.append(UInt8(carry + 48)) }
        return Self(canonical: String(decoding: result.reversed(), as: UTF8.self))
    }

    /// Caller-supplied evidence is an input; this helper does not establish it.
    public static func effectiveLimit(native: Self?, extensionLimit: Self? = nil,
                                      extensionEvidenced: Bool = false, runtimeCeiling: Self? = nil) -> Self? {
        guard let native else { return nil }
        let limit = extensionEvidenced ? (extensionLimit ?? native) : native
        return runtimeCeiling.map { min(limit, $0) } ?? limit
    }
}

public struct ContextBudgetReference: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let version: String
    public var description: String { "ContextBudgetReference" }
    public var debugDescription: String { description }

    public init(id: String, version: String) throws {
        try ContextBudgetScope.validateID(id)
        guard (1...200).contains(version.unicodeScalars.count), contextHasNonWhitespace(version),
              !version.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw ContextBudgetError.invalidScope
        }
        self.id = id; self.version = version
    }

    public static func == (left: Self, right: Self) -> Bool {
        contextExact(left.id, right.id) && contextExact(left.version, right.version)
    }
}

/// An already normalized scope; neither its labels nor its digest grant authority.
public struct ContextBudgetScope: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let selectionID: String
    public let model: ContextBudgetReference
    public let route: ContextBudgetReference
    public let operation: String
    public let tokenizer: ContextBudgetReference
    public let settingsSHA256: String
    public var description: String { "ContextBudgetScope" }
    public var debugDescription: String { description }

    public init(selectionID: String, model: ContextBudgetReference, route: ContextBudgetReference,
                operation: String, tokenizer: ContextBudgetReference, settingsSHA256: String) throws {
        try Self.validateID(selectionID); try Self.validateID(operation)
        try Self.validateDigest(settingsSHA256)
        self.selectionID = selectionID; self.model = model; self.route = route
        self.operation = operation; self.tokenizer = tokenizer; self.settingsSHA256 = settingsSHA256
    }

    public static func decode(_ bytes: Data) throws -> Self { try decode(ContextWire.parse(bytes)) }

    fileprivate static func decode(_ wire: ContextWire) throws -> Self {
        let fields = try wire.object(required: ["selection_id", "model", "route", "operation", "tokenizer", "settings_sha256"])
        func reference(_ name: String) throws -> ContextBudgetReference {
            let value = try fields.field(name).object(required: ["id", "version"])
            return try ContextBudgetReference(id: value.field("id").string(), version: value.field("version").string())
        }
        return try Self(selectionID: fields.field("selection_id").string(), model: reference("model"),
                        route: reference("route"), operation: fields.field("operation").string(),
                        tokenizer: reference("tokenizer"), settingsSHA256: fields.field("settings_sha256").string())
    }

    fileprivate static func validateID(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard (3...120).contains(bytes.count), let first = bytes.first,
              (97...122).contains(first) || (48...57).contains(first),
              bytes.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || [46, 95, 58, 45].contains($0) }) else {
            throw ContextBudgetError.invalidScope
        }
    }

    fileprivate static func validateDigest(_ value: String) throws {
        guard value.utf8.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw ContextBudgetError.invalidScope
        }
    }

    public static func == (left: Self, right: Self) -> Bool {
        contextExact(left.selectionID, right.selectionID) && left.model == right.model && left.route == right.route
            && contextExact(left.operation, right.operation) && left.tokenizer == right.tokenizer
            && contextExact(left.settingsSHA256, right.settingsSHA256)
    }
}

public enum ContextBudgetField: String, CaseIterable, Sendable {
    case semantics, inputTokens = "input_tokens", reservedOutputTokens = "reserved_output_tokens"
    case outputCapTokens = "output_cap_tokens", sharedCapTokens = "shared_cap_tokens"
    case inputCapTokens = "input_cap_tokens", policyTotalCapTokens = "policy_total_cap_tokens"
    public var pointer: String { "/context/" + rawValue }
}

public enum ContextAnswerState: String, Sendable {
    case provided, unknown, missing, withheld, notApplicable = "not_applicable"
}

public enum ContextBudgetSemantics: String, Sendable { case shared, separate }

public enum ContextBudgetValue: Sendable, Equatable {
    case semantics(ContextBudgetSemantics), count(ContextTokenCount)
    case inputRange(lower: ContextTokenCount, upper: ContextTokenCount)
}

public struct ContextBudgetAnswer: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let field: ContextBudgetField
    public let state: ContextAnswerState
    public let value: ContextBudgetValue?
    public let source: String?
    public let sourcePath: String?
    public var requestedPath: String { field.pointer }
    public var description: String { "ContextBudgetAnswer(\(field.rawValue), \(state.rawValue))" }
    public var debugDescription: String { description }
}

public enum ContextBudgetOutcome: String, Sendable { case pass, fail, unknown, skipped }

public struct ContextBudgetCheck: Sendable, Equatable {
    public let name: String
    public let lower: ContextBudgetOutcome
    public let upper: ContextBudgetOutcome
}

public struct ContextBudgetResult: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let outcome: ContextBudgetOutcome
    public let mayNotFit: Bool
    public let reason: String
    public let checks: [ContextBudgetCheck]
    public let answers: [ContextBudgetField: ContextBudgetAnswer]
    public var description: String { "ContextBudgetResult(\(outcome.rawValue), \(reason))" }
    public var debugDescription: String { description }
}

/// Explicit CD11/CD1-0.1 candidate reader, independent of the frozen-v1 dispatcher.
public struct ContextBudgetRecord: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let originalBytes: Data
    public let answerBytes: Data
    public let scope: ContextBudgetScope
    public let answers: [ContextBudgetField: ContextBudgetAnswer]
    public var description: String { "ContextBudgetRecord(cd11-0.1, cd1-0.1)" }
    public var debugDescription: String { description }

    public static func decode(binding: Data, answers answerBytes: Data) throws -> Self {
        let root = try ContextWire.parse(binding).object(required: ["x_t0_context_budget"])
        let proposal = try root.field("x_t0_context_budget").object(required: ["proposal_version", "scope", "answer_states_sha256"])
        guard try proposal.field("proposal_version").string() == "cd11-0.1" else { throw ContextBudgetError.invalidShape }
        let scope = try ContextBudgetScope.decode(proposal.field("scope"))
        let expected = try proposal.field("answer_states_sha256").string()
        try ContextBudgetScope.validateDigest(expected)
        guard answerBytes.count <= 512 * 1024 else { throw ContextBudgetError.unsupportedLimit }
        #if canImport(CryptoKit)
        let actual = SHA256.hash(data: answerBytes).map { String(format: "%02x", $0) }.joined()
        guard contextExact(actual, expected) else { throw ContextBudgetError.answerBytesMismatch }
        #else
        throw ContextBudgetError.unsupportedHashPlatform
        #endif
        let index = try ContextAnswerIndex(answerBytes)
        var answers: [ContextBudgetField: ContextBudgetAnswer] = [:]
        for field in ContextBudgetField.allCases { answers[field] = try index.read(field) }
        if case .semantics(.separate)? = answers[.semantics]?.value,
           answers[.sharedCapTokens]?.state == .provided { throw ContextBudgetError.invalidProvidedValue }
        return Self(originalBytes: binding, answerBytes: answerBytes, scope: scope, answers: answers)
    }

    public func evaluate(activeScope: ContextBudgetScope?, enabled: Bool?, evidenceEligible: Bool?) -> ContextBudgetResult {
        func unresolved(_ reason: String, _ outcome: ContextBudgetOutcome = .unknown) -> ContextBudgetResult {
            ContextBudgetResult(outcome: outcome, mayNotFit: false, reason: reason, checks: [], answers: answers)
        }
        if enabled == false { return unresolved("selection_not_enabled", .skipped) }
        if enabled == nil { return unresolved("selection_activation_unknown") }
        guard let activeScope else { return unresolved("selection_scope_missing") }
        guard activeScope == scope else { return unresolved("route_scope_mismatch") }
        guard evidenceEligible == true else {
            return unresolved(evidenceEligible == nil ? "source_evidence_unresolved" : "source_evidence_ineligible")
        }
        func count(_ field: ContextBudgetField) -> ContextTokenCount? {
            if case .count(let value)? = answers[field]?.value { return value }
            return nil
        }
        func compare(_ demand: ContextTokenCount?, _ limit: ContextTokenCount?) -> ContextBudgetOutcome {
            guard let demand, let limit else { return .unknown }
            return demand <= limit ? .pass : .fail
        }
        func combine(_ results: [ContextBudgetOutcome]) -> ContextBudgetOutcome {
            if results.contains(.fail) { return .fail }
            if results.contains(.unknown) { return .unknown }
            return results.contains(.pass) ? .pass : .skipped
        }
        var lower: ContextTokenCount?, upper: ContextTokenCount?
        if case .inputRange(let first, let last)? = answers[.inputTokens]?.value { lower = first; upper = last }
        let output = count(.reservedOutputTokens)
        let totalLower = lower.flatMap { input in output.map { input.adding($0) } }
        let totalUpper = upper.flatMap { input in output.map { input.adding($0) } }
        let outputCheck = compare(output, count(.outputCapTokens))
        var checks = [ContextBudgetCheck(name: "output", lower: outputCheck, upper: outputCheck)]
        var semantics: ContextBudgetSemantics?
        if case .semantics(let supplied)? = answers[.semantics]?.value { semantics = supplied }
        switch semantics {
        case .some(.shared):
            checks.append(ContextBudgetCheck(name: "combined", lower: compare(totalLower, count(.sharedCapTokens)),
                                             upper: compare(totalUpper, count(.sharedCapTokens))))
        case .some(.separate): checks.append(ContextBudgetCheck(name: "combined", lower: .skipped, upper: .skipped))
        case .none: checks.append(ContextBudgetCheck(name: "combined", lower: .unknown, upper: .unknown))
        }
        if count(.inputCapTokens) != nil || semantics == .separate {
            checks.append(ContextBudgetCheck(name: "input", lower: compare(lower, count(.inputCapTokens)),
                                             upper: compare(upper, count(.inputCapTokens))))
        }
        if let limit = count(.policyTotalCapTokens) {
            checks.append(ContextBudgetCheck(name: "policy_total", lower: compare(totalLower, limit), upper: compare(totalUpper, limit)))
        }
        for (field, name) in [(ContextBudgetField.inputCapTokens, "input"), (.policyTotalCapTokens, "policy_total")] {
            if answers[field]?.state != .provided, answers[field]?.state != .notApplicable,
               !checks.contains(where: { $0.name == name }) {
                checks.append(ContextBudgetCheck(name: name, lower: .unknown, upper: .unknown))
            }
        }
        let outcome = combine(checks.map(\.upper)), lowerOutcome = combine(checks.map(\.lower))
        return ContextBudgetResult(outcome: outcome, mayNotFit: outcome == .fail && lowerOutcome != .fail,
                                   reason: "normalized_context_screen", checks: checks, answers: answers)
    }
}

private struct ContextAnswerIndex {
    struct Record {
        let path: String
        let tokens: [Data]
        let state: ContextAnswerState
        let value: ContextWire?
        let source: String?
    }
    let records: [Record]

    init(_ bytes: Data) throws {
        let root = try ContextWire.parse(bytes).object(required: ["x_t0_answer_states"])
        let envelope = try root.field("x_t0_answer_states").object(required: ["proposal_version", "answers"])
        guard try envelope.field("proposal_version").string() == "cd1-0.1",
              case .object(let encoded) = try envelope.field("answers") else { throw ContextBudgetError.invalidShape }
        var parsed: [Record] = []
        for (key, value) in encoded {
            let path = String(decoding: key, as: UTF8.self), tokens = try Self.tokens(path)
            guard case .object(let object) = value,
                  let state = ContextAnswerState(rawValue: try object.field("state").string()) else {
                throw ContextBudgetError.invalidShape
            }
            let fields = try value.object(required: state == .provided ? ["state", "value"] : ["state"],
                                          optional: state == .provided ? ["source"] : [])
            let source = try fields[Data("source".utf8)].map { try $0.string() }
            if let source, !contextHasNonWhitespace(source) { throw ContextBudgetError.invalidShape }
            parsed.append(Record(path: path, tokens: tokens, state: state, value: fields[Data("value".utf8)], source: source))
        }
        let keys = Set(parsed.map(\.tokens))
        for record in parsed where record.tokens.count > 1 {
            for length in 1..<record.tokens.count where keys.contains(Array(record.tokens.prefix(length))) {
                throw ContextBudgetError.overlappingAnswers
            }
        }
        records = parsed.sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
    }

    static func tokens(_ path: String) throws -> [Data] {
        let original = Array(path.utf8)
        guard original.first == 47 else { throw ContextBudgetError.invalidPointer }
        let parts = original.split(separator: 47, omittingEmptySubsequences: false).dropFirst()
        guard parts.count <= 128 else { throw ContextBudgetError.unsupportedLimit }
        return try parts.map { part in
            let bytes = Array(part)
            var decoded: [UInt8] = [], index = 0
            while index < bytes.count {
                if bytes[index] == 126 {
                    guard index + 1 < bytes.count, [48, 49].contains(bytes[index + 1]) else {
                        throw ContextBudgetError.invalidPointer
                    }
                    decoded.append(bytes[index + 1] == 48 ? 126 : 47); index += 2
                } else { decoded.append(bytes[index]); index += 1 }
            }
            return Data(decoded)
        }
    }

    func read(_ field: ContextBudgetField) throws -> ContextBudgetAnswer {
        let wanted = try Self.tokens(field.pointer)
        func answer(_ state: ContextAnswerState, _ path: String? = nil,
                    value: ContextBudgetValue? = nil, source: String? = nil) -> ContextBudgetAnswer {
            ContextBudgetAnswer(field: field, state: state, value: value, source: source, sourcePath: path)
        }
        guard let record = records.first(where: { wanted.starts(with: $0.tokens) }) else {
            if let child = records.first(where: { $0.state == .withheld && $0.tokens.starts(with: wanted) }) {
                return answer(.withheld, child.path)
            }
            return answer(.missing)
        }
        guard record.state == .provided else { return answer(record.state, record.path) }
        guard var value = record.value else { throw ContextBudgetError.invalidShape }
        for token in wanted.dropFirst(record.tokens.count) {
            switch value {
            case .object(let object):
                guard let member = object[token] else { return answer(.missing, record.path) }
                value = member
            case .array(let values):
                let bytes = Array(token)
                guard !bytes.isEmpty, bytes.allSatisfy({ (48...57).contains($0) }),
                      bytes.count == 1 || bytes[0] != 48 else { throw ContextBudgetError.invalidPointer }
                guard let index = Int(String(decoding: bytes, as: UTF8.self)), index < values.count else {
                    return answer(.missing, record.path)
                }
                value = values[index]
            default: throw ContextBudgetError.invalidProvidedValue
            }
        }
        func count(_ wire: ContextWire, positive: Bool) throws -> ContextTokenCount {
            guard case .number(let token, integer: true) = wire,
                  !token.hasPrefix("-") || token == "-0" else { throw ContextBudgetError.invalidProvidedValue }
            let value = try ContextTokenCount(decimal: token == "-0" ? "0" : token)
            guard !positive || value.decimal != "0" else { throw ContextBudgetError.invalidProvidedValue }
            return value
        }
        let typed: ContextBudgetValue
        switch field {
        case .semantics:
            guard case .string(let text) = value, let semantics = ContextBudgetSemantics(rawValue: text) else {
                throw ContextBudgetError.invalidProvidedValue
            }
            typed = .semantics(semantics)
        case .inputTokens:
            let range = try value.object(required: ["lower", "upper"])
            let lower = try count(range.field("lower"), positive: true)
            let upper = try count(range.field("upper"), positive: true)
            guard lower <= upper else { throw ContextBudgetError.invalidProvidedValue }
            typed = .inputRange(lower: lower, upper: upper)
        default: typed = .count(try count(value, positive: field == .sharedCapTokens || field == .inputCapTokens))
        }
        return answer(.provided, record.path, value: typed, source: record.source)
    }
}
