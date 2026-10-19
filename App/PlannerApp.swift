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
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("LocalDrafts", isDirectory: true)
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
                    if let store = libraries.importedBuilds { ImportedBuildLibraryView(store: store) }
                    else { unavailable("Imported builds") }
                case .unavailable: unavailable("Imported builds")
                }
            }
            .tabItem { Label("Imported builds", systemImage: "doc.badge.plus") }
            catalog
                .tabItem { Label("Demo catalog", systemImage: "square.grid.2x2") }
        }
        .task { await startup.load() }
    }

    @ViewBuilder
    private var catalog: some View {
        #if DEBUG
        // Closed, visibly fictional UI-journey inputs only. No external data,
        // selected records or local-library state can be supplied at launch.
        if ProcessInfo.processInfo.arguments.contains("--comparison-examples-v1") {
            if ProcessInfo.processInfo.arguments.contains("--comparison-accessibility3") {
                CatalogBrowserView(collection: .comparisonExamples).dynamicTypeSize(.accessibility3)
            } else {
                CatalogBrowserView(collection: .comparisonExamples)
            }
        } else {
            CatalogBrowserView()
        }
        #else
        CatalogBrowserView()
        #endif
    }

    private func unavailable(_ library: String) -> some View {
        ContentUnavailableView("\(library) unavailable", systemImage: "externaldrive.badge.exclamationmark",
            description: Text("Your existing data has not been reset. Unlock the device, check available storage, and reopen the app. Other available libraries can still be used."))
    }
}
