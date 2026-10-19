import Foundation

/// Comparison admission is stricter than the frozen record decoder. Fixed error
/// cases contain no supplied measurements, notes, artifact URI or workload text.
public enum HistoricalQualityComparisonError: Error, Equatable, Sendable {
    case buildMismatch, ambiguousSelectionIdentity, unknownEvaluationSuite
    case invalidEvaluationSuiteKind, ambiguousMetricIdentity, conflictingRunIdentity
}

/// A reported quality run attached to the exact saved build and suite selection
/// it names. Identity binding does not verify execution, chronology or labels.
/// Complete original values remain private local records, not a sharing projection.
public struct HistoricalQualityScenario: Equatable, Sendable {
    public let build: BuildSnapshot
    public let run: QualityEvaluationRun
    public let evaluationSuite: JSONValue

    public init(build: BuildSnapshot, run: QualityEvaluationRun) throws {
        guard build.id.utf8.elementsEqual(run.buildID.utf8),
              build.value.object!["revision"]!.number! == run.buildRevision else {
            throw HistoricalQualityComparisonError.buildMismatch
        }
        // Frozen selection IDs are ASCII. Other selections must not silently
        // replace one another just because this run names a different suite.
        var selections: [String: JSONValue] = [:]
        for selection in build.value.object!["selections"]!.array! {
            let id = selection.object!["id"]!.string!
            guard selections.updateValue(selection, forKey: id) == nil else {
                throw HistoricalQualityComparisonError.ambiguousSelectionIdentity
            }
        }
        guard let suite = selections[run.evaluationSuiteSelectionID] else {
            throw HistoricalQualityComparisonError.unknownEvaluationSuite
        }
        guard suite.object!["kind"] == .string("evaluation_suite") else {
            throw HistoricalQualityComparisonError.invalidEvaluationSuiteKind
        }
        // A metric is an opaque decoded UTF-8 identity. The frozen reader permits
        // repeated metric names, but this display join cannot choose a duplicate.
        var metrics = Set<Data>()
        for measurement in run.measurements {
            guard metrics.insert(Data(measurement.metric.utf8)).inserted else {
                throw HistoricalQualityComparisonError.ambiguousMetricIdentity
            }
        }
        self.build = build
        self.run = run
        self.evaluationSuite = suite
    }
}

public enum HistoricalQualityField: String, CaseIterable, Sendable {
    case buildID, buildRevision, buildLocks, evaluationSuiteSelection
    case runID, startedAt, finishedAt, status, evaluatorVersion, datasetRevision
    case sampleSize, artifacts, notes
}

/// These are reasons to retain the separate recorded conditions. An empty list
/// beyond reportedValuesOnly never establishes qualified or comparable evidence.
public enum HistoricalQualityCaution: String, Sendable {
    case reportedValuesOnly, differentConfigurations, differentEvaluationSuites
    case differentEvaluatorVersions, differentDatasets, differentSampleSizes
    case beforeIncompleteRun, afterIncompleteRun, beforeDisabledSuite, afterDisabledSuite
}

public enum HistoricalQualityMeasurementCaution: String, Sendable {
    case beforeAbsent, afterAbsent
    case beforeUnitAbsent, afterUnitAbsent, beforeUnitEmpty, afterUnitEmpty
    case differentUnits, differentThresholds, differentComparators
}

/// Every metric remains inspectable, including unchanged rows. A join is only a
/// display coordinate: each side keeps its own observed value, threshold, unit,
/// comparator and reported result. Nil means absent, never an invented zero.
public struct HistoricalQualityMeasurementComparison: Equatable, Sendable {
    public let metric: String
    public let before: QualityMeasurement?
    public let after: QualityMeasurement?
    public let cautions: [HistoricalQualityMeasurementCaution]
    public var hasChanges: Bool { before != after }
}

/// Local side-by-side inspection, with the existing structural configuration
/// comparison attached. No score delta, normalization, ranking, result evaluation
/// or transfer of evidence to another build is performed.
public struct HistoricalQualityComparison: Equatable, Sendable {
    public let before: HistoricalQualityScenario
    public let after: HistoricalQualityScenario
    public let configuration: BuildComparison
    public let changedFields: [HistoricalQualityField]
    public let measurements: [HistoricalQualityMeasurementComparison]
    public let cautions: [HistoricalQualityCaution]

