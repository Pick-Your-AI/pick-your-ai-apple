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
