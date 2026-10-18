# Transactional local drafts

`PlannerData` is an executable Swift 6/SQLite local storage library for Apple #33,
#69, #80 and #86. It is independent of the client-core changes in PR #133 and uses
only Foundation and the platform SQLite library. iOS/iPadOS 17 and macOS 14 are
compile targets; macOS is a validation host, not an approved additional product.

A draft is a UUID, title, monotonically increasing revision and bounded JSON
object bytes. `{}` is valid: the editor need not invent contract-required fields.
Payload bytes (including decimal strings and revision locks) are retained exactly.
This API does **not** validate or export BuildSnapshots. An incomplete draft must
still pass the separately governed snapshot transition before export or sharing.

`save` requires the exact expected revision (nil means create only). Rename and
restore append immutable history. Restore requires the current revision and
records `restoredFrom`; it cannot erase edits made since an undo was offered.
Duplicate creates a distinct UUID. Delete atomically removes that draft and its
history, retaining only its retired UUID to prevent delayed creates/edits from
reusing the identity and bypassing revision checks. No workload bytes are retained
in the retirement table. Database/file destruction is a separate identity-lifecycle
operation, not a side effect of a failed migration or logout.

Current analysis is never inferred from draft/history content: `analysisIsCurrent`
is false. The client must recompute or obtain revision-bound evidence through its
analysis layer. This library has no remote writes, account credentials, telemetry,
share publication or automatic import of external files.

## Transactions and failure recovery

The actor serializes one connection. `BEGIN IMMEDIATE` also serializes writers
across connections. Revision checks, head/history updates, retirement markers and
deletes commit atomically. DELETE journal mode and FULL synchronous writes are
explicit; acknowledgement follows a successful commit. No test claims hardware
power-loss durability beyond SQLite/filesystem guarantees.

Schema v1 stores heads and revisions; v2 adds restoration provenance; v3 adds
retired identities. All pending upgrades execute in one transaction. Unknown
versions, corrupt databases and failed migrations produce errors without a
reset. A corrupt record remains in storage; paginated reads return recoverable
records plus `unreadableCount`. The UI must disclose that count. Missing or corrupt
heads cannot be overwritten through save. Restore also rejects a corrupt history
revision newer than the current head before writing, preserving the readable head
and the original history for recovery. There is no automatic salvage of broken
SQLite pages or silent replacement of a damaged database.

Before the first database read, the connection disables SQLite's final-close WAL
checkpoint and checks both the configuration result and effective setting. The
effective schema version is then read before changing journal mode or starting
application migrations. This includes committed changes held only in a WAL, even
when the main database header still looks supported. A WAL database whose version
is already unsupported when admission reads it retains its database and WAL bytes
on rejection; temporary shared-memory reader marks are not immutable evidence.
The normal transactional version check remains in place.

SQLite must restore an interrupted transaction's hot rollback journal before it
can read a consistent schema version. The connection allows that recovery, which
may restore database pages and remove the journal. If the recovered version is
unsupported, initialization rejects it without application schema or data changes.
This is distinct from a reset or a promise that all interrupted files remain
byte-identical. The caller still owns the directory and coordinates identity,
database replacement and other external file-lifecycle changes.

SQLite is an implementation choice under the user's delegated engineering mandate,
replacing the earlier proposed Core Data default for this local library. Its
transaction and migration behavior can be exercised on Linux and hosted macOS
without a new package dependency. This does not accept all of #22 or establish
physical-device storage behavior. The app must still supply an app-owned protected
directory, configure backup/file-protection policy, isolate identities, and test
locked-device behavior. No database files should be attached to public issues.