    public static func compare(_ before: HistoricalQualityScenario,
                               _ after: HistoricalQualityScenario) throws -> Self {
        let left = before.run, right = after.run
        if left.id.utf8.elementsEqual(right.id.utf8), left.value != right.value {
            throw HistoricalQualityComparisonError.conflictingRunIdentity
        }
        // Reuse the immutable-revision, duplicate-link, bounded-difference and
        // privacy guards already used by configuration comparison.
        let configuration = try BuildComparison.compare(before.build, after.build)
        var fields: [HistoricalQualityField] = []
        if !left.buildID.utf8.elementsEqual(right.buildID.utf8) { fields.append(.buildID) }
        if left.buildRevision != right.buildRevision { fields.append(.buildRevision) }
        if before.build.locks != after.build.locks { fields.append(.buildLocks) }
        if before.evaluationSuite != after.evaluationSuite { fields.append(.evaluationSuiteSelection) }
        let names: [(HistoricalQualityField, String)] = [
            (.runID, "id"), (.startedAt, "started_at"), (.finishedAt, "finished_at"),
            (.status, "status"), (.evaluatorVersion, "evaluator_version"),
            (.datasetRevision, "dataset_revision"), (.sampleSize, "sample_size"),
            (.artifacts, "artifacts"), (.notes, "notes"),
        ]
        for (field, key) in names where left.value.object![key] != right.value.object![key] {
            fields.append(field)
        }
        let leftRows = Dictionary(uniqueKeysWithValues: left.measurements.map { (Data($0.metric.utf8), $0) })
        let rightRows = Dictionary(uniqueKeysWithValues: right.measurements.map { (Data($0.metric.utf8), $0) })
        let keys = Set(leftRows.keys).union(rightRows.keys).sorted { $0.lexicographicallyPrecedes($1) }
        let measurements = keys.map { key in
            let a = leftRows[key], b = rightRows[key]
            return HistoricalQualityMeasurementComparison(
                metric: a?.metric ?? b!.metric, before: a, after: b, cautions: measurementCautions(a, b))
        }
        var cautions: [HistoricalQualityCaution] = [.reportedValuesOnly]
        if !configuration.differences.isEmpty { cautions.append(.differentConfigurations) }
        if before.evaluationSuite != after.evaluationSuite { cautions.append(.differentEvaluationSuites) }
        if !left.evaluatorVersion.utf8.elementsEqual(right.evaluatorVersion.utf8) {
            cautions.append(.differentEvaluatorVersions)
        }
        if !left.datasetRevision.utf8.elementsEqual(right.datasetRevision.utf8) {
            cautions.append(.differentDatasets)
        }
        if left.sampleSize != right.sampleSize { cautions.append(.differentSampleSizes) }
        if left.status == .incomplete { cautions.append(.beforeIncompleteRun) }
        if right.status == .incomplete { cautions.append(.afterIncompleteRun) }
        if before.evaluationSuite.object!["enabled"] == .bool(false) { cautions.append(.beforeDisabledSuite) }
        if after.evaluationSuite.object!["enabled"] == .bool(false) { cautions.append(.afterDisabledSuite) }
        return Self(before: before, after: after, configuration: configuration,
                    changedFields: fields, measurements: measurements, cautions: cautions)
    }

    private static func measurementCautions(_ before: QualityMeasurement?,
                                            _ after: QualityMeasurement?) -> [HistoricalQualityMeasurementCaution] {
        var result: [HistoricalQualityMeasurementCaution] = []
        if let before {
            if before.unit == nil { result.append(.beforeUnitAbsent) }
            else if before.unit!.isEmpty { result.append(.beforeUnitEmpty) }
        } else { result.append(.beforeAbsent) }
        if let after {
            if after.unit == nil { result.append(.afterUnitAbsent) }
            else if after.unit!.isEmpty { result.append(.afterUnitEmpty) }
        } else { result.append(.afterAbsent) }
        if let before, let after {
            // Optional JSON values retain absent versus empty units and exact text.
            if before.value.object!["unit"] != after.value.object!["unit"] { result.append(.differentUnits) }
            if before.threshold != after.threshold { result.append(.differentThresholds) }
            if before.comparator != after.comparator { result.append(.differentComparators) }
        }
        return result
    }
}
