# T6 review for a selected retained Build

This preparation implements the nine new paths claimed for [#95](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/95#issuecomment-6266798229)
and [#96](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/96). Its fixed
accepted basis is `63df6b24b7bee4272bdcc8e75ad679202089110b`. It requires the three
reviewed [#363](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/363) T6
guidance additions and ten [#372](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/372)
DeploymentManifest additions. The latter's observed two invalid test fixtures
are a separate correction; this UI changes no schema or library API.

## Behavior

`T6ReviewModel` receives an explicitly retained `BuildSnapshot`. It compares the
whole immutable value when selection changes, including exact declared locks,
revision, settings and private fields. Every import or retry gets a fresh
generation. Selection changes, deletion, explicit cancellation and caller
cancellation invalidate previous work. A worker that ignores cancellation cannot
replace a later success with either an old result or an old error. The selected
snapshot and input files are not modified.

A picker receives an opaque, single-use request before presentation. Its stable
presenter retains that original request, including the complete Build and artifact
kind; callbacks do not borrow a later request from mutable view state. Cancellation,
a new picker, review/retry, changed selection or deletion invalidates the pending
request. Late success, failure and cancellation are ignored even if the exact same
Build is selected again. The Files cancellation callback is explicit; dismissal
of the presentation binding alone is not treated as success or failure.

`T6ReviewView` provides explicit JSON file selection, retry, cancellation and
removal actions. Bounded reading and existing decoding run away from the main
actor. An explicitly selected Files URL receives temporary security-scoped
access, which ends after reading; ordinary artifact URI strings are inert text.
The nonblocking opened descriptor must identify a regular file; a path-type
check followed by a different open is not used. Actual bytes read are limited to the existing 512 KiB
`BuildTransfer.maximumBytes`. The original parser still enforces duplicate-key,
depth, node, number and schema restrictions. Diagnostics do not echo private
input or filesystem paths. No task opens a URI embedded in a quality record.

Quality and compatibility stay separate. The model accepts compatibility only
from the existing analysis owner's current state, then compares the report's
own identity with the selected Build's exact five evaluation pins. The caller
also returns the original BuildSnapshot captured for that analysis, which must
equal the complete current snapshot; it must not substitute the current Build
at callback time. The model does not
replace the governed report receiver or determine source freshness. A report
that is absent, pending, failed, cancelled or mismatched leaves compatibility
unavailable. A reported compatibility pass cannot create quality data or approval;
a reported quality pass cannot erase incompatible inputs. Measurements retain
their observed values, thresholds, operators, absent or empty units, and reported
false flags. No thresholds are reevaluated and no score is computed.

The supplied manifest remains a declaration. Non-proposed statuses and their
original approval rows are retained for inspection. A proposed pair requires the
existing helper's exact Build/revision and unambiguous enabled target binding.
Missing required report IDs or approval declarations remain incomplete; there
are no invented IDs, automatic status changes or placeholder approvals. The
view displays the original locks, monitoring selections, report references and
optional `rollback_artifact_uri`. A missing rollback value stays not supplied.

The helper can prepare two existing private JSON artifacts in memory. No files
are written by this view, no combined archive is invented, and no durable save,
public sharing, approval or deployment acknowledgement is presented. The private
pair retains owner references, extensions, notes, approvals and endpoints.
The existing `BuildTransfer.export` public projection remains a separate route;
the new code never sends the private pair through it. A concrete export action
needs the separately reviewed destination/projection and success/failure handoff.

## Receiver integration

The existing [Imported builds receiver](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198)
retains the shared integration paths. This donor changes no package manifest,
existing library view/model, app startup, project, scheme or workflow. The
following integration is still needed before claiming a mounted feature:

1. Receive the exact reviewed library donors and add PlannerTransfer to the
   existing PlannerUI dependency/test dependency through its current owner.
2. Keep one `T6ReviewModel` for the selected Imported-build record; call
   `select(snapshot)` whenever the actual selected snapshot changes, and `clear()`
   after deletion or closure. Bind this to the original retained snapshot, not
   a rewritten original record attached to a newly identified import/fork.
3. Mount `T6ReviewView(model:)` through the selected record's **T6 review**
   navigation action. Start `retry()` for the initial unanswered state. Forward
   the existing current compatibility state and its invalidations via
   `receiveCompatibility(_:for:)`, returning the original captured Build with
   the actual analysis result; this donor supplies no replacement evaluator.
4. Register `T6ReviewJourneyTests.swift` in the existing native UI target and
   supply its explicit `--t6-journey-fixture` test-only scenarios through the
   receiver's existing labelled fixture setup. `quality-absent` supplies the
   synthetic retained Build and a same-pin reported compatibility record, with
   no quality/manifest. `quality-failed-proposed` supplies the same retained
   Build, failed quality fixture and pending proposed manifest. These are
   synthetic test inputs, never actual execution evidence. The journey enters
   Imported builds; it must not replace navigation with a direct test-only T6
   root screen. No fixture hook is installed by this donor.

The three fixture JSON files are under
`Packages/PlannerUI/Tests/PlannerUITests/Fixtures/`, alongside the existing package
test resources. They intentionally omit optional T3–T5 selections. Their IDs,
dates, zero observation, false result, reference URI and pending approver are
explicitly synthetic and demonstrate no actual evaluation, consent or authority.
The fixture's private note uses the frozen `extensions.x_planning_notes` field;
it does not introduce an unsupported top-level Build field.

## Qualification and remaining gates

After the actual receiver composes these files and the two dependency donors:

```sh
swift test --package-path Packages/PlannerUI --filter T6ReviewModelTests
```

The source contains 19 model methods: the original 16 cover separate compatibility/quality states,
exact local pair/private projection distinction, every non-proposed status,
missing references, omitted/disabled selections, ambiguous or disabled targets,
foreign Build/revision rejection, suspended stale success/failure, cancellation,
deletion/retry, malformed/oversized/duplicate-key input, real directory/FIFO
rejection, bounded file recovery and stale file-picker completion. Three additional
methods exercise same-Build cancellation, superseded/single-use picker callbacks,
and review/retry or restored-selection invalidation with zero preparation calls
for obsolete requests. JSON inspection uses only the public enum cases through
uniquely named PlannerUI-local projections; no donor visibility is widened.
The two native journey methods must run on the actual composed iPhone and iPad
app. Their destination and fixture setup are required; the tests do not skip or
pretend to pass when integration is absent.

This source-only donor has not run those SwiftUI model methods or native
journeys. Linux syntax/reference checks, if recorded in the accompanying exact
source receipt, are only their stated checks. The old #363/#372 jobs retain
their original source identities, including actual failures; they do not validate
this later UI. Mounted navigation, lifecycle/Files cancellation, adaptive layout,
VoiceOver, private export selection, current receiving CI and issue-specific
acceptance remain actual integration gates. The literal #95/#96 criteria stay
open until reconciled with delivered evidence.

The implementation follows the existing contributor and platform boundaries:
[repository scope](../REPOSITORY_SCOPE.md), [contributing](../../CONTRIBUTING.md),
and [current analysis store](../../Packages/PlannerCore/Sources/PlannerCore/AnalysisStore.swift).
Its concurrency and Files assumptions use primary documentation:
[cooperative cancellation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/),
[cancellation handler](https://developer.apple.com/documentation/swift/withtaskcancellationhandler(operation:oncancel:)),
[Files import and cancellation](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:oncancellation:)),
and [bounded FileHandle reads](https://developer.apple.com/documentation/foundation/filehandle/read(uptocount:)).
