# Historical quality comparison

This bounded package contribution supports [Apple #81](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/81).
It places two supplied historical quality records beside their actual saved
configurations. It uses the existing frozen-v1 BuildSnapshot and
[QualityEvaluationRun reader](Sources/PlannerTransfer/QualityEvaluationRun.swift),
including their existing byte, depth, node, numeric and schema limits.

## Bind each original side

Construct each `HistoricalQualityScenario` from the saved build and the
`QualityEvaluationRun` that names it. Admission requires the exact build ID and
numeric revision, unique selection IDs, and a referenced selection whose kind
is `evaluation_suite`. The complete selected suite remains attached, including
its catalog item/version, settings, role and enabled state.

A repeated metric name is ambiguous for this comparison, even if the repeated
rows use different units. Admission rejects it explicitly instead of choosing
one row. Metric identity uses exact decoded UTF-8 bytes: canonically equivalent
Unicode spellings remain distinct metric identities. Frozen selection IDs use
the existing ASCII grammar. These are local comparison requirements; the
underlying decoder still preserves schema-valid repeated measurements.

The operation validates local identity relationships. It does not authenticate
the run, inspect its artifacts, validate chronology, execute an evaluator or
confirm the reported labels. A disabled suite and an incomplete run remain
inspectable with explicit per-side cautions. A reported failure is preserved
as a reported failure. Neither a reported pass nor matching conditions confers
verified quality, compatibility, readiness or permission to reuse the result.

## Inspect the comparison

`HistoricalQualityComparison.compare(before, after)` retains both complete
scenarios and adds the existing structural `BuildComparison`. That comparison
shows configuration changes by their original paths and tiers, preserves its
private-field protections, rejects ambiguous links and enforces its existing
difference bound. Conflicting configurations cannot share one immutable
build/revision identity. Selection and link ordering alone does not create a
configuration change.

Different quality records cannot reuse one run ID while changing their complete
value trees. This includes changes to private notes, artifact references and
measurement order. Independently identified runs can retain different row
orders while using the same stable metric display order.

| Output | Meaning |
| --- | --- |
| Complete before/after scenarios | Each original build, revision, locks, suite selection and quality run stays on its own side. |
| Changed fields | A stable typed list identifies changed build IDs/revisions/locks, suite selections, run IDs, timestamps, status, evaluator version, dataset revision, sample size, artifact references and notes. |
| Measurement rows | All exact metric identities are displayed in UTF-8 byte order, including unchanged rows. Each side retains its own observed value, threshold, comparator, optional unit and reported `passed` Boolean. |
| Missing measurement | The corresponding side is `nil` and has a `beforeAbsent` or `afterAbsent` caution. It is never replaced with a zero or a measurement from the other build. |
| Missing or empty unit | Absent, empty and nonempty units remain distinct. Cautions identify either side's absent/empty unit even when both sides have the same omission. |
| Different measurement conditions | Separate row cautions identify changed units, thresholds and comparators. A metric-name join does not establish equal measurement meaning or comparable results. |
| Different run or build conditions | Cautions identify configuration/suite changes, different evaluator or dataset revisions, different sample sizes, incomplete run labels and disabled suite selections. |
| Supported numbers | The reader's exact Decimal values remain unchanged. No narrowing to Int/Double, score subtraction, rescaling, unit conversion, threshold evaluation or ranking occurs. |

Every result carries `reportedValuesOnly`. The absence of additional cautions is
not an acceptance verdict: the frozen record does not establish every workload,
method, rights or evidence condition needed for a qualified comparison. The API
does not expose a `comparable`, `verified` or overall quality verdict.

The source records remain authoritative for what they reported. An observed
value that contradicts its reported result, an earlier finish timestamp, private
artifact URI or unrecognized unit is retained under the existing reader's
rules. The comparison does not silently repair those values or fetch a URI.
In particular, numerical resource capacity remains separate from reported
quality; this API does not substitute a ResourceEstimate for a quality run.

## Privacy, failures and local serialization

Original builds and runs can contain private workload text, notes and artifact
references. Retention here is for local inspection and local serialization,
not public export. The separate sharing projection, source-use controls,
redaction review and user consent still apply to any future disclosure.

Admission errors contain fixed cases without echoed input values. The operation
performs no storage, network, UI or approval action. Rejected pairings leave both
original inputs available. Each retained build and run can be serialized through
its existing `encoded()` method and reopened by the unchanged boundary.

## Reproduce and remaining acceptance

From a checkout with the accepted Swift toolchain:

```sh
swift test --package-path Packages/PlannerTransfer --filter HistoricalQualityComparisonTests
swift test --package-path Packages/PlannerTransfer
```

The twenty synthetic test methods cover foreign build/revision rejection and
recovery, missing/wrong-kind suites, duplicate selections and metrics, exact
Unicode identities, stable joins, absent rows and units, conflicting immutable
identities, reported contradictions, separate changed conditions, disabled and
incomplete states, supported exact numbers, private local values and independent
serialization. The different-component/unmatched-metric case checks the actual
configuration differences and verifies that neither side receives the other's
measurement. Fixtures derive from the existing explicitly fictional frozen
examples; they establish no measured performance or source-use permission.

| #81 acceptance contribution | This slice and remaining work |
| --- | --- |
| Explain meaningful build/revision differences without transferring measurements | The local API attaches the existing configuration differences and preserves exact per-side quality records and conditions. Mounted presentation and its receiving review remain open. |
| Different component tuples and unmatched measurements retain their own quality/capacity evidence | Synthetic package tests exercise separate component tuples and missing counterpart measurements. Capacity-record comparison, actual evidence intake and the combined UI journey remain open. |
| Link criterion results, exact versions, limitations and receiving disposition | The focused PR and its execution/review receipts must identify the actual source tree and observed results. This guide is not an executed-test receipt or a full issue acceptance record. |

The existing #240 controller retains its configuration-comparison UI work. This
contribution changes no frozen schema, fixture, backend or UI delivery route.
Independent source review and the ordinary configured repository checks remain
required before delivery. The full literal #81 criteria remain open until their
own integrated evidence and receiving review are complete.
