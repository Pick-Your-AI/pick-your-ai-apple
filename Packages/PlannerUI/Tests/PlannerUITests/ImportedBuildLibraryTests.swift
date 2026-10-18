import XCTest
import PlannerData
import PlannerTransfer
@testable import PlannerUI

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
    private func setup() throws -> (DraftStore, ImportedBuildLibraryModel, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        return (store, ImportedBuildLibraryModel(store: store), folder)
    }
    private func recordID(_ index: Int) -> UUID {
        let tail = String(index, radix: 16)
        return UUID(uuidString: "00000000-0000-0000-0000-" + String(repeating: "0", count: 12 - tail.count) + tail)!
    }
    private func storedPayload() throws -> Data {
        let snapshot = try BuildTransfer.preview(fixture()).snapshot
        return try JSONEncoder().encode(ImportedBuildRecord(snapshot: snapshot, markedSynthetic: false, sourceRevision: nil))
    }
    func testPreviewAndCancelNeverWriteStorage() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try model.preparePreview(fixture())
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
        try model.preparePreview(bytes); await model.confirmImport()
        let first = try XCTUnwrap(model.snapshot)
        let row = try XCTUnwrap(model.selected)
        XCTAssertNotEqual(first.id, source.id)
        XCTAssertEqual(first.locks, source.locks)
        XCTAssertEqual(row.revision, 1)
        try model.preparePreview(bytes); await model.confirmImport()
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
        try model.preparePreview(JSONEncoder().encode(envelope)); await model.confirmImport()
        let row = try XCTUnwrap(model.selected)
        let secondConnection = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let reopened = ImportedBuildLibraryModel(store: secondConnection)
        await reopened.open(row)
        XCTAssertTrue(reopened.markedSynthetic)
        reopened.prepareExport(publicAlias: "public.alias")
        let exported = try BuildTransfer.preview(XCTUnwrap(reopened.exportData))
        XCTAssertEqual(exported.usesSyntheticData, true)
        XCTAssertEqual(exported.sourceRevision, sha)
        XCTAssertEqual(exported.snapshot.locks, snapshot.locks)
    }
    func testExportRequiresAliasAndDoesNotExposeLocalOwner() async throws {
        let (_, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try model.preparePreview(fixture()); await model.confirmImport()
        model.prepareExport(publicAlias: "")
        XCTAssertNil(model.exportData)
        model.prepareExport(publicAlias: "reviewed.alias")
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
        try model.preparePreview(fixture())
        XCTAssertThrowsError(try model.preparePreview(Data("{}".utf8)))
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
        try model.preparePreview(fixture()); await model.confirmImport()
        let original = try XCTUnwrap(model.selected)
        let snapshot = try XCTUnwrap(model.snapshot)
        model.prepareExport(publicAlias: "reviewed.public")
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
        try model.preparePreview(JSONEncoder().encode(envelope)); await model.confirmImport()
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
        reopened.prepareExport(publicAlias: "reviewed.public")
        let exported = try BuildTransfer.preview(XCTUnwrap(reopened.exportData))
        XCTAssertEqual(exported.usesSyntheticData, true)
        XCTAssertEqual(exported.sourceRevision, sha)
        XCTAssertEqual(exported.snapshot.locks, source.locks)
    }
    func testStaleRenameDuplicateAndDeleteCannotMutateNewerRevision() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try model.preparePreview(fixture()); await model.confirmImport()
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
        try model.preparePreview(fixture()); await model.confirmImport()
        let pendingDelete = try XCTUnwrap(model.selected)
        await model.duplicate(pendingDelete)
        let selected = try XCTUnwrap(model.selected)
        let selectedSnapshot = model.snapshot
        model.prepareExport(publicAlias: "reviewed.public")
        let export = try XCTUnwrap(model.exportData)
        await model.delete(pendingDelete)
        XCTAssertEqual(model.selected, selected)
        XCTAssertEqual(model.snapshot, selectedSnapshot)
        XCTAssertEqual(model.exportData, export)
        let page = try await store.list()
        XCTAssertEqual(page.records, [selected])
        await model.delete(selected)
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
}
