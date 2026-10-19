import PlannerCore

/// Display state for an existing qualified projection. This does not derive
/// current rates, complete coverage or a quote from a decoded wire record.
enum CostCoverageDisplayState: Equatable, Sendable {
    case unavailable, differentRevision, unknown, partial, complete, inconsistent
}

struct CostCoveragePresentation: Equatable, Sendable {
    let state: CostCoverageDisplayState
    let amount: ContractMoney?
    let estimateCurrency: String?
    let periodDays: Int?
    let unpricedSelectionIDs: [String]
    let unsupportedMeters: [String]
    let rateNotice: String?
    let reportedCoverage: CostCoverage?
    let budgetAssessment: BudgetAssessment?

    init(summary: CostSummary?, currentBuildID: String, currentBuildRevision: Int,
         monthlyBudget: ContractMoney?) {
        guard let summary, !currentBuildID.isEmpty, currentBuildRevision > 0,
              summary.buildID.utf8.elementsEqual(currentBuildID.utf8),
              summary.buildRevision == currentBuildRevision else {
            state = summary == nil ? .unavailable : .differentRevision
            amount = nil
            estimateCurrency = nil
            periodDays = nil
            unpricedSelectionIDs = []
            unsupportedMeters = []
            rateNotice = nil
            reportedCoverage = nil
            budgetAssessment = nil
            return
        }

        amount = summary.total
        estimateCurrency = summary.currency
        periodDays = summary.periodDays
        unpricedSelectionIDs = summary.unpricedSelectionIDs
        unsupportedMeters = summary.unsupportedMeters
        reportedCoverage = summary.coverage
        switch summary.rateApplicability {
        case .current: rateNotice = "Rates reported current"
        case .expired: rateNotice = "Rate conditions have expired"
        case .unknown: rateNotice = "Rate applicability is unverified"
        }

        let hasMissingCosts = !summary.unpricedSelectionIDs.isEmpty || !summary.unsupportedMeters.isEmpty
        if let total = summary.total, total.currency != summary.currency {
            state = .inconsistent
        } else if summary.coverage == .complete && hasMissingCosts {
            state = .inconsistent
        } else if summary.total == nil || summary.coverage == .unknown {
            state = .unknown
        } else if summary.coverage == .partial {
            state = .partial
        } else {
            state = .complete
        }
        budgetAssessment = monthlyBudget.map {
            summary.assessMonthlyBudget($0, currentBuildID: currentBuildID,
                                        currentBuildRevision: currentBuildRevision)
        }
    }

    var heading: String {
        switch state {
        case .unavailable: "Cost estimate unavailable"
        case .differentRevision: "Cost estimate unavailable for this revision"
        case .unknown: "Cost coverage unknown"
        case .partial: "Partial cost estimate"
        case .complete: "Reported complete estimate"
        case .inconsistent: "Cost estimate needs review"
        }
    }

    var amountLabel: String {
        switch state {
        case .partial: "Reported amount for priced costs"
        case .complete: "Reported total"
        case .unavailable, .differentRevision, .unknown, .inconsistent: "Reported amount"
        }
    }

    var explanation: String {
        switch state {
        case .unavailable:
            "There is no cost estimate for the selected build. Missing costs are unknown."
        case .differentRevision:
            "The received estimate does not match the selected build and revision. Its amount cannot describe the current selection."
        case .unknown:
            "The supplied estimate does not establish complete cost coverage. An available amount cannot stand for all costs."
        case .partial:
            "This amount excludes missing or unsupported costs. It cannot establish that the complete build fits a budget."
        case .complete:
            "Complete coverage is reported for this estimate. Rate conditions and the selected budget still apply."
        case .inconsistent:
            "The supplied coverage or currency conflicts with other estimate fields. Treat the amount as unqualified until those fields are reconciled."
        }
    }

    func budgetHeading(hasBudget: Bool) -> String {
        guard hasBudget else { return "No monthly budget set" }
        switch budgetAssessment {
        case .satisfied: return "Within estimated budget"
        case .exceeded: return "Above estimated budget"
        case .unknown, nil: return "Budget status unknown"
        }
    }

    func budgetExplanation(hasBudget: Bool) -> String {
        guard hasBudget else { return "A monthly limit is required for a budget comparison." }
        guard let budgetAssessment else {
            return state == .differentRevision
                ? "The estimate does not match the selected build and revision."
                : "No matching cost estimate is available."
        }
        switch budgetAssessment {
        case .satisfied:
            return "The eligible 30-day estimate is within the limit. This is an estimate, not a price guarantee."
        case .exceeded:
            return "The eligible 30-day estimate is above the limit."
        case .unknown(let reason):
            switch reason {
            case .staleBuild: return "The estimate does not match the selected build and revision."
            case .unsupportedPeriod: return "Monthly budget comparison requires an estimate for exactly 30 days."
            case .expiredRates: return "The supplied rate conditions have expired."
            case .unverifiedRates: return "Rate applicability has not been established."
            case .incompleteCoverage: return "Cost coverage is incomplete or unknown."
            case .unpricedSelections: return "One or more selections have no applicable rate."
            case .unsupportedMeters: return "One or more usage meters are unsupported."
            case .missingTotal: return "No total amount is available."
            case .mixedCurrency: return "The estimate and budget currencies do not match. No currency conversion is applied."
            }
        }
    }
}
