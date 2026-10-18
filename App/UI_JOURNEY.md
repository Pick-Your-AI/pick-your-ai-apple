# Bounded local-draft UI journey

[`PlannerAppUITests/LocalDraftJourneyTests.swift`](PlannerAppUITests/LocalDraftJourneyTests.swift)
is an Xcode UI Testing Bundle, separate from the Swift package's editor-model tests.
The shared `Planner` scheme includes it in the Test action. It uses the actual app,
its normal SwiftUI controls and its actual SQLite-backed application container:

1. Create a draft and replace the default name with a unique `UI-Journey-<UUID>` title.
2. Type synthetic notes and tap Save. Wait until the write completes and the controls
   acknowledge clean editor state before closing.
3. Reopen that exact row, assert the complete title/notes, then save another notes revision.
4. Close, terminate the app process, launch it again, reopen the same record identifier,
   and assert the latest complete title/notes.
5. Add an unsaved amendment to that same record, choose Close and Discard changes,
   reopen its exact ID and verify the last committed text remains unchanged.
6. Create and save a separately UUID-titled control draft through the same visible UI.
   Delete only the original record through the confirmation control.
7. Require the control's exact row to load and no operation/corruption notice before
   asserting the deleted target is absent, both immediately and after process relaunch.
   Reopen the control and assert its complete saved title/notes. An empty failed reload
   or a filtered corrupt record cannot substitute for successful deletion evidence.
   Retain screenshots of reopened, discarded, deleted and surviving-control states.

There is no test-only storage path, seed injection, app reset, uninstall or simulator
erase. Every test uses a UUID title and records the resulting row's identifier; discard
and delete operate only on the original newly created record. The separate control is
removed only by cleanup of this run's owned simulator. There is no "first draft" deletion
or assertion that an arbitrary user's whole library is empty. This does not test
duplicate, forced termination during an unacknowledged save, or restoration of an open
scene. Row lookup still assumes the created record is on the current library page; it
does not establish pagination across an arbitrarily populated library.

[`scripts/ui-journey.py`](scripts/ui-journey.py) requires exactly one installed device
type for `iPhone SE (3rd generation)` and `iPad (10th generation)`, plus the available
runtime `com.apple.CoreSimulator.SimRuntime.iOS-18-5`. It creates a fresh simulator of
each exact type with a unique name; pre-existing simulators need not be present.
Missing/ambiguous pins fail instead of choosing another runtime or device type.
The complete original `simctl` inventory and requested type/runtime/build metadata are
retained. Each created simulator's exact returned UDID and name are recorded before
test execution. A returned ID that is malformed or appeared in the original inventory
is never used for testing or cleanup.

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
creation/test failure or timeout. A green runner requires a successful `xcodebuild` exit and exactly one
passed, zero failed/skipped tests in each result summary and successful owned-simulator
cleanup; missing results fail closed.
The workflow retains these with the existing native evidence for 14 days, including
failed-run evidence. For a local rerun, pass a fresh `--evidence-directory` path; existing
results are not deleted or overwritten. Review result bundles before sharing because
XCTest's automatic diagnostics may include other app content visible during a failure.

Portable runner tests cover exact type/runtime selection, missing/unavailable/ambiguous
inventory, no fallback, active-architecture test scope, result/skip rejection, bounded
timeouts, attempts after failure, evidence preservation, and ownership/cleanup errors. They cannot establish that Swift compiles, XCTest launches, or the UI works.
The first hosted run must validate the checked-in UI target, controls, keyboard gestures
and `xcresulttool` result schema. iOS 17 minimum-OS coverage, physical iPhone/iPad,
VoiceOver, accessibility text sizes, rotation/multitasking, signing and release evidence
remain separate; this is not the complete discover/build/evaluate/share journey.

Primary Apple references checked 2026-10-18:
[XCUIApplication process control](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication),
[XCUIElement queries and input](https://developer.apple.com/documentation/xcuiautomation/xcuielement),
[running tests and result bundles](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results),
and [Xcode 16.3 xcresulttool commands](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes).
