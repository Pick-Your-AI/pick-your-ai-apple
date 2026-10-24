import Foundation

/// Value-free diagnostics never echo private build, approval or reference fields.
public enum ProposedDeploymentPlanError: Error, Equatable, Sendable {
    case notProposed, buildMismatch, targetBinding
}

/// A local pair of existing frozen artifacts. This is not another wire envelope,
/// an evidence evaluator, public export permission or a deployment capability.
public struct ProposedDeploymentPlan: Sendable, Equatable {
    public let build: BuildSnapshot
    public let manifest: DeploymentManifest

    /// Bind the explicit proposed declaration to one exact retained Build and one
    /// enabled deployment-target selection. The caller owns current-state admission
    /// and evidence review; an identifier alone does not establish either.
    public init(build: BuildSnapshot, manifest: DeploymentManifest) throws {
        guard manifest.status == "proposed" else { throw ProposedDeploymentPlanError.notProposed }
        guard build.id.utf8.elementsEqual(manifest.buildID.utf8),
              build.value.object?["revision"]?.number == manifest.buildRevision else {
            throw ProposedDeploymentPlanError.buildMismatch
        }
        let matches = build.value.object!["selections"]!.array!.filter { selection in
            selection.object!["id"]!.string!.utf8.elementsEqual(manifest.deploymentTargetSelectionID.utf8)
        }
        // Count all matching identities before testing kind/enabled. A second
        // wrong-kind or disabled match cannot hide an ambiguous target identity.
        guard matches.count == 1,
              matches[0].object?["kind"] == .string("deployment_target"),
              matches[0].object?["enabled"] == .bool(true) else {
            throw ProposedDeploymentPlanError.targetBinding
        }
        self.build = build
        self.manifest = manifest
    }

    /// Two independently usable existing JSON artifacts, with no archive format
    /// or atomic filesystem promise. Original locks, monitoring/tier selections,
    /// private fields, approval rows and optional declarations are not projected.
    public struct LocalArtifacts: Sendable, Equatable {
        public let buildJSON: Data
        public let manifestJSON: Data
    }

    /// Compute both outputs before returning. A failure returns neither output
    /// and leaves the retained inputs intact. Nothing is written, sent or deployed.
    public func encodedLocally() throws -> LocalArtifacts {
        let buildJSON = try build.encoded()
        let manifestJSON = try manifest.encoded()
        return LocalArtifacts(buildJSON: buildJSON, manifestJSON: manifestJSON)
    }
}
