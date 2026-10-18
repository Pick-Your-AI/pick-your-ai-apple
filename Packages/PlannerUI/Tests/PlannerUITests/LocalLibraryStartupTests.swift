import Foundation
import XCTest
import PlannerData
@testable import PlannerUI

// The lock protects probe state; semaphores are used only inside synchronous
// workers, never to block the main actor. Timeouts bound a broken regression.
private final class BlockingOpenProbe: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0
    private var offMain = true
    private var timedOut = false

    var observations: (calls: Int, offMain: Bool, timedOut: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (calls, offMain, timedOut)
    }

    func open(_ url: URL) throws -> DraftStore {
        lock.lock()
        calls += 1
        let shouldBlock = calls == 1
        offMain = offMain && !Thread.isMainThread
        lock.unlock()
        if shouldBlock {
            entered.signal()
            let result = released.wait(timeout: .now() + 5)
            lock.lock(); timedOut = result == .timedOut; lock.unlock()
        }
        return try DraftStore(url: url)
    }

    func waitUntilEntered() async -> Bool {
        await withCheckedContinuation { continuation in
            // The bounded blocking wait belongs to a synchronous dispatch worker,
            // not Swift's cooperative async executor or the main actor.
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.entered.wait(timeout: .now() + 5) == .success)
            }
        }
    }

    func release() { released.signal() }
}

private actor StartupAttempts {
    let directory: URL
    let probe: BlockingOpenProbe?
    let failFirst: Bool
    private(set) var count = 0

    init(directory: URL, probe: BlockingOpenProbe? = nil, failFirst: Bool = false) {
        self.directory = directory; self.probe = probe; self.failFirst = failFirst
    }

    func open() async throws -> LocalLibraryStores {
        count += 1
        if count == 1, failFirst { throw DraftStoreError.database(10) }
        let directory = directory
        if count == 1, let probe {
            return try await LocalLibraryStores.open(preparingDirectory: { directory }, openStore: { try probe.open($0) })
        }
        return try await LocalLibraryStores.open { directory }
    }
}

@MainActor
final class LocalLibraryStartupTests: XCTestCase {
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testMainActorProcessesEditorActionWhileStartupOpenerIsBlocked() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let editorStore = try DraftStore(url: directory.appendingPathComponent("editor.sqlite"))
        let editor = DraftLibraryModel(store: editorStore)
        let probe = BlockingOpenProbe()
        defer { probe.release() }
        let startup = LocalLibraryStartup {
            try await LocalLibraryStores.open(preparingDirectory: {
                XCTAssertFalse(Thread.isMainThread, "Directory preparation must also leave the main actor")
                return directory
            }, openStore: { try probe.open($0) })
        }
        let loading = Task { await startup.load() }
        let entered = await probe.waitUntilEntered()
        XCTAssertTrue(entered)
        // This is the same main-actor binding mutation used by the editor. It must
        // complete before the controlled synchronous storage opener is released.
        editor.notes = "An action processed while storage awaits"
        XCTAssertEqual(editor.notes, "An action processed while storage awaits")
        guard case .loading = startup.state else {
            probe.release(); await loading.value
            return XCTFail("Startup published before the blocked opener was released")
        }
        XCTAssertFalse(probe.observations.timedOut)
        probe.release()
        await loading.value
        XCTAssertTrue(probe.observations.offMain)
        XCTAssertFalse(probe.observations.timedOut)
        XCTAssertEqual(probe.observations.calls, 2)
        guard case .ready(let stores) = startup.state else { return XCTFail("Expected ready libraries") }
        XCTAssertNotNil(stores.notes)
        XCTAssertNotNil(stores.importedBuilds)
    }

    func testCancelledSceneDoesNotPublishAndCanRetry() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = BlockingOpenProbe()
        defer { probe.release() }
        let attempts = StartupAttempts(directory: directory, probe: probe)
        let startup = LocalLibraryStartup { try await attempts.open() }
        let loading = Task { await startup.load() }
        let entered = await probe.waitUntilEntered()
        XCTAssertTrue(entered)
        loading.cancel()
        probe.release()
        await loading.value
        guard case .loading = startup.state else { return XCTFail("Cancelled scene published a result or error") }
        XCTAssertEqual(probe.observations.calls, 1)
        XCTAssertFalse(probe.observations.timedOut)
        await startup.load()
        guard case .ready = startup.state else { return XCTFail("Reappearing scene could not retry") }
    }

    func testCancelledStartupCannotReplaceNewAttempt() async throws {
        try await assertLateStartupCannotReplaceNewAttempt(cancelFirst: true)
    }

    func testSupersededStartupCannotReplaceNewAttemptEvenWithoutCancellation() async throws {
        try await assertLateStartupCannotReplaceNewAttempt(cancelFirst: false)
    }

    private func assertLateStartupCannotReplaceNewAttempt(cancelFirst: Bool) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = BlockingOpenProbe()
        defer { probe.release() }
        let attempts = StartupAttempts(directory: directory, probe: probe)
        let startup = LocalLibraryStartup { try await attempts.open() }
        let first = Task { await startup.load() }
        let entered = await probe.waitUntilEntered()
        XCTAssertTrue(entered)
        if cancelFirst { first.cancel() }
        await startup.load()
        guard case .ready(let latest) = startup.state else {
            probe.release(); await first.value
            return XCTFail("New attempt did not open the libraries")
        }
        probe.release()
        await first.value
        guard case .ready(let retained) = startup.state else { return XCTFail("Late attempt replaced ready state") }
        XCTAssertTrue(retained.notes === latest.notes)
        XCTAssertTrue(retained.importedBuilds === latest.importedBuilds)
        XCTAssertFalse(probe.observations.timedOut)
        // Propagation cancels between blocking SQLite operations, not by forcing
        // an in-flight migration to abort. It must skip opening the second file.
        XCTAssertEqual(probe.observations.calls, cancelFirst ? 1 : 2)
    }

    func testFailureIsExplicitAndLaterAppearanceCanRetryWithoutReopeningReadyStores() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let attempts = StartupAttempts(directory: directory, failFirst: true)
        let startup = LocalLibraryStartup { try await attempts.open() }
        await startup.load()
        guard case .unavailable = startup.state else { return XCTFail("Expected explicit failure") }
        await startup.load()
        guard case .ready(let original) = startup.state else { return XCTFail("Expected retry to succeed") }
        await startup.load()
        guard case .ready(let retained) = startup.state else { return XCTFail("Ready state was lost") }
        XCTAssertTrue(retained.notes === original.notes)
        let attemptsCount = await attempts.count
        XCTAssertEqual(attemptsCount, 2)
    }

    func testFactoryPropagatesDirectoryPreparationError() async throws {
        do {
            _ = try await LocalLibraryStores.open { throw DraftStoreError.database(10) }
            XCTFail("Directory failure must remain an error")
        } catch {
            XCTAssertEqual(error as? DraftStoreError, .database(10))
        }
    }
}
