import XCTest

final class LocalDraftJourneyTests: XCTestCase {
    /// Uses only normal UI and newly created synthetic drafts. No launch-time
    /// storage replacement, seeding, reset, uninstall, or pre-existing-row edits.
    @MainActor
    func testSavedNotesSurviveCloseReopenAndRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // A prior normal session may restore an editor. Close only a clean one;
        // never discard or save an unrelated draft on behalf of this test.
        if app.textFields["draftTitle"].exists {
            XCTAssertFalse(app.buttons["saveDraft"].isEnabled, "An existing draft must be clean")
            tap(app.buttons["Close"])
        }
        let title = "UI-Journey-\(UUID().uuidString)"
        let notes = "Synthetic local draft.\nSaved by the UI journey."
        let recordIdentifier = createDraft(app, title: title, notes: notes)
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: title, notes: notes)
        retainScreenshot(app, name: "Saved notes reopened from library")

        // Repeat the edit/save path so the cold relaunch must read the latest
        // acknowledged revision, rather than the initially created empty draft.
        let addition = "\nSecond acknowledged revision."
        app.textViews["draftNotes"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        app.textViews["draftNotes"].typeText(addition)
        let revisedNotes = notes + addition
        XCTAssertEqual(app.textViews["draftNotes"].value as? String, revisedNotes)
        saveAndClose(app)
        app.terminate()
        app.launch()

        // Termination follows a clean close. Reopening the same record after a
        // fresh app process establishes durable text, not retained editor state.
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: title, notes: revisedNotes)
        retainScreenshot(app, name: "Latest notes reopened after process relaunch")

        // Discard only a new unsaved amendment to our own synthetic record.
        let unsaved = "\nUnsaved synthetic amendment."
        app.textViews["draftNotes"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        app.textViews["draftNotes"].typeText(unsaved)
        XCTAssertEqual(app.textViews["draftNotes"].value as? String, revisedNotes + unsaved)
        wait(app.buttons["saveDraft"], matching: "enabled == true")
        tap(app.buttons["Close"])
        tap(app.buttons["Discard changes"])
        wait(app.textFields["draftTitle"], matching: "exists == false")
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: title, notes: revisedNotes)
        retainScreenshot(app, name: "Unsaved amendment discarded, committed notes preserved")

        tap(app.buttons["Close"])
        // A separately saved control must survive deletion and cold loading.
        // An empty failed load or filtered corrupt row must never prove deletion.
        let controlTitle = "UI-Control-\(UUID().uuidString)"
        let controlNotes = "Synthetic control. Preserve this draft when deleting the other one."
        let controlIdentifier = createDraft(app, title: controlTitle, notes: controlNotes)
        XCTAssertNotEqual(controlIdentifier, recordIdentifier)
        assertLoadedLibrary(app, controlIdentifier: controlIdentifier)

        // Delete only the exact test-created target, never the first row or the
        // app container. The separately created control remains available.
        let createdRecord = app.buttons[recordIdentifier]
        XCTAssertTrue(createdRecord.waitForExistence(timeout: 10))
        wait(createdRecord, matching: "hittable == true AND enabled == true")
        createdRecord.press(forDuration: 1.2)
        tap(app.buttons["Delete"])
        tap(app.buttons["Delete draft"])
        wait(createdRecord, matching: "exists == false")
        assertLoadedLibrary(app, controlIdentifier: controlIdentifier)
        XCTAssertFalse(createdRecord.exists)
        retainScreenshot(app, name: "Test-created draft deleted through confirmation")
        app.terminate()
        app.launch()
        assertLoadedLibrary(app, controlIdentifier: controlIdentifier)
        XCTAssertFalse(app.buttons[recordIdentifier].exists, "Deletion must survive a successful process reload")
        tap(app.buttons[controlIdentifier])
        assertEditor(app, title: controlTitle, notes: controlNotes)
        retainScreenshot(app, name: "Independent control survived deletion and process relaunch")
        tap(app.buttons["Close"])
        // The control is removed only with this run's owned simulator cleanup.
    }

    @MainActor
    private func createDraft(_ app: XCUIApplication, title: String, notes: String) -> String {
        tap(app.buttons["newDraft"])
        let titleField = app.textFields["draftTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        XCTAssertEqual(titleField.value as? String, "Untitled draft")
        // The short default title fits in the field. Tap its trailing edge to
        // place the insertion point after it before deleting the default text.
        titleField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Untitled draft".count))
        titleField.typeText(title)
        XCTAssertEqual(titleField.value as? String, title)
        let notesField = app.textViews["draftNotes"]
        tap(notesField)
        notesField.typeText(notes)
        XCTAssertEqual(notesField.value as? String, notes)
        saveAndClose(app)
        let createdRow = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(createdRow.waitForExistence(timeout: 10))
        let recordIdentifier = createdRow.identifier
        XCTAssertTrue(recordIdentifier.hasPrefix("draft-"))
        return recordIdentifier
    }

    @MainActor
    private func assertLoadedLibrary(_ app: XCUIApplication, controlIdentifier: String) {
        // Positive evidence that the library actually loaded persisted records.
        XCTAssertTrue(app.buttons[controlIdentifier].waitForExistence(timeout: 10),
                      "The independently saved control must be loaded")
        wait(app.buttons["newDraft"], matching: "enabled == true")
        XCTAssertFalse(app.staticTexts["operationNotice"].exists, "Library operations must not report failure")
        XCTAssertFalse(app.staticTexts["corruptionNotice"].exists, "Unreadable drafts must not be mistaken for deletion")
    }

    @MainActor
    private func saveAndClose(_ app: XCUIApplication) {
        let save = app.buttons["saveDraft"]
        let close = app.buttons["Close"]
        wait(save, matching: "enabled == true")
        save.tap()
        // Disabled Save alone also describes an in-flight write. Wait until
        // Close is enabled again, then require Save to remain disabled: the
        // model is no longer busy and has acknowledged these exact edits.
        wait(save, matching: "enabled == false")
        wait(close, matching: "enabled == true")
        XCTAssertFalse(save.isEnabled, "Save must acknowledge all edits before closing")
        close.tap()
        wait(app.textFields["draftTitle"], matching: "exists == false")
    }

    @MainActor
    private func assertEditor(_ app: XCUIApplication, title: String, notes: String) {
        XCTAssertTrue(app.textFields["draftTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textViews["draftNotes"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["draftTitle"].value as? String, title)
        XCTAssertEqual(app.textViews["draftNotes"].value as? String, notes)
        XCTAssertFalse(app.buttons["saveDraft"].isEnabled)
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
