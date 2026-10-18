import XCTest
@testable import PlannerCore

final class BundleRuntimeConfigurationTests: XCTestCase {
    private func information(_ environment: String = "preview", endpoint: Any = "") -> [String: Any] {
        let suffix = environment == "preview" ? "localpreview" : environment
        return ["CFBundleIdentifier": "invalid.pickyourai.\(suffix)",
                "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                "PlannerEnvironment": environment, "PlannerServiceEndpoint": endpoint,
                "PlannerContractVersion": "1.0.0"]
    }

    func testExplicitPreviewHasNoEndpointAndExposesOnlyBuildDiagnostics() throws {
        let configuration = try RuntimeConfiguration.fromBundleInfo(information())
        XCTAssertEqual(configuration.environment, .preview)
        XCTAssertNil(configuration.endpoint)
        XCTAssertEqual(configuration.diagnostics.buildIdentity, "0.1.0 (1)")
        XCTAssertEqual(configuration.diagnostics.contractVersion, "1.0.0")
        XCTAssertNoThrow(try configuration.requireMatchingResponse(.synthetic))
        XCTAssertThrowsError(try configuration.requireMatchingResponse(.production))
    }

    func testMissingOrUnrecognizedEnvironmentNeverDefaultsToPreview() {
        let invalid: [Any?] = [nil, "", "Preview", "$(PLANNER_ENVIRONMENT)", "production\n", 1]
        for value in invalid {
            var source = information()
            source["PlannerEnvironment"] = value
            XCTAssertThrowsError(try RuntimeConfiguration.fromBundleInfo(source))
        }
    }

    func testProductionAndStagingRequireTheirOwnBundleIdentityAndEndpoint() throws {
        let missing: [Any?] = [nil, ""]
        for environment in ["staging", "production"] {
            for endpoint in missing {
                var source = information(environment)
                source["PlannerServiceEndpoint"] = endpoint
                XCTAssertThrowsError(try RuntimeConfiguration.fromBundleInfo(source)) { error in
                    XCTAssertEqual(error as? RuntimeConfigurationError, .missingEndpoint)
                }
            }
            let configured = try RuntimeConfiguration.fromBundleInfo(
                information(environment, endpoint: "https://example.invalid/v1"))
            XCTAssertEqual(configured.environment.rawValue, environment)
            XCTAssertThrowsError(try configured.requireMatchingResponse(.synthetic))
            var mismatch = information(environment, endpoint: "https://example.invalid/v1")
            mismatch["CFBundleIdentifier"] = "invalid.pickyourai.localpreview"
            XCTAssertThrowsError(try RuntimeConfiguration.fromBundleInfo(mismatch)) { error in
                XCTAssertEqual(error as? BundleRuntimeConfigurationError, .bundleEnvironmentMismatch)
            }
        }
    }

    func testProductionBundleCannotDeclarePreviewOrStaging() {
        for environment in ["preview", "staging"] {
            var source = information(environment)
            source["CFBundleIdentifier"] = "invalid.pickyourai.production"
            XCTAssertThrowsError(try RuntimeConfiguration.fromBundleInfo(source)) { error in
                XCTAssertEqual(error as? BundleRuntimeConfigurationError, .bundleEnvironmentMismatch)
            }
        }
    }

    func testPreviewCannotAcceptAConfiguredLiveEndpoint() {
        XCTAssertThrowsError(try RuntimeConfiguration.fromBundleInfo(
            information(endpoint: "https://example.invalid/v1"))) { error in
            XCTAssertEqual(error as? RuntimeConfigurationError, .previewEndpointForbidden)
        }
    }

    func testInvalidEndpointValuesAndCredentialsAreRejectedWithoutEchoingInput() {
        let invalid: [Any] = [false, ["url": "https://example.invalid"], "$(PLANNER_ENDPOINT)",
                              "https://private-user:private-password@example.invalid/v1",
                              "https://example.invalid/v1?token=private-token"]
        for value in invalid {
            XCTAssertThrowsError(try RuntimeConfiguration.fromBundleInfo(information("production", endpoint: value))) { error in
                let description = String(describing: error)
                XCTAssertFalse(description.contains("private-"))
                XCTAssertFalse(description.contains("example.invalid"))
                XCTAssertFalse(description.contains("PLANNER_ENDPOINT"))
            }
        }
    }

    func testMissingUnexpandedMalformedOrUnboundedBuildMetadataCannotEnterDiagnostics() {
        let invalid: [Any?] = [nil, "", "$(CURRENT_PROJECT_VERSION)", "private-token", "1\n", "1.2.3.4", "1234567890", 1]
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            for value in invalid {
                var source = information()
                source[key] = value
                XCTAssertThrowsError(try RuntimeConfiguration.fromBundleInfo(source)) { error in
                    XCTAssertEqual(error as? BundleRuntimeConfigurationError, .invalidBuildMetadata)
                }
            }
        }
    }

    func testAbsentOrDifferentContractDoesNotUseAPreviewDefault() {
        let invalid: [Any?] = [nil, "", "$(PLANNER_CONTRACT_VERSION)", "2.0.0", 1]
        for value in invalid {
            var source = information()
            source["PlannerContractVersion"] = value
            XCTAssertThrowsError(try RuntimeConfiguration.fromBundleInfo(source)) { error in
                XCTAssertEqual(error as? RuntimeConfigurationError, .unsupportedContractVersion)
            }
        }
    }
}
