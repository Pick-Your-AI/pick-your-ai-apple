# Native local draft preview

This unsigned iPhone/iPad app composes `PlannerUI` and `PlannerData`. It is a local
editor, with no catalog, evaluation, snapshot export, account, remote sync or release
configuration. The reserved `invalid.pickyourai.localpreview` bundle ID is for simulator
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

Storage opens in Application Support under a directory protected until first unlock.
A failure shows an unavailable screen and never resets the database. Locked-device
and low-storage behavior still require physical-device qualification.

Primary Apple references checked 2026-10-18: [scene phase](https://developer.apple.com/documentation/swiftui/scenephase),
[file protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication).
Local Linux inspection cannot establish SwiftUI/Xcode correctness. See the PR checks
for observed hosted results, distinct from device, store or production acceptance.