Primary references checked 2026-10-18: [SQLite transactions](https://www.sqlite.org/transactional.html),
[PRAGMA configuration](https://www.sqlite.org/pragma.html),
[checkpoint-on-close configuration](https://www.sqlite.org/c3ref/c_dbconfig_defensive.html#sqlitedbconfignockptonclose),
and [hot-journal recovery](https://www.sqlite.org/lockingv3.html#dealing_with_hot_journals). Their documented guarantees
are design inputs; the tests below are evidence of this implementation's behavior.

## Reproduce

On macOS with Xcode 16.4 (16F6), or Swift 6.0.3 on Linux with SQLite headers/library:

```sh
swift test --package-path Packages/PlannerData --scratch-path .build-storage -Xswiftc -warnings-as-errors
python3 tools/storage/crash_replay.py .build-storage/debug/DraftCrashProbe
```

Tests cover incomplete drafts, exact-byte locks, stale writes, restoration, scoped
CRUD, corrupt records in a 503-entry library, migrations, actual `SQLITE_FULL`
using a page-count limit, failure rollback, and identity retirement. The crash
probe calls `_exit(73)` after an uncommitted history write, before commit, and during
migration. A fresh process checks the original durable revision and integrity.
These are real abrupt process exits, not physical power cuts or OS kill-on-device
measurements. All fixtures are synthetic and temporary. The probe is a test utility,
not an app target or an installation/release artifact.

Five additional storage regressions cover a closed future-schema WAL database,
a future version committed only in an orphaned WAL, a supported WAL database that
migrates and remains writable, supported hot-journal recovery, and rejection of an
unsupported version after rollback recovery. The orphaned WAL and hot journals are
snapshots of real SQLite output copied while their writers are idle; no connection
holds the copied database open. The journal fixtures use a small page cache and
`sqlite3_db_cacheflush` to capture spilled, uncommitted pages with a valid hot journal.
These deterministic fixture tests run without spawning child processes on iOS.

On 2026-10-18, the closed-future case
failed against accepted main `51952c75f2280d57891491903e495fb822b83bfd`: the expected
unsupported-schema error was raised, but database bytes changed and journal mode
became DELETE. The corrected local Swift 6.1.2/Linux suite passed all 30 methods
with zero failures or skips and compiler warnings treated as errors.
These portable results do not substitute
for the configured macOS/iPhone/iPad receiving runs or device qualification.

The [CI workflow](../../.github/workflows/swift-storage.yml) repeats macOS tests,
crash replay and an unsigned iOS Simulator SDK compile. Compilation is distinct
from running a UI, simulator lifecycle tests or physical-device qualification.

## Acceptance boundaries

| Issue | Executed library behavior | Remaining issue-specific work |
| --- | --- | --- |
| #33 | Empty draft saves and reopens; exact payload/lock bytes survive; PlannerTransfer validates the immutable snapshot transition | [Criterion-specific transition receipt](../../docs/acceptance/issue-33-draft-snapshot-boundary.md) reconciles the completed boundary; timed UI autosave and Files journeys remain separate issues |
| #69 | CAS, appended restoration, stale undo rejection; real crash recovery | Editor autosave wiring, process termination during actual UI edits, analysis-state integration |
| #80 | Rename/duplicate/delete, paginated large library, corrupt-record isolation and restart | Native library UI, evidence state display, cross-client build round-trip and private projection |
| #86 | Schema 1/2→3, interrupted upgrade, actual capacity error, rollback/retry, corrupt DB retention; 25 tests also executed on iPhone/iPad simulators | [Criterion-specific storage receipt](../../docs/acceptance/issue-86-durable-storage.md) records the verified database boundary; closure still requires the reviewed #166 off-main startup integration and #33 receipt on signed main. Full device qualification and protected-data work remain #107/#99 |
| #98 | [Reviewed data inventory, threat model and mitigation register](../../docs/validation/issue-98-data-threats.md) traces delivered storage and the exact native Files candidate | Imported-build deletion and device/provider/service qualification remain explicit |

Other rows remain partial criteria results; issue closure follows its exact receipt,
independent review, named prerequisites and signed main integration. See the [all-issue acceptance map](../../docs/acceptance/README.md) for exact
criteria and remaining executable work. Product/domain receiving acceptance is not
fabricated; it does not prevent independently testing this implementation.
