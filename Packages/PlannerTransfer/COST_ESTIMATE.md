# Frozen CostEstimate record boundary

This is bounded preparation for [Apple #47](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/47)
and [#37](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37).
It provides the missing immutable wire record alongside the existing PlannerCore
CostSummary presentation and AnalysisStore request-generation fence. It does not
create a pricing service, calculate an estimate or publish an accepted quote.

## Exact inputs

The schema and synthetic example are copied without modification from research
revision `7acbefbf4e4e700231e88be272bc89e3a73dde15`, the same revision already
used by this package:

| Input | SHA-256 |
| --- | --- |
| [cost-estimate.schema.json](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/schemas/cost-estimate.schema.json) | `ef7cf8c0492022c1a8a1f971e49eb86dfad5b66ce6a4b2cf72a965fc9ba81259` |
| [cost-estimate.json](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/examples/cost-estimate.json) | `4b7c3889881d3c424ed98cc47b146b25b05df21c5459c9558717f21b6198b7e4` |

The [source manifest](source-manifest.json) appends only these two pins. Its
previous hashes, revision and metadata remain unchanged. The existing
common schema supplies identifiers, decimal strings, money and timestamps.
Schema references resolve only to bundled resources. No remote resolver or new
schema engine is introduced.

## Recorded views

`CostEstimateRecord.decode(_:)` validates the complete raw record and returns
an immutable value. All stored values are Swift value types; public views cannot
replace a field or construct an unchecked record. `value` retains the complete
supported JSON structure for inspection.

| View | Preserved representation |
| --- | --- |
| Record, build and pricebook identities | Exact supplied identifier strings |
| Build revision and period days | Exact positive integral Decimal within the existing JSON number limits |
| Estimated timestamp | Supplied valid timestamp spelling, including offset and fractional digits |
| Record currency and coverage | Supplied three-letter code and frozen recorded label |
| Line items | Original order, including duplicate IDs and duplicate rows allowed by the frozen structure |
| Meter, method and confidence | Exact frozen enums; no inferred measurement, price or evidence authority |
| Quantity and every monetary amount | Decimal **strings**, including all supported digits and trailing zeros |
| Unit price, line amount, subtotal, tax and total currencies | Each supplied value, even when currencies disagree |
| Unpriced selection IDs | Original order; duplicate IDs fail the schema's uniqueItems requirement |
| Warnings and per-line assumptions | Original order, duplicate strings, empty strings and private text |

All fields in this frozen artifact are required. Empty line-item, warning,
assumption and unpriced-selection arrays are accepted where the schema allows
them. Absence or explicit null is rejected; an empty array is never inserted
as a default.

The decimal string `"1.2300"` stays different from `"1.23"`. A 200-digit
integer part with twelve fractional digits stays a string and is not rounded
through Double, Foundation Decimal or PlannerCore ContractDecimal. The separate
JSON integer fields use the existing bounded parser and do not narrow to Int.
Serialization may normalize a JSON number's spelling while retaining its exact
numeric value; decimal strings retain their spelling.

`encoded()` is local serialization. It reparses its actual normalized output,
requires the same semantic JSON value and enforces the same input budgets.
Compact strings can expand when escaped; oversized normalized output fails
explicitly. This API retains private notes and is not a share/export sanitizer.

## Structural admission and qualification

The frozen schema does not establish that line amounts equal quantity times
unit price, that subtotal plus tax equals total, that currencies agree, or that
line/rate/selection identities resolve. It does not authenticate coverage,
method or confidence. It permits an empty line list with a reported total,
a reported complete record with unpriced IDs, repeated line IDs and inconsistent
amounts. This reader preserves those supplied facts; it never silently repairs
them or exposes a new budget verdict.

A later adapter must validate the current build/revision and locked pricebook
against the actual response fields, resolve applicable service/evidence context,
and feed the existing request-generation fence. The frozen cost artifact itself
has no catalog-snapshot or ruleset field. This reader does not synthesize those
locks or copy an expected request identity into a response. It has no endpoint,
authentication, retry, cancellation, UI or storage side effect.

Any projection into CostSummary must independently establish its required
coverage and rate-applicability evidence, handle its narrower numeric
representation and retain unknown outcomes. Structural `"complete"`,
`"measured"`, `"vendor_quote"` or `"high"` is not that evidence. Partial or
unknown estimates do not imply zero cost, a lower bound, a free service or an
actual vendor quote.

## Explicit client limits

The shared raw JSON parser admits at most 512 KiB of UTF-8, 48 nesting levels
and 16,384 values. It rejects duplicate keys, including escaped aliases,
invalid UTF-8, trailing input, unknown fields and malformed tokens with
payload-free TransferError cases.

JSON numeric tokens retain the existing limit of 15 significant coefficient
digits, 128 token bytes, exponent -64 through 64, maximum magnitude
9,007,199,254,740,991 and minimum nonzero magnitude 10^-12. Here the schema
also requires positive integral build revision and period days. The canonical
schema has no equivalent numeric upper bound; unsupported records fail rather
than rounding.

The existing frozen-pattern reader replaces terminal `$` with strict end of
input. Canonical Python pattern matching permits one terminal LF for these
anchored string patterns; the Apple reader deliberately rejects it. CR, CRLF,
NEL, Unicode line/paragraph separators, vertical tab and form feed fail the
canonical checks as well. Decimal text must otherwise satisfy the unchanged
nonnegative format with at most twelve fractional digits. Unsupported
leap-second timestamps retain the existing rejection.

The 520 shared cases include 124 canonical-valid records and 97 client-valid
records. The 27 explicit differences are nineteen terminal-LF string cases and
eight numeric representation-limit cases. No client-valid case is marked
canonical-invalid. This is a documented client subset, not a frozen-schema
change or a claim of full JSON Schema conformance.

## Reproduce and receiving evidence

Use the [package reference environment](README.md#pinned-inputs-and-validation)
and run from the repository root:

```sh
python Packages/PlannerTransfer/Tools/cost_vectors.py
python Packages/PlannerTransfer/Tools/verify_contract.py
swift test --package-path Packages/PlannerTransfer
```

The existing build, catalog and quality checks run unchanged before the added
loop over all 520 cost cases. The verifier checks all listed source
hashes. The [deterministic generator](Tools/cost_vectors.py) and Swift test
renderer apply the same compact mutations, retaining raw replacement number
tokens until the public decoder sees them.

Nine dedicated Swift methods exercise every recorded field, all enum values,
raw numeric and decimal-string boundaries, required/empty arrays, duplicate
keys, malformed input, private diagnostics, inconsistent reported arithmetic,
ordered duplicate rows, and normalized output expansion. They must actually
pass on the current hosted Transfer checkout, together with the complete
existing suite and unsigned iOS Simulator SDK build. Local Python results and
declared Swift cases do not substitute for that native execution.

This preparation does not reopen the separately accepted #32 contract scope
or close #47/#37. The #47 service prerequisites, actual wrong-build/stale/fault
API integration, shared-service receiving role and visible current-analysis
behavior remain required. Source, simulator SDK compilation, installed
application, physical-device and release acceptance retain separate evidence.
