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
edits. UI revision-history/undo and autosave crash recovery remain work under #69.

Storage opens in Application Support under a directory protected until first unlock.
A failure shows an unavailable screen and never resets the database. Locked-device
and low-storage behavior still require physical-device qualification.

Primary Apple references checked 2026-10-18: [scene phase](https://developer.apple.com/documentation/swiftui/scenephase),
[file protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication).
Local Linux inspection cannot establish SwiftUI/Xcode correctness. See the PR checks
for observed hosted results, distinct from device, store or production acceptance.


## Files import and reviewed export

The Imported builds screen uses a separate `imported-builds.sqlite` database in the
same protected Application Support directory. It never treats a canonical build as
notes-editor payload or converts an incomplete note into a valid snapshot. A local
version-1 persistence wrapper holds canonical bytes and untrusted fixture metadata;
unsupported local formats are preserved and refused. Imported builds are read-only.

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
preparation causes an explicit rejection and requires reopening the entry. Confirmed deletion carries
the exact selected row/revision; another selected entry is preserved.

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
These added tests require their exact-head hosted SwiftUI test/build execution before
acceptance; no result is inferred from source inspection. Three added PlannerData
regressions exercise a prepared fork against source changes/deletion through another
connection and a successful distinct-payload insert with exact source/history
preservation after reopening. The storage simulator gate requires the new stale-source
cases and all 28 storage tests to pass. Existing PlannerData tests
separately exercise actual malformed SQLite rows, storage exhaustion and migration.
Actual Files-provider/cross-client journeys, unavailable/revoked remote references,
VoiceOver and physical-device behavior retain their own unverified acceptance gates.

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
