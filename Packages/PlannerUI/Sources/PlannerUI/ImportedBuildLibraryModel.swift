import Foundation
import SwiftUI
import PlannerData
import PlannerTransfer

/// Local persistence wrapper only; this is not a shared wire format or evidence claim.
struct ImportedBuildRecord: Codable, Sendable {
    let storageVersion: Int
    let snapshot: Data
    let markedSynthetic: Bool
    let sourceRevision: String?
    init(snapshot: BuildSnapshot, markedSynthetic: Bool, sourceRevision: String?) throws {
        let bytes = try snapshot.encoded()
        // A fresh identity/timestamp can increase the byte count after ingress.
        // Revalidate the exact persisted bytes so every acknowledged fork reopens.
        _ = try BuildTransfer.snapshot(fromDraftJSON: bytes)
        storageVersion = 1; self.snapshot = bytes
        self.markedSynthetic = markedSynthetic; self.sourceRevision = sourceRevision
    }
    func validatedSnapshot() throws -> BuildSnapshot {
        guard storageVersion == 1 else { throw TransferError.unsupportedVersion }
        return try BuildTransfer.snapshot(fromDraftJSON: snapshot)
    }
    static func decode(_ data: Data) throws -> (wrapper: Self, snapshot: BuildSnapshot) {
        let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = Set(fields?.keys.map { $0 } ?? [])
        guard keys.isSubset(of: ["storageVersion", "snapshot", "markedSynthetic", "sourceRevision"]),
              keys.isSuperset(of: ["storageVersion", "snapshot", "markedSynthetic"]) else {
            throw TransferError.unsupportedVersion
        }
        let wrapper = try JSONDecoder().decode(Self.self, from: data)
        if let revision = wrapper.sourceRevision {
            guard revision.range(of: #"\A[0-9a-f]{40}\z"#, options: .regularExpression) != nil else {
                throw TransferError.unsupportedVersion
            }
        }
        guard !wrapper.markedSynthetic || wrapper.sourceRevision != nil else {
            throw TransferError.unsupportedVersion
        }
        return (wrapper, try wrapper.validatedSnapshot())
    }
}

@MainActor
public final class ImportedBuildLibraryModel: ObservableObject {
    @Published public private(set) var records: [DraftRecord] = []
    @Published public private(set) var selected: DraftRecord?
    @Published public private(set) var snapshot: BuildSnapshot?
    @Published public private(set) var markedSynthetic = false
    @Published public private(set) var preview: ImportPreview?
    @Published public private(set) var notice: String?
    @Published public private(set) var libraryNotice: String?
    @Published public private(set) var busy = false
    @Published public private(set) var unreadableCount = 0
    @Published public private(set) var offset = 0
    @Published public private(set) var hasNext = false
    @Published public private(set) var exportData: Data?
    private var sourceRevision: String?
    private let store: DraftStore
    public static let pageSize = 20
    public init(store: DraftStore) { self.store = store }

