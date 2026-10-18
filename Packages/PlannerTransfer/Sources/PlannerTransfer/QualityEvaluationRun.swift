import Foundation

/// A recorded label from a frozen-v1 evaluation record, not a client verdict.
public enum QualityEvaluationStatus: String, CaseIterable, Hashable, Sendable {
    case passed, failed, incomplete
}

/// The recorded comparison operator; decoding never evaluates it.
public enum QualityMeasurementComparator: String, CaseIterable, Hashable, Sendable {
    case gte, gt, lte, lt, eq
}

/// An immutable measurement supplied by the record, including its reported result.
public struct QualityMeasurement: Sendable, Equatable {
    public let value: JSONValue
    fileprivate init(value: JSONValue) { self.value = value }

    public var metric: String { value.object!["metric"]!.string! }
    public var observed: Decimal { value.object!["observed"]!.number! }
    public var threshold: Decimal { value.object!["threshold"]!.number! }
    public var comparator: QualityMeasurementComparator {
        QualityMeasurementComparator(rawValue: value.object!["comparator"]!.string!)!
    }
    public var unit: String? { value.object!["unit"]?.string }
    public var passed: Bool { value.object!["passed"]! == .bool(true) }
}

/// An immutable, structurally valid frozen-v1 record. This boundary neither runs an
/// evaluator nor verifies evidence, freshness, build/suite binding or reported labels.
public struct QualityEvaluationRun: Sendable, Equatable {
    private static let validator = try? FrozenValidator(schemaNames: ["quality-evaluation-run", "common"])
    public let value: JSONValue
    private init(value: JSONValue) { self.value = value }

    public var id: String { value.object!["id"]!.string! }
    public var buildID: String { value.object!["build_id"]!.string! }
    /// Exact integral Decimal within the existing bounded JSON numeric subset.
    public var buildRevision: Decimal { value.object!["build_revision"]!.number! }
    public var evaluationSuiteSelectionID: String { value.object!["evaluation_suite_selection_id"]!.string! }
    public var startedAt: String { value.object!["started_at"]!.string! }
    public var finishedAt: String { value.object!["finished_at"]!.string! }
    public var status: QualityEvaluationStatus {
        QualityEvaluationStatus(rawValue: value.object!["status"]!.string!)!
    }
    public var evaluatorVersion: String { value.object!["evaluator_version"]!.string! }
    public var datasetRevision: String { value.object!["dataset_revision"]!.string! }
    /// Exact positive integral Decimal; no narrowing to an Int or floating point.
    public var sampleSize: Decimal { value.object!["sample_size"]!.number! }
    public var measurements: [QualityMeasurement] {
        value.object!["measurements"]!.array!.map { QualityMeasurement(value: $0) }
    }
    /// Inert URI strings retained for local inspection; decoding does not fetch them.
    public var artifacts: [String] { value.object!["artifacts"]!.array!.map { $0.string! } }
    /// Absence, an empty array and empty note strings remain distinct.
    public var notes: [String]? { value.object!["notes"]?.array?.map { $0.string! } }

    public static func decode(_ data: Data) throws -> Self {
        var parser = try JSONParser(data)
        let value = try parser.parse()
        guard let validator = Self.validator else { throw TransferError.unavailableSchema }
        try validator.validateQualityEvaluationRun(value)
        return Self(value: value)
    }

    /// Local serialization only; notes, labels and artifact URIs remain untrusted
    /// private content. This does not sanitize, publish, authenticate or evaluate them.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        var parser = try JSONParser(data)
        guard try parser.parse() == value else { throw TransferError.unsupportedNumber }
        return data
    }
}
