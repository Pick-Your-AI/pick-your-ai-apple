# Exact catalog search identities

This bounded correction supports [Apple #59](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/59).
It changes the local catalog index and its existing actor regressions. It does
not establish a live catalog, selection integration, mounted UI, accessibility
or whole-issue acceptance.

## Required boundary

The frozen [CatalogItem schema](../../Packages/PlannerTransfer/Sources/PlannerTransfer/Resources/catalog-item.schema.json)
allows any nonempty string for `version`. Its common ID rule remains ASCII.
Versions `release.caf\u{00e9}` and `release.cafe\u{0301}` therefore can identify
different records even though [Swift String equality](https://docs.swift.org/latest/documentation/the-swift-programming-language/stringsandcharacters)
considers their rendered characters canonically equivalent. These spellings use Swift escape notation;
the index receives the decoded strings.

The existing [discovery contract](../../Packages/PlannerCatalog/README.md#snapshot-consistent-local-discovery)
requires distinct `(id, version)` pins and rejects changed entry bytes under an
unchanged release. [JSON Schema instance equality](https://json-schema.org/draft/2020-12/json-schema-core#section-4.2.2)
distinguishes different decoded code-point sequences. Accepted
[Transfer equality](../../Packages/PlannerTransfer/Sources/PlannerTransfer/JSONValue.swift)
preserves the same boundary. Equivalent JSON escapes that decode to the same
string remain the same identity; this change does not compare JSON formatting.

Previously, a synthesized String key rejected those two versions as a duplicate
snapshot. Synthesized entry equality could also treat a changed version or title
as an identical reinstall and retain the old entry and cursor. These are source
findings from the original [PR #338](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/338)
contribution, whose source review did not execute Swift or mounted UI. PR #337's
separate original Linux regressions retain their own source and result attribution;
neither contribution's earlier execution establishes the combined receiving result.

## Correction and preserved behavior

Composite keys hash the original UTF-8 bytes after the existing scalar byte limits
have passed. Entry equality compares the decoded
bytes of all four supplied fields, without normalizing or rewriting them.
Both sort modes preserve the existing String display comparisons. Only a
canonical-equivalence tie uses UTF-8 order, so distinct pins have a deterministic
order when the same input arrives in another order.

Folded title search, query trimming, kind filters, scalar bounds, snapshot limits,
duplicate exact-pin rejection, release generation and opaque cursor checks are
unchanged. No compatibility, ranking, price or semantic-version policy is added.
The upstream adapter still validates canonical records and source-use authority.

## Regression and evidence scope

Two existing methods in
[CatalogSearchIndexTests](../../Packages/PlannerCatalog/Tests/PlannerCatalogTests/CatalogSearchIndexTests.swift)
retain their original assertions and add actual actor operations:

| Existing method | Added required behavior |
| --- | --- |
| `testDistinctVersionsRemainSeparateAndCompositeDuplicatesReject` | Both Unicode versions install, retain exact bytes across single-row pages in both sorts, preserve the cursor on reversed identical input, and still reject an exact duplicate without replacing the old release. |
| `testRejectedRefreshRetainsPriorReleaseAndIdenticalInstallPreservesCursor` | Changed version or title bytes reject an unchanged release; original bytes and cursor survive; an exact copy is idempotent; a new revision accepts the changed bytes, retires the old cursor, and preserves folded search. |

These two additions preserve the eleven methods in this test class. The combined
receiver also retains the four separate `CatalogSearchExactVersionTests` methods
from [PR #337](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/337), for fifteen
search methods in the combined Catalog package. Receiving
profiles must match the complete actual source; historical results for either
contribution do not qualify their combination. The exact combined candidate must
run the existing Catalog and submission-SDK gates before delivery. No workflow
is dispatched or weakened by this correction.

A standalone read-only check used the existing jsonschema 4.25.1 environment and
the committed Draft 2020-12 schemas to validate the original fictional model item
and both version variants. All three passed. The CatalogItem schema SHA-256 is
`81c960c6e7dfe046634062e3f9ce5a1089b1d88adbd9fd45d9a67dcfc0339a25`;
the common schema SHA-256 is
`0342ce2f1114e7276fc7f6a08ff5b86e8727caadd83ae4f443de9a7e1431c43c`.
This confirms the fixture values against those exact schemas. It is separate
from Swift execution, the pinned Transfer reference driver, producer approval,
native integration and physical-device acceptance.
