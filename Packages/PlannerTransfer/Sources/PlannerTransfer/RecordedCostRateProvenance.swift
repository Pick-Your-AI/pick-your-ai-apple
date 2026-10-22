import Foundation
import PlannerCore

/// Observations about the supplied records, not failures of frozen-v1 decoding.
/// A manual override or differently spelled decimal can explain a difference;
/// this consumer does not decide whether that explanation is acceptable.
public enum RecordedCostRateIssue: String, Hashable, Sendable {
    case estimateBuildIDDiffers, estimateBuildRevisionDiffers
    case buildPricebookLockMissing, buildPricebookLockDiffers
    case pricebookNotSupplied, suppliedPricebookIDDiffers, estimateCurrencyDiffersFromBuild
    case duplicateLineID, selectionNotFoundInSuppliedBuild, selectionIDAmbiguous, selectionDisabled
    case rateNotFoundInSuppliedPricebook, rateIDAmbiguous
    case catalogItemIDDiffers, catalogItemVersionDiffers, meterDiffers
    case unitPriceCurrencyDiffers
    /// Same numeric value, different recorded spelling (for example 0.80 and 0.8000).
    case unitPriceAmountTextDiffers
    /// Different numeric value (for example 0.80 and 8.00), compared exactly.
    case unitPriceAmountValueDiffers
    /// Both regions are recorded text; an absent rate region is not a difference.
    case rateRegionDiffersFromBuildObjective
    /// The rate's own recorded validUntil is strictly earlier than its validFrom.
    case rateValidityWindowInverted
    /// The estimate's recorded estimatedAt is strictly outside the rate's recorded
    /// window. No current clock is read; boundary inclusivity is not decided.
    case estimatedAtBeforeRateValidFrom, estimatedAtAfterRateValidUntil
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
public struct RecordedCostRateLine: Equatable, Sendable {
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
/// rejects or repairs a valid input record, selects a substitute rate, reads a
/// clock, decides applicability or expiry, authenticates evidence, calculates
/// costs or grants currentness. It only reports recorded region and
/// validity-window differences among the supplied records.
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
        let objectiveRegion = build.value.object!["objectives"]!.object!["region"]!.string!
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
                // Different spelling is reported even for equal values; a numeric
                // difference (exact scaled-digit comparison, never Double) is a
                // distinct code and is not also reported as spelling.
                if !Self.sameText(line.unitPrice.amount, rate.unitPrice.amount.rawValue) {
                    if let recorded = try? ContractDecimal(line.unitPrice.amount),
                       recorded != rate.unitPrice.amount {
                        issues.append(.unitPriceAmountValueDiffers)
                    } else {
                        issues.append(.unitPriceAmountTextDiffers)
                    }
                }
                if let region = rate.region, !Self.sameText(region, objectiveRegion) {
                    issues.append(.rateRegionDiffersFromBuildObjective)
                }
                // Recorded declarations only: the estimate's own estimatedAt, not a clock.
                let from = RecordedInstant(rate.validFrom)
                let until = rate.validUntil.flatMap { RecordedInstant($0) }
                if let from, let until, until < from { issues.append(.rateValidityWindowInverted) }
                if let at = RecordedInstant(estimate.estimatedAt) {
                    if let from, at < from { issues.append(.estimatedAtBeforeRateValidFrom) }
                    if let until, until < at { issues.append(.estimatedAtAfterRateValidUntil) }
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

/// An exact UTC instant from a frozen-v1 timestamp, using integer arithmetic only.
/// Fraction digits are kept as text (trailing zeros trimmed) so no Double is used.
private struct RecordedInstant: Comparable {
    let seconds: Int
    let fraction: [UInt8]

    init?(_ text: String) {
        let bytes = Array(text.utf8)
        guard bytes.count >= 20 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                guard index < bytes.count, (48...57).contains(bytes[index]) else { return nil }
                value = value * 10 + Int(bytes[index] - 48)
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              (1...12).contains(month) else { return nil }
        var index = 19
        var digits: [UInt8] = []
        if bytes[index] == 46 {
            index += 1
            while index < bytes.count, (48...57).contains(bytes[index]) {
                digits.append(bytes[index]); index += 1
            }
            while digits.last == 48 { digits.removeLast() }
        }
        guard index < bytes.count else { return nil }
        var offset = 0
        if bytes[index] == 90 || bytes[index] == 122 {
            guard index == bytes.count - 1 else { return nil }
        } else if bytes[index] == 43 || bytes[index] == 45 {
            guard index + 6 == bytes.count, let offsetHour = number((index + 1)..<(index + 3)),
                  let offsetMinute = number((index + 4)..<(index + 6)) else { return nil }
            offset = (offsetHour * 3600 + offsetMinute * 60) * (bytes[index] == 45 ? -1 : 1)
        } else { return nil }
        // Days from civil date (proleptic Gregorian), then UTC seconds.
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = shiftedYear / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146097 + dayOfEra - 719468
        seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset
        fraction = digits
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
        return lhs.fraction.lexicographicallyPrecedes(rhs.fraction)
    }
}
