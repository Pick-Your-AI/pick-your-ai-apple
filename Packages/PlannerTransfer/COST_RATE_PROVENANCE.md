# Inspect recorded cost-rate provenance

`RecordedCostRateProvenance` lets an Apple consumer inspect the references in a retained cost estimate alongside a supplied Build and Pricebook. It preserves the original estimate rows, exposes uniquely matching candidate records and reports differences without changing the inputs. This is a bounded consumer contribution to [Apple #76](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/76).

The existing [CostEstimateRecord](Sources/PlannerTransfer/CostEstimateRecord.swift), [BuildTransfer](Sources/PlannerTransfer/BuildTransfer.swift) and [PlannerCore Pricebook](../PlannerCore/Sources/PlannerCore/Pricebook.swift) readers remain the structural admission boundaries. The new consumer accepts only their already-decoded values. A missing reference or conflicting supplied record is an association observation; it does not retroactively invalidate a structurally valid frozen-v1 estimate.

## Supply the exact retained records

```swift
import PlannerCore
import PlannerTransfer

let build = try BuildTransfer.snapshot(fromDraftJSON: retainedBuildData)
let estimate = try CostEstimateRecord.decode(retainedEstimateData)
let pricebook = try Pricebook.decode(suppliedPricebookData)
let inspection = RecordedCostRateProvenance(
    build: build, estimate: estimate, pricebook: pricebook
)
```

Pass `nil` when no Pricebook was supplied. That records absence of an input, not evidence that no Pricebook exists elsewhere. The consumer performs no network request, cache lookup, storage operation, public export or update of a visible Build. Its originals can contain private settings, notes and assumptions; retaining them locally does not authorize sharing them.

`inspection.build`, `inspection.estimate` and `inspection.pricebook` keep the supplied values. The estimate retains its ID, Build revision, period, currency, coverage, totals, unpriced selections, methods, confidence, assumptions and warnings. The Pricebook retains its own ID, revision, capture timestamp and every supplied rate. No record is repaired or replaced.

## Interpret the results

There is one `lines` entry for each original estimate row, in original order. `position` is an index within this immutable estimate, not a reusable line identity. Duplicate line IDs remain separate rows and receive `duplicateLineID`.

| Result | Meaning |
| --- | --- |
| `inputIssues` | Differences between the supplied Build identity/revision, optional Build Pricebook lock, estimate Pricebook ID, supplied Pricebook ID and Build/estimate currencies; also an absent Pricebook. These remain visible even for an estimate with no lines. |
| `line` | The complete original cost line, including its literal quantity, unit price, amount, method, confidence and assumptions. |
| `candidateSelection` | The single selection with the recorded selection ID in the supplied Build. It retains its complete JSON value and position. Missing or duplicate IDs yield no candidate. |
| `candidateRate` | The single rate with the recorded rate ID in the supplied Pricebook. Missing or duplicate IDs yield no candidate. Every source field remains available through the original `PriceRate`. |
| `selectionMatchCount`, `rateMatchCount` | Exact ID-match counts in these supplied records. The consumer never chooses the first or last of several matches. A missing Pricebook has zero supplied rate matches. |
| `issues` | The input issues plus this row's missing/ambiguous references, duplicate line ID, disabled selection, item/version/meter differences, literal unit-price differences and line/estimate currency differences. |
| `limitations` | The four permanent qualification boundaries below. They apply even when every issue list is empty. |

Candidates are ID matches for inspection. For example, a foreign Pricebook can contain the same rate ID; the candidate remains inspectable while every row retains `suppliedPricebookIDDiffers`. The consumer does not call that foreign rate applicable. It similarly keeps a matching selection candidate from a foreign or different-revision Build while reporting the mismatched input on every row.

Missing references stay absent. There is no fallback based on another rate's item, meter, region or price, and no new priced row is created from an unpriced selection or a reported total. Duplicate referenced IDs remain ambiguous even when their rows are identical. Unreferenced duplicate rows remain in the originals and do not create ambiguity for a different uniquely referenced ID.

## Exact text and source conditions

Frozen IDs are ASCII. Catalog versions and other text are compared using their exact UTF-8 spelling; visually equivalent Unicode versions do not silently become one identity. The supplied records are not normalized for display or joined by a name.

Unit-price amounts remain their recorded decimal strings. `0.80` and `0.8000` produce `unitPriceAmountTextDiffers` even though the existing `ContractDecimal` numeric comparison considers them equal. This is a text difference for inspection, not a claim that one amount is wrong. Arbitrarily long supported integer digits and twelve fractional digits remain intact. There is no conversion through `Double`, rounding, multiplication, currency conversion or reconstruction of a total.

The candidate rate retains its exact item/version, meter, region, currency, unit-price string, `validFrom`, optional `validUntil`, price type, ordered conditions and provenance. Missing optional values differ from empty text and empty arrays. Duplicate conditions, original order and reported verification labels are preserved.

| Permanent limitation | Consequence |
| --- | --- |
| `pricebookRevisionNotRecorded` | Frozen CostEstimate v1 carries only `pricebook_id`; neither it nor the Build's optional Pricebook lock carries a Pricebook revision or content hash. Matching all supplied fields cannot prove which Pricebook revision produced the estimate. A later supplied revision is still only the caller's supplied record. |
| `rateApplicabilityNotAssessed` | The consumer does not decide date validity, stale/future/expired status, region precedence, conditions, rate type, meter support or whether a disabled selection should have a price. A reversed date interval remains a reported source declaration for canonical review. |
| `sourceDeclarationsNotVerified` | Source URI, checked timestamp, notes and `verified`/other labels are reported data. They do not establish an inspected source, source-use rights, a live quote or acceptable free/included evidence. Zero and words such as “included” do not grant those claims. |
| `arithmeticAndCoverageNotAssessed` | Recorded usage, line amounts, tax, totals and coverage are not recomputed. An empty issue list cannot establish complete coverage, a budget result or a correct estimate. |

Any UI that later consumes this object must show the relevant input/row issues and the permanent limitations. It must label the candidate as a supplied record, keep both differing values visible and preserve the distinction between reported labels and independently accepted evidence. The consumer offers no `verified`, `current`, `applicable` or budget-success result.

## Meaningful validation

[RecordedCostRateProvenanceTests](Tests/PlannerTransferTests/RecordedCostRateProvenanceTests.swift) use the existing fictional Build, Pricebook and estimate fixtures through the real unchanged typed readers. They cover exact matching inputs; absent/foreign Pricebooks; foreign and changed Build revisions; missing locks; missing and ambiguous references; duplicate/reordered lines; exact item/version/meter/currency differences; Unicode and long decimal preservation; optional absence; disabled selections; unassessed dates, regions and source conditions; later Pricebook revisions; zero/included declarations; empty priced lines; private local text; and deliberately inconsistent reported totals.

The controls retain original records during missing-reference and changed-revision recovery. They compare exact JSON values and literal money text where the existing Pricebook's numeric money equality would hide a spelling difference. An assertion that a candidate is present always describes a supplied ID match, with the permanent limitations still present.

Run the focused and full package checks from the repository root:

```sh
swift test --package-path Packages/PlannerTransfer --filter RecordedCostRateProvenanceTests
swift test --package-path Packages/PlannerTransfer
```

Execution receipts must identify the actual source, toolchain, command and observed outcome. Portable Swift package tests do not qualify macOS/iOS SDK integration, simulator behavior, physical devices or canonical service parity. The repository's configured native checks and independent receiving review remain part of ordinary delivery.

## Remaining #76 acceptance

This contribution supplies a way to inspect recorded rate references and their source conditions. It does not select an applicable dated rate. Canonical rate selection remains coordinated through [Android #66](https://github.com/Pick-Your-AI/pick-your-ai-android/issues/66); rounding and scenario parity retain their separate [Android #85](https://github.com/Pick-Your-AI/pick-your-ai-android/issues/85) and [Apple #77](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/77) work. Pricing policy and versioned contract changes remain under [research #39](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/39) and [research #40](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/40).

The complete #76 criteria still require accepted canonical applicability and evidence rules, dated regional/expired/mixed-currency vectors, exact producer revision authority where the contract supports it, worked decimal totals, Apple integration and receiving disposition. The unchanged v1 revision limitation must remain explicit or be resolved through a separately versioned contract; this client helper cannot fill it by inference. No issue criterion is closed by adding this type or by synthetic fixture execution alone.
