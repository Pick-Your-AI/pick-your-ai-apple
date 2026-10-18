# Imported-build preparation off the main actor

This is a focused follow-up for [Apple #29](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/29)
against the canonical imported-library model in [#193](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/193)
at `d3ee5730257409f54c1def217051eba14a879122`. That source already moves persisted-wrapper
decoding, page inspection and atomic-fork preparation off the main actor. The remaining
preview parser and export projection/encoding still ran synchronously on the actor
that presents the UI. A bounded input limits resource use but does not establish
main-actor responsiveness by itself.

## Behavior and interfaces

The existing detached `offMain` boundary now executes the actual frozen preview
validator for both data and Files input. Security-scoped access still encloses only
the bounded file read and ends before parsing. `preparePreview(_:)` is now async and
throwing; programmatic callers await it before using the preview. The app retains its
existing `previewFile(_:)` route. Canceled callers cannot publish a preview, create a
storage row or report a late preview error.

Export preparation also performs projection, validation and final JSON encoding on
that worker. `prepareExport(publicAlias:)` synchronously captures the selected row and
revision, immutable snapshot, qualification and alias, marks the model busy, and
returns its optional `Task<Void, Never>`. This preserves the existing UI call and
captures intent before a queued task could read changed state. Programmatic callers
can await its `value` or cancel it. A refused request returns nil.

`clearExport()` invalidates the generation as well as clearing bytes, including when
an alias binding changes before the task starts or while preparation is suspended.
Both success and failure publication require the same generation and selected
row/revision. Changing selection also invalidates prepared exports. Cancellation is
checked before unwrapping either worker success or worker error and again on the main
actor immediately before publishing or rethrowing. A worker that throws a validation
error after cancellation therefore cannot bypass cancellation handling. The busy guard retains
the existing operation ordering; this change does not allow concurrent storage writes.

The internal Sendable preparation dependency wraps the same `BuildTransfer` validator
and exporter. The public initializer always uses that live implementation. There is
no unchecked public snapshot initializer, alternate wire format, second import flow,
new source authority or relaxed byte/privacy bound. Synthetic envelopes retain their
untrusted source revision and fixture label, and export still requires the user to
review the exact projected text and alias before using the system file exporter.

## Controlled native regressions

The new tests use a lock-protected preparation probe and a bounded synchronous wait
inside the worker. An async dispatch wait lets the test remain on MainActor. A real
notes editor processes a binding action before the worker is released, and only that
test-created amendment is discarded. The five-second timeout prevents a regression
from deadlocking CI; it is not a performance target or benchmark result. The worker
continues through the real validator/exporter after release, including when it has
been canceled. The cancellation cases also release a worker that throws a non-cancellation
validation error. Both outcomes test rejection independently of cooperative work.

| Required test | Observed assertion when executed |
| --- | --- |
| `testPreviewPreparationLeavesMainActorResponsive` | Both data and Files preview run off-main; another real editor changes before release; selected immutable data and durable storage remain unchanged |
| `testCancelledPreviewPreparationCannotPublishOrWrite` | Late success and validation error are rejected for both data and Files routes; caller cancellation retains the selected fork and leaves no preview, row or stale failure |
| `testExportPreparationLeavesMainActorResponsiveAndPreservesQualification` | MainActor continues before export release; the result has the exact public alias, identity, locks and synthetic/source qualification |
| `testClearedExportRejectsLateBytesAndErrorsAndRetryUsesNewAlias` | Alias invalidation rejects both late success and late error; an explicit retry prepares only the new alias |
| `testInvalidatedQueuedExportNeverEntersPreparation` | Invalidation on the initiating actor turn prevents the queued task from entering preparation at all |
| `testCancelledExportPreparationCannotPublishOrWrite` | Neither late success nor a late validation error from a canceled worker can publish export bytes or failure, mutate selection, append a revision or create another row |

Each case reopens the real SQLite database and compares the exact selected record,
its single retained history revision and the complete one-row library. The fourteen
existing import/CRUD tests remain and now await preparation acknowledgement where
needed. Native CI retains its prior seven required case names and additionally requires
all six new names to report a pass in the full PlannerUI suite.

## Integration and evidence limits

Source preparation occurs in an isolated checkout; it does not modify the active #193
branch or the reviewed editor/UI integration [#198](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198).
Preserve both canonical sources and newer accepted main work when integrating this
delta. The final combined candidate requires independent review, exact hosted native
execution, normal signing and receiving main checks. Swift/Xcode are unavailable in
the local preparation workspace, so no native pass is claimed here.

These tests establish their named scheduling, cancellation and stale-result boundaries
only after native execution. UI Files-provider cancellation, physical device/locked
storage behavior, measured latency, accessibility, interrupted writes, full #29/#57
acceptance and release remain separately evidenced requirements.
