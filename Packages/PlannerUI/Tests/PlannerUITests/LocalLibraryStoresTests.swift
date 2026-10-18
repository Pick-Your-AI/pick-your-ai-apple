import XCTest
import PlannerData
@testable import PlannerUI

@MainActor
final class LocalLibraryStoresTests: XCTestCase {
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testCorruptImportedLibraryDoesNotHideSavedNotesOrHistory() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = try DraftStore(url: directory.appendingPathComponent("drafts.sqlite"))
        let id = UUID()
        let original = try await notes.save(id: id, expectedRevision: nil, title: "Saved note", payload: Data("{\"notes\":\"earlier\"}".utf8))
        let current = try await notes.save(id: id, expectedRevision: original.revision, title: "Saved note", payload: Data("{\"notes\":\"current\"}".utf8))
        let brokenURL = directory.appendingPathComponent("imported-builds.sqlite")
        let broken = Data("not a SQLite database".utf8)
        try broken.write(to: brokenURL)

        let libraries = LocalLibraryStores(directory: directory)
        XCTAssertNil(libraries.importedBuilds)
        let reopened = try XCTUnwrap(libraries.notes)
        let record = try await reopened.read(id: id)
        let history = try await reopened.history(id: id)
        XCTAssertEqual(record, current)
        XCTAssertEqual(history.records.map(\.revision), [2, 1])
        XCTAssertEqual(try Data(contentsOf: brokenURL), broken)
    }

    func testCorruptNotesDoNotHideExistingImportedLibrary() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imports = try DraftStore(url: directory.appendingPathComponent("imported-builds.sqlite"))
        let id = UUID()
        let saved = try await imports.save(id: id, expectedRevision: nil, title: "Stored import", payload: Data("{\"preserved\":true}".utf8))
        let brokenURL = directory.appendingPathComponent("drafts.sqlite")
        let broken = Data("not a SQLite database".utf8)
        try broken.write(to: brokenURL)

        let libraries = LocalLibraryStores(directory: directory)
        XCTAssertNil(libraries.notes)
        let reopened = try XCTUnwrap(libraries.importedBuilds)
        let record = try await reopened.read(id: id)
        XCTAssertEqual(record, saved)
        XCTAssertEqual(try Data(contentsOf: brokenURL), broken)
    }
}
