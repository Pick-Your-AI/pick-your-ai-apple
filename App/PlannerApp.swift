import SwiftUI
import PlannerData
import PlannerUI

@main
struct PlannerApp: App {
    private let store: DraftStore?
    private let importedStore: DraftStore?
    init() {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("LocalDrafts", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let libraries = LocalLibraryStores(directory: root)
            store = libraries.notes; importedStore = libraries.importedBuilds
        } catch { store = nil; importedStore = nil }
    }
    var body: some Scene {
        WindowGroup {
            TabView {
                Group {
                    if let store { DraftLibraryView(store: store) }
                    else { unavailable("Notes") }
                }
                .tabItem { Label("Notes", systemImage: "note.text") }
                Group {
                    if let importedStore { ImportedBuildLibraryView(store: importedStore) }
                    else { unavailable("Imported builds") }
                }
                .tabItem { Label("Imported builds", systemImage: "doc.badge.plus") }
            }
        }
    }

    private func unavailable(_ library: String) -> some View {
        ContentUnavailableView("\(library) unavailable", systemImage: "externaldrive.badge.exclamationmark",
            description: Text("Your existing data has not been reset. Unlock the device, check available storage, and reopen the app. Other available libraries can still be used."))
    }
}
