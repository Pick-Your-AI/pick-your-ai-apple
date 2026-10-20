# Exact catalog selection identity in browser rows and details

## Current preserving receipt

The [current receiving composition](receiving-main7f-row-cost.md) retains this
complete donor at `70c45be7` and accepted main `7f16020b`. All three corrected
production files, both native test files, seven added method bodies and the
235-method UI profile remain exact donor bytes. The later main contribution adds
seventeen Transfer methods, requiring 226 Transfer / 773 package declarations and
48 portable inputs. The 756-declaration donor observations below remain attached
to their original source. No new row/details native result is inferred.

This bounded correction follows [Apple #59](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/59)
on the existing [#391 receiving route](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391),
starting at `6a7b164a1806659ae0f166f1589d367b289299ba`. The canonical controller
retains integration, native qualification and main publication custody. The
[coordination record](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391#issuecomment-6280560344)
identifies the separate row-identity finding. The controller's subsequent
[details-boundary review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391#issuecomment-6280825187)
keeps the coherent correction on this same donor. No whole-issue acceptance is claimed.

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

The details sheet has a separate complete identity because it owns a StateObject
for the selected row and catalog release. Its prior array of Strings also collapsed
canonically equivalent spellings. `CatalogDetailsIdentity` now stores all eight
original parts as separate UTF-8 byte arrays: item ID, version, kind, title, schema
version, catalog ID, revision text and capture date. Exact copies compare and hash
equally; no part or field boundary is dropped.

Before publishing a details response, the model now compares its complete
ID/version/kind/name projection with the selected `CatalogSearchEntry`, using that
existing type's exact UTF-8 equality. A different admitted Unicode version or name
therefore leaves details unavailable until an exact retry succeeds. The bundled
resolver likewise uses exact item/version lookup and complete entry equality while
retaining its unique-match, catalog-pin and fixed-fixture boundaries. All 29 items
in the unchanged SHA-qualified preview have ASCII names and versions; synthetic
Unicode resolver controls do not make arbitrary snapshots an application input.

Search normalization, display sort order, kind filters, pagination guards, cursor
generation, retries, request cancellation, preference storage, canonical decoding
and fixture qualification are unchanged. No contract field, version policy, compatibility conclusion, price,
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

The eight preceding `CatalogDetailsModelTests` methods and helpers also remain
exact. Four appended methods require:

| Method | Required behavior |
| --- | --- |
| `testSheetIdentityUsesExactBytesForEveryStoredSelectionPart` | Every string part remains distinct under canonical-equivalent byte changes; revision and field boundaries remain significant; exact copies retrieve their own dictionary value. These identity-value controls do not claim schema validity for fabricated kind or catalog fields. |
| `testEquivalentUnicodeVersionResponseIsRejectedBeforeExactPinRetry` | The unchanged decoder admits both version spellings; the mismatched response stays invisible; retry admits only the exact selected version and preserves the request pin. |
| `testEquivalentUnicodeNameResponseIsRejectedAndClosedRetryStaysRetired` | A differently spelled validated name stays invisible; a closed model cannot retry; a fresh model admits the exact selected name. |
| `testResolvedItemIDAndKindMustMatchBeforeAnyDetailsArePublished` | ID and kind mismatches still fail before result publication, retaining the selected row and its one original request. |

The frozen row-only checkpoint `3ac62f0073d5775f16491d92c9681ac17d4ec14b`
retains the `catalog-row-identity-ui` profile: all 228 earlier identities plus three,
or **231 UI methods / 752 package declarations**. Its observations below remain
attributed to that source. The coherent follow-up's `catalog-selection-identity-ui`
profile inherits all 231 and adds the four details methods: **235 UI methods**, or
**756 package declarations** across Core151 / Data69 / Transfer209 / Catalog92 /
UI235. The native simulator and submission SDK jobs select this current profile. All historical
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
passed in 1.263 seconds on the frozen row-only source, with no failures, errors or skips. They require every
class-qualified declaration at that checkpoint, reject each same-count substitution and
reject an old 228-method receipt padded to 231. The original failed log is 4,361
bytes / SHA-256 `fe68482f837ccc870a4b802c2a62e46aa96357306063f9f6342b0ff39998e8b1`;
the passing log is 3,370 bytes /
`eb9888318570575b1c233e50df753691d2135d6cb5cf647a35f7d91c0906df64`.
These parser controls use explicitly synthetic XCTest text and do not establish
Swift execution. The expanded profile retains that historical mapping and also
rejects a 231-method result padded to the new 235-method inventory.

On the expanded source, all 17 portable controls passed in 1.108 seconds with
zero failures, errors or skips; their 47 direct source inputs remained unchanged.
The 3,370-byte original log has SHA-256
`f381dbc13b74528e326342ad196b3669ba3001ecd7da2162d0a2ce6943187d69`.
Syntax-only parsing of all five complete changed Swift files also succeeded with
no diagnostics. Neither result qualifies a SwiftUI model or native journey run.

## Separate details admission causal proof

A second unchanged 10,144-byte control body, SHA-256
`3c6717a4279626cb485fb695c775708cc415bafc753eeba0cfb33fefabee9176`,
ran on real Swift 6.2.4 Linux in Swift 6 language mode before and after the details
correction. It compiled the exact row, entry, artifact, pinned-details and sheet
identity declarations with six complete unchanged Transfer source files and their
actual frozen schema resources. Both standard SwiftPM builds succeeded. The
model and resolver admission prefixes were extracted verbatim from the original
source and projected to Boolean results; the control did not replace their
comparisons with a handwritten equivalent.

| Actual value / admission-expression observation | Original details source | Corrected details source |
| --- | ---: | ---: |
| Control checks passed / failed | 26 / 29 | 55 / 0 |
| Model predicate rejects byte-distinct equivalent version and name responses | 0 of 2 | 2 of 2 |
| Resolver predicate rejects byte-distinct equivalent version and name rows | 0 of 2 | 2 of 2 |
| Resolver predicate selects each exact version from two distinct records | 0 of 2 | 2 of 2 |
| Sheet string parts keep separate equality, Set membership and dictionary values | 0 of 7 | 7 of 7 |
| Original child process exit | 1 | 0 |

The actual decoder admitted every version/name specimen before the predicates ran.
Positive exact-copy controls, all 29 original fixture rows, ordinary ID/kind/name
rejections, duplicate exact-record rejection, catalog revision and invalid hash
shape controls passed in both runs. Every recorded input hash remained unchanged.
The original failed output is 8,213 bytes, SHA-256
`2c023fb5692f06754afa57e8749519bfe3add240a70f6b42d2d2a4c9b5d5c698`;
the passing output is 6,521 bytes, SHA-256
`b5b93d409834f9ba6f92afce1d7631c799f137f045aff827340d774b4100659b`.

These are 55 control assertions, not 55 XCTest methods. They do not execute the
complete `CatalogDetailsModel`, its asynchronous lifecycle, a StateObject or native
rendering. The resolver expression receives synthetic structurally validated
snapshots in the isolated control; production still accepts only its original
fixed SHA-qualified fixture. The supplied 64-character test hash establishes only
the model's existing hash-shape condition. No fixture byte-qualification or source
authority is inferred from that controlled response. The four appended native
methods remain required to execute the actual model, retry and retirement paths.

On the pinned Apple host, the existing workflows run the complete model suite
and qualify the resulting original log with:

```sh
set -o pipefail
swift test --package-path Packages/PlannerUI 2>&1 | tee model-tests.txt
python3 tools/ci/require_swift_test_results.py catalog-selection-identity-ui model-tests.txt
```

The actual current-source native results and receiving review must retain their
own identities. Earlier #391 results, syntax parsing, these local value controls,
and source inclusion do not establish the new native model result, accessible
navigation, service failure/recovery, explicit selection, physical-device evidence
or complete #59 acceptance.
