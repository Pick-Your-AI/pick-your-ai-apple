import XCTest

/// Select the one native tab leaf while keeping the journey's own destination
/// assertions authoritative. iPad exposes a same-label Button wrapper and leaf.
enum LibraryTabJourney {
    @MainActor
    static func select(_ title: String, in app: XCUIApplication,
                       timeout: TimeInterval = 10,
                       file: StaticString = #filePath, line: UInt = #line) {
        let label = NSPredicate(format: "label == %@", title)
        let matches = app.buttons.matching(label)
        guard matches.firstMatch.waitForExistence(timeout: timeout) else {
            XCTFail("The library tab did not appear: \(title)", file: file, line: line)
            return
        }
        let leaves = matches.allElementsBoundByIndex.filter {
            $0.descendants(matching: .button).matching(label).count == 0
        }
        guard leaves.count == 1, let tab = leaves.first else {
            XCTFail("Expected one library tab leaf for \(title), found \(leaves.count)",
                    file: file, line: line)
            return
        }
        let available = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true AND enabled == true"),
            object: tab)
        guard XCTWaiter.wait(for: [available], timeout: timeout) == .completed else {
            XCTFail("The library tab is not hittable and enabled: \(title)",
                    file: file, line: line)
            return
        }
        // The retained iPad event was already centered. Keep one activation and
        // all caller postconditions; the longer press still needs a native run.
        tab.press(forDuration: 0.2)
    }
}

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
        LibraryTabJourney.select("Imported builds", in: app)
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
        guard disclosure.waitForExistence(timeout: 5) else {
            XCTFail("The report disclosure must be present"); return
        }
        XCTAssertFalse(save.isEnabled)
        guard !save.isEnabled else { XCTFail("Save must remain disabled before disclosure activation"); return }
        // SwiftUI exposes an identified row and a separate intrinsic switch.
        // Activate exactly one leaf inside this disclosure, never the row label.
        let descendants = disclosure.descendants(matching: .switch).allElementsBoundByIndex
        let leaves = descendants.filter { $0.descendants(matching: .switch).count == 0 }
        let control: XCUIElement
        if descendants.isEmpty {
            control = disclosure
        } else {
            guard leaves.count == 1 else {
                XCTFail("The report disclosure must have one intrinsic switch"); return
            }
            control = leaves[0]
        }
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: control)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed,
              (control.value as? String) == "0" else {
            XCTFail("The report disclosure must be ready and off before its single activation"); return
        }
        control.tap()
        let reviewed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"), object: control)
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: save)
        guard XCTWaiter.wait(for: [reviewed, enabled], timeout: 5) == .completed,
              (control.value as? String) == "1", save.isEnabled else {
            XCTFail("The disclosure must switch on and enable Save before opening Files"); return
        }
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

    @MainActor func testLeavingImportedBuildsWithdrawsReportPreviewAndReopensRetainedInputs() {
        let app = open("quality-failed-proposed")
        let scroll = app.scrollViews["t6-review"]
        let previewButton = app.buttons["t6-preview-report"]
        for _ in 0..<12 where !previewButton.isHittable { scroll.swipeUp() }
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5)); previewButton.tap()
        XCTAssertTrue(app.staticTexts["t6-report-preview"].waitForExistence(timeout: 5))
        LibraryTabJourney.select("Notes", in: app, timeout: 5)
        LibraryTabJourney.select("Imported builds", in: app, timeout: 5)
        let form = app.descendants(matching: .any).matching(identifier: "importedBuildsForm").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["t6-review"].exists)
        XCTAssertFalse(app.staticTexts["t6-report-preview"].exists)
        let destination = app.buttons["openT6Review"]
        for _ in 0..<6 where !destination.isHittable { form.swipeUp() }
        XCTAssertTrue(destination.isHittable); destination.tap()
        let retry = app.buttons["t6-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        let quality = app.staticTexts["t6-quality-status"]
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        XCTAssertTrue(quality.label.contains("failed"))
        for _ in 0..<6 where !app.staticTexts["t6-plan-status"].isHittable { scroll.swipeUp() }
        XCTAssertTrue(app.staticTexts["t6-plan-status"].label.contains("approvals and references remain unverified"))
        XCTAssertTrue(app.staticTexts["t6-local-pair"].exists)
        XCTAssertFalse(app.staticTexts["t6-report-preview"].exists)
        XCTAssertFalse(app.buttons["Deploy"].exists)
    }
}
