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
}
