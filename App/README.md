# Native local draft preview

This unsigned iPhone/iPad app composes `PlannerUI` and `PlannerData`. It is a local
editor, with no catalog, evaluation, snapshot export, account, remote sync or release
configuration. The reserved `invalid.pickyourai.localpreview` bundle ID is for simulator
use only; it does not allocate a production application identifier or signing team.

The delegated engineering mandate selects SwiftUI/iOS 17 and the local SQLite actor
implemented in PlannerData for this executable slice. This advances the proposed
[#22 ADR](../docs/decisions/issue-22-platform.md); its previous Core Data recommendation
is superseded for this local store only. Product receiving acceptance stays separate.

On macOS, use the [pinned toolchain setup and commands](#pinned-toolchain) below.

The workflow records the actual compiler/SDK/runtime and runs model tests, an unsigned
simulator build, and iPhone/iPad launch smoke checks. It contains no signing secrets.
The smoke script is not an accessibility or complete journey test.

The [launch-smoke runner](scripts/simulator-smoke.py) retains its existing selection:
the newest available iOS runtime and the first available iPhone and iPad types in
that runtime's inventory. Its inventory/create/boot/install/launch/terminate commands
have 60-second deadlines; waiting for boot readiness has a separate five-minute
deadline. Each command, deadline, exit code and captured output is printed into the
workflow's retained `launch.txt`, including partial stdout/stderr after a timeout.
A timed-out or failed launch command still fails the smoke gate.

Only a successfully returned, parseable UUID absent from the original inventory is
eligible for use or cleanup. Commands preserve that returned ID's original spelling.
Each verified creation is protected by `finally`: shutdown and delete are separately
bounded to 60 seconds, and delete is attempted even if shutdown fails or times out.
Successful deletion is required; an already-shutdown result alone is not a cleanup
failure. If creation times out, even a partial UUID does not authorize cleanup, and
the retained command/name/output is the evidence for later inspection. The runner
never shuts down or deletes a pre-existing device, guesses an ID, or erases a device.
Thirteen portable regressions cover these deadlines, partial output, failed launch,
ownership and cleanup boundaries; one executes a real bounded synthetic subprocess.
The mandatory native CI step runs them separately from the Xcode-pin guards and
retains their complete output in `smoke-runner-tests.txt` with the native evidence.
Actual macOS simulator execution remains required for a changed runner.

| Issue / acceptance contribution | Implementation and check | Remaining evidence |
| --- | --- | --- |
| #26 pinned clean checkout; #30 native CI | Checked-in project/local packages, explicit Xcode pin, actual CLI missing-pin regression and isolated-cache workflow | Exact-head hosted evidence and receiving review; #30 untrusted-PR and release-secret gates remain separate |
| #28 restore correct draft | SceneStorage selection, explicit dirty-discard guard, background save attempt | Cold-link routing, process-kill replay and physical lifecycle qualification |
| #80 local library operations | Create, title edit, duplicate, confirmed delete; real-store model tests including reopen | Complete build metadata/organization and receiving review |
| #87 offline editing | All operations use local storage; unknown compatibility/pricing always explicit | Governed catalog cache and downstream evaluation integration |
| #105 accessibility | System controls, visible labels, Dynamic Type, editor/action identifiers | Automated complete journeys, VoiceOver, large text and physical device audits |

Save is acknowledged only after storage commits. Failed saves preserve the in-memory
input and display a retry notice; revision conflicts never overwrite newer revisions.
The user can explicitly discard edits and reopen to load the current revision. Drafts
with unsupported editor payloads cannot be opened for editing. Unreadable storage rows
remain stored and are disclosed by count. Selection restoration opens only committed
content. Background save is best effort: force termination can lose unacknowledged
edits. Revision history is paged in bounded groups of 20. Explicit restoration
requires confirmation and clean current input, appends a new revision, preserves
later saved history, and rejects stale compare-and-swap revisions or unsupported
editor payloads. Restored notes never become current compatibility or pricing evidence.
New binding edits arriving during restoration remain dirty. Lifecycle save requests
arriving during an operation are drained afterward with the latest editor contents
and committed revision; they are not silently dropped by the busy flag.

Seven additional model regressions cover restore/reopen/history retention, dirty and
concurrent edit guards, binding updates during restore, bounded history, unsupported
history, and background saves during paused history/restore operations. These are
controlled actor-boundary tests, not simulated OS termination or end-to-end UI taps.
Undo/redo, timed autosave, process-kill during UI autosave and physical lifecycle
qualification remain work under #69. Hosted exact-head compilation and model tests
are required before this slice is accepted.

Storage opens in Application Support under a directory protected until first unlock.
A failure shows an unavailable screen and never resets the database. Locked-device
and low-storage behavior still require physical-device qualification.

Primary Apple references checked 2026-10-18: [scene phase](https://developer.apple.com/documentation/swiftui/scenephase),
[file protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication).
Local Linux inspection cannot establish SwiftUI/Xcode correctness. See the PR checks
for observed hosted results, distinct from device, store or production acceptance.

## Pinned toolchain

[toolchain.json](toolchain.json) pins the full Xcode bundle to version 16.4, build
16F6, at /Applications/Xcode_16.4.app/Contents/Developer. Install that exact release
from [Apple Developer downloads](https://developer.apple.com/download/all/) and open
it once to finish component and license setup. The command-line-tools-only package
does not contain the app's iOS SDK. Simulator runtimes are recorded separately in
each native artifact; launch smoke checks do not qualify physical devices.

Run commands from a fresh repository checkout through the verifier:

```sh
python3 App/scripts/toolchain.py -- swift test --package-path Packages/PlannerUI
python3 App/scripts/toolchain.py -- xcodebuild -project App/Planner.xcodeproj -scheme Planner -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/native -clonedSourcePackagesDirPath .build/native-source-packages CODE_SIGNING_ALLOWED=NO build
python3 App/scripts/toolchain.py -- python3 App/scripts/simulator-smoke.py
```

The verifier checks the selected directory and exact version/build before executing
the command with that bundle's DEVELOPER_DIR. It reports installation/setup
instructions and exits with status 2 for unavailable, malformed, mismatched or
unresponsive pins. It propagates the native command's exit status. The native
workflow publishes the verified directory to later steps only after validation.

All five checked-in Swift packages currently use repository-local package paths or
system SDK libraries. Their source revision is the checkout commit; there is no
remote Swift package version to resolve to a replacement. The native workflow
asserts that its explicit SwiftPM cache/scratch, Xcode package and derived-data paths
are absent, then builds using those paths without a cache restore. See
[toolchain validation](../docs/validation/toolchain-pin.md) for the actual CLI
negative case and the required hosted failure/recovery and clean-build evidence.

Apple's [command-line tools configuration](https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings)
documents the command-scoped DEVELOPER_DIR override; [TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)
describes the full Xcode command-line tools and build commands.

## Submission SDK compatibility

The separate [unsigned submission SDK lane](../docs/validation/submission-sdk.md)
selects Xcode 26.3 / 17C529 and verifies device and simulator SDK 26.2 before
testing all five packages and building both unsigned Release products. The
existing 16.4 development pin remains a regression baseline. Consult the dated
[#113 policy matrix](../docs/validation/issue-113-policy.md) for current Apple
requirements and the signed-artifact, privacy and channel evidence still needed.
