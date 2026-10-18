import Foundation
import CryptoKit
import XCTest
import PlannerData
import PlannerTransfer
@testable import PlannerUI

@MainActor
final class LocalForkLineageTests: XCTestCase {
    private func fixture(id: String = "build.lineage.source", revision: Int = 7) throws -> Data {
        let bytes = try Data(contentsOf: Bundle.module.url(forResource: "build", withExtension: "json")!)
        let source = try BuildTransfer.snapshot(fromDraftJSON: bytes)
        guard case .object(var fields) = source.value, case .array(let selections)? = fields["selections"] else {
            throw TransferError.malformed
        }
        fields["id"] = .string(id); fields["revision"] = .number(Decimal(revision))
        fields["selections"] = .array(selections.map { value in
            guard case .object(var selection) = value, case .object(var settings)? = selection["settings"] else { return value }
            settings.removeValue(forKey: "index_name")
            selection["settings"] = .object(settings)
            return .object(selection)
        })
        let clean = try BuildTransfer.snapshot(fromDraftJSON: JSONEncoder().encode(JSONValue.object(fields)))
        return try BuildTransfer.export(clean, publicOwnerAlias: "fixture.public")
    }
    private func setup() throws -> (DraftStore, ImportedBuildLibraryModel, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        return (store, ImportedBuildLibraryModel(store: store), folder)
    }
    private func fingerprint(_ snapshot: BuildSnapshot) throws -> String {
        SHA256.hash(data: try snapshot.encoded()).map { String(format: "%02x", $0) }.joined()
    }
    private func legacyRow(_ store: DraftStore) async throws -> DraftRecord {
        let snapshot = try BuildTransfer.preview(fixture(id: "build.legacy.control", revision: 3)).snapshot
        let wrapper = try ImportedBuildRecord(snapshot: snapshot, markedSynthetic: false, sourceRevision: nil)
        return try await store.save(id: UUID(), expectedRevision: nil, title: "Existing local control",
                                    payload: JSONEncoder().encode(wrapper))
    }
    func testImportedForkRecordsItsExactSourceAndPreservesExistingEntry() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let existing = try await legacyRow(store)
        // Largest safe-range integer with the frozen parser's fifteen significant digits.
        let sourceRevision = 9_007_199_254_740_990
        let sourceBytes = try fixture(revision: sourceRevision)
        let source = try BuildTransfer.preview(sourceBytes).snapshot
        try await model.preparePreview(sourceBytes)
        await model.confirmImport()
        let row = try XCTUnwrap(model.selected)
        let fork = try XCTUnwrap(model.snapshot)
        let lineage = try XCTUnwrap(model.lineage)
        XCTAssertEqual(lineage.count, 1)
        XCTAssertEqual(lineage[0].buildID, source.id)
        XCTAssertEqual(lineage[0].revision, sourceRevision)
        XCTAssertEqual(lineage[0].snapshotSHA256, try fingerprint(source))
        XCTAssertNotEqual(lineage[0].snapshotSHA256, try fingerprint(fork))
        XCTAssertNotEqual(fork.id, source.id)
        XCTAssertEqual(fork.locks, source.locks)
        XCTAssertEqual(try BuildTransfer.preview(sourceBytes).snapshot, source)
        let retained = try await store.read(id: existing.id)
        let history = try await store.history(id: existing.id)
        XCTAssertEqual(retained, existing)
        XCTAssertEqual(history.records, [existing])
        let reopened = ImportedBuildLibraryModel(store: try DraftStore(url: folder.appendingPathComponent("imports.sqlite")))
        await reopened.open(row)
        XCTAssertEqual(reopened.lineage, lineage)
        XCTAssertEqual(reopened.snapshot, fork)
        XCTAssertFalse(reopened.markedSynthetic)
    }
    func testForkOfForkRetainsLineageAfterAncestorRenameDeleteAndReopen() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try BuildTransfer.preview(fixture()).snapshot
        let sourceRevision = String(repeating: "a", count: 40)
        let envelope = JSONValue.object([
            "format": .string("pickyour.ai/build-export"), "formatVersion": .number(1),
            "exportedAt": .string("2026-10-18T00:00:00Z"),
            "contract": .object(["version": .string("1.0.0"), "sourceSha": .string(sourceRevision)]),
            "dataMode": .string("fixture"), "build": source.value
        ])
        try await model.preparePreview(JSONEncoder().encode(envelope)); await model.confirmImport()
        let first = try XCTUnwrap(model.selected), firstSnapshot = try XCTUnwrap(model.snapshot)
        await model.duplicate(first)
        let second = try XCTUnwrap(model.selected), secondSnapshot = try XCTUnwrap(model.snapshot)
        await model.duplicate(second)
        let third = try XCTUnwrap(model.selected), thirdSnapshot = try XCTUnwrap(model.snapshot)
        let lineage = try XCTUnwrap(model.lineage)
        XCTAssertEqual(Set([first.id, second.id, third.id]).count, 3)
        XCTAssertEqual(Set([firstSnapshot.id, secondSnapshot.id, thirdSnapshot.id]).count, 3)
        XCTAssertEqual(lineage.map(\.buildID), [secondSnapshot.id, firstSnapshot.id, source.id])
        XCTAssertEqual(lineage.map(\.revision), [1, 1, 7])
        XCTAssertEqual(lineage.map(\.snapshotSHA256), try [secondSnapshot, firstSnapshot, source].map { try fingerprint($0) })
        XCTAssertEqual(thirdSnapshot.locks, source.locks)
        XCTAssertTrue(model.markedSynthetic)

        await model.rename(first, to: "Changed ancestor label")
        await model.delete(second)
        XCTAssertEqual(model.selected, third)
        XCTAssertEqual(model.lineage, lineage)
        let durable = try await store.read(id: third.id)
        let history = try await store.history(id: third.id)
        XCTAssertEqual(durable, third)
        XCTAssertEqual(history.records, [third])
        let reopened = ImportedBuildLibraryModel(store: try DraftStore(url: folder.appendingPathComponent("imports.sqlite")))
        await reopened.open(third)
        XCTAssertEqual(reopened.lineage, lineage)
        XCTAssertEqual(reopened.snapshot, thirdSnapshot)
        XCTAssertTrue(reopened.markedSynthetic)
        await reopened.prepareExport(publicAlias: "reviewed.public")?.value
        let exported = try BuildTransfer.preview(XCTUnwrap(reopened.exportData))
        XCTAssertEqual(exported.usesSyntheticData, true)
        XCTAssertEqual(exported.sourceRevision, sourceRevision)
    }
    func testLegacyEntryReopensUnchangedAndForkStartsOnlyKnownLineage() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = try await legacyRow(store)
        await model.open(legacy)
        XCTAssertEqual(model.selected, legacy)
        XCTAssertNil(model.lineage)
        let source = try XCTUnwrap(model.snapshot)
        await model.duplicate(legacy)
        let fork = try XCTUnwrap(model.selected)
        XCTAssertNotEqual(fork.id, legacy.id)
        XCTAssertEqual(model.lineage?.map(\.buildID), [source.id])
        XCTAssertEqual(model.lineage?.map(\.revision), [3])
        let before = try ImportedBuildRecord.decode(legacy.payload).wrapper
        let after = try ImportedBuildRecord.decode(fork.payload).wrapper
        XCTAssertEqual(before.storageVersion, 1)
        XCTAssertEqual(after.storageVersion, 2)
        let unchanged = try await store.read(id: legacy.id)
        let history = try await store.history(id: legacy.id)
        XCTAssertEqual(unchanged, legacy)
        XCTAssertEqual(history.records, [legacy])
    }
    func testMalformedLineageIsPreservedWithoutOverwritingSelectionOrCreatingForks() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await model.preparePreview(fixture()); await model.confirmImport()
        let selected = try XCTUnwrap(model.selected), lineage = try XCTUnwrap(model.lineage)
        let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: selected.payload) as? [String: Any])
        let entry = try XCTUnwrap((valid["lineage"] as? [[String: Any]])?.first)
        var invalid: [[String: Any]] = []
        var missing = valid; missing.removeValue(forKey: "lineage"); invalid.append(missing)
        let invalidValues: [Any] = [NSNull(), [], [entry, entry], "Not lineage"]
        for value in invalidValues {
            var fields = valid; fields["lineage"] = value; invalid.append(fields)
        }
        let invalidEntries: [(String, Any)] = [
            ("buildID", "SECRET-LINEAGE-CANARY"), ("revision", 0),
            ("revision", true), ("revision", 1.5), ("revision", 9_007_199_254_740_992),
            ("snapshotSHA256", String(repeating: "A", count: 64)),
            ("privateNote", "SECRET-LINEAGE-CANARY"),
            ("buildID", try XCTUnwrap(model.snapshot).id)
        ]
        for (key, value) in invalidEntries {
            var changed = entry; changed[key] = value
            var fields = valid; fields["lineage"] = [changed]; invalid.append(fields)
        }
        for version in [1, 3] {
            var fields = valid; fields["storageVersion"] = version; invalid.append(fields)
        }
        var oversized = valid
        oversized["lineage"] = (0...ImportedBuildRecord.maximumLineage).map { index in
            var changed = entry; changed["buildID"] = "build.oversized.\(index)"; return changed
        }
        invalid.append(oversized)
        var legacyNull = valid; legacyNull["storageVersion"] = 1; legacyNull["lineage"] = NSNull()
        invalid.append(legacyNull)
        for (index, fields) in invalid.enumerated() {
            let bytes = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            let row = try await store.save(id: UUID(), expectedRevision: nil, title: "Corrupt local lineage \(index)", payload: bytes)
            await model.open(row)
            await model.duplicate(row)
            XCTAssertEqual(model.selected, selected)
            XCTAssertEqual(model.lineage, lineage)
            XCTAssertFalse(model.notice?.contains("SECRET-LINEAGE-CANARY") ?? false)
            let retained = try await store.read(id: row.id)
            let history = try await store.history(id: row.id)
            XCTAssertEqual(retained, row)
            XCTAssertEqual(history.records, [row])
        }
        await model.refresh()
        XCTAssertEqual(model.records, [selected])
        XCTAssertEqual(model.unreadableCount, invalid.count)
        let all = try await store.list()
        XCTAssertEqual(all.records.count, invalid.count + 1)
    }
    func testLineageLimitRejectsAnotherForkWithoutTruncatingOrChangingStorage() async throws {
        let (store, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshot = try BuildTransfer.preview(fixture()).snapshot
        let lineage = (0..<ImportedBuildRecord.maximumLineage).map { index in
            LocalForkSource(buildID: "build.known.\(index)", revision: 1, snapshotSHA256: String(repeating: "a", count: 64))
        }
        let wrapper = try ImportedBuildRecord(snapshot: snapshot, markedSynthetic: false, sourceRevision: nil, lineage: lineage)
        let row = try await store.save(id: UUID(), expectedRevision: nil, title: "Full local lineage", payload: JSONEncoder().encode(wrapper))
        await model.open(row)
        await model.duplicate(row)
        XCTAssertEqual(model.selected, row)
        XCTAssertEqual(model.lineage, lineage)
        XCTAssertTrue(model.notice?.contains("32 copied snapshots") == true)
        let reopened = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let page = try await reopened.list()
        let history = try await reopened.history(id: row.id)
        XCTAssertEqual(page.records, [row])
        XCTAssertEqual(history.records, [row])
    }
    func testExportExcludesLocalLineageAndReimportCannotAssertItsPriorHistory() async throws {
        let (_, model, folder) = try setup()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await model.preparePreview(fixture()); await model.confirmImport()
        let first = try XCTUnwrap(model.selected)
        await model.duplicate(first)
        let snapshot = try XCTUnwrap(model.snapshot), lineage = try XCTUnwrap(model.lineage)
        XCTAssertEqual(lineage.count, 2)
        await model.prepareExport(publicAlias: "reviewed.public")?.value
        let bytes = try XCTUnwrap(model.exportData)
        let exported = try BuildTransfer.preview(bytes).snapshot
        XCTAssertEqual(exported.id, snapshot.id)
        XCTAssertEqual(exported.locks, snapshot.locks)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(fields["lineage"])
        XCTAssertNil(fields["storageVersion"])
        for source in lineage {
            XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(source.snapshotSHA256))
        }
        try await model.preparePreview(bytes); await model.confirmImport()
        XCTAssertEqual(model.lineage?.count, 1)
        XCTAssertEqual(model.lineage?.first?.buildID, exported.id)
        XCTAssertNotEqual(model.lineage, lineage)
        let original = try DraftStore(url: folder.appendingPathComponent("imports.sqlite"))
        let retained = try await original.read(id: first.id)
        XCTAssertEqual(retained, first)
    }
}
