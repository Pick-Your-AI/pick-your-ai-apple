# Editor undo and debounced autosave

Partial implementation for [Apple #69](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/69),
built on the reviewed revision-history/lifecycle-save boundary in
[PR #158](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/158).
The notes editor remains separate from validated BuildSnapshot data.

## Behavior

An edit to the title or notes schedules one save after 750 milliseconds without
another edit. A newer edit cancels and supersedes that timer. Each timer also checks
the captured draft identity and generation before it can request a save. A cancelled
timer cannot save a subsequently opened draft, even if its clock completes late.
Manual Save and background lifecycle saves cancel the waiting timer and use the
same existing compare-and-swap storage path. Saves requested during another awaited
operation are drained against the latest text and committed revision. A successful
write reevaluates later input against its newly acknowledged baseline, including
text that had returned to the previous baseline while that write was suspended.

Typing remains enabled while a save or history read awaits storage. Destructive
deletion rejects binding edits, and conflicting or invalid writes retain the dirty
text. A failed autosave is not automatically retried forever: the editor shows the
failure, and a corrected edit or explicit Save can retry. A delayed open cannot
replace input that arrived in the original editor while its read was suspended.
Restoration tracks edits to each field, so typing away from and back to an earlier
value during the restore cannot be mistaken for an untouched field.

Close freezes pending input while its discard confirmation is visible. The model
cancels the timer and queued save intent, suspends lifecycle saves, and rejects
queued library/history reads that could otherwise block the destructive action.
Cancelling the decision resumes debounce; confirming it closes without committing
the amendment. A write already awaiting acknowledgement must finish before a
discard decision can start. Dismissing the dialog binding before its destructive
action cannot leave a rearmed timer able to save the discarded draft.

Undo and redo track title/notes binding changes and successful restoration changes
within the current editing session. They retain at most 100 states and 4 MiB of
combined UTF-8 text across both directions. Oldest states are discarded at those
bounds. Text too large to retain safely for redo is never silently discarded by an
undo operation. A new edit clears the redo branch; changing or closing the selected
draft clears transient history. Ordinary saves preserve that session history.

Undo after an acknowledged save makes a new dirty edit. Saving it appends a new
revision; no previously acknowledged revision is rewritten or removed. A restoration
followed by a newer edit can be undone in order, while both the restoration and the
newer saved revision remain available in durable history. These states carry no
compatibility, price, or approval evidence. Every DraftRecord still reports analysis
as not current.

## Validation

Run on the selected macOS/Xcode toolchain:

```sh
swift test --package-path Packages/PlannerUI
```

Thirteen new model tests use a manually released clock and actual SQLite persistence.
The clock intentionally ignores cancellation so tests independently exercise the
generation/cancellation checks, without timing sleeps. A delayed storage adapter
exposes actor suspension points. Two additional pure history tests check entry and
byte bounds. Existing explicit-save model tests disable the timer through the
internal initializer to keep their separate race scenarios deterministic; the public
app initializer always enables the 750 ms debounce.

| Case | Required observed behavior |
| --- | --- |
| Two edits before the clock fires | Only the latest input creates revision 2; a fresh connection reopens exactly those acknowledged bytes |
| Discard confirmation remains visible | Cancelled timers and lifecycle callbacks cannot commit the pending amendment; a fresh connection retains the original revision after discard |
| Cancel the discard decision | The resumed debounce saves the retained input through the normal storage path |
| Dialog binding dismisses before its destructive action | Closing cancels the rearmed timer before it can save |
| A library/history command was queued before the discard decision | It performs no new storage read, cannot make Close busy, and cannot cause the amendment to be saved |
| Close a dirty draft, then open another | The old cancelled timer changes neither draft; the new draft saves only through its own timer |
| Second autosave while the first write is suspended | Later typing stays editable and is drained as the next revision |
| Input returns to the old baseline during a suspended write | The acknowledged write starts a new debounce; the final reverted input becomes the next durable revision |
| Late binding input while another draft is opening | Original selection and new input survive; the other draft is unchanged |
| A field changes and returns to its old value during restoration | That newer input is preserved and autosaved; the untouched field receives restored text |
| Invalid title during autosave | No acknowledgement or extra revision; corrected explicit retry succeeds |
| Undo/redo after saved edits | New revisions append without deleting the earlier saved text; a new edit invalidates redo |
| Restore, save a newer edit, then undo twice | Newer text and restoration remain in history while undo appends revisions in sequence |
| History entry and memory bounds | Both directions remain bounded; an oversized current state cannot be discarded by an unsafe undo |

Local static review and whitespace validation do not establish Swift execution.
This workspace has no Swift/Xcode toolchain; the exact published candidate must pass
the existing hosted native model tests, unsigned app build, and iPhone/iPad simulator
checks before integration. Independent review and those receipts must be linked
from the PR.

The app journey introduced by [PR #188](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/188) predates the production debounce and waits
for a manually enabled Save button. Its save/discard timing assumptions must be
reconciled with this behavior on integration and verified on both native simulator
destinations. The model tests do not replace that production-timer UI evidence.

## Remaining issue acceptance

The transient undo stack is not serialized. After process termination, acknowledged
content and revisions recover through the existing storage and revision-history
implementation. Unacknowledged text can still be lost if the OS terminates the app
before an autosave commits. This patch does not claim an actual process-kill test
during UI autosave, a complete stack-builder/optional-tier journey, accessibility or
physical-device qualification, real-data acceptance, signing, or release. Those
unexecuted #69 criteria remain open. No database or shared contract format changes.
