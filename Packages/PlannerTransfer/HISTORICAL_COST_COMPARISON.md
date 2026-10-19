# Historical cost comparison

This bounded implementation contributes to [Apple #79](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/79).
It compares two supplied historical records using the existing frozen
[CostEstimate reader](COST_ESTIMATE.md) and saved BuildSnapshot boundary. The
existing configuration-only BuildComparison remains unchanged.

## Recorded sides and identity

Construct each `HistoricalCostScenario` from its actual saved build and the
estimate that names it. The constructor requires an exact build ID, the same
numeric revision, and the Pricebook ID in that build's own locks. It rejects
ambiguous build selection IDs, ambiguous cost line IDs, and priced or unpriced
selection references absent from that saved build. This is stricter comparison
admission; it does not change what the frozen decoder accepts.

`HistoricalCostComparison.compare(before, after)` preserves both complete value
trees. Different estimates cannot reuse one historical estimate identity while
changing its content. The existing BuildComparison revision guard rejects
conflicting saved configurations with the same build/revision identity while
retaining its order-independent selection/link handling.

Neither side receives a current request's expected identity. A failed comparison
leaves both original inputs available and changes no persisted data. These APIs
perform no storage, network, UI or approval action.

## Inspectable differences

| Comparison output | Behavior |
| --- | --- |
| Build and estimate identities | Each side retains its own saved build, revision, full locks and estimate ID. |
| Pricebook, timestamp and period | Exact supplied identities, timestamp spelling and integral period remain inspectable. No missing Pricebook revision or source-use receipt is synthesized. |
| Changed scalar fields | Stable typed field list identifies changed identities, locks, period, currency, amounts, recorded coverage, unpriced IDs and warnings. Original values remain on their own side. |
| Line differences | Unique line IDs join two complete recorded rows in stable order. The join is a display aid; changed selection/rate/meter/method/conditions remain on the actual row. It does not prove that different line IDs or selection IDs represent equivalent components. |
| Absent line | The corresponding side is `nil`. No zero-valued replacement line is created. |
| Decimal text | All supported digits, trailing zeros and quantity/amount spellings remain strings. No Double, Decimal or currency conversion is applied to monetary text. |
| Local serialization | Each retained BuildSnapshot and CostEstimateRecord uses its existing `encoded()` method and reopens through the unchanged decoder. Original Pricebook identity and every reported condition remain attached. |

Line ordering alone creates no line difference. A changed line ID is an explicit
removal and addition. Warnings, assumptions and other text use the existing
exact-UTF-8 JSON equality, so canonically equivalent but differently encoded
historical wording remains distinguishable.

## Qualification and privacy

Every result carries `reportedValuesOnly`. Additional cautions identify different
Pricebooks, currencies or periods, partial/unknown recorded coverage, unpriced
selections, and currency inconsistencies within either record. A supplied
`complete`, `measured` or `high` label is retained as a reported label; it is not
converted to verified coverage, measured usage, applicable rates or correct
arithmetic. An inconsistent reported subtotal/tax/total is preserved rather than
silently repaired.

The result produces no aggregate, savings amount, ordering by cost, budget
verdict or cross-currency conversion. A future approved conversion/computation
policy requires its own exact inputs and evidence. Renderers must keep the
per-side recorded labels and cautions visible; this data API does not establish
a mounted comparison screen.

The original records can contain private workload fields, warnings and
assumptions. Retaining them for local inspection and local serialization is not
a public-export sanitizer or permission to disclose them. Existing public
sharing projection, redaction preview and source-use controls remain separate.
Errors contain fixed cases without echoed input text.

## Reproduce and remaining acceptance

From a checkout with the repository's accepted Swift toolchain:

```sh
swift test --package-path Packages/PlannerTransfer --filter HistoricalCostComparisonTests
swift test --package-path Packages/PlannerTransfer
```

The new synthetic regressions cover exact per-side bindings, ambiguous/absent
references, changed/removed line rows, different Pricebooks/currencies/periods,
partial totals, reported-complete records with unpriced selections, every nested
currency position, immutable identity conflicts, exact Unicode and long decimal
text, and independent local serialization. Fixtures derive from the existing
explicitly fictional frozen examples. They supply no observed cost or source-use
qualification.

The exact receiving source still requires independent review and the configured
repository checks. Actual mounted historical-scenario presentation, canonical
service/rate qualification, public-export projection and the issue's complete
integration evidence remain open. This module does not claim #79 acceptance or
change another contribution's delivery route.
