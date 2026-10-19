# Compare retained resource estimates with their own saved builds

Partial package implementation for [Apple #81](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/81).
The API accepts two explicitly supplied historical records and preserves the saved
configuration each record names. It performs no resource estimation, arithmetic,
ranking, capability decision or evidence verification.

## Admission and original records

[`HistoricalResourceScenario`](Sources/PlannerTransfer/HistoricalResourceComparison.swift)
requires an already decoded `BuildSnapshot` and `ResourceEstimate`. The build ID
and exact revision must match. Every selection ID in the complete build must be
unique, and every row reference must resolve in that same build. An unknown
reference or duplicate selection identity rejects the entire scenario, with no
partial rows and no supplied text in the error.

Each `HistoricalResourceRow` retains its complete original JSON record and the
complete referenced selection records, in the order of that row's
`selection_ids`. These records preserve their actual kind, catalog item/version,
role, enabled flag and settings. Resolving an identity does not establish that
the estimator supports those components, that a disabled component applies, or
that workload, context, topology and capacity conditions have been verified.

The row's convenience properties retain exact decimal strings, units, estimator
ID/version, reported confidence, assumptions and optional source URI. Missing
source remains `nil`; a present URI is inert text. Repeated or empty assumptions
remain present. Decimal strings are not parsed into binary floating point or
normalized. The frozen schema enumerates metrics and units independently, so a
structurally valid contradictory metric/unit declaration remains reported and
unqualified. Even a literal `verified` confidence label gains no authority here.

The unchanged frozen readers still provide whole-input byte, depth, node,
duplicate-key, numeric and schema bounds. This contribution adds no wire fields,
schemas, fixtures, estimator policy or production data.

## Groups preserve every row without inventing correspondence

Frozen resource estimates have **no row IDs** and permit repeated metrics. A
metric is therefore only a display group. `metricGroups` are sorted by the frozen
ASCII metric name; each group's `beforeRows` and `afterRows` retain their complete
original order, including identical duplicates and multiple estimators.

Array positions do not pair rows. The implementation does not choose a preferred
estimator, deduplicate a record, infer an identity from units or assumptions, or
copy a value onto another component tuple. An empty side means no row for that
metric was supplied on that side. It does not mean zero, a missing remote
artifact, or permission to recompute historical evidence against current data.
All unchanged rows remain available as well.

The original scenarios retain the complete source row arrays. Consequently,
reordering the estimate array is an `estimates` record-field change even when
the resulting single-row metric groups are otherwise equal. Reordering build
selections or links alone retains the existing structural comparator's
order-independent identity semantics. Explicit row-reference order is preserved.

## Comparison and receiving boundaries

```swift
let left = try HistoricalResourceScenario(build: beforeBuild, estimate: beforeEstimate)
let right = try HistoricalResourceScenario(build: afterBuild, estimate: afterEstimate)
let comparison = try HistoricalResourceComparison.compare(left, right)
```

Different content cannot reuse one estimate ID. The complete existing
[`BuildComparison`](Sources/PlannerTransfer/BuildComparison.swift) always runs,
preserving its immutable revision, duplicate link, private-field and 2,048
difference guards even across different builds. A failure returns no partial
comparison. A new, correctly bound estimate or saved revision can recover;
neither original input is modified.

`changedFields` identifies changes to build ID/revision, recorded locks, estimate
ID, generated timestamp and the complete estimate rows. `cautions` always includes
`reportedValuesOnly`, and discloses differing build identities/revisions/locks,
unmatched metrics and repeated metrics on either side. Matching identities,
locks or row contents do not establish comparable evidence conditions. The
embedded structural comparison's notice continues to describe its own
configuration-only scope.

The original scenarios, row assumptions, source URIs and referenced selections
are **private local inspection values**, not a public export or logging
projection. The nested structural differences preserve their existing private
field suppression, but that does not redact the full original records retained
beside them. A caller must apply its own authorized presentation/export boundary.
This API performs no network or storage operations and accepts no repository from
which it could establish historical artifact availability, freshness, signatures,
rights or confidence. Recorded timestamps are preserved, not reinterpreted as
current checks.

## Focused validation and remaining acceptance

The [focused tests](Tests/PlannerTransferTests/HistoricalResourceComparisonTests.swift)
cover complete row/reference preservation; wrong build/revision and unknown
reference rejection/recovery; duplicate selection identities and links; changed
component tuples; repeated metrics and estimators; unmatched metrics versus zero;
exact decimal and Unicode text; source absence and assumptions; immutable
estimate/build identities; ordering; private structural differences; and the
existing difference budget. Inputs are synthetic variations of the unchanged
frozen fixtures, not measured capacity evidence.

Reproduce native validation with:

```sh
swift test --package-path Packages/PlannerTransfer --filter HistoricalResourceComparisonTests
swift test --package-path Packages/PlannerTransfer
```

These commands describe required execution, not a local pass. Actual focused and
full package results, the configured macOS/iOS and application gates, and
independent exact-source receiving review must be attached to the delivery PR.
The contribution preserves the current reference verifier and imported pins;
reference validation alone does not execute these Swift methods.

| Literal #81 criterion | This package contribution | Remaining acceptance |
| --- | --- | --- |
| Comparison explains meaningful differences without transferring measurements. | Complete local resource records retain their own build/revision and selections; identity and row-availability differences remain explicit. | Native execution, mounted presentation and integrated receiving review. |
| Compare revisions with different component tuples and unmatched measurements; show differences without transplanting quality/capacity evidence between builds. | Synthetic resource regressions retain changed tuples, repeated and unmatched rows, and exact reported conditions. | Actual retained-evidence intake, quality integration, device/UI demonstration and privacy/export disposition. |
| The build/revision comparison and incomparable-evidence tests is linked with criterion results, exact versions, limitations and receiving-review disposition. | This guide and focused tests provide the bounded source and limitations. | Published source and original execution receipts, independent review and whole-issue acceptance record. |

Issue #81 remains open. [#240](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/240)
retains configuration-comparison UI ownership and
[#354](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/354) retains quality
comparison. Durable library integration, canonical service/evidence availability,
physical-device, release and other owners' criteria remain separate.
