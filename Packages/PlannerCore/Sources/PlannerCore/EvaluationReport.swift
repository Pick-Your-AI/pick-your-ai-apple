import Foundation

// Frozen-v1 wire DTOs. Decoding does not recompute compatibility or deployment readiness.
// Integers are bounded by Int and evidence numbers by Foundation Decimal. This is a
// client boundary, not a replacement for the canonical JSON Schema validator.
public enum EvaluationResult: String, Codable, Sendable { case valid, invalid, indeterminate }
public enum EvaluationReadiness: String, Codable, Sendable {
    case ready, blocked
    case needsReview = "needs_review"
}
public enum EvaluationOutcome: String, Codable, Sendable { case pass, fail, unknown, skipped }
public enum EvaluationSeverity: String, Codable, Sendable { case error, warning, info }


/// Arbitrary evidence with a maximum nesting depth of 32. Null is distinct from absence.
public indirect enum EvaluationJSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), string(String), number(Decimal)
    case array([EvaluationJSONValue]), object([String: EvaluationJSONValue])

    /// Compare decoded JSON text without Unicode normalization. Escape spelling
    /// and object member order do not change the represented value.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.bool(left), .bool(right)): return left == right
        case let (.string(left), .string(right)): return left.utf8.elementsEqual(right.utf8)
        case let (.number(left), .number(right)): return left == right
        case let (.array(left), .array(right)): return left == right
        case let (.object(left), .object(right)):
            guard left.count == right.count else { return false }
            return left.allSatisfy { entry in
                guard let index = right.index(forKey: entry.key) else { return false }
                let other = right[index]
                return entry.key.utf8.elementsEqual(other.key.utf8) && entry.value == other.value
            }
        default: return false
        }
    }
    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, depth: 0)
    }
    private init(from decoder: Decoder, depth: Int) throws {
        guard depth <= 32 else { throw contractReject(decoder, "Evidence nesting exceeds 32") }
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Decimal.self), !v.isNaN {
            guard decoder.userInfo[evaluationPreflightKey] as? Bool == true else {
                throw contractReject(decoder, "Numeric evidence requires EvaluationReport.decode preflight")
            }
            self = .number(v)
        }
        else if var a = try? decoder.unkeyedContainer() {
            var values: [EvaluationJSONValue] = []
            while !a.isAtEnd { values.append(try .init(from: a.superDecoder(), depth: depth + 1)) }
            self = .array(values)
        } else {
            let o = try decoder.container(keyedBy: ContractBoundaryKey.self)
            var values: [String: EvaluationJSONValue] = [:]
            for key in o.allKeys { values[key.stringValue] = try .init(from: o.superDecoder(forKey: key), depth: depth + 1) }
            self = .object(values)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v):
            guard !v.isNaN else { throw EncodingError.invalidValue(v, .init(codingPath: encoder.codingPath, debugDescription: "Nonfinite evidence number")) }
            try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

