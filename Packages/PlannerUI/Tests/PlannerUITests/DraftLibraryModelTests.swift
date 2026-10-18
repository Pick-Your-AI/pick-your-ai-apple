import XCTest
import PlannerData
@testable import PlannerUI

@MainActor
final class DraftLibraryModelTests: XCTestCase {
    private func fixture() throws -> (DraftStore, DraftLibraryModel, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = try DraftStore(url: folder.appendingPathComponent("drafts.sqlite"))
        return (store, DraftLibraryModel(store: store), folder)
    }
    func testCreateSaveReopenDuplicateAndDelete() async throws {
        let (store, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.create()
        let id = try XCTUnwrap(model.selected?.id)
        model.title = "My draft"; model.notes = "Offline notes"
        XCTAssertTrue(model.dirty)
        await model.save()
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.status, "Saved locally")
        model.close()
        let second = DraftLibraryModel(store: store)
        await second.refresh()
        await second.open(try XCTUnwrap(second.records.first))
        XCTAssertEqual(second.notes, "Offline notes")
        let original = try await store.read(id: id)
        await second.duplicate(original)
        XCTAssertEqual(second.records.count, 2)
        XCTAssertNotEqual(second.selected?.id, id)
        XCTAssertEqual(second.notes, "Offline notes")
        await second.delete(original)
        XCTAssertEqual(second.records.count, 1)
    }
    func testConflictPreservesUnsavedInput() async throws {
        let (store, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.create()
        let original = try XCTUnwrap(model.selected)
        _ = try await store.rename(id: original.id, expectedRevision: original.revision, title: "Concurrent edit")
        model.title = "My unsaved edit"
        await model.save()
        XCTAssertEqual(model.status, "Not saved")
        XCTAssertEqual(model.title, "My unsaved edit")
        XCTAssertTrue(model.dirty)
        XCTAssertTrue(model.notice?.contains("newer revision") == true)
        model.close()
        await model.open(try XCTUnwrap(model.records.first))
        XCTAssertEqual(model.selected?.revision, original.revision + 1)
        XCTAssertEqual(model.title, "Concurrent edit")
        model.notes = "Recovered edit"
        await model.save()
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, original.revision + 2)
    }
    func testUnknownEditorPayloadIsPreserved() async throws {
        let (store, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = UUID()
        let record = try await store.save(id: id, expectedRevision: nil, title: "Future", payload: Data("{\"editorVersion\":2,\"notes\":\"future\"}".utf8))
        await model.open(record)
        XCTAssertNil(model.selected)
        XCTAssertNotNil(model.notice)
        let unchanged = try await store.read(id: id)
        XCTAssertEqual(unchanged, record)
    }
    func testUnknownPayloadFieldsAreNotSilentlyDiscarded() async throws {
        let (store, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let record = try await store.save(id: UUID(), expectedRevision: nil, title: "Extended",
            payload: Data("{\"editorVersion\":1,\"notes\":\"known\",\"futureField\":true}".utf8))
        await model.open(record)
        XCTAssertNil(model.selected)
        XCTAssertNotNil(model.notice)
        let unchanged = try await store.read(id: record.id)
        XCTAssertEqual(unchanged, record)
    }
    func testInvalidTitleRetainsEditsAndDoesNotAcknowledgeSave() async throws {
        let (_, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.create()
        model.title = String(repeating: "x", count: 1025)
        await model.save()
        XCTAssertTrue(model.dirty)
        XCTAssertEqual(model.status, "Not saved")
        XCTAssertEqual(model.selected?.revision, 1)
    }
}

private actor ControlledStorage: DraftLibraryStorage {
    let store: DraftStore
    var failRefresh = false
    var pauseNextSave = false
    var pauseNextDelete = false
    var pauseNextRestore = false
    var pauseNextHistory = false
    var pauseNextRead = false
    var waiting: CheckedContinuation<Void, Never>?
    var entered: CheckedContinuation<Void, Never>?
    var saveEntered = false
    init(store: DraftStore) { self.store = store }
    func configure(failRefresh: Bool = false, pause: Bool = false, pauseDelete: Bool = false, pauseRestore: Bool = false, pauseHistory: Bool = false, pauseRead: Bool = false) {
        self.failRefresh = failRefresh; pauseNextSave = pause; pauseNextDelete = pauseDelete; pauseNextRestore = pauseRestore; pauseNextHistory = pauseHistory; pauseNextRead = pauseRead
    }
    func waitForSave() async {
        if saveEntered { return }
        await withCheckedContinuation { entered = $0 }
    }
    func resumeSave() { waiting?.resume(); waiting = nil }
    func read(id: UUID) async throws -> DraftRecord {
        if pauseNextRead {
            pauseNextRead = false
            await withCheckedContinuation { continuation in
                waiting = continuation; saveEntered = true; entered?.resume(); entered = nil
            }
        }
        return try await store.read(id: id)
    }
    func history(id: UUID, limit: Int, offset: Int) async throws -> DraftPage {
        if pauseNextHistory {
            pauseNextHistory = false
            await withCheckedContinuation { continuation in
                waiting = continuation; saveEntered = true; entered?.resume(); entered = nil
            }
        }
        return try await store.history(id: id, limit: limit, offset: offset)
    }
    func restore(id: UUID, revision: Int, expectedRevision: Int) async throws -> DraftRecord {
        if pauseNextRestore {
            pauseNextRestore = false
            await withCheckedContinuation { continuation in
                waiting = continuation; saveEntered = true; entered?.resume(); entered = nil
            }
        }
        return try await store.restore(id: id, revision: revision, expectedRevision: expectedRevision)
    }
    func list(limit: Int, offset: Int) async throws -> DraftPage {
        if failRefresh { throw DraftStoreError.database(10) }
        return try await store.list(limit: limit, offset: offset)
    }
    func save(id: UUID, expectedRevision: Int?, title: String, payload: Data) async throws -> DraftRecord {
        if pauseNextSave {
            pauseNextSave = false
            await withCheckedContinuation { continuation in
                waiting = continuation; saveEntered = true; entered?.resume(); entered = nil
            }
        }
        return try await store.save(id: id, expectedRevision: expectedRevision, title: title, payload: payload)
    }
    func duplicate(id: UUID, expectedRevision: Int, newID: UUID) async throws -> DraftRecord {
        try await store.duplicate(id: id, expectedRevision: expectedRevision, newID: newID)
    }
    func delete(id: UUID, expectedRevision: Int) async throws {
        if pauseNextDelete {
            pauseNextDelete = false
            await withCheckedContinuation { continuation in
                waiting = continuation; saveEntered = true; entered?.resume(); entered = nil
            }
        }
        try await store.delete(id: id, expectedRevision: expectedRevision)
    }
}

extension DraftLibraryModelTests {
    func testEditsDuringOpenKeepOriginalDraftAndUnsavedInput() async throws {
        let (store, _, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let controlled = ControlledStorage(store: store)
        let model = DraftLibraryModel(store: controlled)
        await model.create()
        let original = try XCTUnwrap(model.selected)
        let target = try await store.save(id: UUID(), expectedRevision: nil, title: "Other draft",
            payload: JSONEncoder().encode(EditorPayload(notes: "Other saved notes")))
        await controlled.configure(pauseRead: true)
        let opening = Task { await model.open(target) }
        await controlled.waitForSave()
        model.title = "My newer title"
        model.notes = "My newer notes"
        await controlled.resumeSave()
        await opening.value
        XCTAssertEqual(model.selected, original)
        XCTAssertEqual(model.title, "My newer title")
        XCTAssertEqual(model.notes, "My newer notes")
        XCTAssertTrue(model.dirty)
        XCTAssertFalse(model.busy)
        let unchangedOriginal = try await store.read(id: original.id)
        let unchangedTarget = try await store.read(id: target.id)
        XCTAssertEqual(unchangedOriginal, original)
        XCTAssertEqual(unchangedTarget, target)
    }

    func testLifecycleSaveDuringOpenPersistsLatestEditsToOriginalDraft() async throws {
        let (store, _, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let controlled = ControlledStorage(store: store)
        let model = DraftLibraryModel(store: controlled)
        await model.create()
        let original = try XCTUnwrap(model.selected)
        let target = try await store.save(id: UUID(), expectedRevision: nil, title: "Other draft",
            payload: JSONEncoder().encode(EditorPayload(notes: "Other saved notes")))
        await controlled.configure(pauseRead: true)
        let opening = Task { await model.open(target) }
        await controlled.waitForSave()
        model.notes = "Pending lifecycle save"
        await model.save()
        model.title = "Latest original title"
        model.notes = "Latest original notes"
        await controlled.resumeSave()
        await opening.value
        XCTAssertEqual(model.selected?.id, original.id)
        XCTAssertEqual(model.selected?.revision, original.revision + 1)
        XCTAssertEqual(model.title, "Latest original title")
        XCTAssertEqual(model.notes, "Latest original notes")
        XCTAssertFalse(model.dirty)
        XCTAssertFalse(model.busy)
        let durable = try await store.read(id: original.id)
        XCTAssertEqual(durable.title, "Latest original title")
        XCTAssertEqual(try JSONDecoder().decode(EditorPayload.self, from: durable.payload).notes, "Latest original notes")
        let unchangedTarget = try await store.read(id: target.id)
        XCTAssertEqual(unchangedTarget, target)
    }

    func testEditsArrivingDuringSaveRemainDirty() async throws {
        let (store, _, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let controlled = ControlledStorage(store: store)
        let model = DraftLibraryModel(store: controlled)
        await model.create()
        model.notes = "Submitted"
        await controlled.configure(pause: true)
        let saving = Task { await model.save() }
        await controlled.waitForSave()
        model.notes = "Newer unsaved text"
        await controlled.resumeSave()
        await saving.value
        XCTAssertEqual(model.notes, "Newer unsaved text")
        XCTAssertTrue(model.dirty)
        XCTAssertEqual(model.selected?.revision, 2)
        await model.save()
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, 3)
    }
    func testRefreshFailureDoesNotRevokeDurableAcknowledgement() async throws {
        let (store, _, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let controlled = ControlledStorage(store: store)
        let model = DraftLibraryModel(store: controlled)
        await model.create()
        model.title = "Committed"
        await controlled.configure(failRefresh: true)
        await model.save()
        XCTAssertEqual(model.selected?.revision, 2)
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.status, "Saved locally")
        XCTAssertTrue(model.notice?.contains("could not refresh") == true)
    }
    func testDirtyNavigationGuardsAndSelectedDeletion() async throws {
        let (_, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.create()
        let record = try XCTUnwrap(model.selected)
        model.notes = "Unsaved"
        await model.create()
        await model.duplicate(record)
        await model.delete(record)
        XCTAssertEqual(model.selected?.id, record.id)
        XCTAssertEqual(model.notes, "Unsaved")
        XCTAssertEqual(model.records.count, 1)
        await model.save()
        await model.delete(try XCTUnwrap(model.selected))
        XCTAssertNil(model.selected)
        XCTAssertTrue(model.records.isEmpty)
    }
}


extension DraftLibraryModelTests {
    func testEditorBindingsCannotChangeDuringDestructiveDelete() async throws {
        let (store, _, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let controlled = ControlledStorage(store: store)
        let model = DraftLibraryModel(store: controlled)
        await model.create()
        let record = try XCTUnwrap(model.selected)
        await controlled.configure(pauseDelete: true)
        let deleting = Task { await model.delete(record) }
        await controlled.waitForSave()
        model.notes = "Input while disabled"
        model.title = "Input while disabled"
        XCTAssertEqual(model.notes, "")
        XCTAssertEqual(model.title, record.title)
        await controlled.resumeSave()
        await deleting.value
        XCTAssertNil(model.selected)
        XCTAssertTrue(model.records.isEmpty)
    }
}


extension DraftLibraryModelTests {
    func testLibraryKeepsOnlyOneBoundedPage() async throws {
        let (store, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0..<45 {
            _ = try await store.save(id: UUID(), expectedRevision: nil, title: "Draft \(index)",
                payload: JSONEncoder().encode(EditorPayload(notes: String(repeating: "x", count: 32_768))))
        }
        await model.refresh()
        XCTAssertEqual(model.records.count, DraftLibraryModel.pageSize)
        XCTAssertTrue(model.hasNextPage)
        let firstIDs = Set(model.records.map(\.id))
        await model.changePage(forward: true)
        XCTAssertEqual(model.records.count, DraftLibraryModel.pageSize)
        XCTAssertTrue(firstIDs.isDisjoint(with: model.records.map(\.id)))
        await model.changePage(forward: true)
        XCTAssertEqual(model.records.count, 5)
        XCTAssertFalse(model.hasNextPage)
        await model.changePage(forward: false)
        XCTAssertEqual(model.records.count, DraftLibraryModel.pageSize)
    }
}


extension DraftLibraryModelTests {
    func testRestoreAppendsHistoryAndReopensWithoutCurrentAnalysis() async throws {
        let (store, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.create()
        model.notes = "Earlier"; await model.save()
        let earlier = try XCTUnwrap(model.selected)
        model.notes = "Later"; await model.save()
        await model.restore(earlier)
        XCTAssertEqual(model.selected?.revision, 4)
        XCTAssertEqual(model.selected?.restoredFrom, 2)
        XCTAssertEqual(model.notes, "Earlier")
        XCTAssertFalse(model.dirty)
        XCTAssertFalse(try XCTUnwrap(model.selected).analysisIsCurrent)
        let history = try await store.history(id: earlier.id)
        XCTAssertEqual(history.records.map(\.revision), [4, 3, 2, 1])
        XCTAssertEqual(try JSONDecoder().decode(EditorPayload.self, from: history.records[1].payload).notes, "Later")
        let reopened = DraftLibraryModel(store: store)
        await reopened.open(id: earlier.id)
        XCTAssertEqual(reopened.notes, "Earlier")
        XCTAssertEqual(reopened.selected?.restoredFrom, 2)
    }
    func testRestoreCannotDiscardDirtyOrConcurrentSavedEdits() async throws {
        let (store, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.create()
        let earlier = try XCTUnwrap(model.selected)
        model.notes = "Later"; await model.save()
        model.notes = "Unsaved"
        await model.restore(earlier)
        XCTAssertEqual(model.notes, "Unsaved")
        XCTAssertEqual(model.selected?.revision, 2)
        await model.save()
        _ = try await store.rename(id: earlier.id, expectedRevision: 3, title: "Other scene")
        await model.restore(earlier)
        XCTAssertEqual(model.status, "Not restored")
        XCTAssertTrue(model.notice?.contains("newer revision") == true)
        let durable = try await store.read(id: earlier.id)
        XCTAssertEqual(durable.revision, 4)
        XCTAssertEqual(durable.title, "Other scene")
    }
    func testEditsDuringRestorationRemainDirtyAndCanBeSaved() async throws {
        let (store, _, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let controlled = ControlledStorage(store: store)
        let model = DraftLibraryModel(store: controlled)
        await model.create()
        let earlier = try XCTUnwrap(model.selected)
        model.notes = "Later"; await model.save()
        await controlled.configure(pauseRestore: true)
        let restoring = Task { await model.restore(earlier) }
        await controlled.waitForSave()
        model.notes = "Newest input"
        model.title = "Newest name"
        await controlled.resumeSave()
        await restoring.value
        XCTAssertEqual(model.selected?.revision, 3)
        XCTAssertEqual(model.notes, "Newest input")
        XCTAssertEqual(model.title, "Newest name")
        XCTAssertTrue(model.dirty)
        await model.save()
        XCTAssertEqual(model.selected?.revision, 4)
        XCTAssertFalse(model.dirty)
    }
    func testHistoryIsBoundedAndClearedAcrossDrafts() async throws {
        let (_, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        await model.create()
        for index in 1...24 { model.notes = "Revision \(index)"; await model.save() }
        await model.loadHistory()
        XCTAssertEqual(model.revisions.count, 20)
        XCTAssertEqual(model.revisions.first?.revision, 25)
        XCTAssertTrue(model.hasOlderRevisions)
        await model.loadHistory(offset: 20)
        XCTAssertEqual(model.revisions.count, 5)
        XCTAssertFalse(model.hasOlderRevisions)
        model.close()
        XCTAssertTrue(model.revisions.isEmpty)
        await model.create()
        XCTAssertTrue(model.revisions.isEmpty)
    }
    func testUnsupportedHistoryCannotBeRestoredFromEditor() async throws {
        let (store, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = UUID()
        let unsupported = try await store.save(id: id, expectedRevision: nil, title: "Future", payload: Data("{}".utf8))
        _ = try await store.save(id: id, expectedRevision: 1, title: "Current", payload: JSONEncoder().encode(EditorPayload(notes: "Supported")))
        await model.open(id: id)
        await model.restore(unsupported)
        XCTAssertEqual(model.selected?.revision, 2)
        XCTAssertEqual(model.notes, "Supported")
        let durable = try await store.read(id: id)
        XCTAssertEqual(durable.revision, 2)
    }
}


extension DraftLibraryModelTests {
    func testLifecycleSaveDuringHistoryReadIsDrainedWithLatestEdits() async throws {
        let (store, _, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let controlled = ControlledStorage(store: store)
        let model = DraftLibraryModel(store: controlled)
        await model.create()
        let id = try XCTUnwrap(model.selected?.id)
        model.notes = "Pending when history opens"
        await controlled.configure(pauseHistory: true)
        let reading = Task { await model.loadHistory() }
        await controlled.waitForSave()
        await model.save() // Same entry point as scene-phase background autosave.
        model.notes = "Latest before history completes"
        await controlled.resumeSave()
        await reading.value
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, 2)
        let durable = try await store.read(id: id)
        XCTAssertEqual(try JSONDecoder().decode(EditorPayload.self, from: durable.payload).notes, "Latest before history completes")
    }
    func testLifecycleSaveDuringRestoreUsesNewRevisionAndLatestEdits() async throws {
        let (store, _, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let controlled = ControlledStorage(store: store)
        let model = DraftLibraryModel(store: controlled)
        await model.create()
        let earlier = try XCTUnwrap(model.selected)
        model.notes = "Later"; await model.save()
        await controlled.configure(pauseRestore: true)
        let restoring = Task { await model.restore(earlier) }
        await controlled.waitForSave()
        model.notes = "New input during restoration"
        await model.save()
        await controlled.resumeSave()
        await restoring.value
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.selected?.revision, 4)
        XCTAssertEqual(model.notes, "New input during restoration")
        let history = try await store.history(id: earlier.id)
        XCTAssertEqual(history.records.map(\.revision), [4, 3, 2, 1])
        XCTAssertEqual(history.records[1].restoredFrom, 1)
    }
}
