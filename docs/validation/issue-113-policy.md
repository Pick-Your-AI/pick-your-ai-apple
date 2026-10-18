# #113: Apple policy applicability and evidence matrix

Reviewed on **2026-10-18** against the official Apple sources linked below and
Apple main `adbc67c65de14ede660f64acedfb381afb955697`. This is an engineering
applicability assessment under the user's delegated implementation authority.
Independent receiving review and the actual signed-build/channel checks remain
separate. No App Store Connect account, submission, approval or release was
accessed or asserted during this review.

The accepted [platform decision](../decisions/issue-22-platform.md) selects
iPhone and iPad with an iOS/iPadOS 17 deployment minimum. The accepted
[account and commerce decision](../decisions/issue-24-accounts.md) selects
guest-first local planning, import/export and local forks; accounts, tracking,
optional analytics, purchases and subscriptions stay disabled. Remote guest
sharing remains a core target requiring the canonical service handoff in
[#23](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/23), not a service
that this assessment assumes exists. The first qualified real-data tuple and
release markets remain unresolved in [#21](../decisions/issue-21-scope.md).

## Observed release-toolchain gap and implementation response

Apple's [SDK upload requirement][sdk] has applied since **2026-04-28**: App Store
Connect uploads require Xcode 26 or later and the applicable version-26 SDK or
later. The established [development pin](../../App/toolchain.json) is Xcode
16.4 / 16F6; its [observed build receipt](toolchain-pin.md) uses SDK 18.5. Those
successful package/simulator checks do not establish compliance with the upload
SDK requirement. An iOS 26.2 **simulator runtime** does not change the SDK used
to compile an application.

The separate [unsigned submission-SDK compatibility lane](submission-sdk.md)
addresses this engineering gap with an explicit Xcode 26.3 / 17C529 and iOS 26.2
SDK selection. It preserves the existing development regression lanes and must
produce actual hosted execution before its build claims are accepted. The
reported [macOS 15 runner inventory][runner] identifies that installed toolchain;
the lane verifies the actual bundle and both SDKs instead of trusting the runner
label. It does not sign, archive for distribution, provision, upload or submit an
application.

Apple's separate [minimum deployment-target requirement][requirements] has
applied since **2026-09-09** and requires iOS/iPadOS 13 or later for uploads. The
selected deployment minimum of 17 meets that numeric floor. SDK version,
deployment minimum, simulator runtime, physical-device coverage and store
approval are distinct checks.

## Applicability matrix

"Open" means evidence or an applicability decision is still required. A disabled
feature records its current scope, not a successful test of a nonexistent flow.
The receiving issues below preserve responsibilities without inventing a named
operator; #113 had no GitHub assignee at this refresh.

| Requirement and primary source | Current applicability and observed evidence | Required result and receiving issue |
| --- | --- | --- |
| SDK and deployment floors — [Apple requirements][sdk], [index][requirements] | Applicable to an eventual upload. Existing 16.4/18.5 development execution is below the upload SDK floor; iOS 17 remains the selected deployment minimum. | Execute the separate 26.3/26.2 compatibility lane, retain exact package/build and built-product metadata, then verify the eventual signed distribution artifact. [#26](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/26), [#110](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/110), [#114](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/114). |
| App completeness, metadata and review access — [Guidelines 2.1, 2.3 and 2.5.19][guidelines] | Applicable. Inspected main launches a local-notes preview. Unmerged native candidates and synthetic data do not establish the advertised planner journey. No hidden or disabled capability is treated as review-approved. | Reconcile every visible and dormant feature with the actual shipping binary; demonstrate the supported journey and give Apple accurate review instructions and any genuinely required service access. [#111](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/111), [#116](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/116), [#117](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/117). |
| Account creation and deletion — [Apple account-deletion guidance][deletion] | Account creation is excluded from the selected baseline. Local draft deletion does not demonstrate deletion of an account or associated server data. | If activated, implement in-app initiation of account deletion and verify the actual associated-data, pending-write and revocation lifecycle. Keep the feature disabled while that evidence is absent. [#24](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/24), [#50](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/50), [#100](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/100). |
| Third-party/social login — [Guideline 4.8][guidelines] | Disabled. The actual identity method and exceptions determine equivalent-login obligations; no universal Sign in with Apple exemption or requirement is inferred. | Reassess the exact enabled login flow and any claimed exception before activation. [#24](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/24), #50. |
| Digital purchases, subscriptions and external links — [Guideline 3.1][guidelines] | Commerce is disabled. Product category, storefront and program terms have not been selected for an actual paid release. | Record storefront-specific applicability before adding purchase paths; require genuine StoreKit/server entitlement, restore, refund and revocation evidence where applicable. No worldwide external-payment exception is assumed. [#125](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/125), #24. |
| Privacy policy and disclosure answers — [privacy management][privacy-management], [data definitions][privacy-details] | Applicable despite guest-only scope. No verified production privacy-policy URL or App Store privacy answer set is supplied by inspected main. Absence of analytics is not a complete data-flow audit. | Publish an accessible in-app policy and metadata URL; inspect actual binary, network, diagnostics, Files-provider and SDK behavior and reconcile accurate collection/use/retention answers. [#98](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/98), [#101](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/101), #116. |
| Privacy manifests, required-reason APIs and SDK signatures — [manifest documentation][manifests], [SDK requirements][sdk-privacy] | No tracked `PrivacyInfo.xcprivacy` was found at the assessed main. Runtime packages use local Swift packages and system frameworks. This is an inventory observation, not proof that no required-reason API is used. | Audit actual direct and indirect API usage and bundled SDKs; provide approved reasons/manifests and applicable binary SDK signatures, then inspect the built app's privacy report. [#101](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/101), [#103](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/103). |
| Optional collection and tracking — [Guideline 5.1][guidelines], [privacy definitions][privacy-details] | Optional analytics, ad tracking and remote diagnostics upload are disabled by the accepted decision. Local diagnostic redaction does not authorize a later upload. | Keep optional collection off; if selected, review purpose, permission/withdrawal and actual tracking applicability, then test denial and revocation without losing core planning. #24, #98, #101. |
| Content creation and sharing safeguards — [Guideline 1.2][guidelines] | Current wording covers apps enabling content creation/contribution, including AI content creation. The planning client is not an inference runtime. Local notes/Files transfer, future remote sharing and community publishing require separate behavior-based assessment; guest scope is not an exemption. | Review the actual sharing/content surface with privacy/product receivers. Implement applicable filtering, reporting, blocking and contact controls before enabling covered services; retain import/export redaction and server authority requirements. [#48](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/48), [#82](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/82), [#102](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/102), [#126](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/126). |
| Encryption export compliance — [Apple overview][encryption], [documentation procedure][encryption-docs] | A determination is required for an app using encryption, including Apple OS cryptography. System transport/data protection does not justify guessing an exemption or `ITSAppUsesNonExemptEncryption` value. | Inventory the eventual binary's encryption and intended territories, answer the actual App Store Connect questions and retain any required determination/documentation. Do not put identities or supporting private documents in this repository. #112, #114, #113. |
| Legal seller, Developer Team and application identity — [enrollment requirements][enrollment] | App configuration deliberately uses `invalid.pickyourai.localpreview` and disallows code signing. No verified Team ID or App Store record exists in the assessed evidence. | Verify the intended legal seller/team and authorized account roles, then select the registered application identity and least-privilege signing setup. [#112](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/112), #114. Unsigned build success does not complete this row. |
| Release markets and trader information — [Apple DSA process][trader] | Markets and trader determination remain open. Apple's process requires a trader-status declaration even when an app is not distributed in the EU; verified trader contact details apply to covered EU distribution. | The authorized account/market receiver must make the actual determination and verify appropriate details, without inferring status from the GitHub organization or the app being free. #112, [#129](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/129). |
| Age rating and content declarations — [Apple questionnaire][rating] | Applicable to publication. No rating is inferred from synthetic fixtures or the word "planner." | Answer the current questionnaire against actual content and capabilities, including imported/shared content and any later AI generation; retain the resulting territory/OS-specific rating. #116, #126. |
| Accessibility representations — [label overview][accessibility], [VoiceOver criteria][voiceover] | Apple currently describes initial label participation as voluntary. The project's accessibility acceptance remains required independently. A system control or successful simulator launch does not prove completion of common tasks with assistive technology. | Audit common tasks on every supported device class before claiming a feature label; retain actual VoiceOver, large-text and other applicable results and truthful limitations. [#54](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/54), [#105](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/105), #116. |
| TestFlight, App Review and release state — [submission overview][submitting] | No signed uploaded artifact or authoritative Apple channel state has been verified for this application. CI and repository merges do not create that evidence. | Preserve separate upload/processing, beta review, App Review, explicit release decision and installed-production receipts. [#115](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/115)–[#118](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/118). |

## Required negative applicability walkthrough

1. Present a passing Xcode 16.4 build with a launched iOS 26.2 simulator as an
   upload-ready build. Reject the claim: its compiled SDK remains 18.5. Require
   actual 26+ SDK build metadata and later signed-artifact validation.
2. Enable account, paid-plan or remote-sharing UI while describing the release as
   guest-only. Reject inherited applicability conclusions; reopen the exact
   #24/#50/#125/#126 decision and failure cases before activation.
3. Supply a privacy-policy URL, encryption exemption, trader status or age rating
   without verified facts. Keep the corresponding row open and route it to its
   named decision issue. This document supplies no fabricated account answers.
4. Propose an accessibility label based on launch smoke or default system widgets.
   Keep it unverified until users can complete the app's common tasks with that
   feature on each supported device class.

These are documented review cases, not simulated Apple submissions. Actual
account, device, binary, privacy and channel observations remain required where
the matrix specifies them.

## Exact #113 acceptance disposition

| Live criterion | Evidence supplied | Remaining acceptance |
| --- | --- | --- |
| Current policy review identifies all selected release obligations. | Dated primary-source matrix covering the selected native guest baseline and explicit conditional capabilities. The obsolete upload SDK is identified; the separate compatibility lane requires its own actual hosted result. | Independent review of this exact matrix; update applicability when actual scope, binary or Apple requirements change. |
| Recheck official requirements against the selected SDK, accounts, markets, encryption, sharing and commerce; each unresolved applicability item links its decision owner and cannot be marked compliant by assumption. | Every named area is mapped to observed source/configuration, a specific receiving issue and an explicit unresolved result where facts are absent. No people, permissions, storefronts or exemption decisions are invented. | Resolve the actual named inputs and verify the eventual signed artifact; engineering inference alone cannot satisfy Apple account/channel evidence. |
| The dated Apple policy applicability/evidence matrix is linked with criterion results, exact versions, limitations and receiving-review disposition. | This record fixes the source inspection date, assessed main, toolchain versions, source links, negative review cases and acceptance limits. | Link the reviewed publishing commit and receiving receipt from #113. The live issue's signed-artifact and authoritative-channel validation is unexecuted, so this publication does not close #113. |

The assessed main's app/project/package files and the linked official sources
were inspected directly. No native execution is claimed from this Linux review.
Update this record when the new SDK lane produces a reviewed result or when the
actual release artifact, markets, identity, data flow or Apple policy changes.

[sdk]: https://developer.apple.com/news/upcoming-requirements/?id=04282026a
[requirements]: https://developer.apple.com/news/upcoming-requirements/
[runner]: https://github.com/actions/runner-images/blob/07cc2190cd4d100d9f69478219017720c02c40f6/images/macos/macos-15-Readme.md
[guidelines]: https://developer.apple.com/app-store/review/guidelines/
[deletion]: https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion/
[privacy-management]: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
[privacy-details]: https://developer.apple.com/app-store/app-privacy-details/
[manifests]: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
[sdk-privacy]: https://developer.apple.com/support/third-party-SDK-requirements/
[encryption]: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/
[encryption-docs]: https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/
[enrollment]: https://developer.apple.com/help/account/membership/program-enrollment/
[trader]: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
[rating]: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/
[accessibility]: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/
[voiceover]: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria/
[submitting]: https://developer.apple.com/app-store/submitting/
