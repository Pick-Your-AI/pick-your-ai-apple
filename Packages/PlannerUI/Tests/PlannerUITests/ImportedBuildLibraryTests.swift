import Foundation
import XCTest
import PlannerData
import PlannerTransfer
@testable import PlannerUI

// Blocking belongs only to the synchronous preparation worker. A broken move
// back to MainActor releases after five seconds and fails rather than deadlocking.
private final class BlockedBuildPreparation: @unchecked Sendable {
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
    @discardableResult
    func pauseFirst() -> Int {
        lock.lock()
        calls += 1
        let call = calls
        offMain = offMain && !Thread.isMainThread
        lock.unlock()
        if call == 1 {
            entered.signal()
            let result = released.wait(timeout: .now() + 5)
            lock.lock(); timedOut = result == .timedOut; lock.unlock()
        }
        return call
    }
    func waitUntilEntered() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.entered.wait(timeout: .now() + 5) == .success)
            }
        }
    }
    func release() { released.signal() }
}

@MainActor
final class ImportedBuildLibraryTests: XCTestCase {
    private func fixture() throws -> Data {
        let source = try Data(contentsOf: Bundle.module.url(forResource: "build", withExtension: "json")!)
        let snapshot = try BuildTransfer.snapshot(fromDraftJSON: source)
        guard case .object(var build) = snapshot.value, case .array(let selections)? = build["selections"] else {
            throw TransferError.malformed
        }
        build["selections"] = .array(selections.map { value in
            guard case .object(var selection) = value, case .object(var settings)? = selection["settings"] else { return value }
            settings.removeValue(forKey: "index_name")
            selection["settings"] = .object(settings)
            return .object(selection)
        })
        let clean = try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(build)))
        return try BuildTransfer.export(clean, publicOwnerAlias: "fixture.public")
    }
    private func setup(preparation: ImportedBuildPreparation = .live) throws -> (DraftStore, ImportedBuildLibraryModel, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        return (store, ImportedBuildLibraryModel(store: store, preparation: preparation), folder)
    }
    private func recordID(_ index: Int) -> UUID {
        let tail = String(index, radix: 16)
        return UUID(uuidString: "00000000-0000-0000-0000-" + String(repeating: "0", count: 12 - tail.count) + tail)!
    }
    private func storedPayload() throws -> Data {
        let snapshot = try BuildTransfer.preview(fixture()).snapshot
        return try JSONEncoder().encode(ImportedBuildRecord(snapshot: snapshot, markedSynthetic: false, sourceRevision: nil))
    }
    private func selectedFixture(_ model: ImportedBuildLibraryModel, store: DraftStore,
                                 synthetic: Bool = false) async throws -> (DraftRecord, BuildSnapshot) {
        let snapshot = try BuildTransfer.preview(fixture()).snapshot
        let wrapper = try ImportedBuildRecord(snapshot: snapshot, markedSynthetic: synthetic,
            sourceRevision: synthetic ? String(repeating: "e", count: 40) : nil)
        let record = try await store.save(id: UUID(), expectedRevision: nil, title: "Preparation control",
                                         payload: JSONEncoder().encode(wrapper))
        await model.open(record)
        XCTAssertEqual(model.selected, record)
        XCTAssertEqual(model.snapshot, snapshot)
        return (record, snapshot)
    }
    private func notesEditor(in folder: URL) async throws -> DraftLibraryModel {
        let editor = DraftLibraryModel(store: try DraftStore(url: folder.appendingPathComponent("notes.sqlite")))
        await editor.create()
        XCTAssertNotNil(editor.selected)
        return editor
    }
    private func assertResponsiveEditor(_ editor: DraftLibraryModel, probe: BlockedBuildPreparation) {
        editor.notes = "A main-actor edit completed before preparation was released"
        XCTAssertEqual(editor.notes, "A main-actor edit completed before preparation was released")
        XCTAssertFalse(probe.observations.timedOut)
        XCTAssertTrue(probe.observations.offMain)
        // Discard only this test-owned amendment before any production debounce
        // can start; this separate editor is the responsiveness witness.
        editor.close()
    }
    private func assertUnchanged(_ record: DraftRecord, in folder: URL) async throws {
        let reopened = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let durable = try await reopened.read(id: record.id)
        let history = try await reopened.history(id: record.id)
        let page = try await reopened.list()
        XCTAssertEqual(durable, record)
        XCTAssertEqual(history.records, [record])
        XCTAssertEqual(page.records, [record])
    }
    private func comparisonFixtures(in store: DraftStore) async throws -> [(row: DraftRecord, snapshot: BuildSnapshot)] {
        let preview = try BuildTransfer.preview(fixture())
        var fixtures: [(row: DraftRecord, snapshot: BuildSnapshot)] = []
        for index in 0..<3 {
            let fork = try preview.fork(localOwner: "local.comparison.\(index)", timestamp: "2026-10-18T00:00:00Z")
            guard case .object(var fields) = fork.value,
                  case .object(var objectives)? = fields["objectives"] else { throw TransferError.malformed }
            fields["name"] = .string("Comparison fixture \(index)")
            objectives["requests_per_day"] = .number(Decimal((index + 1) * 1000))
            fields["objectives"] = .object(objectives)
            let snapshot = try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(fields)))
            let wrapper = try ImportedBuildRecord(snapshot: snapshot, markedSynthetic: index == 1,
                sourceRevision: index == 1 ? String(repeating: "e", count: 40) : nil)
            let row = try await store.save(id: UUID(), expectedRevision: nil, title: snapshot.name,
                                           payload: JSONEncoder().encode(wrapper))
            fixtures.append((row, snapshot))
        }
        return fixtures
    }
    private func comparisonPreparation(_ probe: BlockedBuildPreparation, failFirst: Bool = false) -> ImportedBuildPreparation {
        ImportedBuildPreparation(preview: ImportedBuildPreparation.live.preview, export: ImportedBuildPreparation.live.export,
            compare: { before, after in
                let call = probe.pauseFirst()
                if call == 1, failFirst { throw BuildComparisonError.tooManyDifferences }
                return try BuildComparison.compare(before, after)
            })
    }
    private func pinFirstAndSelectSecond(_ model: ImportedBuildLibraryModel,
                                        fixtures: [(row: DraftRecord, snapshot: BuildSnapshot)]) async {
        await model.open(fixtures[0].row)
        model.pinComparisonBaseline()
        await model.open(fixtures[1].row)
        XCTAssertEqual(model.comparisonBaseline, fixtures[0].snapshot)
        XCTAssertEqual(model.snapshot, fixtures[1].snapshot)
    }
    private func assertComparisonRowsUnchanged(_ rows: [DraftRecord], in folder: URL) async throws {
        let reopened = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let page = try await reopened.list()
        XCTAssertEqual(Set(page.records.map(\.id)), Set(rows.map(\.id)))
        for row in rows {
            let durable = try await reopened.read(id: row.id), history = try await reopened.history(id: row.id)
            XCTAssertEqual(durable, row)
            XCTAssertEqual(history.records, [row])
        }
    }
    func testPreviewAndCancelNeverWriteStorage() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await model.preparePreview(fixture())
        XCTAssertNotNil(model.preview)
        let before = try await store.list()
        XCTAssertTrue(before.records.isEmpty)
        model.cancelPreview()
        await model.confirmImport()
        let after = try await store.list()
        XCTAssertTrue(after.records.isEmpty)
    }
    func testConfirmedForksNeverReuseSourceOrLocalIdentity() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = try fixture()
        let source = try BuildTransfer.preview(bytes).snapshot
        try await model.preparePreview(bytes); await model.confirmImport()
        let first = try XCTUnwrap(model.snapshot)
        let row = try XCTUnwrap(model.selected)
        XCTAssertNotEqual(first.id, source.id)
        XCTAssertEqual(first.locks, source.locks)
        XCTAssertEqual(row.revision, 1)
        try await model.preparePreview(bytes); await model.confirmImport()
        XCTAssertNotEqual(model.snapshot?.id, first.id)
        XCTAssertNotEqual(model.selected?.id, row.id)
        let page = try await store.list()
        XCTAssertEqual(page.records.count, 2)
        let secondConnection = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let reopened = ImportedBuildLibraryModel(store: secondConnection)
        await reopened.open(row)
        XCTAssertEqual(reopened.snapshot, first)
        XCTAssertFalse(reopened.markedSynthetic) // Bare input is unknown, not production evidence.
    }
    func testSyntheticLabelSurvivesPersistenceAndExportEnvelope() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshot = try BuildTransfer.preview(fixture()).snapshot
        let sha = String(repeating: "a", count: 40) // Untrusted synthetic metadata, never an authority.
        let envelope = JSONValue.object([
            "format": .string("pickyour.ai/build-export"), "formatVersion": .number(1),
            "exportedAt": .string("2026-10-18T00:00:00Z"),
            "contract": .object(["version": .string("1.0.0"), "sourceSha": .string(sha)]),
            "dataMode": .string("fixture"), "build": snapshot.value
        ])
        try await model.preparePreview(JSONEncoder().encode(envelope)); await model.confirmImport()
        let row = try XCTUnwrap(model.selected)
        let secondConnection = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let reopened = ImportedBuildLibraryModel(store: secondConnection)
        await reopened.open(row)
        XCTAssertTrue(reopened.markedSynthetic)
        await reopened.prepareExport(publicAlias: "public.alias")?.value
        let exported = try BuildTransfer.preview(XCTUnwrap(reopened.exportData))
        XCTAssertEqual(exported.usesSyntheticData, true)
        XCTAssertEqual(exported.sourceRevision, sha)
        XCTAssertEqual(exported.snapshot.locks, snapshot.locks)
    }
    func testExportRequiresAliasAndDoesNotExposeLocalOwner() async throws {
        let (_, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await model.preparePreview(fixture()); await model.confirmImport()
        await model.prepareExport(publicAlias: "")?.value
        XCTAssertNil(model.exportData)
        await model.prepareExport(publicAlias: "reviewed.alias")?.value
        let exported = try BuildTransfer.preview(XCTUnwrap(model.exportData)).snapshot
        guard case .object(let fields) = exported.value else { return XCTFail("Missing build") }
        XCTAssertEqual(fields["owner_ref"], .string("reviewed.alias"))
        XCTAssertNil(fields["notes"])
        XCTAssertNil(fields["extensions"])
        XCTAssertEqual(exported.locks, model.snapshot?.locks)
        model.clearExport()
        XCTAssertNil(model.exportData)
    }
    func testInvalidAndOversizedFilesCannotCreateRows() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await model.preparePreview(fixture())
        do {
            try await model.preparePreview(Data("{}".utf8))
            XCTFail("Malformed input must fail the same frozen validator")
        } catch { XCTAssertNil(model.preview) }
        XCTAssertNil(model.preview)
        let file = folder.appendingPathComponent("oversized.json")
        var data = try fixture()
        data.append(Data(repeating: 32, count: BuildTransfer.maximumBytes))
        try data.write(to: file)
        await model.previewFile(file)
        XCTAssertNil(model.preview)
        XCTAssertNotNil(model.notice)
        await model.previewFile(folder)
        XCTAssertNil(model.preview)
        await model.confirmImport()
        let page = try await store.list()
        XCTAssertTrue(page.records.isEmpty)
    }
    func testValidLocalFileCanBePreviewedWithoutImport() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("build.json")
        try fixture().write(to: file)
        await model.previewFile(file)
        XCTAssertNotNil(model.preview)
        let page = try await store.list()
        XCTAssertTrue(page.records.isEmpty)
    }
    func testUnsupportedStoredFormatIsPreserved() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Data("{\"storageVersion\":2,\"future\":true}".utf8)
        let row = try await store.save(id: UUID(), expectedRevision: nil, title: "Future", payload: bytes)
        await model.open(row)
        XCTAssertNil(model.snapshot)
        XCTAssertNotNil(model.notice)
        let unchanged = try await store.read(id: row.id)
        XCTAssertEqual(unchanged.payload, bytes)
    }
    func testLocalRenamePreservesSnapshotAndHistoryAcrossRestart() async throws {
        let (_, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await model.preparePreview(fixture()); await model.confirmImport()
        let original = try XCTUnwrap(model.selected)
        let snapshot = try XCTUnwrap(model.snapshot)
        await model.prepareExport(publicAlias: "reviewed.public")?.value
        XCTAssertNotNil(model.exportData)

        await model.rename(original, to: "My local label")
        let renamed = try XCTUnwrap(model.selected)
        XCTAssertEqual(renamed.id, original.id)
        XCTAssertEqual(renamed.revision, 2)
        XCTAssertEqual(renamed.title, "My local label")
        XCTAssertEqual(renamed.payload, original.payload)
        XCTAssertEqual(model.snapshot, snapshot)
        XCTAssertNil(model.exportData)
        XCTAssertNil(model.notice)
        XCTAssertFalse(renamed.analysisIsCurrent)

        let reopenedStore = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let reopened = ImportedBuildLibraryModel(store: reopenedStore)
        await reopened.open(original) // An older list row opens the current stored revision.
        XCTAssertEqual(reopened.selected, renamed)
        XCTAssertEqual(reopened.snapshot, snapshot)
        let history = try await reopenedStore.history(id: original.id)
        XCTAssertEqual(history.records, [renamed, original])
    }
    func testDuplicateCreatesFreshForkAndRetainsSyntheticQualificationAndLocks() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try BuildTransfer.preview(fixture()).snapshot
        let sha = String(repeating: "b", count: 40)
        let envelope = JSONValue.object([
            "format": .string("pickyour.ai/build-export"), "formatVersion": .number(1),
            "exportedAt": .string("2026-10-18T00:00:00Z"),
            "contract": .object(["version": .string("1.0.0"), "sourceSha": .string(sha)]),
            "dataMode": .string("fixture"), "build": source.value
        ])
        try await model.preparePreview(JSONEncoder().encode(envelope)); await model.confirmImport()
        let imported = try XCTUnwrap(model.selected)
        await model.rename(imported, to: "Organized locally")
        let original = try XCTUnwrap(model.selected)
        let originalSnapshot = try XCTUnwrap(model.snapshot)
        await model.duplicate(original)
        let duplicate = try XCTUnwrap(model.selected)
        let duplicateSnapshot = try XCTUnwrap(model.snapshot)
        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertNotEqual(duplicateSnapshot.id, originalSnapshot.id)
        XCTAssertEqual(duplicate.revision, 1)
        XCTAssertEqual(duplicate.title, original.title)
        XCTAssertEqual(duplicateSnapshot.locks, originalSnapshot.locks)
        XCTAssertTrue(model.markedSynthetic)
        XCTAssertFalse(duplicate.analysisIsCurrent)
        let retained = try await store.read(id: original.id)
        XCTAssertEqual(retained, original)

        let reopened = ImportedBuildLibraryModel(store: try DraftStore(url: folder.appendingPathComponent("imports.sqlite")))
        await reopened.open(duplicate)
        XCTAssertEqual(reopened.snapshot, duplicateSnapshot)
        XCTAssertTrue(reopened.markedSynthetic)
        await reopened.prepareExport(publicAlias: "reviewed.public")?.value
        let exported = try BuildTransfer.preview(XCTUnwrap(reopened.exportData))
        XCTAssertEqual(exported.usesSyntheticData, true)
        XCTAssertEqual(exported.sourceRevision, sha)
        XCTAssertEqual(exported.snapshot.locks, source.locks)
    }
    func testStaleRenameDuplicateAndDeleteCannotMutateNewerRevision() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await model.preparePreview(fixture()); await model.confirmImport()
        let stale = try XCTUnwrap(model.selected)
        let newer = try await store.rename(id: stale.id, expectedRevision: stale.revision, title: "Newer label")
        await model.rename(stale, to: "Stale rename")
        XCTAssertNotNil(model.notice)
        await model.duplicate(stale)
        XCTAssertNotNil(model.notice)
        await model.delete(stale)
        XCTAssertNotNil(model.notice)
        let retained = try await store.read(id: stale.id)
        XCTAssertEqual(retained, newer)
        let page = try await store.list()
        XCTAssertEqual(page.records, [newer])
        XCTAssertNil(model.lastDeletedID, "A rejected deletion must not invalidate a pinned baseline.")
        let failure = model.notice
        await model.refresh()
        XCTAssertEqual(model.notice, failure, "A healthy page refresh does not erase an unresolved mutation failure.")
        await model.open(newer)
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.selected, newer)
    }
    func testConfirmedDeleteTargetsCapturedEntryAndPreservesDifferentSelection() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await model.preparePreview(fixture()); await model.confirmImport()
        let pendingDelete = try XCTUnwrap(model.selected)
        await model.duplicate(pendingDelete)
        let selected = try XCTUnwrap(model.selected)
        let selectedSnapshot = model.snapshot
        await model.prepareExport(publicAlias: "reviewed.public")?.value
        let export = try XCTUnwrap(model.exportData)
        await model.delete(pendingDelete)
        XCTAssertEqual(model.lastDeletedID, pendingDelete.id, "Only the committed target can invalidate its baseline.")
        XCTAssertEqual(model.selected, selected)
        XCTAssertEqual(model.snapshot, selectedSnapshot)
        XCTAssertEqual(model.exportData, export)
        let page = try await store.list()
        XCTAssertEqual(page.records, [selected])
        await model.delete(selected)
        XCTAssertEqual(model.lastDeletedID, selected.id)
        XCTAssertNil(model.selected)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.exportData)
        XCTAssertTrue(model.records.isEmpty)
        let restarted = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let empty = try await restarted.list()
        XCTAssertTrue(empty.records.isEmpty)
    }
    func testLargeLibraryRetainsCorruptWrapperAndUnrelatedMetadataAfterRenameDeleteAndRestart() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let goodPayload = try storedPayload()
        let corruptPayload = Data("{\"storageVersion\":2,\"future\":true}".utf8)
        let corrupt = try await store.save(id: recordID(0), expectedRevision: nil, title: "Unreadable", payload: corruptPayload)
        var expected: [UUID: DraftRecord] = [:]
        for index in 1...502 {
            let row = try await store.save(id: recordID(index), expectedRevision: nil, title: "Entry \(index)", payload: goodPayload)
            expected[row.id] = row
        }
        let neighbor = try await store.rename(id: recordID(3), expectedRevision: 1, title: "Neighbor with history")
        expected[neighbor.id] = neighbor
        let neighborHistory = try await store.history(id: neighbor.id)
        await model.refresh()
        XCTAssertEqual(model.unreadableCount, 1)
        XCTAssertEqual(model.records.count, 19)
        XCTAssertTrue(model.hasNext)
        let renameTarget = try XCTUnwrap(expected[recordID(1)])
        await model.open(renameTarget)
        await model.rename(renameTarget, to: "Renamed beside corruption")
        let renamed = try XCTUnwrap(model.selected)
        XCTAssertEqual(renamed.title, "Renamed beside corruption")
        XCTAssertEqual(renamed.revision, 2)
        XCTAssertEqual(renamed.payload, goodPayload)
        XCTAssertNil(model.notice)
        expected[renameTarget.id] = renamed
        let deleteTarget = try XCTUnwrap(expected[recordID(2)])
        await model.delete(deleteTarget)
        expected.removeValue(forKey: deleteTarget.id)

        let reopenedStore = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let reopened = ImportedBuildLibraryModel(store: reopenedStore)
        var recovered: [UUID: DraftRecord] = [:]
        var unreadable = 0
        for page in 0..<30 {
            await reopened.refresh(offset: page * ImportedBuildLibraryModel.pageSize)
            XCTAssertNil(reopened.libraryNotice)
            unreadable += reopened.unreadableCount
            for row in reopened.records { recovered[row.id] = row }
            if !reopened.hasNext { break }
        }
        XCTAssertEqual(recovered.count, 501)
        XCTAssertEqual(recovered, expected, "Every unrelated title, payload, revision and restoration field survives.")
        XCTAssertEqual(unreadable, 1)
        let preserved = try await reopenedStore.read(id: corrupt.id)
        XCTAssertEqual(preserved, corrupt)
        let historyAfter = try await reopenedStore.history(id: neighbor.id)
        XCTAssertEqual(historyAfter.records, neighborHistory.records)
    }
    func testEntireUnreadablePageStillReachesLaterValidBuild() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let invalidSnapshot = try JSONSerialization.data(withJSONObject: [
            "storageVersion": 1, "snapshot": Data("{}".utf8).base64EncodedString(), "markedSynthetic": false
        ])
        for index in 0..<ImportedBuildLibraryModel.pageSize {
            _ = try await store.save(id: recordID(index), expectedRevision: nil, title: "Invalid snapshot", payload: invalidSnapshot)
        }
        let valid = try await store.save(id: recordID(20), expectedRevision: nil, title: "Later valid build", payload: storedPayload())
        await model.refresh()
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertEqual(model.unreadableCount, 20)
        XCTAssertTrue(model.hasNext)
        await model.refresh(offset: 20)
        XCTAssertEqual(model.records, [valid])
        XCTAssertEqual(model.unreadableCount, 0)
        XCTAssertFalse(model.hasNext)
        await model.open(valid)
        XCTAssertNotNil(model.snapshot)
        let preserved = try await store.read(id: recordID(0))
        XCTAssertEqual(preserved.payload, invalidSnapshot)
    }
    func testMalformedQualificationCannotBeOpenedMutatedOrSilentlyDropped() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: storedPayload()) as? [String: Any])
        fields["markedSynthetic"] = true
        fields["sourceRevision"] = "not-a-contract-revision"
        let bytes = try JSONSerialization.data(withJSONObject: fields)
        let bad = try await store.save(id: recordID(0), expectedRevision: nil, title: "Invalid metadata", payload: bytes)
        await model.refresh()
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertEqual(model.unreadableCount, 1)
        await model.open(bad)
        XCTAssertNil(model.snapshot)
        await model.rename(bad, to: "Must not change")
        await model.duplicate(bad)
        await model.delete(bad)
        let preserved = try await store.read(id: bad.id)
        XCTAssertEqual(preserved, bad)
        let page = try await store.list()
        XCTAssertEqual(page.records.count, 1)
        XCTAssertNotNil(model.notice)
    }
    func testPreviewPreparationLeavesMainActorResponsive() async throws {
        for fromFile in [false, true] {
            let probe = BlockedBuildPreparation()
            defer { probe.release() }
            let preparation = ImportedBuildPreparation(preview: { data in
                probe.pauseFirst()
                return try ImportedBuildPreparation.live.preview(data)
            }, export: ImportedBuildPreparation.live.export)
            let (store, model, folder) = try setup(preparation: preparation)
            defer { try? FileManager.default.removeItem(at: folder) }
            let (selected, snapshot) = try await selectedFixture(model, store: store)
            let editor = try await notesEditor(in: folder)
            let bytes = try fixture(), file = folder.appendingPathComponent("preview.json")
            try bytes.write(to: file)
            let preparing = Task {
                if fromFile { await model.previewFile(file) }
                else { try await model.preparePreview(bytes) }
            }
            let entered = await probe.waitUntilEntered()
            XCTAssertTrue(entered)
            XCTAssertTrue(model.busy)
            XCTAssertNil(model.preview)
            XCTAssertEqual(model.selected, selected)
            XCTAssertEqual(model.snapshot, snapshot)
            assertResponsiveEditor(editor, probe: probe)
            probe.release(); try await preparing.value
            XCTAssertFalse(model.busy)
            XCTAssertEqual(model.preview?.snapshot, snapshot)
            XCTAssertEqual(probe.observations.calls, 1)
            XCTAssertFalse(probe.observations.timedOut)
            try await assertUnchanged(selected, in: folder)
        }
    }
    func testCancelledPreviewPreparationCannotPublishOrWrite() async throws {
        for (fromFile, failAfterCancellation) in [(false, false), (false, true), (true, false), (true, true)] {
            let probe = BlockedBuildPreparation()
            defer { probe.release() }
            let preparation = ImportedBuildPreparation(preview: { data in
                probe.pauseFirst() // Deliberately finishes even after cancellation.
                if failAfterCancellation { throw TransferError.malformed }
                return try ImportedBuildPreparation.live.preview(data)
            }, export: ImportedBuildPreparation.live.export)
            let (store, model, folder) = try setup(preparation: preparation)
            defer { try? FileManager.default.removeItem(at: folder) }
            let (selected, snapshot) = try await selectedFixture(model, store: store)
            let bytes = try fixture(), file = folder.appendingPathComponent("cancelled.json")
            try bytes.write(to: file)
            let preparing = Task {
                if fromFile { await model.previewFile(file) }
                else { try await model.preparePreview(bytes) }
            }
            let entered = await probe.waitUntilEntered()
            XCTAssertTrue(entered)
            preparing.cancel()
            probe.release()
            var threwCancellation = false
            do { try await preparing.value }
            catch is CancellationError { threwCancellation = true }
            XCTAssertEqual(threwCancellation, !fromFile)
            XCTAssertFalse(model.busy)
            XCTAssertNil(model.preview)
            XCTAssertNil(model.notice)
            XCTAssertEqual(model.selected, selected)
            XCTAssertEqual(model.snapshot, snapshot)
            XCTAssertTrue(probe.observations.offMain)
            XCTAssertFalse(probe.observations.timedOut)
            try await assertUnchanged(selected, in: folder)
        }
    }
    func testExportPreparationLeavesMainActorResponsiveAndPreservesQualification() async throws {
        let probe = BlockedBuildPreparation()
        defer { probe.release() }
        let preparation = ImportedBuildPreparation(preview: ImportedBuildPreparation.live.preview, export: { request in
            probe.pauseFirst()
            return try ImportedBuildPreparation.live.export(request)
        })
        let (store, model, folder) = try setup(preparation: preparation)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (selected, snapshot) = try await selectedFixture(model, store: store, synthetic: true)
        let editor = try await notesEditor(in: folder)
        let preparing = try XCTUnwrap(model.prepareExport(publicAlias: "reviewed.public"))
        let entered = await probe.waitUntilEntered()
        XCTAssertTrue(entered)
        XCTAssertTrue(model.busy)
        XCTAssertNil(model.exportData)
        assertResponsiveEditor(editor, probe: probe)
        probe.release(); await preparing.value
        let exported = try BuildTransfer.preview(XCTUnwrap(model.exportData))
        guard case .object(let fields) = exported.snapshot.value else {
            return XCTFail("Exported snapshot must retain an object root")
        }
        XCTAssertEqual(fields["owner_ref"], .string("reviewed.public"))
        XCTAssertEqual(exported.snapshot.id, snapshot.id)
        XCTAssertEqual(exported.snapshot.locks, snapshot.locks)
        XCTAssertEqual(exported.usesSyntheticData, true)
        XCTAssertEqual(exported.sourceRevision, String(repeating: "e", count: 40))
        XCTAssertEqual(model.selected, selected)
        XCTAssertEqual(model.snapshot, snapshot)
        XCTAssertFalse(model.busy)
        XCTAssertFalse(probe.observations.timedOut)
        try await assertUnchanged(selected, in: folder)
    }
    func testClearedExportRejectsLateBytesAndErrorsAndRetryUsesNewAlias() async throws {
        for failFirst in [false, true] {
            let probe = BlockedBuildPreparation()
            defer { probe.release() }
            let preparation = ImportedBuildPreparation(preview: ImportedBuildPreparation.live.preview, export: { request in
                let call = probe.pauseFirst()
                if call == 1, failFirst { throw TransferError.malformed }
                return try ImportedBuildPreparation.live.export(request)
            })
            let (store, model, folder) = try setup(preparation: preparation)
            defer { try? FileManager.default.removeItem(at: folder) }
            let (selected, snapshot) = try await selectedFixture(model, store: store)
            let preparing = try XCTUnwrap(model.prepareExport(publicAlias: "old.alias"))
            let entered = await probe.waitUntilEntered()
            XCTAssertTrue(entered)
            model.clearExport() // The same invalidation used by the alias binding.
            probe.release(); await preparing.value
            XCTAssertNil(model.exportData)
            XCTAssertNil(model.notice, "An invalidated preparation cannot publish a late failure either")
            XCTAssertFalse(model.busy)
            XCTAssertEqual(model.selected, selected)
            XCTAssertEqual(model.snapshot, snapshot)
            await model.prepareExport(publicAlias: "new.alias")?.value
            let exported = try BuildTransfer.preview(XCTUnwrap(model.exportData))
            guard case .object(let fields) = exported.snapshot.value else {
                return XCTFail("Exported snapshot must retain an object root")
            }
            XCTAssertEqual(fields["owner_ref"], .string("new.alias"))
            XCTAssertEqual(probe.observations.calls, 2)
            XCTAssertTrue(probe.observations.offMain)
            XCTAssertFalse(probe.observations.timedOut)
            try await assertUnchanged(selected, in: folder)
        }
    }
    func testInvalidatedQueuedExportNeverEntersPreparation() async throws {
        let probe = BlockedBuildPreparation()
        defer { probe.release() }
        let preparation = ImportedBuildPreparation(preview: ImportedBuildPreparation.live.preview, export: { request in
            probe.pauseFirst()
            return try ImportedBuildPreparation.live.export(request)
        })
        let (store, model, folder) = try setup(preparation: preparation)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (selected, snapshot) = try await selectedFixture(model, store: store)
        let preparing = try XCTUnwrap(model.prepareExport(publicAlias: "old.alias"))
        // Both actions occur on this actor turn, before the queued task begins.
        model.clearExport()
        await preparing.value
        XCTAssertEqual(probe.observations.calls, 0)
        XCTAssertNil(model.exportData)
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.selected, selected)
        XCTAssertEqual(model.snapshot, snapshot)
        try await assertUnchanged(selected, in: folder)
    }
    func testCancelledExportPreparationCannotPublishOrWrite() async throws {
        for failAfterCancellation in [false, true] {
            let probe = BlockedBuildPreparation()
            defer { probe.release() }
            let preparation = ImportedBuildPreparation(preview: ImportedBuildPreparation.live.preview, export: { request in
                probe.pauseFirst()
                if failAfterCancellation { throw TransferError.malformed }
                return try ImportedBuildPreparation.live.export(request)
            })
            let (store, model, folder) = try setup(preparation: preparation)
            defer { try? FileManager.default.removeItem(at: folder) }
            let (selected, snapshot) = try await selectedFixture(model, store: store)
            let preparing = try XCTUnwrap(model.prepareExport(publicAlias: "cancelled.alias"))
            let entered = await probe.waitUntilEntered()
            XCTAssertTrue(entered)
            preparing.cancel()
            probe.release(); await preparing.value
            XCTAssertNil(model.exportData)
            XCTAssertNil(model.notice)
            XCTAssertFalse(model.busy)
            XCTAssertEqual(model.selected, selected)
            XCTAssertEqual(model.snapshot, snapshot)
            XCTAssertTrue(probe.observations.offMain)
            XCTAssertFalse(probe.observations.timedOut)
            try await assertUnchanged(selected, in: folder)
        }
    }
    func testComparisonPreparationLeavesMainActorResponsiveAndPreservesInputs() async throws {
        let probe = BlockedBuildPreparation()
        defer { probe.release() }
        let (store, model, folder) = try setup(preparation: comparisonPreparation(probe))
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixtures = try await comparisonFixtures(in: store)
        await pinFirstAndSelectSecond(model, fixtures: fixtures)
        let editor = try await notesEditor(in: folder)
        let preparing = try XCTUnwrap(model.prepareComparison())
        let entered = await probe.waitUntilEntered()
        XCTAssertTrue(entered)
        XCTAssertTrue(model.comparing)
        XCTAssertFalse(model.busy, "Read-only comparison must not serialize ordinary library work")
        XCTAssertNil(model.prepareComparison(), "Repeated taps must not queue identical in-flight work")
        XCTAssertNil(model.comparison)
        assertResponsiveEditor(editor, probe: probe)
        probe.release(); await preparing.value
        let comparison = try XCTUnwrap(model.comparison)
        XCTAssertEqual(comparison.result, try BuildComparison.compare(fixtures[0].snapshot, fixtures[1].snapshot))
        XCTAssertFalse(comparison.beforeSynthetic)
        XCTAssertTrue(comparison.afterSynthetic)
        XCTAssertFalse(model.comparing)
        XCTAssertNil(model.comparisonNotice)
        XCTAssertEqual(model.selected, fixtures[1].row)
        XCTAssertEqual(model.comparisonBaseline, fixtures[0].snapshot)
        XCTAssertFalse(probe.observations.timedOut)
        model.cancelComparison() // Detail navigation must retain an already completed result.
        XCTAssertEqual(model.comparison, comparison)
        try await assertComparisonRowsUnchanged(fixtures.map { $0.row }, in: folder)
    }
    func testNewSelectionComparisonFinishesBeforeCancelledOlderResultOrError() async throws {
        for failFirst in [false, true] {
            let probe = BlockedBuildPreparation()
            defer { probe.release() }
            let (store, model, folder) = try setup(preparation: comparisonPreparation(probe, failFirst: failFirst))
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixtures = try await comparisonFixtures(in: store)
            await pinFirstAndSelectSecond(model, fixtures: fixtures)
            let older = try XCTUnwrap(model.prepareComparison())
            let entered = await probe.waitUntilEntered()
            XCTAssertTrue(entered)
            await model.open(fixtures[2].row)
            let newer = try XCTUnwrap(model.prepareComparison())
            await newer.value // N+1 completes while the cancelled N worker is still blocked.
            let current = try XCTUnwrap(model.comparison)
            XCTAssertEqual(current.result, try BuildComparison.compare(fixtures[0].snapshot, fixtures[2].snapshot))
            XCTAssertFalse(current.beforeSynthetic)
            XCTAssertFalse(current.afterSynthetic)
            XCTAssertFalse(probe.observations.timedOut)
            probe.release(); await older.value
            XCTAssertEqual(model.comparison, current)
            XCTAssertNil(model.comparisonNotice)
            XCTAssertFalse(model.comparing)
            XCTAssertEqual(model.selected, fixtures[2].row)
            XCTAssertEqual(probe.observations.calls, 2)
            XCTAssertTrue(probe.observations.offMain)
            try await assertComparisonRowsUnchanged(fixtures.map { $0.row }, in: folder)
        }
    }
    func testCancelledOlderComparisonCannotClearPendingNewerWork() async throws {
        for failOlder in [false, true] {
            let olderProbe = BlockedBuildPreparation(), newerProbe = BlockedBuildPreparation()
            defer { olderProbe.release(); newerProbe.release() }
            let preparation = ImportedBuildPreparation(preview: ImportedBuildPreparation.live.preview,
                export: ImportedBuildPreparation.live.export, compare: { before, after in
                    if after.name == "Comparison fixture 1" {
                        olderProbe.pauseFirst()
                        if failOlder { throw BuildComparisonError.tooManyDifferences }
                    } else { newerProbe.pauseFirst() }
                    return try BuildComparison.compare(before, after)
                })
            let (store, model, folder) = try setup(preparation: preparation)
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixtures = try await comparisonFixtures(in: store)
            await pinFirstAndSelectSecond(model, fixtures: fixtures)
            let older = try XCTUnwrap(model.prepareComparison())
            let olderEntered = await olderProbe.waitUntilEntered()
            XCTAssertTrue(olderEntered)
            await model.open(fixtures[2].row)
            let newer = try XCTUnwrap(model.prepareComparison())
            let newerEntered = await newerProbe.waitUntilEntered()
            XCTAssertTrue(newerEntered)
            olderProbe.release(); await older.value // Retired cleanup runs while N+1 still owns the lane.
            XCTAssertTrue(model.comparing, "The older request cannot clear a newer request's progress state")
            XCTAssertNil(model.comparison)
            XCTAssertNil(model.comparisonNotice)
            XCTAssertEqual(model.selected, fixtures[2].row)
            XCTAssertFalse(newerProbe.observations.timedOut)
            newerProbe.release(); await newer.value
            let current = try XCTUnwrap(model.comparison)
            XCTAssertEqual(current.result, try BuildComparison.compare(fixtures[0].snapshot, fixtures[2].snapshot))
            XCTAssertFalse(current.beforeSynthetic)
            XCTAssertFalse(current.afterSynthetic)
            XCTAssertFalse(model.comparing)
            XCTAssertNil(model.comparisonNotice)
            XCTAssertEqual(olderProbe.observations.calls, 1)
            XCTAssertEqual(newerProbe.observations.calls, 1)
            XCTAssertTrue(olderProbe.observations.offMain)
            XCTAssertTrue(newerProbe.observations.offMain)
            XCTAssertFalse(olderProbe.observations.timedOut)
            XCTAssertFalse(newerProbe.observations.timedOut)
            try await assertComparisonRowsUnchanged(fixtures.map { $0.row }, in: folder)
        }
    }
    func testReplacingBaselineRejectsLateComparisonAndRetainsNewQualification() async throws {
        for failFirst in [false, true] {
            let probe = BlockedBuildPreparation()
            defer { probe.release() }
            let (store, model, folder) = try setup(preparation: comparisonPreparation(probe, failFirst: failFirst))
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixtures = try await comparisonFixtures(in: store)
            await pinFirstAndSelectSecond(model, fixtures: fixtures)
            let older = try XCTUnwrap(model.prepareComparison())
            let entered = await probe.waitUntilEntered()
            XCTAssertTrue(entered)
            model.pinComparisonBaseline()
            await model.prepareComparison()?.value
            let current = try XCTUnwrap(model.comparison)
            XCTAssertEqual(current.result.before.id, fixtures[1].snapshot.id)
            XCTAssertEqual(current.result.after.id, fixtures[1].snapshot.id)
            XCTAssertTrue(current.result.differences.isEmpty)
            XCTAssertTrue(current.beforeSynthetic)
            XCTAssertTrue(current.afterSynthetic)
            XCTAssertFalse(probe.observations.timedOut)
            probe.release(); await older.value
            XCTAssertEqual(model.comparison, current)
            XCTAssertEqual(model.comparisonBaseline, fixtures[1].snapshot)
            XCTAssertNil(model.comparisonNotice)
            XCTAssertFalse(model.comparing)
            try await assertComparisonRowsUnchanged(fixtures.map { $0.row }, in: folder)
        }
    }
    func testClearedBaselineRejectsLateComparisonAndError() async throws {
        for failFirst in [false, true] {
            let probe = BlockedBuildPreparation()
            defer { probe.release() }
            let (store, model, folder) = try setup(preparation: comparisonPreparation(probe, failFirst: failFirst))
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixtures = try await comparisonFixtures(in: store)
            await pinFirstAndSelectSecond(model, fixtures: fixtures)
            let preparing = try XCTUnwrap(model.prepareComparison())
            let entered = await probe.waitUntilEntered()
            XCTAssertTrue(entered)
            model.clearComparisonBaseline()
            XCTAssertFalse(model.comparing)
            XCTAssertNil(model.prepareComparison())
            probe.release(); await preparing.value
            XCTAssertNil(model.comparisonBaseline)
            XCTAssertNil(model.comparison)
            XCTAssertNil(model.comparisonNotice)
            XCTAssertEqual(model.selected, fixtures[1].row)
            XCTAssertFalse(probe.observations.timedOut)
            try await assertComparisonRowsUnchanged(fixtures.map { $0.row }, in: folder)
        }
    }
    func testCancelledComparisonRejectsLateResultAndErrorWithoutClearingPin() async throws {
        for (leaveView, failFirst) in [(false, false), (false, true), (true, false), (true, true)] {
            let probe = BlockedBuildPreparation()
            defer { probe.release() }
            let (store, model, folder) = try setup(preparation: comparisonPreparation(probe, failFirst: failFirst))
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixtures = try await comparisonFixtures(in: store)
            await pinFirstAndSelectSecond(model, fixtures: fixtures)
            let preparing = try XCTUnwrap(model.prepareComparison())
            let entered = await probe.waitUntilEntered()
            XCTAssertTrue(entered)
            if leaveView { model.cancelComparison() } else { preparing.cancel() }
            probe.release(); await preparing.value
            XCTAssertNil(model.comparison)
            XCTAssertNil(model.comparisonNotice)
            XCTAssertFalse(model.comparing)
            XCTAssertEqual(model.comparisonBaseline, fixtures[0].snapshot)
            XCTAssertEqual(model.selected, fixtures[1].row)
            XCTAssertFalse(probe.observations.timedOut)
            try await assertComparisonRowsUnchanged(fixtures.map { $0.row }, in: folder)
        }
    }
    func testInvalidatedQueuedComparisonNeverEntersWorker() async throws {
        let probe = BlockedBuildPreparation()
        defer { probe.release() }
        let (store, model, folder) = try setup(preparation: comparisonPreparation(probe))
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixtures = try await comparisonFixtures(in: store)
        await pinFirstAndSelectSecond(model, fixtures: fixtures)
        let preparing = try XCTUnwrap(model.prepareComparison())
        model.clearComparisonBaseline() // Same actor turn, before the queued task starts.
        await preparing.value
        XCTAssertEqual(probe.observations.calls, 0)
        XCTAssertNil(model.comparisonBaseline)
        XCTAssertNil(model.comparison)
        XCTAssertNil(model.comparisonNotice)
        XCTAssertFalse(model.comparing)
        try await assertComparisonRowsUnchanged(fixtures.map { $0.row }, in: folder)
    }
    func testCommittedBaselineDeletionCancelsPendingComparisonAndPreservesSelection() async throws {
        for failFirst in [false, true] {
            let probe = BlockedBuildPreparation()
            defer { probe.release() }
            let (store, model, folder) = try setup(preparation: comparisonPreparation(probe, failFirst: failFirst))
            defer { try? FileManager.default.removeItem(at: folder) }
            let fixtures = try await comparisonFixtures(in: store)
            await pinFirstAndSelectSecond(model, fixtures: fixtures)
            let preparing = try XCTUnwrap(model.prepareComparison())
            let entered = await probe.waitUntilEntered()
            XCTAssertTrue(entered)
            await model.delete(fixtures[0].row)
            XCTAssertEqual(model.lastDeletedID, fixtures[0].row.id)
            XCTAssertNil(model.comparisonBaseline)
            XCTAssertFalse(model.comparing)
            XCTAssertEqual(model.selected, fixtures[1].row)
            probe.release(); await preparing.value
            XCTAssertNil(model.comparison)
            XCTAssertNil(model.comparisonNotice)
            XCTAssertFalse(probe.observations.timedOut)
            try await assertComparisonRowsUnchanged(fixtures.dropFirst().map { $0.row }, in: folder)
        }
    }
    func testRejectedBaselineDeletionPreservesPinAndPendingComparison() async throws {
        let probe = BlockedBuildPreparation()
        defer { probe.release() }
        let (store, model, folder) = try setup(preparation: comparisonPreparation(probe))
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixtures = try await comparisonFixtures(in: store)
        await pinFirstAndSelectSecond(model, fixtures: fixtures)
        let preparing = try XCTUnwrap(model.prepareComparison())
        let entered = await probe.waitUntilEntered()
        XCTAssertTrue(entered)
        let renamed = try await store.rename(id: fixtures[0].row.id, expectedRevision: fixtures[0].row.revision, title: "Newer local label")
        await model.delete(fixtures[0].row)
        XCTAssertNil(model.lastDeletedID)
        XCTAssertNotNil(model.notice)
        XCTAssertTrue(model.comparing)
        XCTAssertEqual(model.comparisonBaseline, fixtures[0].snapshot)
        probe.release(); await preparing.value
        XCTAssertEqual(model.comparison?.result, try BuildComparison.compare(fixtures[0].snapshot, fixtures[1].snapshot))
        XCTAssertNil(model.comparisonNotice)
        XCTAssertNotNil(model.notice, "A read-only comparison must not clear a storage failure")
        XCTAssertFalse(model.comparing)
        XCTAssertFalse(probe.observations.timedOut)
        let reopened = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let baseline = try await reopened.read(id: renamed.id), history = try await reopened.history(id: renamed.id)
        XCTAssertEqual(baseline, renamed)
        XCTAssertEqual(history.records, [renamed, fixtures[0].row])
        for other in fixtures.dropFirst() {
            let row = try await reopened.read(id: other.row.id), revisions = try await reopened.history(id: other.row.id)
            XCTAssertEqual(row, other.row)
            XCTAssertEqual(revisions.records, [other.row])
        }
    }
}
