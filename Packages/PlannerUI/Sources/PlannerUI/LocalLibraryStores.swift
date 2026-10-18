import Foundation
import PlannerData

/// Independent local databases must remain independently available. A corrupt or
/// unsupported library is preserved and must not hide the other library's data.
public struct LocalLibraryStores: Sendable {
    public let notes: DraftStore?
    public let importedBuilds: DraftStore?

    /// Directory preparation and synchronous SQLite initialization/migrations run
    /// outside the caller's actor. The caller supplies its app-owned protected root.
    public static func open(
        preparingDirectory: @escaping @Sendable () throws -> URL
    ) async throws -> Self {
        try await open(preparingDirectory: preparingDirectory, openStore: { try DraftStore(url: $0) })
    }

    // Injectable synchronous opener keeps the executor/cancellation regression
    // deterministic while production and corrupt-database tests use real SQLite.
    static func open(
        preparingDirectory: @escaping @Sendable () throws -> URL,
        openStore: @escaping @Sendable (URL) throws -> DraftStore
    ) async throws -> Self {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let directory = try preparingDirectory()
            try Task.checkCancellation()
            let notes = try? openStore(directory.appendingPathComponent("drafts.sqlite"))
            try Task.checkCancellation()
            let importedBuilds = try? openStore(directory.appendingPathComponent("imported-builds.sqlite"))
            try Task.checkCancellation()
            return Self(notes: notes, importedBuilds: importedBuilds)
        }
        return try await withTaskCancellationHandler {
            let stores = try await worker.value
            try Task.checkCancellation()
            return stores
        } onCancel: {
            worker.cancel()
        }
    }
}
