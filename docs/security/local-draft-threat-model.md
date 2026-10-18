# Local draft storage threat model

Scope: the `PlannerData` implementation in this PR, related to Apple #98, #99,
#100 and #102. This is a concrete storage assessment, not the complete app/service
threat model or security receiving acceptance. All test inputs are synthetic.

## Data and boundaries

A caller supplies a UUID, a title and JSON editor bytes. Those bytes may contain
sensitive workload descriptions, incomplete configuration and pinned version locks.
The store deliberately does not infer privacy from a field name. It persists the
bytes in SQLite heads/history, including the rollback journal during a transaction.
Restoring history returns earlier bytes as a new revision. Local duplication copies
them under a fresh UUID. Neither operation publishes, exports, logs or sends data.

The UI-to-actor boundary validates a JSON object and byte limits, then uses bound
SQLite parameters. This is a **local draft** boundary, not a safe external-file
import or frozen-contract validation boundary. Files and share imports require the
separate #82 validator/projection before any deliberate local fork. A draft is never
a valid BuildSnapshot merely because it can be saved.

The actor-to-filesystem boundary trusts the application to supply its own protected
directory. A user-controlled URL, symlink or shared/writable directory is outside
this API's trusted setup. The app must select and qualify file-protection and backup
policy on Apple devices. SQLite storage is not application-level encryption.
Account authentication, Keychain, remote sync and share capabilities are not
implemented here; no client-only check can substitute for future server authority.

## Mitigation and residual-risk register

| Threat / required replay | Implemented mitigation and evidence | Residual requirement / responsible role |
| --- | --- | --- |
| Delayed edit or undo destroys newer work | Transactional expected-revision checks across connections; stale write/undo tests | UI must surface conflict and keep unsaved text; Apple UI implementation |
| Delete/recreate lets an old revision update a new object | Atomic retired-ID marker plus delete; delayed-create/write regression | Identity cleanup must not reuse IDs from old tasks; lifecycle implementation |
| Crash reports success before durable commit | Return only after commit; `_exit` after history and before commit replays recover prior state | Actual background termination, filesystem and device qualification; Apple test reviewer |
| Interrupted upgrade wipes drafts | Transactional v1/v2→v3 migration; abrupt-exit and rollback tests; unknown schema never resets | Future migrations need the same negative/recovery evidence; storage maintainer |
| One corrupt record destroys unrelated library entries | Corrupt rows retained and counted; 503-entry CRUD/reopen test | UI must display recovery notice; SQLite page-level corruption requires explicit recovery workflow |
| Disk exhaustion changes head without history | Actual SQLite page-limit `SQLITE_FULL`, rollback then successful retry | Device storage pressure and protected-data denial still need device tests |
| Malformed or huge draft consumes resources | JSON-object check, 1 MiB payload limit, 1 KiB title limit, 500-row page limit | History is intentionally retained without quota/eviction; storage growth policy and UX remain work |
| Raw workload appears in diagnostics | Errors contain typed code only; no payload, SQL, SQLite message or path logging | Caller must not log record content or attach databases; app diagnostics audit |
| Delete falsely promises irreversible erasure | Scoped logical deletion removes head/history; retained UUID contains no workload | SQLite free pages, filesystem snapshots/backups may retain bytes; no secure-erasure claim; privacy/lifecycle review |
| Other account reads prior local data | API requires separate caller-owned database per identity; isolation test | Actual login/logout routing, account deletion and Keychain access are unimplemented; identity/security receiver |
| Stale restored evidence looks current | Every local record reports `analysisIsCurrent == false`; restoration preserves exact locks without approval | Wire revision-bound analysis and stale labels in app; native integration tests |
| Export or remote API leaks secrets | Store has no export/network operation | #82 allowlisted projection and #50 server authorization must be implemented and tested separately |

Roles above identify remaining implementation/review needs, not assigned people.
No named security receiver is supplied by this record. Independent technical code
review and tests can verify the implemented mitigations; they do not prove absent
UI/service behavior or provide release approval. Findings stay open until their
specific integration or device evidence exists.
