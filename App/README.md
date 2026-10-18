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
| #80 local library operations | Notes CRUD plus imported-build local labels, fresh-fork duplication, confirmed deletion, revision/qualification display and bounded corrupt-wrapper recovery | Exact-head native CRUD/recovery execution, cross-client journey and receiving review |
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
versioned persistence wrapper holds canonical bytes and untrusted fixture metadata.
Version 1 entries reopen without rewriting; newly confirmed or duplicated forks use
version 2 to record local source lineage. Unsupported local formats are preserved
and refused. Imported builds are read-only.
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

Preview parsing and export validation/projection/encoding also use the existing
detached preparation boundary. Export captures the selected row, qualification and
public alias synchronously before its worker task is queued; alias changes invalidate
both queued and in-flight results. Cancellation cannot publish prepared bytes or a
late failure. Six controlled regressions block real preparation while another notes
editor processes a main-actor edit, then check cancellation, invalidation, retained
qualification and unchanged durable records. See the [preparation validation record](../docs/validation/import-preparation.md).
Their exact hosted native execution remains required; this scheduling coverage does
not establish a measured performance budget or full Files/lifecycle acceptance.

## Organize the imported-build library

Each entry displays its local revision and the fact that imported evidence has not
been revalidated. The selected entry also shows its pinned wire snapshot revision,
original snapshot name and existing synthetic/unknown qualification. A local label
is revisioned library metadata: renaming preserves the exact stored snapshot bytes,
locks and previous label revisions. Export continues to project the pinned snapshot.

**Duplicate as new local fork** validates the selected stored revision, then uses
the existing transfer fork boundary to create distinct wire and local identities.
It preserves the local label, component/settings/version locks, and synthetic/source
metadata; the original entry and its history remain intact. The duplicate starts at
local revision 1 with no current analysis. The source revision check and new row
insert share one SQLite transaction, so a newer revision or deletion during fork
preparation causes an explicit rejection and requires reopening the entry. Confirmed
deletion carries the exact selected row/revision; another selected entry is preserved.
After a successful deletion, any baseline pinned from that local row and its prepared
comparison are cleared. A failed deletion cannot acknowledge that invalidation.

Each new fork records the immediate source build ID, pinned wire revision and SHA-256
of the normalized snapshot bytes captured before copying. A duplicate also retains
the source entry's recorded ancestors, nearest source first. The selected fork shows
the entire bounded lineage; renaming or deleting another local entry cannot rewrite
it. Older entries explicitly report unknown earlier lineage. Their first duplicate
records only the snapshot that is actually available, without inferring missing
ancestors. At 32 retained sources, another duplicate fails visibly and preserves the
source instead of truncating history. Lineage is local metadata, not authenticated
ownership or current evidence, and is excluded from exports. Reimporting an export
starts a new record from the received snapshot and cannot assert its private prior
history. See the [local fork validation record](../docs/validation/local-fork-lineage.md).
Account-backed continuity remains disabled under the selected #24 scope.

Pages contain at most 20 stored rows. Stored-snapshot decoding and fork preparation
run off the main actor. Malformed or unsupported stored wrappers are preserved and
counted alongside unreadable database rows. Page offsets count both kinds, including
an entirely unreadable page, so later valid entries remain reachable. The Refresh
builds action retries reading; a successful read clears only a library-read error,
leaving unresolved mutation errors visible until the entry is reopened or corrected.

Seven additional real-store model regressions cover local rename/restart/history,
fresh-fork duplication with retained synthetic qualification, stale CRUD rejection,
confirmed deletion after selecting another entry, 503-entry recovery beside a
malformed wrapper, an entirely unreadable page followed by a valid entry, and invalid
qualification metadata. The large-library case expects 501 valid entries plus the
preserved unreadable row after one deletion, with exact unrelated metadata/history.
The native workflow requires every one of those seven named tests to report a pass
in the complete PlannerUI suite. Their exact-head hosted SwiftUI test/build execution
is required before acceptance; no result is inferred from source inspection. Three added PlannerData
regressions exercise a prepared fork against source changes/deletion through another
connection and a successful distinct-payload insert with exact source/history
preservation after reopening. The storage simulator gate requires the new stale-source
cases and all 28 storage tests to pass. Existing PlannerData tests
separately exercise actual malformed SQLite rows, storage exhaustion and migration.
Actual Files-provider/cross-client journeys, unavailable/revoked remote references,
VoiceOver and physical-device behavior retain their own unverified acceptance gates.

Six further real-store regressions cover exact captured source identity/bytes, chains
after ancestor rename/delete/reopen, unchanged legacy rows, malformed local lineage,
the explicit history bound, and privacy-preserving export/reimport. Native CI requires
all six named tests to pass alongside the existing imported-library cases. Source
preparation does not establish their execution or close #84.

Native confirmation data follows Apple's
[alert presentation](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:message:)-8584l)
and [confirmation dialog](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:message:))
interfaces (checked 2026-10-18); the captured entry/revision stays separate from the
Boolean presentation state.

## Local configuration comparison

Open an imported build, choose **Use selected build as baseline**, open another
imported build, and explicitly compare. The baseline is an immutable snapshot held
in memory until replaced or cleared. Preparing a comparison captures both build
identities and their synthetic/unknown labels together. Selecting a different build
invalidates the prepared result; it does not silently change the pinned baseline.

The result shows both names, build IDs and revisions, followed by the evidence
notice and every returned configuration difference. Selection kinds carry their
canonical T0–T6 display grouping. Before/after values preserve **Not set**, **Hidden
for privacy**, zero, false, null and empty text as distinct states. Explicit type
labels prevent user-entered strings such as "Not set" from impersonating absent or
hidden fields. Three presentation regressions cover these collisions and full
multiline text. Multiline system
text and a scrolling list avoid a shortened preview of the result. An ambiguous
identity, conflicting revision or more than 2,048 differences produces an explicit
failure message and preserves both builds; no incomplete result is presented.

This screen uses the tested PlannerTransfer comparison boundary without writes or
service calls. It does not compare outcome, quality, capacity, compatibility or cost:
each side still needs qualified evidence matching its own component tuple, workload,
versions, units and conditions. Equal settings do not establish readiness or rights.
The screen is limited to existing read-only imported local forks; it does not add a
builder, revision-history editor or cross-client service. Partial #81 only.

The portable comparison tests cover missing/zero distinctions, changed component
settings and locks, unmatched extension measurements, privacy masking, duplicate
identities, reordered selection/link arrays and the explicit result limit. Native
compilation must pass in the exact-head hosted workflow. Files-picker interaction,
the complete visible comparison journey, large text, VoiceOver and physical-device
acceptance still require their own observed evidence.
