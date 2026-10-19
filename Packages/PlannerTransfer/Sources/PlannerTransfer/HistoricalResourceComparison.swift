import Foundation

/// Relationship errors contain no supplied identifiers, assumptions or source text.
public enum HistoricalResourceComparisonError: Error, Equatable, Sendable {
    case buildMismatch, ambiguousSelectionIdentity, unknownSelection
    case conflictingEstimateIdentity
}

/// One original reported row and the selections it names in its own saved build.
/// These complete local values may contain private settings or assumptions. They
/// are not a sharing projection, a verified measurement or an applicability verdict.
public struct HistoricalResourceRow: Equatable, Sendable {
    public let record: JSONValue
    /// Same order as this row's selection_ids; no current-build substitution.
    public let selections: [JSONValue]

    fileprivate init(record: JSONValue, selections: [JSONValue]) {
        self.record = record
        self.selections = selections
    }

    public var metric: String { record.object!["metric"]!.string! }
    public var reportedValue: String { record.object!["value"]!.string! }
    public var unit: String { record.object!["unit"]!.string! }
    public var estimatorID: String { record.object!["estimator_id"]!.string! }
    public var estimatorVersion: String { record.object!["estimator_version"]!.string! }
    public var reportedConfidence: String { record.object!["confidence"]!.string! }
    /// Nil preserves absence. A present source is inert text, not inspected evidence.
    public var sourceURI: String? { record.object!["source_uri"]?.string }
    public var assumptions: [String] { record.object!["assumptions"]!.array!.map { $0.string! } }
    public var selectionIDs: [String] { record.object!["selection_ids"]!.array!.map { $0.string! } }
}

/// An immutable estimate attached only to the saved build/revision it names.
/// Admission resolves local identities; it does not validate estimator policy,
/// confidence, metric/unit compatibility, runtime topology or current capacity.
public struct HistoricalResourceScenario: Equatable, Sendable {
    public let build: BuildSnapshot
    public let estimate: ResourceEstimate
    public let rows: [HistoricalResourceRow]

    public init(build: BuildSnapshot, estimate: ResourceEstimate) throws {
        guard build.id.utf8.elementsEqual(estimate.buildID.utf8),
              build.value.object!["revision"]!.number! == estimate.buildRevision else {
            throw HistoricalResourceComparisonError.buildMismatch
        }
        // Frozen selection IDs are ASCII. Reject ambiguity across the complete
        // build before resolving even an apparently unambiguous estimate row.
        var selections: [String: JSONValue] = [:]
        for selection in build.value.object!["selections"]!.array! {
            let id = selection.object!["id"]!.string!
            guard selections.updateValue(selection, forKey: id) == nil else {
                throw HistoricalResourceComparisonError.ambiguousSelectionIdentity
            }
        }
        let rows = try estimate.estimates.map { record in
            let selected = try record.object!["selection_ids"]!.array!.map { value in
                guard let selection = selections[value.string!] else {
                    throw HistoricalResourceComparisonError.unknownSelection
                }
                return selection
            }
            return HistoricalResourceRow(record: record, selections: selected)
        }
        self.build = build
        self.estimate = estimate
        self.rows = rows
    }
}

public enum HistoricalResourceField: String, CaseIterable, Sendable {
    case buildID, buildRevision, buildLocks, estimateID, generatedAt, estimates
}

/// Identity and row-availability disclosures, never a statement that other
/// conditions match or that any supplied confidence label has been verified.
public enum HistoricalResourceCaution: String, Sendable {
    case reportedValuesOnly, differentBuilds, differentBuildRevisions, differentBuildLocks
    case unmatchedMetrics, beforeRepeatedMetrics, afterRepeatedMetrics
}

/// Frozen v1 has no estimate-row ID and permits repeated metrics. A metric is a
/// display group only: every row is retained in source order on its own side.
/// Array positions do not pair rows, and an empty side means no supplied row,
/// not zero, unavailable historical storage, or a newly computed replacement.
public struct HistoricalResourceMetricGroup: Equatable, Sendable {
    public let metric: String
    public let beforeRows: [HistoricalResourceRow]
    public let afterRows: [HistoricalResourceRow]
}

/// Read-only local comparison of supplied historical records. This performs no
/// arithmetic, row matching, ranking, resource estimation or evidence verification.
/// The original scenarios and row bindings are private local inspection values;
/// rendering/export must apply their own disclosure and receiving boundaries.
public struct HistoricalResourceComparison: Equatable, Sendable {
    public let before: HistoricalResourceScenario
    public let after: HistoricalResourceScenario
    public let configuration: BuildComparison
    public let changedFields: [HistoricalResourceField]
    public let metricGroups: [HistoricalResourceMetricGroup]
    public let cautions: [HistoricalResourceCaution]

    public static func compare(_ before: HistoricalResourceScenario,
                               _ after: HistoricalResourceScenario) throws -> Self {
        let left = before.estimate, right = after.estimate
        if left.id.utf8.elementsEqual(right.id.utf8), left.value != right.value {
            throw HistoricalResourceComparisonError.conflictingEstimateIdentity
        }
        // Always retain the existing immutable-revision, duplicate-link, private
        // field and difference-budget guards, including across different builds.
        let configuration = try BuildComparison.compare(before.build, after.build)
        var fields: [HistoricalResourceField] = []
        if !left.buildID.utf8.elementsEqual(right.buildID.utf8) { fields.append(.buildID) }
        if left.buildRevision != right.buildRevision { fields.append(.buildRevision) }
        if before.build.locks != after.build.locks { fields.append(.buildLocks) }
        let names: [(HistoricalResourceField, String)] = [
            (.estimateID, "id"), (.generatedAt, "generated_at"), (.estimates, "estimates"),
        ]
        for (field, key) in names where left.value.object![key] != right.value.object![key] {
            fields.append(field)
        }
        let leftGroups = Dictionary(grouping: before.rows, by: \.metric)
        let rightGroups = Dictionary(grouping: after.rows, by: \.metric)
        // Metric names are the frozen ASCII enum. Grouping neither sorts rows nor
        // chooses a duplicate, even when two rows are completely identical.
        let groups = Set(leftGroups.keys).union(rightGroups.keys).sorted().map { metric in
            HistoricalResourceMetricGroup(metric: metric, beforeRows: leftGroups[metric] ?? [],
                                          afterRows: rightGroups[metric] ?? [])
        }
        var cautions: [HistoricalResourceCaution] = [.reportedValuesOnly]
        if fields.contains(.buildID) { cautions.append(.differentBuilds) }
        if fields.contains(.buildRevision) { cautions.append(.differentBuildRevisions) }
        if fields.contains(.buildLocks) { cautions.append(.differentBuildLocks) }
        if groups.contains(where: { $0.beforeRows.isEmpty || $0.afterRows.isEmpty }) {
            cautions.append(.unmatchedMetrics)
        }
        if groups.contains(where: { $0.beforeRows.count > 1 }) { cautions.append(.beforeRepeatedMetrics) }
        if groups.contains(where: { $0.afterRows.count > 1 }) { cautions.append(.afterRepeatedMetrics) }
        return Self(before: before, after: after, configuration: configuration,
                    changedFields: fields, metricGroups: groups, cautions: cautions)
    }
}
