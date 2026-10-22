# #62 — Component comparison preparation

This record follows the three literal criteria in [Apple #62](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/62). It preserves the reviewed main-only donor `ac007c7aa2e1189574f040a9c06abf3d36de7c58`, originally based on accepted main `5387e5b7ace7d6eef57059722040675a9f3618e8`, and first reconciles that donor onto accepted main `76f84345eb4b5451af4385e8207fa7f8719ccc0a`. The corrected receiving source subsequently incorporates accepted main `9e40c79b6eb37273a821d8eddf1c00d57ad4b33c` by ordinary merge, preserving its Ruleset addition. The separately published mounted adapter retains its own source, ownership and evidence. It is **not a completion receipt**: SwiftUI compilation, the mounted catalog receiving composition, native interaction, accessibility recording and independent receiving disposition remain pending.

## Literal criterion matrix

| Original criterion, unchanged | Concrete implementation and required evidence | Current result |
| --- | --- | --- |
| Comparison retains comparable units and all relevant conditions. | `ComponentComparisonModel` aligns exact schema field names and displays each cell's declared type. Identity, versions, specifications, license, description, tags, provenance and extensions remain available. Normalized values retain decimal numbers and ordered arrays. No conversion, numeric delta, ranking or evidence transfer is performed. | Implemented; 19 Swift regression methods authored, including the receiving binding correction below. Native compilation and execution pending. |
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
| A supplied value that cannot be encoded for comparison | Always “Recorded declarations differ” and “Contains unknown information”; unknown is never treated as equal (fail closed). |
| Same declarations, including the same missing state | “Same recorded declaration”; unknowns remain explicitly identified. |
| Declared provenance status, source URI or license permission | Retained declaration, not an independently checked claim or navigation permission. |

No condition is dropped by the comparison: the four sections retain every top-level field and the complete optional specification/license field sets. Full provenance and namespaced extensions remain inspectable even when they carry contradictory, expired, private-looking or unknown text. Their presence supplies no semantic approval. Difference filtering changes the visible rows only; it does not remove selections or their evidence. The whole normalized record is available separately, without truncation. Text uses literal JSON and visible control-character escapes; source URLs do not become links.

## Receiving adapter and current-main composition

Accepted main at the current receiving base does not contain the catalog browser, imported-build library or mounted catalog journey foundation. The catalog browser, detail source and native journeys are owned by the separate #198 receiving lane. This patch does not replace that browser or import its entire receiver.

The [published adapter and independent source review](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/62#issuecomment-6258055872) remain separate from this main-only composition. Adopting that adapter requires review against its exact current receiving source. Its integration boundary is:

1. The existing `CatalogBrowserView` owns one comparison model and a separate comparison presentation flag. The existing query, kinds, sort, page, selected row and detail-sheet identity are retained.
2. The existing detail model rechecks its active loaded result, complete displayed item identity and exact catalog pin at the moment of the explicit Add action. An unavailable, mismatched or retired detail cannot add a record. The existing immutable bundled source remains the membership authority for its exact verified fixture bytes.
3. The existing detail view offers Add to comparison and reports the result without closing its evidence inspection or consuming source-link consent. The browser opens the shared comparison view through a distinct action. Neither action enters a build writer.
4. Actual adapter regression methods retain browser filters/rows and source review, exercise unavailable/retry and cancellation-ignoring late results, and verify dismissal retirement. The receiving workflow must require the complete current UI inventory, preserving all pre-existing methods and guards. Its count must be recomputed for the actually adopted receiving source; the isolated main total below is not a receiving count.

Until that adapter is applied, compiled, mounted and exercised on the selected receiving source, this main-source model/view is **preparation**, not delivered catalog interaction. The existing #198 privacy, SDK, Graph, native-control and main-integration work retains its independent owner and evidence.

The later [mounted donor receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/62#issuecomment-6258894858) publishes `b33c7d72bb17c4de0227767026bfe3b7580c3f36`, tree `5be2899865bb57a5e04f47df7ed80ca41ad0df78`, with sole parent `7620719b79ae54dc6f0e409fe8ce1e9d9ee0d76a`. That source includes a separately identified five-record synthetic catalog, the actual catalog-selection adapter, two native journeys at default and accessibility text sizes, and strict result/attachment qualification. The receipt records source review and ten passing host guard tests; it explicitly records no native execution. Its original canonical fixture bytes remain unchanged. This current-main patch neither duplicates that donor nor claims it is accepted main.

The [latest #198 recovery disposition](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198#issuecomment-6264322043) still requires the exact selected receiving objects and parent roles. Signed `2206ea74b25b7b5c0406563d237e4e7fe332ed21` is staging, not accepted main; replacing the missing selected union with that older full tree would omit accepted intervening work. Mounting and native acceptance therefore remain in the canonical receiving lane.

### Exact current-main preservation

The main-only donor has sole parent `5387e5b7ace7d6eef57059722040675a9f3618e8` and tree `fd20f02ae37f7eb99882afe3f37f93ed08c24958`. The initial receiving checkpoint `755ef423cdd720ef98d4d7d420b63eae52779924`, tree `67932bf0e3cc4d9253cbfff83a4f3b7d5320c211`, preserves its three new production Swift files and 18-case comparison test file byte-for-byte. The subsequent correction below changes only the view binding and adds one comparison test; the projection, model and all 18 original test bodies remain unchanged. The initial composition preserves all 255 original-main files outside the eleven-path donor scope. Against the later accepted `9e40c79` main, all 261 unrelated files are unchanged and the complete eleven-path Ruleset increment is preserved exactly.

Only two donor paths overlap newer main edits. `PlannerUI/Package.swift` retains main's Core dependency and existing evidence-test fixtures while adding the donor Catalog and Transfer dependencies. `native-ui.yml` retains main's actual macOS evidence-rendering UI job, cache controls and artifact retention while adding the complete comparison-model execution gate. Main's #181 asynchronous-open correction and both of its regression methods remain unchanged. The original 43-case receiving profile below preserves both accepted methods without rewriting the historical 41-case donor profile. The later 44-case profile additionally requires the binding correction regression.

The final ordinary receiving merge has ordered parents `93f752d6f12114caa2aeef6a16d79083d94b021b` (the reviewed sheet correction, tree `655daddf1cf09ea90a305c8fe3a3f89259f05750`) and accepted main `9e40c79b6eb37273a821d8eddf1c00d57ad4b33c` (tree `2195fdaeab547f68d1ca5be4210bf895f9da6d7e`). The merge has no source conflict. It changes no comparison Swift file, test, workflow or evidence profile from `93f752d`; only this receipt's composition identity and evidence attribution need reconciliation. All Ruleset schema, wrapper, fixtures, tests, validator and reference-source changes remain exactly as accepted in #359.

### Receiving correction: delayed sheet dismissal

Review of the actual `ComponentComparisonView` sheet binding found that its original setter read `model.inspection` at callback time and closed that current UUID. A retained binding from an earlier sheet therefore bypassed the model's existing `closeInspection(capturedID)` fence and could dismiss a replacement inspection. Direct model tests alone did not cover that UI boundary.

The view now captures the inspection UUID when constructing the binding used by `.sheet`. Its getter returns only that still-current presentation, and its setter passes only the captured UUID to `closeInspection`; an empty or retired binding cannot expose or dismiss a later inspection. Non-nil writes remain ignored. The explicit Done action and all model/selection behavior remain unchanged.

`testCapturedInspectionBindingRejectsStaleDismissalAndReplacement` exercises that actual view binding, not a copied callback: it retains an empty binding, replaces the first inspection, dismisses through stale bindings, attempts a non-nil replacement, successfully dismisses through the current binding, then reopens the same candidate with a fresh UUID and rejects another delayed dismissal. Selections remain intact throughout. This authored Swift regression has not executed in the current Linux workspace. The same correction must be reviewed when adopting the separate mounted `b33c7d7` donor; its owned source branch remains untouched.

## Regressions and observed local checks

The 18 original methods in [`ComponentComparisonModelTests`](../../Packages/PlannerUI/Tests/PlannerUITests/ComponentComparisonModelTests.swift) cover:

- Explicit zero/one/two/four/five membership, stable order and removal/retry at the cap.
- Duplicate input, conflicting record/kind, immutable catalog hash/capture conflicts, distinct revisions and byte-distinct Unicode versions.
- Exact decimals, zero, false, missing, explicit unknown, empty text/collections and schema-derived not-applicable cells.
- Four independent unit/version/currency/region/offering/effective-time tuples, complete evidence and all top-level condition fields.
- Difference-filter retention, failed source/recovery, inspection replacement/removal/terminal retirement, malformed pins/items, complete literal display and independent sessions.

These are authored Swift tests, **not locally executed Swift tests**. Their synthetic unit-test pins exercise identity rules only; they do not stand in for the real adapter's fixture-membership proof.

The copied upstream XCTest result parser and its historical profiles are preserved. `component-comparison-main-ui` retains the original donor inventory of **41 distinct passed methods**: 23 editor and 18 comparison methods. It is historical evidence for that source, not this later composition's count.

The initial receiving `component-comparison-current-main-ui` profile retains exactly **43 distinct passed methods**: all 25 accepted editor methods and all 18 comparison methods, qualified by both XCTest class names and one complete successful XCTest summary. It inherits every original required identity and adds `testEditsDuringOpenKeepOriginalDraftAndUnsavedInput` and `testLifecycleSaveDuringOpenPersistsLatestEditsToOriginalDraft` from accepted #181. A dedicated guard regression rejects replacement of either accepted open-recovery method while preserving the claimed total.

Both existing native-model and submission-SDK workflows now invoke `component-comparison-failclosed-ui`, requiring **45 distinct passed methods**: the complete 44-method `component-comparison-inspection-ui` inventory (43 receiving methods plus the actual view-binding regression) plus `testValuesThatCannotBeEncodedForComparisonNeverCollapseIntoSame`. The 44-case profile is retained unchanged. All prior profiles remain unchanged. Compile messages, duplicate names, other-class substitutes, missing/failed/skipped cases, a padded old editor run, and padded old 41- or 43-case comparison runs cannot qualify this corrected source.

Historical local observations retained from the published `ac007c7` donor on 2026-10-19; these are not executions of the later current-main composition:

| Check | Actual scope and result |
| --- | --- |
| Existing Swift 6.1.2 Linux compiler, `-frontend -parse -swift-version 6`, four new/adopted Swift source files | Exit 0. Syntax parsing only; no imports were type-checked and no SwiftUI, model tests or native app ran. |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/ci/tests -p 'test_swift_test_results.py' -v` | All 11 Python guard methods passed, 0.061 seconds, including complete/false-green CLI presentation specimens. This verifies the evidence gate, not the Swift implementation. |
| Full SwiftUI package compilation/model execution, unsigned app build and mounted native journeys | Pending actual hosted execution of the reviewed source. Linux SwiftUI is unavailable. |

In that earlier donor session, the initial version probe without the existing runtime library failed with missing `libncurses.so.6`. Supplying the already present library for that subprocess allowed both existing binaries to identify themselves as Swift 6.1.2 for `x86_64-unknown-linux-gnu`. Nothing was installed or globally reconfigured. Shared disk pressure also blocked ordinary sandbox startup before some read commands; those attempts performed no tests or source changes.

Preparation checks on 2026-10-19 retain their actual source identities. App-script and original Transfer checks below ran at the initial `755ef42` receiving checkpoint. CI guards were rerun for the `93f752d` sheet correction. Their results are not relabeled as executions of the later merge; its comparison/CI/App source files are unchanged, while the accepted Ruleset addition changes the Transfer tree and receives the separate fresh reference check below:

| Check with its recorded source identity | Actual result |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/ci/tests -v` | 81 Python cases passed, zero failures/skips, 7.821 seconds. This includes all 12 execution-evidence guard regressions and existing native-scope/obsolete-run guards. |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s App/scripts/tests -v` | 25 Python cases passed, zero failures/skips, 1.105 seconds. These use host specimens and do not execute Xcode or a simulator. |
| Fresh isolated environment installed from `Packages/PlannerTransfer/Tools/requirements.txt` with `--isolated --require-hashes --only-binary=:all:`, followed by `pip check` and `verify_contract.py` | No broken requirements. Verified 14 source hashes, 129 base cases, all 29 catalog kinds/1,635 catalog cases, 202 quality cases, 520 cost cases, 223 resource cases, 98 placement cases and 150 dependency-graph cases. These are canonical Python reference checks, not Swift execution. |
| Fresh `verify_contract.py` replay after merging accepted `9e40c79` | Verified 16 source hashes and all the preceding canonical case inventories, plus 321 Ruleset syntax cases. The hash-pinned environment and requirement file remain unchanged. This verifies the later merged reference inputs, not Swift or rule execution. |
| Exact profile/source comparison | All 12 donor profiles, the 43-case receiving profile and the 44-case inspection profile are unchanged. The new 45-case profile adds only the fail-closed difference regression; source declarations do not establish execution. |
| `python3 tools/acceptance/check_map.py`, whitespace and relative Markdown links | Internal baseline coverage remains 129 issues and 465 exact criteria; whitespace and relative links pass. This does not assert a fresh all-issue acceptance export. |

The fresh workspace has no Swift compiler or Apple SDK, so no new Swift syntax, type-check, model-execution or native result is claimed here. Hosted checks must execute the exact reviewed final receiving tree before merge. The initial dependency download was blocked by the network sandbox; the automatically reviewed, hash-pinned retry succeeded into the isolated temporary environment without changing repository pins.

## Review follow-up limits (Opus review of #388)

- **Fail-closed differences.** A supplied value whose normalized encoding fails no longer collapses into the absent (`nil`) state: the cell is marked not comparable, its row always reports a difference and unknown information, and a test injects a failing encoder to prove it. Two absent values still report the same missing state, labelled as unknown.
- **Wide-grid accessibility is unverified.** In the wide layout each cell sets `accessibilityLabel("Component n, field")` and then `accessibilityElement(children: .contain)`. Whether VoiceOver announces the container label as context for the contained text, rather than reading a bare value, is not established by package tests or by SwiftUI documentation. The narrow layout carries explicit component headings and is unaffected. No VoiceOver or other assistive-technology result is claimed; the recording below remains required and this layout must be re-examined there.
- **Not localized.** The comparison view and `ComponentComparisonError.message` use English literals. The existing localized path in PlannerUI is a closed, per-view `Bundle.module` table (`ClaimEvidence.strings` in en/de/ar) selected by the view's locale; extending it needs reviewed translations and a rendering-lane scenario, which are not available here. Localization is deferred, not claimed. Values remain verbatim by design.
- **Top-level key list.** `ComponentComparisonModel.rows` hardcodes the identity and evidence keys, while specification and license fields are derived from the bundled schema. All 15 current top-level `catalog-item.schema.json` properties are covered and a fixture-driven test checks every key of a full item. The bundled schema is private to PlannerTransfer, so a schema-derived guard in PlannerUI would require a new PlannerTransfer API and test-count changes; that is deferred. A new schema property would not be shown until this list is updated.
- **Cost-rate provenance.** The three `RecordedCostRateProvenance` paths are carried byte-identical from #404's review-fixed head so this PR cannot revert that fix. They are #76 preparation only (see the #76 row in the acceptance index); #62 is unaffected.
- **Landing order.** #387 adds a PlannerUI test, which breaks the exact-45 `component-comparison-failclosed-ui` profile unless that profile is bumped in the same change. This is an ordering concern, not addressed here.

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

The original main-only donor and later mounted adapter have the independent source-review receipts linked above. Independent receiving review and actual hosted execution are still required for this newer current-main composition. Its preparation is local; publication and merge of it must follow the existing signed-commit, independent-review and repository check gates. No physical-device result, VoiceOver recording, service/catalog publication, production source approval, current price, compatibility assessment or builder mutation is claimed. #62 remains open until its literal criteria and receiving evidence are satisfied.
