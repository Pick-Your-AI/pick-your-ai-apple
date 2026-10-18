# Comparison preparation and revision-bound results

This follow-up addresses a remaining [#29](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/29)
boundary in the [#81](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/81)
imported-build comparison screen. The canonical
[#198 integration](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198)
at `877f8f16447be2698ba43079ff4ef8066f85a2c4` moves preview/export preparation off
the main actor but still called the full comparison synchronously in a SwiftUI button
action. Inputs and difference counts are bounded; those bounds alone do not establish
that another main-actor interaction can proceed while comparison runs.

## One comparison flow

The existing imported-library model now owns the pinned baseline and comparison
state previously held in the view. Its button action synchronously captures both
validated immutable snapshots, the selected local row/revision and each side's
synthetic/unknown qualification before returning a cancellable task. The existing
detached `offMain` boundary runs the canonical `BuildComparison.compare` algorithm.
There is no second comparison implementation or new wire format. The accepted
[#231 record-identity correction](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/231)
from signed main `b773e7d3e99cc1a83dcd3199b51b3a4e1301814f` is retained byte-for-byte:
record IDs remain coordinates, while actual nested private fields remain redacted.

Comparison preparation has its own generation and task. It performs no storage
writes and does not hold the library's mutation busy flag, so opening another entry
can invalidate the old result and start a new comparison before the old worker
finishes. Publication requires the same generation and selected row/revision.
Repeated requests while that same selection/baseline is still preparing are refused;
the Compare control is disabled until completion or explicit invalidation.
Cancellation is checked before either worker success or worker error is unwrapped
and again before actor-side publication. A late validation error cannot bypass the
same cancellation and identity boundary as a successful result.

Replacing or clearing the baseline invalidates preparation immediately. Deleting
the baseline entry clears it only after the exact deletion transaction commits;
a rejected stale deletion leaves both the immutable baseline and its current
comparison intact. Deleting or adopting another selected entry also invalidates
comparison results on that actor turn. Library failure notices and comparison
notices remain separate.

The screen retains its original baseline, compare, clear and detail controls, and
adds progress plus Cancel comparison. Leaving the library cancels pending work.
Opening the immutable result's detail after preparation is complete retains that
result, so the navigation link is not removed by its own disappearance callback.
All qualification, private-field filtering and incomparable-evidence wording come
from the existing comparison boundary and presentation.

## Controlled native regressions

Nine additional cases use three schema-validated synthetic snapshots saved through
real SQLite. Their exact wire identities, public settings and qualification differ.
A lock-protected worker probe waits for at most five seconds; an asynchronous wait
lets the test's main actor continue before worker release. The timeout is a deadlock
guard, not a latency or performance result. Where applicable, the deliberately
cancelled worker later returns a real comparison or throws a non-cancellation error.

| Required case | Assertions required when executed |
| --- | --- |
| `testComparisonPreparationLeavesMainActorResponsiveAndPreservesInputs` | Another actual notes editor changes before release; comparison runs off-main, carries the exact snapshots and qualification, and leaves all three records/revisions unchanged |
| `testNewSelectionComparisonFinishesBeforeCancelledOlderResultOrError` | N+1 completes on another selected entry before the cancelled N worker returns; neither N's result nor its error replaces the new result |
| `testCancelledOlderComparisonCannotClearPendingNewerWork` | In the inverse completion order, cancelled N finishes while N+1 remains blocked; N cannot clear the newer progress/generation or prevent its later exact result |
| `testReplacingBaselineRejectsLateComparisonAndRetainsNewQualification` | Re-pinning creates a new exact baseline and qualification; older work cannot replace it |
| `testClearedBaselineRejectsLateComparisonAndError` | Clearing prevents both late outcomes and refuses comparison without a baseline |
| `testCancelledComparisonRejectsLateResultAndErrorWithoutClearingPin` | Returned-task cancellation and the view's cancellation route suppress both outcomes while retaining the pin and selected data |
| `testInvalidatedQueuedComparisonNeverEntersWorker` | A same-turn invalidation prevents the queued request from entering preparation at all |
| `testCommittedBaselineDeletionCancelsPendingComparisonAndPreservesSelection` | Only the committed target is deleted; its pin and pending work clear while the different selected row and other history remain intact |
| `testRejectedBaselineDeletionPreservesPinAndPendingComparison` | A stale deletion preserves the baseline, allows its valid comparison to finish, retains the storage failure notice and leaves newer durable metadata intact |

The existing 20 imported-library cases remain, including the reviewed correction
that accesses exported JSON using the public enum case rather than another module's
internal helper. The complete PlannerUI package declares 80 cases in this prepared
follow-up; all 22 required imported-library names are explicit native CI pass gates.
The 71-case canonical source includes the accepted history-notice integration;
all three mandatory history-recovery names remain gates beside the imported-library
checks. The actual editor UI journey, model coverage, two pinned destinations,
storage and toolchain requirements are retained unchanged.

## Execution and acceptance

This source is prepared in a separate checkout while the corrected canonical #198
integration completes its native gates. It does not reset that active candidate or
replace the retained failed compiler/UI receipts. Its receiving base is exact
`877f8f16447be2698ba43079ff4ef8066f85a2c4`, tree
`1bfc17779920d4e12b41e20f58288e97d37fe30c`, which preserves signed main
`8ca109963bfca3a707b1af8b80aabcd9dd28fd8a`. The nine comparison cases and their
production changes are the previously reviewed isolated worker source, reconciled
with the current native workflow's history gates. Independent review and exact-head
hosted Swift execution, unsigned SDK compilation and both complete simulator
journeys remain required. Swift/Xcode are unavailable in this local workspace; no
native pass or measured responsiveness result is claimed here.

The [module boundary inventory](module-boundaries.md) records the production
dependency diagram, each asynchronous publication owner, and the remaining #29
acceptance work against this same receiving base.

These scheduling and identity cases are a partial #29/#81 delivery. Full comparison
UI interactions, physical-device responsiveness and accessibility, matched outcome
or cost evidence, complete lifecycle acceptance and release qualification remain
separately evidenced requirements. No issue closes solely from this composition.
