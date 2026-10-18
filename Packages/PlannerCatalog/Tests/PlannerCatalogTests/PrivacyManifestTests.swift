import Foundation
import XCTest
@testable import PlannerCatalog

final class PrivacyManifestTests: XCTestCase {
    func testPackagedManifestDeclaresOnlyAppContainerFileMetadataReason() throws {
        // Read the actual SwiftPM resource bundle, so an unbundled source file
        // cannot satisfy this regression.
        let url = try XCTUnwrap(Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(Set(manifest.keys), ["NSPrivacyAccessedAPITypes"])
        let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(Set(entry.keys), ["NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"])
        XCTAssertEqual(entry["NSPrivacyAccessedAPIType"] as? String, "NSPrivacyAccessedAPICategoryFileTimestamp")
        XCTAssertEqual(entry["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])
    }
}
