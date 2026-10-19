import Foundation

/// Comparison admission is stricter than the frozen record decoder. Errors carry
/// no workload, assumption, warning, credential or other supplied payload.
public enum HistoricalCostComparisonError: Error, Equatable, Sendable {
    case buildMismatch, pricebookMismatch, ambiguousSelectionIdentity
    case unknownSelection, ambiguousLineIdentity, conflictingEstimateIdentity
}

/// A reported estimate attached to the exact saved configuration it names.
/// This validates local identity relationships, not rates, arithmetic or coverage.
/// Both original values remain available for local inspection and serialization;
/// they may contain private text and are not a public sharing projection.
public struct HistoricalCostScenario: Equatable, Sendable {
    public let build: BuildSnapshot
    public let estimate: CostEstimateRecord

    public init(build: BuildSnapshot, estimate: CostEstimateRecord) throws {
        guard build.id.utf8.elementsEqual(estimate.buildID.utf8),
              build.value.object!["revision"]!.number! == estimate.buildRevision else {
            throw HistoricalCostComparisonError.buildMismatch
        }
        guard let pricebook = build.locks.object?["pricebook_id"]?.string,
              pricebook.utf8.elementsEqual(estimate.pricebookID.utf8) else {
            throw HistoricalCostComparisonError.pricebookMismatch
        }
        // Frozen selection/line identifiers are ASCII. Detect ambiguity rather
        // than allowing a dictionary insertion to silently replace a record.
        var selectionIDs = Set<String>()
        for selection in build.value.object!["selections"]!.array! {
            guard selectionIDs.insert(selection.object!["id"]!.string!).inserted else {
                throw HistoricalCostComparisonError.ambiguousSelectionIdentity
            }
        }
        var lineIDs = Set<String>()
        for line in estimate.lineItems {
            guard lineIDs.insert(line.id).inserted else {
                throw HistoricalCostComparisonError.ambiguousLineIdentity
            }
            guard selectionIDs.contains(line.selectionID) else {
                throw HistoricalCostComparisonError.unknownSelection
            }
        }
        guard estimate.unpricedSelectionIDs.allSatisfy(selectionIDs.contains) else {
            throw HistoricalCostComparisonError.unknownSelection
        }
        self.build = build
        self.estimate = estimate
    }
}

public enum HistoricalCostField: String, CaseIterable, Sendable {
    case buildID, buildRevision, buildLocks, estimateID, pricebookID, estimatedAt
    case periodDays, currency, subtotal, tax, total, coverage, unpricedSelectionIDs, warnings
}

/// These are reasons to keep the original sides separate. Even matching complete
/// labels do not establish measured usage, applicable rates or a correct total.
public enum HistoricalCostCaution: String, Sendable {
    case reportedValuesOnly, differentPricebooks, differentCurrencies, differentPeriods
    case beforeIncompleteCoverage, afterIncompleteCoverage
    case beforeUnpricedSelections, afterUnpricedSelections
    case beforeMixedCurrencies, afterMixedCurrencies
}

/// A line ID is a display join only. Each complete side retains its own selection,
/// rate, meter, units, method, confidence and assumptions. Nil means absent, not zero.
public struct HistoricalCostLineChange: Equatable, Sendable {
    public let id: String
    public let before: CostEstimateLineItem?
    public let after: CostEstimateLineItem?
}

/// Side-by-side historical records with no mutation, conversion, recomputation,
/// ranking, budget verdict or implied current quote. Rendering must retain the
/// cautions and label coverage/method/confidence as reported rather than verified.
public struct HistoricalCostComparison: Equatable, Sendable {
    public let before: HistoricalCostScenario
    public let after: HistoricalCostScenario
    public let changedFields: [HistoricalCostField]
    public let lineChanges: [HistoricalCostLineChange]
    public let cautions: [HistoricalCostCaution]

    public static func compare(_ before: HistoricalCostScenario,
                               _ after: HistoricalCostScenario) throws -> Self {
        let left = before.estimate, right = after.estimate
        if left.id.utf8.elementsEqual(right.id.utf8), left.value != right.value {
            // Two different records cannot silently use one historical identity.
            throw HistoricalCostComparisonError.conflictingEstimateIdentity
        }
        if before.build.id.utf8.elementsEqual(after.build.id.utf8),
           left.buildRevision == right.buildRevision {
            // Reuse the existing revision guard, including its order-independent
            // selection/link identity handling and private-field protections.
            _ = try BuildComparison.compare(before.build, after.build)
        }
        var fields: [HistoricalCostField] = []
        if !left.buildID.utf8.elementsEqual(right.buildID.utf8) { fields.append(.buildID) }
        if left.buildRevision != right.buildRevision { fields.append(.buildRevision) }
        if before.build.locks != after.build.locks { fields.append(.buildLocks) }
        let names: [(HistoricalCostField, String)] = [
            (.estimateID, "id"), (.pricebookID, "pricebook_id"), (.estimatedAt, "estimated_at"),
            (.periodDays, "period_days"), (.currency, "currency"), (.subtotal, "subtotal"),
            (.tax, "tax"), (.total, "total"), (.coverage, "coverage"),
            (.unpricedSelectionIDs, "unpriced_selection_ids"), (.warnings, "warnings"),
        ]
        for (field, key) in names where left.value.object![key] != right.value.object![key] {
            fields.append(field)
        }
        // Admission above established unique IDs; joining never chooses an
        // arbitrary duplicate. Stable ordering is independent of capture row order.
        let leftLines = Dictionary(uniqueKeysWithValues: left.lineItems.map { ($0.id, $0) })
        let rightLines = Dictionary(uniqueKeysWithValues: right.lineItems.map { ($0.id, $0) })
        let changes = Set(leftLines.keys).union(rightLines.keys).sorted().compactMap { id -> HistoricalCostLineChange? in
            guard leftLines[id] != rightLines[id] else { return nil }
            return HistoricalCostLineChange(id: id, before: leftLines[id], after: rightLines[id])
        }
        var cautions: [HistoricalCostCaution] = [.reportedValuesOnly]
        if !left.pricebookID.utf8.elementsEqual(right.pricebookID.utf8) { cautions.append(.differentPricebooks) }
        if left.currency != right.currency { cautions.append(.differentCurrencies) }
        if left.periodDays != right.periodDays { cautions.append(.differentPeriods) }
        if left.coverage != .complete { cautions.append(.beforeIncompleteCoverage) }
        if right.coverage != .complete { cautions.append(.afterIncompleteCoverage) }
        if !left.unpricedSelectionIDs.isEmpty { cautions.append(.beforeUnpricedSelections) }
        if !right.unpricedSelectionIDs.isEmpty { cautions.append(.afterUnpricedSelections) }
        if hasMixedCurrencies(left) { cautions.append(.beforeMixedCurrencies) }
        if hasMixedCurrencies(right) { cautions.append(.afterMixedCurrencies) }
        return Self(before: before, after: after, changedFields: fields,
                    lineChanges: changes, cautions: cautions)
    }

    private static func hasMixedCurrencies(_ record: CostEstimateRecord) -> Bool {
        if [record.subtotal, record.tax, record.total].contains(where: { $0.currency != record.currency }) {
            return true
        }
        return record.lineItems.contains {
            $0.unitPrice.currency != record.currency || $0.amount.currency != record.currency
        }
    }
}
