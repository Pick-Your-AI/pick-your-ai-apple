# Native local-draft UI journey

Related partial outcomes: [#80](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/80),
[#105](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/105) and
[#107](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/107).

The `PlannerUITests` XCUITest target drives the installed application through its
visible controls. It creates a note, enters synthetic text, saves and waits for the
durable acknowledgment, terminates and relaunches the app, verifies the saved text,
discards a later unsaved change explicitly, and confirms deletion. The test never
reads SQLite directly, injects records, or asks the app to bypass production paths.
It retains screenshots and the complete XCTest result bundle.

The driver creates a fresh iPhone SE (3rd generation) and iPad (10th generation)
simulator using the installed iOS 18.5 runtime, and deletes only those devices after
each run. This isolates test records without a destructive application reset switch.
Unavailable runtime/device pins fail with setup instructions instead of silently
selecting a different target. Xcode 16.4 build 16F6 remains the checked toolchain.

Run from the repository root on a Mac with that Xcode and runtime installed:

```sh
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
python3 App/scripts/run-ui-journeys.py
```

The `Native draft UI journeys` workflow retains toolchain/commit identities,
simulator selection, logs, screenshots and `.xcresult` bundles for each device.
Its PR permissions are read-only and it uses no signing or release secrets.

## Acceptance boundary

This source change must pass its exact-head hosted UI run before an executed
journey is claimed. Python/static checks in the Linux workspace cannot execute
XCUITest. A successful run establishes the tested visible note lifecycle on the
recorded simulators only. If scene restoration does not reopen the editor, the test
navigates to the saved draft explicitly; it does not certify automatic scene
restoration or cold Universal Links. Termination occurs after a save acknowledgment,
so it does not prove lossless termination during an unacknowledged autosave.

Full builder, catalog, analysis, import/provider, accessibility, minimum/current OS,
physical-device, signed-release and production acceptance remain separate. No
VoiceOver or human usability audit is inferred from element queries or screenshots.

Primary Apple documentation checked 2026-10-18: [Xcode testing](https://developer.apple.com/documentation/xcode/testing),
[adding test targets](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project),
and [XCUIApplication](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication).
These explain UI-test facilities; actual results come from the recorded CI run.
