# Apple #75: Native visible-revision analysis binding

This bounded contribution supplies the observable native model and guarded report
view for [Apple #75](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/75).
It was prepared from accepted main `78aa0de9a4a2b1c651f73c284890e4dbe8bcd137`
under the [recorded scope](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/75#issuecomment-6262507182).
The selected-build editor remains with [#198](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/198).
All three complete issue criteria remain open for their integration and receiving
requirements; the new component is not an evaluator, transport or completed editor.

## Currentness and selected inputs

[`EvaluationAnalysisModel`](../../Packages/PlannerUI/Sources/PlannerUI/EvaluationAnalysisModel.swift)
is `@MainActor` and `@Observable`. A selected identity change, explicit ownership
clear or disconnect revokes visible analysis synchronously. Its short Core
operations then enter one ordered queue, including select, clear, begin, receive,
failure and cancellation. Network or evaluation work does not enter that queue.
Every response uses the existing typed `AnalysisStore<EvaluationReport>.receive`
overload, which derives response identity from the validated report. Returning
actor calls must still match the captured native generation and active request.

Core decides whether completion or cancellation wins. Cancellation arriving after
an accepted completion cannot erase that completion while its UI publication is
returning. A retry obtains a new Core token even for identical inputs. Disconnect
does not automatically resume an earlier request. A cancelled or superseded
`begin` returns no token; an owner must not start transport work for it.

[`BuildSnapshot.evaluationAnalysisIdentity`](../../Packages/PlannerUI/Sources/PlannerUI/BuildAnalysisIdentity.swift)
projects the expected tuple from a validated selected snapshot through public
transfer APIs. The build ID and revision are wire identities, separate from a
local draft row's UUID, revision or title. Required catalog, ruleset and graph
pins are retained exactly. Positive integral revisions must be represented
without rounding. Optional pricebook identity is outside the frozen evaluation
report's input tuple, so it is not added to that tuple.

[`EvaluationAnalysisView`](../../Packages/PlannerUI/Sources/PlannerUI/EvaluationAnalysisView.swift)
requires the containing view's currently visible identity on each render. It
displays the existing `EvaluationReportView` only when the native request and the
validated report both match. Pending, cancelled, failed, disconnected and
unrequested inputs remain explicitly unavailable or pending. Reported findings,
severity, outcomes, readiness and unknowns are not rewritten or promoted into
verified claims.

Apple documents [Observation model dependencies](https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app)
for iOS/iPadOS 17 and macOS 14 onward, matching the accepted UI deployment floor.
The model uses that standard SDK module; no external observation library is added.
The [Swift concurrency guide](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
informs the actor boundary. These primary API sources were checked on 2026-10-19;
they establish API behavior, not this application's native qualification.

## Exact editor handoff

The inspected signed #198 stage is
`2206ea74b25b7b5c0406563d237e4e7fe332ed21`, tree
`7c1f448977119771104f30daab498d0e81f165b9`. Its real
`ImportedBuildLibraryModel` adopts a validated immutable `BuildSnapshot` alongside
a separate `DraftRecord`. Those imported-build source files are absent from the
inspected main. The stage also predates the accepted typed Core adapter. Therefore
the separate three-file caller patch must be composed by that receiving owner
with current main and this contribution; it is not a standalone build of the old
signed stage and is not applied to the note-only application here.

The caller patch gives the imported-build model one retained analysis model. An
adopted `DraftRecord` context change clears ownership before selecting the
snapshot's wire tuple. This includes a different row with identical wire bytes
and a newer local revision whose wire revision remains unchanged. Only committed
deletion of the selected row clears that owner. A detail view observes the actual
library model and recomputes the visible identity during rendering; it does not
capture an old snapshot in a navigation action. Comparison, import/export and
storage operations retain their original behavior.

Three direct caller regressions are supplied with that patch: identical-wire
rows, local rename versus wire revision, and unrelated/stale/committed deletion.
They use the actual imported-build model, SQLite store and typed Core path, but
have **not executed** because the selected editor receiving composition is not
available in this main. The 6889 receiving controller retains that integration.
No live service, production evaluator or synthetic report is inserted in the app.

## Executed portable checks and required native checks

The [receipt](visible-analysis/receipt.json) binds source hashes, actual commands,
toolchain identity and per-case results to the retained original logs. It records
Swift 6.1.2 on x86_64 Ubuntu 24.04.3, Swift 6 language mode, one build worker and
the host's KST (`UTC+09:00`) log timezone. The official Swift archive's release
signature was verified before use. Two matching Ubuntu terminal libraries were
verified through the signed Ubuntu package inventory and extracted locally;
system configuration was not changed.

The portable check compiles byte-identical copies of the production observable
model, snapshot projection and fourteen test methods against the actual unchanged
Core and Transfer modules. It excludes SwiftUI, the app and the editor handoff.
Both [Debug](visible-analysis/portable-debug.txt) and
[Release](visible-analysis/portable-release.txt) executed all fourteen methods
with zero failures, unexpected errors or skips. These include the controlled
three-revision completion order `3, 1, 2` across disconnect/reconnect, every
response identity field, foreign tokens, retry, observation notification,
immediate invalidation and both Core completion/cancellation orderings.

Three isolated source mutations were each detected by their exact selected test:
ignoring the visible identity produced two assertion failures; publishing a
superseded queued begin produced one; clearing native state before Core admitted
cancellation produced two. The original source was restored after every control.
The [recovery run](visible-analysis/portable-recovery.txt) then passed all fourteen
methods. The negative logs and exact substitutions are retained with the receipt.
These are intentional synthetic failures, not native UI execution or regressions
in the delivered source.

The pinned Python 3.12.14 conformance environment passed the reference runner,
all 47 harness methods and the unchanged 45-report and 37-evidence vector checks.
The [conformance log](visible-analysis/conformance-tests.txt) and receipt preserve
their separate attribution. No frozen fixture or schema was edited. The two new
UI fixture resources are exact copies of the existing Core report and Transfer
build fixtures and remain synthetic test inputs.

The existing native UI and Core simulator workflows now require a fifth actual
rendering method. It drives the real model/view with the existing synthetic
report and checks current, foreign visible revision, pending retry, cancellation,
failure, disconnect and clear. All four original rendering methods and the strict
module/session/failure/skip receipt checks remain required. Swift syntax parsing
of the new view, host and caller files passed locally; Apple SDK compilation and
all five native rendering methods are **unexecuted locally**. Their actual hosted
logs and `.xcresult` bundles must pass for the publishing head before delivery.

On the pinned Apple toolchain, reproduce the model package and native view gates:

```sh
swift test --package-path Packages/PlannerUI
swift test --package-path Packages/PlannerUI --configuration release
xcodebuild test -project tools/evidence-rendering/EvidenceHarness.xcodeproj \
  -scheme EvidenceHarness -destination 'platform=macOS' \
  -only-testing:PlannerEvidenceUITests/EvidenceRenderingTests \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

Use the configured workflow's actual iPhone/iPad simulator UUIDs for those cohorts,
retain each original log, and run `tools/conformance/qualify_evidence_rendering.py`
on it. The separate caller tests become part of the native package only when its
receiving patch is integrated. Physical-device, real reconnect, accessibility,
service and signed-release qualification remain separate.

## Manifest inventory delta

PlannerUI now declares the existing first-party PlannerTransfer dependency for
the public selected-snapshot projection. PlannerCore and PlannerData remain local
dependencies. No third-party package, package version, remote endpoint or lock
policy changes. The new `Packages/PlannerUI/Package.swift` SHA-256 is
`cf646d3f7424fcc65dbb5c712a5788fa5e3832b4b2b4eb4f4bc27dfafe46fa98`.
This source inventory supplements the historical
[#103 inventory](dependency-review.md); it does not claim a shipped-binary audit.

## Criterion disposition

| Literal #75 criterion | Prepared evidence | Remaining gate |
| --- | --- | --- |
| Only analysis for the visible revision receives current status. | Observable model and guarded view; actual portable identity and ownership-revocation tests; exact #198 caller patch. | Configured Apple UI execution, #198 caller receiving integration, and #71's governed recomputation/unavailable output. |
| Reconnect while three successive revisions finish out of order; only the visible revision is current and cancellation cannot erase the latest matching result. | Actual Core-backed native-model test uses three revisions, reconnect token replacement and `3, 1, 2` completion order; both ordered cancellation controls and restored-source recovery pass. | Real selected-editor/service integration and its reconnect replay; no live connection was created by these tests. |
| The race/cancellation/reconnect reproducibility log is linked with criterion results, exact versions, limitations and receiving-review disposition. | Linked source-bound original portable logs, negative/recovery substitutions, toolchain and scope receipt, plus this table. | Exact-head independent Apple and governed evaluator receiving review; hosted and integrated receipts remain distinct. |

The delivering PR records independent review and current-head hosted outcomes.
At this preparation checkpoint, those receiving decisions are pending. No issue
checkbox, assignee, native relationship or Project field is changed by this record.

## Later accepted-date receiving composition

The preparation record above and its original logs/receipt remain tied to the
original component and accepted base78aa. The later receiving baseline is
`2ba5136d09b639305aa87eda12cf7960881e7533`, which includes the accepted capture-date
contribution from #368, source-preserving mutation-input checks from #362 and
optimized Transfer validation from #364. These accepted changes are retained;
no old execution is reassigned to this combined source.

The current native rendering gate requires the exact union of **six** methods:
the original four, the accepted capture-date method and the unchanged analysis
method. Both five-method predecessor logs and the original four-method log are
insufficient for this union. All original Swift method bodies, synthetic vectors,
analysis model/projection sources and source-bound execution logs are preserved.
The shared host retains date-view identity across locale changes and separate
analysis scenario identities. New actual prepared-source Apple SDK/rendering
execution and the #198 owner caller composition remain receiving requirements.
The separate #377 localization continuation is not incorporated here.
