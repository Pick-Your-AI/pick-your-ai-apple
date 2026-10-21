# Catalog reference rejection report (partial)

A bounded contribution to [Apple issue #39](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/39). It records the within-snapshot reference policy that `FrozenCatalogCacheValidator` applies after the [whole-artifact catalog decode](CATALOG_CACHE_VALIDATION.md). It is not the complete "Apple intake validation and source-to-field rejection report" the issue names: it contains no approved real snapshot, retracted snapshot, unavailable-release replay, source-use decision or receiving-review disposition, and it does not close the issue.

## Why

The unchanged frozen-v1 catalog-item schema states each reference field's target kind only in a `description` ("Reference to catalog kind ..."). JSON Schema validation therefore accepts a `provider_ref` that names a tool, and `CatalogSnapshot.decode` preserves it. Before this change the cache admitted such a catalog. References carry an identity and no version, so an identity that appears on more than one item leaves the target undetermined.

## Policy

`CatalogReferenceIntegrity.validate(_:)` runs on a successfully decoded `CatalogSnapshot`, inside the same cache validation callback, so a rejection quarantines the whole pair and the previous pairs are retained byte-for-byte by the existing cache.

For every `spec` field below on every item, and for every element of an array-valued field, the target identity is looked up among all items of the snapshot:

| Target matches | Violation reason |
| --- | --- |
| No item in the snapshot | `unresolved` |
| More than one item (same or different version) | `ambiguous(candidateKinds:)`; every candidate's kind is listed, so an ambiguity whose candidates are all the wrong kind is visible as such |
| Exactly one item of a different kind | `wrongKind(actual:)` |
| Exactly one item of the expected kind | accepted |
| A value or array element that is not a string | `malformedReference` (unreachable while the frozen schema types these fields as strings; it has no test because no decodable snapshot can reach it) |

All violations are collected, not only the first, and thrown as one `CatalogReferenceRejection`. Order is item order, then sorted field name, then array index. Each `CatalogReferenceViolation` names the source item identity and kind, the field, the zero-based array element index (nil for scalar fields), the target identity (nil only for `malformedReference`), the expected kind and the reason. The report lists at most 64 violations; further ones are counted in `omittedViolationCount`, and the whole snapshot is rejected regardless. It carries catalog identifiers and frozen field names only, not payload text.

| Field | Expected target kind |
| --- | --- |
| `provider_ref` | `model_provider` |
| `accelerator_ref`, `accelerator_refs` | `accelerator` |
| `hosting_ref` | `hosting_platform` |
| `data_source_refs` | `data_source` |
| `tool_refs`, `associated_tool_refs` | `tool` |
| `compute_profile_ref` | `compute_profile` |
| `storage_ref` | `storage` |
| `base_model_ref` | `model` |
| `training_framework_ref` | `training_framework` |
| `training_dataset_ref`, `dataset_refs` | `training_dataset` |

`license_ref` is a plain string in the schema with no catalog-kind description and is not checked. The check is by field name; every such field appears directly under an item's `spec`.

Identities shared by items that nothing references stay accepted: they remain facts for the receiving graph policy, consistent with the existing duplicate-identity test. A duplicate is therefore admitted or rejected depending on whether a reference points at it.

## Open policy decision: unresolved targets are rejected

Rejecting a reference whose target is absent from the snapshot is this contribution's conservative choice ("unknown is not pass"; otherwise a publisher can evade the wrong-kind check by pointing a reference at an absent identity). It is not a rule found in a canonical contract. What was checked:

- The schema descriptions say only "Reference to catalog kind X"; neither the schema nor the catalog-snapshot envelope states that references resolve within a snapshot or may point outside it.
- No document in this repository states a resolution rule.
- Of the repository's JSON fixtures, only `Fixtures/catalog.json` holds complete catalog items. All 18 of its references resolve to exactly one item of the documented kind. The conformance vector files hold single-item mutations and do not exercise resolution.
- No field legitimately external to the snapshot was found among the 13 reference fields (`license_ref` is a different, free string and is excluded).

If a canonical rule later permits references to items outside a snapshot (for example a partial snapshot), the maintainer or the shared validation owner (Android #28) should relax or scope the `unresolved` reason in `CatalogReferenceIntegrity`; this PR does not claim that decision.

"Ambiguous" is defined here as more than one item with the target identity. Whether versions may legitimately coexist in one snapshot, and how a reference would then pin one, is likewise not settled by a canonical contract.

## Retained pairs admitted before this policy

The policy is applied whenever the cache validates a record, which includes every retained record on every load. A pair admitted under the earlier structural-only validator that fails the new policy is therefore never served: `load` and `load(_:)` throw `CatalogReferenceRejection`, as for any contract-invalid retained record.

Unlike other contract failures, that one is recoverable. `FrozenCatalogCacheValidator.isReplaceableRetainedFailure` classifies it, and `CatalogCache` accepts the classifier through a new `isReplaceableRetainedFailure:` initializer parameter (the existing initializer keeps its behavior: nothing is replaceable). During `refresh` only, a retained record that fails with a replaceable error is dropped from the retained history, every known pin is kept so its version stays immutable, and the newly downloaded and validated pair is committed in the same atomic write. If the download or its validation fails, nothing is written. Structural, digest, identity and storage failures still block refresh. The dropped pair's bytes are not kept (they are public, re-downloadable cache data). The storage version is unchanged. See [CATALOG_CACHE_VALIDATION.md](CATALOG_CACHE_VALIDATION.md).

## Evidence and status

| Item | Status |
| --- | --- |
| Reference table equals the bundled schema's 18 "Reference to catalog kind" descriptions over 13 distinct field names; each target kind is a `CatalogKind` | Checked by a throwaway local Python script (not committed) comparing the Swift source text with `catalog-item.schema.json` |
| The unchanged `Fixtures/catalog.json` (29 items, 18 references) resolves every reference to exactly one item of the expected kind | Same kind of local script, a Python port of the algorithm; not a Swift execution |
| Swift compilation and tests | Hosted macOS CI only; not run locally (no Swift toolchain in the authoring environment). Signed source `7d11b223f224a71be78224f86b46cf168329a492`: `macos-transfer` (run 39655358791) executed all 19 `CatalogCacheValidatorTests` with 0 failures and none skipped; `macos-catalog-cache` (39655358822), `macos-catalog-maintenance` (39655358907), `macos-storage` (39655358942), `submission-sdk` (39655358830), `frozen-contract-preparation` (39655359594), `dependency-review` (39655358776) and the `macos-core` jobs (39655358714) passed. `native-simulator` in run 39655358743 failed twice on runner-side `simctl` install/launch timeouts (host load average above 400 in the first retry's log) and passed on the third attempt; that is infrastructure, not a result for this change on its own. The earlier source `267af40` failed to compile (`convenience` on an actor initializer) and is superseded |
| `git diff --check` and relative Markdown links | Run locally; see the pull request |

Reference-policy methods in `CatalogCacheValidatorTests`:

- `testWrongKindReferencesRejectTheWholeCatalogWithSourceToFieldReport` (scalar and array fields with element index; structural decode still accepts the same bytes)
- `testAmbiguousReferenceTargetsRejectEvenWhenTheVersionOrContentsAgree`
- `testAmbiguousTargetWhoseCandidatesAreAllWrongKindReportsTheirKinds`
- `testUnresolvedReferenceTargetsAreRejectedSoTheyCannotEvadeTheKindCheck`
- `testReportCollectsEveryViolationInItemFieldAndIndexOrderAndCapsTheList`
- `testUnreferencedDuplicateIdentitiesRemainAvailableToTheReceivingGraphPolicy`
- `testWrongKindReferenceQuarantinesWholeCatalogAndRetainsLastValidCache` and `testAmbiguousReferenceQuarantinesWholeCatalogAndRetainsLastValidCache` (CryptoKit lane; hash-valid catalog, previous pairs and envelope bytes preserved, valid revision recovers)
- `testRetainedPairFailingOnlyTheReferencePolicyFailsClosedButRefreshReplacesIt` (CryptoKit lane; a pair admitted by a structural-only validator is not served, a failed refresh changes nothing, a good refresh replaces it and the older valid pair remains)

The cache methods skip without CryptoKit; a skip is not cache validation.

## Limits and remaining decisions

- The fixtures are synthetic and demonstrate the mechanism only. They are not product evidence, a source-use decision or a publication receipt.
- Pricebook `catalog_item_id` / `catalog_item_version` references to catalog items are not checked. The `CatalogCache.refresh` flow holds both validated artifacts before committing, so a pair-level check is possible there, but the per-artifact validation callback used here cannot express it. It is left to a follow-up, not implemented in this PR.
- Malformed units and missing provenance rejection are the existing schema checks covered by the earlier contribution. Replay of an approved real snapshot, a retracted snapshot and an unavailable historical release, source-use approval and receiving review remain open.
