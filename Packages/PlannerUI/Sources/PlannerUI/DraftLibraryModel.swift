import Foundation
import SwiftUI
import PlannerData

/// Actor boundary permits deterministic failure/race tests without fake product data.
public protocol DraftLibraryStorage: Sendable {
    func read(id: UUID) async throws -> DraftRecord
    func history(id: UUID, limit: Int, offset: Int) async throws -> DraftPage
    func restore(id: UUID, revision: Int, expectedRevision: Int) async throws -> DraftRecord
    func list(limit: Int, offset: Int) async throws -> DraftPage
    func save(id: UUID, expectedRevision: Int?, title: String, payload: Data) async throws -> DraftRecord
    func duplicate(id: UUID, expectedRevision: Int, newID: UUID) async throws -> DraftRecord
    func delete(id: UUID, expectedRevision: Int) async throws
}
extension DraftStore: DraftLibraryStorage {}

/// UI editor bytes are intentionally separate from frozen BuildSnapshot contracts.
struct EditorPayload: Codable, Equatable {
    let editorVersion: Int
    var notes: String
    init(notes: String) { editorVersion = 1; self.notes = notes }
}

@MainActor
public final class DraftLibraryModel: ObservableObject {
    @Published public private(set) var records: [DraftRecord] = []
    @Published public private(set) var unreadableCount = 0
    @Published public private(set) var busy = false
    @Published public private(set) var notice: String?
    @Published public private(set) var selected: DraftRecord?
    @Published private var titleValue = ""
    @Published private var notesValue = ""
    public var title: String {
        get { titleValue }
        set { if !deleting { titleValue = newValue } }
    }
    public var notes: String {
        get { notesValue }
        set { if !deleting { notesValue = newValue } }
    }
    public static let pageSize = 20
    @Published public private(set) var pageOffset = 0
    @Published public private(set) var hasNextPage = false
    @Published public private(set) var revisions: [DraftRecord] = []
    @Published public private(set) var historyOffset = 0
    @Published public private(set) var hasOlderRevisions = false
    @Published public private(set) var unreadableRevisions = 0
    @Published public private(set) var status = "Saved locally"
    private var deleting = false
    private var saveRequested = false
    private var savedTitle = ""
    private var savedNotes = ""
    private let store: any DraftLibraryStorage
    public var dirty: Bool { title != savedTitle || notes != savedNotes }
    public init(store: any DraftLibraryStorage) { self.store = store }

