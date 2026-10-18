# #22: Native Apple platform and repository ADR

Status: **accepted for engineering implementation under the user's explicit decision authority**, 2026-10-18. [Current disposition and evidence](foundation-disposition.md) selects the bounded #21 implementation scope and this architecture for the application implementation. Independent review of this updated record follows the normal PR workflow. No human/product receiving approval or release qualification is claimed. The original alternatives and rationale below remain applicable; missing production inputs do not prevent unsigned local/simulator implementation.

## Recommendation and alternatives

Select SwiftUI with narrowly scoped UIKit interoperability, Swift 6 language mode, iOS/iPadOS 17.0 minimum deployment targets, iPhone and adaptive iPad only. These minimum versions are the engineering baseline to bound lifecycle/UI qualification, not measured audience coverage. iPad keyboard, resize, rotation, VoiceOver and accessibility text sizes belong to the baseline. Native macOS, Catalyst, watchOS, tvOS and visionOS are deferred through #129; disable automatic additional-platform distribution until separately qualified. Multiple concurrently editable scenes are deferred; sequential navigation between durable drafts remains core.

| Candidate | Offline persistence | Accessibility | Toolchain and maintenance assessment | Disposition |
| --- | --- | --- | --- | --- |
| SwiftUI + native adapters | Platform SQLite behind a storage actor; explicit transactions and migrations | System controls plus explicit focus, labels, Dynamic Type and VoiceOver checks | One Swift/Apple toolchain; direct lifecycle, Keychain and file-protection access | Selected; native integration fits this Apple-only repository |
| UIKit-first | Same native storage boundary | Direct UIKit accessibility APIs; manual layout/focus work | Same macOS/Xcode requirement; more imperative state wiring for this new app | Keep interoperability escape hatch, reject as default |
| React Native | Requires chosen native storage integration and migration testing | Provides platform accessibility APIs; platform behavior still differs | Adds JavaScript tooling and native dependency compatibility; still needs Xcode for iOS | Reject for baseline absent an existing shared UI/code investment |
| Flutter | Requires a persistence/plugin choice and migration testing | Provides accessibility support; semantics and physical assistive testing remain necessary | Adds Dart/toolchain/plugin maintenance and Apple integration boundaries | Reject for baseline; no demonstrated reuse offsets added boundary |

This is a maintainability judgment, not a framework benchmark or claim that alternatives cannot support offline/accessibility. Linux domain tests never establish Apple framework correctness.

## Selected implementation boundaries

All Apple code belongs in this repository. `App/` contains the Xcode application composition, SwiftUI screens, navigation and scene lifecycle. Swift package `Packages/PlannerCore` contains contract DTOs and domain state/revision logic without SwiftUI, Keychain or network I/O. `Packages/PlannerData` contains protocol-backed local storage, catalog activation, URLSession adapters and Keychain access. App depends on Core and Data; Data depends on Core; Core never imports App or Data. Separate test targets cover portable domain semantics, Apple persistence/network adapters and app UI journeys. Do not copy a server, catalog publisher or pricing authority into these modules.

The original Core Data recommendation is superseded for local drafts by the engineering decision below; store immutable snapshots separately from incomplete editor drafts. No automatic CloudKit synchronization. Persistence acceptance requires interrupted-migration, disk-full, corrupt-record isolation, locked-device, revision-race and termination tests. Schema choice alone does not prove recovery. Contract JSON must preserve decimal/unknown semantics and reject unsupported versions; generated fields remain governed by research #40. Do not put incomplete drafts into a valid frozen-v1 build by inventing defaults.

Application bundle identifier, Developer Team ID and App Store Connect record remain unknown: do not fabricate them. Display name may be provisionally Pick Your AI. Preview uses explicitly synthetic inputs and no production endpoint; staging and production remain separately configured with validated endpoint/identity gates.

## Local storage implementation decision — 2026-10-18

Under the user’s explicit delegation of ordinary engineering decisions, use the system SQLite library for `Packages/PlannerData` local drafts and revision history. This supersedes the initial Core Data recommendation for this boundary. It requires no external Swift package, supports atomic compare-and-swap revision writes and schema upgrades, and allows the same negative/recovery cases to run on Linux and hosted macOS. Keep app-owned file protection, identity routing, SwiftUI integration and snapshot validation outside this actor. No stateful backend or shared contract changes are introduced.

