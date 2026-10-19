# Visible analysis pending caption

This correction supplements [PR #387](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/387)
at source `89e98340ee2d2570b33511e60c63d127249665b8`. Its existing publisher and
[visible-analysis acceptance record](visible-analysis.md) retain the component
and selected-editor receiving scope. This change does not complete Apple #75.

## Observed original failure

The original [native rendering job 118156623560](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39280108621/job/118156623560)
checked out `e6c4e07cac09b1b4bf149bff412578f314929c64`, with source
`89e98340ee2d2570b33511e60c63d127249665b8` and base
`262b9804cd3d8d0fe8c134ee2c4caeed05f13e9f`. It used Xcode 16.4 / 16F6.
All six required methods executed: the five earlier evidence/date methods passed,
and the visible-analysis method failed after 48.692 seconds at the bounded scan
for `analysis-pending-retry`. Its current and foreign-visible scenarios completed;
cancelled, failed, disconnected and cleared were not reached. The complete native
session reported six tests with one failure and zero unexpected failures.

The actual artifact [12206803468](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39280108621/artifacts/12206803468)
is 74,897,453 bytes, SHA-256
`94abf310037ce8439c326877e07f43c647af186ee0ce2dfbc1bb4b43d69a2af7`.
The downloaded bytes match the API and original upload digest. All 1,604 unique
ZIP members passed CRC and safe-path/type checks. The original log and retained
test-activity record agree on the pending-scan failure. The artifact has not been
turned into a new native execution or a physical-device accessibility receipt.

The failed method's retained 48.028-second screen recording provides direct
presentation evidence. At 40 seconds it shows `analysis-pending-retry`, `Case 3
of 7`, the ready-scenario text, a spinner and the unknown-state explanation. The
pending caption is visibly absent. This confirms a presentation omission in that
original macOS execution; it does not independently expose the accessibility
tree. The 1,737,573-byte recording hashes to
`a1f3234e51e90772732e930d1f6f2f1f826675dad410c3f38617453d329f3eb6`.

## Correction and retained checks

The pending view now places its unchanged status text next to an indeterminate
spinner as a separate `Text`. The spinner is decorative and hidden from the
accessibility tree; the status and the following unknown-state explanation remain
available as text. The caption no longer depends on a platform progress-control
style to display its label or expose it as a static-text descendant. This is a
focused source correction for that representation boundary. The original console
does not print its collected strings, so the caption's accessibility
representation is not independently established by that console.

Apple documents [ProgressView](https://developer.apple.com/documentation/swiftui/progressview)
as the progress presentation and
[accessibilityHidden](https://developer.apple.com/documentation/swiftui/view/accessibilityhidden%28_%3A%29)
as controlling a view's participation in system accessibility. These primary
sources were checked on 2026-10-19; they do not establish this app's accessibility
or rendering acceptance.

The existing scan's failure message now includes the actual collected native
text. Its sixteen-scan bound, settling condition, positive and negative assertions,
scroll behavior and module/session qualification are unchanged. All six required
test methods, all seven analysis scenarios, fixtures, host transitions, model
identity checks and workflow gates remain intact. No expected status is supplied
to the host by the test process.

No Swift/Xcode or simulator run executed locally for this correction. The existing
four Python rendering-receipt methods passed and verify only the retained parser boundary.
Actual configured native execution must pass all six methods on the receiving
source, including every previously unreached scenario, before delivery can claim
recovery. The later main composition, selected-editor integration, governed service
replay, physical devices, assistive technology and signed release retain their own
acceptance requirements.
