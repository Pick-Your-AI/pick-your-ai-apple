import XCTest
import PlannerData
@testable import PlannerUI

private actor ExactTextPausedStorage: DraftLibraryStorage {
    let store: DraftStore
    private var pauseNextRead = false
    private var pauseNextRestore = false
    private var paused: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    init(_ store: DraftStore) { self.store = store }
    func pauseRead() { pauseNextRead = true }
    func pauseRestore() { pauseNextRestore = true }
    func waitForPause() async {
        if paused != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() { paused?.resume(); paused = nil }
    private func suspend() async {
        await withCheckedContinuation { paused = $0; observer?.resume(); observer = nil }
    }
    func read(id: UUID) async throws -> DraftRecord {
        if pauseNextRead { pauseNextRead = false; await suspend() }
        return try await store.read(id: id)
    }
    func list(limit: Int, offset: Int) async throws -> DraftPage {
        try await store.list(limit: limit, offset: offset)
    }
    func history(id: UUID, limit: Int, offset: Int) async throws -> DraftPage {
        try await store.history(id: id, limit: limit, offset: offset)
    }
    func restore(id: UUID, revision: Int, expectedRevision: Int) async throws -> DraftRecord {
        if pauseNextRestore { pauseNextRestore = false; await suspend() }
        return try await store.restore(id: id, revision: revision, expectedRevision: expectedRevision)
    }
    func save(id: UUID, expectedRevision: Int?, title: String, payload: Data) async throws -> DraftRecord {
        try await store.save(id: id, expectedRevision: expectedRevision, title: title, payload: payload)
    }
    func duplicate(id: UUID, expectedRevision: Int, newID: UUID) async throws -> DraftRecord {
        try await store.duplicate(id: id, expectedRevision: expectedRevision, newID: newID)
    }
    func delete(id: UUID, expectedRevision: Int) async throws {
        try await store.delete(id: id, expectedRevision: expectedRevision)
    }
}

private actor ExactTextClock {
    private var sleeper: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func sleep() async throws {
        await withCheckedContinuation { sleeper = $0; observer?.resume(); observer = nil }
    }
    func waitForSleep() async {
        if sleeper != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { sleeper?.resume(); sleeper = nil }
}

@MainActor
final class EditorExactTextTests: XCTestCase {
    private let composed = "Caf\u{00E9}"
    private let decomposed = "Cafe\u{0301}"

    private func store() throws -> (DraftStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (try DraftStore(url: folder.appendingPathComponent("drafts.sqlite")), folder)
    }
    private func seed(_ store: DraftStore, title: String, notes: String) async throws -> DraftRecord {
        try await store.save(id: UUID(), expectedRevision: nil, title: title,
            payload: JSONEncoder().encode(EditorPayload(notes: notes)))
    }
    private func assertBytes(_ actual: String, _ expected: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(actual.utf8), Array(expected.utf8), file: file, line: line)
    }
    private func checkRoundTrip(titleField: Bool, from: String, to: String) async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = try await seed(store, title: titleField ? from : "Unaffected title",
                                     notes: titleField ? "Unaffected notes" : from)
        let model = DraftLibraryModel(store: store, autosaveWait: nil)
        await model.open(id: initial.id)
        XCTAssertFalse(model.dirty)
        XCTAssertFalse(model.canUndo)
        if titleField { model.title = to } else { model.notes = to }
        assertBytes(titleField ? model.title : model.notes, to)
        XCTAssertTrue(model.dirty)
        XCTAssertTrue(model.canUndo)
        await model.save()
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, 2)
        let fresh = DraftLibraryModel(
            store: try DraftStore(url: folder.appendingPathComponent("drafts.sqlite")), autosaveWait: nil)
        await fresh.open(id: initial.id)
        assertBytes(titleField ? fresh.title : fresh.notes, to)
        assertBytes(titleField ? fresh.notes : fresh.title,
                    titleField ? "Unaffected notes" : "Unaffected title")

        model.undo()
        assertBytes(titleField ? model.title : model.notes, from)
        XCTAssertTrue(model.dirty)
        XCTAssertTrue(model.canRedo)
        await model.save()
        XCTAssertEqual(model.selected?.revision, 3)
        model.redo()
        assertBytes(titleField ? model.title : model.notes, to)
        XCTAssertTrue(model.dirty)
        await model.save()
        XCTAssertEqual(model.selected?.revision, 4)
        let history = try await store.history(id: initial.id)
        XCTAssertEqual(history.records.map(\.revision), [4, 3, 2, 1])
        let values = try history.records.map { record in
            titleField ? record.title : try JSONDecoder().decode(EditorPayload.self, from: record.payload).notes
        }
        XCTAssertEqual(values.map { Array($0.utf8) }, [to, from, to, from].map { Array($0.utf8) })
        XCTAssertTrue(history.records.allSatisfy { !$0.analysisIsCurrent })
    }

    func testCanonicalTitleEditPersistsExactBytesAndUndoRedoRevisions() async throws {
        XCTAssertEqual(composed, decomposed)
        XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))
        try await checkRoundTrip(titleField: true, from: composed, to: decomposed)
        try await checkRoundTrip(titleField: true, from: decomposed, to: composed)
    }
    func testCanonicalNotesEditPersistsExactBytesAndUndoRedoRevisions() async throws {
        try await checkRoundTrip(titleField: false, from: composed, to: decomposed)
        try await checkRoundTrip(titleField: false, from: decomposed, to: composed)
    }
    func testExactRepeatedInputDoesNotCreateDirtyStateOrUndoOrRevision() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = try await seed(store, title: composed, notes: decomposed)
        let model = DraftLibraryModel(store: store, autosaveWait: nil)
        await model.open(id: initial.id)
        model.title = String(decoding: Array(composed.utf8), as: UTF8.self)
        model.notes = String(decoding: Array(decomposed.utf8), as: UTF8.self)
        XCTAssertFalse(model.dirty)
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.canRedo)
        await model.save()
        let durable = try await store.read(id: initial.id)
        XCTAssertEqual(durable.revision, 1)
        assertBytes(durable.title, composed)
        assertBytes(try JSONDecoder().decode(EditorPayload.self, from: durable.payload).notes, decomposed)
    }
    func testOrdinaryAsciiEditRetainsTheExistingSaveAndUndoBehavior() async throws {
        try await checkRoundTrip(titleField: true, from: "Original", to: "Amended")
        try await checkRoundTrip(titleField: false, from: "Original notes", to: "Amended notes")
    }
    func testCanonicalBindingEditSchedulesTheNormalDebouncedSave() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = try await seed(store, title: composed, notes: composed)
        let clock = ExactTextClock()
        let model = DraftLibraryModel(store: store, autosaveWait: { try await clock.sleep() })
        await model.open(id: initial.id)
        model.notes = decomposed
        let timer = try XCTUnwrap(model.pendingAutosave)
        await clock.waitForSleep()
        await clock.release()
        await timer.value
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, 2)
        let durable = try await store.read(id: initial.id)
        assertBytes(try JSONDecoder().decode(EditorPayload.self, from: durable.payload).notes, decomposed)
    }
    func testCanonicalEditsDuringRestoreSurviveTheActorSuspension() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let earlier = try await seed(store, title: "Earlier title", notes: "Earlier notes")
        _ = try await store.save(id: earlier.id, expectedRevision: 1, title: composed,
            payload: JSONEncoder().encode(EditorPayload(notes: composed)))
        let paused = ExactTextPausedStorage(store)
        let model = DraftLibraryModel(store: paused, autosaveWait: nil)
        await model.open(id: earlier.id)
        await paused.pauseRestore()
        let restoration = Task { @MainActor in await model.restore(earlier) }
        await paused.waitForPause()
        model.title = decomposed
        model.notes = decomposed
        await paused.resume()
        await restoration.value
        assertBytes(model.title, decomposed)
        assertBytes(model.notes, decomposed)
        XCTAssertTrue(model.dirty)
        XCTAssertEqual(model.selected?.revision, 3)
        await model.save()
        let durable = try await store.read(id: earlier.id)
        XCTAssertEqual(durable.revision, 4)
        assertBytes(durable.title, decomposed)
        assertBytes(try JSONDecoder().decode(EditorPayload.self, from: durable.payload).notes, decomposed)
        XCTAssertFalse(durable.analysisIsCurrent)
    }
    func testCanonicalLateEditPreventsAnOlderOpenFromReplacingTheSelection() async throws {
        let (store, folder) = try store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try await seed(store, title: composed, notes: composed)
        let other = try await seed(store, title: "Other title", notes: "Other notes")
        let paused = ExactTextPausedStorage(store)
        let model = DraftLibraryModel(store: paused, autosaveWait: nil)
        await model.open(id: first.id)
        await paused.pauseRead()
        let opening = Task { @MainActor in await model.open(id: other.id) }
        await paused.waitForPause()
        model.notes = decomposed
        await paused.resume()
        await opening.value
        XCTAssertEqual(model.selected?.id, first.id)
        assertBytes(model.title, composed)
        assertBytes(model.notes, decomposed)
        XCTAssertTrue(model.dirty)
        await model.save()
        let durable = try await store.read(id: first.id)
        XCTAssertEqual(durable.revision, 2)
        assertBytes(try JSONDecoder().decode(EditorPayload.self, from: durable.payload).notes, decomposed)
        let untouched = try await store.read(id: other.id)
        XCTAssertEqual(untouched.revision, 1)
        assertBytes(untouched.title, "Other title")
    }
}
