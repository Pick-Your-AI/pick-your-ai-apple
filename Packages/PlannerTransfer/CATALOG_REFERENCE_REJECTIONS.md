# Catalog reference rejection report (partial)

A bounded contribution to [Apple issue #39](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/39). It records the within-snapshot reference policy that `FrozenCatalogCacheValidator` applies after the [whole-artifact catalog decode](CATALOG_CACHE_VALIDATION.md). It is not the complete "Apple intake validation and source-to-field rejection report" the issue names: it contains no approved real snapshot, retracted snapshot, unavailable-release replay, source-use decision or receiving-review disposition, and it does not close the issue.

## Why

The unchanged frozen-v1 catalog-item schema states each reference field's target kind only in a `description` ("Reference to catalog kind ..."). JSON Schema validation therefore accepts a `provider_ref` that names a tool, and `CatalogSnapshot.decode` preserves it. Before this change the cache admitted such a catalog. References carry an identity and no version, so an identity that appears on more than one item leaves the target undetermined.

## Policy

`CatalogReferenceIntegrity.validate(_:)` runs on a successfully decoded `CatalogSnapshot`, inside the same cache validation callback, so a rejection quarantines the whole pair and the previous pairs are retained byte-for-byte by the existing cache.

For every `spec` field below on every item, and for every element of an array-valued field, the target identity is looked up among all items of the snapshot:

| Target matches | Result |
| --- | --- |
| Exactly one item of a different kind | rejected: `wrongKind(actual:)` |
| More than one item (same or different version) | rejected: `ambiguous(candidateKinds:)`; every candidate's kind is listed, so an ambiguity whose candidates are all the wrong kind is visible as such |
| A value or array element that is not a string | rejected: `malformedReference` (unreachable while the frozen schema types these fields as strings; no decodable snapshot can reach it, so it has no test) |
| Exactly one item of the expected kind | accepted |
| No item in the snapshot | **admitted, not rejected**; listed by `CatalogReferenceIntegrity.unresolvedReferences(in:)` with reason `unresolved` (see the open decision below) |

All rejecting violations are collected, not only the first, and thrown as one `CatalogReferenceRejection`. Order is item order, then sorted field name, then array index. Each `CatalogReferenceViolation` names the source item identity and kind, the field, the zero-based array element index (nil for scalar fields), the target identity (nil only for `malformedReference`), the expected kind and the reason. The report lists at most 64 violations; further ones are counted in `omittedViolationCount`, and the whole snapshot is rejected regardless. It carries catalog identifiers and frozen field names only, not payload text.

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

### Duplicate identities and the ambiguity rule

`CatalogSnapshot` deliberately preserves duplicate item identities, and the existing duplicate-identity test keeps passing: identities that nothing references stay accepted and remain facts for the receiving graph policy. The ambiguity rule is narrower and does interact with that choice: any reference to an identity that appears on more than one item rejects the whole snapshot, because a reference carries no version and so cannot pick one candidate. If multi-version snapshots are legal and references are expected to resolve among them, this rule would reject them; that is my definition of "ambiguous", not a canonical contract rule, and is part of the open decision below. A duplicate is therefore admitted or rejected depending on whether a reference points at it.

## Open maintainer decision: unresolved targets are admitted, not rejected

Whether a reference whose target is absent from the snapshot must be rejected is not established by any canonical source I could find. The first revision of this contribution rejected them ("unknown is not pass"); the evidence below reversed that.

- The schema descriptions say only "Reference to catalog kind X"; neither the schema nor the catalog-snapshot envelope states that references resolve within a snapshot or may point outside it. No document in this repository states a resolution rule.
- **Counter-evidence in the repository.** `tools/catalog-maintenance/Sources/MaintenanceDrill/Fixtures/catalog-a.json` and `catalog-b.json` are `catalog-snapshot`-schema-valid snapshots of three items (workload, compute_profile, storage) and each holds 3 references (`cat.compute_profile.fixture` to an accelerator and a hosting platform; `cat.storage.fixture` to a hosting platform) whose targets are absent from the snapshot. The maintenance drill's CI passes because it checks exact byte membership against a closed allowlist, not the frozen validator. Its README calls that allowlist "only a fixture adapter ... not a general publisher validator" and calls the inputs "closed fictional inputs"; it does not say the dangling references are intentional, so I cannot show these files are not complete snapshots meant for the validator.
- `Fixtures/catalog.json` (29 items, 18 references) resolves every reference to exactly one item of the documented kind, so it is consistent with a resolution rule but does not establish one. The conformance vector files hold single-item mutations and do not exercise resolution. No reference field legitimately external to the snapshot was found among the 13 fields.

Given a project-authored schema-valid snapshot that would be quarantined by a resolution rule, enforcing it at the cache boundary could reject legitimate catalogs on an unestablished policy. So unresolved targets are admitted but never hidden: the validator does not mark them verified, `unresolvedReferences(in:)` lists each with its source item, field and index, and a test pins both the admission and the listing. The cost is that a publisher can point a reference at an absent identity and thereby avoid the wrong-kind check for that reference; a receiving graph policy must call `unresolvedReferences(in:)` and decide. The maintainer or the shared validation owner (Android #28) should decide whether the cache boundary rejects them; the change is confined to `CatalogReferenceIntegrity.validate`.

## Retained pairs admitted before this policy

The policy is applied whenever the cache validates a record, which includes every retained record on every load. `FrozenCatalogCacheValidator.isReplaceableRetainedFailure` classifies `CatalogReferenceRejection` as replaceable, and `CatalogCache` accepts the classifier through a new `isReplaceableRetainedFailure:` initializer parameter (the existing initializer keeps its behavior: nothing is replaceable).

- A retained record that fails with a replaceable error is excluded in memory and never served. Loading that exact pair, or the active pair when it is the failing one, throws the rejection. Other valid records, including a valid active pair, are still served, so an offline device keeps its valid cached catalog. Loads never write.
- During `refresh`, excluded records are pruned, every known pin is kept so its version stays immutable, and the newly validated pair is committed in the same atomic write. A failed or cancelled download or validation writes nothing.
- Structural, digest, identity and storage failures still block loads and refresh. A corrupt envelope, including an active manifest that names no stored record, still raises `corruptCache` even when another record is prunable.
- The pruned pair's bytes are not kept (public, re-downloadable cache data). The storage version is unchanged.

See [CATALOG_CACHE_VALIDATION.md](CATALOG_CACHE_VALIDATION.md).

## Evidence and status

| Item | Status |
| --- | --- |
| Reference table equals the bundled schema's 18 "Reference to catalog kind" descriptions over 13 distinct field names; each target kind is a `CatalogKind` | Checked by a throwaway local Python script (not committed) comparing the Swift source text with `catalog-item.schema.json` |
| `Fixtures/catalog.json` (29 items, 18 references) resolves every reference to exactly one item of the expected kind; the maintenance-drill `catalog-a.json` and `catalog-b.json` each have 3 unresolved references | Local Python scripts (a port of the algorithm, not a Swift execution) |
| Swift compilation and tests | Hosted macOS CI only; not run locally (no Swift toolchain in the authoring environment). Results for each head are recorded in the pull request; earlier revisions are superseded. One earlier revision failed to compile (`convenience` on an actor initializer) |
| `native-simulator` | In an earlier revision's run 39655358743 it failed on attempts 1, 2 and 3 and passed on attempt 4. All three failures were `simctl` timeouts (launch, install, launch) on the hosted runner, one with a host load average above 400; this change touches no App code and I did not establish the root cause |
| `git diff --check` and relative Markdown links | Run locally; see the pull request |

Reference-policy methods in `CatalogCacheValidatorTests`:

- `testWrongKindReferencesRejectTheWholeCatalogWithSourceToFieldReport` (scalar and array fields with element index; structural decode still accepts the same bytes)
- `testAmbiguousReferenceTargetsRejectEvenWhenTheVersionOrContentsAgree`
- `testAmbiguousTargetWhoseCandidatesAreAllWrongKindReportsTheirKinds`
- `testUnresolvedReferencesAreAdmittedButListedByAnExplicitQuery`
- `testReportCollectsEveryViolationInItemFieldAndIndexOrderAndCapsTheList`
- `testUnreferencedDuplicateIdentitiesRemainAvailableToTheReceivingGraphPolicy`
- `testWrongKindReferenceQuarantinesWholeCatalogAndRetainsLastValidCache` and `testAmbiguousReferenceQuarantinesWholeCatalogAndRetainsLastValidCache` (CryptoKit lane; hash-valid catalog, previous pairs and envelope bytes preserved, valid revision recovers)
- `testValidActivePairLoadsBesideAnOlderPolicyViolatingRecordAndRefreshPrunesIt` (CryptoKit lane; a pair admitted by a structural-only validator is not servable, the valid active pair is, loads do not write, a failed refresh changes nothing, a good refresh prunes)
- `testActivePairFailingTheReferencePolicyIsNeverServedButRefreshReplacesIt` (CryptoKit lane; the failing active pair throws, the older valid pair is served, refresh replaces it, the pruned version stays immutable)
- `testPruningDoesNotHideAnActiveManifestThatNamesNoStoredRecord` (CryptoKit lane; `corruptCache` despite a prunable record)

The cache methods skip without CryptoKit; a skip is not cache validation.

## Limits and remaining decisions

- The fixtures are synthetic and demonstrate the mechanism only. They are not product evidence, a source-use decision or a publication receipt.
- Pricebook `catalog_item_id` / `catalog_item_version` references to catalog items are not checked. The `CatalogCache.refresh` flow holds both validated artifacts before committing, so a pair-level check is possible there, but the per-artifact validation callback used here cannot express it. It is left to a follow-up, not implemented in this PR.
- Malformed units and missing provenance rejection are the existing schema checks covered by the earlier contribution. Replay of an approved real snapshot, a retracted snapshot and an unavailable historical release, source-use approval and receiving review remain open.
