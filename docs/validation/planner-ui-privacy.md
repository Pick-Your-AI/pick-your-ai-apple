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

## Remaining integration and acceptance

This follow-up leaves the independently reviewed PlannerCatalog file-metadata
manifest in [PR #284](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/284)
with its canonical owner and exact evidence. Its historical package inventory
does not establish the integrated app's inventory. Both resource contributions
must be preserved in their receiving composition and inspected in the resulting
app/archive privacy report.

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
