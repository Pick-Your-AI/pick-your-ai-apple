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
        second.open(try XCTUnwrap(second.records.first))
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
    }
    func testUnknownEditorPayloadIsPreserved() async throws {
        let (store, model, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = UUID()
        let record = try await store.save(id: id, expectedRevision: nil, title: "Future", payload: Data("{\"editorVersion\":2,\"notes\":\"future\"}".utf8))
        model.open(record)
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
        model.open(record)
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
    var waiting: CheckedContinuation<Void, Never>?
    var entered: CheckedContinuation<Void, Never>?
    var saveEntered = false
    init(store: DraftStore) { self.store = store }
    func configure(failRefresh: Bool = false, pause: Bool = false, pauseDelete: Bool = false) {
        self.failRefresh = failRefresh; pauseNextSave = pause; pauseNextDelete = pauseDelete
    }
    func waitForSave() async {
        if saveEntered { return }
        await withCheckedContinuation { entered = $0 }
    }
    func resumeSave() { waiting?.resume(); waiting = nil }
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
