# Bounded native notes and catalog UI journeys

[`PlannerAppUITests/LocalDraftJourneyTests.swift`](PlannerAppUITests/LocalDraftJourneyTests.swift)
is an Xcode UI Testing Bundle, separate from the Swift package's editor-model tests.
The shared `Planner` scheme includes it in the Test action. It uses the actual app,
its normal SwiftUI controls and its actual SQLite-backed application container:

1. Create a draft and replace the default name with a unique `UI-Journey-<UUID>` title.
2. Type synthetic notes and wait for the actual 750 ms production autosave to commit.
   Require both idle controls and clean editor state before closing; do not tap Save.
3. Reopen that exact row, assert the complete title/notes, then autosave another notes revision.
4. Close, terminate the app process, launch it again, reopen the same record identifier,
   and assert the latest complete title/notes.
5. Add one title character, autosave it, and read its exact durable revision/title
   using Load saved revisions. Use the normal Undo edit and Redo edit controls,
   requiring each next revision and its exact title to appear in a new history read.
   Close and reopen the same record and assert the complete final title/notes again.
   An older Saved label or an unchanged history page cannot satisfy these checks.
6. Paste one synthetic 1025-byte ASCII string into that record's title using the
   standard edit menu, then amend its notes. The actual store's 1024-byte title
   validation must reject autosave: require a new editor failure notice and dirty
   controls. Choose Close and Discard changes, reopen the exact record identifier,
   and verify its last acknowledged title/notes remain unchanged. This invalid
   amendment keeps the discard path deterministic while the production timer runs.
7. Create and autosave a separately UUID-titled control draft through the same visible UI.
   Delete only the original record through the confirmation control.
8. Require the control's exact row to load and no operation/corruption notice before
   asserting the deleted target is absent, both immediately and after process relaunch.
   Reopen the control and assert its complete saved title/notes. An empty failed reload
   or a filtered corrupt record cannot substitute for successful deletion evidence.
   Retain screenshots of reopened, discarded, deleted and surviving-control states.

The test writes only synthetic text to the clipboard on this run's newly created
owned simulator and clears that clipboard after the paste. It uses normal text input
and the system Paste command; it does not inject a draft or change the storage rules.
There is no test-only storage path, seed injection, app reset, uninstall or simulator
erase. Every test uses a UUID title and records the resulting row's identifier; discard
and delete operate only on the original newly created record. The separate control is
removed only by cleanup of this run's owned simulator. There is no "first draft" deletion
or assertion that an arbitrary user's whole library is empty. This does not test
duplicate, forced termination during an unacknowledged save, or restoration of an open
scene. Row lookup still assumes the created record is on the current library page; it
does not establish pagination across an arbitrarily populated library.

## Catalog browsing journey

[`PlannerAppUITests/CatalogBrowserJourneyTests.swift`](PlannerAppUITests/CatalogBrowserJourneyTests.swift)
uses the same actual app and ordinary controls to browse the fixed synthetic
catalog. It verifies the initial 25-of-29 result count, combines a query with the
Accelerator kind and kind ordering, then terminates and relaunches the process.
The recreated browser must restore those preferences and return the exact
`cat.accelerator.fixture` item at `2026.10-demo`. Its detail must identify the
pinned `catalog.fixture.1` source and explicitly unknown assessment.

Clear filters restores the first bounded page; Load more components must reach
29-of-29. A unique unmatched query must show a successful zero count and an empty
state without a failure notice. The test restores default filters through the UI
and returns to the available Notes tab. It never creates, edits, selects, deletes
or replaces a note or imported build. Screenshots retain combined-filter,
pinned-detail, pagination and empty states. Both list and detail gestures target
their explicit accessible containers, and text entry dismisses the keyboard
through the real field submission handler.

This test does not inject a failing service, invent compatibility assessments or
select a component into a build. Deterministic model regressions cover unavailable
pages and cancellation races separately. The added journey still requires actual
hosted execution on both pinned destinations; its source alone proves no UI or
physical accessibility result. See the [catalog receipt](../docs/validation/issue-59-catalog-browser.md).

## Shared pinned runner

