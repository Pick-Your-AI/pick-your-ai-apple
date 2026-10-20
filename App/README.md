# Native local draft preview

This unsigned iPhone/iPad app composes `PlannerUI` and `PlannerData`. It is a local
editor with a separate local imported-build library, reviewed JSON file export and
a separately reviewed proposed-plan text report. The report is not a private
Build/Manifest pair or a deployment action.
The Demo catalog tab browses a pinned, explicitly synthetic fixture and its typed
component details; compatibility and price remain unknown. A selected imported
Build can open a local T6 declaration review. No ordinary compatibility evaluator,
account, remote sync or release configuration is connected. The reserved
`invalid.pickyourai.localpreview` bundle ID is for simulator
use only; it does not allocate a production application identifier or signing team.

The [accepted #22 ADR](../docs/decisions/issue-22-platform.md) selects SwiftUI with
native adapters, iPhone/adaptive iPad on iOS/iPadOS 17, and the local SQLite actor
implemented in PlannerData. Preserve those module boundaries; product, device,
service and release receiving acceptance retain their separate criteria.

On macOS, use the [pinned toolchain setup and commands](#pinned-toolchain) below.

The workflow records the actual compiler/SDK/runtime and runs model tests, an unsigned
simulator build, iPhone/iPad launch smoke checks, and seven XCUITest journeys on each
pinned UI-test destination: local notes with production autosave, durable undo/redo
and discard recovery; catalog filters, pagination, relaunch and exact details; and
four T6 journeys using two explicitly synthetic retained-review scenarios, including
report disclosure/Files cancellation and actual tab withdrawal; and the planning-input
edit, acknowledged-save, relaunch and revision-restoration journey. It contains no signing
secrets. The launch-only smoke script remains a separate check; see the
[UI journey evidence and limits](UI_JOURNEY.md).

The exact canonical editor `8e76d0ee` has an actual 71-model pass and complete
Notes journey passes on both pinned simulators, with successful owned cleanup;
see the [completed editor receipt](../docs/validation/editor-integration.md#completed-corrected-editor-execution).
Its separate scope-cleanup failure remains recorded. The earlier 110 UI / 57
Transfer composition is historical input. That earlier preparation required all
235 UI and 209 Transfer methods plus all seven complete journeys on each destination;
none of those expanded results is inferred from the earlier editor run.

## Current receiving source and required validation

### Current accepted-main cache-validator composition through #433

This source preserves the reviewed `88a704c9` integration and receives accepted
main `09667e27`. Its three exact additions provide the
[whole-artifact cache validator](../Packages/PlannerTransfer/CATALOG_CACHE_VALIDATION.md),
ten focused methods and that contribution's guide. Validation passes original
bytes to the existing decoders; it does not grant cache production, graph,
source-use or current-check authority. The existing iPad interactions and all
their assertions remain unchanged.

Required declarations are **151 Core, 84 Data, 275 Transfer, 92 Catalog and
235 UI: 837 total**. Transfer adds the ten exact `CatalogCacheValidatorTests`
identities to the complete prior 265. The dedicated Transfer and submission-SDK
jobs select `integrated-catalog-cache-transfer`; all 27 preceding profiles remain
exact for their own original sources. Data and UI keep their existing strict
84/235 profiles.

The one added Swift test file expands direct receiver inputs from 51 to **52**.
All 17 portable control identities remain; the current-source comparison,
same-count substitutions and padded-history rejection include the new profile.
The earlier 51-input control result and 265-method Transfer original retain
their actual `26543` source. They do not execute these expanded inputs. All seven
App journeys on each configured destination, six Evidence methods and three Cost
methods remain required. No new control or native execution is claimed by this
source inventory.

### Historical accepted-main composition through #431

This source preserves the reviewed iPad interaction correction at `a924668d`
and receives accepted main `49bf4d59`: strict JSON pin admission (#432), local
conflict preparation (#429), caller-supplied pending-write dispatch (#425), and
immutable reported-summary projection (#431). All existing app interactions and
their assertions, including the separate iPad correction, remain intact.

The required package declarations are **151 Core, 84 Data, 265 Transfer,
92 Catalog and 235 UI: 827 total**. Data is the prior 69 plus 15 exact dispatcher
methods. Transfer is the prior 226 plus 15 exact conflict and 24 exact summary
methods. Storage and submission SDK select `integrated-dispatch-data`; Transfer
and submission SDK select `integrated-summary-transfer`. Each profile requires
every named identity exactly once, a passing result, and the exact aggregate.
All 25 preceding profiles remain unchanged for their historical source scopes.

The three new package test files expand the receiver's direct source inputs from
48 to **51**. The existing 17 portable receiver controls now require the exact
84/265/235 source groups and reject every same-count identity substitution and
padded preceding receipt. No prior 48-input execution qualifies those expanded
controls. All seven App journeys on each configured destination, six Evidence
methods and three Cost methods remain required. No local control or native run
is claimed for this composition; its ordinary configured current-source jobs
must supply their own results. Earlier counts and outputs below remain tied to
the named source that actually produced them.

### Historical 7f composition and its original boundaries

The [current receiving record](../docs/validation/receiving-main7f-row-cost.md)
joins reviewed donor `3476c279` (retaining exact row/details source `70c45be7`)
with accepted main `7f16020b` and all prior source corrections.
Required package declarations are **151 Core, 69 Data, 226 Transfer, 92 Catalog
and 235 UI: 773 total**, with all seven App journeys, six Evidence methods and
three Cost methods still required in their configured native lanes. The Transfer
gate selects `integrated-alternative-transfer`; every earlier profile remains.
The new accepted Transfer file expands the portable inventory to 48 direct inputs,
so an older 47-input observation cannot qualify this composition.

The same record preserves the actual failed iPhone, iPad and macOS Cost originals
and the test-only macOS accessible-text observation correction. It establishes no
new native pass, whole-issue acceptance or main delivery. The separate journey
command/job allowances are 2,700 seconds and 55 minutes; their sufficiency remains
unproved, and the simulator-inventory limit stays 60 seconds. The original 438
portable observation passed 17 controls in 1.579 seconds; only its 48 exact inputs
are reused here, with no new execution claim. The following earlier receiving
record retains its original revisions and counts; its 209 Transfer /
756 package inventory is not the requirement for this new source.

#### Focused corrections from the 7d4b iPad original

The [new iPad original](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39432580815/job/118664487819)
checked out receiving `7d4b87c5` for public `3642efe9`. Its 41 portable runner
controls passed in 0.363 seconds. Of the seven required native journeys, Catalog
and three T6 methods passed; the planning-history, saved-notes and report/Files
methods failed, with five assertion reports in 1,025.671 seconds overall. These
are the original results before the following corrections, not results for the
new source.

The planning failure accepted a severely clipped Load saved revisions control:
only its top 16 points intersected the editor Form. The actual tap was inside that
visible strip, so a missed model action is not established. The test then waited
for revision-title rows without revealing the section below the button. Its
existing Form-scoped helper now requires the complete target frame inside the
usable viewport below the editor navigation bar. After the single Load action,
the first or exact required revision title gets its own bounded reveal before
the existing ten-second existence and exact title/revision assertions. Each
reveal retains six attempts and the existing drag parameters; the additional
post-load reveal adds bounded interaction work. No history query, storage
operation, revision ordering or acknowledgment assertion is replaced.

The report original tapped the wide disclosure row at its label center. The
retained hierarchy still showed the separate intrinsic switch off and Save
disabled. The journey now admits exactly one leaf switch inside that identified
disclosure, verifies its initial off state, activates it once, and requires both
the on state and an enabled, hittable Save within a five-second state wait.
Failure returns before attempting Save or Files cancellation. All preview,
private-field omission, disabled-before, real Files cancellation and retained-plan
postconditions remain. This adds explicit bounded readiness/state observation;
it does not bypass disclosure or model admission.

The recognized keyboard gesture tutorial remained after its single centered
200 ms Continue press and covered the keyboard-toolbar Done editing control.
On iOS, that one focus-only control now appears in the editor navigation toolbar
while a field is focused, with the same identifier and `focusedEditorField = nil`
action. The other platform's keyboard toolbar and both Save/Close actions and
enabled rules remain. This is a production usability change; its native placement
and activation still need current-source execution. Only the recognized tutorial
branch invokes the existing keyboard-dismissal helper, then still requires the
keyboard, Continue and instructional text to disappear and the actual pasted
value to remain exact. The real paste still exceeds the store's 1,024-byte
boundary. No Return behavior, repeated Continue activation, operating-system
setting or injected application state is assumed.

All seven required App method identities and the package method inventory remain.
These source corrections establish no new native pass, simulator fix, full
acceptance or main delivery. The configured current-source native gates retain
their original duties.

#### Evidence from a pending simulator inventory attempt

The [04b iPad original](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39398429701/job/118548102048)
passed its 29 portable controls, then the single `xcrun simctl list --json` call
timed out after 60 seconds with empty retained stdout/stderr, before device
selection or App build. Its cause remains unresolved. The runner now preserves
that exact command, timeout, output streams and original error while a macOS-only
observer waits 20 seconds for the same attempt to remain pending.

The observer has a separate ten-second command budget. It retains whitelisted
image/toolchain metadata and one `ps` table containing PID, parent PID, reported
start time and command, without argument or environment columns. At most two
inferred candidates are eligible for one-second `sample` observations: the unique
inventory child candidate and unique `simdiskimaged`. Each gets a bounded identity
recheck first; ambiguity, disappearance or changed reported fields prevents that
sample. These snapshots do not provide a race-free process handle or verified
binary identity. Sampling permission failures remain diagnostic results.

When inventory returns or fails, cancellation terminates/reaps only observer-created
diagnostic children, and the caller allows at most one second for the observer
thread to finish. That separate shutdown allowance does not change the inventory
command's 60-second deadline or its recorded duration. Diagnostic OS process
creation and file I/O cannot be forcibly interrupted. Directory creation, the
initial `inventory-observer/pending.json` marker and the final `observation.json`
all belong to the daemon; starting or stopping it performs no diagnostic file or
stream I/O on the inventory caller. A pending marker without a final record means
no completion was retained. Failed or blocked setup may leave no marker, and
missing evidence never proves completion. Optional observer errors cannot replace
the inventory outcome. All observer files stay inside the fresh
owned evidence directory and follow its existing artifact retention. No additional
inventory, service control, privilege escalation, runtime installation or retry is
introduced, and this change establishes no native pass or runtime fix.

The scope follows Apple's [narrow simulator backtrace guidance](https://developer.apple.com/forums/thread/756767)
and [documented sample duration/interval](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/LaunchTime/Articles/MeasuringLaunch.html).
The portable observer controls exercise process ownership and failure preservation;
real Apple diagnostic behavior still needs its own current-source hosted result.

### Earlier receiving record

The [integration record](../docs/validation/imported-build-integration.md) names the
actual 2026-10-19 selection, immutable donors, current-module joins and remaining
receiving gates. The fixed preparation selected on `888cb7e7` carried accepted
main through `0e289d81`; the preceding composition carried accepted `7431b7d6`.
The reviewed planning composition receives accepted main `4632c72a` and
the exact planning donor `3f7f48ec`, with their boundaries below.
It does not recover an absent old #198 tree or deliver its signed
staging branch to main. The separately prepared T6 report/route follow-up starts
on published #391 source `9e7cc629`, with the exact donor `394ff3ba` and
[explicit route ownership](../docs/validation/imported-build-integration.md#t6-report-and-route-lifecycle-follow-up).
Its local source checkpoint is not a native or main-delivery observation. The
[current-main intake](../docs/validation/imported-build-integration.md#accepted-ruleset-cache-adapter-carry)
preserves the bounded SDK inputs, regular-file admission, accepted catalog-envelope delivery and later
documentation changes with their original source identities. The existing
Build configuration comparison is independent of the separately owned catalog
component comparison in #365.

Opening, forking or deleting the selected imported snapshot updates its T6 owner
synchronously with complete Build equality. Local label changes retain the same
immutable Build; changed locks, another fork or selected deletion retire prior
T6 inputs, compatibility and pending picker authority. Ordinary navigation begins
without a compatibility result. The user explicitly reviews retained quality and
proposed deployment declarations; no service, default pass, approval or execution
is manufactured. The original six real-store binding tests remain exact. Eight
additional receiver methods specify the captured full-Build route, actual tab
withdrawal, stale callbacks, selected closure/deletion and fresh recovery.
Six further callback regressions specify the separately identified
[stale child-disappearance correction](../docs/validation/imported-build-integration.md#route-captured-child-disappearance-correction):
completed and pending no-Files reviews, both current-route cancellation controls,
and live importer/exporter protection. The original eight method bodies remain.

Six test-only exact-fixture controls now require direct raw admission, complete
no-op value preservation, unrelated-mutation fraction preservation, quality
threshold/false preservation and rejection of floating or bridged numeric inputs.
The four T6 test families use the existing exact Transfer parser/value encoder;
their original method bodies, raw fixtures and production numeric limits remain.
The [fixture correction record](../docs/validation/imported-build-integration.md#exact-t6-fixture-mutation-correction)
preserves the actual older 52-failure native observation separately from the
new source and portable controls. It claims no corrected native execution.

Files intake additionally requires the seven [descriptor admission regressions](../docs/validation/imported-build-integration.md#regular-import-descriptor-admission).
The existing security scope, URL preflight, cancellation and byte limit remain.
Nonblocking open and a regular-type check on the actual descriptor prevent a
pathname replacement from turning that intake into a blocking FIFO read.

The App reports tab withdrawal synchronously before changing selectedTab. The
library uses a separate opaque route for each T6 presentation; a stale Back
binding cannot cancel a reopened same-Build route. Files temporarily covering
the view preserves its exact owned request. The destination also captures that
same route for its MainActor disappearance callback: a callback from an old child
cannot cancel a reopened review, including when no Files request is active.
Back navigation, another tab, selected
closure/deletion or a replaced library owner cancels it explicitly. Closing the
selection preserves every stored row. Report disclosure and source rights remain
separate; a successful system callback is only a reported file-save result.

Only an explicitly selected Debug UI-journey argument admits the two synthetic T6
scenarios. Each such app launch uses a fresh temporary library, preserves the exact
three donor fixture byte strings and visibly labels its record synthetic. Its
synthetic compatibility report uses the existing analysis store. Release builds
contain neither that fixture path nor its bytes. Ordinary app launches create no
fixture and receive no synthetic report. The source-defined two original T6 test
bodies remain unchanged; their shared navigation helper uses the same adaptive
button lookup as the existing catalog journey and bounded scrolling in the exact
imported-build Form. The donor third Files-cancellation body is also exact; the
fourth T6 journey exercises actual tab withdrawal, reopen and retained-input retry.

| Mandatory current job | Exact selected work |
| --- | --- |
| `native-evidence-rendering` | All six accepted real macOS Evidence methods and strict receipt, including Gregorian capture dates and localized claim copy, Xcode 16.4, unchanged 20-minute job. |
| `native-simulator` | Existing Xcode 26.3 / SDK 26.2 selection, Xcode-pin, smoke-runner and SDK guards, all 235 UI methods, unsigned Debug build and both highest-runtime fresh smoke destinations; unchanged 20-minute job and command deadlines. |
| `native-cost-rendering` | Three real macOS Cost methods and their strict receipt, Xcode 16.4, separate 20-minute job. |
| `native-ui-journey (iphone)` and `(ipad)` | All seven app journeys on each fresh pinned 18.5 destination, 41 runner controls, separate 55-minute jobs and a bounded 2,700-second inner test limit. |
| `native-ui` | Result-only aggregate requires successful scope and every selected job's success; only an audited false scope permits all native jobs to skip. |

The inventory runner retains evidence from the same single 60-second
`xcrun simctl list --json` call before device selection. File-backed stderr,
partial stdout and a structured attempt record preserve the original command
failure even when secondary evidence or diagnostic I/O fails. A successful
command still cannot proceed if required evidence retention fails. The five added
portable controls make 29 runner controls; all 24 earlier methods remain exact.
The [reviewed diagnostic source](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391#issuecomment-6284168303)
and [close-error finding](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391#issuecomment-6284203858)
retain their original observations. This change does not establish the cause of
the CoreSimulator delay or turn either failed native original into a pass.
All seven real journeys and existing ownership, selection and cleanup gates
remain required; the inventory command, timeout and attempt count are unchanged.

The original [iPad journey job 118384069059](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39347486216/job/118384069059)
on prepared `5e111f687139dee1533f3d92f47e7a142df0df7a` timed out after 900 seconds.
Its cold build and setup consumed approximately 379 seconds; only the first of
seven selected methods began and none completed. Retained artifact `12236051485`
(SHA-256 `46ca786235cb1f658e5355eae8fca14a59fdff07ee512221f00921f3883e07ec`)
records the command timeout, incomplete result summary, failed acceptance and
successful owned-simulator shutdown/deletion. This does not prove a product
assertion failure. The 45-minute command allowance and 55-minute job limit leave
bounded room for the full selection, cleanup and original-artifact retention;
their sufficiency still requires completed native execution. All seven exact
method identities, failure/skip rejection, ownership and cleanup checks remain.
The separate [iPhone inventory timeout](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39347486216/job/118384069103)
occurred at the existing 60-second simulator-discovery limit before a journey
started; that limit and the failed original remain unchanged.

Core retains every existing package, mutation, guard and Evidence-rendering step
and adds the three Cost methods on each pinned simulator. Storage requires all 69
methods: 34 retained draft cases and 35 accepted pending-write cases, with both
actual crash/recovery probes. The strict Data receiver checks every identity in
the macOS, iPhone, iPad and submission SDK logs. Transfer requires 209 exact methods,
the original nine reference phases and the separate Manifest controls. Submission
SDK requires all five packages (151 Core, 69 Data, 209 Transfer, 92 Catalog, 235 UI; 756 total),
all current App guards and both unsigned Release products with their separate SDK
and privacy receipts. Static inventories are not execution observations.

The current carry preserves the accepted evidence-date presentation and adds the
sixth localized claim-copy method, with its exact English/German/Arabic resources, the native package-path preflight before mutation-output cleanup,
the maintenance runbook and the exact #317 smoke source. The combined Transfer
receiver keeps the same nine reference phases now accepted through #285 at
`b35414a8`; this source carry does not reexecute their earlier receipts.
Earlier four-method rendering results remain observations
of those earlier inputs; they do not execute the added date method.

The complete Core/native UI scope footprints include this UI package's Catalog
and Transfer dependencies. The historical audit gains only the four corresponding
existing package-tree values and supplies no current skip authority. The separate
journey execution budget is qualified above.

The exact method receiver rejects missing, duplicated, skipped or substituted
methods and an older padded receipt. Its 17 portable controls and the exhaustive
4,096-state result-gate control do not execute an Apple application. New source,
current-main composition, configured native results and actual main readback must
retain their own identities.

The [planning-input source and journey record](../docs/validation/issue-64-planning-inputs.md)
describes the local raw fields, unanswered catalog references and lossless editor-v1
reading. Its 17 added UI methods retain all 204 preceding identities. The new App
journey creates only its own draft through ordinary controls, retains invalid usage
units and exact budget spelling across a process relaunch, explicitly chooses the
fictional workload/deployment records, then restores the earlier invalid/unanswered
revision and verifies it after another relaunch. It also checks that catalog usage,
classification and region declarations do not become fabricated user input.
The six preceding App method bodies and both historical local/T6 selector groups
remain exact; `--suite all` additionally requires the new method's start and pass.
An older six-method result cannot qualify the expanded current suite. This is a
declared journey awaiting its own native execution, not a simulated interruption,
manual accessibility audit, evaluated filter result or completed #64 criterion.

The accepted [historical resource comparison](../Packages/PlannerTransfer/HISTORICAL_RESOURCE_COMPARISON.md)
retains complete estimate rows and their own build/selection bindings. Its nineteen
methods join the unchanged 190-method receiver as `integrated-historical-resource-transfer`
in both Transfer and submission SDK workflows. All earlier receiver maps and parser
functions remain intact. The accepted [claim-copy rendering](../Packages/PlannerUI/EVIDENCE_RENDERING.md)
keeps six exact rendering methods, three 24-key localization tables, and verbatim
evidence values with directional isolation. The UI manifest preserves all four
package/target dependencies and both Resources and privacy-manifest processing.

The original `682f04a8` / prepared `1e5b90b6` and planning donor `3f7f48ec` /
prepared `228840ae` results describe their own source and base. Earlier original
comparison and renderer results likewise retain their exact execution identities.
Their receipt counts do not qualify this 756-method, seven-journey composition;
the configured current-source native jobs and ordinary review/merge gates remain
required. Native destinations, method selection and owned-simulator cleanup remain
unchanged; the separate journey command and job budgets are qualified above.

The later accepted main `c512e99d9042669171cf418ddace3e3769fc854f`
adds five Core methods for exact evidence/audit receipt identity, preserves
simulator command outcomes when observation or output reporting fails, and
requires literal Boolean acceptance-map states. Its complete runtime, regression
and documentation changes join the reviewed public `086492dd` source. The first
signed receiving commit `c81a2806e41608856d799d47a51c82ebcd7e42c4`, tree
`cfde13b48c82da69eb540ce02036df5da972b479`, binds that actual current-main union.
The present documentation reconciliation leaves every executable input in that
union unchanged. The earlier 744-declaration public source, its 17 portable
controls, and each native preparation retain their original identities; no
old native result qualifies that 749-declaration source.

The subsequent [exact catalog selection correction](../docs/validation/catalog-browser-row-identity.md)
retains those 749 declarations and adds three browser regressions. Its first frozen
`catalog-row-identity-ui` profile requires 231 UI identities, including complete
filtered pages and failed-page retry with distinct Unicode version pins. That
752-declaration checkpoint retains its original bounded value/index observations.
The coherent details follow-up adds four methods for exact sheet identity and
hostile version/name responses, retaining ID/kind admission, retry and dismissal.
The current `catalog-selection-identity-ui` profile requires all 235 UI identities
and the 756-declaration inventory above. All earlier profiles and result attribution
remain exact; the expanded source requires its own configured native qualification.

## Retained smoke and toolchain history

The dated paragraphs below preserve each original runner revision and observation.
Their 17-, 24-, 27-, 29- and earlier 25-model references describe those source-time
profiles; the current job inventory is the table above. Original failures remain
failures. The selected 55f continuation retains its existing Intel host and actual
qualified original receipt; the separate reviewed arm64 offer is not selected here.

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

Each native job uses its own fresh standard `macos-15-intel` host and retains the
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
| #26 pinned clean checkout; #30 native CI | Checked-in app/UI-test targets and shared scheme, local packages, explicit Xcode pin, actual CLI missing-pin regression and isolated-cache workflow | Exact-head hosted evidence and receiving review; #30 untrusted-PR and release-secret gates remain separate |
| #28 restore correct draft | SceneStorage selection, explicit dirty-discard guard, background save attempt; UI test reopens an acknowledged revision after process termination | Current expanded-source native execution; cold-link routing, interrupted unacknowledged edits and physical lifecycle qualification |
| #80 local library operations | Notes CRUD and UI save/reopen/discard/delete; imported-build local labels, fresh-fork duplication, confirmed deletion, revision/qualification display and bounded corrupt-wrapper recovery | Exact-head native CRUD/recovery and UI execution, UI duplicate/cross-client journey and receiving review |
| #87 offline editing | All operations use local storage; unknown compatibility/pricing always explicit | Governed catalog cache and downstream evaluation integration |
| #105 accessibility | System controls, visible labels, Dynamic Type, editor/action identifiers; bounded XCUITest local-draft journey | Current expanded-source native execution; wider complete journeys, VoiceOver, large text and physical device audits |

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
The subsequent [undo and autosave implementation](../docs/validation/editor-autosave.md)
adds bounded session undo/redo and a 750 ms typing debounce through the same queued
save path. Input remains editable while saving, and delayed timers/opens cannot
overwrite another draft or newer input. Actual process-kill during UI autosave,
full builder journeys and physical lifecycle qualification remain work under #69.
Hosted exact-head compilation and model tests are required before acceptance.
The [combined editor integration record](../docs/validation/editor-integration.md)
tracks the stronger delayed-open generation guard, retained lifecycle-save regressions,
separate library/editor failure notices and the updated real-timer journey. The
later accepted-main carry also retains independent history failure and recovery;
the [current receiving receipt](../docs/validation/catalog-editor-receiving.md)
records that composition and its complete test inventory. Previously
passed source runs are historical evidence; the combined source still requires its
own native package execution and both pinned UI destinations.

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
python3 -m unittest discover -s App/scripts/tests -v
python3 App/scripts/toolchain.py -- python3 App/scripts/ui-journey.py --suite all
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

## Asynchronous local startup

The #86/#29 startup correction builds on the independently available libraries in
[PR #159](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/159), baseline
`a8d3ac6c449a483a3373ebfaecc6eab4fa9af861`. Each scene owns a `LocalLibraryStartup`
model. Its SwiftUI `.task` awaits `LocalLibraryStores.open`; a detached worker prepares
the same protected Application Support directory and opens/migrates each SQLite
file. App initialization and the main actor do not perform those blocking operations.
Each tab shows a loading indicator, then either its library or an explicit unavailable
state. One failed database still cannot hide the other database's records.

SwiftUI cancellation is forwarded to the detached worker. Synchronous SQLite work
already in flight is allowed to finish or roll back normally; cancellation is checked
before directory preparation, between opens and before publishing. Cancelled results
are discarded, and a generation token prevents an older attempt from replacing a
newer one even if the older operation ignores cancellation. A reappearing scene can
retry incomplete startup; a ready scene retains its connections and editor state.
Separate windows own separate startup lifetimes and use the existing SQLite
transaction/revision guards when accessing the same files.

`LocalLibraryStartupTests` bounds the controlled opener wait to five seconds and
checks an editor binding action on a real selected synthetic draft while opening is
blocked. Its injected nil autosave clock isolates that startup scheduling assertion;
the public app initializer and separate UI journey retain the production timer. It also
checks off-main directory preparation/opening, cancellation between database opens,
superseded results, explicit failure/retry, retained ready state and directory errors.
The timeout is a test deadlock guard, not a responsiveness budget or performance
measurement. `LocalLibraryStoresTests` continues to exercise both corrupt-file cases
using real SQLite through the asynchronous factory. Run these with the existing
`swift test --package-path Packages/PlannerUI` and native UI workflow above.

This is bounded startup/cancellation coverage for #86's #29 prerequisite. Hosted
exact-head Swift/Xcode tests, simulator launch and receiving review are still required;
physical-device responsiveness, locked-device and low-storage behavior, and the full
#29/#86 acceptance criteria are separate. No startup timings or device results are
inferred from static inspection. Apple references checked 2026-10-18:
[app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
and [Task cancellation](https://developer.apple.com/documentation/swift/task).


## Files import and reviewed export

The Imported builds screen uses a separate `imported-builds.sqlite` database in the
same protected Application Support directory. It never treats a canonical build as
notes-editor payload or converts an incomplete note into a valid snapshot. A local
version-1 persistence wrapper holds canonical bytes and untrusted fixture metadata;
unsupported local formats are preserved and refused. Imported builds are read-only.
Each library opens independently. If either database is corrupt or unsupported,
only that tab reports an unavailable library; the other tab remains usable. Two
regression tests corrupt each database in turn and verify that the healthy database
still reopens its saved records (including note history) and corrupt bytes remain
unchanged. These tests exercise real SQLite initialization, not mocked success.

The system Files picker supplies one JSON URL. Security-scoped access lasts only for
a bounded background read (512 KiB actual-byte maximum, checked independently of
metadata); directories and malformed/unsupported/private imports fail without writes.
A preview is not an import. Explicit confirmation creates a fresh wire build ID,
local owner reference and local storage row, preserves version locks, and never
updates the source identity. Imported references are not fetched or rights-approved.

Export requires an explicit public alias, previews the exact projected JSON and asks
the user to review free text before opening the system file exporter. Private owner,
notes and extensions are stripped by PlannerTransfer. Allowed text can still be
sensitive: field filtering is not arbitrary secret detection. Changing the alias or
selection invalidates the prepared export. Marked synthetic imports retain their
fixture label across persistence and re-export via the existing web envelope;
its original source revision is untrusted metadata, not authority. Bare/unmarked
imports remain visibly unqualified, never presented as production data.

Seven controlled model tests cover preview/cancel without writes, repeated fresh-ID
forks and durable reopen, fixture-label preservation, explicit alias/projection,
invalid/oversized files and directories, bounded local-file preview, and preservation
of future stored formats. The bundled synthetic fixture is copied unchanged from
PlannerTransfer/Tests/PlannerTransferTests/Fixtures/build.json (its source manifest
remains authoritative); test projection explicitly removes private fixture settings.
Hosted exact-head compilation/tests are required. Actual Files-provider interactions,
accessibility, complete cross-client UI round trips, process interruption and physical
device/privacy receiving qualification remain unverified. Partial #82/#84/#102 only.

Preview parsing and export validation/projection/encoding also use the existing
detached preparation boundary. Export captures the selected row, qualification and
public alias synchronously before its worker task is queued; alias changes invalidate
both queued and in-flight results. Cancellation cannot publish prepared bytes or a
late failure. Six controlled regressions block real preparation while another notes
editor processes a main-actor edit, then check cancellation, invalidation, retained
qualification and unchanged durable records. See the [preparation validation record](../docs/validation/import-preparation.md).
Their exact hosted native execution remains required; this scheduling coverage does
not establish a measured performance budget or full Files/lifecycle acceptance.

## Organize the imported-build library

Each entry displays its local revision and the fact that imported evidence has not
been revalidated. The selected entry also shows its pinned wire snapshot revision,
original snapshot name and existing synthetic/unknown qualification. A local label
is revisioned library metadata: renaming preserves the exact stored snapshot bytes,
locks and previous label revisions. Export continues to project the pinned snapshot.

**Duplicate as new local fork** validates the selected stored revision, then uses
the existing transfer fork boundary to create distinct wire and local identities.
It preserves the local label, component/settings/version locks, and synthetic/source
metadata; the original entry and its history remain intact. The duplicate starts at
local revision 1 with no current analysis. The source revision check and new row
insert share one SQLite transaction, so a newer revision or deletion during fork
preparation causes an explicit rejection and requires reopening the entry. Confirmed
deletion carries the exact selected row/revision; another selected entry is preserved.
After a successful deletion, any baseline pinned from that local row and its prepared
comparison are cleared. A failed deletion cannot acknowledge that invalidation.

Pages contain at most 20 stored rows. Stored-snapshot decoding and fork preparation
run off the main actor. Malformed or unsupported stored wrappers are preserved and
counted alongside unreadable database rows. Page offsets count both kinds, including
an entirely unreadable page, so later valid entries remain reachable. The Refresh
builds action retries reading; a successful read clears only a library-read error,
leaving unresolved mutation errors visible until the entry is reopened or corrected.

Seven additional real-store model regressions cover local rename/restart/history,
fresh-fork duplication with retained synthetic qualification, stale CRUD rejection,
confirmed deletion after selecting another entry, 503-entry recovery beside a
malformed wrapper, an entirely unreadable page followed by a valid entry, and invalid
qualification metadata. The large-library case expects 501 valid entries plus the
preserved unreadable row after one deletion, with exact unrelated metadata/history.
The native workflow requires every one of those seven named tests to report a pass
in the complete PlannerUI suite. Their exact-head hosted SwiftUI test/build execution
is required before acceptance; no result is inferred from source inspection. Three added PlannerData
regressions exercise a prepared fork against source changes/deletion through another
connection and a successful distinct-payload insert with exact source/history
preservation after reopening. The storage simulator gate requires the new stale-source
cases and all 34 current storage tests to pass. Existing PlannerData tests
separately exercise actual malformed SQLite rows, storage exhaustion and migration.
Actual Files-provider/cross-client journeys, unavailable/revoked remote references,
VoiceOver and physical-device behavior retain their own unverified acceptance gates.

Native confirmation data follows Apple's
[alert presentation](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:message:)-8584l)
and [confirmation dialog](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:message:))
interfaces (checked 2026-10-18); the captured entry/revision stays separate from the
Boolean presentation state.

## Local configuration comparison

Comparison preparation runs through the existing off-main worker boundary. The
button captures both immutable snapshots and their synthetic/unknown labels before
queueing; changing the selected entry or replacing/clearing its pinned baseline
invalidates the result. A newer comparison may finish while cancelled older work
is still unwinding. The screen shows progress and a Cancel comparison control;
leaving the library cancels pending work while opening completed details retains
their immutable result. Committed deletion of the pinned entry clears its baseline;
a rejected deletion preserves it. See the [comparison preparation record](../docs/validation/comparison-preparation.md)
for the nine controlled regressions and required native execution.

Open an imported build, choose **Use selected build as baseline**, open another
imported build, and explicitly compare. The baseline is an immutable snapshot held
in memory until replaced or cleared. Preparing a comparison captures both build
identities and their synthetic/unknown labels together. Selecting a different build
invalidates the prepared result; it does not silently change the pinned baseline.

The result shows both names, build IDs and revisions, followed by the evidence
notice and every returned configuration difference. Selection kinds carry their
canonical T0–T6 display grouping. Before/after values preserve **Not set**, **Hidden
for privacy**, zero, false, null and empty text as distinct states. Explicit type
labels prevent user-entered strings such as "Not set" from impersonating absent or
hidden fields. Three presentation regressions cover these collisions and full
multiline text. Multiline system
text and a scrolling list avoid a shortened preview of the result. An ambiguous
identity, conflicting revision or more than 2,048 differences produces an explicit
failure message and preserves both builds; no incomplete result is presented.

This screen uses the tested PlannerTransfer comparison boundary without writes or
service calls. It does not compare outcome, quality, capacity, compatibility or cost:
each side still needs qualified evidence matching its own component tuple, workload,
versions, units and conditions. Equal settings do not establish readiness or rights.
The screen is limited to existing read-only imported local forks; it does not add a
builder, revision-history editor or cross-client service. Partial #81 only.

The portable comparison tests cover missing/zero distinctions, changed component
settings and locks, unmatched extension measurements, privacy masking, duplicate
identities, reordered selection/link arrays and the explicit result limit. Native
compilation must pass in the exact-head hosted workflow. Files-picker interaction,
the complete visible comparison journey, large text, VoiceOver and physical-device
acceptance still require their own observed evidence.

The [typed component details receipt](../docs/validation/issue-61-catalog-details.md) records exact catalog/item pins, retained source declarations and bounded read-only inspection. The [combined receiving receipt](../docs/validation/catalog-editor-receiving.md) separates this current source from earlier candidate counts and native results.

The separate [comparison-worker composition](../docs/validation/comparison-preparation.md)
retains that catalog/editor source and adds nine model cases. Its own native profile
retains its historical 96 UI cases and 47 named identities. The then-current
[source-link composition](../docs/validation/catalog-source-navigation.md#comparison-worker-receiving-composition)
added fourteen cases and required all 110 UI cases and 61 named identities. That recorded carry retained
the accepted quality boundary, so its Transfer profile required 57 cases and all
21 named identities. The catalog/editor receipt preserves its recorded 87/48
source and historical executions alongside these expanded receiving gates;
those earlier results do not execute this follow-up.

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

## 2026-10-20 iPad journey interaction correction

The original `c43d43269d10d877bab5724f413a61ec04850919` iPad
[job 118590233449](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39411421045/job/118590233449)
reached the real app and failed all seven selected methods: Catalog search did
not appear after its tab activation; the planning journey scrolled past
`planningInput-requests_per_day`; the saved-notes journey remained at the
recognized system keyboard tutorial; and all four T6 journeys encountered
duplicate nested Imported builds buttons. This saved-notes stop precedes its
app-close assertion. The literal XCTest total is seven failures in 840.157
seconds. The complete 533,650-byte console has SHA-256
`01163c3acdb9f67014fa1867d83f87696426fafa28673d0a5de5729ea48d0e9b`;
the single retained artifact is `12264287009`, 152,730,935 bytes, SHA-256
`83c795c8cbfa74b4d8660f89ddb09143509d8aeb9826d286454b7db7db9cbbc9`.

The retained native hierarchy exposes same-label tab wrappers and leaves.
The journey selector now requires exactly one matching leaf button, then
requires it to be enabled and hittable. For an existing occluded editor field,
the LocalDraft helper uses the same small, frame-directed movement as the
Catalog helper, within its original six attempts and the same editor Form.
An absent target still uses the caller's original scroll direction.

The Catalog and tutorial event records already placed their 50 ms touches at
the centers of the intended frames; a coordinate-only change would repeat
that input. One 200 ms press replaces the single activation only for library
tabs and the recognized system Continue control. This duration is an
unexecuted interaction hypothesis, not an established OS diagnosis or native
success. The exact tutorial-copy guard, both disappearance checks, pasted-text
equality, all seven method identities and all destination/data/revision/
negative assertions remain. Existing per-wait limits, scroll-attempt limits, runtime
pins, job deadlines, production model/storage code and receipt profiles remain
unchanged; T6 also waits for enabled/hittable readiness within its existing
five- or ten-second per-wait bound. A new configured native run must qualify the corrected source;
neither the earlier passing portable originals nor this failed iPad original
establishes that result.
