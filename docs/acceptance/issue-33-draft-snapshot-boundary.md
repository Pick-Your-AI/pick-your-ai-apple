# #33: Durable draft-to-snapshot boundary receipt

Reviewed scope: [Apple #33](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/33),
2026-10-18. This records the exact draft/snapshot transition output, not full contract
adoption, Files UI, user-autosave timing, device qualification or release acceptance.

## Artifact and execution identity

- Merged implementation: [PR #141](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/141),
  main commit `f56139e05bf54a44407aebd155df126e033b3359`.
- Independently reviewed signed head: `bca909542e1e60799f1e761879c68954d9c5a085`;
  [technical review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/141#pullrequestreview-5560912191).
- [Exact-head transfer execution](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39085893693)
  and [post-merge execution](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39087836369):
  Xcode 16.4 (16F6), macOS hosted runner, 12 Swift tests, 129 canonical reference
  cases, four source SHA-256 comparisons, and unsigned iOS Simulator compilation.
  Both executions succeeded. Other exact-head and post-merge workflows also passed.
- Frozen contract 1.0.0, research revision
  `7acbefbf4e4e700231e88be272bc89e3a73dde15`; exact schema/fixture hashes are in
  [source-manifest.json](../../Packages/PlannerTransfer/source-manifest.json).
  All test inputs are synthetic. No production data or rights receipt is implied.

## Criterion-specific disposition

| Live criterion | Evidence and result |
| --- | --- |
| Draft editing and valid snapshot export have distinct validated boundaries. | PlannerData accepts bounded incomplete editor objects. `BuildTransfer.snapshot(fromDraftJSON:)` validates a complete build against bundled frozen build/selection/common schemas before constructing an immutable snapshot; no required defaults are inserted. Export requires that typed snapshot. The valid fixture and all 29 selection-kind conditional-settings tests pass. |
| Autosave an empty draft, then attempt snapshot export; retain the draft while rejecting incomplete snapshots without invented required values or lost revision locks. | `DurableTransferTests.testEmptyAutosaveSurvivesRejectedExportAndStoreReopen` persists an empty-selection payload with a catalog lock, reads it using a new SQLite connection, rejects snapshot construction, and reopens again. Exact payload bytes, lock, revision 1, one history entry and non-current analysis remain unchanged. A rejected malicious import also leaves the existing draft identical. This test invokes the persistence API directly; it does not simulate a UI timer or OS process death. |
| The draft-to-snapshot transition tests are linked with criterion results, exact versions, limitations and receiving-review disposition. | This receipt links immutable implementation identity, exact successful hosted executions and the canonical manifest. The independent technical receiver accepted the bounded transition output under the user's delegated engineering/review authority. It is agent technical receiving review, not a separate human, product, privacy or release approval. The publishing PR records the receiver's disposition for this exact evidence document. |

[Transition test source](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/DurableTransferTests.swift)
and [boundary/adversarial test source](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/BuildTransferTests.swift)
are reproducible through [the package instructions](../../Packages/PlannerTransfer/README.md).
The positive fixture/fork tests preserve exact version locks; negative vectors cover
unknown fields, unsupported versions, missing fields, wrong types and settings.
Exponent round-trip and nonzero decimal-underflow regressions keep accepted transfer
values closed under encoding rather than silently changing or losing values.

## Prerequisite and scope reconciliation

The live #32 prerequisite is the named output “Swift accepts valid fixtures and
rejects incompatible contract payloads,” not closure of all #32. The frozen build
and selection validator, all-kind conditional-settings coverage and 129 identical
reference cases establish that output for this transition. Broader #32 top-level
model coverage and #37 cross-client/migration acceptance remain open.

Earlier package README text said #33 still required autosave-to-export UI integration.
That was a conservative implementation-gap note, not an additional live acceptance
criterion. It is superseded for #33 by this criterion-specific receipt: the required
persistence-to-validation rejection case is executed without inventing valid values.
Actual timed UI autosave/process-kill work remains #69; Files/share-sheet and
cross-client UI journeys remain #82; physical-device and release gates remain their
own tasks. #70 evaluator parity and #75 actual visible-result integration are not
satisfied by these tests. No broader issue is closed by this receipt.
