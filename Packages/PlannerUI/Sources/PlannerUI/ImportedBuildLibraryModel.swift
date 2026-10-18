import Foundation
import SwiftUI
import PlannerData
import PlannerTransfer

/// Local persistence wrapper only; this is not a shared wire format or evidence claim.
struct ImportedBuildRecord: Codable {
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
}

@MainActor
public final class ImportedBuildLibraryModel: ObservableObject {
    @Published public private(set) var records: [DraftRecord] = []
    @Published public private(set) var selected: DraftRecord?
    @Published public private(set) var snapshot: BuildSnapshot?
    @Published public private(set) var markedSynthetic = false
    @Published public private(set) var preview: ImportPreview?
    @Published public private(set) var notice: String?
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
        catch { notice = "The imported-build library could not be read. Existing files were preserved." }
    }
    private func load(offset: Int) async throws {
        let page = try await store.list(limit: Self.pageSize, offset: offset)
        records = page.records; unreadableCount = page.unreadableCount; self.offset = offset
        hasNext = page.records.count + page.unreadableCount == Self.pageSize
    }
    /// Every confirmation creates a new wire ID and a separate local row. Source IDs
    /// and claimed owner references never become update/authorization targets.
    public func confirmImport() async {
        guard !busy, let preview else { return }
        busy = true
        defer { busy = false }
        do {
            let fork = try preview.fork(localOwner: "local." + UUID().uuidString.lowercased(),
                                        timestamp: ISO8601DateFormatter().string(from: Date()))
            let wrapper = try ImportedBuildRecord(snapshot: fork, markedSynthetic: preview.usesSyntheticData == true, sourceRevision: preview.sourceRevision)
            let row = try await store.save(id: UUID(), expectedRevision: nil, title: fork.name,
                                           payload: JSONEncoder().encode(wrapper))
            self.preview = nil
            adopt(row, snapshot: fork, markedSynthetic: wrapper.markedSynthetic, sourceRevision: wrapper.sourceRevision)
            do { try await load(offset: 0) }
            catch { notice = "The new local fork was saved, but the library could not refresh." }
        } catch { notice = "The local fork could not be saved. No source build was updated. You can retry." }
    }
    public func open(_ record: DraftRecord) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let fresh = try await store.read(id: record.id)
            let fields = try JSONSerialization.jsonObject(with: fresh.payload) as? [String: Any]
            let keys = Set(fields?.keys.map { $0 } ?? [])
            guard keys.isSubset(of: ["storageVersion", "snapshot", "markedSynthetic", "sourceRevision"]),
                  keys.isSuperset(of: ["storageVersion", "snapshot", "markedSynthetic"]) else {
                throw TransferError.unsupportedVersion
            }
            let wrapper = try JSONDecoder().decode(ImportedBuildRecord.self, from: fresh.payload)
            adopt(fresh, snapshot: try wrapper.validatedSnapshot(), markedSynthetic: wrapper.markedSynthetic, sourceRevision: wrapper.sourceRevision)
        } catch { notice = "This imported build could not be opened. Its stored bytes were preserved." }
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
