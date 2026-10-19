import Foundation
import PlannerCore

/// Observations about the supplied records, not failures of frozen-v1 decoding.
/// A manual override or differently spelled decimal can explain a difference;
/// this consumer does not decide whether that explanation is acceptable.
public enum RecordedCostRateIssue: String, Equatable, Sendable {
    case estimateBuildIDDiffers, estimateBuildRevisionDiffers
    case buildPricebookLockMissing, buildPricebookLockDiffers
    case pricebookNotSupplied, suppliedPricebookIDDiffers, estimateCurrencyDiffersFromBuild
    case duplicateLineID, selectionNotFoundInSuppliedBuild, selectionIDAmbiguous, selectionDisabled
    case rateNotFoundInSuppliedPricebook, rateIDAmbiguous
    case catalogItemIDDiffers, catalogItemVersionDiffers, meterDiffers
    case unitPriceCurrencyDiffers, unitPriceAmountTextDiffers
    case lineUnitPriceCurrencyDiffersFromEstimate, lineAmountCurrencyDiffersFromEstimate
}

/// These limitations apply even when every supplied identity and field matches.
public enum RecordedCostRateLimitation: String, CaseIterable, Equatable, Sendable {
    case pricebookRevisionNotRecorded
    case rateApplicabilityNotAssessed
    case sourceDeclarationsNotVerified
    case arithmeticAndCoverageNotAssessed
}

/// The complete original selection at one position in the supplied Build.
/// Its settings and private text are retained for local inspection, not export.
public struct RecordedCostRateSelection: Equatable, Sendable {
    public let position: Int
    public let value: JSONValue
    fileprivate init(position: Int, value: JSONValue) {
        self.position = position; self.value = value
    }
    public var id: String { value.object!["id"]!.string! }
    public var catalogItemID: String { value.object!["catalog_item_id"]!.string! }
    public var catalogItemVersion: String { value.object!["catalog_item_version"]!.string! }
    public var enabled: Bool { value.object!["enabled"]! == .bool(true) }
}

/// One original estimate row, including duplicates and original ordering.
/// Candidates are unique ID matches within the supplied inputs, not proof that
/// a rate was applicable or produced the estimate. Nil never means free or zero.
public struct RecordedCostRateLine: Sendable {
    public let position: Int
    public let line: CostEstimateLineItem
    public let candidateSelection: RecordedCostRateSelection?
    public let candidateRate: PriceRate?
    public let selectionMatchCount: Int
    public let rateMatchCount: Int
    /// Includes the enclosing input issues so a row cannot hide a foreign Build
    /// or Pricebook merely because the referenced IDs happen to exist in it.
    public let issues: [RecordedCostRateIssue]
}

/// Local, read-only inspection of the rate references in a retained estimate.
/// The existing typed readers own structural admission. This initializer never
/// rejects or repairs a valid input record, selects a substitute rate, evaluates
/// dates/regions, authenticates evidence, calculates costs or grants currentness.
/// All originals may contain private text and have no public sharing projection.
public struct RecordedCostRateProvenance: Sendable {
    public let build: BuildSnapshot
    public let estimate: CostEstimateRecord
    public let pricebook: Pricebook?
    public let inputIssues: [RecordedCostRateIssue]
    public let lines: [RecordedCostRateLine]
    public let limitations = RecordedCostRateLimitation.allCases

    public init(build: BuildSnapshot, estimate: CostEstimateRecord, pricebook: Pricebook?) {
        var inputIssues: [RecordedCostRateIssue] = []
        if !Self.sameText(build.id, estimate.buildID) { inputIssues.append(.estimateBuildIDDiffers) }
        if build.value.object!["revision"]!.number! != estimate.buildRevision {
            inputIssues.append(.estimateBuildRevisionDiffers)
        }
        if let lock = build.locks.object!["pricebook_id"]?.string {
            if !Self.sameText(lock, estimate.pricebookID) { inputIssues.append(.buildPricebookLockDiffers) }
        } else { inputIssues.append(.buildPricebookLockMissing) }
        if let pricebook {
            if !Self.sameText(pricebook.id, estimate.pricebookID) { inputIssues.append(.suppliedPricebookIDDiffers) }
        } else { inputIssues.append(.pricebookNotSupplied) }
        if !Self.sameText(build.value.object!["objectives"]!.object!["currency"]!.string!, estimate.currency) {
            inputIssues.append(.estimateCurrencyDiffersFromBuild)
        }

        // Frozen IDs are ASCII. Group rather than overwrite duplicates, and
        // build the indexes once so inspection is linear in the supplied rows.
        let selections = build.value.object!["selections"]!.array!.enumerated().map {
            RecordedCostRateSelection(position: $0.offset, value: $0.element)
        }
        let selectionsByID = Dictionary(grouping: selections, by: \.id)
        let ratesByID = Dictionary(grouping: pricebook?.rates ?? [], by: \.id)
        let recordedLines = estimate.lineItems
        let lineCounts = Dictionary(grouping: recordedLines, by: \.id).mapValues(\.count)
        let lines = recordedLines.enumerated().map { position, line in
            let selectionMatches = selectionsByID[line.selectionID] ?? []
            let rateMatches = ratesByID[line.priceRateID] ?? []
            let selection = selectionMatches.count == 1 ? selectionMatches.first : nil
            let rate = rateMatches.count == 1 ? rateMatches.first : nil
            var issues = inputIssues
            if lineCounts[line.id, default: 0] > 1 { issues.append(.duplicateLineID) }
            if selectionMatches.isEmpty { issues.append(.selectionNotFoundInSuppliedBuild) }
            if selectionMatches.count > 1 { issues.append(.selectionIDAmbiguous) }
            if selection?.enabled == false { issues.append(.selectionDisabled) }
            if pricebook != nil && rateMatches.isEmpty { issues.append(.rateNotFoundInSuppliedPricebook) }
            if rateMatches.count > 1 { issues.append(.rateIDAmbiguous) }
            if let selection, let rate {
                if !Self.sameText(selection.catalogItemID, rate.catalogItemID) { issues.append(.catalogItemIDDiffers) }
                if !Self.sameText(selection.catalogItemVersion, rate.catalogItemVersion) {
                    issues.append(.catalogItemVersionDiffers)
                }
            }
            if let rate {
                if line.meter.rawValue != rate.meter.rawValue { issues.append(.meterDiffers) }
                if !Self.sameText(line.unitPrice.currency, rate.unitPrice.currency) { issues.append(.unitPriceCurrencyDiffers) }
                // ContractDecimal equality is numeric; this inspection instead
                // reports different recorded text such as 0.80 versus 0.8000.
                if !Self.sameText(line.unitPrice.amount, rate.unitPrice.amount.rawValue) {
                    issues.append(.unitPriceAmountTextDiffers)
                }
            }
            if !Self.sameText(line.unitPrice.currency, estimate.currency) {
                issues.append(.lineUnitPriceCurrencyDiffersFromEstimate)
            }
            if !Self.sameText(line.amount.currency, estimate.currency) {
                issues.append(.lineAmountCurrencyDiffersFromEstimate)
            }
            return RecordedCostRateLine(position: position, line: line,
                candidateSelection: selection, candidateRate: rate,
                selectionMatchCount: selectionMatches.count, rateMatchCount: rateMatches.count, issues: issues)
        }
        self.build = build; self.estimate = estimate; self.pricebook = pricebook
        self.inputIssues = inputIssues; self.lines = lines
    }

    private static func sameText(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }
}
