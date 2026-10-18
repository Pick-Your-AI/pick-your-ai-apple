import Foundation
import XCTest
@testable import PlannerUI

final class PlannerUIPrivacyManifestTests: XCTestCase {
    func testPackagedManifestDeclaresOwnAppPreferencesReason() throws {
        // PlannerUITests also has Bundle.module. Read the production bundle used
        // by the catalog source so a test-only resource cannot satisfy this check.
        let url = try XCTUnwrap(BundledCatalogPreviewSource.resourceBundle.url(
            forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any])
        XCTAssertEqual(Set(manifest.keys), ["NSPrivacyAccessedAPITypes"])
        let declarations = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertEqual(declarations.count, 1)
        let declaration = try XCTUnwrap(declarations.first)
        XCTAssertEqual(Set(declaration.keys), ["NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"])
        XCTAssertEqual(declaration["NSPrivacyAccessedAPIType"] as? String,
                       "NSPrivacyAccessedAPICategoryUserDefaults")
        XCTAssertEqual(declaration["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }
}
