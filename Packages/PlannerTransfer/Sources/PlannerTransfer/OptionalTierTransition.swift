import Foundation
import PlannerCore

/// The optional tiers in the frozen catalog contract. The validated catalog,
/// rather than a second kind table, supplies each selected component's tier.
public enum OptionalBuildTier: String, CaseIterable, Hashable, Sendable {
    case t3 = "T3", t4 = "T4", t5 = "T5"
}

/// Resolved governed inputs from the caller. Missing decisions remain unknown;
/// a component ID, lifecycle or absent setting never supplies a default here.
public struct OptionalTierEnvironment: Equatable, Sendable {
    public let mode: DependencyInvalidation.Mode?
    public let production: Bool?

    public init(mode: DependencyInvalidation.Mode?, production: Bool?) {
        self.mode = mode
        self.production = production
    }
}

/// Admission and confirmation errors, not compatibility findings. No supplied
/// settings, private build text or catalog content is included in diagnostics.
public enum OptionalTierTransitionError: Error, Equatable, Sendable {
    case emptyTierRequest, unchangedSelectionState
    case catalogMismatch, graphMismatch, ambiguousCatalogIdentity, ambiguousSelectionIdentity
    case missingCatalogItem, differentKind, unsupportedRevision
    case invalidLocalOwner, staleConfirmation
}

/// One changed retained selection, in original Build order. Settings, role and
/// links stay in the original/proposed snapshots; disabling never deletes them.
public struct OptionalTierSelectionChange: Sendable {
    public let selectionID: String
    public let tier: OptionalBuildTier
    public let item: CatalogItem
    public let beforeEnabled: Bool
    public let afterEnabled: Bool
}

/// A validated, uncommitted proposal with a direct dependency preview. It has no
/// storage, network or evaluator authority. Active/inactive/unknown describe the
/// supplied graph's participation, never fabricated pass/fail/skipped findings.
public struct OptionalTierTransition: Sendable {
    public let original: BuildSnapshot
    public let proposed: BuildSnapshot
    public let catalog: CatalogSnapshot
    public let graph: DependencyGraph
    public let tiers: Set<OptionalBuildTier>
    public let enabled: Bool
    public let environment: OptionalTierEnvironment
    public let changes: [OptionalTierSelectionChange]
    public let dependencyPreview: DependencyParticipantPlan
    // A new preparation, including identical input, needs its own presentation.
    let generation = UUID()

    public static func prepare(
        build: BuildSnapshot, catalog: CatalogSnapshot, graph: DependencyGraph,
        tiers: Set<OptionalBuildTier>, enabled: Bool,
        environment: OptionalTierEnvironment, updatedAt: String
    ) throws -> Self {
        guard !tiers.isEmpty else { throw OptionalTierTransitionError.emptyTierRequest }
        let locks = build.locks.object!
        guard locks["catalog_snapshot_id"] == .string(catalog.id) else {
            throw OptionalTierTransitionError.catalogMismatch
        }
        guard locks["dependency_graph_id"] == .string(graph.id),
              locks["dependency_graph_revision"] == .number(graph.revision) else {
            throw OptionalTierTransitionError.graphMismatch
        }
        var items: [ItemKey: CatalogItem] = [:]
        for item in catalog.items {
            guard items.updateValue(item, forKey: ItemKey(item.id, item.version)) == nil else {
                throw OptionalTierTransitionError.ambiguousCatalogIdentity
            }
        }
        var selections = build.value.object!["selections"]!.array!
        var seen = Set<Data>()
        var changes: [OptionalTierSelectionChange] = []
        for index in selections.indices {
            var fields = selections[index].object!
            let id = fields["id"]!.string!
            guard seen.insert(Data(id.utf8)).inserted else {
                throw OptionalTierTransitionError.ambiguousSelectionIdentity
            }
            let key = ItemKey(fields["catalog_item_id"]!.string!, fields["catalog_item_version"]!.string!)
            guard let item = items[key] else { throw OptionalTierTransitionError.missingCatalogItem }
            guard fields["kind"] == .string(item.kind.rawValue) else {
                throw OptionalTierTransitionError.differentKind
            }
            // CatalogItem's frozen validation enforces kind/tier agreement. Core
            // T0-T2/T6 and optional tiers outside this explicit request stay exact.
            guard let tier = OptionalBuildTier(rawValue: item.tier), tiers.contains(tier) else { continue }
            let beforeEnabled = fields["enabled"] == .bool(true)
            guard beforeEnabled != enabled else { continue }
            changes.append(OptionalTierSelectionChange(selectionID: id, tier: tier, item: item,
                beforeEnabled: beforeEnabled, afterEnabled: enabled))
            fields["enabled"] = .bool(enabled)
            selections[index] = .object(fields)
        }
        // Empty tiers are not populated, and an already satisfied request does
        // not create a new revision or imply a missing mandatory dependency.
        guard !changes.isEmpty else { throw OptionalTierTransitionError.unchangedSelectionState }
        var object = build.value.object!
        var revision = object["revision"]!.number!, one = Decimal(1), next = Decimal()
        guard NSDecimalAdd(&next, &revision, &one, .plain) == .noError, next > revision else {
            throw OptionalTierTransitionError.unsupportedRevision
        }
        object["selections"] = .array(selections)
        object["revision"] = .number(next)
        object["updated_at"] = .string(updatedAt)
        object["lifecycle"] = .string("draft")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // Validate the actual generated bytes through the ordinary bounded
        // frozen Build decoder, including timestamp, numeric and size admission.
        let proposed = try BuildTransfer.snapshot(fromDraftJSON: encoder.encode(JSONValue.object(object)))
        let preview = graph.affectedParticipants(changedKinds: Set(changes.map { $0.item.kind }),
            before: build.dependencyContext(mode: environment.mode, production: environment.production),
            after: proposed.dependencyContext(mode: environment.mode, production: environment.production))
        return Self(original: build, proposed: proposed, catalog: catalog, graph: graph,
                    tiers: tiers, enabled: enabled, environment: environment,
                    changes: changes, dependencyPreview: preview)
    }

    private struct ItemKey: Hashable {
        let id: Data
        let version: Data
        init(_ id: String, _ version: String) {
            self.id = Data(id.utf8)
            self.version = Data(version.utf8)
        }
    }
}