    /// Only the Files picker grants access. The actual read is bounded independently
    /// of advertised file size, and the security-scoped grant ends immediately.
    public func previewFile(_ url: URL) async {
        guard !busy else { return }
        busy = true; preview = nil; exportData = nil
        defer { busy = false }
        let reading = Task.detached(priority: .userInitiated) { try Self.readFile(url) }
        do {
            let bytes = try await withTaskCancellationHandler(operation: { try await reading.value },
                                                               onCancel: { reading.cancel() })
            try Task.checkCancellation()
            preview = try BuildTransfer.preview(bytes); notice = nil
        } catch { notice = "The file could not be previewed. It may be unreadable, unsupported, oversized, or contain private fields." }
    }
    nonisolated private static func readFile(_ url: URL) throws -> Data {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw TransferError.malformed
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytes = Data()
        while bytes.count <= BuildTransfer.maximumBytes {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: min(65_536, BuildTransfer.maximumBytes + 1 - bytes.count)) ?? Data()
            if chunk.isEmpty { break }
            bytes.append(chunk)
        }
        guard bytes.count <= BuildTransfer.maximumBytes else { throw TransferError.oversized }
        return bytes
    }
    public func preparePreview(_ data: Data) throws {
        guard !busy else { return }
        preview = nil; exportData = nil
        preview = try BuildTransfer.preview(data)
        notice = nil
    }
    public func cancelPreview() { if !busy { preview = nil } }
    public func refresh(offset: Int = 0) async {
        guard !busy, offset >= 0 else { return }
        busy = true
        defer { busy = false }
        do { try await load(offset: offset) }
        catch { libraryNotice = "The imported-build library could not be read. Existing files were preserved. Refresh to retry." }
    }
    private func load(offset: Int) async throws {
        let page = try await store.list(limit: Self.pageSize, offset: offset)
        let readable = try await Self.offMain {
            var records: [DraftRecord] = []
            var unreadable = page.unreadableCount
            for record in page.records {
                try Task.checkCancellation()
                do { _ = try ImportedBuildRecord.decode(record.payload); records.append(record) }
                catch { unreadable += 1 }
            }
            return (records: records, unreadable: unreadable)
        }
        records = readable.records; unreadableCount = readable.unreadable; self.offset = offset
        // Offset and next-page state count the original rows, including preserved
        // unsupported wrappers, so an unreadable page cannot hide later good data.
        hasNext = page.records.count + page.unreadableCount == Self.pageSize
        libraryNotice = nil
    }
    nonisolated private static func offMain<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try operation()
        }
        return try await withTaskCancellationHandler(operation: {
            let value = try await task.value
            try Task.checkCancellation()
            return value
        }, onCancel: { task.cancel() })
    }
    nonisolated private static func prepareFork(
        _ preview: ImportPreview, markedSynthetic: Bool, sourceRevision: String?
    ) throws -> (snapshot: BuildSnapshot, payload: Data) {
        let fork = try preview.fork(localOwner: "local." + UUID().uuidString.lowercased(),
                                    timestamp: ISO8601DateFormatter().string(from: Date()))
        let wrapper = try ImportedBuildRecord(snapshot: fork, markedSynthetic: markedSynthetic,
                                              sourceRevision: sourceRevision)
        return (fork, try JSONEncoder().encode(wrapper))
    }
    private func current(_ record: DraftRecord) async throws -> (row: DraftRecord, wrapper: ImportedBuildRecord, snapshot: BuildSnapshot) {
        let fresh = try await store.read(id: record.id)
        guard fresh.revision == record.revision else { throw DraftStoreError.conflict }
        let decoded = try await Self.offMain { try ImportedBuildRecord.decode(fresh.payload) }
        return (fresh, decoded.wrapper, decoded.snapshot)
    }
    private func reloadAfterMutation(_ acknowledgement: String, offset: Int) async {
        do { try await load(offset: offset) }
        catch { libraryNotice = acknowledgement + " The library could not refresh; refresh to retry." }
    }
    /// Every confirmation creates a new wire ID and a separate local row. Source IDs
    /// and claimed owner references never become update/authorization targets.
    public func confirmImport() async {
        guard !busy, let preview else { return }
        busy = true
        defer { busy = false }
        do {
            let prepared = try await Self.offMain {
                try Self.prepareFork(preview, markedSynthetic: preview.usesSyntheticData == true,
                                     sourceRevision: preview.sourceRevision)
            }
            let row = try await store.save(id: UUID(), expectedRevision: nil, title: prepared.snapshot.name,
                                           payload: prepared.payload)
            self.preview = nil
            adopt(row, snapshot: prepared.snapshot, markedSynthetic: preview.usesSyntheticData == true,
                  sourceRevision: preview.sourceRevision)
            await reloadAfterMutation("The new local fork was saved.", offset: 0)
        } catch { notice = "The local fork could not be saved. No source build was updated. You can retry." }
    }
    public func open(_ record: DraftRecord) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let fresh = try await store.read(id: record.id)
            let decoded = try await Self.offMain { try ImportedBuildRecord.decode(fresh.payload) }
            adopt(fresh, snapshot: decoded.snapshot, markedSynthetic: decoded.wrapper.markedSynthetic,
                  sourceRevision: decoded.wrapper.sourceRevision)
        } catch { notice = "This imported build could not be opened. Its stored bytes were preserved." }
    }
    /// A local label is revisioned library metadata; immutable wire bytes stay pinned.
    public func rename(_ record: DraftRecord, to title: String) async {
        guard !busy else { return }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice = "Enter a nonempty local label."; return
        }
        busy = true
        defer { busy = false }
        do {
            let prior = try await current(record)
            let row = try await store.rename(id: record.id, expectedRevision: record.revision, title: title)
            if selected?.id == record.id {
                adopt(row, snapshot: prior.snapshot, markedSynthetic: prior.wrapper.markedSynthetic,
                      sourceRevision: prior.wrapper.sourceRevision)
            } else { notice = nil }
            await reloadAfterMutation("The local label was saved.", offset: offset)
        } catch { notice = "The local label could not be saved. Reopen the entry and retry; existing revisions were preserved." }
    }
    /// Duplicate the explicitly chosen revision as a new fork, never as an update
    /// to a supplied source identity or a byte copy that reuses its wire build ID.
    public func duplicate(_ record: DraftRecord) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let prior = try await current(record)
            let prepared = try await Self.offMain {
                let preview = try BuildTransfer.preview(prior.wrapper.snapshot)
                return try Self.prepareFork(preview, markedSynthetic: prior.wrapper.markedSynthetic,
                                            sourceRevision: prior.wrapper.sourceRevision)
            }
            let row = try await store.duplicate(id: record.id, expectedRevision: record.revision,
                                               title: prior.row.title, payload: prepared.payload)
            adopt(row, snapshot: prepared.snapshot, markedSynthetic: prior.wrapper.markedSynthetic,
                  sourceRevision: prior.wrapper.sourceRevision)
            await reloadAfterMutation("The duplicate local fork was saved.", offset: 0)
        } catch { notice = "The selected revision could not be duplicated. Reopen the entry and retry; the source was preserved." }
    }
    /// Confirmation carries the exact row/revision, even if another row is selected.
    public func delete(_ record: DraftRecord) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await current(record)
            try await store.delete(id: record.id, expectedRevision: record.revision)
            if selected?.id == record.id {
                selected = nil; snapshot = nil; markedSynthetic = false; sourceRevision = nil; exportData = nil
            }
            notice = nil
            await reloadAfterMutation("The selected local entry was deleted.", offset: offset)
        } catch { notice = "The selected revision could not be deleted. Reopen the entry and retry; existing records were preserved." }
    }
    private func adopt(_ record: DraftRecord, snapshot: BuildSnapshot, markedSynthetic: Bool, sourceRevision: String?) {
        selected = record; self.snapshot = snapshot; self.markedSynthetic = markedSynthetic; self.sourceRevision = sourceRevision
        exportData = nil; notice = nil
    }
    public func prepareExport(publicAlias: String) {
        exportData = nil
        guard !busy, let snapshot else { return }
        do {
            var data = try BuildTransfer.export(snapshot, publicOwnerAlias: publicAlias)
            if markedSynthetic {
                guard let sourceRevision else { throw TransferError.unsupportedVersion }
                let projected = try BuildTransfer.snapshot(fromDraftJSON: data)
                let envelope = JSONValue.object([
                    "format": .string("pickyour.ai/build-export"), "formatVersion": .number(1),
                    "exportedAt": .string(ISO8601DateFormatter().string(from: Date())),
                    "contract": .object(["version": .string("1.0.0"), "sourceSha": .string(sourceRevision)]),
                    "dataMode": .string("fixture"), "build": projected.value
                ])
                data = try JSONEncoder().encode(envelope)
                // Revalidate the final envelope and its total byte bound too.
                _ = try BuildTransfer.preview(data)
            }
            exportData = data; notice = nil
        }
        catch { notice = "Export could not be prepared. Supply a public alias and remove unsupported or private content." }
    }
    public func clearExport() { exportData = nil }
    public func reportFileFailure() { notice = "The file operation did not finish. Existing local builds were preserved." }
}
