import XCTest
import PlannerData
@testable import PlannerUI

/// Deliberately ignores cancellation: the consumer must reject old generations itself.
private actor ManualEditorClock {
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    private var started = 0
    func sleep() async throws {
        await withCheckedContinuation { continuation in
            sleepers.append(continuation); started += 1
            let ready = observers.filter { $0.0 <= started }
            observers.removeAll { $0.0 <= started }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForSleeps(_ count: Int) async {
        if started >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func releaseFirst() { if !sleepers.isEmpty { sleepers.removeFirst().resume() } }
    func releaseAll() {
        let ready = sleepers; sleepers = []
        ready.forEach { $0.resume() }
    }
}

private actor PausedEditorStorage: DraftLibraryStorage {
    let store: DraftStore
    private var nextSave = false
    private var nextRead = false
    private var nextRestore = false
    private var suspended: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    init(_ store: DraftStore) { self.store = store }
    func pauseSave() { nextSave = true }
    func pauseRead() { nextRead = true }
    func pauseRestore() { nextRestore = true }
    func waitForPause() async {
        if suspended != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() { suspended?.resume(); suspended = nil }
    private func suspend() async {
        await withCheckedContinuation { suspended = $0; observer?.resume(); observer = nil }
    }
    func read(id: UUID) async throws -> DraftRecord {
        if nextRead { nextRead = false; await suspend() }
        return try await store.read(id: id)
    }
    func list(limit: Int, offset: Int) async throws -> DraftPage { try await store.list(limit: limit, offset: offset) }
    func history(id: UUID, limit: Int, offset: Int) async throws -> DraftPage {
        try await store.history(id: id, limit: limit, offset: offset)
    }
    func restore(id: UUID, revision: Int, expectedRevision: Int) async throws -> DraftRecord {
        if nextRestore { nextRestore = false; await suspend() }
        return try await store.restore(id: id, revision: revision, expectedRevision: expectedRevision)
    }
    func save(id: UUID, expectedRevision: Int?, title: String, payload: Data) async throws -> DraftRecord {
        if nextSave { nextSave = false; await suspend() }
        return try await store.save(id: id, expectedRevision: expectedRevision, title: title, payload: payload)
    }
    func duplicate(id: UUID, expectedRevision: Int, newID: UUID) async throws -> DraftRecord {
        try await store.duplicate(id: id, expectedRevision: expectedRevision, newID: newID)
    }
    func delete(id: UUID, expectedRevision: Int) async throws { try await store.delete(id: id, expectedRevision: expectedRevision) }
}

@MainActor
final class EditorAutosaveTests: XCTestCase {
    private func store() throws -> (DraftStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (try DraftStore(url: folder.appendingPathComponent("drafts.sqlite")), folder)
    }
    func testDebounceSavesOnlyLatestInputAndReopensAcknowledgedRevision() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualEditorClock()
        let model = DraftLibraryModel(store: store, autosaveWait: { try await clock.sleep() })
        await model.create()
        let id = try XCTUnwrap(model.selected?.id)
        model.notes = "First edit"
        let first = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(1)
        model.notes = "Latest edit"
        let last = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(2)
        await clock.releaseAll()
        await first.value; await last.value
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, 2)
        let reopened = DraftLibraryModel(store: try DraftStore(url: folder.appendingPathComponent("drafts.sqlite")), autosaveWait: nil)
        await reopened.open(id: id)
        XCTAssertEqual(reopened.notes, "Latest edit")
        let history = try await store.history(id: id)
        XCTAssertEqual(history.records.map(\.revision), [2, 1])
        XCTAssertFalse(try XCTUnwrap(model.selected).analysisIsCurrent)
    }
    func testDiscardDecisionFreezesCancelledTimerAndLifecycleSaveUntilConfirmed() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualEditorClock()
        let model = DraftLibraryModel(store: store, autosaveWait: { try await clock.sleep() })
        await model.create()
        let original = try XCTUnwrap(model.selected)
        model.notes = "Do not persist this amendment"
        let timer = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(1)
        model.requestClose()
        XCTAssertTrue(model.awaitingDiscardDecision)
        XCTAssertFalse(model.canEdit)
        XCTAssertFalse(model.canUndo)
        await clock.releaseAll(); await timer.value
        await model.save() // A lifecycle callback while the dialog is visible.
        XCTAssertTrue(model.dirty)
        XCTAssertNil(model.pendingAutosave)
        XCTAssertEqual(model.selected, original)
        let pending = try await store.read(id: original.id)
        XCTAssertEqual(pending, original)
        model.discardChangesAndClose()
        XCTAssertNil(model.selected)
        XCTAssertFalse(model.awaitingDiscardDecision)
        let reopened = try DraftStore(url: folder.appendingPathComponent("drafts.sqlite"))
        let durable = try await reopened.read(id: original.id)
        XCTAssertEqual(durable, original)
        let history = try await reopened.history(id: original.id)
        XCTAssertEqual(history.records.count, 1)
    }

    func testCancellingDiscardDecisionRestartsProductionSavePathForLatestInput() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualEditorClock()
        let model = DraftLibraryModel(store: store, autosaveWait: { try await clock.sleep() })
        await model.create()
        let id = try XCTUnwrap(model.selected?.id)
        model.notes = "Keep editing this amendment"
        let cancelled = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(1)
        model.requestClose()
        await clock.releaseAll(); await cancelled.value
        model.cancelDiscardDecision()
        XCTAssertFalse(model.awaitingDiscardDecision)
        XCTAssertTrue(model.canEdit)
        let resumed = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(2)
        await clock.releaseAll(); await resumed.value
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, 2)
        let durable = try await store.read(id: id)
        XCTAssertEqual(try JSONDecoder().decode(EditorPayload.self, from: durable.payload).notes,
                       "Keep editing this amendment")
    }

    func testDialogBindingDismissalBeforeDiscardActionCannotRearmAWrite() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualEditorClock()
        let model = DraftLibraryModel(store: store, autosaveWait: { try await clock.sleep() })
        await model.create()
        let original = try XCTUnwrap(model.selected)
        model.notes = "Discard after dismissal"
        let old = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(1)
        model.requestClose()
        await clock.releaseAll(); await old.value
        model.cancelDiscardDecision() // SwiftUI binding can dismiss first.
        let rearmed = try XCTUnwrap(model.pendingAutosave)
        model.discardChangesAndClose() // Same synchronous main-actor turn.
        await clock.waitForSleeps(2)
        await clock.releaseAll(); await rearmed.value
        XCTAssertNil(model.selected)
        XCTAssertNil(model.pendingAutosave)
        let durable = try await store.read(id: original.id)
        XCTAssertEqual(durable, original)
    }

    func testCancelledDraftTimerCannotSaveAnotherDraft() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualEditorClock()
        let model = DraftLibraryModel(store: store, autosaveWait: { try await clock.sleep() })
        await model.create()
        let discardedID = try XCTUnwrap(model.selected?.id)
        model.notes = "Explicitly discarded"
        let old = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(1)
        model.close()
        await model.create()
        let currentID = try XCTUnwrap(model.selected?.id)
        model.notes = "Current draft"
        let current = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(2)
        await clock.releaseFirst(); await old.value
        XCTAssertEqual(model.selected?.id, currentID)
        XCTAssertEqual(model.selected?.revision, 1)
        XCTAssertTrue(model.dirty)
        await clock.releaseAll(); await current.value
        let discarded = try await store.read(id: discardedID)
        XCTAssertEqual(discarded.revision, 1)
        XCTAssertEqual(model.selected?.revision, 2)
        XCTAssertEqual(model.notes, "Current draft")
    }
    func testAutosaveDuringSuspendedWriteDrainsLatestInput() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualEditorClock(), controlled = PausedEditorStorage(store)
        let model = DraftLibraryModel(store: controlled, autosaveWait: { try await clock.sleep() })
        await model.create()
        await controlled.pauseSave()
        model.notes = "Submitted"
        let first = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(1); await clock.releaseFirst(); await controlled.waitForPause()
        XCTAssertTrue(model.canEdit)
        model.notes = "Typed while saving"
        let second = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(2); await clock.releaseFirst(); await second.value
        await controlled.resume(); await first.value
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.notes, "Typed while saving")
        XCTAssertEqual(model.selected?.revision, 3)
        let history = try await store.history(id: XCTUnwrap(model.selected?.id))
        XCTAssertEqual(history.records.map(\.revision), [3, 2, 1])
        XCTAssertEqual(try JSONDecoder().decode(EditorPayload.self, from: history.records[1].payload).notes, "Submitted")
    }
    func testInputReturningToOldBaselineDuringWriteIsAutosavedAfterAcknowledgement() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualEditorClock(), controlled = PausedEditorStorage(store)
        let model = DraftLibraryModel(store: controlled, autosaveWait: { try await clock.sleep() })
        await model.create()
        await controlled.pauseSave()
        model.notes = "Submitted"
        let first = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(1); await clock.releaseFirst(); await controlled.waitForPause()
        model.notes = ""
        XCTAssertFalse(model.dirty) // Matches only the old durable baseline.
        XCTAssertNil(model.pendingAutosave)
        await controlled.resume(); await first.value
        XCTAssertEqual(model.selected?.revision, 2)
        XCTAssertEqual(model.notes, "")
        XCTAssertTrue(model.dirty)
        let reverted = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(2); await clock.releaseAll(); await reverted.value
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, 3)
        let history = try await store.history(id: XCTUnwrap(model.selected?.id))
        XCTAssertEqual(history.records.map(\.revision), [3, 2, 1])
        XCTAssertEqual(try JSONDecoder().decode(EditorPayload.self, from: history.records[0].payload).notes, "")
        XCTAssertEqual(try JSONDecoder().decode(EditorPayload.self, from: history.records[1].payload).notes, "Submitted")
        XCTAssertNil(model.pendingAutosave)
    }
    func testDelayedOpenPreservesAndAutosavesNewInputInOriginalDraft() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualEditorClock(), controlled = PausedEditorStorage(store)
        let model = DraftLibraryModel(store: controlled, autosaveWait: { try await clock.sleep() })
        await model.create()
        let originalID = try XCTUnwrap(model.selected?.id)
        let other = try await store.save(id: UUID(), expectedRevision: nil, title: "Other", payload: JSONEncoder().encode(EditorPayload(notes: "Other contents")))
        await controlled.pauseRead()
        let opening = Task { await model.open(other) }
        await controlled.waitForPause()
        model.notes = "Late original-draft edit"
        let autosave = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(1); await clock.releaseAll(); await autosave.value
        await controlled.resume(); await opening.value
        XCTAssertEqual(model.selected?.id, originalID)
        XCTAssertEqual(model.notes, "Late original-draft edit")
        XCTAssertEqual(model.selected?.revision, 2)
        XCTAssertFalse(model.dirty)
        let unchanged = try await store.read(id: other.id)
        XCTAssertEqual(unchanged, other)
    }
    func testRestorationPreservesRevertedLateInputAndAutosavesIt() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let earlier = try await store.save(id: UUID(), expectedRevision: nil, title: "Earlier title",
                                           payload: JSONEncoder().encode(EditorPayload(notes: "Earlier")))
        let later = try await store.save(id: earlier.id, expectedRevision: earlier.revision, title: "Later title",
                                         payload: JSONEncoder().encode(EditorPayload(notes: "Later")))
        let clock = ManualEditorClock(), controlled = PausedEditorStorage(store)
        let model = DraftLibraryModel(store: controlled, autosaveWait: { try await clock.sleep() })
        await model.open(later)
        await controlled.pauseRestore()
        let restoring = Task { await model.restore(earlier) }
        await controlled.waitForPause()
        model.notes = "Newer input"
        let cancelled = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(1)
        model.notes = "Later"
        XCTAssertFalse(model.dirty)
        XCTAssertNil(model.pendingAutosave)
        await controlled.resume(); await restoring.value
        XCTAssertEqual(model.notes, "Later") // The field was edited despite matching its old value.
        XCTAssertEqual(model.title, "Earlier title") // The untouched field is restored.
        XCTAssertEqual(model.selected?.revision, 3)
        XCTAssertTrue(model.dirty)
        let autosave = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(2); await clock.releaseAll()
        await cancelled.value; await autosave.value
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, 4)
        let history = try await store.history(id: earlier.id)
        XCTAssertEqual(history.records.map(\.revision), [4, 3, 2, 1])
        XCTAssertEqual(try JSONDecoder().decode(EditorPayload.self, from: history.records[0].payload).notes, "Later")
        XCTAssertEqual(try JSONDecoder().decode(EditorPayload.self, from: history.records[1].payload).notes, "Earlier")
        XCTAssertEqual(history.records[1].restoredFrom, earlier.revision)
        XCTAssertTrue(history.records.allSatisfy { !$0.analysisIsCurrent })
    }
    func testFailedAutosaveRetainsDirtyInputAndCanRetryExplicitly() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualEditorClock()
        let model = DraftLibraryModel(store: store, autosaveWait: { try await clock.sleep() })
        await model.create()
        model.title = String(repeating: "x", count: 1_025)
        let attempt = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(1); await clock.releaseAll(); await attempt.value
        XCTAssertTrue(model.dirty)
        XCTAssertEqual(model.status, "Not saved")
        XCTAssertEqual(model.selected?.revision, 1)
        XCTAssertNil(model.pendingAutosave)
        model.title = "Corrected"
        let retryTimer = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleeps(2)
        await model.save()
        await clock.releaseAll(); await retryTimer.value
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, 2)
    }
    func testUndoAndRedoAppendRevisionsAndNewEditClearsRedo() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = DraftLibraryModel(store: store, autosaveWait: nil)
        await model.create()
        model.notes = "One"; await model.save()
        model.notes = "Two"; await model.save()
        model.undo()
        XCTAssertEqual(model.notes, "One")
        XCTAssertTrue(model.dirty)
        XCTAssertTrue(model.canRedo)
        await model.save()
        model.redo(); await model.save()
        XCTAssertEqual(model.notes, "Two")
        XCTAssertEqual(model.selected?.revision, 5)
        let history = try await store.history(id: XCTUnwrap(model.selected?.id))
        XCTAssertEqual(history.records.map(\.revision), [5, 4, 3, 2, 1])
        XCTAssertTrue(history.records.allSatisfy { !$0.analysisIsCurrent })
        model.undo(); model.notes = "New branch"
        XCTAssertFalse(model.canRedo)
        model.close()
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.canRedo)
    }
    func testUndoAfterNewerEditAndRestorationRetainsEveryDurableRevision() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = DraftLibraryModel(store: store, autosaveWait: nil)
        await model.create()
        model.notes = "Earlier"; await model.save()
        let earlier = try XCTUnwrap(model.selected)
        model.notes = "Later"; await model.save()
        await model.restore(earlier)
        model.notes = "Newest"; await model.save()
        model.undo(); await model.save()
        XCTAssertEqual(model.notes, "Earlier")
        model.undo(); await model.save()
        XCTAssertEqual(model.notes, "Later")
        let history = try await store.history(id: earlier.id)
        XCTAssertEqual(history.records.map(\.revision), [7, 6, 5, 4, 3, 2, 1])
        XCTAssertEqual(try JSONDecoder().decode(EditorPayload.self, from: history.records[2].payload).notes, "Newest")
        XCTAssertEqual(history.records[3].restoredFrom, 2)
        XCTAssertTrue(history.records.allSatisfy { !$0.analysisIsCurrent })
    }
}

