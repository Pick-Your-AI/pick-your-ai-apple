# Mounted component comparison: candidate evidence contract

This is the separate #62 candidate on signed catalog source `2206ea74b25b7b5c0406563d237e4e7fe332ed21` and reviewed adapter tree `f5b9e0a4c6ca154a31cdae792037851322fc6336`. It does not change the canonical #198 branch or borrow that branch's unrelated 133-test inventory. These new journeys have **not executed natively**. Source parsing and Python guard execution are not SwiftUI compilation or accessibility recordings.

## Exact closed collection

The Debug app accepts only `--comparison-examples-v1` to mount `CatalogBrowserView(collection: .comparisonExamples)` through its existing Demo catalog tab. The optional `--comparison-accessibility3` flag applies SwiftUI's documented `dynamicTypeSize(.accessibility3)` to that subtree. It is not a device Settings change. Release builds retain the original catalog. Neither argument accepts a file, URL, credential, catalog bytes, saved draft, comparison selection or arbitrary text size.

The original 29-item catalog and SHA-256 `2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8` remain unchanged. The new `catalog-comparison-preview.json` has these exact source facts:

| Field | Value |
| --- | --- |
| SHA-256 | `7d5e39193254ad2830f74628aec91a8d95bd782329550f0438d717e4e92dd69e` |
| Catalog ID / revision / schema | `catalog.comparison.examples.v1` / `1` / `1.0.0` |
| Captured | `2026-10-19T00:00:00Z` |
| Records | Five explicitly fictional, unverified records; no current vendor specification, rate, measurement or source host is adopted. |

| Version | Exact item ID | Kind | Unit declaration | Region declaration | Distinct specification state |
| --- | --- | --- | --- | --- | --- |
| `fixture-v1` | `cat.comparison.compute` | `compute_profile` | 1000 milliseconds/request | `fixture-east` | Recorded `disk_gb: 0`; missing `network_gbps`. |
| `fixture-v2` | `cat.comparison.compute` | `compute_profile` | 1 seconds/request | `fixture-west` | Missing `disk_gb`; recorded `network_gbps: 0`. |
| `fixture-v3` | `cat.comparison.storage` | `storage` | 1 tokens/second | `unknown` | Compute disk/network fields are not applicable to this schema kind. |
| `fixture-v4` | `cat.comparison.storage` | `storage` | 1 requests/second | empty text | Missing optional storage capacity stays unknown. |
| `fixture-v5` | `cat.comparison.control` | `compute_profile` | 500 milliseconds/request | `fixture-control` | Distinct fifth record for rejection and explicit remove/recovery. |

Units and full offering/effective-time/workload conditions are namespaced extension declarations. They remain opaque complete objects; the comparison does not convert or rank them. Different units and unknowns do not imply zero or equivalence. The source applies the existing canonical snapshot validator, an exact byte hash, exact five-member identity list and complete row/pin membership before producing details. Its search preferences use a separate key. The existing comparison admission model, detail revalidation, original catalog source and existing journey files remain unchanged.

## Two real-control journeys

`ComponentComparisonJourneyTests` has exactly these methods:

1. `testComparisonRetainsExactUnitsVersionsAndLimitRecovery` uses default text, the narrow iPhone portrait viewport and wide iPad landscape viewport.
2. `testComparisonAtAccessibilitySizeRetainsNavigationAndCompleteValues` repeats the actual flow with the explicit accessibility3 subtree. Both devices must use the stacked field layout at that size.

Each opens the real catalog, sets a query, both explicit kind filters and kind sort, selects two then three then four exact versions through detail Add, checks all held labels and original snapshot pins, traverses four sections, reads exact zero/missing/not-applicable/explicit-unknown/empty states, parses the complete displayed four unit/condition objects, and uses all/differences without discarding selections. It opens and dismisses complete evidence, returns to unchanged filters, rejects a fifth addition, removes only component two, adds the fifth, and clears to a recoverable empty state. The comparison is read-only and no builder or saved-draft writer is called.

