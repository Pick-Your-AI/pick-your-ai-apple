import Foundation
import SwiftUI
import PlannerData
import PlannerTransfer

/// Local persistence wrapper only; this is not a shared wire format or evidence claim.
struct ImportedBuildRecord: Codable, Sendable {
    static let maximumLineage = 32
    let storageVersion: Int
    let snapshot: Data
    let markedSynthetic: Bool
    let sourceRevision: String?
    /// Nearest copied snapshot first. Nil denotes a legacy entry with no record.
    let lineage: [LocalForkSource]?
    init(snapshot: BuildSnapshot, markedSynthetic: Bool, sourceRevision: String?,
         lineage: [LocalForkSource]? = nil) throws {
        let bytes = try snapshot.encoded()
        // A fresh identity/timestamp can increase the byte count after ingress.
        // Revalidate the exact persisted bytes so every acknowledged fork reopens.
        _ = try BuildTransfer.snapshot(fromDraftJSON: bytes)
        storageVersion = lineage == nil ? 1 : 2; self.snapshot = bytes
        self.markedSynthetic = markedSynthetic; self.sourceRevision = sourceRevision
        self.lineage = lineage
        try validateLineage(snapshotID: snapshot.id)
    }
    func validatedSnapshot() throws -> BuildSnapshot {
        let result = try BuildTransfer.snapshot(fromDraftJSON: snapshot)
        try validateLineage(snapshotID: result.id)
        return result
    }
    private func validateLineage(snapshotID: String) throws {
        if storageVersion == 1 {
            guard lineage == nil else { throw TransferError.unsupportedVersion }
            return
        }
        guard storageVersion == 2, let lineage, !lineage.isEmpty,
              lineage.count <= Self.maximumLineage,
              Set(lineage.map(\.buildID)).count == lineage.count,
              !lineage.contains(where: { $0.buildID == snapshotID }) else {
            throw TransferError.unsupportedVersion
        }
        for source in lineage { try source.validate() }
    }
    static func decode(_ data: Data) throws -> (wrapper: Self, snapshot: BuildSnapshot) {
        let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = Set(fields?.keys.map { $0 } ?? [])
        guard keys.isSubset(of: ["storageVersion", "snapshot", "markedSynthetic", "sourceRevision", "lineage"]),
              keys.isSuperset(of: ["storageVersion", "snapshot", "markedSynthetic"]) else {
            throw TransferError.unsupportedVersion
        }
        let wrapper = try JSONDecoder().decode(Self.self, from: data)
        if wrapper.storageVersion == 1 {
            guard !keys.contains("lineage") else { throw TransferError.unsupportedVersion }
        } else {
            guard let entries = fields?["lineage"] as? [[String: Any]],
                  entries.allSatisfy({ Set($0.keys) == ["buildID", "revision", "snapshotSHA256"] }) else {
                throw TransferError.unsupportedVersion
            }
        }
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
    @Published public private(set) var lineage: [LocalForkSource]?
    @Published public private(set) var preview: ImportPreview?
    @Published public private(set) var notice: String?
    @Published public private(set) var libraryNotice: String?
    /// Set only after the exact row's deletion transaction commits.
    @Published public private(set) var lastDeletedID: UUID?
    @Published public private(set) var busy = false
    @Published public private(set) var unreadableCount = 0
    @Published public private(set) var offset = 0
    @Published public private(set) var hasNext = false
    @Published public private(set) var exportData: Data?
    private var sourceRevision: String?
    private let store: DraftStore
    private let preparation: ImportedBuildPreparation
    private var exportGeneration: UUID?
    public static let pageSize = 20
    public convenience init(store: DraftStore) { self.init(store: store, preparation: .live) }
    init(store: DraftStore, preparation: ImportedBuildPreparation) {
        self.store = store; self.preparation = preparation
    }

    /// Only the Files picker grants access. The actual read is bounded independently
    /// of advertised file size, and the security-scoped grant ends immediately.
    public func previewFile(_ url: URL) async {
        guard !busy else { return }
        busy = true; preview = nil; clearExport()
        defer { busy = false }
        let preparation = preparation
        do {
            let result = try await Self.offMain {
                // The file grant ends after the bounded read. Parsing and schema
                // validation remain on this worker, not on the returning actor.
                try preparation.preview(Self.readFile(url))
            }
            try Task.checkCancellation()
            preview = result; notice = nil
        } catch is CancellationError {
            // A cancelled caller cannot publish a preview or a stale failure.
        } catch {
            guard !Task.isCancelled else { return }
            notice = "The file could not be previewed. It may be unreadable, unsupported, oversized, or contain private fields."
        }
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
    public func preparePreview(_ data: Data) async throws {
        guard !busy else { return }
        busy = true; preview = nil; clearExport()
        defer { busy = false }
        let preparation = preparation
        do {
            let result = try await Self.offMain { try preparation.preview(data) }
            try Task.checkCancellation()
            preview = result
            notice = nil
        } catch {
            // Cancellation can also arrive while returning to this actor.
            try Task.checkCancellation()
            throw error
        }
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
            // A worker error must not skip the caller's cancellation check.
            let result = await task.result
            try Task.checkCancellation()
            return try result.get()
        }, onCancel: { task.cancel() })
    }
    nonisolated private static func prepareFork(
        _ preview: ImportPreview, markedSynthetic: Bool, sourceRevision: String?,
        priorLineage: [LocalForkSource]? = nil
    ) throws -> (snapshot: BuildSnapshot, payload: Data, lineage: [LocalForkSource]) {
        let retained = priorLineage ?? []
        guard retained.count < ImportedBuildRecord.maximumLineage else { throw LocalForkError.lineageLimit }
        let lineage = [try LocalForkSource.capture(preview.snapshot)] + retained
        let fork = try preview.fork(localOwner: "local." + UUID().uuidString.lowercased(),
                                    timestamp: ISO8601DateFormatter().string(from: Date()))
        let wrapper = try ImportedBuildRecord(snapshot: fork, markedSynthetic: markedSynthetic,
                                              sourceRevision: sourceRevision, lineage: lineage)
        return (fork, try JSONEncoder().encode(wrapper), lineage)
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
                  sourceRevision: preview.sourceRevision, lineage: prepared.lineage)
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
                  sourceRevision: decoded.wrapper.sourceRevision, lineage: decoded.wrapper.lineage)
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
                      sourceRevision: prior.wrapper.sourceRevision, lineage: prior.wrapper.lineage)
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
                                            sourceRevision: prior.wrapper.sourceRevision,
                                            priorLineage: prior.wrapper.lineage)
            }
            let row = try await store.duplicate(id: record.id, expectedRevision: record.revision,
                                               title: prior.row.title, payload: prepared.payload)
            adopt(row, snapshot: prepared.snapshot, markedSynthetic: prior.wrapper.markedSynthetic,
                  sourceRevision: prior.wrapper.sourceRevision, lineage: prepared.lineage)
            await reloadAfterMutation("The duplicate local fork was saved.", offset: 0)
        } catch LocalForkError.lineageLimit {
            notice = "This entry already records 32 copied snapshots. It cannot be duplicated without losing lineage. The source was preserved."
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
            lastDeletedID = record.id
            if selected?.id == record.id {
                selected = nil; snapshot = nil; markedSynthetic = false; sourceRevision = nil; lineage = nil; clearExport()
            }
            notice = nil
            await reloadAfterMutation("The selected local entry was deleted.", offset: offset)
        } catch { notice = "The selected revision could not be deleted. Reopen the entry and retry; existing records were preserved." }
    }
    private func adopt(_ record: DraftRecord, snapshot: BuildSnapshot, markedSynthetic: Bool,
                       sourceRevision: String?, lineage: [LocalForkSource]?) {
        selected = record; self.snapshot = snapshot; self.markedSynthetic = markedSynthetic; self.sourceRevision = sourceRevision
        self.lineage = lineage
        clearExport(); notice = nil
    }
    /// Capture intent before a queued Task can observe a different alias or row.
    /// The returned operation permits cancellation/acknowledgement; it never
    /// authorizes sharing, which still requires review of the resulting bytes.
    @discardableResult
    public func prepareExport(publicAlias: String) -> Task<Void, Never>? {
        guard !busy, let snapshot, let selected else { return nil }
        clearExport()
        let generation = UUID()
        exportGeneration = generation
        let request = ImportedBuildPreparation.ExportRequest(snapshot: snapshot, publicAlias: publicAlias,
            markedSynthetic: markedSynthetic, sourceRevision: sourceRevision)
        let preparation = preparation
        busy = true
        return Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.exportGeneration == generation { self.exportGeneration = nil }
                self.busy = false
            }
            guard !Task.isCancelled, self.currentExport(generation, selected: selected) else { return }
            do {
                let data = try await Self.offMain { try preparation.export(request) }
                try Task.checkCancellation()
                guard self.currentExport(generation, selected: selected) else { return }
                self.exportData = data; self.notice = nil
            } catch is CancellationError {
                // Cancellation retains the fork without making bytes shareable.
            } catch {
                guard !Task.isCancelled, self.currentExport(generation, selected: selected) else { return }
                self.notice = "Export could not be prepared. Supply a public alias and remove unsupported or private content."
            }
        }
    }
    private func currentExport(_ generation: UUID, selected: DraftRecord) -> Bool {
        exportGeneration == generation && self.selected?.id == selected.id
            && self.selected?.revision == selected.revision
    }
    /// An alias change also invalidates preparation that has not returned yet.
    public func clearExport() { exportGeneration = nil; exportData = nil }
    public func reportFileFailure() { notice = "The file operation did not finish. Existing local builds were preserved." }
}
