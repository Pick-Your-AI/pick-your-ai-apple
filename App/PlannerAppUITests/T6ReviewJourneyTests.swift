import XCTest

/// Receiver integration contract. The existing Imported-builds test host must
/// seed the three labelled fixture artifacts for the named scenario, retain the
/// original Build identity, and enter through the actual library navigation.
/// The donor did not register or execute these methods. The receiving app now
/// mounts the same assertions; actual native results retain their own identity.
final class T6ReviewJourneyTests: XCTestCase {
    @MainActor private func open(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--t6-journey-fixture", scenario]
        app.launch()
        // The adaptive iPad layout exposes this navigation as a normal Button,
        // as in the existing catalog and Files-cancellation journeys.
        let library = app.buttons["Imported builds"]
        XCTAssertTrue(library.waitForExistence(timeout: 10)); library.tap()
        let record = app.buttons["SYNTHETIC T6 review fixture"]
        XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
        let destination = app.buttons["T6 review"]
        let form = app.descendants(matching: .any).matching(identifier: "importedBuildsForm").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        for _ in 0..<6 where !destination.isHittable { form.swipeUp() }
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertTrue(destination.isHittable); destination.tap()
        XCTAssertTrue(app.scrollViews["t6-review"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor func testAbsentQualityIsVisibleAfterReportedCompatibilityAndDismissal() {
        let app = open("quality-absent")
        XCTAssertEqual(app.staticTexts["t6-compatibility"].label, "Reported compatibility: valid")
        XCTAssertTrue(app.staticTexts["t6-quality-status"].label.contains("not supplied"))
        XCTAssertEqual(app.staticTexts["t6-approval-unknown"].label, "Approval is not established.")
        XCTAssertTrue(app.staticTexts["t6-plan-status"].label.contains("No deployment declaration"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["T6 review"].waitForExistence(timeout: 5))
        app.buttons["T6 review"].tap()
        app.buttons["t6-retry"].tap()
        XCTAssertTrue(app.staticTexts["t6-quality-status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["t6-quality-status"].label.contains("not supplied"))
    }

    @MainActor func testReportedFailureAndPendingPlanRemainVisibleWithoutDeploymentAction() {
        let app = open("quality-failed-proposed")
        XCTAssertTrue(app.staticTexts["t6-quality-status"].label.contains("failed"))
        XCTAssertTrue(app.staticTexts["t6-approval-unknown"].exists)
        let scroll = app.scrollViews["t6-review"]
        for _ in 0..<6 where !app.staticTexts["t6-plan-status"].isHittable { scroll.swipeUp() }
        XCTAssertTrue(app.staticTexts["t6-plan-status"].label.contains("approvals and references remain unverified"))
        XCTAssertTrue(app.staticTexts["t6-local-pair"].exists)
        XCTAssertFalse(app.buttons["Deploy"].exists)
        XCTAssertFalse(app.buttons["Share private plan"].exists)
    }
}
