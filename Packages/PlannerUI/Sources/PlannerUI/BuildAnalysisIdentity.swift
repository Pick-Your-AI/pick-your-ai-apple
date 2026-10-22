import Foundation
import PlannerCore
import PlannerTransfer

public extension BuildSnapshot {
    private static let knownLockKeys: Set<String> = [
        "catalog_snapshot_id", "ruleset_id", "ruleset_version",
        "dependency_graph_id", "dependency_graph_revision", "pricebook_id"
    ]

    /// Expected evaluation inputs come from the selected validated wire snapshot,
    /// never a local DraftRecord revision or a report's claimed identity.
    ///
    /// Known limit: the frozen-v1 report wire carries exactly five input pins, so
    /// the optional `pricebook_id` lock cannot be represented in a report identity
    /// and does not distinguish builds here. Any other lock key is not a known
    /// governed pin; return nil (unavailable) rather than silently dropping it.
    var evaluationAnalysisIdentity: AnalysisIdentity? {
        guard case .object(let build) = value,
              case .string(let buildID)? = build["id"],
              let revision = analysisRevision(build["revision"]),
              case .object(let pins)? = build["locks"],
              pins.keys.allSatisfy(Self.knownLockKeys.contains),
              case .string(let catalog)? = pins["catalog_snapshot_id"],
              case .string(let ruleset)? = pins["ruleset_id"],
              case .string(let rulesetVersion)? = pins["ruleset_version"],
              case .string(let graph)? = pins["dependency_graph_id"],
              let graphRevision = analysisRevision(pins["dependency_graph_revision"]) else { return nil }
        return .frozenV1Evaluation(
            buildID: buildID, buildRevision: revision,
            catalogSnapshotID: catalog, rulesetID: ruleset, rulesetVersion: rulesetVersion,
            dependencyGraphID: graph, dependencyGraphRevision: graphRevision
        )
    }
}

private func analysisRevision(_ value: JSONValue?) -> Int? {
    guard case .number(let decimal) = value,
          let revision = Int(NSDecimalNumber(decimal: decimal).stringValue),
          revision > 0, Decimal(revision) == decimal else { return nil }
    return revision
}
