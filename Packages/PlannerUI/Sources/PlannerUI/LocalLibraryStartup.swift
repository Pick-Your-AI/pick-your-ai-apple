import Foundation
import SwiftUI

/// One scene owns its startup attempt. SwiftUI cancels `load` when that scene's
/// view disappears; a late result cannot replace a later attempt's state.
@MainActor
public final class LocalLibraryStartup: ObservableObject {
    public enum State {
        case loading
        case ready(LocalLibraryStores)
        case unavailable
    }

    @Published public private(set) var state: State = .loading
    private let open: @Sendable () async throws -> LocalLibraryStores
    private var generation: UUID?

    public init(open: @escaping @Sendable () async throws -> LocalLibraryStores) {
        self.open = open
    }

    public func load() async {
        // Reappearing scenes keep their existing connections and editor state.
        if case .ready = state { return }
        let attempt = UUID()
        generation = attempt
        state = .loading
        do {
            let stores = try await open()
            try Task.checkCancellation()
            guard generation == attempt else { return }
            state = .ready(stores)
        } catch {
            guard generation == attempt else { return }
            // Cancellation is a lifecycle event, not a database failure. A later
            // appearance can retry; a cancelled opener never publishes its result.
            if Task.isCancelled || error is CancellationError { state = .loading }
            else { state = .unavailable }
        }
    }
}
