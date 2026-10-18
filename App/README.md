# Native local draft preview

This unsigned iPhone/iPad app composes `PlannerUI` and `PlannerData`. It is a local
editor with a separate read-only imported-build library and reviewed JSON file export.
The separate Demo catalog tab browses a pinned, explicitly synthetic fixture; compatibility and price remain unknown. It has no evaluation, account, remote sync or release configuration. The reserved `invalid.pickyourai.localpreview` bundle ID is for simulator
use only; it does not allocate a production application identifier or signing team.

The delegated engineering mandate selects SwiftUI/iOS 17 and the local SQLite actor
implemented in PlannerData for this executable slice. This advances the proposed
[#22 ADR](../docs/decisions/issue-22-platform.md); its previous Core Data recommendation
is superseded for this local store only. Product receiving acceptance stays separate.

On macOS, use the [pinned toolchain setup and commands](#pinned-toolchain) below.

The workflow records the actual compiler/SDK/runtime and runs model tests, an unsigned
simulator build, iPhone/iPad launch smoke checks, and a separate XCUITest local-draft
journey with the actual production autosave, durable undo/redo reads and validated
discard recovery. It contains no signing secrets. The launch-only smoke script remains a
separate check; see the [UI journey evidence and limits](UI_JOURNEY.md).

| Issue / acceptance contribution | Implementation and check | Remaining evidence |
| --- | --- | --- |
| #26 pinned clean checkout; #30 native CI | Checked-in project/local packages, explicit Xcode pin, actual CLI missing-pin regression and isolated-cache workflow | Exact-head hosted evidence and receiving review; #30 untrusted-PR and release-secret gates remain separate |
| #28 restore correct draft | SceneStorage selection, explicit dirty-discard guard, background save attempt; UI test reopens an acknowledged revision after process termination | Hosted UI run pending; cold-link routing, interrupted unacknowledged edits and physical lifecycle qualification |
| #80 local library operations | Create, title edit, duplicate, confirmed delete; real-store model tests and UI save/reopen/discard/delete test | Hosted UI run pending; UI duplicate, complete build metadata/organization and receiving review |
| #87 offline editing | All operations use local storage; unknown compatibility/pricing always explicit | Governed catalog cache and downstream evaluation integration |
| #105 accessibility | System controls, visible labels, Dynamic Type, editor/action identifiers; bounded XCUITest local-draft journey | Hosted UI run pending; wider complete journeys, VoiceOver, large text and physical device audits |

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
The subsequent [undo and autosave implementation](../docs/validation/editor-autosave.md)
adds bounded session undo/redo and a 750 ms typing debounce through the same queued
save path. Input remains editable while saving, and delayed timers/opens cannot
overwrite another draft or newer input. Actual process-kill during UI autosave,
full builder journeys and physical lifecycle qualification remain work under #69.
Hosted exact-head compilation and model tests are required before acceptance.
The [combined editor integration record](../docs/validation/editor-integration.md)
tracks the stronger delayed-open generation guard, retained lifecycle-save regressions,
separate library/editor failure notices and the updated real-timer journey. Previously
passed source runs are historical evidence; the combined source still requires its
own native package execution and both pinned UI destinations.

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
python3 -m unittest discover -s App/scripts/tests -v
python3 App/scripts/toolchain.py -- python3 App/scripts/ui-journey.py
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

## Asynchronous local startup

The #86/#29 startup correction builds on the independently available libraries in
[PR #159](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/159), baseline
`a8d3ac6c449a483a3373ebfaecc6eab4fa9af861`. Each scene owns a `LocalLibraryStartup`
model. Its SwiftUI `.task` awaits `LocalLibraryStores.open`; a detached worker prepares
the same protected Application Support directory and opens/migrates each SQLite
file. App initialization and the main actor do not perform those blocking operations.
Each tab shows a loading indicator, then either its library or an explicit unavailable
state. One failed database still cannot hide the other database's records.

SwiftUI cancellation is forwarded to the detached worker. Synchronous SQLite work
already in flight is allowed to finish or roll back normally; cancellation is checked
before directory preparation, between opens and before publishing. Cancelled results
are discarded, and a generation token prevents an older attempt from replacing a
newer one even if the older operation ignores cancellation. A reappearing scene can
retry incomplete startup; a ready scene retains its connections and editor state.
Separate windows own separate startup lifetimes and use the existing SQLite
transaction/revision guards when accessing the same files.

`LocalLibraryStartupTests` bounds the controlled opener wait to five seconds and
checks an editor binding action on a real selected synthetic draft while opening is
blocked. Its injected nil autosave clock isolates that startup scheduling assertion;
the public app initializer and separate UI journey retain the production timer. It also
checks off-main directory preparation/opening, cancellation between database opens,
superseded results, explicit failure/retry, retained ready state and directory errors.
The timeout is a test deadlock guard, not a responsiveness budget or performance
measurement. `LocalLibraryStoresTests` continues to exercise both corrupt-file cases
using real SQLite through the asynchronous factory. Run these with the existing
`swift test --package-path Packages/PlannerUI` and native UI workflow above.

This is bounded startup/cancellation coverage for #86's #29 prerequisite. Hosted
exact-head Swift/Xcode tests, simulator launch and receiving review are still required;
physical-device responsiveness, locked-device and low-storage behavior, and the full
#29/#86 acceptance criteria are separate. No startup timings or device results are
inferred from static inspection. Apple references checked 2026-10-18:
[app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
and [Task cancellation](https://developer.apple.com/documentation/swift/task).


## Files import and reviewed export

The Imported builds screen uses a separate `imported-builds.sqlite` database in the
same protected Application Support directory. It never treats a canonical build as
notes-editor payload or converts an incomplete note into a valid snapshot. A local
version-1 persistence wrapper holds canonical bytes and untrusted fixture metadata;
unsupported local formats are preserved and refused. Imported builds are read-only.
Each library opens independently. If either database is corrupt or unsupported,
only that tab reports an unavailable library; the other tab remains usable. Two
regression tests corrupt each database in turn and verify that the healthy database
still reopens its saved records (including note history) and corrupt bytes remain
unchanged. These tests exercise real SQLite initialization, not mocked success.

The system Files picker supplies one JSON URL. Security-scoped access lasts only for
a bounded background read (512 KiB actual-byte maximum, checked independently of
metadata); directories and malformed/unsupported/private imports fail without writes.
A preview is not an import. Explicit confirmation creates a fresh wire build ID,
local owner reference and local storage row, preserves version locks, and never
updates the source identity. Imported references are not fetched or rights-approved.

Export requires an explicit public alias, previews the exact projected JSON and asks
the user to review free text before opening the system file exporter. Private owner,
notes and extensions are stripped by PlannerTransfer. Allowed text can still be
sensitive: field filtering is not arbitrary secret detection. Changing the alias or
selection invalidates the prepared export. Marked synthetic imports retain their
fixture label across persistence and re-export via the existing web envelope;
its original source revision is untrusted metadata, not authority. Bare/unmarked
imports remain visibly unqualified, never presented as production data.

Seven controlled model tests cover preview/cancel without writes, repeated fresh-ID
forks and durable reopen, fixture-label preservation, explicit alias/projection,
invalid/oversized files and directories, bounded local-file preview, and preservation
of future stored formats. The bundled synthetic fixture is copied unchanged from
PlannerTransfer/Tests/PlannerTransferTests/Fixtures/build.json (its source manifest
remains authoritative); test projection explicitly removes private fixture settings.
Hosted exact-head compilation/tests are required. Actual Files-provider interactions,
accessibility, complete cross-client UI round trips, process interruption and physical
device/privacy receiving qualification remain unverified. Partial #82/#84/#102 only.
