import Foundation
import PlannerData
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Synthetic storage probe only; never sends a request or interprets a server receipt.
@main struct PendingWriteCrashProbe {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { exit(64) }
        let mode = CommandLine.arguments[1]
        let url = URL(fileURLWithPath: CommandLine.arguments[2])
        let owner = try PendingWritePartition(environment: "fixture-v1", authority: "synthetic-owner")
        let body = Data("{\"build_id\":\"synthetic-build\",\"revision\":8,\"decimal\":\"1.000\"}".utf8)
        let intent = try PendingBuildWrite(operationID: "queued-write", method: .update,
            buildID: "synthetic-build", idempotencyKey: "stable-key-queued-write", ifMatch: "\"7\"", body: body)
        let store = try PendingBuildWriteStore(url: url, fault: { point in
            if mode == "crash-enqueue", point == .beforeEnqueueCommit { _exit(73) }
            if mode == "crash-attempt", point == .beforeAttemptCommit { _exit(73) }
            if mode == "crash-outcome", point == .beforeOutcomeCommit { _exit(73) }
        })
        let session = try await store.activate(owner)
        switch mode {
        case "seed":
            let baseline = try PendingBuildWrite(operationID: "baseline", method: .create,
                buildID: "baseline-build", idempotencyKey: "baseline-key", body: Data("{\"revision\":1}".utf8))
            try await store.enqueue(baseline, session: session)
            let drafts = try DraftStore(url: url.deletingLastPathComponent().appendingPathComponent("drafts.sqlite"))
            try await drafts.save(id: UUID(uuidString: "00000000-0000-0000-0000-000000000089")!,
                                  expectedRevision: nil, title: "Synthetic queue control", payload: Data("{}".utf8))
        case "enqueue", "crash-enqueue", "commit-enqueue":
            try await store.enqueue(intent, session: session)
            if mode == "commit-enqueue" { _exit(73) }
            if mode == "crash-enqueue" { exit(65) }
        case "crash-attempt", "commit-attempt", "crash-outcome", "commit-outcome":
            let attempt = try await store.beginAttempt(operationID: intent.operationID, session: session)
            guard attempt.write == intent else { exit(66) }
            if mode == "commit-attempt" { _exit(73) }
            if mode == "crash-attempt" { exit(65) }
            // This synthetic acknowledged outcome tests only local persistence.
            // It is not a simulated authority, service TTL, or server-success claim.
            guard try await store.recordOutcome(.confirmed, for: attempt) else { exit(66) }
            if mode == "commit-outcome" { _exit(73) }
            exit(65)
        case "verify-missing", "verify-pending", "verify-uncertain", "verify-confirmed":
            let records = try await store.records(session: session)
            guard records.first?.write.operationID == "baseline", records.first?.state == .pending else { exit(66) }
            let expectedCount = mode == "verify-missing" ? 1 : 2
            guard records.count == expectedCount else { exit(66) }
            if expectedCount == 2 {
                let expected: PendingWriteState = mode == "verify-pending" ? .pending : (mode == "verify-confirmed" ? .confirmed : .uncertain)
                guard records[1].write == intent, records[1].state == expected else { exit(66) }
                if expected != .pending {
                    do { _ = try await store.beginAttempt(operationID: intent.operationID, session: session); exit(66) }
                    catch PendingWriteError.notPending { }
                }
            }
            let drafts = try DraftStore(url: url.deletingLastPathComponent().appendingPathComponent("drafts.sqlite"))
            let draft = try await drafts.read(id: UUID(uuidString: "00000000-0000-0000-0000-000000000089")!)
            let history = try await drafts.history(id: draft.id)
            guard draft.revision == 1, draft.payload == Data("{}".utf8), history.records.count == 1 else { exit(66) }
            print("verified \(mode)")
        default: exit(64)
        }
    }
}