    public func refresh() async {
        guard !busy else { return }
        busy = true
        do { try await load() } catch { report(error) }
        await finishOperation()
    }
    private func load() async throws {
        let page = try await store.list(limit: Self.pageSize, offset: pageOffset)
        records = page.records; unreadableCount = page.unreadableCount
        hasNextPage = page.records.count + page.unreadableCount == Self.pageSize
    }
    public func changePage(forward: Bool) async {
        guard !busy, !dirty, forward ? hasNextPage : pageOffset > 0 else { return }
        let previous = pageOffset
        pageOffset = max(0, pageOffset + (forward ? Self.pageSize : -Self.pageSize))
        busy = true
        do { try await load() }
        catch { pageOffset = previous; report(error) }
        await finishOperation()
    }
    public func open(_ record: DraftRecord) async { await open(id: record.id) }
    public func open(id: UUID) async {
        guard !busy, !dirty else { return }
        busy = true
        do { adopt(try await store.read(id: id)) }
        catch { report(error) }
        await finishOperation()
    }
    private func adopt(_ record: DraftRecord) {
        do {
            let payload = try editorPayload(record)
            clearHistory()
            selected = record; title = record.title; notes = payload.notes
            savedTitle = title; savedNotes = notes; status = "Saved locally"; notice = nil
        } catch {
            notice = "This draft uses an unsupported editor format. It has been preserved without changes."
        }
    }
    private func editorPayload(_ record: DraftRecord) throws -> EditorPayload {
        guard let fields = try JSONSerialization.jsonObject(with: record.payload) as? [String: Any],
              Set(fields.keys) == ["editorVersion", "notes"] else { throw DraftStoreError.invalidDraft }
        let payload = try JSONDecoder().decode(EditorPayload.self, from: record.payload)
        guard payload.editorVersion == 1 else { throw DraftStoreError.invalidDraft }
        return payload
    }
    private func clearHistory() {
        revisions = []; historyOffset = 0; hasOlderRevisions = false; unreadableRevisions = 0
    }
    /// Pages replace each other; payload-bearing history never grows without bound.
    public func loadHistory(offset: Int = 0) async {
        guard let selected, !busy, offset >= 0 else { return }
        busy = true
        do {
            let page = try await store.history(id: selected.id, limit: Self.pageSize, offset: offset)
            revisions = page.records; historyOffset = offset; unreadableRevisions = page.unreadableCount
            hasOlderRevisions = page.records.count + page.unreadableCount == Self.pageSize
        } catch { report(error) }
        await finishOperation()
    }
    /// Explicit restoration appends a revision and never carries analysis into notes.
    /// Storage enforces the selected revision as a compare-and-swap boundary.
    public func restore(_ revision: DraftRecord) async {
        guard let selected, !busy, !dirty, revision.id == selected.id,
              revision.revision < selected.revision else { return }
        let submittedTitle = title; let submittedNotes = notes
        busy = true; notice = nil
        do {
            _ = try editorPayload(revision) // Unsupported history is preserved, never promoted.
            let restored = try await store.restore(id: selected.id, revision: revision.revision,
                                                   expectedRevision: selected.revision)
            let payload = try editorPayload(restored)
            self.selected = restored
            // A binding update can arrive during the actor hop. Preserve that newer
            // input while acknowledging only the actual durable restored contents.
            if title == submittedTitle { title = restored.title }
            if notes == submittedNotes { notes = payload.notes }
            savedTitle = restored.title; savedNotes = payload.notes
            status = "Restored revision \(revision.revision) as local revision \(restored.revision)"
            clearHistory()
            do { try await load() }
            catch { notice = "The restoration was saved locally, but the library could not refresh. Try Refresh." }
        } catch { status = "Not restored"; report(error) }
        await finishOperation()
    }
    public func close() { guard !busy else { return }; clearHistory(); selected = nil; title = ""; notes = ""; savedTitle = ""; savedNotes = "" }
    public func create() async {
        guard !dirty else { return }
        await operation {
            let record = try await self.store.save(id: UUID(), expectedRevision: nil, title: "Untitled draft", payload: JSONEncoder().encode(EditorPayload(notes: "")))
            return record
        }
    }
    public func save() async {
        guard let selected, dirty else { return }
        if busy { saveRequested = true; return }
        let title = self.title; let notes = self.notes
        await operation {
            try await self.store.save(id: selected.id, expectedRevision: selected.revision, title: title, payload: JSONEncoder().encode(EditorPayload(notes: notes)))
        }
    }
    public func duplicate(_ record: DraftRecord) async {
        guard !dirty else { return }
        await operation { try await self.store.duplicate(id: record.id, expectedRevision: record.revision, newID: UUID()) }
    }
    public func delete(_ record: DraftRecord) async {
        guard !dirty, !busy else { return }
        deleting = true
        defer { deleting = false }
        await operation {
            try await self.store.delete(id: record.id, expectedRevision: record.revision)
            self.deleting = false
            if self.selected?.id == record.id {
                self.clearHistory()
                self.selected = nil; self.title = ""; self.notes = ""
                self.savedTitle = ""; self.savedNotes = ""
            }
            return nil
        }
    }
    private func operation(_ action: @MainActor () async throws -> DraftRecord?) async {
        guard !busy else { return }
        let submittedTitle = title; let submittedNotes = notes
        busy = true; status = "Saving…"; notice = nil
        do {
            let result = try await action()
            busy = false
            if let result {
                if selected?.id == result.id {
                    clearHistory()
                    selected = result
                    savedTitle = submittedTitle; savedNotes = submittedNotes
                } else if !dirty {
                    adopt(result)
                }
            }
            status = "Saved locally"
            busy = true
            do { try await load() }
            catch { notice = "The change was saved locally, but the library could not refresh. Try Refresh." }
            busy = false
        } catch { busy = false; status = "Not saved"; report(error) }
        await finishOperation()
    }

    /// Lifecycle save requests survive actor hops, including a history read or
    /// restoration. The drain snapshots the latest text and selected revision.
    private func finishOperation() async {
        busy = false
        if saveRequested {
            saveRequested = false
            await save()
        }
    }

    private func report(_ error: Error) {
        if error as? DraftStoreError == .conflict {
            notice = "A newer revision exists. Your edits are still here. Close without saving and reopen the draft to load its latest revision."
        } else {
            notice = "The operation could not finish. Your edits are still here. Check available storage and try again."
        }
    }
}
