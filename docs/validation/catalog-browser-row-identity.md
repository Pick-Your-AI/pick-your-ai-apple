# Exact catalog version identity in browser rows

This bounded correction follows [Apple #59](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/59)
on the existing [#391 receiving route](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391),
starting at `6a7b164a1806659ae0f166f1589d367b289299ba`. The canonical controller
retains integration, native qualification and main publication custody. The
[coordination record](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391#issuecomment-6280560344)
identifies this separate row-identity finding. No whole-issue acceptance is claimed.

## Defect and resulting behavior

The accepted [catalog search boundary](catalog-search-identity.md) preserves exact
UTF-8 item/version pins. The frozen CatalogItem version field accepts a nonempty
string, so `release.caf\u{00e9}` and `release.cafe\u{0301}` are distinct admitted
version spellings. Swift String equality considers those strings canonically
equivalent. The browser's synthesized row-ID equality and hash therefore collapsed
the two versions even after the real index retained them correctly.

The browser checks that every combined page has distinct row IDs. With both
versions in a first page it could report unavailable instead of publishing the
valid results. With one version per page it could retain the first row and reject
the next page as a duplicate. The same ID type is used for SwiftUI row identity.
The unchanged bundled preview currently has one version per kind; this defect
concerns the public indexed browser boundary, not an observed failure in that
one-version fixture.

`CatalogBrowserRow.ID` now compares each original UTF-8 sequence and hashes the
two byte arrays separately, consistent with the accepted exact-pin approach.
An exact reconstructed pin retains equal identity and dictionary lookup. A changed
display title or snapshot does not redefine the existing item/version row ID.
The row's full value still retains the complete entry and snapshot.

Search normalization, display sort order, kind filters, pagination guards, cursor
generation, retries, request cancellation, preference storage and source validation
are unchanged. No contract field, version policy, compatibility conclusion, price,
catalog authority, user default or build selection is added.

## Required native regressions

All eight preceding `CatalogBrowserModelTests` methods and their helper bodies
remain exact. Three appended methods require:

| Method | Required behavior |
| --- | --- |
| `testExactVersionRowIDsKeepEquivalentSpellingsSeparateAndExactCopiesEqual` | Both original version byte sequences remain separate in equality, a Set and a dictionary; an independently reconstructed exact pin retrieves its own value. |
| `testExactVersionRowsRemainDistinctInOneFilteredPage` | The real index and browser publish both versions with the correct count under combined query/kind filters in both display sorts; an idempotently reordered release preserves the results. |
| `testExactVersionPaginationFailureRetryKeepsBothPinsCountsAndOrder` | A failed second page preserves the first row, total, filters, pin and retry cursor; retry after an idempotently reordered install publishes both exact versions in the original order. |

The model cases await each actual request and use the existing controlled source;
they do not sleep, change production deadlines, alter app storage or fabricate a
successful network result. Both full-page and single-row pagination cases exercise
the actual `CatalogSearchIndex` actor. Actual SwiftUI model compilation and native
execution of these three methods remain required on the proposed source.

The new `catalog-row-identity-ui` receipt profile inherits every one of the prior
228 identities and adds these three: **231 UI methods**, or **752 package
declarations** across Core151 / Data69 / Transfer209 / Catalog92 / UI231. The
native simulator and submission SDK jobs select this exact profile. All historical
profiles, the fail-closed parser, seven App journeys, six Evidence methods and
every other native command remain unchanged. Counts are required inventories,
not execution results.

## Bounded local causal proof

A real Swift 6.2.4 Linux execution in Swift 6 language mode compiled the exact
`CatalogBrowserRow` and `ArtifactIdentity` declarations plus the complete unchanged
`CatalogSearchIndex.swift`. These original declarations were extracted without
editing their contents into an isolated compilation; no SwiftUI stub or replacement
index was used. The same 5,624-byte control body, SHA-256
`04f751888e91c462d72d9fd999e6fecc4a960ad4151cf2af7c2ce49da7a90cbf`, ran before
and after the correction. Both compilations succeeded without diagnostic output,
and each run preserved all of its input source hashes.

| Exact value/index observation | Original row ID | Corrected row ID |
| --- | ---: | ---: |
| Control checks passed / failed | 13 / 8 | 21 / 0 |
| Actual index first-page / second-page entries, in each sort | 1 / 1 | 1 / 1 |
| Actual index total and combined row count, in each sort | 2 / 2 | 2 / 2 |
| Distinct combined row IDs, in each sort | 1 | 2 |
| Full filtered page entries / distinct IDs, in each sort | 2 / 1 | 2 / 2 |
| Original child process exit | 1 | 0 |

The original failed output is 4,252 bytes, SHA-256
`3304a73c9f524decf4ac590b0bf7342c744993c4ee4dc921afe83192e6c4fd47`.
The corrected output is 3,770 bytes, SHA-256
`d7bfaee212745b245a3165c597d847bdcfaf35531d49a689b75816d435e5edb2`.
This proves the exact value/index identity defect and duplicate predicate on real
returned pages. It does not execute `CatalogBrowserModel`, its failed-page retry,
the complete PlannerUI module, SwiftUI rendering or a native application.

The existing portable inventory control first rejected the three unregistered
source methods: 16 of 17 methods passed and the exact source-inventory method
failed. After registering the new profile, all **17 Python receipt controls**
passed in 1.263 seconds on the final source, with no failures, errors or skips. They require every
current class-qualified declaration, reject each same-count substitution and
reject an old 228-method receipt padded to 231. The original failed log is 4,361
bytes / SHA-256 `fe68482f837ccc870a4b802c2a62e46aa96357306063f9f6342b0ff39998e8b1`;
the passing log is 3,370 bytes /
`eb9888318570575b1c233e50df753691d2135d6cb5cf647a35f7d91c0906df64`.
These parser controls use explicitly synthetic XCTest text and do not establish
Swift execution.

On the pinned Apple host, the existing workflows run the complete model suite
and qualify the resulting original log with:

```sh
set -o pipefail
swift test --package-path Packages/PlannerUI 2>&1 | tee model-tests.txt
python3 tools/ci/require_swift_test_results.py catalog-row-identity-ui model-tests.txt
```

The actual current-source native results and receiving review must retain their
own identities. Earlier #391 results, syntax parsing, these local value controls,
and source inclusion do not establish the new native model result, accessible
navigation, service failure/recovery, explicit selection, physical-device evidence
or complete #59 acceptance.
