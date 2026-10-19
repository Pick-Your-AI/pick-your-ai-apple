import Foundation
import PlannerCore

// These are the existing frozen kind cases; no alternate kind schema is added.
extension CatalogKind: DependencyParticipantKind {}

public struct DependencyParticipantPlan: Equatable, Sendable {
    public let graphID: String
    public let graphRevision: Decimal
    public let participants: DependencyInvalidation.Result<CatalogKind>
}

public extension DependencyGraph {
    /// An explicit consumer of the validated graph. Each returned edge index
    /// addresses `edges` unchanged. The caller still binds the complete Build and
    /// input revision before retiring/replacing results or running an evaluator.
    func affectedParticipants(
        changedKinds: Set<CatalogKind>,
        before: DependencyInvalidation.Context<CatalogKind>,
        after: DependencyInvalidation.Context<CatalogKind>
    ) -> DependencyParticipantPlan {
        let projected = edges.map { edge in
            DependencyInvalidation.Edge(dependentKind: edge.dependentKind, dependsOnKind: edge.dependsOnKind,
                                        activation: edge.activation.invalidationActivation)
        }
        return DependencyParticipantPlan(graphID: id, graphRevision: revision,
            participants: DependencyInvalidation.affectedParticipants(
                edges: projected, changedKinds: changedKinds, before: before, after: after))
    }
}

public extension BuildSnapshot {
    /// Preserve all admitted selection identities, including disabled entries.
    /// Mode and production come from the caller's resolved governed inputs; they
    /// are not guessed from a catalog ID, lifecycle, missing field or label.
    func dependencyContext(mode: DependencyInvalidation.Mode?, production: Bool?)
        -> DependencyInvalidation.Context<CatalogKind> {
        let selections = value.object!["selections"]!.array!.map { selection in
            let fields = selection.object!
            return DependencyInvalidation.Selection(
                id: fields["id"]!.string!, kind: CatalogKind(rawValue: fields["kind"]!.string!)!,
                enabled: fields["enabled"] == .bool(true))
        }
        return DependencyInvalidation.Context(selections: selections, mode: mode, production: production)
    }
}

private extension DependencyActivation {
    var invalidationActivation: DependencyInvalidation.Activation {
        switch self {
        case .always: .always
        case .selfHosted: .selfHosted
        case .nonAPI: .nonAPI
        case .ragEnabled: .ragEnabled
        case .agentsEnabled: .agentsEnabled
        case .fineTuningEnabled: .fineTuningEnabled
        case .ifSelected: .ifSelected
        case .productionOnly: .productionOnly
        }
    }
}
