import XCTest

final class LocalDraftJourneyTests: XCTestCase {
    /// Uses only normal UI and a newly created synthetic draft. No launch-time
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
        tap(app.buttons["newDraft"])
        let title = "UI-Journey-\(UUID().uuidString)"
        let notes = "Synthetic local draft.\nSaved by the UI journey."
        let titleField = app.textFields["draftTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        XCTAssertEqual(titleField.value as? String, "Untitled draft")
        // The new draft's short default title fits in the field. Tap its trailing
        // edge to put the insertion point after it before deleting that text.
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
        tap(createdRow)
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
        tap(app.buttons["Close"])
        XCTAssertTrue(app.buttons[recordIdentifier].waitForExistence(timeout: 10))
        // Leave only this uniquely titled synthetic record. Do not clean the
        // application container or delete any existing user data.
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
