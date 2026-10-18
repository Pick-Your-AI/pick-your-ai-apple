# #86: Durable local storage and migration receipt

Scope: [Apple #86](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/86),
reviewed on 2026-10-18. This receipt addresses its local database, revision history,
migration and recovery criteria. It does not establish device-release qualification,
protected-data behavior, remote synchronization or UI autosave timing.

## Reviewed implementation and execution

The transactional store was merged by [PR #137](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/137)
at `aa7da9b0e510b887e40a085aef009a2879b55b6c`, with signed implementation
`72d6ec94a7d8c85212d586cae5f65fdc82d33791`. The
[independent implementation review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/137#pullrequestreview-5560851259)
reproduced the tests and actual process exits, and required the subsequently fixed
deleted-ID reuse race. Atomic retirement now prevents delayed writes from recreating
a deleted identity.

[PR #144](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/144) added executed
iPhone/iPad storage tests, merged at `c17a152d9cfdc0b9bd6029f3e97aedbf30dc04cb`.
Its [final review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/144#issuecomment-6244473412)
verified both previously failing native build paths were corrected and all 25 tests
actually executed on each simulator. The test-count and migration assertions remain.

This receipt independently inspected the successful post-merge storage
[run 39089657213](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39089657213),
[job 117563489464](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39089657213/job/117563489464),
at signed main commit `96470f2ec60516ad668a546eecbe2825fc8689de`:

| Execution | Observed result |
| --- | --- |
| Toolchain and host | Xcode 16.4, build 16F6; Apple Swift 6.1.2 (`swiftlang-6.1.2.1.2`); arm64 macOS 15.7.9, build 24G830 |
| macOS package tests | 25 tests passed, zero failures; warnings treated as errors |
| Abrupt-process replay | Three actual `_exit(73)` boundaries passed: after an uncommitted history write, before commit, and during migration; a new process verified the durable revision |
| iOS Simulator SDK build | Unsigned compilation succeeded |
| iPhone SE (3rd generation), iOS 18.5 | All 25 storage tests passed, zero failures, including interrupted-migration recovery; `TEST SUCCEEDED` |
| iPad (10th generation), iOS 18.5 | All 25 storage tests passed, zero failures, including interrupted-migration recovery; `TEST SUCCEEDED` |
| Retained evidence | [Artifact 12122975406](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39089657213/artifacts/12122975406), `swift-storage-validation`: toolchain/test/build/crash logs, simulator inventory and selection, and both xcresult bundles; workflow retention is 14 days |

All fixtures are synthetic and temporary. Result bundles/logs are execution evidence;
their temporary retention does not change the immutable source and replay commands.
The same storage implementation, tests and crash probe are identified below.

| Source | SHA-256 |
| --- | --- |
| `Packages/PlannerData/Sources/PlannerData/DraftStore.swift` | `19bdb1e82ef64574f7eeed7c85c681a8f3ca16b52472bdd04903b0124a406f14` |
| `Packages/PlannerData/Tests/PlannerDataTests/DraftStoreTests.swift` | `4c19e23606f982e883b469e7c51ec0a16839937bf9d0284fb3bde6d5bdbbffbc` |
| `Packages/PlannerData/Sources/DraftCrashProbe/DraftCrashProbe.swift` | `ca8051725f40b8df8823fa538734897718f494247c9358ce2422461aeb437636` |
| `tools/storage/crash_replay.py` | `e32241a4acc0c57ae8fcb5171867d1997d4f612f7655423b1d12c5df48465e42` |

## Criterion-specific disposition

| Live #86 criterion | Evidence and result |
| --- | --- |
| Restart and upgrade preserve supported drafts and revision history. | Schema 1/2 to 3 migration tests preserve the existing draft/history, reopen idempotently, and retain exact payload bytes and version locks. Revision checks, history writes, restoration and identity retirement are transactional. Stale writers and restores cannot overwrite newer revisions. |
| Interrupt migration with existing revisions. | The legacy fixture contains an existing head and history row. The controlled migration error rolls schema changes back; the separate actual-exit replay terminates the process during migration, verifies schema 1 and no partial column, then reopens/migrates and verifies the original revision and history. |
| Simulate disk exhaustion. | `testActualSQLiteFullRollsBackThenUnconstrainedReopenRecovers` constrains SQLite pages, attempts a 500,000-character payload, observes actual `SQLITE_FULL`, reopens the unchanged prior draft, and successfully retries after removing the constraint. The before-commit failure test separately verifies delete rollback. |
| Reopen a corrupt record and retain recoverable data without a silent destructive reset. | The 503-record test corrupts one row, reports it through `unreadableCount`, renames/deletes another row, reopens and retains the other 501 readable records plus the corrupt bytes. Other tests reject malformed current rows, disclose missing history, preserve an unsupported schema, and leave a corrupt database file byte-for-byte unchanged. |
| Link the versioned schema and migration/recovery tests with criterion results, exact versions, limitations and receiving review. | This receipt links immutable implementation/review identities, directly inspected successful execution, source hashes and reproducible checks. Independent technical receiving disposition is recorded on the publishing PR; issue closure waits for that review and signed main publication. |

Reproduce using the [PlannerData instructions](../../Packages/PlannerData/README.md#reproduce),
[storage tests](../../Packages/PlannerData/Tests/PlannerDataTests/DraftStoreTests.swift),
[crash replay](../../tools/storage/crash_replay.py), and the
[pinned workflow](../../.github/workflows/swift-storage.yml). Failed storage operations
return payload-free errors and never initialize a replacement database.

## Scope reconciliation and remaining work

The two native prerequisites gate their named output for this storage integration,
not closure of their entire feature scope:

| Prerequisite | Storage-facing output |
| --- | --- |
| #29: responsive UI boundary and no stale overwrite | The main-actor editor awaits the separate storage actor and bounds its loaded library to 20 records. `testEditsArrivingDuringSaveRemainDirty` pauses storage, changes editor state while the request is pending, and verifies the late acknowledgement retains the newer input for another revision. Conflict, failed-refresh, dirty-navigation and deletion-race tests preserve the relevant state. [Native run 39088274930](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39088274930) succeeded on signed main `c17a152d9cfdc0b9bd6029f3e97aedbf30dc04cb`, including these model tests, unsigned app build and iPhone/iPad launches. This supplies the asynchronous local-storage boundary; it does not claim complete app-wide network cancellation, frame-performance or #29 acceptance. |
| #33: distinct draft and valid-snapshot boundaries | Merged [PR #141](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/141) validates the immutable snapshot transition. The real-store empty-draft/rejected-export test preserves exact draft bytes, locks, revision and history after reopening. Its criterion-specific receiving receipt is tracked in [PR #160](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/160); publication does not redefine the draft as a complete build. |

The live task requires the selected durable database and its migration/recovery
output. The earlier package README listed app integration, the full supported device
upgrade matrix and protected-data tests as broader gaps. Those notes do not add new
criteria to #86. Actual OS/device release qualification remains
[#107](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/107), protected-data
and locked-device behavior remain [#99](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/99),
and timed editor autosave/termination remains [#69](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/69).

The process-exit replay is a host-side storage test, not a physical power cut or
termination of the installed app during an unacknowledged UI save. Simulator tests
exercise the library on iOS 18.5; minimum-OS/physical-device upgrades are unverified.
Accounts and remote synchronization are outside this local-store boundary. This
receipt invents no human, product, privacy, store or production approval and closes
no broader issue. Technical receiving review uses the user's delegated engineering
authority and is explicitly separate from those approvals.
