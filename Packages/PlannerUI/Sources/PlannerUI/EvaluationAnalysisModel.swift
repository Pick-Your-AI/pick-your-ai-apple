import Foundation
import Observation
import PlannerCore

/// Native presentation only. A current report still contains reported claims,
/// including unknowns; matching the visible inputs does not approve those claims.
public enum EvaluationAnalysisPresentation: Equatable, Sendable {
    case unavailable(AnalysisUnavailableReason)
    case pending
    case current(EvaluationReport)
}

/// MainActor observation for the existing Core request/identity boundary.
/// This model neither evaluates a build nor starts a transport. Its owner supplies
/// expected inputs from the selected build before handing a request to a service.
@MainActor
@Observable
public final class EvaluationAnalysisModel {
    public private(set) var selectedIdentity: AnalysisIdentity?
    private var state: AnalysisState<EvaluationReport> = .unavailable(identity: nil, reason: .notRequested)
    private var starting = false
    @ObservationIgnored private let store = AnalysisStore<EvaluationReport>()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeRequest: AnalysisRequest?
    @ObservationIgnored private var commandTail: Task<Void, Never>?

    public init() {}

    /// A view supplies its own currently visible identity on every render. This
    /// also denies a previously retained model while a new owner's selection is
    /// being installed. Never derive this argument from the returned report.
    public func presentation(for visibleIdentity: AnalysisIdentity?) -> EvaluationAnalysisPresentation {
        guard let visibleIdentity, visibleIdentity == selectedIdentity else {
            return .unavailable(.notRequested)
        }
        if starting { return .pending }
        switch state {
        case .pending(let request) where request.identity == visibleIdentity:
            return .pending
        // Report-to-request agreement is enforced once, by Core's typed receive
        // overload, before `.current` can be assigned. It is not re-checked here.
        case .current(let request, let report) where request.identity == visibleIdentity:
            return .current(report)
        case .unavailable(let identity, let reason) where identity == visibleIdentity:
            return .unavailable(reason)
        default:
            return .unavailable(.notRequested)
        }
    }

    /// Changing selection revokes visible analysis before the first actor hop.
    /// Re-selecting the same immutable wire inputs preserves their current state.
    /// Clear first when switching local owners/rows with otherwise identical pins.
    /// Contract for callers (#391): this model fences only wire identity, not local
    /// row ownership, so selecting identical wire pins for a different row is a
    /// no-op and the caller must call `clear()` first when ownership changes.
    public func select(_ identity: AnalysisIdentity?) {
        guard identity != selectedIdentity else { return }
        selectedIdentity = identity
        invalidate(reason: .notRequested)
        enqueue { [store] in
            if let identity { await store.select(identity) }
            else { await store.clear() }
        }
    }

    /// Clears ownership even if the next selected row has identical wire inputs.
    public func clear() {
        selectedIdentity = nil
        invalidate(reason: .notRequested)
        enqueue { [store] in await store.clear() }
    }

    /// Called for an actual connection loss. Reconnection does not revive an old
    /// generation; the owner must explicitly begin another request.
    public func disconnect() {
        invalidate(reason: .disconnected)
        enqueue { [store] in await store.disconnect() }
    }

    /// Starts/retries only the already selected inputs. A superseded or cancelled
    /// caller receives no token and therefore must not launch evaluation work.
    public func begin() async -> AnalysisRequest? {
        guard !Task.isCancelled, let identity = selectedIdentity else { return nil }
        invalidate(reason: .notRequested)
        starting = true
        let intent = generation
        let request = await enqueue { [store] in await store.begin(for: identity) }.value
        guard intent == generation, identity == selectedIdentity else { return nil }
        activeRequest = request
        starting = false
        state = .pending(request)
        if Task.isCancelled {
            _ = await cancel(request)
            return nil
        }
        return request
    }

    /// The report's validated wire fields supply the response identity to Core.
    /// A mismatch does not consume the request or replace a later matching result.
    @discardableResult
    public func receive(_ report: EvaluationReport, for request: AnalysisRequest) async -> Bool {
        guard isVisible(request) else { return false }
        let intent = generation
        let accepted = await enqueue { [store] in await store.receive(report, for: request) }.value
        guard accepted, intent == generation, isVisible(request) else { return false }
        activeRequest = nil
        state = .current(request: request, value: report)
        return true
    }

    @discardableResult
    public func cancel(_ request: AnalysisRequest) async -> Bool {
        await finish(request, reason: .cancelled)
    }

    @discardableResult
    public func fail(_ request: AnalysisRequest) async -> Bool {
        await finish(request, reason: .failed)
    }

    private func finish(_ request: AnalysisRequest, reason: AnalysisUnavailableReason) async -> Bool {
        guard isVisible(request) else { return false }
        let intent = generation
        let accepted = await enqueue { [store] in
            if reason == .cancelled { return await store.cancel(request) }
            return await store.fail(request)
        }.value
        // Core decides whether completion or cancellation won. An inactive late
        // cancellation must not clear a completed report awaiting UI publication.
        guard accepted, intent == generation, isVisible(request) else { return false }
        activeRequest = nil
        state = .unavailable(identity: request.identity, reason: reason)
        return true
    }

    private func isVisible(_ request: AnalysisRequest) -> Bool {
        request == activeRequest && request.identity == selectedIdentity
    }

    private func invalidate(reason: AnalysisUnavailableReason) {
        generation = UUID()
        activeRequest = nil
        starting = false
        state = .unavailable(identity: selectedIdentity, reason: reason)
    }

    /// All Core mutations share this short queue. Transport work never enters it.
    /// Unstructured tasks deliberately finish their predecessor even if a caller
    /// is cancelled. Internal visibility permits deterministic suspension tests
    /// without substituting a fake Core store or issuing timer-based races.
    @discardableResult
    func enqueue<Result: Sendable>(_ operation: @escaping @Sendable () async -> Result) -> Task<Result, Never> {
        let previous = commandTail
        let command = Task {
            await previous?.value
            return await operation()
        }
        commandTail = Task { _ = await command.value }
        return command
    }
}