The [implementation and tests](../../Packages/PlannerData/README.md) record schema migrations, actual capacity errors, abrupt process-exit recovery and retired-ID replay protection. These engineering results do not approve product scope, actual device persistence, security receiving acceptance or release. Core Data remains a rejected default for this slice because its platform-only stack adds no demonstrated requirement that offsets losing portable recovery tests; revisit if actual app requirements justify it. Future changes must preserve existing SQLite migrations and payload history rather than replacing data silently.

Merged receipt: [PR #137](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/137), commit `aa7da9b0e510b887e40a085aef009a2879b55b6c`. This update preserves its SQLite implementation decision and local implementation link.

## Toolchain and validation gate

Apple's [Xcode system requirements](https://developer.apple.com/xcode/system-requirements) distinguish host macOS, SDKs, deployment targets and simulator/device support; checked 2026-10-18. Do not interpret a deployment target as proof of an installed simulator runtime. The implemented package workflow pins Xcode 16.4 build 16F6 on `macos-15`; successful native test and unsigned iOS Simulator SDK compile receipts are linked in the current disposition. Keep this known-working toolchain for initial app scaffolding; record exact installed simulator runtime and device when executing app tests. The hosted image label is mutable, and a package SDK compile is not simulator execution. Avoid beta selection by default. Fresh-checkout `xcodebuild` build/test must cover compact iPhone and adaptive iPad on minimum and current supported OS before native acceptance. PR jobs must be unsigned and lack signing secrets; signed archives and devices require separate authorized credentials and evidence. Do not purchase runners or enroll a team.

Primary sources checked 2026-10-18: [SwiftUI and UIKit interoperability](https://developer.apple.com/swiftui/), [React Native accessibility](https://reactnative.dev/docs/accessibility), [Flutter accessibility](https://docs.flutter.dev/ui/accessibility). These document capabilities, not this app's conformance. Core Data documentation was reachable only as a JavaScript shell in the original check; no runtime claim was based on it. The subsequent SQLite implementation decision supersedes that storage proposal.

## Criterion disposition

| #22 criterion | Prepared evidence | Remaining acceptance |
| --- | --- | --- |
| Architecture decision names supported targets and implementation boundaries | Explicit target versions, excluded platforms, module dependency direction and native storage recommendation above | Independent review of the accepted bounded implementation decision; full release/support qualification remains separate |
| Compare offline persistence, accessibility, toolchain support and maintainability; record minimum OS/devices, placement and rejected alternatives before scaffolding | Four-candidate matrix, deployment floor, placement and CI gate above | Independent review must accept the recorded comparison/choice; app runtime/device tests belong to downstream implementation criteria |
| Linked ADR with criterion results, exact versions, limitations and receiving-review disposition | This ADR, current disposition and exact native-package CI receipts; no app/device result claimed | Updated publishing commit/PR and explicit decision-content receiving review receipt; downstream app/device and release results are not this ADR criterion |

## Closure boundary for this decision task

The live #22 requires a **product/release decision reviewer** and receiving review, but does not say that role must be human or name a mandatory individual. The user delegated educated engineering decisions and independent review. An independent agent reviewer may therefore review and explicitly accept this decision's scope, target/support tradeoffs, framework alternatives, module/storage boundary, evidence and limitations under that authority. Mere syntax review, or a receipt limited to “preparation only,” is insufficient; do not relabel prior receipts retrospectively.

After this exact ADR is published and an independent reviewer explicitly accepts that decision content, link both the artifact and receipt from #22 and reconcile its three criteria. Then #22 can close as an architecture decision. The named #21 prerequisite is the scope matrix, supplied by the selected implementation scope and existing 110-package matrix; it does not require closing #21 or inventing its real-data tuple. App scaffold validation, physical-device testing, production service integration, signing and release remain their own open tasks. They are not extra acceptance criteria for this ADR. No new routine human permission request is warranted by the text of #22.
