# #62 — Component comparison preparation

## 2026-10-19 mounted candidate checkpoint

The isolated main model/view was independently source-reviewed at tree
`fd20f02ae37f7eb99882afe3f37f93ed08c24958`. The separate catalog adapter was
independently source-reviewed at `f5b9e0a4c6ca154a31cdae792037851322fc6336` on
signed `2206ea74b25b7b5c0406563d237e4e7fe332ed21`, then persisted as source-only
`7620719b79ae54dc6f0e409fe8ce1e9d9ee0d76a`. Its independent local commit has the
same tree. Those facts supersede the earlier preparation-only publication and
pending-source-review sentences below; they do not supply native acceptance.

The [mounted journey evidence contract](../../App/COMPONENT_COMPARISON_JOURNEY.md)
now describes a separately pinned fictional five-record catalog, Debug-only real
app entry, exact-cell identifiers, two bounded journey methods, default/large text
and narrow/wide layouts, original-recording retention and strict evidence checks.
The source is a candidate; the new 139-model inventory and four device/method
executions have not run natively. The three original criteria below stay unchanged
and unclosed. Canonical #198 and the separate recorded-version route are preserved.

## Original isolated-main preparation and criterion record

This record follows the three literal criteria in [Apple #62](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/62). It describes an isolated implementation on accepted main `5387e5b7ace7d6eef57059722040675a9f3618e8` and a separately prepared receiving adapter. It is **not a completion receipt**: SwiftUI compilation, the mounted catalog receiving composition, native interaction, accessibility recording and independent receiving disposition remain pending.

## Literal criterion matrix

| Original criterion, unchanged | Concrete implementation and required evidence | Current result |
| --- | --- | --- |
| Comparison retains comparable units and all relevant conditions. | `ComponentComparisonModel` aligns exact schema field names and displays each cell's declared type. Identity, versions, specifications, license, description, tags, provenance and extensions remain available. Normalized values retain decimal numbers and ordered arrays. No conversion, numeric delta, ranking or evidence transfer is performed. | Implemented; 18 Swift regression methods authored. Native compilation and execution pending. |
| Compare two to four variants with different units, versions and missing values on a narrow screen; do not rank incomparable facts as better or zero. | Explicit ordered membership has a four-record cap, minimum two-record matrix, immutable catalog conflict rejection, exact version identity and unknown/not-applicable states. A field-first narrow layout and a wide grid use the same cells. The four-unit/four-version specimen keeps each complete unit, currency, region, offering and effective-time tuple. | Source and specimens prepared. The required narrow-screen interaction and accessibility recording have not executed. No variant-family relationship is inferred. |
| The component comparison matrix and accessibility recording is linked with criterion results, exact versions, limitations and receiving-review disposition. | This matrix records the exact input boundary, API, host checks, proposed mounted adapter, required device journey and unresolved evidence. Future actual recordings must bind their source commit, prepared tree, toolchain, destination and complete case identities. | Matrix linked; accessibility recording and final independent receiving disposition pending. |

The named #61 prerequisite is **“Every material claim has inspectable evidence or an explicit gap.”** Its immutable projection and qualified detail consumer are already present on the separately reviewed catalog integration source. This preparation reuses that projection and proposes an explicit consumer adapter; it does not wait for, or assert, the complete closure of #61. [The accepted platform ADR](../decisions/issue-22-platform.md) and [repository scope](../REPOSITORY_SCOPE.md) still govern integration. No canonical schema or shared service is redefined.

## Source and interface boundaries

The upstream [`CatalogItemDetails`](../../Packages/PlannerTransfer/Sources/PlannerTransfer/CatalogItemDetails.swift) file is preserved **byte-for-byte** from signed integration commit [`2206ea74b25b7b5c0406563d237e4e7fe332ed21`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/2206ea74b25b7b5c0406563d237e4e7fe332ed21). Main's `catalog-item.schema.json` and `common.schema.json` are identical to that source. The projection enumerates optional fields from those actual schemas and preserves the validated `CatalogItem`; it adds no unchecked item initializer. Its earlier execution belongs to that upstream source, not this new UI composition.

The new main-source interface is:

- `ComponentComparisonCandidate(item:catalog:)`: an immutable validated item plus the caller's exact `ArtifactPin`. The caller must first establish that the item belongs to those catalog bytes. Constructor pin checks establish bounded shape only; they do not manufacture membership, publication, source-use or production approval. `encodedItem` is the normalized item representation, explicitly distinct from the snapshot SHA-256.
- `ComponentComparisonModel`: explicit `add`, `remove`, `clear`, `inspect`, `closeInspection` and unavailable-result handling. It retains at most four candidates in selection order. Section and difference-filter preferences are local session state. There is no durable storage, network operation, builder selection or draft writer.
- `ComponentComparisonView(model:)`: a read-only field matrix and complete-record inspector. Narrow windows and accessibility text sizes show each field followed by separately labelled component values; sufficiently wide windows show aligned columns. Dismissing the view retains the browser-owned comparison model.

Duplicate exact records are idempotent. Different content claiming the same item ID/version in one exact catalog is rejected, including cross-kind aliases. A changed hash or capture claiming the same catalog ID/revision is rejected before it can mix with held records. Different actual revisions and versions remain distinct. Pin and version keys compare UTF-8 bytes, so canonically equivalent Unicode spellings are not silently treated as the same version.

### Meaning of values and differences

| Observed declaration | Display meaning |
| --- | --- |
| Optional field absent in this kind's schema-defined field set | Unknown: not recorded. |
| Literal `unknown`, empty text, empty collection, or unknown entries in an array | A separately labelled unknown state; original contents remain visible. |
| Recorded `false` or numeric zero | A supplied declaration with its real type and value, not a missing field or approval. |
| Field absent from this component kind's schema definition | Not applicable **to this kind's contract field set**; no real-world capability inference. |
| Unequal typed declarations | “Recorded declarations differ”; no better/worse, compatibility or equivalent-unit verdict. |
| Same declarations, including the same missing state | “Same recorded declaration”; unknowns remain explicitly identified. |
| Declared provenance status, source URI or license permission | Retained declaration, not an independently checked claim or navigation permission. |

No condition is dropped by the comparison: the four sections retain every top-level field and the complete optional specification/license field sets. Full provenance and namespaced extensions remain inspectable even when they carry contradictory, expired, private-looking or unknown text. Their presence supplies no semantic approval. Difference filtering changes the visible rows only; it does not remove selections or their evidence. The whole normalized record is available separately, without truncation. Text uses literal JSON and visible control-character escapes; source URLs do not become links.

## Receiving adapter proposal

Accepted main at the implementation base has only the local draft UI. The catalog browser, detail source and native journeys are owned by the separate #198 receiving lane. This patch does not replace that browser or import its entire receiver.

The separate adapter proposal must be reviewed against its exact source before adoption. Its intended changes are limited to:

1. The existing `CatalogBrowserView` owns one comparison model and a separate comparison presentation flag. The existing query, kinds, sort, page, selected row and detail-sheet identity are retained.
2. The existing detail model rechecks its active loaded result, complete displayed item identity and exact catalog pin at the moment of the explicit Add action. An unavailable, mismatched or retired detail cannot add a record. The existing immutable bundled source remains the membership authority for its exact verified fixture bytes.
3. The existing detail view offers Add to comparison and reports the result without closing its evidence inspection or consuming source-link consent. The browser opens the shared comparison view through a distinct action. Neither action enters a build writer.
4. Actual adapter regression methods retain browser filters/rows and source review, exercise unavailable/retry and cancellation-ignoring late results, and verify dismissal retirement. The receiving workflow must require the complete current UI inventory, preserving all pre-existing methods and guards. Its count must be recomputed for the actually adopted receiving source; the isolated main total below is not a receiving count.

Until that adapter is applied, compiled, mounted and exercised, this main-source model/view is **preparation**, not delivered catalog interaction. The existing #198 privacy, SDK, Graph, native-control and main-integration work retains its independent owner and evidence. The separate recorded-version checkpoint also remains independent; its adoption is not assumed.

## Regressions and observed local checks

The 18 methods in [`ComponentComparisonModelTests`](../../Packages/PlannerUI/Tests/PlannerUITests/ComponentComparisonModelTests.swift) cover:

- Explicit zero/one/two/four/five membership, stable order and removal/retry at the cap.
- Duplicate input, conflicting record/kind, immutable catalog hash/capture conflicts, distinct revisions and byte-distinct Unicode versions.
- Exact decimals, zero, false, missing, explicit unknown, empty text/collections and schema-derived not-applicable cells.
- Four independent unit/version/currency/region/offering/effective-time tuples, complete evidence and all top-level condition fields.
- Difference-filter retention, failed source/recovery, inspection replacement/removal/terminal retirement, malformed pins/items, complete literal display and independent sessions.

These are authored Swift tests, **not locally executed Swift tests**. Their synthetic unit-test pins exercise identity rules only; they do not stand in for the real adapter's fixture-membership proof.

The copied upstream XCTest result parser and its historical profiles are preserved. The new `component-comparison-main-ui` profile requires exactly **41 distinct passed methods**: all 23 original editor methods and all 18 comparison methods, qualified by both XCTest class names and one complete successful XCTest summary. Both existing native-model and submission-SDK workflows invoke this profile. Compile messages, duplicate names, other-class substitutes, missing/failed/skipped cases and a padded old editor run cannot satisfy it.

Observed local checks on 2026-10-19:

| Check | Actual scope and result |
| --- | --- |
| Existing Swift 6.1.2 Linux compiler, `-frontend -parse -swift-version 6`, four new/adopted Swift source files | Exit 0. Syntax parsing only; no imports were type-checked and no SwiftUI, model tests or native app ran. |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/ci/tests -p 'test_swift_test_results.py' -v` | All 11 Python guard methods passed, 0.061 seconds, including complete/false-green CLI presentation specimens. This verifies the evidence gate, not the Swift implementation. |
| Full SwiftUI package compilation/model execution, unsigned app build and mounted native journeys | Pending actual hosted execution of the reviewed source. Linux SwiftUI is unavailable. |

The initial version probe without the existing runtime library failed with missing `libncurses.so.6`. Supplying the already present library for that subprocess allowed both existing binaries to identify themselves as Swift 6.1.2 for `x86_64-unknown-linux-gnu`. Nothing was installed or globally reconfigured. Shared disk pressure also blocked ordinary sandbox startup before some read commands; those attempts performed no tests or source changes.

## Required mounted journey and accessibility recording

After receiving integration, record the actual iPhone narrow viewport and adaptive iPad, including a large accessibility text size. A recording is still required; a source review, syntax parse or simulator launch is not that recording.

1. Apply non-default catalog query/kind/sort filters, inspect one exact record, inspect its provenance, and explicitly add it. Confirm the source inspection and filters remain unchanged.
2. Close details, inspect and add a second, third and fourth qualified record. Confirm stable selection order, complete ID/version/catalog/hash labels and aligned fields. Include the required different-version/unit/missing-value specimen through a reviewed, explicitly synthetic source; do not silently alter the existing pinned fixture to manufacture it.
3. Read an exact decimal, false, zero, missing/unknown field and schema-not-applicable cell. Retain the complete conditions for different units/currencies/offerings; verify no preferred rank, conversion or zero substitution appears.
4. Traverse each field section, switch all/differences, inspect the complete record, dismiss inspection and comparison, and confirm catalog query/kinds/sort/rows/inspection identity and all retained pins.
5. Try a fifth item, remove one and retry. Exercise an unavailable detail, recovery, a replaced/cancelled detail and a changed catalog revision without publishing a stale or conflicting selection.
6. Capture actual semantic labels/selected states, reading order, reachable controls, untruncated conditions and narrow-screen scrolling. Keep original video/screenshots, accessibility hierarchy, exact selectors, test results, destination/runtime and source/prepared commit identities. Reconcile any failed or unexecuted case before criterion acceptance.

The layout uses documented [Grid column alignment](https://developer.apple.com/documentation/swiftui/grid), [accessibility text-size detection](https://developer.apple.com/documentation/swiftui/dynamictypesize/isaccessibilitysize), [contained accessibility children](https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:)) and [selected traits](https://developer.apple.com/documentation/swiftui/accessibilitytraits/isselected). Their documented platform availability fits iOS/iPadOS 17 and macOS 14. That API availability does not prove this interface's actual accessibility behavior.

## Receiving disposition and limits

Independent source review is pending for this exact candidate and the separate mounted adapter. No public source branch, PR, workflow dispatch or merge has been performed for this preparation. No physical-device result, VoiceOver recording, service/catalog publication, production source approval, current price, compatibility assessment or builder mutation is claimed. #62 remains open until its literal criteria and receiving evidence are satisfied.
