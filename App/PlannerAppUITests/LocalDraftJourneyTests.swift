import XCTest
import UIKit

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

        // Repeat the production autosave path so cold relaunch reads the latest
        // acknowledged revision, rather than the initially created empty draft.
        let addition = "\nSecond acknowledged revision."
        app.textViews["draftNotes"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        app.textViews["draftNotes"].typeText(addition)
        let revisedNotes = notes + addition
        XCTAssertEqual(app.textViews["draftNotes"].value as? String, revisedNotes)
        autosaveAndClose(app)
        app.terminate()
        app.launch()

        // Termination follows a clean close. Reopening the same record after a
        // fresh app process establishes durable text, not retained editor state.
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: title, notes: revisedNotes)
        retainScreenshot(app, name: "Latest notes reopened after process relaunch")

        // One input character creates one undo state. Its position may depend on
        // the current caret, but every original character must remain intact.
        let titleField = app.textFields["draftTitle"]
        tap(titleField)
        titleField.typeText("!")
        let renamedTitle = titleField.value as? String ?? ""
        XCTAssertEqual(renamedTitle.utf8.count, title.utf8.count + 1)
        XCTAssertEqual(renamedTitle.replacingOccurrences(of: "!", with: ""), title)
        awaitAutosaveAcknowledgement(app)
        let renamedRevision = newestSavedRevision(app, title: renamedTitle)

        reveal(app.buttons["undoDraftEdit"], in: app, towardTop: true)
        tap(app.buttons["undoDraftEdit"])
        reveal(titleField, in: app, towardTop: true)
        XCTAssertEqual(titleField.value as? String, title)
        awaitAutosaveAcknowledgement(app)
        assertSavedRevision(app, revision: renamedRevision + 1, title: title)
        reveal(app.buttons["redoDraftEdit"], in: app, towardTop: true)
        tap(app.buttons["redoDraftEdit"])
        reveal(titleField, in: app, towardTop: true)
        XCTAssertEqual(titleField.value as? String, renamedTitle)
        awaitAutosaveAcknowledgement(app)
        assertSavedRevision(app, revision: renamedRevision + 2, title: renamedTitle)
        autosaveAndClose(app)
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: renamedTitle, notes: revisedNotes)
        retainScreenshot(app, name: "Undo and redo autosaves reopened from durable revisions")

        // Paste one invalid amendment through the standard edit menu. Its 1025
        // ASCII bytes exceed the actual store's 1024-byte title boundary, so the
        // real debounce must fail before this input can be explicitly discarded.
        // This keeps the production timer enabled without racing it to Close.
        XCTAssertFalse(app.staticTexts["editorNotice"].exists)
        pasteOversizedTitle(app)
        let unsaved = "\nUnsaved synthetic amendment."
        reveal(app.textViews["draftNotes"], in: app, towardTop: false)
        app.textViews["draftNotes"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        app.textViews["draftNotes"].typeText(unsaved)
        XCTAssertEqual(app.textViews["draftNotes"].value as? String, revisedNotes + unsaved)
        reveal(app.staticTexts["editorNotice"], in: app, towardTop: false)
        XCTAssertTrue(app.staticTexts["editorNotice"].waitForExistence(timeout: 10),
                      "Actual autosave must reject the over-limit title")
        wait(app.buttons["saveDraft"], matching: "enabled == true")
        tap(app.buttons["Close"])
        tap(app.buttons["Discard changes"])
        wait(app.textFields["draftTitle"], matching: "exists == false")
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: renamedTitle, notes: revisedNotes)
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
        autosaveAndClose(app)
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
    private func awaitAutosaveAcknowledgement(_ app: XCUIApplication) {
        let save = app.buttons["saveDraft"]
        let close = app.buttons["Close"]
        // Disabled Save alone also describes an in-flight write. Wait until
        // Close is enabled again, then require Save to remain disabled: the
        // model is idle and has acknowledged these edits through its real timer.
        // Callers also reopen the record or read its exact durable history row;
        // an old clean-state display cannot substitute for persistence evidence.
        wait(save, matching: "enabled == false")
        wait(close, matching: "enabled == true")
        XCTAssertFalse(save.isEnabled, "Production autosave must acknowledge all edits")
    }

    @MainActor
    private func autosaveAndClose(_ app: XCUIApplication) {
        awaitAutosaveAcknowledgement(app)
        app.buttons["Close"].tap()
        wait(app.textFields["draftTitle"], matching: "exists == false")
    }

    @MainActor
    private func newestSavedRevision(_ app: XCUIApplication, title: String) -> Int {
        let load = app.buttons["loadRevisions"]
        reveal(load, in: app, towardTop: false)
        tap(load)
        let rows = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "revisionTitle-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let revisions = rows.allElementsBoundByIndex.compactMap {
            Int($0.identifier.dropFirst("revisionTitle-".count))
        }
        guard let latest = revisions.max() else { XCTFail("No durable revision title was loaded"); return 0 }
        XCTAssertEqual(app.staticTexts["revisionTitle-\(latest)"].label, title)
        return latest
    }

    @MainActor
    private func assertSavedRevision(_ app: XCUIApplication, revision: Int, title: String) {
        let load = app.buttons["loadRevisions"]
        reveal(load, in: app, towardTop: false)
        tap(load)
        // The required next revision was absent from the preceding history load.
        // Its exact title therefore proves a new durable undo/redo acknowledgement.
        let row = app.staticTexts["revisionTitle-\(revision)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.label, title)
    }

    @MainActor
    private func pasteOversizedTitle(_ app: XCUIApplication) {
        let field = app.textFields["draftTitle"]
        reveal(field, in: app, towardTop: true)
        tap(field)
        // Only synthetic text on the runner's newly created owned simulator.
        // Clipboard input does not seed or replace application storage.
        UIPasteboard.general.string = String(repeating: "x", count: 1_025)
        defer { UIPasteboard.general.items = [] }
        field.press(forDuration: 1.2)
        let menuPaste = app.menuItems["Paste"]
        let buttonPaste = app.buttons["Paste"]
        if menuPaste.waitForExistence(timeout: 2) { tap(menuPaste) }
        else { tap(buttonPaste) }
        let pastedTitle = field.value as? String ?? ""
        XCTAssertGreaterThan(pastedTitle.utf8.count, 1_024)
        dismissKeyboardGestureIntroductionIfPresent(app)
        XCTAssertEqual(field.value as? String, pastedTitle,
                       "Dismissing the system introduction must preserve the pasted amendment")
    }

    @MainActor
    private func dismissKeyboardGestureIntroductionIfPresent(_ app: XCUIApplication) {
        // A fresh iPad may cover its keyboard after the first system Paste with
        // an automatically rotating gesture tutorial. Recognize its exact
        // instructional copy before using Continue; unrelated dialogs still fail.
        let introduction = app.staticTexts.matching(NSPredicate(format: "label IN %@", [
            "Double-tap with three fingers.",
            "Double-tap with three fingers.\n",
            // The retained query snapshot exposes the raw newline as one space.
            "Double-tap with three fingers. ",
            "Swipe left with three fingers to undo and swipe right to redo.",
            "Pinch and spread with three fingers to copy and paste a selection."
        ])).firstMatch
        guard introduction.waitForExistence(timeout: 3) else { return }
        retainScreenshot(app, name: "System keyboard gesture introduction after synthetic paste")
        let continueButton = app.buttons["Continue"]
        tap(continueButton)
        wait(continueButton, matching: "exists == false")
        wait(introduction, matching: "exists == false")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool) {
        // Finish text entry through the editor's normal keyboard control before
        // asking the Form to reveal content that the software keyboard obscures.
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            tap(app.buttons["finishDraftEditing"])
            wait(keyboard, matching: "exists == false")
        }
        // The library List remains in the hierarchy behind the editor sheet.
        // Scroll only this editor Form, never the first hittable collection.
        let container = app.descendants(matching: .any).matching(identifier: "draftEditorForm").firstMatch
        XCTAssertTrue(container.waitForExistence(timeout: 10), "The editor Form must be present")
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            guard container.isHittable else { XCTFail("The editor Form must be hittable"); return }
            if towardTop { container.swipeDown() } else { container.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal the control in the editor Form")
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
