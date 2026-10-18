import XCTest

/// Drives the installed simulator application; no storage mocks, launch backdoors,
/// injected records, or direct database access substitute for the visible journey.
@MainActor
final class DraftJourneyTests: XCTestCase {
    func testSavedNotesSurviveRelaunchAndExplicitDiscardThenDelete() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let create = app.buttons["newDraft"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        create.tap()

        let notes = app.textViews["draftNotes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        let savedText = "Synthetic UI journey " + UUID().uuidString
        notes.tap()
        notes.typeText(savedText)
        app.buttons["saveDraft"].tap()
        let status = app.staticTexts["saveStatus"]
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Saved locally"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        XCTAssertEqual(notes.value as? String, savedText)
        retainScreenshot(app, name: "saved-note")

        // Only acknowledged bytes are expected to survive. This does not claim
        // termination during an unacknowledged autosave is lossless.
        app.terminate()
        app.launch()
        openSavedDraftIfNecessary(app)
        XCTAssertEqual(app.textViews["draftNotes"].value as? String, savedText)
        retainScreenshot(app, name: "reopened-after-termination")

        let reopenedNotes = app.textViews["draftNotes"]
        reopenedNotes.tap()
        reopenedNotes.typeText("\nUnsaved synthetic amendment")
        XCTAssertTrue((reopenedNotes.value as? String)?.contains("Unsaved synthetic amendment") == true)
        app.buttons["Close"].tap()
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10))
        discard.tap()
        openSavedDraftIfNecessary(app)
        XCTAssertEqual(app.textViews["draftNotes"].value as? String, savedText)

        app.buttons["Close"].tap()
        let row = draftRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1.2)
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        let confirmDelete = app.buttons["Delete draft"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 10))
        confirmDelete.tap()
        XCTAssertTrue(app.staticTexts["No local drafts yet"].waitForExistence(timeout: 10))
        retainScreenshot(app, name: "confirmed-deletion")
    }

    private func openSavedDraftIfNecessary(_ app: XCUIApplication) {
        // Scene restoration may reopen the sheet; otherwise navigate explicitly.
        // Both paths verify durable contents, without claiming scene restoration.
        if app.textViews["draftNotes"].waitForExistence(timeout: 3) { return }
        let row = draftRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.textViews["draftNotes"].waitForExistence(timeout: 10))
    }

    private func draftRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "draft-")).firstMatch
    }

    private func retainScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
