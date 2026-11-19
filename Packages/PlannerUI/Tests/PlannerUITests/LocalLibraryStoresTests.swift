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

        let libraries = try await LocalLibraryStores.open { directory }
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

        let libraries = try await LocalLibraryStores.open { directory }
        XCTAssertNil(libraries.notes)
        let reopened = try XCTUnwrap(libraries.importedBuilds)
        let record = try await reopened.read(id: id)
        XCTAssertEqual(record, saved)
        XCTAssertEqual(try Data(contentsOf: brokenURL), broken)
    }

    func testBothLibrariesFailingIsRetryableErrorAndPreservesBytes() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let broken = Data("not a SQLite database".utf8)
        let notesURL = directory.appendingPathComponent("drafts.sqlite")
        let importsURL = directory.appendingPathComponent("imported-builds.sqlite")
        try broken.write(to: notesURL)
        try broken.write(to: importsURL)

        do {
            _ = try await LocalLibraryStores.open { directory }
            XCTFail("Two failed opens must not be published as a ready pair of missing libraries")
        } catch {
            XCTAssertEqual(error as? LocalLibraryStores.OpenFailure, .noLibraryAvailable)
        }
        XCTAssertEqual(try Data(contentsOf: notesURL), broken)
        XCTAssertEqual(try Data(contentsOf: importsURL), broken)
    }

    func testStartupRetriesAfterBothLibrariesFailedToOpen() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notesURL = directory.appendingPathComponent("drafts.sqlite")
        let importsURL = directory.appendingPathComponent("imported-builds.sqlite")
        let broken = Data("not a SQLite database".utf8)
        try broken.write(to: notesURL)
        try broken.write(to: importsURL)
        let startup = LocalLibraryStartup { try await LocalLibraryStores.open { directory } }

        await startup.load()
        guard case .unavailable = startup.state else { return XCTFail("Both failed opens must be unavailable, not ready") }

        // Simulates storage becoming readable later (for example after first unlock).
        try FileManager.default.removeItem(at: notesURL)
        try FileManager.default.removeItem(at: importsURL)
        await startup.load()
        guard case .ready(let stores) = startup.state else { return XCTFail("Later appearance must retry") }
        XCTAssertNotNil(stores.notes)
        XCTAssertNotNil(stores.importedBuilds)
    }
}
