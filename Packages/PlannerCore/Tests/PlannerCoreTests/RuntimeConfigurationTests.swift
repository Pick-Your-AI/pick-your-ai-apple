import XCTest
@testable import PlannerCore

final class RuntimeConfigurationTests: XCTestCase {
    private func config(_ environment: ClientEnvironment, endpoint: String? = "https://api.example.invalid/v1") throws -> RuntimeConfiguration {
        try RuntimeConfiguration(environment: environment, endpoint: endpoint,
                                 buildIdentity: "synthetic-test-build", contractVersion: "1.0.0")
    }

    func testMissingLiveEndpointNeverFallsBackToPreview() throws {
        for environment in [ClientEnvironment.staging, .production] {
            for endpoint: String? in [nil, ""] {
                XCTAssertThrowsError(try config(environment, endpoint: endpoint)) {
                    XCTAssertEqual($0 as? RuntimeConfigurationError, .missingEndpoint)
                }
            }
        }
    }

    func testPreviewCannotCarryLiveEndpoint() throws {
        let preview = try config(.preview, endpoint: nil)
        XCTAssertNil(preview.endpoint)
        try preview.requireMatchingResponse(.synthetic)
        XCTAssertThrowsError(try config(.preview))
        XCTAssertThrowsError(try preview.requireMatchingResponse(.production))
        XCTAssertThrowsError(try preview.requireMatchingResponse(.staging))
    }

    func testProductionRejectsStagingAndFixtures() throws {
        let production = try config(.production)
        XCTAssertThrowsError(try production.requireMatchingResponse(.synthetic))
        XCTAssertThrowsError(try production.requireMatchingResponse(.staging))
        try production.requireMatchingResponse(.production)
        XCTAssertEqual(production.environment, .production)
        XCTAssertEqual(production.endpoint?.absoluteString, "https://api.example.invalid/v1")
    }

    func testStagingRejectsProductionAndFixtures() throws {
        let staging = try config(.staging)
        XCTAssertThrowsError(try staging.requireMatchingResponse(.synthetic))
        XCTAssertThrowsError(try staging.requireMatchingResponse(.production))
        try staging.requireMatchingResponse(.staging)
    }

    func testUnsafeOrMalformedEndpointsAreRejectedWithoutEchoingInput() throws {
        for endpoint in ["http://api.example.invalid", "file:///tmp/catalog", "/relative", "https://",
                         "https://user:secret@api.example.invalid", "https://api.example.invalid?token=secret",
                         "https://api.example.invalid#secret", "https://api.example.invalid:0", "https://api.example.invalid:65536",
                         "https://api.example.invalid:99999999999999999999999999", "https://api.example.invalid:",
                         "https://api.example.invalid/{x}", "https://api.example.invalid/path\\segment",
                         "https://api.example.invalid/%GG", "https://api.example.invalid/%", "https://api.example.invalid/\u{0}",
                         "https://api.example.invalid/\u{1}", " https://api.example.invalid", "https://api.example.invalid/path with space"] {
            XCTAssertThrowsError(try config(.production, endpoint: endpoint), endpoint) {
                XCTAssertEqual($0 as? RuntimeConfigurationError, .invalidEndpoint)
                XCTAssertFalse(String(describing: $0).contains("secret"))
            }
        }
    }

    func testValidIPv6AndEscapedPathsRemainUnchanged() throws {
        for endpoint in ["https://[::1]:8443/v1", "https://api.example.invalid/%7Bx%7D", "https://api.example.invalid/path%20with%20space"] {
            XCTAssertEqual(try config(.staging, endpoint: endpoint).endpoint?.absoluteString, endpoint)
        }
    }

    func testBuildAndContractIdentityAreRequiredAndDiagnosticsExcludeEndpoint() throws {
        XCTAssertThrowsError(try RuntimeConfiguration(environment: .preview, endpoint: nil,
            buildIdentity: " \n", contractVersion: "1.0.0"))
        for contract in ["", "1", "1.1.0", "2.0.0"] {
            XCTAssertThrowsError(try RuntimeConfiguration(environment: .preview, endpoint: nil,
                buildIdentity: "test", contractVersion: contract))
        }
        let configuration = try config(.production)
        XCTAssertEqual(configuration.diagnostics.environment, .production)
        XCTAssertEqual(configuration.diagnostics.buildIdentity, "synthetic-test-build")
        XCTAssertEqual(configuration.diagnostics.contractVersion, "1.0.0")
        XCTAssertFalse(String(describing: configuration.diagnostics).contains("api.example.invalid"))
    }
}
