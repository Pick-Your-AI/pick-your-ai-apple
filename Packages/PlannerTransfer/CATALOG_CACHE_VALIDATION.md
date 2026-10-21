# Whole-artifact validation for the public preview cache

This is a bounded contribution to [Apple issue #39](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/39): a reusable frozen-v1 validator for the existing catalog/pricebook cache. It does not close the entire work package or establish production source rights, service integration, UI delivery or device acceptance.

`CatalogCache` in `PlannerCatalog` already requires a validation callback. It checks each original artifact's size, SHA-256 and identity before invoking that callback, then commits the complete pair and retained history in one envelope. An identity header is not full artifact validation.

`FrozenCatalogCacheValidator` in `PlannerTransfer` supplies that missing reusable callback:

```swift
import PlannerCatalog
import PlannerTransfer

let cache = try CatalogCache(
    directory: directory,
    isReplaceableRetainedFailure: FrozenCatalogCacheValidator.isReplaceableRetainedFailure
) { kind, bytes in
    try FrozenCatalogCacheValidator.validate(kind, bytes)
}
```

The catalog branch calls `CatalogSnapshot.decode` on the complete original `Data`, then applies the within-snapshot [reference policy](CATALOG_REFERENCE_REJECTIONS.md), which rejects the whole catalog, with a report of every violation, when an item reference resolves to exactly one item of a different kind or to more than one item. A reference to an identity absent from the snapshot is admitted, not rejected, and is listed by `CatalogReferenceIntegrity.unresolvedReferences(in:)` (an open maintainer decision recorded in the rejection report). The pricebook branch calls `Pricebook.decode` on the complete original `Data`. Existing decoder errors propagate. The adapter does not extract individual items, normalize JSON or re-encode bytes before the cache hashes or retains them. Each decoder retains its own byte, depth, node, encoding, duplicate-key and field rules; the larger cache byte ceiling does not widen either decoder's limits.

## Authority and recovery boundaries

Structural validity does not establish source-use rights, publication approval, a live price quote, compatibility or current checks. Catalog item order and schema-permitted duplicate identities that no reference points to remain facts for the receiving graph policy; references to identities absent from the snapshot are admitted but listed, not verified. Each catalog item requires a nonempty provenance array, and a pricebook's required provenance cannot be omitted. Source URIs within provenance records may remain absent; absent source URIs or unverified status do not become verified. Decimal strings retain their original spelling.

The cache remains limited to public artifacts in `.syntheticPreview`. `.production` continues to reject before downloading or loading content. A reopened preview remains synthetic with `.unknown` current checks. The adapter does not change cache pins, pair atomicity, retained-history policy, immutable revisions, cancellation, storage version, account isolation or file protection. The on-disk storage version is unchanged. It introduces no network operation. Its reference policy is limited to references between items of one catalog snapshot; pricebook-to-catalog references are not checked (possible at the pair-commit point of `refresh`, but not implemented in this change).

Every cache load revalidates the complete retained envelope, including history that is not the requested active pair. A contract-invalid retained artifact therefore blocks active, historical and missing-pair lookups, and blocks refresh before downloading. Failing bytes remain available for explicit recovery; validation does not silently evict or rewrite them. A rejected new pair leaves the previous envelope byte-for-byte intact, and a later valid revision can be admitted normally.

The reference policy is retroactive: it also runs over records admitted before it existed. A retained pair that fails only that policy is never served, and it is recoverable where other contract failures are not. `CatalogCache(isReplaceableRetainedFailure:)` lets the validator classify such an error (`FrozenCatalogCacheValidator.isReplaceableRetainedFailure`). On load, that record is excluded in memory: loading that exact pair, or the active pair if it is the failing one, throws `CatalogReferenceRejection`, while other valid records, including a valid active pair, are still served and nothing is written. During `refresh`, excluded records are pruned from retained history while all known pins stay (their versions remain immutable), and the new validated pair is committed in the same atomic write; a failed download or validation writes nothing. Pruning discards that pair's bytes, which are public and re-downloadable. Without the classifier, the unchanged initializer keeps the earlier behavior that any failing retained record blocks reads and refresh. Structural, digest, identity and storage failures are never classified replaceable, and a corrupt envelope (including an active manifest naming no stored record) still raises `corruptCache` even when another record is prunable.

## Focused verification

The twenty-one methods in `CatalogCacheValidatorTests` cover twelve pure decoder or policy boundaries and nine cache cases (the original ten from the first contribution plus eleven reference-policy methods, listed in the [rejection report](CATALOG_REFERENCE_REJECTIONS.md)). They use the unchanged frozen catalog and pricebook examples already bundled in the test target. Malformed cache candidates deliberately have correct hashes, decodable identity headers and fresh revisions so they reach the complete decoder rather than failing an earlier checksum or immutable-version check.

| Boundary | Control |
| --- | --- |
| Complete original data | Whitespace and existing pricebook UTF-16 support remain accepted. |
| Whole artifact and correct kind | Swapped artifact kinds and header-only documents fail. |
| Nested catalog/pricebook fields | Invalid kinds, string-valued numeric units and missing required provenance fail. |
| Original JSON framing | Literal and escaped duplicate keys reach the existing whole-document scanners. |
| Existing client limits | Each decoder retains its own byte, depth and node errors. |
| Receiving authority | Duplicate catalog identities, optional source-URI absence and unverified catalog/price claims retain their existing meaning; missing or empty catalog provenance is rejected. |
| Item references | A wrong-kind or ambiguous reference rejects the whole catalog with a report of every violation; unresolved targets and unreferenced duplicates are not rejected. A retained pair failing only this policy is never served but does not block other valid records, and a good refresh replaces it. See the [rejection report](CATALOG_REFERENCE_REJECTIONS.md). |
| Atomic cache admission | Malformed catalog and second-artifact pricebook candidates preserve active and historical pairs, exact dates and envelope bytes; a later valid revision recovers. |
| Reopen and retained corruption | Valid original bytes reopen exactly; internally consistent but contract-invalid older content blocks reads and refresh, preserves the failing file and permits an explicit test-fixture restoration. |

Run the focused Swift cases on the existing supported Apple toolchain:

```sh
swift test --package-path Packages/PlannerTransfer --filter CatalogCacheValidatorTests
```

The nine persistence methods require CryptoKit and explicitly skip before creating files when it is unavailable. Such a skip is not cache validation. The existing full Transfer workflow and unsigned iOS Simulator compilation remain required for delivery; these package controls do not establish application, physical-device or production acceptance.

If this contribution is composed into a branch that enforces a named exact Transfer attendance profile, derive its final profile from that complete source and select it explicitly in the workflow. Add these twenty-one method identities without replacing existing identities or weakening pass, duplicate or summary checks. Equal method counts from a different branch do not establish equal attendance.

The existing canonical fixture admission and HTTP recovery suites retain their closed, byte-pinned fixture callback. They are not replaced or relabelled as results for this general adapter. The separate [ruleset cache validator](Sources/PlannerTransfer/RulesetCacheValidator.swift), [whole catalog decoder](Sources/PlannerTransfer/CatalogSnapshot.swift) and [cache owner](../PlannerCatalog/Sources/PlannerCatalog/CatalogCache.swift) remain unchanged.