private struct EvaluationReportWire: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let buildID: String
    public let buildRevision: Int
    public let catalogSnapshotID: String
    public let rulesetID: String
    public let rulesetVersion: String
    public let dependencyGraphID: String
    public let dependencyGraphRevision: Int
    public let evaluatedAt: String
    public let result: EvaluationResult
    public let deploymentReadiness: EvaluationReadiness
    public let findings: [EvaluationFinding]
    public let summary: EvaluationSummary
    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id = "id"
        case buildID = "build_id"
        case buildRevision = "build_revision"
        case catalogSnapshotID = "catalog_snapshot_id"
        case rulesetID = "ruleset_id"
        case rulesetVersion = "ruleset_version"
        case dependencyGraphID = "dependency_graph_id"
        case dependencyGraphRevision = "dependency_graph_revision"
        case evaluatedAt = "evaluated_at"
        case result = "result"
        case deploymentReadiness = "deployment_readiness"
        case findings = "findings"
        case summary = "summary"
    }
    public init(from decoder: Decoder) throws {
        try contractKeys(decoder, ["schema_version", "id", "build_id", "build_revision", "catalog_snapshot_id", "ruleset_id", "ruleset_version", "dependency_graph_id", "dependency_graph_revision", "evaluated_at", "result", "deployment_readiness", "findings", "summary"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        id = try c.decode(String.self, forKey: .id)
        buildID = try c.decode(String.self, forKey: .buildID)
        buildRevision = try c.decode(Int.self, forKey: .buildRevision)
        catalogSnapshotID = try c.decode(String.self, forKey: .catalogSnapshotID)
        rulesetID = try c.decode(String.self, forKey: .rulesetID)
        rulesetVersion = try c.decode(String.self, forKey: .rulesetVersion)
        dependencyGraphID = try c.decode(String.self, forKey: .dependencyGraphID)
        dependencyGraphRevision = try c.decode(Int.self, forKey: .dependencyGraphRevision)
        evaluatedAt = try c.decode(String.self, forKey: .evaluatedAt)
        result = try c.decode(EvaluationResult.self, forKey: .result)
        deploymentReadiness = try c.decode(EvaluationReadiness.self, forKey: .deploymentReadiness)
        findings = try c.decode([EvaluationFinding].self, forKey: .findings)
        summary = try c.decode(EvaluationSummary.self, forKey: .summary)

        guard schemaVersion == "1.0.0" else { throw contractReject(decoder, "Unsupported schema version") }
        guard [id, buildID, catalogSnapshotID, rulesetID, dependencyGraphID].allSatisfy(contractID),
              buildRevision >= 1, dependencyGraphRevision >= 1,
              contractMatches(rulesetVersion, "\\A[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?\\z")
        else { throw contractReject(decoder, "Invalid identity, revision or ruleset version") }
        guard contractTimestamp(evaluatedAt)
        else { throw contractReject(decoder, "Invalid or unsupported evaluation timestamp") }
    }
}

public struct EvaluationReport: Encodable, Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let buildID: String
    public let buildRevision: Int
    public let catalogSnapshotID: String
    public let rulesetID: String
    public let rulesetVersion: String
    public let dependencyGraphID: String
    public let dependencyGraphRevision: Int
    public let evaluatedAt: String
    public let result: EvaluationResult
    public let deploymentReadiness: EvaluationReadiness
    public let findings: [EvaluationFinding]
    public let summary: EvaluationSummary
    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id = "id"
        case buildID = "build_id"
        case buildRevision = "build_revision"
        case catalogSnapshotID = "catalog_snapshot_id"
        case rulesetID = "ruleset_id"
        case rulesetVersion = "ruleset_version"
        case dependencyGraphID = "dependency_graph_id"
        case dependencyGraphRevision = "dependency_graph_revision"
        case evaluatedAt = "evaluated_at"
        case result = "result"
        case deploymentReadiness = "deployment_readiness"
        case findings = "findings"
        case summary = "summary"
    }
    private init(_ wire: EvaluationReportWire) {
        schemaVersion = wire.schemaVersion
        id = wire.id
        buildID = wire.buildID
        buildRevision = wire.buildRevision
        catalogSnapshotID = wire.catalogSnapshotID
        rulesetID = wire.rulesetID
        rulesetVersion = wire.rulesetVersion
        dependencyGraphID = wire.dependencyGraphID
        dependencyGraphRevision = wire.dependencyGraphRevision
        evaluatedAt = wire.evaluatedAt
        result = wire.result
        deploymentReadiness = wire.deploymentReadiness
        findings = wire.findings
        summary = wire.summary
    }
}