[`scripts/ui-journey.py`](scripts/ui-journey.py) requires exactly one installed device
type for `iPhone SE (3rd generation)` and `iPad (10th generation)`, plus the available
runtime `com.apple.CoreSimulator.SimRuntime.iOS-18-5`. It creates a fresh simulator of
each exact type with a unique name; pre-existing simulators need not be present.
Missing/ambiguous pins fail instead of choosing another runtime or device type.
The complete original `simctl` inventory and requested type/runtime/build metadata are
retained. Each created simulator's exact returned UDID and name are recorded before
test execution. A returned ID that is malformed or appeared in the original inventory
is never used for testing or cleanup.
UUID equality for that safety check ignores letter case, while test and cleanup
commands preserve the validated spelling returned by `simctl`. Candidate
`f9af742d68a1010af0203953489c4c8ca66b22cf` in
[native run 39091041272](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39091041272)
lowercased both returned IDs; Xcode listed those same IDs in uppercase and rejected
the requested destinations before either UI test executed. The regression check
covers original command spelling and rejects case variants of pre-existing IDs.
The corrected pre-autosave journey subsequently passed on both pinned destinations
at `de1f432` in [native run 39094714003](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39094714003/job/117578640861).
Those earlier results establish that harness revision only; the combined production
autosave, undo/redo and invalid-amendment journey requires fresh native execution.

The first combined attempt at `206fbb0a97673bc03246af6175411c3eff11f4a4` in
[native run 39100534357](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39100534357/job/117595708300)
passed all 52 model cases and the entire iPad journey. The iPhone journey failed before
its history read: the generic helper repeatedly swiped the first hittable collection,
but `loadRevisions` never appeared. The library also remains behind the editor sheet,
so that container selection is ambiguous. The editor Form now has the exact
`draftEditorForm` identifier, and every reveal gesture targets only that container.
All persistence, revision, dirty-discard and destination assertions remain mandatory.
This correction requires a fresh successful run on both destinations.

### Control failures observed in the catalog candidate

Candidate `e964f566874ab5f26f7d7499f753316ec97c75c8` in
[native run 39104693228](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39104693228/job/117608134115)
compiled and passed all 60 editor/browser model tests, the unsigned simulator build
and both smoke launches. Its full journeys failed: the iPhone ran both tests and
failed both; the iPad passed the complete notes journey and failed catalog entry.
Those results do not qualify either destination's complete two-journey gate.

The retained [native evidence artifact 12129922478](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39104693228/artifacts/12129922478)
has SHA-256 `41fffea1d09afcb676e34b3cd1b803b8a0888eea0f246007c87628d466a01866`.
Its actual `xcresult` activity records, accessibility trees and screen recordings
identify three distinct controls, despite the browser failures sharing one helper
line number:

| Observed failure | Evidence and scoped correction |
| --- | --- |
| iPad: `app.tabBars.buttons["Demo catalog"]` never exists. | The retained hierarchy exposes the visible top navigation as nested Buttons under Other, with no TabBar. The test now finds the exact visible navigation label among buttons on both layouts and still performs a normal hittable/enabled tap. The Notes return uses the same query. |
| iPhone: the kind menu never opens before waiting for `catalogKind-accelerator`. | The outer List button covers `(16,369,343,44)` while the actual inner menu button covers `(32,381,199,20.5)`. XCTest's retained tap was `(50.3,373.4)`, outside that inner control, and the recording shows no open menu. Candidate `aba37` requested the borderless button style; its later actual result below shows that this did not correct the nested activation target. |
| iPhone: six Form swipes never reveal `loadRevisions`. | Each retained swipe starts at `(187.5,453.5)` while the visible keyboard starts at y=407. The recording shows an unchanged editor and keyboard throughout. Title and notes now share explicit focus state and a visible Done editing keyboard action. The test uses that action and requires the keyboard to disappear before its unchanged identified-Form scrolling. After the first dismissal it also reasserts the exact amended title and complete notes before reading durable history. |

The focus action only ends text entry; it does not save, discard or close the draft.
The title's Done submission also ends focus, and interactive scroll dismissal is
available to a user who begins a gesture above the keyboard. The real production
autosave, exact revision increments, invalid-title rejection, discard, independent
control and cold deletion assertions are unchanged. No extra swipes, arbitrary
coordinate taps, storage injection, skipped test or destination fallback were added.
Failure messages identify the requested control rather than only a shared helper.

The separately reviewed finite-window-geometry correction
and the canonical editor candidate's additional model/Home/Files tests are distinct
work and must be preserved when the branches are reconciled; this receipt does not
claim they have been applied or executed here.

Candidate `aba37bb980f49e0e6772f11bcfaa8023a34d4839` in
[native run 39111714464](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39111714464/job/117629098778)
passed all 60 model tests, the unsigned build and both smoke launches. The complete
iPhone notes journey passed in 258.729 seconds. Its catalog journey failed in
83.791 seconds; iPad catalog failed in 97.477 seconds and notes in 162.826 seconds.
Both destinations executed the exact two tests with zero skips, and both owned
simulator deletions succeeded. Artifact `12131547131` is 211,972,207 bytes and its
downloaded ZIP matches SHA-256
`9e11bdda7ab52f620eb42b6ef797027e45f50c754c7194d2f8136f4b892af294`.

