import Foundation
import PlannerCore
import PlannerTransfer

/// A read-only projection of the selected immutable snapshot, never an estimate
/// producer or an alternative build validator. Local library label revisions
/// do not participate in cost identity.
enum ImportedBuildCostContext: Equatable, Sendable {
    struct Selection: Equatable, Sendable {
        let buildID: String
        let buildRevision: Int
        let monthlyBudget: ContractMoney?
    }

    enum UnavailableReason: Equatable, Sendable {
        case identity, revision, budget

        var explanation: String {
            switch self {
            case .identity:
                "The selected build identity could not be read. The imported build is unchanged."
            case .revision:
                "This snapshot's recorded revision cannot be used for a cost estimate. The imported build is unchanged."
            case .budget:
                "The recorded budget or currency could not be read. Both were preserved, and no budget comparison was made."
            }
        }
    }

    case available(Selection)
    case unavailable(UnavailableReason)

    init(snapshot: BuildSnapshot) {
        self.init(snapshotValue: snapshot.value)
    }

    /// The value boundary is internal so malformed projection inputs can be
    /// checked without constructing or admitting an invalid BuildSnapshot.
    init(snapshotValue: JSONValue) {
        guard case .object(let fields) = snapshotValue,
              case .string(let buildID)? = fields["id"], !buildID.isEmpty else {
            self = .unavailable(.identity)
            return
        }
        guard case .number(let recordedRevision)? = fields["revision"],
              let revision = Int(NSDecimalNumber(decimal: recordedRevision).stringValue),
              revision > 0, Decimal(revision) == recordedRevision else {
            self = .unavailable(.revision)
            return
        }
        guard case .object(let objectives)? = fields["objectives"],
              case .string(let currency)? = objectives["currency"],
              currency.utf8.count == 3,
              currency.utf8.allSatisfy({ (65...90).contains($0) }) else {
            self = .unavailable(.budget)
            return
        }

        let budget: ContractMoney?
        switch objectives["monthly_budget_amount"] {
        case nil:
            budget = nil
        case .string(let amount)?:
            do {
                budget = try ContractMoney(amount: ContractDecimal(amount), currency: currency)
            } catch {
                self = .unavailable(.budget)
                return
            }
        default:
            self = .unavailable(.budget)
            return
        }
        self = .available(Selection(buildID: buildID, buildRevision: revision, monthlyBudget: budget))
    }
}
