# Actionable Xcode pin validation

Scope: the remaining unavailable-toolchain and clean-cache case for
[Apple #26](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/26).
The accepted local SwiftUI/iOS 17 architecture, checked-in project and local SQLite
package remain the implementation boundary.

[The pin](../../App/toolchain.json) names Xcode 16.4, build 16F6, and its exact
developer directory. [The verifier](../../App/scripts/toolchain.py) uses the
explicit directory to query /usr/bin/xcodebuild with DEVELOPER_DIR, compares the
complete version/build response, and returns a verified environment only on success.
Missing directories, unreadable/malformed pin files, a failed/timed-out probe or a
different version/build produce setup instructions and exit status 2. The CLI never
searches installed versions. Commands after -- receive the verified environment and
their exit status is propagated.

## Reproduction and retained evidence

Run the portable checks:

```sh
python3 -m unittest discover -s App/scripts/tests -p 'test_toolchain.py' -v
```

The unavailable-pin regression executes the production CLI as a real child process
with a temporary pin naming a missing Xcode bundle. It requires exit status 2, exact
installation/version/path instructions, an unchanged pre-existing environment file,
and absence of a downstream command's sentinel. Its captured failure message is
printed into the retained test log. Additional injected probe tests cover a wrong
version, wrong build, extra output, nonzero exit, timeout, inherited directory
override, malformed configuration and command exit-status propagation.

The native workflow first runs those checks, then invokes the same CLI against the
real repository pin. It records pin-tests.txt and pin-selection.txt. It verifies
empty explicit SwiftPM cache/scratch, Xcode package cache and derived-data paths
before dependency resolution/build, retaining empty-caches.txt. Model tests and the
unsigned iOS Simulator app build use those paths. The existing Xcode/macOS/Swift/
runtime logs and iPhone/iPad launch logs remain in native-local-drafts-evidence.

The five current Swift packages have no remote package dependencies: local package
paths are committed together, and CSQLite uses the selected system SDK. Missing
checkout content fails resolution/build; the verifier does not download or substitute
package or Xcode versions. Future external dependencies require explicit version
pins and their own unavailable-pin regression.

## Acceptance disposition

The implementation reached signed main in
[PR #195](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/195) at
[`acb0b578cbca098867abcd10f7137a81f98fe483`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/acb0b578cbca098867abcd10f7137a81f98fe483).
GitHub's commit readback reports a valid verified signature and full tree
`ea1ce16bd2d29b00f3d8179074cc3d126f88f816`. The earlier unavailable-executor
statement describes implementation intake; it is not a current native-evidence gap.

The following receipt was independently checked against the raw hosted job log,
artifact metadata and Git objects on 2026-10-18. It covers the issue's pinned
configuration, fresh-cache build and unavailable-pin negative/recovery case.
Independent receiving review of this exact record and its signed-main publication
completed through [PR #210](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/210).
[Review 5561703728](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/210#pullrequestreview-5561703728)
accepted the bounded receipt while retaining the additional validation gaps below.
This receipt alone does not justify issue closure or change any checkbox.

The accepted record, blob `b23a2664055457acc40721c8a502cab1d4504a9f`, reached
verified signed main
[`0ec644af3e3516fd4d000c0fbe92cf0e51696779`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/0ec644af3e3516fd4d000c0fbe92cf0e51696779),
tree `5775e48a4f1c0492b2d5217a35c785dc0a64919c`, preserving the concurrent
accepted main. The [issue publication receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/26#issuecomment-6246453594)
records that delivery and explicitly retains the open app-lifecycle and environment
checks. This publication result does not recast the historical native execution
below as a new or current-main run.

### Execution and artifact identity

| Field | Verified value |
| --- | --- |
| Native run and job | [39098950754 / 117591076018](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39098950754/job/117591076018), completed successfully |
| Tested checkout | `37067364226f3849dac4873a269bcc8eb129b351`, test merge with ordered parents `1a5954b268834b1199b12982d20abc9ff387e9f5` and `b29cf778a38d4d93cf94242a125892d558b8e694` |
| Tested full tree | `4333fb38bca664d6377a0cd5bcfad862b200fc62` |
| Host | macOS 15.7.9, build 24G830; workflow runner label `macos-15` |
| Compiler and SDK | Xcode 16.4, build 16F6, explicit `/Applications/Xcode_16.4.app/Contents/Developer`; Apple Swift 6.1.2; iPhoneSimulator 18.5 SDK |
| Build targets | Unsigned `Planner` simulator application, arm64 and x86_64, iOS 17.0 deployment floor |
| Observed launch destinations | iPhone 17 Pro and iPad Pro 13-inch (M5), both iOS 26.2 simulator runtime |
| Retained artifact | [native-local-drafts-evidence, ID 12126840445](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39098950754/artifacts/12126840445), 13,002 bytes |
| Artifact SHA-256 | `1df5edfbdf0b3642ddce74ac5401af10fa88fed3fddf8829eb54e215bbcf17c9` |
| Artifact availability readback | Not expired when inspected; advertised expiry 2026-11-01 05:33:25 UTC |

The observed simulator runtime is distinct from the compiled SDK and deployment
floor. This run does not prove execution on the minimum iOS 17 runtime or every
supported OS/device combination. The hosted image label is mutable; the host,
compiler and actual runtime above identify this execution.

The tested checkout and delivered main have identical `App/`, `Packages/` and
`.github/workflows/native-ui.yml` contents. The only full-tree differences at
delivery are the four separately reviewed obsolete-PR maintenance files listed in
[the final receiving review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/195#pullrequestreview-5561607454).
This is evidence for the delivered native build inputs, not a claim that a later
push-triggered run has already passed.

### Exact criterion receipt

| Criterion from Apple #26 | Observed implementation and failure/recovery result | Receiving boundary |
| --- | --- | --- |
| Fresh macOS checkout builds supported targets reproducibly. | The retained job checked out the exact merge above, verified the explicit Xcode pin, passed all 17 native model tests, built the unsigned simulator app for both architectures, and completed iPhone/iPad launch smoke. The configuration and native inputs are preserved in signed main. | The selected iPhone/iPad application build boundary is demonstrated. The issue's additional backgrounding/cancellation validation and full OS/device qualification are not established by this run. |
| Build from a fresh macOS checkout with an empty dependency cache; unavailable pins must fail with actionable setup instructions rather than resolve a different dependency silently. | All four named SwiftPM/Xcode cache and output paths were verified absent before resolution/build. All eight pin regressions passed. The actual missing-pin CLI returned status 2 with exact version/build/path setup instructions, preserved the existing environment file, and prevented its downstream sentinel command. The next production CLI invocation selected and verified the real pinned Xcode; model tests and the clean build then succeeded. Five committed Swift package manifests use local paths and the SDK system library, with no remote package release to substitute. | Both the intended failure and successful recovery were executed. Portable or injected-probe results alone are not used as the clean native build evidence. Future remote dependencies require their own version pins and unavailable-pin case. |
| The pinned Xcode/package configuration and clean-build log is linked with criterion results, exact versions, limitations and receiving-review disposition. | The pin, verifier, configuration and reproduction commands above lead to this exact run/artifact and its identity table. [Source/execution review on #176](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/176#pullrequestreview-5561501356) and [final integration/execution review on #195](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/195#pullrequestreview-5561607454) accepted the source and observed native gate; both explicitly reserved this issue-specific receipt. | [Independent receiving review on #210](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/210#pullrequestreview-5561703728), its verified signed main publication `0ec644af` and the [linked issue receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/26#issuecomment-6246453594) complete the record's review/publication step. Resolve the additional app validation gaps before whole-issue closure. |

### Additional issue validation remains explicit

The live #26 validation paragraph also names cold start, backgrounding,
cancellation and invalid environment configuration. The observed launch smoke
covers initial simulator launch. The pin tests exercise invalid toolchain
configuration and preserve the environment file on failure; they do not test the
app's preview/staging/production configuration. The two passing native model tests
`testLifecycleSaveDuringHistoryReadIsDrainedWithLatestEdits` and
`testLifecycleSaveDuringRestoreUsesNewRevisionAndLatestEdits` exercise controlled
lifecycle-save calls; they do not reproduce an operating-system background event.

Actual app background/foreground, cancellation and invalid app-environment
journeys are not evidenced by this receipt. Existing #27/#28/#29 and cumulative
editor work can supply the corresponding artifacts once executed and accepted, but
their presence is not an acceptance waiver for #26. Keep #26 open until these
named checks have evidence or a recorded applicable receiving scope disposition.

The architecture prerequisite is the accepted
[#22 decision receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/22#issuecomment-6244062120).
The #26 evidence does not establish all #30 branch-protection/untrusted-PR
requirements, physical-device or assistive-technology behavior, actual Files
provider journeys, signed installation, TestFlight, App Store or release readiness.
Those acceptance requirements and any later combined editor workflow results remain
separate. No owner assignment, Project field or unrelated criterion is changed.
