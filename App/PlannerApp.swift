import SwiftUI
import PlannerData
import PlannerUI

@main
struct PlannerApp: App {
    private let store: DraftStore?
    init() {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("LocalDrafts", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            store = try DraftStore(url: root.appendingPathComponent("drafts.sqlite"))
        } catch { store = nil }
    }
    var body: some Scene {
        WindowGroup {
            if let store { DraftLibraryView(store: store) }
            else {
                ContentUnavailableView("Local storage unavailable", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Your existing data has not been reset. Unlock the device, check available storage, and reopen the app."))
            }
        }
    }
}
