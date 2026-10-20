# Optional-tier activation and removal — Apple #66

## Receiving scope

This record covers the opt-in `PlannerTransfer` transition and confirmation API
for [Apple #66](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/66).
It prepares a validated, uncommitted Build snapshot. The native editor remains
responsible for displaying the preview, supplying its actual current owner and
inputs, confirming the action, and saving through its existing revision check.

The source was prepared on accepted `e742379f9a474e632a998f1586515f4cb1280b18`.
The three-file implementation/test tree is
`4596d2bdc871a0d40daed94ea52bf6ab4009cd9e`; this is a Git tree identity, not a
claim of signed delivery. Independent source review and the configured receiving
checks are recorded separately when they occur.

[Apple #64](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/64)'s
[current input handoff](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/64#issuecomment-6280451575)
remains in the canonical editor receiver. This package preparation uses an
explicit caller-supplied `OptionalTierEnvironment` and does not commit a default
deployment mode, production decision, catalog selection or filter policy.
The existing editor and persistence owners retain their integration work.

## Canonical tier and value boundaries

The unchanged frozen v1 catalog schema at Research
[`7acbefbf4e4e700231e88be272bc89e3a73dde15`](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/schemas/catalog-item.schema.json)
enforces each kind's tier. `CatalogItem` validates that schema before this API
uses its `tier`; the implementation does not maintain another kind mapping.

| Explicit optional tier | Frozen component kinds |
| --- | --- |
| T3 | `data_source`, `knowledge_base`, `embedding_model`, `vector_database`, `rag_pipeline` |
| T4 | `agent_framework`, `tool`, `mcp_server`, `memory_store`, `integration` |
| T5 | `training_framework`, `training_compute`, `training_dataset`, `fine_tuned_model` |

T0–T2 and T6 selections stay unchanged, including guardrails, evaluations,
deployment targets, monitoring and cost policy. The source catalog must bind
every retained selection by exact UTF-8 item ID/version and agree with its kind.
Duplicate item identities, duplicate selection IDs, missing catalog bindings and
kind mismatches reject preparation. These are input-admission errors, not
findings that a build has an unmet mandatory dependency.

Preparation verifies the Build's catalog ID and both dependency-graph lock fields.
Those checks bind supplied records; they do not authenticate a catalog publisher
or approve its compatibility policy. Complete immutable catalog and graph values
also participate in confirmation freshness checks, including same-pin content
changes.

## Preview, confirmation and persistence

[`OptionalTierTransition.prepare`](../../Packages/PlannerTransfer/Sources/PlannerTransfer/OptionalTierTransition.swift)
accepts an explicit set of optional tiers and one requested enabled state. It
changes only `enabled` on retained selections in those tiers. Each actual change
retains its source-order selection ID, tier, catalog item and before/after state
in `changes`. Settings, notes, roles, links, locks, objectives, private extensions
and selection order remain in both complete snapshots.

An omitted tier is not populated. An empty request returns `emptyTierRequest`;
an absent or already satisfied selection state returns `unchangedSelectionState`
without a proposed revision. A mixed tier changes only rows whose state differs
from the explicit request. Enabling a tier explicitly enables every retained row
in that tier, including individually disabled rows shown in that new preview;
the API does not infer a hidden prior activation state. The original snapshot
remains available for the existing owner's undo/history behavior.

A changed snapshot increments its wire revision exactly once, uses the supplied
validated timestamp and returns to lifecycle `draft`. The ordinary bounded
Build decoder validates the encoded proposal. Old validation or deployment
labels cannot qualify the changed snapshot.

The preview uses the existing direct `DependencyInvalidation` behavior and keeps
original graph edge order. Optional branches that become inactive retain their
before/after states; affected core selections are included for rechecking but
remain unchanged. `always` edges stay active, and absent mode or production
decisions stay unknown. This is not transitive invalidation or evaluator output.
In particular, graph inactivity does not fabricate a report's `skipped` outcome,
erase a retained failure, or classify an unknown decision as missing-required.

[`OptionalTierTransitionSession`](../../Packages/PlannerTransfer/Sources/PlannerTransfer/OptionalTierTransitionSession.swift)
issues one-use review tokens. A confirmation must match the actual local store,
draft, durable revision and selection-session identity; the exact current Build,
catalog and graph; the current environment; and the exact preparation generation.
A newly prepared identical proposal needs a new review. Dismissal, invalidation,
reopening, supersession and failed freshness checks retire the relevant token.
An old callback cannot consume a newer presentation's token.

`confirm` returns an uncommitted snapshot. The caller must still save with its
actual expected durable revision and wait for acknowledgement before displaying
a saved/current state. A concurrent save wins and requires a fresh user review;
the session never retries a write. No storage or network callback is part of the
production API.

## Transition tests and original execution

The new [test source](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/OptionalTierTransitionTests.swift)
contains 16 transition methods and eight confirmation/persistence methods.
These use the existing fictional frozen fixtures. They cover all three tiers,
full-value disable/re-enable preservation, mixed activation, multiple rows of one
kind, omitted tiers, core participant retention, active/inactive/unknown graph
states, pin and identity admission, exact Unicode versions, numeric/timestamp
reopening limits, foreign/stale/replayed confirmations and real local SQLite CAS.

The SQLite tests demonstrate that preview, dismissal and confirmation leave the
stored bytes unchanged until an explicit save; the saved proposal reopens with
the original history retained. A concurrent durable edit rejects the older save
without automatic retry. These tests do not simulate process termination or
physical power loss; the existing storage/replay gates keep their own scope.

The first local invocation stopped before test execution because SwiftPM did not
find the already present SQLite pkg-config record through environment settings.
Its 2,347-byte original log has SHA-256
`b85de282f10d9eade0705c8679ee473f685f0fcb8cd203550370bc6fc24cd1ff`.
The command was corrected to supply the existing `--pkg-config-path` explicitly;
no project source or shared toolchain changed for that recovery.

The corrected focused invocation on tree `4596d2bd` passed all 24 new methods
and two existing methods selected by the `OptionalTier` filter: 26 passed,
zero failures/skips, 4.6 seconds. Its original 14,103-byte log has SHA-256
`1419d53feb3d1f1376dbb13170de03f934e2d1768b6848a994ffee5f8835ae8d`.
The wrapper's UTC interval was 2026-10-20 04:36:48.293089–04:37:30.326730;
the console's own displayed clock is retained separately.

The exact toolchain reports Swift 6.1.2 (`swift-6.1.2-RELEASE`), target
`x86_64-unknown-linux-gnu`. It was reused read-only with task-owned build and
module caches. This is Linux execution. Apple SDK compilation, iPhone/iPad
behavior and the configured receiving checks require their own actual results.

The subsequent complete-package SwiftPM attempt did not produce a final root
summary. Its original log contains 223 completed passes and 12 explicit existing
CryptoKit skips before collection stopped. The XCTest child had exited while
the owned SwiftPM parent remained waiting. Only that verified owned parent group
was terminated; the attempt ended with exit `-15`. Its unchanged 69,750-byte
original log has SHA-256
`e2f07552632b0db67f713ce4e5bbaebf86757ea9858b8694bbfe3eb523d5633d`.
This remains an incomplete attempt and supplies no full-package pass.

The same source-bound compiled XCTest binary was then invoked directly, without
another compilation or source change. The complete `All tests` root reports
238 executed methods: **226 passed, 12 explicitly skipped, zero failures** in
29.876 seconds. All 24 new methods passed. The original 70,725-byte log has
SHA-256
`37a9a3b2339865d06f9fb47297738de102ef494d9c9324b55b0320ea8f6c6f72`.
The wrapper interval was 2026-10-20 04:45:51.476670–04:46:21.445575 UTC;
the original console clock is retained separately. The executable was
14,245,904 bytes with SHA-256
`388a0709e8aed58127c4beac6264e9428a20dc5efee642fb11285b6635d77f53`.

The textual source declares 244 methods. The six methods in the unchanged
`#if canImport(Darwin)` `NetworkArtifactRecoveryTests` file are not compiled on
Linux. SwiftPM's generated discovery list contains exactly the other 238 names,
each with one matching complete outcome in the direct run. The 12 explicit
skips are the five native-hashing methods in `RulesetCacheValidatorTests` and
seven canonical-fixture/cache methods in `SyntheticFixtureAdmissionTests`;
their original source guards require CryptoKit. These 18 platform-limited
declarations remain for actual Apple execution, and none is reported as passed
by this Linux record.

All 337 source leaves, the generated discovery list, exact new-method attendance,
all four original execution records and the unchanged executable were qualified
without running another test. The 145,637-byte local qualification JSON has
SHA-256
`d6593ec11f80fdefac27c4ee61f324ef894d456b416d7cc17e81acd04406e09e`.
The successful direct run resolves the observed local collection limitation;
the original SwiftPM attempt remains incomplete and the hosted workflow must
still execute its own ordinary command and platform gates.

Portable reproduction on a supported toolchain:

```sh
swift test --package-path Packages/PlannerTransfer --filter OptionalTier
swift test --package-path Packages/PlannerTransfer
```

The retained local command additionally pins task-owned scratch/cache directories,
uses one compiler job, and supplies the existing Linux SQLite pkg-config location.
All source inputs are hash-bound before and after each invocation. The direct
recovery executes SwiftPM's resulting `PlannerTransferPackageTests.xctest` with
the same local environment; it does not substitute a filtered test set. The repository's
unchanged native workflow performs its own reference verification and unsigned
iOS Simulator compilation.

## Literal criterion disposition

| Literal #66 criterion | Bounded evidence and remaining receiving work |
| --- | --- |
| Omitting an optional tier does not invent missing mandatory dependencies. | Package transition tests preserve 15 core selections and treat absent optional tiers as unchanged, without inserting records or emitting compatibility findings. Native editor/filter integration and criterion acceptance remain pending. |
| Disable T3-T5 with dependent settings present; preview destructive effects, preserve intent and mark non-applicable results skipped rather than missing-required. | The preview, complete-value preservation, dependency activity and explicit confirmation boundaries are tested. The governed evaluator's actual `skipped` findings and their native presentation remain a separate integration requirement; this package does not manufacture them. |
| The optional-tier activation/removal transition tests is linked with criterion results, exact versions, limitations and receiving-review disposition. | This record links all 24 new methods and the exact local original results. Independent Apple-domain/UX receiving disposition, normal signed delivery and actual configured native checks remain pending. |

All three whole-issue criteria remain open in this preparation record. No issue
checkbox, assignee, prerequisite, frozen schema or shared evaluator is changed.
The active #391 editor receiver and its #64 inputs retain their canonical scope.
