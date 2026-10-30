# Native local draft preview

This unsigned iPhone/iPad app composes `PlannerUI` and `PlannerData`. It is a local
editor, with no catalog, evaluation, snapshot export, account, remote sync or release
configuration. The reserved `invalid.pickyourai.localpreview` bundle ID is for simulator
use only; it does not allocate a production application identifier or signing team.

The delegated engineering mandate selects SwiftUI/iOS 17 and the local SQLite actor
implemented in PlannerData for this executable slice. This advances the proposed
[#22 ADR](../docs/decisions/issue-22-platform.md); its previous Core Data recommendation
is superseded for this local store only. Product receiving acceptance stays separate.

On macOS, use the [pinned toolchain setup and commands](#pinned-toolchain) below.

The workflow records the actual compiler/SDK/runtime and runs model tests, an unsigned
simulator build, and iPhone/iPad launch smoke checks. It contains no signing secrets.
The smoke script is not an accessibility or complete journey test.

The simulator qualification job uses the existing Xcode 26.3 / 17C529 and SDK 26.2
pins described in the [toolchain continuation](#simulator-toolchain-continuation-2026-10-19).
The Xcode 16.4 development pin and rendering/package baseline remain unchanged.

The [launch-smoke runner](scripts/simulator-smoke.py) retains its existing selection:
the newest available iOS runtime and the first available iPhone and iPad types in
that runtime's inventory. Its inventory/create/boot/launch/terminate commands have
60-second deadlines. Installation has a dedicated three-minute budget, and waiting
for boot readiness has a separate five-minute deadline. Each command, deadline,
exit code and captured output is printed into the workflow's retained `launch.txt`,
including partial stdout/stderr after a timeout. Each operation is attempted once;
a timed-out or failed installation or launch command still fails the smoke gate.

Each destination is a newly created simulator with a newly installed app. The
runner uses one plain `simctl launch` and does not request pre-launch termination
of an earlier app process. Successful launch must still be followed by the
explicit `simctl terminate` command before owned shutdown and deletion. This
removes an unnecessary pre-launch request; it does not retry a failed launch,
change its 60-second deadline or establish a simulator failure's root cause.

Only a successfully returned, parseable UUID absent from the original inventory is
eligible for use or cleanup. Commands preserve that returned ID's original spelling.
Each verified creation is protected by `finally`: shutdown and delete are separately
bounded to 60 seconds, and delete is attempted even if shutdown fails or times out.
Successful deletion is required; an already-shutdown result alone is not a cleanup
failure. If creation times out, even a partial UUID does not authorize cleanup, and
the retained command/name/output is the evidence for later inspection. The runner
never shuts down or deletes a pre-existing device, guesses an ID, or erases a device.
After a failed launch, two read-only diagnostic commands target that same verified
owned UUID before cleanup: the installed app-bundle container query and the last
two minutes of simulator logs filtered to the Planner process or its exact bundle
identifier. Each has its own 15-second limit. Diagnostic output or failure is
retained in `launch.txt`; neither can turn the failed launch into a pass, retry it,
or replace its original error. The 60-second launch limit and separate cleanup
limits are unchanged. The outer job deadline can still interrupt diagnostics or
cleanup. These are observations for diagnosis, not evidence of a launch cause.
Apple describes simulator-specific tools in its [Simulator command-line guide](https://developer.apple.com/videos/play/wwdc2019/418/)
and filtered log inspection in its [logging example](https://developer.apple.com/videos/play/wwdc2022/10119/).


The earlier receiving attempt at `1f48f42f` timed out during the single plain
iPhone launch after installation succeeded; its bounded container lookup also
timed out. Earlier successful destinations retain their own source/run identities.
The runner now records best-effort runtime snapshots immediately before launch
and after a launch failure: host load averages, selected virtual-memory counters,
PID/parent/state/CPU-percent/RSS for an allowlist of simulator processes, and
selected service PID/status rows from that verified owned simulator. Host process
rows are not proof that a process belongs to this destination; the separate
service query carries the explicit destination scope.

Each of the three read-only probes has a three-second deadline. Only filtered
fields are emitted, with at most 40 rows and 4096 row-text characters per probe;
process arguments, environment, unrelated labels and raw diagnostic stderr are
not emitted. Empty, truncated or failed observations do not establish healthy
readiness or absence of a service. The extra observations can perturb timing and
supply no fix or causal conclusion. They add no readiness wait, retry, timeout
increase or successful-launch fallback. The ordinary launch, explicit
post-success termination and owned cleanup keep their existing requirements;
actual native qualification still requires the successful launch/PID receipt.

Seven additional portable cases exercise filtering, truncation, short-deadline
partial output, unavailable probes, exact owned scope, launch/failure ordering
and absence of snapshots before successful owned installation. They supplement
the original 17 methods; portable execution does not establish a native outcome.

Seventeen portable regressions cover these deadlines, partial output, failed install/launch,
ownership and cleanup boundaries; one executes a real bounded synthetic subprocess.
Launch-failure cases also cover diagnostic command failures, exact preservation
of the original timeout, and isolation to the failing iPhone or iPad's owned UUID.
The mandatory native CI step runs them separately from the Xcode-pin guards and
retains their complete output in `smoke-runner-tests.txt` with the native evidence.
Actual macOS simulator execution remains required for a changed runner.

**Standard Intel runner trial — 2026-10-19.** The native UI workflow selects
GitHub's standard `macos-15-intel` hosted runner for one changed-environment
qualification. GitHub's [public runner specification](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
checked on this date, lists four Intel CPUs and 14 GB RAM for this label, compared
with three M1 CPUs and 7 GB RAM for the previous `macos-15` label. This public
repository uses a standard runner; this change adds no paid or self-hosted runner.

The [Intel image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md),
checked on the same date, lists Xcode 16.4 / 16F6 and an iOS 26.2 simulator runtime.
An image inventory is not execution evidence. This initial Intel trial required
that exact Xcode directory/version/build. The smoke runner still selects the
newest actually available iOS runtime and its first iPhone and iPad types. The
actual image, compiler, SDK, runtime, devices and launch outputs must be recorded
by the new job. No runtime substitution or destination shortcut is introduced.

The original arm64 job at receiving checkout `1c06b3d29346037e7bb82aa3718fb17aa89d2037`
is still [failed](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/317#issuecomment-6261553869):
the iPhone launch returned PID 19822, while the iPad's single launch timed out at
60 seconds after successful installation. Its owned service queries also timed
out, and the recorded host load was high. Those observations do not establish a
cause; the phone succeeded with a higher recorded load. All original logs, artifact
hashes and earlier `1f48f42f` failures retain their own scope.

This trial changes host architecture, image and resource capacity together, so a
later success cannot isolate a cause or qualify the prior arm64 host. The same
24 smoke guards, Xcode guards, model tests, four actual macOS rendering methods,
clean-cache assertions, unsigned build, both device families, command/job
deadlines, explicit successful-launch termination, owned cleanup and retained
failure diagnostics remain required. There is no retry or success fallback.
Fresh source and actual receiving checks must qualify this changed environment.

The [#22 ADR](../docs/decisions/issue-22-platform.md) retains its initial
`macos-15` package-workflow observation and the selected Xcode toolchain. This
host choice is limited to the native UI job; package and submission-SDK workflows
are unchanged. It does not add a product platform, physical-device observation,
minimum-OS coverage or broader native/release acceptance.

**Separate mandatory rendering and simulator jobs — 2026-10-19.** The first
Intel trial at actual receiving checkout
`2e3f97e1889b45b05d765ea55ebe73eba5e70d81` is still
[cancelled](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/317#issuecomment-6262744418).
Its four macOS rendering methods passed, the unsigned app built, and the phone's
single launch returned PID 26970 before successful termination, shutdown and
deletion. The tablet was then created and booted, but the job stopped during its
boot-readiness command. There is no tablet installation, launch or cleanup result.
The [original check annotation](https://api.github.com/repos/Pick-Your-AI/pick-your-ai-apple/check-runs/117937750065/annotations)
confirms the overall 20-minute job limit. It does not explain the slow rendering,
boot readiness or installation, and the earlier arm64 launch failure remains open
under its own source and evidence.

The workflow now runs two separately required jobs from the same event checkout:

| Job | Required work and original artifact |
| --- | --- |
| `native-evidence-rendering` | Exact Xcode verification, fresh-cache checks, actual toolchain recording, all six real macOS rendering methods and the unchanged strict rendering qualifier; `native-evidence-rendering` retains the log and result bundle. |
| `native-simulator` | Xcode-pin, smoke-runner and SDK guards; exact Xcode 26.3 / SDK 26.2 verification, fresh-cache checks, actual toolchain recording, all 25 current model methods, unsigned Simulator build and product-metadata verification, and both phone/tablet launch sequences; the existing `native-local-drafts-evidence` artifact retains their outputs. |

In that split trial, each native job used its own fresh standard `macos-15-intel` host and retained the
same 20-minute job limit. The rendering command, source and qualifier are moved
unchanged. The simulator runner, every individual command deadline, single-attempt
behavior, device/runtime selection, explicit termination and owned cleanup are
unchanged. No app or cache is transferred between jobs. Each always-run artifact
step retains its own actual inputs and failures for 14 days.

The existing `native-ui` check is a short completion gate with no source checkout,
build or simulator operation. It waits for both native jobs and checks their
literal results even when a dependency fails or is skipped. A successful scope
result with `native_required: true` requires both native jobs to succeed; an
explicit audited `false` requires both to be skipped. A failed scope, missing or
unexpected output, or any failed/cancelled/unexpectedly skipped required job fails
the gate. The original conservative scope condition still selects both native
jobs together. GitHub documents [dependent-job conditions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idneeds)
and the [always status function](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#always)
used by this bounded result-only gate.

The split removes unrelated rendering work from the simulator job's elapsed-time
budget; it does not extend that budget or promise the remaining work will finish.
Both new jobs still need their own successful actual receiving execution and
artifact qualification before this source can complete the native gate. A later
success cannot identify the cancelled run's performance cause, qualify the prior
arm64 host or supply physical-device, minimum-OS, accessibility-journey or release
acceptance. The original cancelled run, failed arm64 run and all earlier receipts
remain historical observations rather than results of this new composition.

### Install-phase observations after the split (2026-10-19)

The first split receiving checkout, `2bc6470804faa49af19b19aa8998e0e5e7d18fe0`
(tree `2df9e20d35a22471935290fc3ed8245cfcb32390`), kept the two native outcomes
separate. Its [rendering job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39224938072/job/117968907685)
passed all four real methods. Its [simulator job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39224938072/job/117968907682)
passed the eight pin guards, twenty-four smoke guards, twenty-three model methods
and unsigned build, then failed during the first phone's installation. The
required `native-ui` completion gate correctly rejected that mixed result.

The literal host selected Xcode 16.4 / 16F6, Swift 6.1.2, x86_64 macOS 15.7.9 /
24G830 and the available iOS 26.2 / 23C54 runtime. Creation, boot and the
300-second-bounded boot-status command returned success. Installation timed out
at its unchanged 180-second deadline. Cleanup attempted both commands: shutdown
timed out at 60 seconds and deletion returned success. No launch command or PID
was observed, and the tablet sequence did not start. This is an installation
failure, not the earlier launch timeout or outer-job cancellation.

That source collected runtime snapshots only after installation. Consequently,
the failed original has no snapshot of the host or owned services around this
install boundary. Its selected versions and available-runtime flag do not
establish a toolchain mismatch, health, saturation or another cause. The
earlier successful Intel phone remains a separately identified observation.

This extension reuses the existing filtered resource, process and owned-service
probes immediately after successful owned boot readiness, before installation,
and after an installation timeout, nonzero exit or unavailable command. Each
probe still has its three-second deadline and the same field, row and character
limits. Partial or failed probes remain explicit observations; they neither
replace the original install error nor prevent the remaining cleanup attempts.
There is no app-container query or app-log claim before installation succeeds.
The observations can perturb timing and supply no native fix or causal result.

The portable suite now has twenty-nine methods. All original seventeen method
bodies and six earlier snapshot method bodies remain unchanged. The earlier
test forbidding snapshots before successful installation is deliberately narrowed
to creation and boot failures. Three additional methods check both successful
destination sequences, install timeout/nonzero/unavailable errors with failed
diagnostic probes and cleanup, and a tablet install failure after phone cleanup.
They preserve original exception identity or nonzero status, partial output,
one install attempt, exact owned IDs, and the required launches on success.
Two additional methods cover collector and observation-output exceptions on
successful and failed installs, and real bounded child probes with filtered
partial output. The installation-only wrapper reports only the exception type
if collection fails and tolerates failure of that observation sink. It preserves
the original install result and the existing owned cleanup attempts.
Each reached installation phase adds nine nominal probe seconds plus process
and output overhead; it supplies no job-completion guarantee.
These are portable regression cases, not a new simulator execution.

This installation-observation revision preserved the split workflow, required
result gate, both device families, selected toolchain/runtime, every command
deadline and both 20-minute job limits. All earlier guard counts and failed,
cancelled or successful native observations above retain their original source
and run identities.

### Simulator toolchain continuation (2026-10-19)

The next actual receiving checkout, `3b4624f94742da16d4f0c7044ab9fd7c95bdf43c`
(tree `638edd7f86b562de783b1907b46c89fe59283c0d`), failed earlier, during
[first-phone boot readiness](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/317#issuecomment-6265594183).
Its inventory, creation and boot commands returned success, but the single
300-second `bootstatus` attempt retained only nonterminal progress through data
migration and then waiting for the system app. Owned shutdown timed out at
60 seconds, deletion returned success, and the original boot-readiness exception
remained the failure. Installation, all runtime-snapshot phases, app launch and
the tablet sequence were never reached. The job completed as failed within its
20-minute limit; this was not another outer-job cancellation.

The original selected Xcode 16.4 / 16F6 on Intel macOS 15.7.9 / 24G830, built the
unsigned app with SDK 18.5, and selected the available iOS 26.2 / 23C54 runtime.
Apple's [Xcode support matrix](https://developer.apple.com/xcode/system-requirements/)
lists macOS Sequoia 15.6 through Tahoe 26.x and SDK 26.2 for Xcode 26.3. Its separate Simulator
range for Xcode 16.4 is iOS 15 or later; this does not establish that the original
16.4 / 26.2 pairing is prohibited. The
[exact official Intel image inventory](https://github.com/actions/runner-images/blob/macos-15/20260824.0482/images/macos/macos-15-Readme.md)
for image `20260824.0482.1` lists Xcode 26.3 / 17C529 and the iOS 26.2 Simulator
SDK and runtime. Published compatibility and co-installation do not establish
successful cold boot on the failed host.

The bounded next trial changes only the simulator job's selected Xcode bundle,
compiler, SDK and Simulator tools together. It reuses the existing
[submission toolchain pin](submission-toolchain.json),
[SDK pin](submission-sdk.json) and guarded verifier. Exact Xcode identity and
both installed SDK versions must match before the verifier publishes
`DEVELOPER_DIR`; there is no alternate-toolchain or SDK fallback. The job also
runs the existing 17 SDK guards and verifies the unsigned Debug Simulator
product's Xcode build, SDK 26.2 and minimum iOS 17 metadata. The earlier SDK 18.5
build remains evidence only for its original source and run.

The standard Intel host, newest-available-runtime selection, fresh owned phone
and iPad, 29 smoke guards, model methods, clean caches, all command deadlines,
both 20-minute job limits and strict required result gate remain unchanged.
The 16.4 rendering/package baseline and separate submission workflow also remain
unchanged. This experiment adds no retry, readiness shortcut, runtime download or
destination reduction. It changes coupled toolchain inputs, so even a later
success cannot isolate the old failure's cause or qualify the old environment.

The next configured execution must record its actual image, Xcode, SDK and runtime
and complete both full cold-device launch and cleanup sequences. Portable guards
and product metadata cannot supply those native results. The first-phone boot
failure, earlier installation and launch failures, cancellation histories and
broader physical-device, minimum-OS and release criteria remain separately open.

### Boot-phase observations after installation instrumentation (2026-10-19)

The next original [simulator job118003120297 / run39235369439](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39235369439/job/118003120297)
failed before installation. Its valid-signed checkout was
`3b4624f94742da16d4f0c7044ab9fd7c95bdf43c`, tree
`638edd7f86b562de783b1907b46c89fe59283c0d`, receiving source
`fe600b20b9d3d035f8e1be1b13e766c7458b8023` on accepted `76f84345`.
The [independent original qualification6265594183](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/317#issuecomment-6265594183)
records eight pin guards, twenty-nine portable smoke methods, twenty-five current
model methods and the unsigned Simulator build passing. The twenty-five model
methods include the separately accepted delayed-open regressions; earlier
23-method observations keep their original source identities.

The original selected Xcode 16.4 / 16F6, Swift 6.1.2 on x86_64 macOS 15.7.9 /
24G830 and available iOS 26.2 / 23C54 for an iPhone 17 Pro. Creation returned a
verified new UUID and `boot` exited zero, but `bootstatus -b` timed out at its
unchanged 300-second deadline. Its retained status progresses through BackBoard
and migration to Waiting on System App; it does not identify a single stalled
service or a cause. The subsequent shutdown timed out at 60 seconds and deletion
succeeded. No installation, app launch, tablet or phase snapshot was reached.
The source and all original failures remain retained, including the separate
install failure and earlier launch/cancellation observations.

The highest available iOS runtime remains the intentional smoke profile; a
missing family still fails without falling back to an older runtime. The exact
original inventory contains the runtime's availability, build and supported
architectures, its device-type mapping and the selected device's runtime range.
The unchanged command log binds the fresh UUID to that runtime/device, and the
existing toolchain artifacts retain the actual selected Xcode, SDK and host.
Apple's [Xcode compatibility matrix](https://developer.apple.com/xcode/system-requirements)
distinguishes the SDK included with Xcode from its supported Simulator OS range;
the SDK version alone is not treated as an upper runtime limit. No runtime,
device, toolchain or architecture substitution is introduced by these observations.

After successful creation and fresh-UUID validation, this extension reuses the
existing filtered load, memory, process and owned-service observations immediately
before boot, and after an operating-system/subprocess failure of either `boot` or
`bootstatus`. Its `before-boot` and `boot-failed` records preserve the actual boot
error, status and partial output. The generic best-effort observation wrapper
also retains the existing installation behavior. Collector or output failures
report only an exception type when possible; they cannot replace boot/install
success or failure or prevent both owned cleanup attempts.

Each probe retains its three-second deadline, fixed fields, forty-row and
4,096-character limits. A service query against the newly created, still-unbooted
device can fail or time out; that is an unavailable observation, not proof of
missing services or an extra boot attempt. Each reached phase adds at most nine
nominal probe seconds plus process/output overhead. Observations are sequential,
can perturb timing and are not a process history, readiness repair or explanation
of the original timeout. There is no added app-container query, readiness poll,
retry, destination fallback or simulator creation.

The portable suite now contains thirty-two methods. Twenty-four of the preceding
twenty-nine method bodies remain byte-exact. Five existing methods explicitly
extend their ordering/count assertions for the added phase or narrow the no-probe
boundary to unverified creation. Three new methods cover both boot commands,
phone/tablet failures, timeout/nonzero/unavailable outcomes, failed cleanup,
collector/sink failures and the filtered resource/service observations. They
retain the primary exception or status, one boot/readiness attempt, successful
phone completion before a tablet failure, and both successful launches on the
positive path. The existing real-child deadline controls remain part of this
portable suite. These controls do not execute Xcode or a native simulator.

The workflow, both required native jobs, result gate, both device families,
exact toolchain checks, command deadlines and 20-minute job limits are unchanged.
This source needs its own actual current-composition hosted qualification; adding
observations alone does not qualify the failed readiness or either device family.

This observation source was independently reviewed on the preceding runner.
Its composition retains the selected toolchain continuation above, including
all seventeen SDK guards and unsigned product inspection. The earlier trial's
twenty-nine smoke-method and fifty-four total portable-method observations
keep their original source; they are not thirty-two-method or new native results.

| Issue / acceptance contribution | Implementation and check | Remaining evidence |
| --- | --- | --- |
| #26 pinned clean checkout; #30 native CI | Checked-in project/local packages, explicit Xcode pin, actual CLI missing-pin regression and isolated-cache workflow | Exact-head hosted evidence and receiving review; #30 untrusted-PR and release-secret gates remain separate |
| #28 restore correct draft | SceneStorage selection, explicit dirty-discard guard, background save attempt | Cold-link routing, process-kill replay and physical lifecycle qualification |
| #80 local library operations | Create, title edit, duplicate, confirmed delete; real-store model tests including reopen | Complete build metadata/organization and receiving review |
| #87 offline editing | All operations use local storage; unknown compatibility/pricing always explicit | Governed catalog cache and downstream evaluation integration |
| #105 accessibility | System controls, visible labels, Dynamic Type, editor/action identifiers | Automated complete journeys, VoiceOver, large text and physical device audits |

Save is acknowledged only after storage commits. Failed saves preserve the in-memory
input and display a retry notice; revision conflicts never overwrite newer revisions.
The user can explicitly discard edits and reopen to load the current revision. Drafts
with unsupported editor payloads cannot be opened for editing. Unreadable storage rows
remain stored and are disclosed by count. Selection restoration opens only committed
content. Background save is best effort: force termination can lose unacknowledged
edits. Revision history is paged in bounded groups of 20. Explicit restoration
requires confirmation and clean current input, appends a new revision, preserves
later saved history, and rejects stale compare-and-swap revisions or unsupported
editor payloads. Restored notes never become current compatibility or pricing evidence.
New binding edits arriving during restoration remain dirty. Lifecycle save requests
arriving during an operation are drained afterward with the latest editor contents
and committed revision; they are not silently dropped by the busy flag.

Seven additional model regressions cover restore/reopen/history retention, dirty and
concurrent edit guards, binding updates during restore, bounded history, unsupported
history, and background saves during paused history/restore operations. These are
controlled actor-boundary tests, not simulated OS termination or end-to-end UI taps.
Undo/redo, timed autosave, process-kill during UI autosave and physical lifecycle
qualification remain work under #69. Hosted exact-head compilation and model tests
are required before this slice is accepted.

Storage opens in Application Support under a directory protected until first unlock.
A failure shows an unavailable screen and never resets the database. Locked-device
and low-storage behavior still require physical-device qualification.

Primary Apple references checked 2026-10-18: [scene phase](https://developer.apple.com/documentation/swiftui/scenephase),
[file protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication).
Local Linux inspection cannot establish SwiftUI/Xcode correctness. See the PR checks
for observed hosted results, distinct from device, store or production acceptance.

## Pinned toolchain

[toolchain.json](toolchain.json) pins the full Xcode bundle to version 16.4, build
16F6, at /Applications/Xcode_16.4.app/Contents/Developer. Install that exact release
from [Apple Developer downloads](https://developer.apple.com/download/all/) and open
it once to finish component and license setup. The command-line-tools-only package
does not contain the app's iOS SDK. Simulator runtimes are recorded separately in
each native artifact; launch smoke checks do not qualify physical devices.

Run commands from a fresh repository checkout through the verifier:

```sh
python3 App/scripts/toolchain.py -- swift test --package-path Packages/PlannerUI
python3 App/scripts/toolchain.py -- xcodebuild -project App/Planner.xcodeproj -scheme Planner -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/native -clonedSourcePackagesDirPath .build/native-source-packages CODE_SIGNING_ALLOWED=NO build
python3 App/scripts/toolchain.py -- python3 App/scripts/simulator-smoke.py
```

The verifier checks the selected directory and exact version/build before executing
the command with that bundle's DEVELOPER_DIR. It reports installation/setup
instructions and exits with status 2 for unavailable, malformed, mismatched or
unresponsive pins. It propagates the native command's exit status. The native
workflow publishes the verified directory to later steps only after validation.

All five checked-in Swift packages currently use repository-local package paths or
system SDK libraries. Their source revision is the checkout commit; there is no
remote Swift package version to resolve to a replacement. The native workflow
asserts that its explicit SwiftPM cache/scratch, Xcode package and derived-data paths
are absent, then builds using those paths without a cache restore. See
[toolchain validation](../docs/validation/toolchain-pin.md) for the actual CLI
negative case and the required hosted failure/recovery and clean-build evidence.

Apple's [command-line tools configuration](https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings)
documents the command-scoped DEVELOPER_DIR override; [TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)
describes the full Xcode command-line tools and build commands.

## Submission SDK compatibility

The separate [unsigned submission SDK lane](../docs/validation/submission-sdk.md)
selects Xcode 26.3 / 17C529 and verifies device and simulator SDK 26.2 before
testing all five packages and building both unsigned Release products. The
existing 16.4 development pin remains a regression baseline. Consult the dated
[#113 policy matrix](../docs/validation/issue-113-policy.md) for current Apple
requirements and the signed-artifact, privacy and channel evidence still needed.
The native simulator launch job now reuses these pins and verifier for its Debug
product; the separate Release-product lane does not supply its required launch
or cleanup results.

## Launch observation failure boundary

The `before-launch` and `launch-failed` snapshots use the same guarded
`observe_runtime` path as boot and installation. A collector exception or an
unavailable observation output must not prevent the single launch attempt,
replace its original failure, or skip its two bounded launch diagnostics. The
existing owned shutdown/delete cleanup still applies. Commands, destinations,
deadlines, runtime selection and successful-launch requirements are unchanged.

A controlled Python probe on accepted source `0e289d81428068a0a3196cde064fda536c71691b`
preserved two normal controls and demonstrated four violations: collector and
output failures before launch prevented the attempt, and those failures after a
launch timeout replaced its exact exception and skipped diagnostics. These are
synthetic exception-ordering observations, not a cause assigned to any historical
macOS simulator failure. Four new portable regression methods cover both device
families, exact original failure identity, both diagnostic commands, owned
cleanup, redaction and unchanged deadlines. All 32 earlier smoke test methods
remain unchanged. Run the complete focused suite with
`python3 -m unittest discover -s App/scripts/tests -p 'test_simulator_smoke.py' -v`.
Actual changed-runner native qualification remains separate.

Captured command text replaces undecodable bytes so a malformed diagnostic
stream cannot erase a successful creation UUID, hide the actual exit status, or
interrupt owned cleanup. These logs contain decoded text with replacement
characters; they are not byte-exact raw process output. Returned UUID and
inventory text still pass the existing parsers, nonzero statuses still fail,
and unsuccessful deletion still prevents a successful smoke result.

Four additional portable methods use real Python children to cover success,
nonzero exits, valid creation output with malformed stderr, a real launch
timeout followed by both owned cleanup attempts, and a failed deletion. All 43
preceding method bodies remain unchanged. These controlled child processes
demonstrate exception ordering; they do not assign a cause to any historical
simulator failure or establish native recovery.

## Standard ARM simulator runner trial (2026-10-30)

The simulator job now selects the standard `macos-15` ARM runner; rendering
remains on `macos-15-intel`. This changes one runner pin and the simulator host
architecture. Xcode 26.3 / 17C529, SDK 26.2, fresh caches, the newest available
runtime and first iPhone/iPad device selection, every guard, single launch
attempt, command deadlines and the 20-minute job limit remain unchanged.

At source `b258f6859e7f4e74f8dad7306b033469a6d686de`, the three Intel attempts
in [run 41133558633](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/41133558633)
did not qualify simulator execution: the first timed out during launch, the
second during boot readiness, and the third exceeded the job limit during
iPad installation in the launch-sequence step. Their retained logs and artifacts
remain failure evidence. High host
load was observed, but it does not establish the cause.

The separate submission-SDK [run 41133558749](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/41133558749)
successfully used this ARM image with the same Xcode/SDK; it did not qualify
simulator boot or launch. This new trial still requires its own successful
native checks and evidence. It executes arm64 simulator slices only and does
not qualify x86_64 simulator execution; Intel macOS rendering supplies no such
coverage. Earlier ARM and Intel failures remain historical evidence. A later
success cannot isolate their cause, qualify those prior runs, or establish
physical-device, minimum-OS, signing, store or production acceptance.
