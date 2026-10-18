# Synthetic fixture inventory and production-admission evidence

Bounded implementation for [Apple #31](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/31).
Prepared against signed main `f636afb24b8ecc1324a361aa2a7d2caa3a2481d7`, after
[#32's accepted conformance record](../../Packages/PlannerTransfer/README.md#32-receiving-conformance-record).
This record inventories the existing synthetic inputs and adds full-payload
admission tests. Independent source review and exact-head native execution are
pending. It is not a production-data qualification or a whole-issue acceptance.

## Canonical examples

The three examples use unchanged frozen contract `1.0.0` from research revision
[`7acbefbf4e4e700231e88be272bc89e3a73dde15`](https://github.com/Pick-Your-AI/pick-your-ai-research/tree/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1).
The existing [transfer source manifest](../../Packages/PlannerTransfer/source-manifest.json)
pins build/catalog inputs; the [Core fixture record](../../Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures/README.txt)
pins the pricebook. This slice copies only that exact pricebook into the transfer
test resources. It adds no app-bundled data and changes no frozen bytes.

| Input | Exact identities and visible classification | SHA-256 of original bytes |
| --- | --- | --- |
| [Build](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/Fixtures/build.json) | `build.fixture.1`, revision 1, `FICTIONAL Full-Stack AI Build`; 29 selections pinned to the fictional catalog and `2026.10-demo`; locks retain `catalog.fixture.1`, `prices.fixture.1`, `rules.fixture.1` and the canonical dependency graph | `26762208769a8cf1012b4f33b1c1608556d275187ce21117d0b9632cdf951864` |
| [Catalog](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/Fixtures/catalog.json) | `catalog.fixture.1`, revision 1; exactly one `cat.<canonical_kind>.fixture` item for each of the 29 frozen kinds; every item retains its `FICTIONAL` name and `2026.10-demo` version | `2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8` |
| [Pricebook](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/Fixtures/pricebook.json) | `prices.fixture.1`, revision 1; `rate.compute_profile.fixture` and `rate.storage.fixture` point to their exact fictional catalog versions; both are estimates with the retained note “Illustrative price, NOT a live market quote.” | `716a848822fc2b182d226c597f7e50f4b00a0fe01ba5c03879e858ca6f0c9b46` |

All three payloads remain test resources. Their schema-valid values, illustrative
prices, dates and computed test hashes supply no vendor measurement, source-use
permission, compatibility result or current quote. The build contains a fictional
`index_name` setting; its acceptance as a local snapshot does not imply acceptance
by the separate privacy-preserving import/export boundary.

## Other persisted fixture resources

This is the complete JSON resource inventory under the Core and Transfer test
`Fixtures` directories at the named base, plus the new byte-identical pricebook
copy above. The two quality resources additionally retain the exact accepted
[`549543ab` composition](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/549543abed6f75d7eef4401584b4922c1f7f59ca).
The corpora deliberately include valid and invalid mutations; their
synthetic case descriptions and location identify them as tests. The inventory is
a versioned receipt, not a promise that future added fixtures are automatically
covered.

| Resource | Purpose and limits | SHA-256 |
| --- | --- | --- |
| [Core pricebook](../../Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures/pricebook.json) | Original canonical synthetic pricebook; identical to the new transfer test copy | `716a848822fc2b182d226c597f7e50f4b00a0fe01ba5c03879e858ca6f0c9b46` |
| [Core pricebook vectors](../../Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures/pricebook-vectors.json) | 82 structural valid/invalid cases; no live-rate or pricing-engine result | `bed33221eaf346a44d27d78fb190b16ec21c41ff6c7c7c69927578bd9bbdf4dd` |
| [Core evaluation report](../../Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures/evaluation-report.json) | Frozen fictional report; reference-evaluator output, not measured readiness | `039626962ef0f2c4f706614d775ad47eda1d148c58f736c98ad169fc153221f3` |
| [Core evaluation vectors](../../Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures/evaluation-vectors.json) | 45 synthetic boundary cases; no actual safety, quality or deployment evidence | `aa7b7cdffdff0e7d810ffb68c271bfdc5258574ed3ce8e8fec9c357b68fcd137` |
| [Transfer build/selection vectors](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/Fixtures/conformance.json) | 129 canonical and client-boundary cases; not build compatibility | `e4f336bc3071637655b8f825856b6f9b5ad99ee88684481779938d846a7d08be` |
| [Transfer catalog vectors](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/Fixtures/catalog-conformance.json) | 1,635 item mutations, including disclosed client representation limits; not an approved catalog release | `163c51fa880404e4f472140ad6a3e6ff7d89bf337419a3de65fe3e8a1eeb9578` |
| [Transfer quality record](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/Fixtures/quality-evaluation-run.json) | `quality.fixture.1` / `build.fixture.1`; `0.0-fixture`, synthetic dataset and explicit test note; its stored `passed` and score are not an executed evaluation | `bc0abc0b33e2b6bf77fc4609ac88a73981068eac6fabf604c255f58fec954a6d` |
| [Transfer quality vectors](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/Fixtures/quality-conformance.json) | 202 synthetic structural cases from the accepted quality boundary; no measured quality or current-build evidence | `a64e315a3a070688af44726f78b486a9a5b0cdf375d6e31810621ae46f4a55fb` |

Inline fixtures elsewhere in `Tests` remain controlled unit-test inputs. For
example, the existing catalog-cache suite labels its `synthetic-demo-*` headers
as header-only cache-mechanics fixtures; they are not full contract conformance
evidence. The new tests below use the complete canonical catalog/pricebook pair
instead. No suffix-wide reserved namespace is inferred from any example, and
selection IDs or the canonical dependency-graph ID are not reclassified.

## Existing admission and validation interfaces

The new [SyntheticFixtureAdmissionTests](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/SyntheticFixtureAdmissionTests.swift)
are an integration test of the existing APIs. The transfer package's test target
now consumes local Core and Catalog products; the `PlannerTransfer` library
target's dependencies, public API and supported platforms are unchanged.

- `BuildTransfer.snapshot(fromDraftJSON:)` validates the complete build.
- `CatalogItem.decode(_:)` validates each of its 29 catalog items.
- `Pricebook.decode(_:)` validates the complete pricebook while preserving
  estimate and provenance fields.
- `CatalogCache` checks exact byte pins, artifact identities and its mandatory
  validation callback before atomically storing a synthetic preview.
- `RuntimeConfiguration` rejects synthetic response identity in staging or
  production and forbids an endpoint in preview configuration.

The test callback is a deliberately closed **fixture oracle**: it accepts only
the two exact canonical byte hashes and invokes the existing item/pricebook
decoders. It does not implement a general catalog-snapshot schema adapter. The
full catalog-snapshot decoder and bundled catalog UI remain with
[owned #211](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/211).
No permissive production validator or caller-supplied approval flag is added.

`CatalogDataMode.production` already rejects every refresh before downloading and
every load before returning a cached preview. The
[source-use policy](source-use-policy.md) remains unchanged: its exact known
catalog identities/demo version are an additional negative gate, and its
`syntheticOnly` result is never authorization. Neither a schema-valid snapshot
nor a self-declared HTTP envelope authenticates data. Trusted intake, current
rights and a separately accepted production-promotion record remain required
for a future real-data path.

## Reproducible negative and recovery cases

Run with the selected Apple toolchain:

```sh
swift test --package-path Packages/PlannerTransfer --filter SyntheticFixtureAdmissionTests
swift test --package-path Packages/PlannerTransfer
```

The existing [Swift transfer workflow](../../.github/workflows/swift-transfer.yml)
must execute the full package and unsigned iOS Simulator SDK compilation. The
[catalog cache workflow](../../.github/workflows/catalog-cache.yml) retains its
separate full cache/cancellation suite. The pinned Xcode selection is recorded in
[App/toolchain.json](../../App/toolchain.json); record the actual Xcode, Swift,
macOS/SDK, commit, run/job and retained log identities from the resulting jobs.
An SDK compilation is not an installed simulator or physical-device journey.

| New method | Required observed result | Recovery / preserved state |
| --- | --- | --- |
| `testCanonicalFixtureBytesMatchFrozenInventory` | All three original-byte hashes match the canonical pins | No normalization or fixture regeneration |
| `testCanonicalArtifactsKeepShapePinsAndSyntheticLabels` | Valid build, 29 kinds/selections, consistent catalog/pricebook references and retained fictional/estimate labels | No compatibility, price freshness or source-use promotion |
| `testMalformedFullFixturesFailTheirExistingBoundariesAndOriginalsRemainValid` | Wrong build schema version, unknown catalog kind and numeric money each reject through the existing decoder | Original exact examples still decode |
| `testProductionRejectsFullCanonicalPairBeforeAnyDownload` | `.productionReceiptUnavailable`; downloader call count stays zero; no preview is created | Same complete pair can subsequently load only in synthetic preview |
| `testProductionReadCannotPromotePersistedPreviewAndPreviewStillReopens` | A new cache instance rejects production read of persisted fixture bytes | Exact on-disk bytes remain unchanged and preview reopens as synthetic with current checks unknown |
| `testChangedPriceBytesDoNotReplacePreviewAndExactRetryRecovers` | A still-schema-shaped price mutation fails the original immutable digest | Previous complete pair and disk bytes survive; exact original retry works |
| `testCancellationDuringFullPairDownloadPreservesPreviewAndRetryRecovers` | Injected downloader `CancellationError` on the pricebook prevents commit | Previous full pair/disk bytes survive and original retry works; no OS background-expiration claim |
| `testSyntheticResponseCannotEnterLiveEnvironmentOrCreatePreviewEndpoint` | Both live environments reject synthetic identity; preview rejects an endpoint | Explicit endpoint-free preview accepts synthetic identity without network access |

These are required expectations, not executed native results in this preparation
environment. Swift/Xcode are unavailable locally. Hash checks, fixture inventory
inspection and whitespace checks are local evidence only. Native hash-dependent
methods explicitly skip where CryptoKit is unavailable; a skip is not a pass.
The independent reviewer and hosted exact-head receipt must record actual method
counts and failures before this slice is accepted.

## Whole-issue receiving boundary

| Unchanged #31 criterion | Contribution of this slice | Still required |
| --- | --- | --- |
| Every fixture recognizable; real-data mode rejects demo records | Complete pinned resource inventory, preserved fictional/estimate labels and exact full-payload rejection/recovery cases | Independent source review and actual selected-toolchain results; actual app fixture presentation |
| Try reserved demo IDs in real mode; preview visibly synthetic in screen, export and screenshots | Complete canonical IDs exercised against the existing production gate; no production adapter invented | Owned #198 import/export and #211 catalog UI integration and observed native artifacts |
| Linked inventory/rejection test with criterion results, exact versions, limitations and receiving disposition | This record and named methods, immutable inputs and explicit validation limits | Actual native run identities and Apple engineering/CI receiving review |

[Owned #198](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198) retains
import/fork/duplicate/export labeling and privacy behavior. Its bare/HTTP imports
remain qualification-unknown; that state is never production acceptance. #211
retains its exact bundled catalog pin and Demo catalog presentation. This slice
changes neither owned path and supplies no screenshot, app cold-start,
backgrounding, physical-device or export-observation result. Those issue-specific
checks remain unverified here, so this PR must use a partial reference and cannot
close #31 by itself.