final class EditorUndoHistoryTests: XCTestCase {
    func testBothHistoryDirectionsRemainBounded() {
        var history = EditorUndoHistory()
        for index in 0..<150 { history.record(EditorContents(title: "Draft", notes: "Edit \(index)")) }
        XCTAssertEqual(history.past.count, EditorUndoHistory.maximumEntries)
        var current = EditorContents(title: "Draft", notes: "Current")
        while let previous = history.undo(current) { current = previous }
        XCTAssertEqual(history.future.count, EditorUndoHistory.maximumEntries)
        while let next = history.redo(current) { current = next }
        XCTAssertEqual(history.past.count, EditorUndoHistory.maximumEntries)
        XCTAssertEqual(current.notes, "Current")
    }
    func testByteLimitAndOversizedCurrentTextDoNotSilentlyDiscardInput() {
        var history = EditorUndoHistory()
        let large = EditorContents(title: "", notes: String(repeating: "x", count: 1_500_000))
        for _ in 0..<10 { history.record(large) }
        XCTAssertLessThanOrEqual(history.byteCount, EditorUndoHistory.maximumBytes)
        let oversized = EditorContents(title: "", notes: String(repeating: "x", count: EditorUndoHistory.maximumBytes + 1))
        let prior = history.past
        XCTAssertNil(history.undo(oversized))
        XCTAssertEqual(history.past, prior)
        XCTAssertNotNil(history.undo(large))
        XCTAssertTrue(history.canRedo(large))
        XCTAssertNotNil(history.redo(large))
        XCTAssertTrue(history.canUndo(large))
        XCTAssertLessThanOrEqual(history.byteCount, EditorUndoHistory.maximumBytes)
    }
}
