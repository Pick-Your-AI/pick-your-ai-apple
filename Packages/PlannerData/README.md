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
python3 -m unittest discover -s tools/storage/tests -p 'test_crash_replay.py' -v
swift test --package-path Packages/PlannerData --scratch-path .build-storage -Xswiftc -warnings-as-errors
python3 tools/storage/crash_replay.py .build-storage/debug/DraftCrashProbe
```

The replay driver's exit-code, integrity and migration-rollback checks use
explicit runtime failures and remain active under optimized Python. Its
[portable regression tests](../../tools/storage/tests/test_crash_replay.py)
exercise every probe phase, invalid SQLite contents and changed migration state
in normal and optimized Python, with a valid synthetic protocol control. These
fixtures test the driver; they do not execute Swift or establish native storage
durability. The mandatory hosted step retains `storage-replay-guards.log` with
the existing storage evidence, and the actual native crash probe still runs.

Each native probe phase has a 60-second deadline. If a phase stalls, the driver
kills and waits for that probe, reports the phase and captured diagnostics, and
stops before later recovery checks or a success message. This also bounds local
replay, independently of the hosted job's timeout. Use `--timeout-seconds` only
when an explicit different per-phase deadline is needed; zero, negative and
non-finite values are rejected before starting a probe. Portable guards exercise
timeouts at all seven phase positions, child cleanup and a fresh successful retry
in both normal and optimized Python. These guards use temporary synthetic probe
processes; the real Swift replay and configured native runs remain separate checks.

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

## Durable pending build writes — #89 client boundary

`PendingBuildWriteStore` adds a separate local SQLite queue for immutable write
intents. It implements the client persistence portion of
[Apple #89](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/89), under the
[accepted service decision](../../docs/decisions/issue-23-services.md). It makes no
network request, issues no credential, supplies no service origin and does not
activate a remote lifecycle in the app. The frozen v1 API requires an
`Idempotency-Key` for create and update, plus the exact quoted current revision in
`If-Match` for update. The governed service adapter remains responsible for
BuildSnapshot validity, the candidate's next revision, credentials, object
authority and validated response interpretation.

An intent snapshots the operation ID, method, build ID, stable key, optional
precondition and body bytes. Caller-owned backing storage and later mutations of
returned `Data` cannot change the snapshot. All identifier, key and partition
comparisons use UTF-8 bytes, including Swift value equality and SQLite BLOB keys.
Composed and decomposed Unicode spellings remain different identities. The queue
never normalizes a key, reparses and serializes a body, or advances a precondition.
For this client, opaque labels and keys must be nonempty UTF-8, at most 1024 bytes,
without ASCII control characters. Update preconditions admit exact quoted positive
ASCII decimal revisions without leading zeroes; create admits no precondition.
These admission bounds do not extend or replace the frozen service contract.

The environment/authority partition is an opaque, noncredential isolation label
supplied by the trusted local lifecycle adapter. It is not proof of authentication
or permission to access a remote build. The app must provide its own protected
queue directory and coordinate account changes and file lifecycle. Use a separate
file from `DraftStore`; a distinct application ID and exact schema prevent a draft
or unrelated database from being adopted as a queue.

### Sessions and durable transitions

Opening a handle does not activate a partition or invalidate another handle's
attempt. Explicit `activate` commits a fresh persisted generation and changes all
older attempting rows to uncertain in the same transaction. A store-issued token
also binds the issuing instance. Returning to an earlier partition does not revive
an old token. Reads check the active generation and load private rows in one SQLite
snapshot. Write operations combine that check with their decision under
`BEGIN IMMEDIATE`; actor isolation alone is not the cross-handle lock.

| Operation | Durable result |
| --- | --- |
| `enqueue` | Commits a pending immutable intent before returning it. An identical operation/key and partition returns the existing record, even at capacity. Reuse with any different intent or partition fails without exposing another partition's payload. |
| `beginAttempt` | Commits pending → attempting with a fresh attempt ID before handing the intent to a future adapter. Every earlier unresolved operation for the same partition/build blocks it; another build can proceed independently. |
| `recordOutcome` | A current matching callback can record adapter-confirmed, conflict, invalid or uncertain. Late, foreign and duplicate callbacks return false without rewriting data or a newer state. The queue does not derive confirmation from a status code or current-head GET. |
| `activate` / `deactivate` | Supersedes the active generation and conservatively retains any interrupted attempt as uncertain. A failed commit retains the previous generation and attempts. |

Every transition runs synchronously inside its SQLite transaction. No `await`,
network call or cancellation suspension occurs between validation and commit.
SQLite DELETE journal mode, FULL synchronous writes and checked final-close WAL
checkpoint suppression follow the existing draft storage boundary. Unknown
versions, foreign schemas, invalid SQLite files and unreadable rows are retained.
An unreadable row blocks the whole queue operation; it cannot disappear from
predecessor checks through best-effort decoding. The transactional schema guard
remains in place. Ordinary hot-journal recovery may restore database pages and
remove the journal before schema admission; a rejected already-unsupported or
foreign WAL database retains its main and WAL bytes, with no claim that shared
memory reader marks stay unchanged.

There is deliberately no uncertain → pending transition, automatic resend,
expiry, receipt lookup, deletion or eviction in this increment. After an unknown
acknowledgement, the immutable intent remains available for the separately accepted
reconciliation policy. A latest-build response alone cannot establish which
operation succeeded. The queue cannot revoke bytes already handed to a caller or
cancel an external request: a future transport adapter must coordinate dispatch,
authority changes, cancellation and server-side authorization. No remote success,
idempotency receipt lifetime or replay-safe retention period is inferred here.

Default growth bounds are 256 retained operations and 16 MiB of body bytes, with a
1 MiB per-body bound. Explicit caller limits may allow at most 4096 operations and
64 MiB total. All retained states and partitions count; existing records above a
newly lowered growth limit remain readable. Confirmed records still reserve their
operation IDs and keys. These are client resource limits, not a remote TTL. A
future governed maintenance policy is required before removing records or reusing
identities; this API never silently discards an intent to create space.

### Queue validation

The new suite declares 35 queue methods in addition to the 31 unchanged draft
methods. It covers exact byte identity and copying, duplicate and capacity rules,
cross-handle/ABA sessions, ordering and outcomes, failed commits, actual
`SQLITE_FULL`, foreign/corrupt storage retention, supported WAL/hot-journal recovery
and rejection of committed future metadata held only in an orphaned WAL. Those
method declarations are an inventory, not evidence that a particular environment
executed them. The hosted workflow requires both suites on macOS, compact iPhone
and iPad, and retains the unsigned Simulator SDK compile and original draft replay.

```sh
python3 tools/storage/pending_write_replay.py --self-test
swift test --package-path Packages/PlannerData --scratch-path .build-storage -Xswiftc -warnings-as-errors
python3 tools/storage/crash_replay.py .build-storage/debug/DraftCrashProbe
python3 tools/storage/pending_write_replay.py .build-storage/debug/PendingWriteCrashProbe
```

The pending-write driver requires six actual `_exit(73)` cuts, before and after
the enqueue, attempt and outcome commits. Fresh processes and independent SQLite
reads check state, exact intent and attempt bytes, conservative recovery, and an
unchanged separate draft/history file. Each child has a 60-second deadline; a
timeout stops the sequence after the direct child is killed and reaped. Explicit
runtime checks also remain active under optimized Python. The eleven portable
driver guard methods use synthetic Python probes and test those checks, including
wrong exits, changed bytes/states, malformed metadata, missing output and child
timeout cleanup. They do not execute Swift or establish queue/native durability.
The synthetic confirmed-outcome cut tests a local commit only, not a real service
write or successful authentication.

Primary design references checked 2026-10-19:
[SQLite transaction and failure semantics](https://www.sqlite.org/lang_transaction.html),
[copied bindings](https://www.sqlite.org/c3ref/bind_blob.html),
[result value lifetimes](https://www.sqlite.org/c3ref/column_blob.html),
[checkpoint-on-close configuration](https://www.sqlite.org/c3ref/c_dbconfig_defensive.html#sqlitedbconfignockptonclose),
and [Swift actor isolation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/).
They inform the implementation; source review and actual test output establish
which behaviors have been verified in each receiving environment.

Whole issue #89 remains open until the accepted remote adapter loses an
acknowledgement after a successful server write and reconciles without a duplicate
build or stale overwrite, with independent criterion-specific review. The named
#46 and #86 outputs, guest/object authority, receipt retention/reconciliation,
native app integration, physical-device behavior and operating activation retain
their own owners and evidence gates.
