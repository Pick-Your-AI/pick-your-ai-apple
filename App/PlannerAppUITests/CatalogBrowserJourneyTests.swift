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
        let accelerator = app.switches["catalogKind-accelerator"]
        XCTAssertTrue(accelerator.waitForExistence(timeout: 10))
        XCTAssertEqual(accelerator.label, "Accelerator")
        XCTAssertEqual(accelerator.value as? String, "0")
        retainScreenshot(app, name: "Component-kind switch before selection")
        // SwiftUI exposes the whole row as a Switch and includes the visible
        // native switch beneath it. Tap that single control, not the row center.
        let controlTree = XCTAttachment(string: accelerator.debugDescription)
        controlTree.name = "Identified kind row and its native switch"
        controlTree.lifetime = .keepAlways
        add(controlTree)
        let nativeSwitches = accelerator.descendants(matching: .switch)
        XCTAssertEqual(nativeSwitches.count, 1, "The kind row must contain one native switch")
        let nativeAccelerator = nativeSwitches.element
        XCTAssertLessThan(nativeAccelerator.frame.width, accelerator.frame.width)
        XCTAssertTrue(accelerator.frame.contains(nativeAccelerator.frame))
        XCTAssertEqual(nativeAccelerator.value as? String, "0")
        tap(nativeAccelerator)
        // Observe the exact resulting state through the existing bounded helper.
        // Both the native control and its identified row must become selected.
        wait(nativeAccelerator, matching: "value == '1'")
        XCTAssertEqual(nativeAccelerator.value as? String, "1")
        wait(accelerator, matching: "value == '1'")
        XCTAssertEqual(accelerator.value as? String, "1")
        tap(app.buttons["catalogKindFiltersDone"])
        wait(accelerator, matching: "exists == false")
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
        reveal(app.buttons["catalogKinds"], in: app, towardTop: true)
        tap(app.buttons["catalogKinds"])
        XCTAssertTrue(accelerator.waitForExistence(timeout: 10))
        XCTAssertEqual(accelerator.label, "Accelerator")
        XCTAssertEqual(accelerator.value as? String, "1", "The reopened filter control must retain its selected state")
        tap(app.buttons["catalogKindFiltersDone"])
        wait(accelerator, matching: "exists == false")
        let candidate = app.buttons["catalogItem-cat.accelerator.fixture-2026.10-demo"]
        reveal(candidate, in: app, towardTop: false)
        tap(candidate)
        XCTAssertTrue(app.staticTexts["catalogDetailReady"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["catalogDetailReady"].label, "Specifications: 8 · Source records: 1")
        let detailForm = app.descendants(matching: .any).matching(identifier: "catalogDetailsForm").firstMatch
        // LabeledContent exposes each caption and value as one exact label in
        // the observed native snapshot. Require both assessment gaps separately.
        for expected in [
            "Version, 2026.10-demo",
            "Identifier, cat.accelerator.fixture",
            "Compatibility, Unknown",
            "Price estimate, Unknown",
            "Catalog, catalog.fixture.1"
        ] {
            let matches = detailForm.staticTexts.matching(NSPredicate(format: "label == %@", expected))
            let value = matches.element
            reveal(value, in: app, towardTop: false, containerID: "catalogDetailsForm")
            XCTAssertEqual(matches.count, 1, "The detail must expose one exact labeled value: \(expected)")
            XCTAssertEqual(value.label, expected)
        }
        retainScreenshot(app, name: "Exact fictional component and pinned catalog details")
        let versionCount = app.staticTexts["catalogVersionCount"]
        reveal(versionCount, in: app, towardTop: true, containerID: "catalogDetailsForm")
        XCTAssertEqual(versionCount.label, "Recorded versions in this catalog: 1")
        let noOtherVersions = app.staticTexts["catalogVersionsNoOthers"]
        reveal(noOtherVersions, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertEqual(noOtherVersions.label, "No other version of this identifier and kind is recorded in this catalog.")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "catalogRecordedVersion-")).count, 0)
        let hash = app.staticTexts["catalogDetailHash"]
        reveal(hash, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertEqual(hash.label, "2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8")

        // Read the actual schema-derived values and absent optional field. The
        // app supplies its bundled fixture normally; no test source is injected.
        let memory = app.staticTexts["catalogDetailSpecValue-vram_gb"]
        reveal(memory, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertEqual(memory.label, "24")
        let missingPower = app.staticTexts["catalogDetailSpecState-rated_power_w"]
        reveal(missingPower, in: app, towardTop: true, containerID: "catalogDetailsForm")
        XCTAssertEqual(missingPower.label, "Not recorded")
        retainScreenshot(app, name: "Typed accelerator values and an explicit specification gap")
        let declaredStatus = app.staticTexts["catalogDetailSourceStatus-0"]
        reveal(declaredStatus, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertEqual(declaredStatus.label, "user_supplied")
        let checked = app.staticTexts["catalogDetailSourceDate-0"]
        reveal(checked, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertEqual(checked.label, "2026-10-16T09:00:00Z")
        let missingSource = app.staticTexts["catalogDetailSourceMissing-0"]
        reveal(missingSource, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertEqual(missingSource.label, "Source URL not recorded")
        let sourceNotes = app.staticTexts["catalogDetailSourceNotes-0"]
        reveal(sourceNotes, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertEqual(sourceNotes.label, "FICTIONAL TEST FIXTURE. Not vendor specification or commercial pricing.")
        retainScreenshot(app, name: "Retained source declaration, date, missing URL and fictional qualification")

        // The bundled specimen has no source URL. Its normal review control
        // must explain that gap without offering or requesting navigation.
        let reviewSource = app.buttons["catalogSourceReview-0"]
        reveal(reviewSource, in: app, towardTop: false, containerID: "catalogDetailsForm")
        tap(reviewSource)
        let sourceGap = app.staticTexts["catalogSourceReviewMissing"]
        reveal(sourceGap, in: app, towardTop: false, containerID: "catalogDetailsForm")
        XCTAssertEqual(sourceGap.label, "This source record has no URL. No external navigation is available.")
        XCTAssertFalse(app.buttons["catalogSourceConfirm"].exists)
        retainScreenshot(app, name: "Explicit source review retains the missing-URL boundary")
        let closeSource = app.buttons["catalogSourceClose"]
        reveal(closeSource, in: app, towardTop: false, containerID: "catalogDetailsForm")
        tap(closeSource)
        wait(sourceGap, matching: "exists == false")
        XCTAssertTrue(reviewSource.exists)
        XCTAssertEqual(missingSource.label, "Source URL not recorded")
        XCTAssertEqual(checked.label, "2026-10-16T09:00:00Z")
        XCTAssertEqual(declaredStatus.label, "user_supplied")
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
        tapNavigation("Notes", in: app)
        XCTAssertTrue(app.buttons["newDraft"].waitForExistence(timeout: 10))
        // No note or imported build was created, edited, selected or deleted.
    }

    @MainActor
    private func openCatalog(_ app: XCUIApplication) {
        tapNavigation("Demo catalog", in: app)
        XCTAssertTrue(app.textFields["catalogSearch"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func tapNavigation(_ title: String, in app: XCUIApplication) {
        // iOS 18 exposes adaptive iPad tabs as buttons outside a TabBar. Both
        // layouts expose this same visible navigation label; use normal taps.
        tap(app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch)
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
        XCTAssertTrue(element.waitForExistence(timeout: 10),
                      "The requested control did not appear: \(element)")
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
