import XCTest
@testable import PlannerCatalog

final class CatalogSearchExactVersionTests: XCTestCase {
    private let composed = "release.caf\u{00e9}"
    private let decomposed = "release.cafe\u{0301}"

    private func identity(_ revision: Int = 1) -> ArtifactIdentity {
        ArtifactIdentity(schemaVersion: "1.0.0", id: "synthetic.catalog", revision: revision,
                         capturedAt: "2026-10-18T00:00:00Z")
    }

    private func entry(_ version: String, id: String = "model.alpha", title: String = "Cafe Alpha") -> CatalogSearchEntry {
        CatalogSearchEntry(id: id, version: version, kind: "model", title: title)
    }

    func testDistinctUnicodeVersionsKeepStablePagesWhenTheSameReleaseIsReordered() async throws {
        let values = [entry(composed), entry(decomposed)]
        for sort in [CatalogSearchSort.title, .kind] {
            let index = CatalogSearchIndex()
            try await index.install(identity: identity(), entries: values)
            let first = try await index.search(limit: 1, sort: sort)
            XCTAssertEqual(first.totalCount, 2)
            XCTAssertEqual(first.entries.count, 1)
            XCTAssertEqual(Array(first.entries[0].version.utf8), Array(decomposed.utf8))
            let token = try XCTUnwrap(first.next)

            // Reversing an identical release must preserve its already-issued page.
            try await index.install(identity: identity(), entries: Array(values.reversed()))
            let second = try await index.search(limit: 1, sort: sort, after: token)
            XCTAssertEqual(second.totalCount, 2)
            XCTAssertEqual(second.entries.count, 1)
            XCTAssertEqual(Array(second.entries[0].version.utf8), Array(composed.utf8))
            XCTAssertNil(second.next)
        }
    }

    func testChangedUnicodeVersionConflictsAndTheNextRevisionRecovers() async throws {
        for (original, changed) in [(composed, decomposed), (decomposed, composed)] {
            let index = CatalogSearchIndex()
            let other = entry("stable", id: "model.beta", title: "Cafe Beta")
            try await index.install(identity: identity(), entries: [entry(original), other])
            let first = try await index.search(limit: 1)
            let token = try XCTUnwrap(first.next)
            do {
                try await index.install(identity: identity(), entries: [entry(changed), other])
                XCTFail("A different version pin was accepted as the same immutable release")
            } catch { XCTAssertEqual(error as? CatalogSearchError, .immutableIdentityConflict) }
            let retained = try await index.search()
            XCTAssertEqual(Array(retained.entries[0].version.utf8), Array(original.utf8))
            let continued = try await index.search(limit: 1, after: token)
            XCTAssertEqual(continued.entries.map(\.id), ["model.beta"])

            try await index.install(identity: identity(2), entries: [entry(changed), other])
            do {
                _ = try await index.search(limit: 1, after: token)
                XCTFail("A prior-release page survived a new revision")
            } catch { XCTAssertEqual(error as? CatalogSearchError, .stalePage) }
            let recovered = try await index.search()
            XCTAssertEqual(recovered.identity.revision, 2)
            XCTAssertEqual(Array(recovered.entries[0].version.utf8), Array(changed.utf8))
        }
    }

    func testChangedUnicodeTitleCannotMasqueradeAsAnIdenticalRelease() async throws {
        for (original, changed) in [("Caf\u{00e9} Alpha", "Cafe\u{0301} Alpha"),
                                    ("Cafe\u{0301} Alpha", "Caf\u{00e9} Alpha")] {
            let index = CatalogSearchIndex()
            let other = entry("stable", id: "model.beta", title: "Cafe Beta")
            try await index.install(identity: identity(), entries: [entry("1", title: original), other])
            let first = try await index.search(query: " CAFE ", limit: 1)
            do {
                try await index.install(identity: identity(), entries: [entry("1", title: changed), other])
                XCTFail("Different supplied title text was accepted as the same immutable release")
            } catch { XCTAssertEqual(error as? CatalogSearchError, .immutableIdentityConflict) }
            let retained = try await index.search(query: "cafe")
            XCTAssertEqual(retained.totalCount, 2)
            XCTAssertEqual(Array(retained.entries[0].title.utf8), Array(original.utf8))
            let continued = try await index.search(query: "cafe", limit: 1, after: XCTUnwrap(first.next))
            XCTAssertEqual(continued.entries.map(\.id), ["model.beta"])
        }
    }

    func testExactVersionDuplicatesStillRejectWithoutDisturbingFoldedSearch() async throws {
        let index = CatalogSearchIndex()
        let original = entry(composed, title: "Caf\u{00e9} Alpha")
        let other = entry("stable", id: "model.beta", title: "Cafe Beta")
        try await index.install(identity: identity(), entries: [original, other])
        let first = try await index.search(query: " CAFE ", kinds: ["model"], limit: 1)
        let reconstructed = String(decoding: Array(composed.utf8), as: UTF8.self)
        do {
            try await index.install(identity: identity(2), entries: [original, entry(reconstructed, title: "Different")])
            XCTFail("An exact duplicate version pin was accepted")
        } catch { XCTAssertEqual(error as? CatalogSearchError, .invalidSnapshot) }
        let retained = try await index.search(query: "cafe", kinds: ["model"])
        XCTAssertEqual(retained.identity.revision, 1)
        XCTAssertEqual(retained.totalCount, 2)
        XCTAssertEqual(Array(retained.entries[0].version.utf8), Array(composed.utf8))
        let continued = try await index.search(query: "cafe", kinds: ["model"], limit: 1, after: XCTUnwrap(first.next))
        XCTAssertEqual(continued.entries.map(\.id), ["model.beta"])
        XCTAssertNil(continued.next)
    }
}
