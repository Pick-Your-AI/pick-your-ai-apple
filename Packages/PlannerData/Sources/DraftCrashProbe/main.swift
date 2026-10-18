import Foundation
import PlannerData
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main struct DraftCrashProbe {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { exit(64) }
        let mode = CommandLine.arguments[1]
        let url = URL(fileURLWithPath: CommandLine.arguments[2])
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let store = try DraftStore(url: url, fault: { point in
            if mode == "crash-migration", case .duringMigration = point { _exit(73) }
            if mode == "crash-write", case .afterHistoryWrite = point { _exit(73) }
            if mode == "crash-commit", case .beforeCommit = point { _exit(73) }
        })
        switch mode {
        case "seed":
            try await store.save(id: id, expectedRevision: nil, title: "Synthetic crash probe", payload: Data("{}".utf8))
        case "crash-write", "crash-commit":
            try await store.save(id: id, expectedRevision: 1, title: "Uncommitted", payload: Data("{\"edit\":\"pending\"}".utf8))
            exit(65)
        case "verify":
            let record = try await store.read(id: id)
            let history = try await store.history(id: id)
            guard record.revision == 1, record.payload == Data("{}".utf8), history.records.count == 1 else { exit(66) }
            print("durable revision 1 preserved")
        case "crash-migration": exit(67)
        default: exit(64)
        }
    }
}