Both catalog recordings still show a closed kind menu. The iPhone retains the
same outer/inner frames and synthesized tap; iPad now reaches that same nested
menu after successful adaptive navigation. A normal row button now opens a
component-kind sheet with visibly labeled switch Toggles and an explicit Done
action. Each toggle uses the existing exact kind binding; no search, sorting,
source identity, preference or pagination semantics change. The actual journey
requires off/on switch values, the same one-result Accelerator filter and its
selected state after process relaunch before continuing to details and pagination.

The iPad notes failure occurs later, after its standard oversized-title Paste:
the retained recording shows the OS **Copy and Paste** first-use education panel
with its **Continue** button covering the keyboard toolbar. `finishDraftEditing`
exists but is not hittable behind that panel. This is separate from editor focus.
The paste helper dismisses only that exact observed education heading through its
normal visible Continue action, waits for the heading to disappear and reasserts
the complete over-limit title value. The actual autosave rejection, unsaved notes,
mandatory discard and durable reopening remain required. No production focus
change, arbitrary coordinate, longer timeout or simulator-state injection is added.

These follow-up controls still require fresh exact-source execution of both full
journeys on both pinned destinations. The one passing iPhone notes result is
retained source-specific evidence, not acceptance of the combined native gate.

A try/finally scope protects every verified creation, including later evidence-writing
or test failures. Cleanup shuts down and deletes only the verified ID created by this
invocation, retaining both command outcomes; it never uses blanket shutdown, erase or
delete commands. If creation times out without a verified returned ID, the runner
records failure and does not guess which simulator to remove. Abrupt runner termination
can prevent cleanup, so the retained creation receipt remains relevant for inspection.
A cleanup failure fails the overall run even when UI assertions passed.

Xcode tests target the exact created UDID with parallel testing disabled and no signing
credentials.
The test invocation uses `ONLY_ACTIVE_ARCH=YES` so the app and its Swift package
dependencies build the same active simulator architecture. A hosted candidate
without this setting failed before UI execution because the app requested an
unbuilt x86_64 package module on an arm64 destination. The setting follows the
selected destination rather than hard-coding either processor architecture.
The existing Xcode 16.4 build 16F6 verification remains in the workflow.
The generic simulator compile gate is unchanged. Each device test has a 15-minute
timeout; the 40-minute job budget allows both attempts plus existing checks.

Every run keeps per-device `xcodebuild` commands/logs, `.xcresult` bundles (including
screenshots), `xcresulttool` JSON summaries, per-device creation/cleanup receipts, and a combined result record under
`.build/native-evidence/ui-journey`. Both destinations are attempted after an ordinary
creation/test failure or timeout. A green runner requires a successful `xcodebuild` exit and exactly two
passed, zero failed/skipped tests in each result summary and successful owned-simulator
cleanup; missing results or only one completed journey fail closed. Both specific
test identifiers are passed through separate `-only-testing` arguments; no whole
test target, automatic retries or skipped case can substitute for those counts.
The workflow retains these with the existing native evidence for 14 days, including
failed-run evidence. For a local rerun, pass a fresh `--evidence-directory` path; existing
results are not deleted or overwritten. Review result bundles before sharing because
XCTest's automatic diagnostics may include other app content visible during a failure.

Portable runner tests cover exact type/runtime selection, missing/unavailable/ambiguous
inventory, no fallback, active-architecture test scope, result/skip rejection, bounded
timeouts, attempts after failure, evidence preservation, and ownership/cleanup errors. They cannot establish that Swift compiles, XCTest launches, or the UI works.
The combined candidate's hosted run must validate the checked-in UI target, history
controls, scroll/keyboard/paste gestures and `xcresulttool` result schema.
iOS 17 minimum-OS coverage, physical iPhone/iPad,
VoiceOver, accessibility text sizes, rotation/multitasking, signing and release evidence
remain separate; this is not the complete discover/build/evaluate/share journey.

Primary Apple references checked 2026-10-18:
[XCUIApplication process control](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication),
[XCUIElement queries and input](https://developer.apple.com/documentation/xcuiautomation/xcuielement),
[the general pasteboard](https://developer.apple.com/documentation/uikit/uipasteboard/general),
[running tests and result bundles](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results),
and [Xcode 16.3 xcresulttool commands](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes).
The control correction also uses Apple's documented
[focus state](https://developer.apple.com/documentation/swiftui/focusstate),
[keyboard toolbar placement](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/keyboard),
and [borderless button style](https://developer.apple.com/documentation/swiftui/borderlessbuttonstyle).
The kind-selection follow-up uses standard
[bound toggles](https://developer.apple.com/documentation/swiftui/toggle) and
[a scoped sheet with explicit dismissal](https://developer.apple.com/design/human-interface-guidelines/sheets).
