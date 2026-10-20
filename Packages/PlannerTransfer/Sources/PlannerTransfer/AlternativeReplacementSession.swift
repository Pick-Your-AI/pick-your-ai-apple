import Foundation

/// App-owned local context, separate from the imported wire Build identity.
/// The store and selection-session IDs come from the actual owning controller,
/// never from imported fields. Reopening a selection requires a fresh session ID.
public struct AlternativeSelectionOwner: Equatable, Sendable {
    public let storeID: UUID
    public let draftID: UUID
    public let draftRevision: Int
    public let selectionSessionID: UUID

    public init(storeID: UUID, draftID: UUID, draftRevision: Int, selectionSessionID: UUID) throws {
        guard draftRevision > 0 else { throw SelectionAlternativeError.invalidLocalOwner }
        self.storeID = storeID; self.draftID = draftID; self.draftRevision = draftRevision
        self.selectionSessionID = selectionSessionID
    }
}

/// Issued only by the session that presented this exact immutable comparison.
/// Holding a review confers no store, remote-write or evaluator authority.
public struct AlternativeReplacementReview: Sendable {
    public let comparison: AlternativeComparison
    public let owner: AlternativeSelectionOwner
    fileprivate let token: UUID
}

/// Serializes explicit confirmation without performing storage or network work.
/// The native owner must invalidate on selection/lifecycle/authority changes and
/// supply its actual current build, catalog and assessment when confirming.
public actor AlternativeReplacementSession {
    private var pending: AlternativeReplacementReview?

    public init() {}

    /// Presenting another row or assessment retires all older callbacks. This
    /// includes identical A-to-B-to-A content and retries of an identical report.
    public func present(_ comparison: AlternativeComparison, owner: AlternativeSelectionOwner) -> AlternativeReplacementReview {
        let review = AlternativeReplacementReview(comparison: comparison, owner: owner, token: UUID())
        pending = review
        return review
    }

    /// Dismissal, navigation, editing, unavailable inputs and lifecycle retirement
    /// all use this synchronous actor transition; transport cancellation is optional.
    public func invalidate() { pending = nil }

    /// Returns an uncommitted replacement only after explicit confirmation. The
    /// caller must still use its durable expected-revision write and acknowledge
    /// that result before showing saved/current state. This never retries a write.
    public func confirm(
        _ review: AlternativeReplacementReview,
        currentOwner: AlternativeSelectionOwner,
        currentBuild: BuildSnapshot, currentCatalog: CatalogSnapshot,
        currentComparison: AlternativeComparison
    ) throws -> BuildSnapshot {
        guard pending?.token == review.token else { throw SelectionAlternativeError.staleConfirmation }
        // Consume once, including a failed fresh-context check. A stale callback
        // for a different token above cannot retire the newer pending review.
        pending = nil
        guard currentOwner == review.owner,
              currentComparison.generation == review.comparison.generation,
              currentBuild.value == review.comparison.alternative.original.value,
              currentCatalog.value == review.comparison.alternative.catalog.value else {
            throw SelectionAlternativeError.staleConfirmation
        }
        return review.comparison.alternative.proposed
    }
}
