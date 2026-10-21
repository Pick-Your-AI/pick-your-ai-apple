# Catalog reference rejection report (partial)

A bounded contribution to [Apple issue #39](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/39). It records the within-snapshot reference policy that `FrozenCatalogCacheValidator` now applies after the [whole-artifact catalog decode](CATALOG_CACHE_VALIDATION.md). It is not the complete "Apple intake validation and source-to-field rejection report" the issue names: it contains no approved real snapshot, retracted snapshot, unavailable-release replay, source-use decision or receiving-review disposition, and it does not close the issue.

## Why

The unchanged frozen-v1 catalog-item schema states each reference field's target kind only in a `description` ("Reference to catalog kind ..."). JSON Schema validation therefore accepts a `provider_ref` that names a tool, and `CatalogSnapshot.decode` preserves it. Before this change the cache admitted such a catalog. References also carry an identity and no version, so an identity that appears on more than one item leaves the target undetermined.

## Policy

`CatalogReferenceIntegrity.validate(_:)` runs on a successfully decoded `CatalogSnapshot`, inside the same cache validation callback, so a rejection quarantines the whole pair and the previous active and historical pairs are retained byte-for-byte by the existing cache.

For every `spec` field below on every item, and for every string in an array-valued field, the target identity is looked up among all items of the snapshot:

| Target matches | Result |
| --- | --- |
| More than one item (same or different version) | Rejected: `ambiguous(candidateCount:)` |
| Exactly one item of a different kind | Rejected: `wrongKind(actual:)` |
| Exactly one item of the expected kind | Accepted |
| No item in the snapshot | Not judged (neither accepted as verified nor rejected) |

The first rejection is reported in item order, then sorted field name, then array order. The thrown `CatalogReferenceRejection` names the source item identity and kind, the field, the target identity, the expected kind and the reason. It carries catalog identifiers and frozen field names only, not payload text.

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

`license_ref` is a plain string in the schema with no catalog-kind description and is not checked. Source kinds that use each field are those declared by the schema's `spec_*` definitions; the check is by field name.

## Evidence and status

| Item | Status |
| --- | --- |
| Table matches the bundled schema's 13 "Reference to catalog kind" descriptions exactly, and every target kind is a `CatalogKind` | Checked by a throwaway local Python script comparing the Swift source text with `catalog-item.schema.json`; the script is not committed |
| The unchanged `Fixtures/catalog.json` (29 items) resolves every reference to exactly one item of the expected kind | Same local script, a Python port of the Swift algorithm; this is not a Swift execution |
| Swift compilation and the five new test methods | Pending hosted macOS CI; not run locally (no Swift toolchain in the authoring environment) |
| `git diff --check` and relative Markdown links | Run locally; see the pull request |

The five new `CatalogCacheValidatorTests` methods:

- `testWrongKindReferencesRejectTheWholeCatalogWithSourceToFieldReport` (scalar and array fields; structural decode still accepts the same bytes)
- `testAmbiguousReferenceTargetsRejectEvenWhenTheVersionOrContentsAgree`
- `testReferencePolicyRejectsOnlyReferencedAmbiguityAndLeavesUnresolvedTargetsUnjudged`
- `testWrongKindReferenceQuarantinesWholeCatalogAndRetainsLastValidCache` (CryptoKit lane; hash-valid catalog, previous active and historical pairs and envelope bytes preserved, valid revision recovers)
- `testAmbiguousReferenceQuarantinesWholeCatalogAndRetainsLastValidCache` (same cache assertions)

The two cache methods skip without CryptoKit; a skip is not cache validation.

## Limits and remaining decisions

- The fixtures are synthetic and demonstrate the mechanism only. They are not product evidence, a source-use decision or a publication receipt.
- Whether a reference to a target absent from the snapshot must be rejected is an open decision for the receiving graph/release policy and the shared canonical validation (Android #28). This change does not decide it and does not treat such a reference as verified.
- "Ambiguous" is defined here as more than one item with the target identity. Whether versions may legitimately coexist in one snapshot, and how a reference would then pin one, is a canonical-contract question not settled by this change.
- Pricebook `catalog_item_id` / `catalog_item_version` references to catalog items are a pair-level check. The cache validation callback sees one artifact at a time, so this is not implemented.
- Malformed units and missing provenance rejection are the existing schema checks covered by the earlier contribution; replay of an approved real snapshot, a retracted snapshot and an unavailable historical release, and receiving review, remain open.
