import XCTest

/// Receiver integration contract. The existing Imported-builds test host must
/// seed the three labelled fixture artifacts for the named scenario, retain the
/// original Build identity, and enter through the actual library navigation.
/// These methods are not registered or claimed as executed by a source donor.
final class T6ReviewJourneyTests: XCTestCase {
    @MainActor private func open(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--t6-journey-fixture", scenario]
        app.launch()
        let library = app.tabBars.buttons["Imported builds"]
        XCTAssertTrue(library.waitForExistence(timeout: 10)); library.tap()
        let record = app.buttons["SYNTHETIC T6 review fixture"]
        XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
        let destination = app.buttons["T6 review"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); destination.tap()
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

    @MainActor func testReportDisclosurePreviewAndFilesCancellationKeepThePrivatePlan() {
        let app = open("quality-failed-proposed")
        let scroll = app.scrollViews["t6-review"]
        let previewButton = app.buttons["t6-preview-report"]
        for _ in 0..<12 where !previewButton.isHittable { scroll.swipeUp() }
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5)); previewButton.tap()
        let preview = app.staticTexts["t6-report-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.label.hasPrefix("PROPOSED DEPLOYMENT PLAN"))
        XCTAssertTrue(preview.label.contains("Lock \"pricebook_id\": \"prices.fixture.1\""))
        XCTAssertFalse(preview.label.contains("user.fixture"))
        XCTAssertFalse(preview.label.contains("SYNTHETIC private owner note"))
        let disclosure = app.switches["t6-report-disclosure"]
        let save = app.buttons["t6-save-report"]
        for _ in 0..<12 where !disclosure.isHittable { scroll.swipeUp() }
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        disclosure.tap()
        XCTAssertTrue(save.isEnabled); save.tap()
        // Exercise the real system presentation. Missing receiver/Files behavior
        // fails this journey; no injected success or test-only save is accepted.
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        let notice = app.staticTexts["t6-notice"]
        for _ in 0..<12 where !notice.isHittable { scroll.swipeDown() }
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertEqual(notice.label, "Plan report export was cancelled. No save was confirmed; the retained declarations were not changed.")
        XCTAssertFalse(app.staticTexts["t6-report-preview"].exists)
        XCTAssertFalse(app.buttons["Deploy"].exists)
    }
}
