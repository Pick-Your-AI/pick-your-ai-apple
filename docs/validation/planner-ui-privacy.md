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
corrections. The running `5af50d4e` candidate remains unchanged by this separate
local preparation.

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

The eleven filesystem regression methods use temporary synthetic product folders
containing the actual reviewed source bytes. They exercise missing/swapped/extra
manifests, source-pin changes, links, FIFOs, byte/traversal bounds, stale evidence,
publication failure, actual CLI loop/missing-app retries and recovery. They do
not build or execute an Apple app.
The inventory also does not inspect Mach-O API use, measure requests, enumerate
system-framework behavior, determine collection/tracking answers, reconcile
consent or certify an archive/submission. Those remaining #101 gates still apply.

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