The test captures eight named checkpoints per method: two-selected, three-selected, four-exact-states, complete-unit-conditions, complete-record, fifth-rejected, remove-and-recover and empty-recovery. Every checkpoint retains the actual `app.debugDescription` hierarchy and screenshot. The final matrix attachment records actual observed labels, typed values, complete extension declarations, filter values and measured layout selection after their assertions. Visible field-navigation and empty-control audits cover `hitRegion` and `sufficientElementDescription`; a visible condition-field audit covers `textClipped` and `sufficientElementDescription`. Each audit is explicitly limited to its current viewport, not a full-screen/VoiceOver or participant study. Original videos and full hierarchies remain necessary for receiving review of reading order, clipping and interaction.

Each reveal remains bounded to 12 attempts and each existence/predicate wait to 10 seconds. New comparison navigation uses observed target/container geometry: slow whole swipes for targets farther than a viewport, then the existing small slow drag when near the target. No absolute tap point, sleep, additional simulator reset or original-journey timeout change is introduced. Native execution must establish whether those bounds reach the actual controls.

## Separate pinned runner lane

The original `Planner` scheme and notes/catalog suite remain intact. The new `PlannerComparison` scheme retains successful system attachments using `systemAttachmentLifetime="keepAlways"`; it otherwise uses the same app and UI-test targets. Apple's [Xcode 15 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes) document screen recordings as the default capture format. The new lane records actual Xcode 16.4 / 16F6, Swift/macOS/runtime versions and `xcresulttool help export attachments` before testing. Configuration and documentation do not establish that a recording was produced.

The closed runner suite is:

```sh
python3 App/scripts/ui-journey.py --suite component-comparison \
  --evidence-directory .build/component-comparison-evidence/ui-journey
```

It preserves iOS 18.5, iPhone SE (3rd generation), iPad (10th generation), fresh process-owned simulators, exact verified create IDs, 120-second destination selection, the existing 15-minute per-device test budget and owned shutdown/delete cleanup. A separate 40-minute workflow job prevents the extra journeys from silently consuming the original suite's execution budget. There are no retries or fallback devices/toolchains. A new evidence directory is mandatory; earlier receipts are never overwritten.

The ordinary native-model and submission-SDK gates use `component-comparison-examples-ui`: exactly **139** distinct successful UI model methods, the complete prior 133 plus six new source qualification/filter/concurrency/admission regressions. Every historical profile remains. This count is specific to this candidate; receiving later main/canonical source requires a new source-derived union inventory.

## Evidence gate and remaining acceptance

The runner requires a successful structured 2/2 summary plus two exact class-qualified once-passed XCTest results, successful attachment export, strict matrix verification and successful owned cleanup for **each** pinned destination. Its verifier rejects failed/skipped/retried or missing methods, wrong owners, duplicated attachments, missing or altered units/conditions/pins/states/filter values, unknown manifest schemas, unsafe paths/symlinks, missing checkpoint hierarchies, incomplete PNGs and missing or truncated success recordings. Export failure, verification failure or timeout invalidates the result before cleanup. Full original `.xcresult` bundles, export stdout/stderr, matrices, video/image containers and hashes are retained even on failure where available.

Screenshot qualification requires intact PNG chunk bounds and CRCs, at least 320 pixels along both dimensions, and the journey's explicit portrait iPhone or landscape iPad orientation. The video check verifies ISO media container bounds and nonempty movie/media boxes; it does not decode video or claim readable frames, duration, touch accuracy or participant acceptance. The retained originals must still be viewed and related to exact selectors and source by an independent receiver. Apple documents the [modern xcresult commands in Xcode 16.3](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes); an unexpected actual export schema or absent success video fails this gate and requires diagnosis, never a guessed positive receipt.

The ten Python tests exercise real CLI/filesystem rejection paths using explicitly synthetic parser specimens. They do not run Swift, launch an app, generate real screenshots or supply native acceptance. Local Linux syntax parsing has the same limited qualification. #62 remains open pending actual current-source model compilation, both journeys on both devices, original-recording review and criterion-by-criterion receiving disposition.
