# T6 review for a selected retained Build

This preparation implements eleven T6-specific additions. The original nine paths were claimed for [#95](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/95#issuecomment-6266798229)
and [#96](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/96). Its fixed
accepted basis is `63df6b24b7bee4272bdcc8e75ad679202089110b`. It requires the three
reviewed [#363](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/363) T6
guidance additions and ten [#372](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/372)
DeploymentManifest additions. The latter's observed two invalid test fixtures
were corrected separately; this UI changes no schema or library API. The
[eleven-path continuation](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/95#issuecomment-6267909869)
adds the selected plain-text report and its tests. The independently reviewed
`5ac3923503d696d5b80af566296eda53389dbece` picker/API/journey correction remains a
separate predecessor with its original receipts.

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

View disappearance preserves an unconsumed owned importer request or an admitted
export request, including the interval between the system clearing its binding
and delivering its terminal callback. The view keeps that request's presenter
state. With neither owned request pending, disappearance performs ordinary review
cancellation, retiring unfinished preparation or an unsubmitted preview. This
distinction addresses a source-level interaction risk; it is not an observed
native Files failure. Actual navigation withdrawal is a separate explicit signal:
the receiver must call `cancel()` even with an owned Files dialog pending, and
`clear()` for record closure/deletion. Those calls always retire the requests.

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

The helper prepares two existing private JSON artifacts in memory. The private
pair retains owner references, extensions, notes, approvals and endpoints.
Neither member is supplied to the Files exporter. The existing
`BuildTransfer.export` JSON projection remains a separate route; this report does
not change it or introduce a combined archive.

## Proposed-plan report and Files save

`T6PlanReport` is a deterministic UTF-8 **plain-text** disclosure report, labelled
**PROPOSED DEPLOYMENT PLAN**. It is not a v1 manifest, a reimportable package or an
executable deployment. It requires an already proposed, exactly bound local pair
and guidance for the same complete Build. Other declared statuses remain visible
in the review, but cannot create this report.

| Retained information | Report representation |
| --- | --- |
| Build identity and revision | Exact quoted ID and exact numeric value; no name or owner. |
| Locks | Every admitted supplied lock, including optional `pricebook_id`; known absent locks explicitly say **not supplied**. Numeric values use the existing exact JSONValue serialization without floating-point or integer narrowing. |
| Deployment target and monitoring | The bound target and all monitoring selections in original order, including disabled rows: selection ID, kind, catalog item ID/version and enabled flag. Settings, names and roles are omitted. |
| Rollout and approvals | Original rollout strategy and every approval row's scope/decision in original order, including duplicates or contradictory declarations. Approver references and dates are withheld; no authority is inferred. |
| Selected quality record | Original reported status and sample size, measurement count and counts of the recorded true/false flags; artifact reference count. No threshold calculation or manifest-reference binding is asserted. An absent record stays unknown. |
| Report and rollback references | Each of the four report-reference fields says supplied/not supplied, with its identity withheld. Rollback URI presence is preserved while its address is withheld; the report directs the reader to the retained declaration for rollback requirements. Neither presence nor absence certifies a rollback procedure. |

The complete omission list is in both the report and the disclosure UI: Build
names/owners/objectives/policy/links, all selection settings/roles, notes and
extensions; approver identities/dates; report/artifact/deployment identities and
addresses; manifest identity/request date; quality record identity, evaluator and
dataset labels, measurement details and notes; other tier selections. The
originals are retained unchanged. No replacement reference or approval ID is
created to make the projected report appear schema-complete.

Every retained string is quoted. Quotes, backslashes, control characters and
Unicode format/line/paragraph separators are escaped; ordinary Unicode scalar
spelling remains exact. This prevents an identifier/version from introducing a
new line or hidden heading. A `secret://` marker in any retained value, matched
without case sensitivity, rejects the whole report. Omitted private values are
never serialized into the report. This allowlist and explicit disclosure review
do not claim that every user-chosen identifier is inherently public.

Formatting runs off the main actor from the exact Build/content captured before
the task is scheduled. The complete output, including escapes, is bounded to
512 KiB. An error or cancellation publishes no preview bytes and changes no
private input. The user sees the exact complete text and omission list before
checking **I reviewed the exact report and the listed omissions for disclosure**.
**Save report to Files** is disabled until that check is made for this preview.

The actual SwiftUI Files exporter receives only that immutable report as one
`utf8PlainText` FileDocument, with the fixed safe default filename
`proposed-deployment-plan.txt`. The system lets the user select the destination
and edit the name. The app creates no temporary file or private-pair output.
Only this request's actual terminal Files callback may acknowledge save, failure
or cancellation. Callback diagnostics contain no path, URL or input value.

A new preview, review/retry, picker, changed selection, deletion or cancellation
retires the export request and any unfinished preparation. A delayed success or
failure cannot borrow the new content, restore an old preview or overwrite the
current notice, even after restoring the same Build. Save admission is
single-use. Closing a preview or failing/cancelling Files retains the original
declarations and permits a fresh reviewed retry. Retiring a request prevents
later UI acceptance; it does not claim to undo an OS save that already occurred.
The app makes no crash-atomic or file-provider durability promise.

## Receiver integration

The existing [Imported builds receiver](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198)
retains the shared integration paths. This donor changes no package manifest,
existing library view/model, app startup, project, scheme or workflow. The
following integration is still needed before claiming a mounted feature:

1. Receive the exact reviewed library donors and add PlannerTransfer to the
   existing PlannerUI dependency/test dependency through its current owner.
2. Keep one `T6ReviewModel` for the selected Imported-build record; call
   `select(snapshot)` whenever the actual selected snapshot changes, and `clear()`
   after record deletion or closure. When the actual T6 navigation route is
   withdrawn, explicitly call `cancel()` even while its importer/exporter is
   pending. This must follow the receiver's navigation state, not another
   visibility callback: an owned Files presentation may hide its destination
   without withdrawing the route. Bind selection to the original retained
   snapshot, not a rewritten original record attached to a newly identified import/fork.
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

The source contains 22 model methods: the original 16 cover separate compatibility/quality states,
exact local pair/private projection distinction, every non-proposed status,
missing references, omitted/disabled selections, ambiguous or disabled targets,
foreign Build/revision rejection, suspended stale success/failure, cancellation,
deletion/retry, malformed/oversized/duplicate-key input, real directory/FIFO
rejection, bounded file recovery and stale file-picker completion. Three additional
methods exercise same-Build cancellation, superseded/single-use picker callbacks,
and review/retry or restored-selection invalidation with zero preparation calls
for obsolete requests. JSON inspection uses only the public enum cases through
uniquely named PlannerUI-local projections; no donor visibility is widened.
Three lifecycle methods additionally cover owned importer disappearance and its
exact terminal callback, explicit route cancellation/record closure, and ordinary
disappearance during unfinished review followed by recovery.
The 16 `T6PlanReportTests` methods cover the complete lock/field projection,
private-value omission, approval order, exact Unicode bytes and escaping,
secret-marker rejection, escaped-output bounds, proposed/full-content binding,
optional/disabled selections, disclosure and single-use admission, stale Files
callbacks, cancellation, failure and fresh-preview recovery. The original 19
model methods and 13 report methods remain unchanged. Three report lifecycle
methods cover the corresponding owned exporter, explicit route withdrawal and
ordinary preparation/preview disappearance boundaries. The `2c65a8be` report
checkpoint and its bounded input checks retain their original source identity;
these six later lifecycle methods have not been executed.

Run both focused classes after the actual dependency/receiver composition:

```sh
swift test --package-path Packages/PlannerUI --filter T6PlanReportTests
```

The three native journey methods must run on the actual composed iPhone and iPad
app. Their destination and fixture setup are required; the tests do not skip or
pretend to pass when integration is absent. The report journey verifies the exact
preview/omissions, disclosure gating and a real Files presentation/cancellation.
Successful Files save still needs an actual native destination run: save to an
owned local provider, independently read the complete saved UTF-8 bytes and compare
them to that preview, verify the filename/default and retained private originals,
then exercise destination failure/cancellation and a fresh retry. Do not substitute
a mocked callback or another source tree's job for that observed save/readback.

This source-only donor has not run those SwiftUI model methods or native
journeys. Linux syntax/reference checks, if recorded in the accompanying exact
source receipt, are only their stated checks. The old #363/#372 jobs retain
their original source identities, including actual failures; they do not validate
this later UI. Mounted navigation, lifecycle/Files cancellation, adaptive layout,
VoiceOver, actual Files save/readback and disclosure, current receiving CI and issue-specific
acceptance remain actual integration gates. The literal #95/#96 criteria stay
open until reconciled with delivered evidence.

The implementation follows the existing contributor and platform boundaries:
[repository scope](../REPOSITORY_SCOPE.md), [contributing](../../CONTRIBUTING.md),
and [current analysis store](../../Packages/PlannerCore/Sources/PlannerCore/AnalysisStore.swift).
Its concurrency and Files assumptions use primary documentation:
[cooperative cancellation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/),
[cancellation handler](https://developer.apple.com/documentation/swift/withtaskcancellationhandler(operation:oncancel:)),
[Files import and cancellation](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:oncancellation:)),
[FileDocument](https://developer.apple.com/documentation/swiftui/filedocument),
[Files export and cancellation](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttypes:defaultfilename:oncompletion:oncancellation:)),
and [bounded FileHandle reads](https://developer.apple.com/documentation/foundation/filehandle/read(uptocount:)).

The Files importer/exporter cancellation overloads are documented for iOS 17 and
macOS 14; FileDocument predates those deployment targets. Those primary API
availability reads are not Swift typechecking or native execution. The retained
Linux compiler became unavailable after the predecessor's syntax check; its
actual missing-executable receipt is preserved, and no replacement installation
or claim of Swift execution was made for this continuation.
