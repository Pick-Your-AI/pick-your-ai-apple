# Local fork lineage and independent storage

This follows [Apple #84](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/84)
and its required offline local-fork branch. The imported library already creates new
wire and local IDs and persists duplicates with an atomic source-revision check.
This change records which snapshot was copied so that the independent identity does
not lose the known source history. It uses the existing local library, with no
network or account dependency.

## Local format and behavior

`ImportedBuildRecord` is private application persistence, not a shared export schema.
Existing version 1 rows reopen as before and keep their exact bytes and history. A
newly confirmed import or duplicate writes version 2 with a nonempty `lineage` array.
Each element contains only the copied snapshot's build ID, integer wire revision and
lowercase SHA-256 of the normalized bytes returned by `BuildSnapshot.encoded()`.
The immediate source comes first, followed by the source entry's retained ancestors.
This fingerprint is a local byte record, not a signature or source authorization.

The snapshot is captured before a fresh local owner reference, wire build ID,
revision 1 and timestamp are created. Library row IDs and label revisions remain
separate from wire IDs and revisions. Source locks and synthetic/source qualification
remain unchanged; no inherited analysis becomes current. Duplicating an existing row
still checks its captured local revision and inserts the prepared payload in one
SQLite transaction, so an intervening source edit or deletion cannot acknowledge a
stale fork. Source labels and snapshot bytes are never updated by the new row.

The lineage array is bounded to 32 distinct source build IDs. Each entry must have a
valid build ID, positive safe-range integer revision and 64 lowercase hexadecimal
hash characters. The array cannot contain the current fork's own ID. Missing,
unknown-version, empty, oversized, duplicate, self-referencing or malformed lineage
is refused without changing the stored row, selected good entry or history. Unknown
wrapper and lineage-element fields are refused, including potentially private free
text. A version 1 row with an added lineage field is not silently reinterpreted.

At the bound, duplication reports that it cannot retain another source and creates
no row. It never truncates history. Legacy entries show that their earlier lineage
is unknown. Duplicating one starts with its available snapshot identity only; the
application does not infer its previous owner or missing ancestors.

The selected build presents every recorded ancestor in an expandable native row,
including its ID, revision and full selectable fingerprint. The explanation keeps
local history separate from ownership and evidence qualification. Renaming or
deleting another local ancestor leaves an existing fork and its stored lineage
unchanged, including after reopening the database. Imported wire snapshots remain
immutable; editable local labels belong to the separate revisioned library metadata.

## Privacy and conditional continuity

The local wrapper and lineage never enter `BuildTransfer.export`. The existing
explicit public alias, private-field projection, synthetic envelope and review of
the exact export bytes remain in place. An exported file contains the current
snapshot only. Reimport creates a new independent fork whose one known source is
that received snapshot; it does not claim the sender's unexported history.

[The selected #24 account scope](../decisions/issue-24-accounts.md) enables guest-first
local planning and disables account-backed continuity. Consequently #90's remote
conflict service is not selected for this local branch. If continuity is selected
later, its explicit account scope, authorization, conflict and receiving-review
requirements still apply. No remote shared-link service or protocol extension is
introduced here.

## Prepared regression evidence

All cases use the existing synthetic frozen build fixture, explicitly remove its
private `index_name` setting before export, and exercise the real `DraftStore`. Test
databases are isolated and deleted after use. These are source-level assertions to
be executed in the exact-head native workflow; no Swift/Xcode run is available in
the local preparation environment.

| Required test | Concrete behavior checked when executed |
| --- | --- |
| `testImportedForkRecordsItsExactSourceAndPreservesExistingEntry` | Records source ID, a large exact supported wire revision and normalized-byte hash before copying; new IDs/locks are correct; an unrelated row and its history remain exact; a fresh connection reopens the fork |
| `testForkOfForkRetainsLineageAfterAncestorRenameDeleteAndReopen` | Three independent forks retain the ordered exact source identities, revisions and fingerprints; ancestor rename/delete cannot rewrite the selected fork; reopen and re-export preserve its synthetic/source qualification |
| `testLegacyEntryReopensUnchangedAndForkStartsOnlyKnownLineage` | A version 1 row remains byte-for-byte unchanged with its original history; its new version 2 fork records only the known source snapshot |
| `testMalformedLineageIsPreservedWithoutOverwritingSelectionOrCreatingForks` | Missing/null/empty/duplicate/oversized history, invalid versions and entry fields, private text, invalid revisions, self-reference and a legacy added field all fail open/duplicate while preserving exact rows/history and the selected good entry |
| `testLineageLimitRejectsAnotherForkWithoutTruncatingOrChangingStorage` | The complete 32-source history reopens; another duplicate returns an explicit failure with no new row or history revision |
| `testExportExcludesLocalLineageAndReimportCannotAssertItsPriorHistory` | Exact reviewed wire export excludes the wrapper and all private lineage fingerprints; reimport begins from its sole received source and preserves the existing entry |

The native workflow retains all existing imported-library pass guards and separately
requires these six named tests to report success. The PlannerData race regressions
remain the proof of the existing atomic source-check/create transaction; this change
does not replace their gate or alter the database schema.

## Receiving and integration boundary

The prepared source follows the reviewed library/preparation component in
[#193](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/193) and
[#208](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/208). It will follow the
canonical combined native delivery [#198](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198),
preserving current main, the serializer reopening bounds, the full native journey
and its required test counts. It does not amend that active candidate or reuse a
failed native result as acceptance.

Independent Apple storage/sharing and privacy review, exact hosted compilation and
these six actual test results remain required before this implementation is accepted.
This source preparation is not a complete #84 receipt. Its #83 consumed output is
the available immutable preview/snapshot boundary that cannot update its source or
the viewer's existing draft; it does not establish unavailable remote authorization.
Actual Files-provider and web UI round trips, revoked links, unavailable remote
versions, physical accessibility and device behavior retain their own unverified
results. They must be reconciled with the live issue rather than inferred from a
local model or package pass.
