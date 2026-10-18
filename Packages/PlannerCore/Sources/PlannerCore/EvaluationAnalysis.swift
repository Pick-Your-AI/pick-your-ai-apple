public extension AnalysisIdentity {
    /// The expected input tuple for the existing frozen-v1 evaluation report.
    /// Supply these values from the selected build and its governed input pins.
    /// This names inputs; it does not validate or approve them for evaluation.
    static func frozenV1Evaluation(
        buildID: String,
        buildRevision: Int,
        catalogSnapshotID: String,
        rulesetID: String,
        rulesetVersion: String,
        dependencyGraphID: String,
        dependencyGraphRevision: Int
    ) -> AnalysisIdentity {
        AnalysisIdentity(
            buildID: buildID,
            revision: String(buildRevision),
            versionLocks: [
                "catalog_snapshot_id": catalogSnapshotID,
                "ruleset_id": rulesetID,
                "ruleset_version": rulesetVersion,
                "dependency_graph_id": dependencyGraphID,
                "dependency_graph_revision": String(dependencyGraphRevision)
            ]
        )
    }
}

public extension EvaluationReport {
    /// Derives every input identity from this validated report, independently of
    /// whichever request initiated the transport. Report ID, evaluation time and
    /// verdicts are output metadata, not substitutes for the governed input pins.
    var analysisIdentity: AnalysisIdentity {
        .frozenV1Evaluation(
            buildID: buildID,
            buildRevision: buildRevision,
            catalogSnapshotID: catalogSnapshotID,
            rulesetID: rulesetID,
            rulesetVersion: rulesetVersion,
            dependencyGraphID: dependencyGraphID,
            dependencyGraphRevision: dependencyGraphRevision
        )
    }
}

public extension AnalysisStore where Value == EvaluationReport {
    /// Admit a report produced by EvaluationReport.decode using its own input
    /// tuple. The existing request-generation and full-identity gate remains the
    /// only state transition; rejected responses leave the active attempt pending.
    @discardableResult
    func receive(_ report: EvaluationReport, for request: AnalysisRequest) -> Bool {
        receive(report, identity: report.analysisIdentity, for: request)
    }
}
