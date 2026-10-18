import Foundation
import PlannerData

/// Independent local databases must remain independently available. A corrupt or
/// unsupported library is preserved and must not hide the other library's data.
public struct LocalLibraryStores: Sendable {
    public let notes: DraftStore?
    public let importedBuilds: DraftStore?

    public init(directory: URL) {
        notes = try? DraftStore(url: directory.appendingPathComponent("drafts.sqlite"))
        importedBuilds = try? DraftStore(url: directory.appendingPathComponent("imported-builds.sqlite"))
    }
}
