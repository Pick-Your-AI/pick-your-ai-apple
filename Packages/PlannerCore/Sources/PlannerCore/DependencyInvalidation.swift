/// The existing kind identities that enable optional graph branches. A consumer
/// supplies its kind type; this protocol does not define another wire enum.
public protocol DependencyParticipantKind: Hashable, Sendable {
    static var ragPipeline: Self { get }
    static var agentFramework: Self { get }
    static var trainingFramework: Self { get }
    static var trainingCompute: Self { get }
    static var trainingDataset: Self { get }
    static var fineTunedModel: Self { get }
}

/// Pure, direct graph participation for an explicitly supplied change. This is
/// neither a compatibility evaluator nor authority to reuse an old result.
public enum DependencyInvalidation {
    public enum Mode: String, CaseIterable, Sendable {
        case api
        case managed
        case selfHosted = "self_hosted"
        case hybrid
    }

    public enum Activation: String, CaseIterable, Sendable {
        case always
        case selfHosted = "self_hosted"
        case nonAPI = "non_api"
        case ragEnabled = "rag_enabled"
        case agentsEnabled = "agents_enabled"
        case fineTuningEnabled = "fine_tuning_enabled"
        case ifSelected = "if_selected"
        case productionOnly = "production_only"
    }

    public enum Activity: Equatable, Sendable {
        case active, inactive, unknown
    }

    /// An immutable identity projection, including disabled selections. The
    /// caller owns source validation and supplies every retained selection.
    public struct Selection<Kind: DependencyParticipantKind>: Equatable, Sendable {
        public let id: String
        public let kind: Kind
        public let enabled: Bool

        public init(id: String, kind: Kind, enabled: Bool) {
            self.id = id
            self.kind = kind
            self.enabled = enabled
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id.utf8.elementsEqual(rhs.id.utf8) && lhs.kind == rhs.kind && lhs.enabled == rhs.enabled
        }
    }

    public struct Context<Kind: DependencyParticipantKind>: Equatable, Sendable {
        public let selections: [Selection<Kind>]
        public let mode: Mode?
        public let production: Bool?
        fileprivate let enabledKinds: Set<Kind>

        /// A missing mode/production decision stays unknown. Disabled records
        /// remain in `selections` but do not enable a branch.
        public init(selections: [Selection<Kind>], mode: Mode?, production: Bool?) {
            self.selections = selections
            self.mode = mode
            self.production = production
            enabledKinds = Set(selections.filter(\.enabled).map(\.kind))
        }
    }

    /// Only the fields needed for participation. The original validated graph
    /// retains relationship, rationale, IDs and all other source information.
    public struct Edge<Kind: DependencyParticipantKind>: Equatable, Sendable {
        public let dependentKind: Kind
        public let dependsOnKind: Kind
        public let activation: Activation

        public init(dependentKind: Kind, dependsOnKind: Kind, activation: Activation) {
            self.dependentKind = dependentKind
            self.dependsOnKind = dependsOnKind
            self.activation = activation
        }
    }

    public struct Participation: Equatable, Sendable {
        /// Index into the caller's original ordered edge array, not an edge ID.
        /// Duplicate IDs/edges and self/cyclic edges are never collapsed here.
        public let edgeIndex: Int
        public let before: Activity
        public let after: Activity
    }

    public struct Result<Kind: DependencyParticipantKind>: Equatable, Sendable {
        public let changedKinds: Set<Kind>
        /// Includes declared changed kinds even when no edge/selection exists.
        public let affectedKinds: Set<Kind>
        /// First occurrence in before selections, then after selections; IDs
        /// deduplicate by exact UTF-8 bytes, independently of enabled state.
        public let affectedSelectionIDs: [String]
        /// Original input order; repeated edges each retain their own index.
        public let participatingEdges: [Participation]

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.changedKinds == rhs.changedKinds && lhs.affectedKinds == rhs.affectedKinds &&
            lhs.participatingEdges == rhs.participatingEdges &&
            lhs.affectedSelectionIDs.count == rhs.affectedSelectionIDs.count &&
            zip(lhs.affectedSelectionIDs, rhs.affectedSelectionIDs).allSatisfy { pair in
                pair.0.utf8.elementsEqual(pair.1.utf8)
            }
        }
    }

    public static func activity<Kind: DependencyParticipantKind>(of edge: Edge<Kind>, in context: Context<Kind>) -> Activity {
        func state(_ value: Bool) -> Activity { value ? .active : .inactive }
        switch edge.activation {
        case .always:
            return .active
        case .selfHosted:
            guard let mode = context.mode else { return .unknown }
            return state(mode == .selfHosted || mode == .hybrid)
        case .nonAPI:
            guard let mode = context.mode else { return .unknown }
            return state(mode != .api)
        case .ragEnabled:
            return state(context.enabledKinds.contains(.ragPipeline))
        case .agentsEnabled:
            return state(context.enabledKinds.contains(.agentFramework))
        case .fineTuningEnabled:
            return state(!context.enabledKinds.isDisjoint(with: [
                .trainingFramework, .trainingCompute, .trainingDataset, .fineTunedModel
            ]))
        case .ifSelected:
            return state(context.enabledKinds.contains(edge.dependentKind) &&
                         context.enabledKinds.contains(edge.dependsOnKind))
        case .productionOnly:
            guard let production = context.production else { return .unknown }
            return state(production)
        }
    }

    /// Consider an edge when a declared change touches either endpoint or the
    /// activation changes. Only inactive/inactive suppresses an incident edge.
    /// Unchanged nonincident unknown/unknown does not expand every edit globally.
    /// A single pass is deliberate: affected kinds do not become new seeds.
    public static func affectedParticipants<Kind: DependencyParticipantKind>(
        edges: [Edge<Kind>], changedKinds: Set<Kind>, before: Context<Kind>, after: Context<Kind>
    ) -> Result<Kind> {
        var affected = changedKinds
        var participating: [Participation] = []
        for (index, edge) in edges.enumerated() {
            let old = activity(of: edge, in: before)
            let new = activity(of: edge, in: after)
            let incident = changedKinds.contains(edge.dependentKind) || changedKinds.contains(edge.dependsOnKind)
            guard old != new || (incident && !(old == .inactive && new == .inactive)) else { continue }
            affected.insert(edge.dependentKind)
            affected.insert(edge.dependsOnKind)
            participating.append(Participation(edgeIndex: index, before: old, after: new))
        }
        var seen: Set<[UInt8]> = []
        var ids: [String] = []
        for selection in before.selections + after.selections where affected.contains(selection.kind) {
            if seen.insert(Array(selection.id.utf8)).inserted { ids.append(selection.id) }
        }
        return Result(changedKinds: changedKinds, affectedKinds: affected,
                      affectedSelectionIDs: ids, participatingEdges: participating)
    }
}
