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
        dismissEditorKeyboard(app)
        XCTAssertEqual(titleField.value as? String, renamedTitle)
        XCTAssertEqual(app.textViews["draftNotes"].value as? String, revisedNotes)
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

        // Open the real Files picker from the separate imported-build library.
        // Cancellation must not prepare an import or report a failed operation.
        tapNavigation("Imported builds", in: app)
        let chooseImport = app.buttons["chooseBuildImport"]
        let confirmImport = app.buttons["confirmBuildImport"]
        let fileFailure = app.staticTexts["The file operation did not finish. Existing local builds were preserved."]
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@", "Cancel"))
        XCTAssertTrue(chooseImport.waitForExistence(timeout: 10))
        XCTAssertFalse(confirmImport.exists)
        XCTAssertFalse(fileFailure.exists)
        XCTAssertEqual(cancel.count, 0, "There must be no earlier cancellation dialog")
        tap(chooseImport)
        XCTAssertTrue(cancel.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(cancel.count, 1, "The actual file picker must expose one Cancel action")
        retainHierarchy(app, name: "Actual Files picker before cancellation")
        retainScreenshot(app, name: "Actual Files picker before cancellation")
        tap(cancel.firstMatch)
        wait(cancel.firstMatch, matching: "exists == false")
        wait(chooseImport, matching: "hittable == true AND enabled == true")
        XCTAssertFalse(confirmImport.exists, "Cancelling file selection must not prepare an import")
        XCTAssertFalse(fileFailure.exists, "File-picker cancellation is not an import failure")
        retainScreenshot(app, name: "Imported library preserved after Files cancellation")

        // Positive saved-record evidence prevents an empty or failed load from
        // standing in for preservation across the separate library and picker.
        tapNavigation("Notes", in: app)
        assertLoadedLibrary(app, controlIdentifier: controlIdentifier)
        XCTAssertFalse(app.buttons[recordIdentifier].exists)
        tap(app.buttons[controlIdentifier])
        assertEditor(app, title: controlTitle, notes: controlNotes)
        tap(app.buttons["Close"])
        app.terminate()
        app.launch()
        tapNavigation("Notes", in: app)
        assertLoadedLibrary(app, controlIdentifier: controlIdentifier)
        XCTAssertFalse(app.buttons[recordIdentifier].exists,
                       "Files cancellation must not revive the deleted draft after relaunch")
        tap(app.buttons[controlIdentifier])
        assertEditor(app, title: controlTitle, notes: controlNotes)
        retainScreenshot(app, name: "Saved control survived Files cancellation and process relaunch")
        tap(app.buttons["Close"])
        // The control is removed only with this run's owned simulator cleanup.
    }

    /// Exercises only this test-created draft through the normal app controls.
    /// Invalid input is valid local draft content, not a validated frozen Build.
    @MainActor
    func testPlanningInputsPreserveUnansweredInvalidTextAndRestoredRevisions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.textFields["draftTitle"].exists {
            XCTAssertFalse(app.buttons["saveDraft"].isEnabled, "An existing draft must be clean")
            tap(app.buttons["Close"])
        }
        tapNavigation("Notes", in: app)
        let title = "UI-Planning-\(UUID().uuidString)"
        let notes = "Synthetic planning input journey. Preserve these notes."
        let recordIdentifier = createDraft(app, title: title, notes: notes)
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: title, notes: notes)
        assertUnansweredPlanningChoices(app, towardTop: false)
        retainHierarchy(app, name: "New draft with unanswered workload and deployment")
        assertPlanningState(app, key: "currency",
            message: "Unanswered. A budget cannot be interpreted without its currency.", towardTop: false)

        replacePlanningInput(app, key: "monthly_budget_amount", previous: "", replacement: "1.2500", towardTop: false)
        assertPlanningState(app, key: "monthly_budget_amount",
            message: "Amount entered. A valid currency code is still needed to interpret this budget.", towardTop: false)
        replacePlanningInput(app, key: "requests_per_day", previous: "", replacement: "12 requests/day", towardTop: false)
        let invalidUsage = "Invalid input. Use a whole number of at least 0 in the stated unit; omit separators and unit text. Your text is preserved."
        assertPlanningState(app, key: "requests_per_day", message: invalidUsage, towardTop: false)
        awaitAutosaveAcknowledgement(app)
        let invalidRevision = newestSavedRevision(app, title: title)
        retainScreenshot(app, name: "Saved revision after invalid planning units and unanswered choices")
        autosaveAndClose(app)
        app.terminate()
        app.launch()
        tapNavigation("Notes", in: app)
        assertLoadedLibrary(app, controlIdentifier: recordIdentifier)
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: title, notes: notes)
        assertUnansweredPlanningChoices(app, towardTop: false)
        assertPlanningState(app, key: "currency",
            message: "Unanswered. A budget cannot be interpreted without its currency.", towardTop: false)
        assertPlanningValue(app, key: "monthly_budget_amount", expected: "1.2500", towardTop: false)
        assertPlanningValue(app, key: "requests_per_day", expected: "12 requests/day", towardTop: false)
        assertPlanningState(app, key: "requests_per_day", message: invalidUsage, towardTop: false)
        retainScreenshot(app, name: "Exact invalid units and budget spelling after process relaunch")

        // These are explicit native menu selections from the unchanged fictional
        // catalog. Its declared usage and region must not become user input.
        let workload = app.buttons["planningChoice-workload"]
        reveal(workload, in: app, towardTop: true)
        tap(workload)
        tap(app.buttons["FICTIONAL Workload — agentic"])
        let workloadReference = app.staticTexts["cat.workload.fixture · 2026.10-demo"]
        XCTAssertTrue(workloadReference.waitForExistence(timeout: 10))
        let deployment = app.buttons["planningChoice-deployment_mode"]
        reveal(deployment, in: app, towardTop: false)
        tap(deployment)
        tap(app.buttons["FICTIONAL Deployment Mode — self_hosted"])
        XCTAssertTrue(app.staticTexts["cat.deployment_mode.fixture · 2026.10-demo"].waitForExistence(timeout: 10))
        retainScreenshot(app, name: "Explicit fictional workload and deployment choices")
        assertPlanningState(app, key: "region",
            message: "Unanswered. Region restrictions cannot be applied.", towardTop: false)
        replacePlanningInput(app, key: "currency", previous: "", replacement: "USD", towardTop: false)
        assertPlanningState(app, key: "data_classification",
            message: "Unanswered. Data classification restrictions cannot be applied.", towardTop: false)
        replacePlanningInput(app, key: "requests_per_day", previous: "12 requests/day", replacement: "00012", towardTop: false)
        assertPlanningState(app, key: "requests_per_day",
            message: "Input recorded. Compatibility, availability and prices remain unknown.", towardTop: false)
        assertPlanningState(app, key: "avg_input_tokens",
            message: "Unanswered. Usage is unknown; no zero usage is assumed.", towardTop: false)
        awaitAutosaveAcknowledgement(app)
        let correctedRevision = newestSavedRevision(app, title: title)
        XCTAssertGreaterThan(correctedRevision, invalidRevision)
        retainScreenshot(app, name: "Saved revision after explicit choices and corrected usage")

        let restore = app.buttons["Restore revision \(invalidRevision)"]
        reveal(restore, in: app, towardTop: false)
        tap(restore)
        tap(app.buttons["Restore revision"])
        assertUnansweredPlanningChoices(app, towardTop: true)
        assertPlanningState(app, key: "currency",
            message: "Unanswered. A budget cannot be interpreted without its currency.", towardTop: false)
        assertPlanningValue(app, key: "monthly_budget_amount", expected: "1.2500", towardTop: false)
        assertPlanningValue(app, key: "requests_per_day", expected: "12 requests/day", towardTop: false)
        assertPlanningState(app, key: "requests_per_day", message: invalidUsage, towardTop: false)
        awaitAutosaveAcknowledgement(app)
        assertSavedRevision(app, revision: correctedRevision + 1, title: title)
        let retainedCorrected = app.staticTexts["revisionTitle-\(correctedRevision)"]
        reveal(retainedCorrected, in: app, towardTop: false)
        XCTAssertEqual(retainedCorrected.label, title, "Restoration must retain the later saved revision")
        autosaveAndClose(app)
        app.terminate()
        app.launch()
        tapNavigation("Notes", in: app)
        assertLoadedLibrary(app, controlIdentifier: recordIdentifier)
        tap(app.buttons[recordIdentifier])
        assertEditor(app, title: title, notes: notes)
        assertUnansweredPlanningChoices(app, towardTop: false)
        assertPlanningState(app, key: "currency",
            message: "Unanswered. A budget cannot be interpreted without its currency.", towardTop: false)
        assertPlanningValue(app, key: "monthly_budget_amount", expected: "1.2500", towardTop: false)
        assertPlanningValue(app, key: "requests_per_day", expected: "12 requests/day", towardTop: false)
        assertPlanningState(app, key: "requests_per_day", message: invalidUsage, towardTop: false)
        XCTAssertFalse(app.staticTexts["editorNotice"].exists)
        retainHierarchy(app, name: "Restored planning inputs after process relaunch")
        retainScreenshot(app, name: "Restored planning inputs after process relaunch")
        autosaveAndClose(app)
        // The test-created row remains until this run's owned simulator cleanup.
        // This acknowledged-save journey does not simulate an interrupted write.
    }

    @MainActor
    private func assertUnansweredPlanningChoices(_ app: XCUIApplication, towardTop: Bool) {
        for (index, kind) in ["Workload", "Deployment mode"].enumerated() {
            let state = app.staticTexts["Unanswered. \(kind) filters cannot be applied."]
            reveal(state, in: app, towardTop: index == 0 ? towardTop : false)
            XCTAssertEqual(state.label, "Unanswered. \(kind) filters cannot be applied.")
        }
    }

    @MainActor
    private func replacePlanningInput(_ app: XCUIApplication, key: String, previous: String,
                                      replacement: String, towardTop: Bool) {
        let field = app.textFields["planningInput-\(key)"]
        reveal(field, in: app, towardTop: towardTop)
        if previous.isEmpty {
            XCTAssertEqual(field.placeholderValue, "Unanswered")
            XCTAssertTrue((field.value as? String) == "" || (field.value as? String) == field.placeholderValue,
                          "Only an empty native field or its displayed placeholder is expected")
        } else {
            XCTAssertEqual(field.value as? String, previous)
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if !previous.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        field.typeText(replacement)
        XCTAssertEqual(field.value as? String, replacement)
    }

    @MainActor
    private func assertPlanningValue(_ app: XCUIApplication, key: String, expected: String, towardTop: Bool) {
        let field = app.textFields["planningInput-\(key)"]
        reveal(field, in: app, towardTop: towardTop)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        XCTAssertEqual(field.value as? String, expected)
    }

    @MainActor
    private func assertPlanningState(_ app: XCUIApplication, key: String, message: String, towardTop: Bool) {
        let state = app.staticTexts["planningInputState-\(key)"]
        reveal(state, in: app, towardTop: towardTop)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", message), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        XCTAssertEqual(state.label, message)
    }

    @MainActor
    private func tapNavigation(_ title: String, in app: XCUIApplication) {
        LibraryTabJourney.select(title, in: app)
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
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        wait(continueButton, matching: "hittable == true AND enabled == true")
        // The recognized system tutorial stayed open after a centered 50 ms
        // event. Try one bounded press; both disappearance checks still decide.
        continueButton.press(forDuration: 0.2)
        wait(continueButton, matching: "exists == false")
        wait(introduction, matching: "exists == false")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool) {
        dismissEditorKeyboard(app)
        // The library List remains in the hierarchy behind the editor sheet.
        // Scroll only this editor Form, never the first hittable collection.
        let container = app.descendants(matching: .any).matching(identifier: "draftEditorForm").firstMatch
        XCTAssertTrue(container.waitForExistence(timeout: 10), "The editor Form must be present")
        for _ in 0..<6 {
            let exists = element.exists
            if exists && element.isHittable { return }
            guard container.isHittable else { XCTFail("The editor Form must be hittable"); return }
            if exists {
                // An existing short field can pass behind the sheet navigation
                // area. Move it toward this Form's center instead of overshooting.
                let target = element.frame
                let bounds = container.frame
                guard target.midY.isFinite, bounds.midY.isFinite,
                      target.height > 0, bounds.height > 0 else {
                    XCTFail("The editor Form scroll geometry is unavailable"); return
                }
                let endY = target.midY < bounds.midY ? 0.65 : 0.35
                let start = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let end = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
                start.press(forDuration: 0.05, thenDragTo: end,
                            withVelocity: .slow, thenHoldForDuration: 0.1)
            } else if towardTop {
                container.swipeDown()
            } else {
                container.swipeUp()
            }
        }
        XCTAssertTrue(element.exists && element.isHittable,
                      "Could not reveal \(element.identifier) in the editor Form")
    }

    @MainActor
    private func dismissEditorKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        // On the compact iPhone, the Form's synthesized swipe began inside the
        // keyboard. Use the app's visible focus control before normal scrolling.
        // This does not submit, save, discard, close or replace any draft state.
        tap(app.buttons["finishDraftEditing"])
        wait(app.keyboards.firstMatch, matching: "exists == false")
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

    @MainActor
    private func retainHierarchy(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
