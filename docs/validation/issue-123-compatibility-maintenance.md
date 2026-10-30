# Compatibility maintenance and hotfix runbook

This is the bounded preparation record for
[Apple #123](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/123), under
[scope claim6264598638](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/123#issuecomment-6264598638).
It defines the compatibility inventory, change review, old-client drill and
maintenance evidence required before coordinated updates. **The older supported
client, real service migration and hotfix release drill remain unexecuted.**
Independent receiving review and delivery of this document are pending at this
preparation checkpoint; the issue's linked receiving disposition records their
later outcome. Existing assignments, native prerequisites and release authority
remain unchanged.

## Baseline and criterion results

Source inspection uses accepted commit
`76f84345eb4b5451af4385e8207fa7f8719ccc0a`, tree
`2fb09f5fcb6bcf3fc37fbfd272dca477d0fa2239`. The inspected identities are pinned
to that revision. Relative links are navigation aids and may advance with later
source; use the exact revision for historical verification. This baseline
preserves the delivered network/cache contribution at
signed `d29fd608b965d5affb89314d05f1c22e9439245a`, tree
`0795f0983cb66f99d92d68726ef1196ce886049d`, sole parent
`5c4da0e83482286536d4c49667b6f12aeac36144`.
[The #349 delivery review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/349#issuecomment-6264035605)
records that actual merge and its original execution evidence.

| Literal #123 criterion | This record supplies | Observed result / remaining acceptance |
| --- | --- | --- |
| Maintenance process preserves supported clients during coordinated updates. | Pinned configuration and executed-build inventory; change triggers, preservation rules and stop conditions below | Preparation only. No supported installed-client cohort or real coordinated update was exercised; criterion remains open |
| Run an older supported client against a service migration and rehearse a hotfix; define deprecation/recheck responsibility without invented release dates. | Ordered drill, required version/authority inputs, role responsibilities and recovery evidence fields | Required old-client, service migration and signed hotfix inputs are missing. No deprecation date, operator assignment or successful drill is supplied; criterion remains open |
| The OS/SDK/API compatibility and maintenance/hotfix runbook is linked with criterion results, exact versions, limitations and receiving-review disposition. | This runbook, exact source and original run references, failure/recovery mapping and explicit gaps | Document prepared for independent content/operating-boundary review and ordinary delivery. Link that exact artifact and receiving disposition from #123 before reconciling this documentary criterion |

The named prerequisite from [#30](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/30)
is a clean PR run executing required native checks without weakening the existing
gates. The original #349 run supplied all fourteen configured checks, including
actual native jobs, as recorded below. That bounded input permits this preparation;
it neither closes all of #30 nor transfers old results to a changed candidate.
The repository's current required checks and independent receiving review still
govern delivery of this document. No workflow, documentation-scope selector,
dependency policy, contract or product source is changed here.

## Configuration and compatibility inventory

The [accepted platform decision](../decisions/issue-22-platform.md) selects iPhone
and adaptive iPad, SwiftUI with UIKit interoperability and a 17.0 deployment floor.
The [device/lifecycle matrix](issue-107-device-lifecycle-matrix.md) retains the
separate minimum/current OS, physical-device and interruption gaps. A minimum
deployment target, SDK compile and installed simulator runtime answer different
questions; keep all three fields in every compatibility receipt.

| Boundary | Exact inspected configuration | Evidence and maintenance limit |
| --- | --- | --- |
| Apple product scope | iOS/iPadOS 17.0 minimum; iPhone and adaptive iPad; no additional Apple product platform selected | [Platform ADR](../decisions/issue-22-platform.md) and [App composition](../../App/README.md). The package macOS declarations support host tests; they do not activate a macOS product. Minimum-OS/physical-device qualification remains separate |
| Development compiler | [Xcode pin](../../App/toolchain.json): Xcode 16.4, build 16F6, `/Applications/Xcode_16.4.app/Contents/Developer` | Original #349 development jobs observed Swift 6.1.2 and SDK 18.5. Preserve the regression baseline until a reviewed replacement and its actual checks are accepted; do not silently select an available Xcode |
| Unsigned submission compatibility | [Xcode pin](../../App/submission-toolchain.json): 26.3 / build 17C529; [SDK pin](../../App/submission-sdk.json): device and simulator 26.2, product minimum 17.0 | Original #349 submission job observed Swift 6.2.4 and built both unsigned Release products. [SDK verification](submission-sdk.md) checks actual metadata. This configured selection is not an evergreen statement of Apple's upload policy or a signed release |
| Native dependencies | Five repository-local Swift packages; system SDK/frameworks and system SQLite | The five `Package.swift` manifests and [storage record](../../Packages/PlannerData/README.md) pin behavior through the source tree. No remote Swift package is currently resolved. Inventory any newly introduced dependency, resource, license or required-reason API before accepting it |
| Python preparation | CPython 3.12.14 in the preparation workflow; [version manifest](../../tools/conformance/requirements.txt) and [artifact lock](../../tools/conformance/requirements-lock.txt) | Seven packages: jsonschema 4.25.1, referencing 0.37.0, jsonschema-specifications 2025.9.1, attrs 26.1.0, rpds-py 0.30.0, PyYAML 6.0.3, typing-extensions 4.16.0. [Environment record](../../tools/conformance/environment-lock.md) limits the eleven admitted wheels; artifact availability is not execution on every platform |
| Python Transfer reference | Separate [hashed requirements](../../Packages/PlannerTransfer/Tools/requirements.txt), jsonschema 4.26.0 and explicit timestamp/URI providers | The [reference environment](../../Packages/PlannerTransfer/Tools/reference-environment.md) pins all nine distributions, including typing-extensions only before Python 3.13. Original Transfer used Python 3.14.7 and eight applicable packages. Preserve this provider contract independently of the preparation environment |
| Frozen artifacts | [Contract lock](../../tools/conformance/contract-lock.json): contract 1.0.0, fixture bundle `apple-contract-preparation-1`, Research revision `7acbefbf4e4e700231e88be272bc89e3a73dde15` | Import manifest SHA-256 `ef6d5801eec10f3169e2bf84653e7026b33088e305a987991ec52faadcd7f554`. Frozen v1 changes require canonical Research #40 review and a governed migration; an Apple decoder cannot redefine the shared contract |
| API and old-client negotiation | Frozen API version 1.0.0, OpenAPI syntax 3.1.0; relative server `/v1`; thirteen paths/fourteen bearer-protected operations | [Apple #34 packet](../proposals/issue-34-api-consumer-intake.md), blob `42e99538ab7c1314e32b23b8f2689eacba71ca16`, inventories all operations and R1–R7 gaps. It supplies no live origin, approved version-negotiation extension, deprecation window or older-client compatibility receipt |
| Shared service and operations | [Apple #23 handoff](../decisions/issue-23-services.md) consumes the accepted canonical shared-service design | Website/Android/Research authorities retain their existing responsibilities. Actual deployed identity, guest/object authority, custody, recovery and operating acceptance remain required; this document introduces no service or wire interface |

The two Python installer inputs have distinct exact identities at this baseline:
preparation lock blob `e5d907c2a4b7ef8318ba0958763f8235c415ba4b`, SHA-256
`39f16918d39968c6e26183c2d09399b49cc071bf751a7c3beff4577dd3717c23`;
Transfer requirements at that baseline were blob `938c69ecb43b8eda36bee6066e1802f103190ece`, SHA-256
`49d2158183e44a47f0f66fd7ce6cb146ca52281015cfcd2e9dd2670724eb0344` (1,969 bytes, CPython 3.11–3.14 macOS wheels).
The current Transfer requirements file is 2,139 bytes, SHA-256
`fcbc3401debf58500ce2c5f7a6a298e445d1c6161e21ab3de571bf0f9a64e777`, after admitting the two regular CPython 3.15 macOS `rpds-py==2026.9.1` wheels.
Install into a newly allocated environment with the documented isolated,
hash-required, binary-only commands and dependency consistency check. An already
installed matching version does not prove its wheel matches the lock. Keep the
resolver enabled so missing transitives fail; update provenance, license evidence,
both relevant manifests and failure/recovery checks together when changing a lock.

## Original executed evidence

The following table refers only to source
`a421e7f612b99cc4584c8cf4a8aa6641f5b44e8e` and its actual prepared checkout
`2f8fa7f92bf329c6bcc3c90eab800cf54e01de78`, tree
`78a8b4209b101e34e1128bdca3a43b5a24efeb47`, ordered parents
`666033a9f6621e3342b190e75725310fa71f8826` and `a421e7f…`.
All fourteen original checks succeeded; the six scope jobs are included in that
fourteen, rather than counted as additional native execution. Original logs and
artifact members were read, matched to their actual checkout and checked against
the source method inventory. The #349 receiving link above records the qualification.

| Original run | Actual bounded result | What it does not establish |
| --- | --- | --- |
| [Core 39211805287](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39211805287) | 113 methods in each debug, optimized, iPhone, iPad and mutation-baseline run; all expected positive results; actual deliberate failures caught by their assertions | A new source tree, external evaluator, physical-device performance or full application journey |
| [Transfer 39211805303](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39211805303) | 107 methods including all six network/cache recovery methods; 14 frozen source hashes and 2,957 reference cases; unsigned SDK 18.5 arm64/x86_64 compilation | Live HTTP/TLS, installed old-client or service migration behavior |
| [Storage 39211805304](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39211805304) | 31 methods each on macOS, iPhone SE (3rd generation) and iPad (10th generation) simulators; ten replay guards; actual abrupt process exits during write/migration and successful recovery | Physical locked-device behavior, app background expiration or server restore |
| [Submission SDK 39211805305](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39211805305) | 353 package methods: 113 Core + 31 Data + 107 Transfer + 79 Catalog + 23 UI, no failures/skips; all six new recovery methods; 25 toolchain/SDK guards; five fresh caches; unsigned device/simulator Release builds at SDK 26.2 / minimum 17.0 | Codesigning, provisioning, a distribution archive, TestFlight, App Review or installed production behavior |
| [Catalog 39211805307](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39211805307) | 79 methods, no failures/skips; unsigned SDK 18.5 compilation | Real catalog rights/freshness, newly accepted offline-release features or a governed live data release |
| [UI 39211805321](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39211805321) | 23 model methods, four macOS rendering cases, eight pin guards; unsigned SDK 18.5 build; launch smoke on iPhone 17 Pro and iPad Pro 13 (M5) simulators running iOS 26.2 | Minimum 17.0 execution, complete journeys, physical devices, VoiceOver or release approval |
| [Preparation 39211805331](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39211805331) | 47 Python methods, 137 schema cases, six domain checks and three detected deliberate mutations; fresh seven-package locked environment | Swift execution or adopted service/evaluator policy |
| [Dependency 39211805319](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39211805319) | 62 security guard methods and the actual configured dependency gate succeeded | An all-time vulnerability guarantee, complete native-binary inventory or credential rotation |

The original fourteen-check qualification index has SHA-256
`3e76b3c35f5a84dbfa9359be6b2c44f4bc11dbd857619778c48cd283ac9a26e3`.
It retains each check/job ID, ordered source identity and seven complete lane
receipts. For example, original UI artifact 12175565930 is 1,751,395 bytes,
SHA-256 `1d72e0efa80eb6373f75d18af8fa943b54143b2d16b781b56346dbbb58bc3c2e`;
all fifty archive members were checked. Preserve original artifacts before their
configured retention expires; retain their hashes and qualified results with the
change record. A missing/expired original requires an explicit evidence gap or a
new separately identified execution, never an inferred historical pass.

### Separate post-merge and later-source observations

Actual main `d29fd608…` ran [Storage 39228666148](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39228666148)
successfully. Its workflow-list success metadata was updated on 2026-10-19 at
10:06:13 UTC. Its 31 methods passed separately
on macOS, iPhone SE (3rd generation) and iPad (10th generation) / iOS 18.5, with ten replay guards, real process-exit
recovery and an unsigned SDK 18.5 build. Actual host was macOS 15.7.9 / build 24G830,
Xcode 16.4 / build 16F6, Swift 6.1.2. Original artifact 12177359361 is 211,923 bytes,
SHA-256 `69ae199ba063b3c461d4c3bf7f435ac67a1192633b64c3c1ffae66846c532b20`;
all 211 members, uploader/API identity and exact source attendance were checked.
Qualification receipt SHA-256 is
`52e44501d6e1f230d7d8280b72c09c424869de9d0a3eb76c137004398d6d9c3f`.

At the separate 10:11:56 UTC readback, d29's preparation run 39228666127 and Storage
had succeeded; its five other native runs remained queued. Later results belong
to later dated receipts. The inspected 76f baseline also contains accepted
offline-release selection (#351), historical quality comparison (#354), protection
of newer edits during asynchronous draft open (#181), and conformance input/output
preflight correction (#345). Those later changes preserve this runbook's linked
original receipts; their execution is not supplied by the earlier #349 totals.

## Change triggers and required review

Maintenance is triggered by an interface, dependency, toolchain, supported-device,
service/data release or incident change. There is no invented weekly release
schedule or default deprecation duration. Before implementation or rollout, open
one scoped change record and reconcile current owners and overlapping PRs.

| Trigger | Required comparison and checks | Receiving responsibility |
| --- | --- | --- |
| OS support, Xcode, SDK or app configuration changes | Diff the exact pins, deployment targets and package graph; verify the selected bundle/SDK and built metadata; run affected native/unsigned jobs and the changed minimum/current device/lifecycle rows. Read current primary [Apple requirements](https://developer.apple.com/news/upcoming-requirements/) and [Xcode support](https://developer.apple.com/support/xcode/) before making a release-policy claim | Apple engineering/CI receiving review; the actual authorized release maintainer records channel applicability. No existing operating assignment is implied |
| Validation or runtime dependency changes | Reconcile source/lock/provenance/license inputs; fresh isolated installation, wrong-hash and missing-transitive rejection/recovery; canonical vectors and actual affected native jobs. Preserve the [dependency policy](dependency-review.md), its bounded immutable-artifact proofs and all unrelated gates | Engineering/security receiving review of exact artifacts and changed behavior; release inventory has its own signed-binary scope |
| API, authority, schema or data-release changes | Pin old/new API and artifact versions, release IDs/hashes, scope/rights/withdrawal state, environment and allowed consumers. Resolve #34 R1–R7 through canonical owners, then run the old-client matrix below | Existing canonical service/data owners and affected Apple/Android/web reviewers; Research #40 governs contract changes. A consumer proposal is not their adoption |
| Local storage, cache or editor changes | Preserve original durable rows, immutable history, retired identities and exact artifact bytes. Exercise migration interruption, corrupt/future input, concurrent revision updates and cancellation; qualify UI/device paths separately | Apple storage/UI receiving review and data compatibility review when shared meaning changes |
| Hotfix or incident recovery | Pin the affected distributed build and actual service/data state, retain failure evidence and privacy classification, define containment and forward fix, then execute the required drill and affected regression gates | Support/service/data operating receiving review and authorized release responsibility, recorded for that specific change |

Each record must identify the actual person or accepted responsible role holder
before an operational action is assigned. Role labels here define review work;
they appoint no operator, recovery custodian or release maintainer. Record independent
review of the support/service/data responsibilities and compatibility procedure
against the exact source. That review neither appoints an operating role nor
attests to an unperformed service or installed-client drill. Keep the existing
[service O1–O6 gates](../decisions/issue-23-services.md)
and live issue ownership intact.

## Coordinated migration and old-client drill

This procedure is prepared, with every operational step below **unexecuted**.
Use only an adopted canonical service interface and a specifically authorized,
isolated environment. The frozen relative `/v1` server and local URLProtocol
fixtures do not supply one. Record each missing input rather than manufacture a
response code, version header, route or compatibility window.

1. **Identify both clients and both service states.** Retain the older supported
   installed build and proposed hotfix/candidate: source/tree, app version/build,
   executable/archive SHA-256, signing/provisioning and distribution-channel
   receipt, device class, actual OS/SDK and supported scope. Pin service and data
   releases before/after, deployed environment identity, contract version,
   credentials/guest-object authority and permitted cached artifacts. Keep secret
   values outside the public record. The selected older binary and actual service
   migration are currently missing.
2. **Capture a baseline before changing state.** On the unchanged old client,
   establish the supported journey, durable draft ID/revision/history and exact
   catalog/graph/rule/pricebook pins. Record observed errors/unknowns, local offline
   behavior and authorized remote receipt/head separately. Capture privacy-safe
   evidence and recovery inputs before modifying any service or local store.
3. **Review coexistence and deprecation before rollout.** The canonical service
   owner and affected-client reviewers must accept which existing client versions
   remain compatible, which operations/data representations can change, the
   migration order, withdrawal/revocation treatment and the exact end conditions
   for old behavior. Record an agreed window only when supplied by that decision.
   If there is no adopted compatibility or explicit rejection mechanism, the
   migration step remains blocked; no new wire behavior is defined here.
4. **Exercise the old client against the changed service.** Run the cases below
   with actual old-client requests and service observations. Verify intended
   behavior and failures independently of server deployment success. Preserve
   local editing and evidence labels through outage, unsupported data and stale
   callbacks. A timed-out write may already be committed; reconcile the real
   authorized head/operation receipt before retry or a success message.
5. **Recover and recheck both directions that are actually supported.** Use only
   the accepted service/data rollback or containment mechanism. Reconcile current
   rights, revocations, deletions and committed operation state after recovery;
   restored bytes alone cannot restore authority. Confirm old-client behavior and
   the proposed fixed client against that recovered state. A downgrade of local
   storage or an installed App Store binary is not assumed safe or available.
6. **Receive the evidence before retiring compatibility.** Compare observed
   results with the agreed matrix and stop conditions. Record failed cases,
   corrective source/release, repeated cases and reviewer disposition. Service,
   client, support and release responsibilities must each accept their applicable
   step. Keep a named recheck trigger and unset deprecation date when no supported
   operating agreement supplies them.

| Required case | Expected preservation/recovery observation | Available related evidence / missing operational result |
| --- | --- | --- |
| Old client reads supported data after migration | Exact accepted representation and pins remain usable; current checks remain tied to the selected revision and evidence tuple | Frozen/reference admission and package checks exist. Actual old-client/service result is missing |
| Newer or withdrawn representation | Adopted compatible response or explicit rejection; retain only still-eligible prior data and durable draft; no mixed pair or silent contract rewrite | Package hash/version rejection is available. Version negotiation, release eligibility and withdrawal against a live service remain missing |
| Timeout, throttling or disconnect during a second artifact | No partial activation or invented success; bounded fixed error; explicit recovery preserves the original pair | [#106 tests](issue-106-network-cache-recovery.md) actually pass through intercepted URLSession on both original Xcodes. Real service/network behavior remains unexecuted |
| Wrong immutable pin or schema-shaped replacement | Reject substituted bytes even when their shape is valid; reopening preserves the original exact pair | Original #106 malformed/replacement cases passed. An approved migrated service/data release remains missing |
| Cancellation, newer local edits and stale write | Ignore obsolete result/authority; preserve newer committed draft/history; reconcile uncertain remote writes without blind retry | Original #106 exact cancellation/local CAS case and d29 process/storage recovery passed. App background expiration, stale remote writes and installed-device behavior remain unexecuted |
| Service/data restore and hotfix | Retired authority stays retired; recoverable state remains readable; selected old/fixed clients have explicit outcomes; support can identify the affected build | Prepared procedure only. Actual isolated restore, distributed older binary, signed hotfix and operating receiving result are missing |

## Hotfix record and release boundary

Prepare the smallest reviewed fix from an exact source base while retaining the
original failed run and affected build. Record user-visible containment, local
data consequences and whether compatibility can be preserved through a service
change or requires a client forward fix. A server/data rollback and an installed
client update are separate operations. Do not promise remote binary downgrade,
automatic local database downgrade or a store approval date.

Run the changed-source regression and the repository's configured checks; retain
any first failure and subsequent correction. For a release candidate, additionally
verify the actual signed binary, privacy/configuration inventory, minimum/current
supported devices, adopted service behavior and required beta/channel evidence.
Link [#110](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/110),
[#113](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/113) and the
[#117 release decision](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/117)
as applicable; upload, review acceptance, release authorization, rollout and
installed behavior require their distinct actual receipts. A signed Git commit
or the unsigned submission-SDK job cannot supply them.

The maintenance record for each real drill/change must retain:

- Exact old/new client source, tree, app/build and binary identities; observed
  toolchain, device/OS, channel and signing facts, with unavailable fields explicit.
- Exact service/API/schema/data releases, environment, authority scope, artifact
  eligibility and source-use/retention decisions; no credentials or private payloads.
- Approved coexistence/deprecation decision, actual operating/recheck responsibility,
  intended steps and stop conditions, with no invented dates or response promises.
- Reproducible commands/actions, original run/attempt/job IDs, source checkout and
  every expected/observed case, including first failure, recovery, canceled,
  missing and skipped work. Store artifact/log bytes, hashes and retention location.
- Durable draft/history and remote receipt/head observations before/after; privacy
  effects, loss/correction outcomes, corrective commit/release and affected clients.
- Exact source and receiving reviews, protected merge/accepted-main identity,
  post-merge results and separate service/release/installed dispositions. Reconcile
  only the literal criteria actually met; link unresolved cases to their existing
  owners without silently transferring or closing their work.

## Verification and remaining work

This change is one documentation file. Preparation verifies its complete source
and evidence references, literal #123 criteria, exact pins, relative Markdown
links and whitespace. It performs no new Swift, simulator, service, store or
hotfix execution. The original runs above retain their original source identity;
normal configured checks on this document's eventual PR are separate evidence.

Required receiving work is independent review of the compatibility inventory,
old-client/hotfix procedure, responsibility and evidence boundaries, followed by
ordinary protected delivery and a link from #123 to the exact artifact and review.
Operational C1/C2 acceptance still needs the actual older supported client,
canonical migrated service, accepted operating/release responsibilities and the
failed/recovery drill results. This document supplies preparation for that work;
it changes no minimum OS, supported platform, frozen contract, service commitment
or release gate.
