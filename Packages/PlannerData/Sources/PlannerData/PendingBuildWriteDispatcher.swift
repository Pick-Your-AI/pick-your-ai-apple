/// A locally persisted outcome is distinct from a stale, foreign or already
/// consumed callback. Neither case supplies server authority or receipt policy.
public enum PendingBuildWriteDispatchResult: Sendable {
    case recorded(PendingWriteOutcome)
    case notRecorded
}

/// Connects one durable attempt to one caller-supplied asynchronous adapter call.
/// It does not activate a session, implement networking or retry an operation.
/// The adapter must validate any returned outcome for the exact supplied attempt
/// and coordinate its actual dispatch, credentials and cancellation lifecycle.
public struct PendingBuildWriteDispatcher: Sendable {
    private let store: PendingBuildWriteStore

    public init(store: PendingBuildWriteStore) {
        self.store = store
    }

    /// The adapter receives the committed immutable attempt without request
    /// reconstruction. A status code or current-head GET alone is not confirmation.
    ///
    /// Cancellation observed before beginAttempt leaves the intent pending. Once
    /// that transition commits, cancellation or an adapter error is conservative:
    /// record uncertainty, never reset to pending or invoke the adapter again.
    /// A validated outcome already returned by the adapter is retained even if
    /// the caller task has been cancelled. A retired callback remains notRecorded.
    /// Store errors propagate; a failed outcome commit is not acknowledgement.
    public func perform(
        operationID: String,
        session: PendingWriteSession,
        using adapter: @Sendable (PendingWriteAttempt) async throws -> PendingWriteOutcome
    ) async throws -> PendingBuildWriteDispatchResult {
        try Task.checkCancellation()
        let attempt = try await store.beginAttempt(operationID: operationID, session: session)

        let outcome: PendingWriteOutcome
        do {
            // Cancellation can arrive while waiting for the durable transition.
            // There is intentionally no safe-abort-to-pending store operation.
            try Task.checkCancellation()
            outcome = try await adapter(attempt)
        } catch {
            outcome = .uncertain
        }

        // Do not replace a known, validated outcome merely because cancellation
        // arrived later. The store still checks the live generation and attempt.
        if try await store.recordOutcome(outcome, for: attempt) {
            return .recorded(outcome)
        }
        return .notRecorded
    }
}
