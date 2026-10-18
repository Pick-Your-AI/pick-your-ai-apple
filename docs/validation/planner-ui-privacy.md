# PlannerUI preference privacy declaration

This is a bounded source and package-resource contribution to
[Apple #101](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/101).
The inspected input is the editor/catalog integration at
[`a113480a595ceb89727a7718fd6ee4d92ecc239a`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/a113480a595ceb89727a7718fd6ee4d92ecc239a).
Its existing native run and historical receipts retain that source identity.

The current receiving preparation carries that unchanged privacy source onto
[`5af50d4eadac56a19a46191e6b5d82e056441349`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/5af50d4eadac56a19a46191e6b5d82e056441349),
the independently source-reviewed editor/catalog correction with accepted
ResourceEstimate input from signed main
[`51952c75f2280d57891491903e495fb822b83bfd`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/51952c75f2280d57891491903e495fb822b83bfd).
It preserves both narrow catalog hit-target/source-action corrections, every
existing model and journey assertion, and the complete 65-case Transfer profile
with 29 required identities. The 110-case model pass and two catalog journey
failures recorded for `a113480a` remain historical evidence in the
[catalog/editor receiving record](catalog-editor-receiving.md). They do not
establish execution of this 111-case privacy composition or the current UI
corrections. The completed `5af50d4e` result also retains its own identity: all
110 models and both iPad journeys passed, while the iPhone Catalog journey
failed during detail-row scrolling. The next canonical receiving composition
combines this privacy work with the separately reviewed bounded reveal helper;
that correction still requires both complete native journeys.

The receiving composition also preserves the five accepted Catalog privacy
files from signed main
[`bcf4c771641e62b30812e67bff86cf6b221c92cb`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/bcf4c771641e62b30812e67bff86cf6b221c92cb),
the normal delivery of [PR #284](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/284).
Those complete blobs are unchanged. Each package keeps its own production
resource bundle and exact required-reason regression; the UI 111/62 and Transfer
65/29 execution profiles remain unchanged. The composed Catalog source declares
45 tests. Earlier 44-case Catalog and 332-case submission-SDK receipts for
`5af50d4e` retain their own tree and do not establish this later composition's
execution.

The same receiving composition preserves signed main
[`9c744450d689690f66ab6a28aa146a1318917464`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/9c744450d689690f66ab6a28aa146a1318917464),
which rejects a corrupt future history revision before publishing a restored
head. Its regression joins the existing prepared-duplicate and interrupted-
migration cases, raising the declared Data inventory to 29. The five current
package inventories are 85 Core, 29 Data, 65 Transfer, 45 Catalog and 111 UI,
or 335 cases. These counts, both built-product manifest inventories and the
full journeys remain fresh execution gates; the prior 332-case SDK run does
not qualify this union.

## API use and reason

The app opens [`CatalogBrowserView`](../../Packages/PlannerUI/Sources/PlannerUI/CatalogBrowserView.swift)
with `CatalogFilterPreferences()`.
[`CatalogFilterPreferences`](../../Packages/PlannerUI/Sources/PlannerUI/CatalogBrowserModel.swift)
reads and writes a versioned envelope under `catalogBrowserFilters.v1` in
`UserDefaults.standard`. The envelope stores the literal search query, selected
kinds and sort order. It does not contain the draft, item selections, credentials
or continuation tokens. Existing validation bounds the query, kinds and encoded
preference data; this change preserves those reads, writes and limits.

Apple's [required-reason API reference][reasons], checked on 2026-10-18,
lists `UserDefaults` in `NSPrivacyAccessedAPICategoryUserDefaults`.
`CA92.1` covers preferences accessible only to this app. It does not authorize
reading another app's or the system's information, or sharing writes with other
apps. The injectable defaults instance remains limited to an app-owned domain;
the existing tests use isolated synthetic suites. Any future App Group, managed
configuration or cross-app access needs its own purpose and declaration review.

## Production resource and regression

[`PrivacyInfo.xcprivacy`](../../Packages/PlannerUI/Sources/PlannerUI/PrivacyInfo.xcprivacy)
declares that one category and reason. The
[`PlannerUI` target](../../Packages/PlannerUI/Package.swift) explicitly processes
the manifest alongside its existing resources, following Apple's
[privacy-manifest packaging guidance][packaging] and
[Swift package resource guidance][resources].

[`PlannerUIPrivacyManifestTests`](../../Packages/PlannerUI/Tests/PlannerUITests/PlannerUIPrivacyManifestTests.swift)
reads the built production bundle through the same internal bundle accessor used
by the existing catalog fixture loader. The test target has a separate `Fixtures`
bundle; its own `Bundle.module` cannot substitute for the production resource.
The regression requires a readable plist with exactly the intended category,
reason and declaration keys. The existing catalog loader still validates its
same immutable fixture hash, size bounds and snapshot identity.

The native workflow selects `comparison-catalog-source-privacy-ui` in the
[executed-result guard](../../tools/ci/require_swift_test_results.py):
111 distinct passing XCTest cases, including 62 required identities across
eight classes. The earlier 110-case profile and all other profiles remain
available for their own evidence. Parser regressions reject an older profile
padded to 111 cases or the required method reported under a different class.
These are declared source inventories until the native job actually executes.
Both complete pinned iPhone/iPad journeys, other package gates and the additive
submission-SDK lane remain required.

## Built-app inventory

Package resource tests and a built app have distinct boundaries. The submission
SDK workflow runs [`privacy_inventory.py`](../../App/scripts/privacy_inventory.py)
against each existing unsigned Release device and simulator product, after the
separate SDK/product-metadata verification. It requires the exact reviewed
manifest bytes inside both `PlannerCatalog_PlannerCatalog.bundle` and
`PlannerUI_PlannerUI.bundle`, and rejects missing, moved, additional or changed
manifests. The source files themselves must still match their reviewed SHA-256
pins. A reviewed declaration or packaging change must update this explicit
inventory; a source-only file cannot satisfy the product check.

The selected locations follow this project's package/target names and the pinned
build layout. The original [Catalog resource build](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39135044975/job/117697798609)
records `CpResource`/`builtin-copy` into the named Catalog bundle. The original
[`5af50d4e` SDK build](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39144793921/job/117726675535)
records the named UI bundle copied into each app. These are separate historical
observations; the complete new two-manifest app composition still requires its
actual device and simulator product runs. No alternate location or transformed
manifest bytes are silently accepted.

The inspector opens directories and files without following links, reads only
the two expected bounded manifest files, limits traversal, and rejects special
entries. Its JSON records each product-relative location, exact digest, byte
count and reviewed category/reason. The archive retains `device-privacy.json`
and `simulator-privacy.json` beside the actual checkout/tree and SDK/product
receipts. A failed retry removes its previous regular-file success receipt;
successful publication replaces a temporary sibling atomically. It does not
alter the inspected app, and rejects a symlink supplied as the receipt file.
App-path link loops are normalized after checking the output's independent
safety, so their failure cannot retain an older success receipt. Both the
`RuntimeError` and `ELOOP` forms are covered, while product-contained and linked
receipt targets remain preserved and rejected.

The thirteen filesystem regression methods use temporary synthetic product folders
containing the actual reviewed source bytes. They exercise missing/swapped/extra
manifests, source-pin changes, links, FIFOs, byte/traversal bounds, stale evidence,
publication failure, actual CLI loop/missing-app retries, ancestor aliases and
recovery. They do not build or execute an Apple app.
The inventory also does not inspect Mach-O API use, measure requests, enumerate
system-framework behavior, determine collection/tracking answers, reconcile
consent or certify an archive/submission. Those remaining #101 gates still apply.

### Observed ancestor-alias preservation failure

The original [submission-SDK job 117751884950](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39153511912/job/117751884950)
for source `2eb2093ca861cdb9a8ea11bebbfe83b422311a7f`, prepared checkout
`bbc5e8296525c60d55eea5a342fa59ea18f5e46d` / tree
`d51cb8084145ae4122e7fc9fdac3462d07c10458`, failed before selecting the SDK or
executing any Swift package/build step. On macOS with Python 3.14.7, its complete
48-method portable suite had one error: the final retained-file assertion in
`test_product_or_linked_evidence_destinations_are_preserved_and_rejected`
reported `FileNotFoundError`. The protected synthetic outside receipt had been
removed. The complete decoded job log is 27,465 UTF-8 bytes, SHA-256
`4219aa2d589a26517af4e48a687869b8a125e107dde3f704508ce6bdcea0dd0c`.
The earlier successful Linux scope run and prior 11/48-method local receipts do
not erase this actual failure or establish SDK/built-product acceptance.

The endpoint-only check compared lexical and fully resolved app/output paths.
With an ancestor directory alias, the supplied output can enter the actual app
and then follow its `escape` link to an outside file; neither endpoint retains
the intervening product identity. This was reproduced on Linux with real
directory symlinks, using both a canonical selected app and an app alias. The
unchanged original failing test also reproduced its same final assertion error
when its temporary parent was supplied through a real directory alias. No
`Path.resolve` mock or macOS execution is claimed for these local replays.

The correction adds the resolved identities of each supplied output parent to
the existing containment check, before any receipt removal. It keeps final-file
link rejection, lexical and resolved containment, stale-success invalidation,
app-loop handling and atomic publication intact. The complete original eleven
test methods remain unchanged. Two additional methods use the actual CLI:
unsafe traversal must preserve both existing and absent receipts for canonical
and aliased app inputs, while a genuinely outside output under an ancestor
alias must still publish, invalidate after a failed app read, and recover.

At test-only tree `17160d9e5f4995d98dd152b88e8642e115d1083f`, unchanged production
fails all four new unsafe-path subcases, including both actual receipt-deletion
assertions; the twelve other methods pass. At corrected source/test tree
`432fc00274d17a9aa7f696efad711c09891e04cb`, all 13 privacy methods pass in
0.505 seconds and all 50 App script methods pass in 0.678 seconds, with zero
failures or skips. The unchanged original method also passes under the same
aliased temporary-parent replay. This receiving documentation is the only later
change to those executed source/test bytes. These are Python 3.12 Linux
filesystem and runner controls. Fresh macOS guards, all 335 current package
cases, both unsigned products and both exact built-product manifest inventories
remain required; this correction changes no Swift, journey, workflow or native
acceptance assertion.

## Prospective combined Graph/editor receiving inventory

The 335-case source inventory and 13/50-method Linux correction receipts above
belong to the editor/privacy preparation, including canonical checkpoint
`6091b05306ab89a2f9831da6a51d20d32653ede0`. They do not describe execution of a
later Graph/editor receiving union. A composition with Graph source
`81ca8804151a1c592d00211cf03d110bf2bd9a7a` preserves those complete Swift test
sources and adds eight exact-decimal formatter methods and six dependency-graph
methods. Its declared package inventory is **93 Core, 29 Data, 71 Transfer,
45 Catalog and 111 UI: 349 distinct source identities**.

The additive `graph-resource-quality-catalog-editor-transfer` result profile
requires exactly 71 passing Transfer identities, including all 29 previously
required identities and all six graph methods across six qualified classes.
The unchanged 65-case profile and prior 59-case Graph-only execution keep their
own source attribution. A padded older profile or an unrelated class cannot
supply the added graph evidence. These parser regressions use synthetic logs;
they establish no new Swift execution.

All 349 package cases, both complete Notes/Catalog journeys on the pinned iPhone
and iPad, both unsigned products, and both exact built-product manifest
inventories remain fresh receiving gates. The original `bbc5e829` privacy failure
and each earlier passing package result remain separately attributed. This
composition changes no model, journey assertion, manifest pin or store boundary.

## Receiving accepted placement, report, recovery and fixture checks

Accepted main `791c355812bfbbf8003941b59734118011d4734a` delivers the
placement/relationship conformance source from #286 after canonical Graph/editor
head `f4a35dadbe733e20d35e78f60c622c8c649ae3e2` was published. The latter's
signed prepared checkout `bee8391622a768f6451c58a68d57e52d88cec6c9` and its
349-case inventory retain their exact source attribution. Later accepted main
`1ff2907ad851737fd11f344734a84c487cd59c54` adds the typed report adapter
from #312, and `c23050050c9ce46f35aee73e2f80b7b638cba159` adds the WAL
admission and hot-journal recovery correction from #306. Accepted
`cd098e8e19f5e4a1d90112379bc8ca089d81ec93` adds the eight synthetic-fixture
admission methods from #275. This receiving
preparation preserves these accepted sources and adds four placement methods,
seven report-admission methods, five storage-recovery methods and eight fixture
methods to the complete Graph/editor suites. Its declared inventory is **100 Core,
34 Data, 83 Transfer, 45 Catalog and 111 UI: 373 distinct source identities**.

The additive `placement-graph-resource-quality-catalog-editor-transfer` profile
requires exactly 75 passing identities, including all 35 previously required
identities and all four class-qualified placement methods, for 39 required
identities across seven classes. Every earlier profile remains unchanged; padded
71-case evidence or another class cannot establish the four added cases.

The selected `fixture-placement-graph-resource-quality-catalog-editor-transfer`
profile extends that complete 75-case profile to exactly 83 passes, with all 47
required identities across eight classes. All eight accepted fixture methods are
required by their actual class identity. The complete fixture, hash pins and
test-only Core/Catalog dependencies remain exact accepted main. A skipped
CryptoKit-dependent method, a substituted class or a padded older profile cannot
satisfy the current receiving gate. This adds no production data or permission.

The reference verifier retains all thirteen frozen input hashes and the complete
build, item, snapshot, quality, resource and Graph replays. It appends the exact
accepted 98-case placement replay without changing any production decoder,
fixture, graph policy or assertion. Structural placement preservation does not
establish allocation, binding or executable compatibility semantics.

The storage workflow requires all 34 methods on each selected iPhone and iPad.
The original restoration and interrupted-migration witnesses, both prepared-copy
race witnesses, the actual process-termination replay and its seven Python guard
methods remain required. The storage source combines the accepted no-checkpoint
admission with the complete editor preparation operations; the typed report
adapter preserves its exact accepted source and all seven regression methods.

This is a separate source preparation, not a new native result or an update to
the running canonical head. Before receiving delivery, the actual composition
requires all applicable package checks, both complete Notes/Catalog journeys on
each pinned iPhone and iPad, both unsigned products and both built-product privacy
inventories. Earlier native and portable receipts retain their original source
and scope.

## Receiving correction for ancestry hidden inside link targets

The original `f4a35dadbe733e20d35e78f60c622c8c649ae3e2` SDK job successfully
executed its thirteen privacy tests and inspected both unsigned built products.
Those receipts do not cover a later reproduced output-path boundary: a supplied
parent link can target `Planner.app/escape` or `Planner.app/../outside` while
every supplied parent's resolved endpoint remains outside the selected app.
The actual original CLI returned failure after deleting an existing, freshly
created synthetic outside receipt in all three initial absolute, relative and
internal-`..` reproductions. No actual product or user file was used.

The receiving helper now retains each directory-link target and its ancestry,
including prefixes before an internal `..`, before allowing receipt removal.
Existing parent components must be directories, and `..` cannot discard a
missing directory prefix. Unresolvable output paths fail through the ordinary
CLI rejection boundary. Final-file link rejection, exact source pins, app
scanning, stale-success invalidation for valid outside outputs, atomic receipt
publication and the earlier app-loop retry behavior are unchanged.

Three additive actual-CLI methods cover absolute, relative, nested and internal
`..` link targets, canonical and aliased app selections, existing and absent
receipts, invalid prefixes and link loops. Safe outside aliases still create
missing tail directories, publish, remove stale success after a failed app
read, and recover on retry. Every test uses owned temporary synthetic inputs.
All thirteen earlier method bodies remain exact. Against the unchanged helper,
the new negative methods produced 24 hidden-target and two missing-prefix
failures; the safe-alias method passed. With this correction, all sixteen
privacy methods pass in normal and optimized Python 3.12.14, and the complete
App script suite passes all 59 methods with no failures or skips.

This three-file continuation is applied to the independently reviewed
`faede0f32449aedcff3383c8bc1ae3515e5cf712` receiving tree. Its 373 Swift source
identities, every production Swift file, the exact privacy-manifest bytes,
all frozen inputs and all native workflows/profiles remain unchanged. These
portable results are additional source evidence; the new privacy helper still
requires the actual receiving SDK and UI built-product gates before main
delivery. The running f4 source and its original native receipts retain their
own identity.

## Receiving filesystem-identity and temporary-alias correction

An additional source review follows the separate SDK receipt correction in
[#313](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/313).
Its filesystem-identity source `2cef1096da823656d718aea43c76652c60de6be6`
retains the preceding target-ancestry correction `95c79b4477ea810ebc0467b1e4f688f199196049`;
the selected successor `f319f4b847ca119e2d488d8e91a342f10db18bbb` normalizes
only the expected temporary parent in its safe-output assertion. Those source
reviews and SDK executions are separate from this privacy continuation.

[Apple volumes can treat different letter cases as the same entry](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/Articles/RaceConditions.html).
The privacy helper now compares the selected product's existing device/inode
identities with each retained output location before removing an earlier receipt,
using the same identity relation documented for
[Python file comparisons](https://docs.python.org/3.12/library/os.path.html#os.path.samestat).
The candidate lookup uses `lstat`; lexical checks still cover missing paths and
the final-file link rejection remains intact. An unsafe physical product alias
preserves the receipt even when a later directory link escapes to an outside file.
Valid outside aliases retain publication, stale-success invalidation and recovery.
The earlier selected-app loop handling is preserved when no product identity can
be resolved. This remains stable-path validation.

The two-route causal fixture models one directory's observed `lstat` identity
while using real directory traversal, links and owned receipt files. Against the
unchanged preceding helper, both direct and hidden aliases deleted their synthetic
outside receipt. The corrected helper preserves both. This controlled identity
fixture is not a native case-insensitive filesystem result. A second actual-CLI
method observes the real temporary filesystem: it rejects direct and hidden
case aliases when supported, or accepts a truly distinct differently cased
directory. The Linux execution exercised the distinct-directory branch; the
case-insensitive branch requires the actual receiving macOS run.

The existing six-route safe-alias test also failed all six destination comparisons
when its temporary root was supplied through a real directory symlink, after
the CLI and JSON checks had succeeded. Resolving the expected parent before
appending the unchanged final filename fixes that assertion and preserves exact
destination equality. The same actual six-route replay then passed, including
receipt invalidation and recovery. No `Path.resolve` or receipt-unlink mock is
used in that replay.

All sixteen preceding privacy method identities remain: fifteen bodies are
unchanged and the safe-alias method changes only that one expected-parent
expression. Two methods are added. Actual Python 3.12.14 execution passes all
**61 App script methods** and all **18 privacy methods** under optimized Python,
with zero failures or skips. The controlled two-route and actual six-route
replays also pass. Original failed logs remain retained separately.

This three-file layer extends immutable receiving preparation
[`986ac82a13edd7bc6541082c1a62c59eba57a6c3`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/986ac82a13edd7bc6541082c1a62c59eba57a6c3),
tree `d432f15cf7b9afaa7c2bf8fdd269b75835dc0528`. Its complete 373-method Swift
inventory, manifest bytes, frozen inputs and native workflows/profiles remain
unchanged. The new helper and filesystem-conditioned branch require their own
configured native receiving results and both built-product privacy inventories.
Original f4 and separate SDK results establish no execution of this new source.

## Remaining integration and acceptance

This composition retains the independently reviewed and delivered PlannerCatalog
file-metadata manifest alongside the PlannerUI preference declaration. The
[Catalog source inventory](issue-101-privacy.md) keeps its historical inspection
boundary and does not establish the integrated app's inventory. Both production
resource bundles must be inspected in the resulting app/archive privacy report.

No Swift compilation, built-resource execution, simulator result or release
privacy report is claimed for this new source by this document. Package source
declarations do not establish measured release-binary network/SDK behavior,
consent or policy accuracy, App Store answers, physical-device acceptance or
release approval. Those comparisons and their receiving review remain under
#101 and its existing prerequisites. This change introduces no SDK, analytics,
tracking, endpoint or new preference behavior and closes no whole issue.

[reasons]: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
[packaging]: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
[resources]: https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
