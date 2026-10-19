# #101: Privacy source inventory and release reconciliation

This record advances [Apple #101](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/101)
with a package manifest and source inventory. It is partial implementation;
the release-binary, measured-network, disclosure and receiving gates remain open.
The accepted [accounts and analytics decision](../decisions/issue-24-accounts.md)
selects guest local planning, with accounts, advertising/tracking SDKs, optional
analytics and remote diagnostics uploads disabled. The accepted [local draft
threat model](../security/local-draft-threat-model.md) records sensitive local
content, retention and recovery boundaries.

## Inspected source identity

The inventory was inspected on 2026-10-18 against accepted main
`8ca109963bfca3a707b1af8b80aabcd9dd28fd8a` and the three cache paths delivered by
the signed [#242 source](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/242)
`b915a9e6c34ee0174142e9fa834febfc41a085b7`. Their conflict-free composition is
tree `23a6ab47e6a1424e60e5c7c0fc11bc370b06dfaf`. The manifest and regression are
the additional source changes described below. This identity is a source
inspection boundary; it is not an archived or submitted application identity.

| Component | Source-observed behavior | Privacy reconciliation boundary |
| --- | --- | --- |
| [App entry](../../App/PlannerApp.swift) and [project definition](../../App/Planner.xcodeproj/project.pbxproj) | Links the local PlannerUI and PlannerData products; creates local draft storage inside Application Support with protection until first unlock | Catalog is not yet linked by this inspected app. Verify the final integrated dependency graph and actual packaged resources before release |
| [PlannerUI](../../Packages/PlannerUI/Package.swift) | SwiftUI with local PlannerData dependency; local scene selection uses `SceneStorage` | Framework-managed storage does not prove a direct UserDefaults call by app code. Audit the final build and required API report before choosing additional reasons |
| [PlannerData](../../Packages/PlannerData/Package.swift) | Local data package and system SQLite module; persists drafts and history | Review local retention/export/deletion disclosures and actual application behavior using the threat-model evidence |
| [PlannerCore](../../Packages/PlannerCore/Package.swift) and [PlannerTransfer](../../Packages/PlannerTransfer/Package.swift) | Local computation and frozen contract resources; Transfer's tests use local Data while its library target declares no target dependency | No external binary SDK dependency is declared in these inspected package manifests; rescan the exact release dependency graph |
| [PlannerCatalog](../../Packages/PlannerCatalog/Package.swift) | Local cache/search package; Foundation, CryptoKit and system file APIs; optional public artifact transport | This package supplies its file-metadata reason as an explicit SwiftPM resource; native package and final app-bundle verification have different scopes |
| [PublicArtifactClient](../../Packages/PlannerCatalog/Sources/PlannerCatalog/PublicArtifactClient.swift) | Configured exact-origin HTTPS GET with an ephemeral credential/cookie/cache-free session, bounded streaming and rejected redirects; no endpoint is hard-coded and construction sends no request | A source inspection and synthetic URLProtocol tests do not measure a configured release binary's requests. Record actual destinations and payloads before disclosure reconciliation |

All five package manifests were inspected for local, remote and binary target
dependencies. None declares a remote package or external binary target at this
source boundary. Apple frameworks and system SQLite are recorded as system
dependencies, not presented as independently inventoried third-party SDK bundles.
This finding does not assert that future integration or the final archive contains
no additional SDKs.

## Required-reason API and resource

The bounded [cache reader](../../Packages/PlannerCatalog/Sources/PlannerCatalog/CatalogCache.swift)
uses `fstat` on its one opened descriptor to reject non-regular objects before
bounded reads. It reads the file's type locally; it does not send the resulting
metadata in network requests. Apple's current required-reason list explicitly
includes `fstat` in `NSPrivacyAccessedAPICategoryFileTimestamp`. The applicable
`C617.1` purpose is metadata access within the app's own container. The cache
caller must continue using that app-controlled location. A later document-picker
or external-path feature needs its own purpose review.

[PrivacyInfo.xcprivacy](../../Packages/PlannerCatalog/Sources/PlannerCatalog/PrivacyInfo.xcprivacy)
declares exactly that category and reason. It contains no app-wide collection or
tracking determination. [Package.swift](../../Packages/PlannerCatalog/Package.swift)
explicitly processes the file into the target resource bundle, as required for a
Swift package privacy manifest. The new [resource regression](../../Packages/PlannerCatalog/Tests/PlannerCatalogTests/PrivacyManifestTests.swift)
loads the built bundle through `Bundle.module`, parses the property list and
checks the exact declared reason. Reading only the source file would miss a
packaging omission, so the test resolves the actual packaged resource.

Primary Apple documentation checked 2026-10-18:

- [Required-reason categories and API list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype): `fstat`, the file-timestamp category and the `C617.1` app-container purpose.
- [Adding a privacy manifest to an app or SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk): privacy manifests in Swift packages must be explicitly declared resources.
- [Bundling resources with a Swift package](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package): target resources and `Bundle.module` lookup.

## Verification and remaining acceptance

Run from `Packages/PlannerCatalog`:

```sh
swift test
xcodebuild -scheme PlannerCatalog -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/planner-catalog-privacy-derived CODE_SIGNING_ALLOWED=NO build
```

The catalog workflow already runs the whole package suite and unsigned iOS
Simulator compilation. The manifest regression must pass on the exact final
candidate along with the existing native cache and transport cases. A Linux
resource test can verify SwiftPM packaging, but cannot establish CryptoKit,
Apple URLSession or iOS archive behavior. Record actual test counts, skipped
cases, toolchain, head/tree and logs in the delivery PR; do not infer results from
test source or reuse another tree's receipt as this change's execution.

| #101 acceptance | This deliverable | Evidence still required |
| --- | --- | --- |
| Disclosures match measured app and SDK behavior | Pinned source inventory; exact catalog file-metadata purpose and packaged manifest regression | Final app/SDK inventory, built manifests and actual network measurements reconciled with consent and disclosures |
| Unlisted collection or unjustified required API prevents release | Known direct `fstat` use has a scoped reason; disabled analytics/tracking decision remains explicit | Inspect the exact release archive and privacy report, exercise supported journeys and denied/revoked consent where applicable, and resolve every unexplained API or request before submission |
| Linked SDK/manifest inventory and reviewed reconciliation | This record links inspected packages, source behavior, manifest and primary API rules | Exact-version independent receiving review plus dated release evidence, app metadata/privacy answers and a working in-app/public privacy-policy location |

The release reconciliation must pin the app version/build, source commit, archive
identity, SDK/toolchain, device/OS and dependency versions. Enumerate the actual
bundled privacy manifests and required API findings, then compare observed
destinations and payload categories with purposes, retention, local storage and
any enabled consent/revocation behavior. Retain sanitized evidence and unresolved
findings in the release PR; do not commit personal payloads or device secrets.
The in-app privacy link and App Store disclosures must refer to the actual chosen
policy and shipped behavior. No policy endpoint, privacy answer, consent result,
device trace, release archive or store approval is invented by this package work.
