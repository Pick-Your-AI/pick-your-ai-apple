import XCTest

final class CatalogBrowserJourneyTests: XCTestCase {
    /// Browse only the app's visibly synthetic fixture through normal controls.
    /// Preference restoration uses a process relaunch; no launch-time state,
    /// storage replacement, arbitrary source injection or draft writes are used.
    @MainActor
    func testCatalogFiltersPaginationAndPinnedDetailsSurviveRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        openCatalog(app)
        wait(app.staticTexts["catalogQualification"], matching: "exists == true")
        let clear = app.buttons["catalogClearFilters"]
        if clear.isEnabled {
            reveal(clear, in: app, towardTop: false)
            tap(clear)
        }
        assertCount(app, "Showing 25 of 29 results")

        // Exercise the actual search binding and keyboard dismissal, then combine
        // the query with a kind and a sort. Unknown assessments remain explicit.
        let search = app.textFields["catalogSearch"]
        reveal(search, in: app, towardTop: true)
        tap(search)
        search.typeText("FICTIONAL\n")
        wait(app.keyboards.firstMatch, matching: "exists == false")
        let kindSort = app.segmentedControls["catalogSort"].buttons["Kind"]
        reveal(kindSort, in: app, towardTop: false)
        tap(kindSort)
        reveal(app.buttons["catalogKinds"], in: app, towardTop: false)
        tap(app.buttons["catalogKinds"])
        tap(app.buttons["catalogKind-accelerator"])
        assertCount(app, "Showing 1 of 1 results")
        XCTAssertEqual(app.staticTexts["catalogActiveKinds"].label, "Accelerator")
        XCTAssertTrue(kindSort.isSelected)
        retainScreenshot(app, name: "Combined catalog query, kind and ordering")

        // Reconstruct both the process and view. Saved filters, not in-memory
        // model state or a cursor, must produce the same exact candidate again.
        app.terminate()
        app.launch()
        openCatalog(app)
        XCTAssertEqual(app.textFields["catalogSearch"].value as? String, "FICTIONAL")
        XCTAssertTrue(app.segmentedControls["catalogSort"].buttons["Kind"].isSelected)
        assertCount(app, "Showing 1 of 1 results")
        XCTAssertEqual(app.staticTexts["catalogActiveKinds"].label, "Accelerator")
        let candidate = app.buttons["catalogItem-cat.accelerator.fixture-2026.10-demo"]
        reveal(candidate, in: app, towardTop: false)
        tap(candidate)
        let identifier = app.staticTexts["cat.accelerator.fixture"]
        reveal(identifier, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertTrue(identifier.exists)
        XCTAssertTrue(app.staticTexts["2026.10-demo"].exists)
        let unknown = app.staticTexts.matching(identifier: "Unknown").firstMatch
        reveal(unknown, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertTrue(unknown.exists)
        let source = app.staticTexts["catalog.fixture.1"]
        reveal(source, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertTrue(source.exists)
        retainScreenshot(app, name: "Exact fictional component and pinned catalog details")
        tap(app.buttons["Done"])

        // Clear-all restores the first bounded page. Loading the continuation
        // reaches the exact whole-fixture count without changing filter state.
        reveal(clear, in: app, towardTop: true)
        tap(clear)
        assertCount(app, "Showing 25 of 29 results")
        let more = app.buttons["catalogLoadMore"]
        reveal(more, in: app, towardTop: false)
        tap(more)
        assertCount(app, "Showing 29 of 29 results", towardTop: true)
        XCTAssertFalse(more.exists)
        XCTAssertFalse(app.staticTexts["catalogNotice"].exists)
        retainScreenshot(app, name: "All 29 synthetic catalog rows loaded through pagination")

        // Empty successful search is visibly different from failure. Restore
        // defaults through the same UI without removing unrelated preferences.
        reveal(search, in: app, towardTop: true)
        tap(search)
        search.typeText("No-match-\(UUID().uuidString)\n")
        wait(app.keyboards.firstMatch, matching: "exists == false")
        assertCount(app, "Showing 0 of 0 results")
        XCTAssertTrue(app.staticTexts["catalogEmpty"].exists)
        XCTAssertFalse(app.staticTexts["catalogNotice"].exists)
        retainScreenshot(app, name: "Explicit empty catalog search")
        reveal(clear, in: app, towardTop: true)
        tap(clear)
        assertCount(app, "Showing 25 of 29 results")
        tap(app.tabBars.buttons["Notes"])
        XCTAssertTrue(app.buttons["newDraft"].waitForExistence(timeout: 10))
        // No note or imported build was created, edited, selected or deleted.
    }

    @MainActor
    private func openCatalog(_ app: XCUIApplication) {
        tap(app.tabBars.buttons["Demo catalog"])
        XCTAssertTrue(app.textFields["catalogSearch"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func assertCount(_ app: XCUIApplication, _ expected: String, towardTop: Bool = false) {
        let count = app.staticTexts["catalogResultCount"]
        reveal(count, in: app, towardTop: towardTop)
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
                       "Catalog count did not become \(expected)")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool,
                        containerID: String = "catalogList") {
        let container = app.descendants(matching: .any).matching(identifier: containerID).firstMatch
        XCTAssertTrue(container.waitForExistence(timeout: 10))
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            guard container.isHittable else { XCTFail("Catalog container is not hittable"); return }
            if towardTop { container.swipeDown() } else { container.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element.identifier)")
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        wait(element, matching: "hittable == true AND enabled == true")
        element.tap()
    }

    @MainActor
    private func wait(_ element: XCUIElement, matching predicate: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
                       "Timed out waiting for \(element.identifier): \(predicate)")
    }

    @MainActor
    private func retainScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
