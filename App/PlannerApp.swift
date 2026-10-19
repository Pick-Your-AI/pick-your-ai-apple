import SwiftUI
import PlannerUI

@main
struct PlannerApp: App {
    var body: some Scene {
        WindowGroup { LocalLibrariesView() }
    }
}

private struct LocalLibrariesView: View {
    @StateObject private var startup = LocalLibraryStartup {
        try await LocalLibraryStores.open {
            let root: URL
            #if DEBUG
            if SyntheticT6Launch.scenario != nil {
                // Each explicit synthetic launch owns a new disposable namespace.
                // It cannot seed, replace, or reset the user's ordinary libraries.
                root = FileManager.default.temporaryDirectory
                    .appendingPathComponent("T6Journey-" + UUID().uuidString, isDirectory: true)
            } else {
                root = try ordinaryLibraryRoot()
            }
            #else
            root = try ordinaryLibraryRoot()
            #endif
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            return root
        }
    }

    var body: some View {
        TabView {
            Group {
                switch startup.state {
                case .loading: ProgressView("Opening notes…")
                case .ready(let libraries):
                    if let store = libraries.notes { DraftLibraryView(store: store) }
                    else { unavailable("Notes") }
                case .unavailable: unavailable("Notes")
                }
            }
            .tabItem { Label("Notes", systemImage: "note.text") }
            Group {
                switch startup.state {
                case .loading: ProgressView("Opening imported builds…")
                case .ready(let libraries):
                    if let store = libraries.importedBuilds {
                        #if DEBUG
                        if let scenario = SyntheticT6Launch.scenario {
                            ImportedBuildLibraryView(store: store, syntheticT6Scenario: scenario)
                        } else { ImportedBuildLibraryView(store: store) }
                        #else
                        ImportedBuildLibraryView(store: store)
                        #endif
                    }
                    else { unavailable("Imported builds") }
                case .unavailable: unavailable("Imported builds")
                }
            }
            .tabItem { Label("Imported builds", systemImage: "doc.badge.plus") }
            CatalogBrowserView()
                .tabItem { Label("Demo catalog", systemImage: "square.grid.2x2") }
        }
        .task { await startup.load() }
    }

    private func unavailable(_ library: String) -> some View {
        ContentUnavailableView("\(library) unavailable", systemImage: "externaldrive.badge.exclamationmark",
            description: Text("Your existing data has not been reset. Unlock the device, check available storage, and reopen the app. Other available libraries can still be used."))
    }
}

private func ordinaryLibraryRoot() throws -> URL {
    try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true).appendingPathComponent("LocalDrafts", isDirectory: true)
}

#if DEBUG
private enum SyntheticT6Launch {
    static let scenario: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        let matches = arguments.indices.filter { arguments[$0] == "--t6-journey-fixture" }
        guard matches.count == 1, let index = matches.first, index + 1 < arguments.count,
              ["quality-absent", "quality-failed-proposed"].contains(arguments[index + 1]) else { return nil }
        return arguments[index + 1]
    }()
}
#endif
