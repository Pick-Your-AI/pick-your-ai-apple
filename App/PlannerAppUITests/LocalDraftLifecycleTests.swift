import XCTest
import UIKit

final class LocalDraftLifecycleTests: XCTestCase {
    /// Normal UI on this run's owned simulator. No storage seeding, reset,
    /// clock replacement or unrelated draft mutation is used.
    @MainActor
    func testBackgroundRecoveryAndCancelledDiscardPreserveOwnDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.textFields["draftTitle"].exists {
            XCTAssertFalse(app.buttons["saveDraft"].isEnabled, "An existing editor must be clean")
            tap(app.buttons["Close"])
        }

        let title = "UI-Lifecycle-\(UUID().uuidString)"
        let initialNotes = "Synthetic lifecycle control."
        tap(app.buttons["newDraft"])
        let titleField = app.textFields["draftTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        XCTAssertEqual(titleField.value as? String, "Untitled draft")
        titleField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Untitled draft".count))
        titleField.typeText(title)
        tap(app.textViews["draftNotes"])
        app.textViews["draftNotes"].typeText(initialNotes)
        awaitAutosave(app)
        tap(app.buttons["Close"])
        wait(titleField, matching: "exists == false")
        let row = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let recordIdentifier = row.identifier
        XCTAssertTrue(recordIdentifier.hasPrefix("draft-"))

        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: title, notes: initialNotes)
        let amendment = "\nForeground/background amendment."
        let notesField = app.textViews["draftNotes"]
        notesField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        notesField.typeText(amendment)
        let revisedNotes = initialNotes + amendment
        XCTAssertEqual(notesField.value as? String, revisedNotes)
        // Do not await Save, Close, or the autosave acknowledgement before Home.
        // OS scheduling may still allow debounce to finish; this test does not
        // claim that it forced a particular ordering of those two save triggers.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.state == .runningBackgroundSuspended,
                      "The application must actually enter the OS background")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        assertEditor(app, title: title, notes: revisedNotes)
        retainScreenshot(app, name: "Same draft restored after an actual OS background transition")
        awaitAutosave(app)
        tap(app.buttons["Close"])
        wait(titleField, matching: "exists == false")
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launch()
        XCTAssertTrue(app.buttons[recordIdentifier].waitForExistence(timeout: 10))
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: title, notes: revisedNotes)
        retainScreenshot(app, name: "Background journey text reopened from durable storage in a new process")

        // Force a real validation failure so the production debounce cannot
        // erase the dirty state while this test exercises the Cancel action.
        XCTAssertFalse(app.staticTexts["editorNotice"].exists)
        pasteOversizedTitle(app)
        let invalidTitle = titleField.value as? String ?? ""
        XCTAssertGreaterThan(invalidTitle.utf8.count, 1_024)
        dismissKeyboardGestureIntroductionIfPresent(app)
        XCTAssertEqual(titleField.value as? String ?? "", invalidTitle)
        reveal(app.staticTexts["editorNotice"], in: app, towardTop: false)
        XCTAssertTrue(app.staticTexts["editorNotice"].waitForExistence(timeout: 10))
        wait(app.buttons["saveDraft"], matching: "enabled == true")
        tap(app.buttons["Close"])
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 10))

        // On compact layouts UIKit exposes Cancel. A regular-width iPad uses a
        // dismissible popover; tapping outside is its normal cancellation route.
        if app.buttons["Cancel"].exists {
            tap(app.buttons["Cancel"])
        } else {
            XCTAssertEqual(UIDevice.current.userInterfaceIdiom, .pad,
                           "A missing compact Cancel button is not an allowed fallback")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.95)).tap()
        }
        wait(app.buttons["Discard changes"], matching: "exists == false")
        reveal(titleField, in: app, towardTop: true)
        assertEditor(app, title: invalidTitle, notes: revisedNotes)
        wait(app.buttons["saveDraft"], matching: "enabled == true")
        retainScreenshot(app, name: "Cancelled discard preserves exact unsaved input")

        // The dialog must be usable again, and an explicit discard must restore
        // this test's prior committed text without affecting unrelated records.
        tap(app.buttons["Close"])
        tap(app.buttons["Discard changes"])
        wait(titleField, matching: "exists == false")
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: title, notes: revisedNotes)
        XCTAssertFalse(app.buttons["saveDraft"].isEnabled)
        retainScreenshot(app, name: "Committed background text survives cancellation followed by explicit discard")
        tap(app.buttons["Close"])
        // Only this invocation's simulator cleanup removes the synthetic record.
    }

    @MainActor
    private func pasteOversizedTitle(_ app: XCUIApplication) {
        let field = app.textFields["draftTitle"]
        reveal(field, in: app, towardTop: true)
        tap(field)
        UIPasteboard.general.string = String(repeating: "x", count: 1_025)
        defer { UIPasteboard.general.items = [] }
        field.press(forDuration: 1.2)
        let menuPaste = app.menuItems["Paste"]
        if menuPaste.waitForExistence(timeout: 2) { tap(menuPaste) }
        else { tap(app.buttons["Paste"]) }
    }

    @MainActor
    private func awaitAutosave(_ app: XCUIApplication) {
        wait(app.buttons["saveDraft"], matching: "enabled == false")
        wait(app.buttons["Close"], matching: "enabled == true")
        XCTAssertFalse(app.buttons["saveDraft"].isEnabled)
    }

    @MainActor
    private func assertEditor(_ app: XCUIApplication, title: String, notes: String) {
        XCTAssertTrue(app.textFields["draftTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textViews["draftNotes"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["draftTitle"].value as? String, title)
        XCTAssertEqual(app.textViews["draftNotes"].value as? String, notes)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool) {
        // Use the canonical editor's normal dismissal control before a Form
        // gesture can start inside the smaller iPhone's software keyboard.
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            tap(app.buttons["finishDraftEditing"])
            wait(keyboard, matching: "exists == false")
        }
        let form = app.descendants(matching: .any).matching(identifier: "draftEditorForm").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            guard form.isHittable else { XCTFail("The editor Form must be hittable"); return }
            if towardTop { form.swipeDown() } else { form.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal the editor control")
    }

    @MainActor
    private func dismissKeyboardGestureIntroductionIfPresent(_ app: XCUIApplication) {
        // A fresh iPad may cover its keyboard after the first system Paste with
        // an automatically rotating gesture tutorial. Recognize its exact
        // instructional copy before using Continue; unrelated dialogs still fail.
        let introduction = app.staticTexts.matching(NSPredicate(format: "label IN %@", [
            "Double-tap with three fingers.",
            "Double-tap with three fingers.\n",
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
