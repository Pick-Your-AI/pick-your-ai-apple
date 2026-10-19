# #64: Local planning input preparation

This bounded implementation candidate addresses the missing input editor in
[Apple #64](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/64). It is a donor
on the existing [#391 app integration](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391)
source `9e83640075037bb23a1703a5c03f40befe0b5580`, not another main integration route.
The [scope/ownership receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/64#issuecomment-6276489324)
records the fresh inspection and preparation boundary. No issue criterion is closed
by this document, a portable test result, or source inclusion.

## User behavior and contract boundary

The existing local draft form gains workload/deployment choices and nine labeled
usage/objective fields. Each field keeps its raw text, including an empty value,
invalid units, decimal spelling and exact Unicode spelling. Invalid or unanswered
fields can be saved and reopened. They do not become zero, a default budget,
an assumed location, or a valid immutable Build.

The unchanged frozen contract is `1.0.0`, research revision
`7acbefbf4e4e700231e88be272bc89e3a73dde15`. The
[import manifest](../../Packages/PlannerTransfer/source-manifest.json) retains the
exact schema hashes. The [draft/snapshot receipt](../acceptance/issue-33-draft-snapshot-boundary.md)
and [relationship preservation boundary](../../Packages/PlannerTransfer/PLACEMENT_RELATIONSHIPS.md)
remain authority for #33 and #35. No schema, canonical settings field, relationship,
activation rule, validator or evaluation policy is added or changed.

| Input | Local format check and meaning |
| --- | --- |
| Region | Empty remains unanswered. A nonempty string meets the frozen field's shape; this does not assert that a service supports the region. No allowlist or location is invented. |
| Currency | Three uppercase ASCII letters. No currency is inferred from the device, region or catalog. A budget with unanswered/invalid currency is visibly incomplete. |
| Data classification | Only the existing `public`, `internal`, `confidential` and `restricted` values are recognized. Other raw text remains editable and durable. |
| Monthly budget amount | The existing `ContractDecimal` checks a nonnegative base-10 decimal string with at most twelve fractional digits. It preserves spelling and does not use `Double` or `Foundation.Decimal`. Symbols, separators, exponent notation and negative amounts stay invalid text. |
| Requests per day, average input/output tokens | ASCII whole-number text, minimum zero. Blank is distinct from zero. Leading zero spelling is retained. |
| Maximum concurrency, maximum latency in milliseconds | ASCII whole-number text, minimum one. Unit suffixes, fractions, exponents and a zero value remain invalid. The visible labels state the unit. |
| Workload and deployment mode | Optional references to actual `workload` / `deployment_mode` catalog kinds. Leaving or returning a choice to unanswered keeps it nil. The client does not infer a mode from being an Apple application. |

These are local input-format checks, not a full Build admission or filter result.
Whole-number text is checked without an `Int`/floating-point conversion or a new
contract maximum; a later transfer operation must still apply its existing bounded
JSON numeric admission. Saving a very large integer as draft text does not establish
that it is transferable. This slice does not export objectives or manufacture
selection IDs, roles, enabled flags, links, locks or missing required Build fields.

## Catalog choices and uncertainty

Choices come from the existing `BundledCatalogPreviewSource` after its full canonical
decode and byte-digest check. The exact synthetic catalog SHA-256 is
`2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8`.
The UI labels it as fictional and shows the actual workload type or deployment-mode
declaration. The selected local reference retains its canonical kind, item ID,
item version, name, catalog schema version, catalog ID/revision/capture time and
SHA-256. A reference in the wrong kind slot is rejected. A retained reference that
does not match a current choice remains visible as unavailable and is not replaced.

No workload usage values or deployment regions are copied from the synthetic
catalog's spec into unanswered user fields. No reference activates a service or
confers source-use, publication, freshness, compatibility or pricing authority.
Unanswered fields explain the missing restriction or quantity. Supplied fields
remain explicitly unevaluated; no catalog item is hidden or declared compatible
by this slice. Actual input-driven catalog/evaluator filtering remains #64 work.

## Local data and lifecycle changes

`EditorPayload` version 1 remains readable with its exact two-key shape. Opening
it does not write a revision, fill input values, normalize notes or change its
original stored bytes. New drafts and later explicit/autosave writes use local
editor version 2 with `planningInputs`; the original v1 revision stays in SQLite
history. The SQLite schema and opaque draft storage boundary are unchanged.
An older reader rejects v2 instead of silently discarding its additional fields.

The v2 reader rejects unknown top-level/nested fields, unsupported versions,
wrong raw-value types, invalid reference shape and misplaced canonical kinds.
The editor preserves such a record unopened. Supported raw invalid text is
different: it is decoded, shown, edited and saved without becoming a validated Build.

Inputs participate in the existing UTF-8 equality, bounded session undo/redo,
autosave scheduler and compare-and-swap revision writes. A save acknowledges only
its submitted inputs. Restoration uses per-field/per-reference input generations:
an input edited during the actor hop remains current even if its text returned to
its earlier spelling, while untouched inputs receive the restored revision's value.
Queued lifecycle saves use the latest values and acknowledged revision. Menu and
field callbacks capture their draft ID and editor-opening token. Adoption, close
and deletion retire that token; ordinary save/restoration preserve it. A retained
control cannot edit a different draft or the same draft after it has been reopened.
Discard suspension and destructive-delete guards still apply to the input setters.

Independent preparatory review identified that a draft-ID-only callback guard would
accept an old control after that same ID was reopened. The editor-opening token and
same-ID reopen case correct that source-level counterexample before publication.
It is not an observation of a particular SwiftUI callback ordering on a device.

## Prepared vectors and executed checks

The [36 synthetic field vectors](../../Packages/PlannerUI/Tests/PlannerUITests/Fixtures/planning-input-vectors.json)
cover all nine fields, absent values, explicit zero, minimum-one values, unit text,
Unicode digits, separators, exponent notation, decimal precision and large exact
values. [Eight domain tests](../../Packages/PlannerUI/Tests/PlannerUITests/PlanningInputsTests.swift)
consume those vectors and cover exact text, catalog kinds/pins, removal, unsupported
payload shapes and bounded undo. [Nine appended real-store/editor tests](../../Packages/PlannerUI/Tests/PlannerUITests/DraftLibraryModelTests.swift)
cover v1 history preservation, invalid text/absence after reopen and duplication,
stale callbacks, undo/redo, in-flight saves, restoration, revision conflict, queued
lifecycle save, autosave/discard and unsupported-record preservation.

All **204 preceding Swift test method bodies remain unchanged**. The new current
`planning-inputs-ui` receipt profile requires **221 exact class/method identities**.
The original 204-method profile and every older profile/parser function remain
intact for their historical sources. Both native model and submission SDK jobs now
select the 221-method profile; job selection, toolchains, deadlines, cleanup and
other native acceptance requirements are unchanged.

| Actual local observation, 2026-10-19 | What it establishes |
| --- | --- |
| Before adding the new receipt profile: 16 Python receipt controls, one expected source-inventory failure, 0.483 seconds. Original log: 5,610 bytes, SHA-256 `a6027dbc9a14ed45f28063c2cbd9c68edd800766b83c0fdda6cbe5d1ce2e4f89`. | The old receipt inventory lacks all seventeen added Swift identities. This is a receipt-control failure, not an executed Swift behavior failure. |
| After registering the exact profile: the same 16 Python methods pass in 0.570 seconds, zero failures/errors/skips. Original log: 3,153 bytes, SHA-256 `fb79ec67e1a24101795ee7145e02bedea2280476354a84596a2749696d1d5f99`. | Actual source inventory matches the required profile; missing/duplicate/failed/skipped and same-count substituted results are rejected. This does not establish native compilation or execute the seventeen Swift methods. |
| The full portable CI suite passes all 97 methods in 18.470 seconds, zero failures/errors/skips. Original log: 16,546 bytes, SHA-256 `24931f7d1b47f08a9546d0c981a112ffffd58525442aac36dc9d39053eb7a6a3`. | Existing CI selectors, result controls and publication controls still pass; no native UI or Swift execution is inferred. This run preceded the final same-ID callback guard, which changes Swift source and existing new regression bodies only. |
| Full original-source preservation and whitespace checks. | Original Swift bodies are exact, with only the nine-method extension appended to the existing model-test file; prior receipt functions/profiles are structurally exact. |

Reproduce native model execution with the pinned supported Apple toolchain:

```sh
set -o pipefail
swift test --package-path Packages/PlannerUI 2>&1 | tee model-tests.txt
python3 tools/ci/require_swift_test_results.py planning-inputs-ui model-tests.txt
```

The hosted workflows retain their stricter cache, toolchain, product and artifact
requirements. Native Swift compilation, actual model behavior, simulator rendering,
full app journeys and installed-device behavior remain unverified for this donor
until their original current-source results are recorded. Independent receiving
review follows the concrete published source; no prior donor review applies to this
new input implementation automatically.

## Native planning-input journey follow-up

The initially published donor `3113efb3007194ce22b413783c88a5650ebcac0a`, tree
`62803d95458c093c6b9beb7d42fa24f2c96196ff`, retains the six preceding App journeys;
none of those methods operates these new fields. Its root source review and
original hosted results retain that exact source identity. The follow-up adds
`LocalDraftJourneyTests.testPlanningInputsPreserveUnansweredInvalidTextAndRestoredRevisions`
through the existing App test target. No application code or frozen field schema
changes in this test increment.

The [complete declared journey](../../App/UI_JOURNEY.md#current-seven-journey-planning-input-follow-up--2026-10-19)
uses ordinary controls and a uniquely named test-created draft. It checks absent
workload/deployment/currency, preserves `1.2500` and invalid `12 requests/day` after
acknowledged autosave and process relaunch, explicitly selects the fictional pinned
records, then corrects currency/usage while preserving unanswered catalog-derived
inputs. Restoring the earlier revision must create a new saved revision, retain the
later corrected history, and recover the earlier raw invalid/absent state after
another process relaunch. It checks actual UI values, state text and durable row
identities; it neither injects records nor reads the database directly.

All six preceding App method bodies and every old helper remain exact. The 221
package-test profile is unchanged. The original two/four local/T6 selector groups
are unchanged; the existing native workflow's `--suite all` additionally requires
the seventh App method. All runner functions, destinations, deadlines, single
attempts and cleanup remain unchanged. The workflow edit only makes its step name
describe the complete current selection. Current App documentation now names the
221 package methods and seven App journeys, preserving dated prior receipts.

The actual local registration control first ran the same 24 Python methods with
the new Swift method absent from the runner selection: one expected missing-method
failure in 0.046 seconds. After registration, all 24 pass in 0.055 seconds with
zero failures/errors/skips. The original red/green logs are retained. This proves
source/receipt attendance and rejection of older or substituted output, not
execution of the Swift journey. A Swift 6.2.4 frontend syntax parse of the changed
native test is separately recorded; syntax parsing is not Apple SDK type checking
or native behavioral execution.

## Remaining acceptance

#64 remains open for input-driven documented filters, complete empty-draft to
selection/settings/restoration journeys, optional-tier removal and actual interrupted
persistence evidence. This slice neither adds optional T3–T5 components nor changes
their activation semantics. The #54 named accessibility output remains a qualification
boundary: verify the new persistent labels, menu choices, field state and Done action
on pinned compact iPhone and adaptive iPad, with largest supported Dynamic Type,
VoiceOver order, keyboard navigation, Reduce Motion and both appearances. Source use
of native controls and text status is preparation, not a recorded accessibility audit.
The separate field/store, native, signing, delivery and issue-specific receiving
criteria must be reconciled before broader completion is claimed.
