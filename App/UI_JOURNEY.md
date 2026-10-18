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
   and assert the latest complete title/notes. Retain screenshots of both reopened editors.

There is no test-only storage path, seed injection, reset, uninstall, simulator erase,
or data cleanup in the journey. It leaves its synthetic record for inspection; reruns
use a new title. It never edits or discards an existing draft. It does not test duplicate,
delete, forced termination during an unacknowledged save, or restoration of an open scene.
The hosted test destinations are fresh. Row lookup assumes the newly created record
is visible on the current library page; this test does not establish navigation across
an arbitrarily populated, paginated library. Do not run UI automation against a
simulator being used for concurrent manual editing.

[`scripts/ui-journey.py`](scripts/ui-journey.py) requires exactly one available installed
`iPhone SE (3rd generation)` and `iPad (10th generation)` on runtime
`com.apple.CoreSimulator.SimRuntime.iOS-18-5`. These are the repository's existing hosted
storage destinations. It fails instead of choosing a newer runtime, another device, or
an ambiguous name. It records the full `simctl` JSON inventory and selected runtime/build,
device type, UDID and state as returned by the host. Xcode's simulator test command uses
the exact selected UDID, disables parallel testing and requires no signing credentials.
The test invocation uses `ONLY_ACTIVE_ARCH=YES` so the app and its Swift package
dependencies build the same active simulator architecture. A hosted candidate
without this setting failed before UI execution because the app requested an
unbuilt x86_64 package module on an arm64 destination. The setting follows the
selected destination rather than hard-coding either processor architecture.
The existing Xcode 16.4 build 16F6 verification remains in the workflow.

Every run keeps per-device `xcodebuild` commands/logs, `.xcresult` bundles (including
screenshots), `xcresulttool` JSON summaries, and a combined result record under
`.build/native-evidence/ui-journey`. Both destinations are attempted after an ordinary
test failure. A green runner requires a successful `xcodebuild` exit and exactly one
passed, zero failed/skipped tests in each result summary; missing results fail closed.
The workflow retains these with the existing native evidence for 14 days, including
failed-run evidence. For a local rerun, pass a fresh `--evidence-directory` path; existing
results are not deleted or overwritten. Review result bundles before sharing because
XCTest's automatic diagnostics may include other app content visible during a failure.

Portable runner tests cover exact destination selection, missing/unavailable/ambiguous
inventory, no newer-runtime fallback, the real UI-test command and fail-closed summary
checks. They cannot establish that Swift compiles, XCTest launches, or the UI works.
The first hosted run must validate the checked-in UI target, controls, keyboard gestures
and `xcresulttool` result schema. iOS 17 minimum-OS coverage, physical iPhone/iPad,
VoiceOver, accessibility text sizes, rotation/multitasking, signing and release evidence
remain separate; this is not the complete discover/build/evaluate/share journey.

Primary Apple references checked 2026-10-18:
[XCUIApplication process control](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication),
[XCUIElement queries and input](https://developer.apple.com/documentation/xcuiautomation/xcuielement),
[running tests and result bundles](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results),
and [Xcode 16.3 xcresulttool commands](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes).
