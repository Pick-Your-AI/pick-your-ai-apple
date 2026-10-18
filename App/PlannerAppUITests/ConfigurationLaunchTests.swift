import XCTest

final class ConfigurationLaunchTests: XCTestCase {
    /// The runner builds the actual Staging or Release configuration, with its
    /// own bundle ID and the repository's intentionally absent live endpoint.
    /// No launch override, substitute bundle or response fixture is injected.
    @MainActor
    func testMissingEndpointStopsStartupWithoutPreviewFallback() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        assertMissingEndpoint(app)
        retainScreenshot(app, name: "Missing live endpoint fails visibly at cold start")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.state == .runningBackgroundSuspended,
                      "The application must actually enter the OS background")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        assertMissingEndpoint(app)
        retainScreenshot(app, name: "Invalid configuration remains blocked after foreground recovery")

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launch()
        assertMissingEndpoint(app)
        retainScreenshot(app, name: "Invalid configuration remains blocked after process relaunch")
    }

    @MainActor
    private func assertMissingEndpoint(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["configurationFailure"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["configurationFailure"].label, "App configuration unavailable")
        XCTAssertEqual(app.staticTexts["configurationFailureDetails"].label,
                       "This build requires a service endpoint. Install a correctly configured build. Local drafts have not been opened.")
        XCTAssertFalse(app.buttons["newDraft"].exists, "Invalid configuration must not open preview libraries")
        XCTAssertFalse(app.buttons["Demo catalog"].exists, "Invalid configuration must not expose the synthetic catalog")
        XCTAssertFalse(app.staticTexts["runtimeDiagnostics"].exists, "A rejected build cannot report a ready environment")
        XCTAssertFalse(app.textFields["draftTitle"].exists)
    }

    @MainActor
    private func retainScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
