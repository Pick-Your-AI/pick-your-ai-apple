import Foundation

/// Actual local controller identity, independent of imported Build fields. A
/// reopened selection flow gets a fresh session ID even when its bytes match.
public struct OptionalTierTransitionOwner: Equatable, Sendable {
    public let storeID: UUID
    public let draftID: UUID
    public let draftRevision: Int
    public let selectionSessionID: UUID

    public init(storeID: UUID, draftID: UUID, draftRevision: Int, selectionSessionID: UUID) throws {
        guard draftRevision > 0 else { throw OptionalTierTransitionError.invalidLocalOwner }
        self.storeID = storeID
        self.draftID = draftID
        self.draftRevision = draftRevision
        self.selectionSessionID = selectionSessionID
    }
}

/// Only the presenting session can issue or consume this review. Possession
/// does not confer persistence authority or qualify existing analysis as current.
public struct OptionalTierTransitionReview: Sendable {
    public let transition: OptionalTierTransition
    public let owner: OptionalTierTransitionOwner
    fileprivate let token: UUID
}

/// Serializes explicit confirmation and retirement; never performs a write.
/// The caller invalidates on dismissal, navigation, lifecycle or input changes.
public actor OptionalTierTransitionSession {
    private var pending: OptionalTierTransitionReview?

    public init() {}

    public func present(_ transition: OptionalTierTransition, owner: OptionalTierTransitionOwner)
        -> OptionalTierTransitionReview {
        let review = OptionalTierTransitionReview(transition: transition, owner: owner, token: UUID())
        pending = review
        return review
    }

    public func invalidate() { pending = nil }

    /// The only public route to the proposed Build: `OptionalTierTransition`
    /// keeps it internal, so `prepare` alone does not yield an activated build.
    /// This is a ceremony gate; it does not check any recorded scope decision.
    ///
    /// Supply actual current controller inputs, not values copied out of the
    /// review. After this returns, persistence still requires expected-revision
    /// CAS and a durable acknowledgement; this method does not retry either.
    public func confirm(
        _ review: OptionalTierTransitionReview,
        currentOwner: OptionalTierTransitionOwner, currentBuild: BuildSnapshot,
        currentCatalog: CatalogSnapshot, currentGraph: DependencyGraph,
        currentEnvironment: OptionalTierEnvironment, currentTransition: OptionalTierTransition
    ) throws -> BuildSnapshot {
        guard pending?.token == review.token else { throw OptionalTierTransitionError.staleConfirmation }
        // Consume once even if freshness fails. A different, retired token above
        // cannot invalidate a newer pending review.
        pending = nil
        let transition = review.transition
        guard currentOwner == review.owner, currentTransition.generation == transition.generation,
              currentBuild.value == transition.original.value,
              currentCatalog.value == transition.catalog.value,
              currentGraph.value == transition.graph.value,
              currentEnvironment == transition.environment else {
            throw OptionalTierTransitionError.staleConfirmation
        }
        return transition.proposed
    }
}
