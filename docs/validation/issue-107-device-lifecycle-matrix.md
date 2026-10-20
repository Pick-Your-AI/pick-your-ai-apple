# #107: Device, OS and lifecycle qualification matrix

This is the evidence intake for [Apple #107](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/107).
It separates the accepted target declaration, observed simulator/package execution,
and the installed-app and physical-device cases still needed for qualification.
It does not expand supported platforms, change a deployment target, or qualify a
release. Criteria 1 and 2 remain open. The documentary third criterion is complete
under the [2026-10-19 receiving disposition](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/107#issuecomment-6260653935).

The execution baseline is signed main
[`518c1c69f8dc5ab82c8fe86da9e9eabd7d707f1e`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/518c1c69f8dc5ab82c8fe86da9e9eabd7d707f1e),
tree `2c620d72926ccd55d52b53dc8ad7a575cdd74d01`, sole parent
`d64dba942a4eeab3950daf0ee3ceffb883166974`, delivered in
[#266](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/266) on
2026-10-19 at 02:58:15 UTC. The completed executions qualified below are the
original attempt-1 **push** runs of that exact commit. Their original logs and
available archives were read without rerunning a project test, build or installer.
The document's later publication commit is not their execution identity.

## Accepted declarations and observed tools

The [accepted platform ADR](../decisions/issue-22-platform.md),
[repository scope](../REPOSITORY_SCOPE.md), [project](../../App/Planner.xcodeproj/project.pbxproj)
and [toolchain records](../../App/README.md#pinned-toolchain) define the baseline.
At the execution revision they declare:

| Boundary | Declared value at 518c1c69 | What it does not establish |
| --- | --- | --- |
| Product device classes | iPhone and adaptive iPad; Xcode device families `1,2` | Availability or successful testing of every physical device, screen size or input mode |
| Deployment floor | iOS/iPadOS 17.0 in both app configurations and the submission-SDK policy | Execution on an iOS 17 runtime or a populated installed upgrade at that floor |
| Development regression toolchain | Xcode 16.4 / build 16F6; actual Swift 6.1.2 and iOS Simulator SDK 18.5 in the selected native runs | A release SDK or the runtime chosen by the separate launch script |
| Submission compatibility toolchain | Xcode 26.3 / build 17C529; actual Swift 6.2.4; device and simulator SDK 26.2 | A signed archive, physical installation, TestFlight or App Store acceptance |
| Assessed application | `invalid.pickyourai.localpreview`, display name `Pick Your AI Local`, version 0.1.0 / build 1; unsigned local Notes app | A production identity, account, shared service or the unmerged combined editor application |
| Additional Apple platforms | Native macOS, Catalyst, watchOS, tvOS and visionOS remain deferred by the ADR; the app disables Catalyst and Mac-designed distribution | macOS package tests do not add macOS to product scope |

Both compiler lanes observed macOS 15.7.9 / build 24G830. The submission artifact
also records hosted image `macos15`, version `20260907.0337.1`. A mutable runner
label, an SDK version and a simulator runtime are different fields. This record
does not declare a new upper OS limit or call an available simulator the complete
current supported-OS matrix. Current Apple submission requirements remain in the
separate dated [policy record](issue-113-policy.md).

## Execution matrix at the pinned source

Evidence keys refer to the immutable run/job and artifact table below. Package
counts are actual unique XCTest method starts and passes matched to test source at
518c1c69. They exclude repeated `grep` summaries and Swift Testing's separate
zero-test footer.

| Observed environment | Exact executed scope | Result | Evidence and limit |
| --- | --- | --- | --- |
| macOS 15.7.9, Xcode 16.4 | `PlannerUI` editor-model suite, using fresh explicit SwiftPM scratch/cache paths | 23 of 23 methods passed; no failed or skipped method | U; controlled model and store calls, not OS lifecycle events |
| macOS 15.7.9, Xcode 16.4 | `PlannerData` storage suite | 31 of 31 methods passed; no failed or skipped method | S; exact durable-store regression source |
| iPhone SE (3rd generation), iOS 18.5 Simulator | `PlannerData-Package` XCTest action | The same 31 source methods passed; `TEST SUCCEEDED` | S; compact-phone storage execution, not a complete app journey |
| iPad (10th generation), iOS 18.5 Simulator | `PlannerData-Package` XCTest action | The same 31 source methods passed; `TEST SUCCEEDED` | S; tablet storage execution, not adaptive-layout or assistive-technology acceptance |
| iPhone 17 Pro, iOS 26.2 Simulator | Install and launch of the unsigned local app compiled with SDK 18.5 | Launch reported PID 14737; required launch/termination commands completed | U; smoke only, without assertions over the larger editor journey |
| iPad Pro 13-inch (M5), iOS 26.2 Simulator | Install and launch of that unsigned local app | Launch reported PID 24327; required launch/termination commands completed | U; smoke only, without resize, keyboard or accessibility assertions |
| macOS 15.7.9, Xcode 16.4 | `PlannerTransfer` boundary/adversarial suite | 79 of 79 methods passed; no failed or skipped method | T; followed by an unsigned generic iOS Simulator SDK compile |
| macOS 15.7.9, Xcode 26.3 | All five package suites | Core 100, Data 31, Transfer 79, Catalog 64, UI 23: 297 of 297 methods passed; no failed or skipped method | K; host execution under the submission compiler, not tests on SDK 26.2 devices |
| Generic iOS Simulator and generic iOS build destinations, SDK 26.2 | Two unsigned `Release` app products | Both builds succeeded; the production inspector recorded matching platform/SDK/build identity and minimum OS 17.0 | K; compilation and metadata inspection, without installation or archived executable-byte inspection |

The storage artifact contains the original simulator inventory and exact selected
UDIDs. Selection required the installed, available iOS 18.5 runtime and one exact
device match per named class before executing either XCTest action. The UI smoke
script instead selected an available runtime and reported the actual 26.2
destinations above. Those destinations cannot be relabeled as iOS 18.5 or minimum
iOS 17 execution.

The source at 518c1c69 does not check the smoke script's shutdown/deletion exit
statuses or bound all its subprocesses. The completed launch receipt therefore
does not establish verified cleanup or deadline behavior. The separate reviewed
[#317](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/317) delivery owns that
correction. Similarly, the completed storage replay does not establish the proposed
probe deadlines in [#340](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/340).
Neither pending source is incorporated into these original results.

### Original evidence identities

| Key | Original run / native job | Original retained artifact | Full downloaded job log: UTF-8 bytes and SHA-256 |
| --- | --- | --- | --- |
| U | [39192437749 / 117868016042](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437749/job/117868016042) | [12160598968](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437749/artifacts/12160598968), `native-local-drafts-evidence`, 14,413 bytes, 12 members; SHA-256 `61c91343d52606144ae945f676fbd1396b5f7650fc642ae24fc6f5c464f901ef` | 267,482; `0aa7a1b2e5f0bc9dd183ba4ba72a3974010554091c05e058cc01eecbbb44c7c2` |
| S | [39192437767 / 117868023148](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437767/job/117868023148) | [12160617844](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437767/artifacts/12160617844), `swift-storage-validation`, 211,449 bytes, 211 members; SHA-256 `382b05a78988a72c20b99efb29f7a82d47889efe18e4ab8c2eefff86f3fa1c1c` | 220,697; `481e7fe1ef2541c49edc2b7c827d6ef98fcf6ea73b16d39adc62ae5b44b5fa50` |
| T | [39192437726 / 117868014452](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437726/job/117868014452) | None: this exact workflow has no upload step and its artifact collection was empty | 138,916; `a0429b15f0442639d5a102d7657ae4b8df4dae682783a1ea2865207abde2b759` |
| K | [39192437680 / 117868023778](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437680/job/117868023778) | [12161796765](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437680/artifacts/12161796765), `unsigned-submission-sdk-evidence`, 51,287 bytes, 16 members; SHA-256 `b137f275b9fa840c27ac0650eda1d4b1aada784704dbedbbb6324fa9f39ca694` | 671,997; `8cb134284dce7ced6979b4f5de2e421c730879678ccbad2638d458269099f4d2` |

Every available ZIP member was read, checked for unique safe paths, and verified
against its CRC and a SHA-256 digest. Each archive's bytes and digest match both
the artifact API record and its original uploader log. All four full job logs
record the exact checkout. K additionally retains the exact commit/tree/parent
receipt. S retains both original `.xcresult` bundles; attendance above was checked
from the complete original `xcodebuild` logs, without claiming a new
`xcresulttool` extraction. K retains build logs and product-inspection JSON, not
the executable products themselves.

The supplementary controls are also scoped to these originals: U ran eight
toolchain failure/recovery methods and verified four absent caches; S ran seven
crash-replay guard methods and the actual child-process replay; K ran 25 toolchain
and SDK/product-rejection methods and verified five absent caches. T used Python
3.14.7 in a fresh venv, installed eight packages with the committed hash-only,
binary-only lock, passed `pip check`, verified twelve canonical source hashes and
2,807 canonical cases (129 shared, 1,635 Catalog, 202 quality, 520 cost, 223
resource-estimate and 98 placement). Those Python observations do not add native
device coverage.

At the separate 2026-10-19 03:40:42 UTC workflow readback, the original
[Core run 39192437732](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437732)
was running and [Catalog run 39192437830](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437830)
was queued. Their outcomes are not inferred from K's successful host package
suites. A later qualification must retain their own checkout, actual attendance
and artifacts; this dated observation is not a new execution or a current-status
promise.

### Later Core qualification — 2026-10-19 04:01:58 UTC

The same original attempt-1 [Core run / job 39192437732 / 117868013436](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437732/job/117868013436)
completed successfully at 03:44:49 UTC and was qualified from its original output
at the time above. The same 100 source methods passed once in each of debug and
optimized macOS tests, iPhone SE (3rd generation) and iPad (10th generation) tests;
both simulators used iOS 18.5 / runtime build 22F77. All four lanes had zero failed
or skipped methods. A separate unchanged mutation baseline passed those same 100
methods; these are repeated executions of 100 unique tests.

The original normal and optimized Python 3.12.10 mutation-runner controls each
passed all 22 methods. The intentional single-test failure exercised the nonzero
exit gate. All three semantic mutations were detected by their exact selected
regressions: required-field, decimal-comparison and request-generation. Their
two, six and one assertion failures are expected negative evidence. The retained
report is written only after the source guard requires exit 1 for each mutation;
it does not separately print a return-code table.

The full original job log is 370,018 UTF-8 bytes, SHA-256
`7ca5acd03a314f6957993545aaa60a55d78ad5881224ff677df491fc7657caed`.
Its [original artifact 12161303735](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39192437732/artifacts/12161303735),
`swift-core-validation`, is 515,147 bytes with 495 members and SHA-256
`15bef210208e16abd9f54671f67bfb3d627c8698ce0ce232a01703939c5b0c54`.
All member CRCs/digests and API/uploader/archive identities were checked. The
original XCTest logs supply attendance; no new native or `xcresulttool` execution
was performed. Core package tests do not complete the installed-app lifecycle or
physical-device rows below. The separate Catalog run was in progress at the
04:02:39 UTC readback; no Catalog outcome is qualified here.

## Lifecycle cases and remaining gaps

The required #107 case is to upgrade a populated installation, terminate or
background it, and exercise low-resource states on the declared device/OS classes.
The following table preserves the useful existing lower-level evidence without
converting it into that full installed-app case.

| Case | Existing observed contribution at 518c1c69 | Remaining qualification |
| --- | --- | --- |
| Populate, migrate and reopen stored revisions | S executed `testLegacyMigrationPreservesHistoryAndIsIdempotent`, `testVersionTwoMigratesWithoutChangingExistingHistory` and `testInterruptedMigrationRollsBackSchemaThenRecovers` on the host and both named 18.5 simulators | Install an identified older app, populate it, upgrade to an identified new binary on each selected OS/device class, and compare acknowledged drafts/history before and after. Synthetic legacy SQLite construction is not an installed-app upgrade. |
| Abrupt termination during durable writes and migration | S's production crash replay actually required child exit 73 after history write, before commit and during migration, then reopened and checked preserved state/integrity | Replay the actual installed application's interruption points and preserve the original failed and recovery observations. This process-exit probe is not power loss, jetsam or a UI-process termination. |
| Background saves while work is in flight | U passed `testLifecycleSaveDuringHistoryReadIsDrainedWithLatestEdits` and `testLifecycleSaveDuringRestoreUsesNewRevisionAndLatestEdits`; other model cases preserve newer edits and conflict guidance | Exercise real OS background/foreground and cancellation during the current visible journey. A controlled model method call is not an observed scene transition. Unacknowledged in-memory edits retain their documented risk. |
| Storage exhaustion and recovery | S's `testActualSQLiteFullRollsBackThenUnconstrainedReopenRecovers` constrains actual SQLite pages, receives `SQLITE_FULL`, retains the old draft and succeeds after unconstrained reopen | Qualify the installed app's low-storage presentation and recovery on the selected device classes. This is a real database-full result, not evidence of OS-wide disk exhaustion. |
| Corrupt or future data | S passed future-schema/WAL/hot-journal, corrupt-row, missing-history and diagnostic-redaction controls without a silent destructive reset | Verify the corresponding current app presentation and recovery with retained synthetic state on each required installation; do not expose user databases as evidence. |
| Terminate, then cold-open a second build link | The assessed main app provides local Notes; its U smoke contains no second-build-link assertion | [#28](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/28) still needs the named lifecycle/navigation output and explicit navigation that preserves the first draft. Pending combined-editor source is not execution of this main. |
| Minimum OS and physical devices | The accepted floor is 17.0; the originals above execute named simulators or macOS host tests | No iOS/iPadOS 17 execution or physical-device receipt is qualified here. Record actual available hardware and OS builds before committing a run; absent hardware remains a gap, not a simulated pass. |
| Memory pressure, energy/thermal pressure and foreground responsiveness | Parser/storage bounds and successful package tests provide functional controls | No measured OS pressure, jetsam, battery/thermal, rendering or performance-budget result is supplied. Use [#109](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/109)'s observed and reviewed budgets rather than inventing thresholds. |
| Locked data, backup/restore and device-only interaction | Main configures its Application Support directory for protection until first user authentication | Locked-device attributes, journal/backup behavior, VoiceOver, accessibility text sizes, rotation, iPad resizing and keyboard interaction require their own actual checks under [#99](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/99), [#105](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/105) and affected feature acceptance. No result is supplied by SDK compilation. |

The exact [storage test source](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/518c1c69f8dc5ab82c8fe86da9e9eabd7d707f1e/Packages/PlannerData/Tests/PlannerDataTests/DraftStoreTests.swift),
[UI model test source](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/518c1c69f8dc5ab82c8fe86da9e9eabd7d707f1e/Packages/PlannerUI/Tests/PlannerUITests/DraftLibraryModelTests.swift)
and [crash replay](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/518c1c69f8dc5ab82c8fe86da9e9eabd7d707f1e/tools/storage/crash_replay.py)
define these controls. The existing [storage acceptance record](../acceptance/issue-86-durable-storage.md)
and [toolchain receipt](toolchain-pin.md) retain their older execution identities;
this matrix adds the explicit later 518c1c69 observations without replacing them.

## Completing a row with actual evidence

Before an installed lifecycle run, identify the available device class and exact
OS build, the old and new application builds/source revisions, installation
channel, SDK/compiler, and the synthetic fixture/draft/history identities. Keep a
physical device's personal identifiers and real account or workload data out of
public artifacts. Record an unexecuted row as such if hardware, a prior installable
binary, an accepted feature input or its receiving owner is missing.

For the required upgrade/interruption case, retain the acknowledged state from
the old installation, the exact interruption trigger and point, the observed
error or exit, and the state read by the new/reopened installation. Compare the
original draft identity, committed revision, title/payload and retained history;
separate unacknowledged editor changes from committed data. Exercise both the
failure and recovery path. Record the actual app-visible unavailable/conflict
state instead of treating a process's successful exit as sufficient evidence.

Attach the original run/job and report identities, source and fixture hashes,
actual named attendance, screenshots where applicable, and the outcome for each
case. Retain failed/cancelled attempts with their causes rather than replacing
them with a later pass. A successful replay belongs to its own exact source and
environment. Preserve a durable, reviewed evidence record before a workflow
artifact expires; a missing original must remain a provenance gap.

The quality reviewer and affected feature consumer named by #107 must review the
same completed row and dispose of its limitations. Coordinate the actual
navigation, storage and combined-editor receivers already owning those changes;
this matrix neither starts a replacement receiver nor approves their unpublished
source. Source inspection, model/package tests, simulator application checks,
physical-device evidence and signed release acceptance retain distinct scopes.

## Criterion disposition and prerequisites

| Literal #107 criterion | Disposition of this record |
| --- | --- |
| Release qualification covers all declared supported device classes. | Incomplete. The declaration and observed classes are explicit; minimum-OS, physical, installed upgrade and low-resource gaps remain. |
| Upgrade a populated installation, terminate/background it and use low-resource states on declared OS/device classes; unavailable physical devices remain qualification gaps. | Incomplete. The existing migration, process-exit, background-save model and database-full contributions are mapped above, with no fabricated installed/device execution. |
| The device/OS/lifecycle qualification matrix is linked with criterion results, exact versions, limitations and receiving-review disposition. | Complete for the delivered, reviewed matrix at [signed 84c05bb0](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/84c05bb0034f604580077f1ea403386b94128b7e/docs/validation/issue-107-device-lifecycle-matrix.md), published through [#344](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/344) and accepted in the [2026-10-19 receiving disposition](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/107#issuecomment-6260653935). Criteria 1 and 2 remain open; original execution identities and limitations are preserved. |

The [#28 prerequisite](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/28)
is the correct interrupted/deep-linked draft journey. The
[#86 prerequisite](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/86)
is preservation of supported drafts and revision history across restart/upgrade.
Their named outputs gate integrated acceptance; the issue explicitly permits
preparation before all upstream scope is complete. This record supplies no new
service, shared schema, owner assignment, release date, physical-device capacity,
store authorization or acceptance waiver. Unresolved release criteria and
ownership decisions retain the existing [#25 route](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/25).