public struct EvaluationFinding: Codable, Equatable, Sendable {
    public let ruleID: String
    public let outcome: EvaluationOutcome
    public let severity: EvaluationSeverity
    public let code: String
    public let message: String
    public let remediation: String?
    public let selectionIDs: [String]
    public let evidence: [EvaluationEvidence]?
    private enum CodingKeys: String, CodingKey {
        case ruleID = "rule_id"
        case outcome = "outcome"
        case severity = "severity"
        case code = "code"
        case message = "message"
        case remediation = "remediation"
        case selectionIDs = "selection_ids"
        case evidence = "evidence"
    }
    public init(from decoder: Decoder) throws {
        try contractKeys(decoder, ["rule_id", "outcome", "severity", "code", "message", "remediation", "selection_ids", "evidence"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ruleID = try c.decode(String.self, forKey: .ruleID)
        outcome = try c.decode(EvaluationOutcome.self, forKey: .outcome)
        severity = try c.decode(EvaluationSeverity.self, forKey: .severity)
        code = try c.decode(String.self, forKey: .code)
        message = try c.decode(String.self, forKey: .message)
        remediation = c.contains(.remediation) ? try c.decode(String.self, forKey: .remediation) : nil
        selectionIDs = try c.decode([String].self, forKey: .selectionIDs)
        evidence = c.contains(.evidence) ? try c.decode([EvaluationEvidence].self, forKey: .evidence) : nil

        guard contractID(ruleID), !message.isEmpty,
              contractMatches(code, "\\A[A-Z][A-Z0-9_]{2,80}\\z"),
              selectionIDs.allSatisfy({ contractMatches($0, "\\A[a-z][a-z0-9_-]{2,79}\\z") }),
              Set(selectionIDs).count == selectionIDs.count
        else { throw contractReject(decoder, "Invalid finding identity, code, message or selections") }
    }
}

public struct EvaluationEvidence: Codable, Equatable, Sendable {
    public let path: String
    public let observed: EvaluationJSONValue?
    public let expected: EvaluationJSONValue?
    public let sourceVersion: String?
    private enum CodingKeys: String, CodingKey {
        case path = "path"
        case observed = "observed"
        case expected = "expected"
        case sourceVersion = "source_version"
    }
    public init(from decoder: Decoder) throws {
        try contractKeys(decoder, ["path", "observed", "expected", "source_version"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        observed = c.contains(.observed) ? try c.decode(EvaluationJSONValue.self, forKey: .observed) : nil
        expected = c.contains(.expected) ? try c.decode(EvaluationJSONValue.self, forKey: .expected) : nil
        sourceVersion = c.contains(.sourceVersion) ? try c.decode(String.self, forKey: .sourceVersion) : nil
    }
}

public struct EvaluationSummary: Codable, Equatable, Sendable {
    public let passed: Int
    public let failed: Int
    public let unknown: Int
    public let skipped: Int
    private enum CodingKeys: String, CodingKey {
        case passed = "passed"
        case failed = "failed"
        case unknown = "unknown"
        case skipped = "skipped"
    }
    public init(from decoder: Decoder) throws {
        try contractKeys(decoder, ["passed", "failed", "unknown", "skipped"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        passed = try c.decode(Int.self, forKey: .passed)
        failed = try c.decode(Int.self, forKey: .failed)
        unknown = try c.decode(Int.self, forKey: .unknown)
        skipped = try c.decode(Int.self, forKey: .skipped)

        guard [passed, failed, unknown, skipped].allSatisfy({ $0 >= 0 })
        else { throw contractReject(decoder, "Negative summary count") }
    }
}

public enum EvaluationBoundaryError: Error, Equatable, Sendable {
    case unsupportedNumber
    case invalidUTF8
    case payloadTooLarge
}
private let evaluationPreflightKey = CodingUserInfoKey(rawValue: "PlannerCore.Evaluation.preflight")!

extension EvaluationReport {
    /// Maximum input size before any text decoding or parsing (4 MiB).
    public static let maximumPayloadBytes = 4 * 1024 * 1024

    /// Decode a bounded frozen-v1 report. Gregorian years 0001...9999 are supported;
    /// leap-second timestamps are rejected. Input is limited to 4 MiB.
    /// Numeric JSON tokens are limited to 15
    /// significant digits and normalized coefficient exponents -100...100 to prevent Decimal rounding.
    /// This representation limit is a client constraint, not a wire-schema change.
    public static func decode(_ data: Data) throws -> EvaluationReport {
        guard data.count <= maximumPayloadBytes else { throw EvaluationBoundaryError.payloadTooLarge }
        // Raw NUL is invalid JSON and can hide UTF-16/32 tokens from the UTF-8
        // numeric scan while Foundation detects a different encoding. Escaped
        // \u0000 remains valid; scan and decode must see the same numeric text.
        guard !data.contains(0), let text = String(data: data, encoding: .utf8)
        else { throw EvaluationBoundaryError.invalidUTF8 }
        try ContractJSONPreflight.validate(text)
        // Match strings first so digit sequences in IDs/messages are not numbers.
        let tokens = try NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"|(-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)"#)
        let ns = text as NSString
        for match in tokens.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard match.range(at: 1).location != NSNotFound else { continue }
            let token = ns.substring(with: match.range(at: 1))
            let parts = token.lowercased().split(separator: "e")
            let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
            let fractionCount = mantissa.count == 2 ? mantissa[1].count : 0
            let explicitExponent: Int
            if parts.count == 2 {
                guard let exponent = Int(parts[1]), (-maximumPayloadBytes...maximumPayloadBytes).contains(exponent)
                else { throw EvaluationBoundaryError.unsupportedNumber }
                explicitExponent = exponent
            } else { explicitExponent = 0 }
            var digits = Array(parts[0].filter { $0.isNumber })
            while digits.last == "0" { digits.removeLast() }
            let trailingZeros = parts[0].filter { $0.isNumber }.count - digits.count
            let significantDigits = digits.drop(while: { $0 == "0" }).count
            let normalizedExponent = significantDigits == 0 ? 0 : explicitExponent - fractionCount + trailingZeros
            guard significantDigits <= 15, (-100...100).contains(normalizedExponent)
            else { throw EvaluationBoundaryError.unsupportedNumber }
        }
        let decoder = JSONDecoder()
        decoder.userInfo[evaluationPreflightKey] = true
        return try EvaluationReport(decoder.decode(EvaluationReportWire.self, from: data))
    }
}
