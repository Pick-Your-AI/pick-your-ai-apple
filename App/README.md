# Native local draft preview

This unsigned iPhone/iPad app composes `PlannerUI` and `PlannerData`. It is a local
editor with a separate read-only imported-build library and reviewed JSON file export.
It has no catalog UI, evaluation, account, remote sync or release configuration. The reserved `invalid.pickyourai.localpreview` bundle ID is for simulator
use only; it does not allocate a production application identifier or signing team.

The delegated engineering mandate selects SwiftUI/iOS 17 and the local SQLite actor
implemented in PlannerData for this executable slice. This advances the proposed
[#22 ADR](../docs/decisions/issue-22-platform.md); its previous Core Data recommendation
is superseded for this local store only. Product receiving acceptance stays separate.

On macOS with Xcode 16.4 selected:

```sh
swift test --package-path Packages/PlannerUI
xcodebuild -project App/Planner.xcodeproj -scheme Planner -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/native CODE_SIGNING_ALLOWED=NO build
python3 App/scripts/simulator-smoke.py
```

The workflow records the actual compiler/SDK/runtime and runs model tests, an unsigned
simulator build, and iPhone/iPad launch smoke checks. It contains no signing secrets.
The smoke script is not an accessibility or complete journey test.

| Issue / acceptance contribution | Implementation and check | Remaining evidence |
| --- | --- | --- |
| #26 fresh checkout scaffold; #30 CI | Checked-in Xcode project/scheme, local packages and pinned Xcode selection | Hosted run needed; no release configuration or signed archive |
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
edits. UI revision-history/undo and autosave crash recovery remain work under #69.

Storage opens in Application Support under a directory protected until first unlock.
A failure shows an unavailable screen and never resets the database. Locked-device
and low-storage behavior still require physical-device qualification.

Primary Apple references checked 2026-10-18: [scene phase](https://developer.apple.com/documentation/swiftui/scenephase),
[file protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication).
Local Linux inspection cannot establish SwiftUI/Xcode correctness. See the PR checks
for observed hosted results, distinct from device, store or production acceptance.


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
checks an editor binding action on the main actor while opening is blocked. It also
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
