import Foundation

/// Identifies the exact build inputs used by an analysis. Lock keys and values are
/// opaque canonical identifiers; the store does not define or infer their meaning.
public struct AnalysisIdentity: Equatable, Sendable {
    public let buildID: String
    public let revision: String
    public let versionLocks: [String: String]

    public init(buildID: String, revision: String, versionLocks: [String: String]) {
        self.buildID = buildID
        self.revision = revision
        self.versionLocks = versionLocks
    }
}

/// A fresh token for every attempt, including retries of identical build inputs.
/// Only the issuing store can create tokens; consumers return the original token.
public struct AnalysisRequest: Equatable, Sendable {
    public let identity: AnalysisIdentity
    public let generation: UUID

    fileprivate init(identity: AnalysisIdentity) {
        self.identity = identity
        self.generation = UUID()
    }
}

public enum AnalysisUnavailableReason: Equatable, Sendable {
    case notRequested
    case cancelled
    case failed
    case disconnected
}

public enum AnalysisState<Value: Sendable>: Sendable {
    case unavailable(identity: AnalysisIdentity?, reason: AnalysisUnavailableReason)
    case pending(AnalysisRequest)
    case current(request: AnalysisRequest, value: Value)
}

extension AnalysisState: Equatable where Value: Equatable {}

/// Serializes result acceptance, not network execution. Callers perform work and
/// return the original request token. Cancelling transport is an optimization:
/// even a transport that ignores cancellation cannot publish a superseded result.
public actor AnalysisStore<Value: Sendable> {
    private var identity: AnalysisIdentity?
    private var activeRequest: AnalysisRequest?
    public private(set) var state: AnalysisState<Value> = .unavailable(
        identity: nil, reason: .notRequested
    )

    public init() {}

    /// Selecting different inputs immediately invalidates both pending and current
    /// results. Selecting identical inputs preserves the current state.
    public func select(_ identity: AnalysisIdentity) {
        guard self.identity != identity else { return }
        self.identity = identity
        activeRequest = nil
        state = .unavailable(identity: identity, reason: .notRequested)
    }

    /// Begins a fresh attempt. A previous result is no longer presented as current
    /// while a retry is pending, even if its build revision has not changed.
    @discardableResult
    public func begin(for identity: AnalysisIdentity) -> AnalysisRequest {
        select(identity)
        let request = AnalysisRequest(identity: identity)
        activeRequest = request
        state = .pending(request)
        return request
    }

    /// Returns false for superseded, cancelled, duplicate, foreign-store or
    /// mismatched-response work. The adapter must construct responseIdentity
    /// from validated response fields, never copy it from the request merely
    /// because that request initiated the transport.
    @discardableResult
    public func receive(
        _ value: Value, identity responseIdentity: AnalysisIdentity, for request: AnalysisRequest
    ) -> Bool {
        guard isActive(request), responseIdentity == request.identity else { return false }
        activeRequest = nil
        state = .current(request: request, value: value)
        return true
    }

    @discardableResult
    public func fail(_ request: AnalysisRequest) -> Bool {
        finish(request, reason: .failed)
    }

    @discardableResult
    public func cancel(_ request: AnalysisRequest) -> Bool {
        finish(request, reason: .cancelled)
    }

    /// Explicitly invalidates all outstanding work. Reconnection requires begin;
    /// reconnecting cannot revive a callback issued before disconnection.
    public func disconnect() {
        activeRequest = nil
        state = .unavailable(identity: identity, reason: .disconnected)
    }

    /// Clears the selected build and all results, including work still executing.
    public func clear() {
        identity = nil
        activeRequest = nil
        state = .unavailable(identity: nil, reason: .notRequested)
    }

    private func isActive(_ request: AnalysisRequest) -> Bool {
        activeRequest == request && identity == request.identity
    }

    private func finish(_ request: AnalysisRequest, reason: AnalysisUnavailableReason) -> Bool {
        guard isActive(request) else { return false }
        activeRequest = nil
        state = .unavailable(identity: identity, reason: reason)
        return true
    }
}
