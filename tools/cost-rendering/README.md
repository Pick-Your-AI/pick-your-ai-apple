# Native cost coverage rendering

This separate test application renders the production `PlannerUI.CostCoverageView`
with explicitly synthetic `PlannerCore.CostSummary` inputs for
[Apple #78](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/78).
It opens no draft library, imports no user file and contacts no pricing service.
The production imported-build call site still supplies no estimate until a
qualified producer is available.

The host receives only a fixture-group identifier. Expected display strings,
positive and negative assertions, and outcome checks live in the separate XCTest
process. Every scenario passes `isSynthetic: true` to the production view and
requires its actual synthetic-pricing label in the observed native content.

## Declared scenarios and required observations

The three methods declare **17 view states**, not 17 separately named test
methods. None is claimed executed until an original qualified native result is
retained for the exact receiving source.

| Native method | States | Required observation |
| --- | ---: | --- |
| `testMostExpensiveRateRemovalKeepsBudgetUnknownAndRecoveryVisible` | 3 | A complete USD 110 projection exceeds a USD 100 budget. Removing the synthetic expensive component's USD 90 rate leaves a USD 20 partial projection, its unpriced selection and an unknown budget result. The partial subtotal never displays a satisfied or exceeded budget or a complete total. Restoring the complete projection restores the exceeded result and removes the prior missing-selection text. |
| `testMissingZeroExpiredUnsupportedMixedAndStaleCostsRemainQualified` | 10 | Absent estimates and missing amounts stay unknown; literal partial/unknown zeros stay qualified. A complete current zero may satisfy the budget. Unsupported meters, expired or unverified rates and mixed currencies retain their limiting explanations and unknown budget result. A mismatched revision exposes neither its received amount nor its missing-cost details. |
| `testLargeTextCompactAndWideLayoutsRetainExactMoneyAndBoundedMissingCosts` | 4 | Requested 375- and 820-point layouts use the accessibility3 text size. Long exact decimal amounts and a one-trillionth budget difference remain distinguishable. Partial coverage stays unknown; all first 20 of 22 missing meters and the visible truncation notice remain accessible, while the two omitted items are absent. A recovered complete projection restores the exceeded result. |

The rate-removal inputs are explicit synthetic projections matching the component
regression's USD 110 / USD 20 / USD 100 scenario. The host does not calculate rates,
reconcile canonical line totals or establish real rate applicability.

The test reads actual native static-text labels and, on macOS, their string
values. It checks each fixture identity and position before reading only the
production view's vertical viewport. The single vertical scroll owner avoids
using an occluded outer horizontal viewport for gestures. The scan retains
observed text across at most sixteen scrolls and requires two unchanged reads
after finding all positive labels. Negative assertions apply to the accumulated
observations. Exact-money checks reject a different numeric value that merely
shares the expected prefix, such as USD 200 in place of USD 20.

On iOS, the vertical drag uses the content frame's nonempty intersection with the
actual app window, with both endpoints inside that intersection. This keeps the
820-point fixture's gesture on screen on a compact iPhone. Window-relative
coordinates use Apple's documented
[normalized origin](https://developer.apple.com/documentation/xcuiautomation/xcuielement/coordinate(withnormalizedoffset:)),
[point offsets](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/withoffset(_:))
and [coordinate drag](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/press(forduration:thendragto:))
APIs, checked on 2026-10-18. The gesture's actual operation remains a native-run
obligation; source inspection does not establish a rendered-frame observation.

The requested widths and text size come from the host's explicit layout inputs.
The test also requires a nonempty native viewport and successful fixture controls.
This is source-backed native text/layout qualification; it does not measure glyph
clipping, provide screenshot comparison or constitute VoiceOver interaction.

## Existing workflow integration

The existing `Native local drafts` workflow invokes this separate host on the
actual macOS runner architecture after its 133-method UI package gate. Its
configured editor, library, catalog, app build and iPhone/iPad journeys remain.
The new derived-data directory must be absent at the original fresh-cache check.

The existing `Swift client core` workflow invokes the same three methods on the
already selected iPhone SE (3rd generation) and iPad (10th generation), both using
the installed iOS 18.5 runtime. It reuses that workflow's observed destination
identities. It changes no simulator identity or fallback policy, core regression,
negative test, mutation gate, timeout or toolchain pin.

Each invocation retains its original log and a distinct `.xcresult` bundle.
The new `qualify.py` requires one complete `Selected tests` or `All tests` session,
each exact class-qualified start and pass exactly once, and the matching
three-test, zero-failure summary. Unknown, duplicate, missing, failed, skipped,
out-of-session and out-of-order method records fail. A Swift Testing zero-test
footer does not supply XCTest evidence. Existing historical UI package profiles
and all shared conformance/mutation helpers remain unchanged.

Portable receipt-parser regressions use synthetic log specimens:

```sh
python3 -B -m unittest discover -s tools/ci/tests -p test_cost_rendering_results.py -v
```

They validate only the receipt parser. They do not execute Swift, render a view
or supply a native acceptance result.

On the pinned macOS environment, the isolated host can be reproduced from the
repository root with new result/output paths:

```sh
set -euo pipefail
mkdir -p .build/cost-rendering-evidence
xcodebuild test -project tools/cost-rendering/CostHarness.xcodeproj -scheme CostHarness \
  -sdk macosx -destination "platform=macOS,arch=$(uname -m)" \
  -parallel-testing-enabled NO \
  -only-testing:PlannerCostUITests/CostRenderingTests \
  -derivedDataPath .build/cost-rendering-native \
  -resultBundlePath .build/cost-rendering-evidence/cost-macos.xcresult \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
  2>&1 | tee .build/cost-rendering-evidence/cost-macos-test.log
python3 tools/cost-rendering/qualify.py .build/cost-rendering-evidence/cost-macos-test.log
```

The `.xcresult` path must not already exist; preserve earlier evidence when
repeating a run. For iOS, use the existing workflow's exact destination selection
and separate iPhone/iPad logs and result bundles.

## Receiving and acceptance boundary

The source extends the reviewed cost integration preparation
[`2c044896aaa1b19d4f88d715a6070d1682bf5a8e`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/2c044896aaa1b19d4f88d715a6070d1682bf5a8e),
whose receiving offer is recorded on
[#198](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198#issuecomment-6256489817).
Its original cost component, snapshot context, call site and 133-method profile
remain intact. This continuation has no native execution receipt yet.

| Literal #78 criterion | Prepared evidence and remaining gate |
| --- | --- |
| Missing costs cannot render as zero or an unqualified complete total. | Component/context regressions and the declared native absence, literal-zero, partial and stale cases. Actual results must name the final source, checkout, platform, toolchain and retained original output. |
| Remove the most expensive component's rate, apply a budget, show partial cost and never satisfy it from the subtotal. | The declared three-state native method checks the actual production view. It uses synthetic received projections; worked scenarios still need the named #77 canonical pricing-service output. |
| Link missing-rate/coverage/budget tests with criterion results, exact versions, limits and receiving review. | This source/test mapping plus the exact receiving preparation and future original native records. Independent receiving review and current-main delivery remain required before a completed disposition. |

Actual native results, the named #54 accessibility output and #77 canonical
pricing output remain separate prerequisites. The accessibility3 fixtures are
not physical-device, assistive-technology, canonical-service, store or release
acceptance. No issue criterion, pricing policy or frozen wire contract is changed.
