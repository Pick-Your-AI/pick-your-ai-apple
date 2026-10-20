# Comparison preparation and revision-bound results

This follow-up addresses a remaining [#29](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/29)
boundary in the [#81](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/81)
imported-build comparison screen. Its receiving source is the catalog/editor
[#240 candidate](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/240)
at `c8fa65c79b7f02a39f5a03e85a69a81d4d4d2694`, which already contains canonical
[#198 source](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198)
`8e76d0ee3db9659df4b7c96bef0eb0c70909ea52`. That source moves preview/export
preparation off the main actor but still calls the full comparison synchronously
in a SwiftUI button action. Inputs and difference counts are bounded; those bounds
alone do not establish that another main-actor interaction can proceed while
comparison runs.

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
internal helper. The receiving catalog/editor source declares 87 UI cases; this
comparison follow-up declares 96. All 22 required imported-library names remain
explicit native CI pass gates, alongside the three history-recovery names.
The class-qualified `comparison-catalog-editor-ui` profile additionally retains
all 38 required identities from the received catalog/editor profile and adds the
nine comparison identities, for 47 required cases across five XCTest classes.
The `quality-catalog-editor-transfer` profile preserves the 48 Transfer cases and
12 required identities from that receiving source, then adds the nine accepted
quality-record cases: 57 cases and 21 required identities across four classes.
Historical 42/68 and 48/87 profiles remain available only to qualify their own
recorded sources.

The guard regressions require an exact 96-case success and reject an older
87-case specimen padded with nine unrelated passing cases. Moving a required
method into another class also fails. The analogous 57-case Transfer specimen
passes only with all nine quality methods in their exact class; padding an older
48-case specimen cannot satisfy it. These are parser tests, not native results.
The actual Notes and Demo catalog journeys, all model coverage, both pinned
destinations, storage and toolchain requirements remain required.

## Execution and acceptance

This source is prepared in a separate checkout without changing active #198 or
#240. It preserves their failed compiler/UI and interrupted-run receipts. Its
initial receiving base is exact `29c91f0d43257b0ce37758013d4d46fc85da8ad4`, tree
`d9a69e2b5ca1a1e66b1a901aeed4f0c587ffb6b7`, which contains canonical `877f8f16`
and signed main `8ca109963bfca3a707b1af8b80aabcd9dd28fd8a`. The four worker
production/test blobs remain exactly the independently reviewed source checkpoint
`183b07399f1331eaba2d19f0560e657039cf2f40`, tree
`78dca587ba7ca8f51679e1a8336dcf704d96fdf4`. That earlier isolated composition
declared 80 UI cases; it is not evidence of execution of the current 96-case union.

The next composition retains canonical catalog candidate `c8fa65c7`, the editor
correction `8e76d0ee`, the reviewed fixture-lifetime checkpoint `10cd075c`, and
accepted signed main `9a3b0fe48890507ec0e8d80994da53c626e2ca86`. The editor carry adds only the observed
trailing-space tutorial label to the catalog candidate's existing journey helpers;
its keyboard dismissal, durable title/notes checks and catalog journey remain.
Both source-specific failed UI receipts and the failed scope cleanup are retained.
The fixture change keeps automatic maintenance in the foreground without changing
scope assertions or suppressing cleanup errors. Its receipt does not claim to
reproduce the hosted cleanup interleaving or to establish a hosted pass.

Accepted main adds the bounded quality-record boundary, precise bounded cache
reading, raw Core JSON admission and current conformance/guidance records. Their
source remains intact. The catalog-snapshot and quality schema entry points,
all nine source pins and both reference vector replays are composed together;
neither boundary gains storage, network, evaluation or source-use authority.
The received catalog/details and literal comparison presentation are preserved.
The catalog journey carries the canonical contained-switch selector: exactly one
narrower descendant must lie inside its identified row, and both native and row
values must change after a normal tap. Its prior failed transition and all later
restoration/detail assertions remain. Independent receiving review, exact-head hosted Swift execution,
unsigned SDK/app compilation and both complete Notes/catalog cases on each pinned
simulator remain required. Swift/Xcode are unavailable in this local workspace;
no native pass or measured responsiveness result is claimed here.

Local receiving checks passed all 10 execution-guard tests, including the new
57-case positive and padded/wrong-class negative specimens. The combined Transfer
reference verifier passed all nine source hashes, 129 build/selection cases,
1,635 item cases, 77 snapshot-envelope cases and 202 quality-record cases with
the required format checker. Quality-vector generation also matched exactly.
These Python results establish neither Swift execution nor the native journeys.

The independent receiving reviewer additionally ran all 20 raw-Core vectors using
the unchanged exact 4.25.1 environment and hash-verified frozen inputs. The earlier
attempt in a 4.26.0 environment stopped at its version guard before execution and
does not count as a pass. The [completed canonical editor receipt](editor-integration.md#completed-corrected-editor-execution)
now records the actual 71-model and complete iPhone/iPad Notes success at `8e76d0ee`.
That source-specific success does not execute the current 96/57 union or the new
catalog selector; its separate failed scope receipt remains preserved.

The [module boundary inventory](module-boundaries.md) records the production
dependency diagram, each asynchronous publication owner, and the remaining #29
acceptance work against this same receiving base.

These scheduling and identity cases are a partial #29/#81 delivery. Full comparison
UI interactions, physical-device responsiveness and accessibility, matched outcome
or cost evidence, complete lifecycle acceptance and release qualification remain
separately evidenced requirements. No issue closes solely from this composition.

## Accepted main protection carry

The published source checkpoint `0914f5edcb4bdf8d9819c6bc2b147ed4232da6c8`, tree
`7f6e9af4ba9d75cd466d6dd99ba37bb1598c8c83`, preserves the reviewed composition
above. Its next receiving carry adds all 16 exact files from signed main
`074ae4bffec6066d3fe6e6a5fe47ab429dde54ed` and its signed parent `1601ec4a`,
which descends from the recorded `9a3b0fe4` base. There is no source conflict:
the accepted dependency-review workflow, immutable license/snapshot checks and
conformance receipt invalidation are retained whole. All application, Swift test,
native workflow and 96/57 profile bytes remain the reviewed checkpoint's source.
The added dependency workflow is a further receiving gate.

Actual local execution at tree `28f430c0dacfc532927355d87603ce90f2bf33b0`
passed all 24 conformance harness/parser tests and all 31 dependency-policy tests,
with zero failures, errors or skips. The conformance suite used the unchanged
exact requirements environment and hash-verified Android frozen v1 import. Its
real CLI case creates a success receipt, rejects a changed source while removing
that receipt, then recovers to the original result. Protected paths, dependencies
and partial-write/publication failures retain their negative coverage. The
existing workflow's root-level output has an existing parent outside both
protected input directories, so it remains a valid destination.

The complete local log SHA-256 values are
`24254ad66acb8e2493cad090308990c9d97ffaa678f4b21b5751f6477fc5159c`
(24 conformance cases) and
`b6629b4b5bb4d0da392abd6898fc17af97270bb16948e8aecaee47aa6c19fab4`
(31 policy cases). These are portable execution receipts, not Swift cases or a
live dependency-service result. This paragraph is a documentation-only addition
to that tested tree. Fresh current-head dependency review, the complete 96/57
native inventory and both full journeys on each pinned destination remain required.

## Source-link receiving composition

The earlier `0269dead` receiving checkpoint combined reviewed `6ee51dae` with canonical
source-link candidate `3bdb956ab5640a055913621d9b96eec5cf329489`, using their
exact `c8fa65c7` common input. All four comparison-worker production/test blobs
remained `183b0739`; all five source-link production/model/policy test blobs retained
the canonical candidate's exact bytes. At that checkpoint the amended catalog
journey also matched #273 exactly, and the complete Notes journey was unchanged.

The workflow now selects `comparison-catalog-source-ui`: **110 complete UI
cases and 61 mandatory identities across seven classes**. Its profile includes
all nine comparison and fourteen source-review additions. The earlier 96/47 and
101/52 profiles remain intact; padding either older result cannot qualify this
union. Every existing 57/21 Transfer gate and accepted-main protection remains.
The [receiving record](catalog-editor-receiving.md) preserves the completed c8
87-case model/Notes success and both real catalog failures. Its later sections
separately record the exact detail-label correction and bounded post-tap state
hypothesis. No Swift result or successful control correction for this expanded
composition is claimed.

## Accepted submission SDK and toolchain receipt carry

The reviewed 110-case UI / 57-case Transfer source-navigation and comparison
union is preserved while receiving signed main
`d0537ace2cb0a14cdbb5f316a79e972e427ae63c`, tree
`145227d3bb81c4063d161544454342bc9c41a525`. Its signed parent
`4074f08047e480fa8981a3deabd7527593314ed9` delivered the separate
[unsigned submission SDK lane](submission-sdk.md); the next accepted commit
reconciled the already published toolchain receipt. The exact shared input is
signed `074ae4bffec6066d3fe6e6a5fe47ab429dde54ed`.

All eighteen accepted paths are retained. The existing UI workflow gains only
its accepted generated Info.plist evidence commands; all prior full-suite,
class-qualified identity, two-destination journey and owned-cleanup gates remain.
The generated project keeps every UI-test target and source while receiving the
accepted app orientation/search-path settings. Both complete README sections,
the foreground fixture-maintenance setting and the conservative scope assertions
remain. The additional Xcode 26.3 / SDK 26.2 lane keeps its own verification, fresh
caches, complete five-package execution and unsigned simulator/device products;
it does not replace the pinned Xcode 16.4 development journeys.

At pre-receipt tree `af95485e8cfea1f4653b5f994248541493afeb3a`,
all 37 App runner/toolchain/SDK tests, all 15 real-Git scope tests and all 26
obsolete-run selection/transport tests passed, with no failures or skips. The
complete App log SHA-256 is `e6a683bab42c28eef8bfa6d1d27fdc621b571d5c3ac002ed242f33057950a6e1`; the
combined scope/retirement log SHA-256 is `9a8543f0a6ec5aeb52f88ad8d71d3e5c60fc388f434cf85c791febed023bf6d2`.
These are portable guard executions. This receiving source has no new Swift,
SDK-product or device-journey acceptance; the original c8 catalog failures and
the expanded 110/61 UI and 57/21 Transfer requirements remain explicit.
