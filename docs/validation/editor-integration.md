# Combined editor, startup and native journey integration

This record tracks a receiving integration for partial [#29](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/29),
[#57](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/57) and
[#69](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/69) work. It carries the
reviewed Files/startup and actual UI harness prerequisites while consolidating the
overlapping editor corrections. No issue is closed by this source composition alone.

## Retained source identities

| Source | Exact consumed revision | Retained behavior |
| --- | --- | --- |
| [#187 autosave and undo](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/187) | `de09f59eb7bdedf2e694f18da6b1732fb7542a87` | Production 750 ms timer, input generations, bounded session history, discard freeze and queued-read guards; all 13 controlled model and two history tests |
| [#178 recovery notices](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/178) | `8296ef95c244504df9f91fec54dd0c8c13e253be` | Successful library reads clear only their own failure; editor failures and saved acknowledgements remain; three recovery regressions |
| [#181 delayed open](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/181) | `c14fb6f27c2b544aa5cd21e3c1d8ca0d36fb0108` | Both controlled read/lifecycle-save regressions and adapter pauses; #187's stronger captured-generation source guard is canonical |
| [#184 Files and startup](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/184) | `aa537c4dcacca0bdecdec201759542f9f3acbe71` | Independent local stores, asynchronous cancellable startup, bounded preview/fork/export and all existing regression cases |
| [#188 real UI harness](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/188) | `8c8013111833a3500665bcfee841a1debb792dd4` | Xcode UI target, owned exact simulator destinations, retained result/cleanup evidence and portable runner tests |
| Accepted main | `b56bf5712b4a76a6c88ee4e4dfcb0adfc6dd24c4` | Delivered receipts, privacy guidance, domain/history behavior, accurate empty-page copy, workflow concurrency and reviewed obsolete-run maintenance |

The notice merge preserves both notice channels inside the generation-guarded
adoption and restoration paths. The five imported notice/delayed-open tests use the
existing internal `autosaveWait: nil` initializer so their controlled storage races
do not depend on wall-clock speed. The startup responsiveness test now creates and
selects an actual synthetic draft before the opener is blocked; nil debounce isolates
that scheduling test. Its main-actor action must still complete before opener release.
The public app initializer always retains the production debounce.

## Native UI reconciliation

The prior UI harness waited for an enabled Save button and tried to open the discard
dialog before a valid amendment saved. Both assumptions race a real typing debounce.
The [revised journey](../../App/UI_JOURNEY.md) waits for normal autosave, then proves
durability by reopening exact title/notes after close and process relaunch. Undo and
redo must each append a distinct next revision with the expected title, read through
the normal history control; a final reopen also verifies the complete text.

For discard, the test pastes one 1025-byte ASCII amendment through the standard
edit menu. Actual storage rejects the over-limit title, leaving the amendment dirty.
The test requires that new failure notice, discards through the normal confirmation,
then verifies the prior committed text. It changes no timer, application storage path,
validation bound or launch behavior. The clipboard contains synthetic text only and
is cleared after use on the runner's newly created owned simulator. Exact-ID deletion,
the separately saved control, positive successful reload checks and scoped simulator
cleanup remain mandatory.

## Evidence and remaining gates

The combined package contains 52 XCTest cases: 22 editor/library model,
13 controlled autosave, two bounded history, seven imported-build, six startup and
two independent-store cases. [Run 39100534357 / job 117595708300](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39100534357/job/117595708300)
at `206fbb0a97673bc03246af6175411c3eff11f4a4` executed all 52 with zero failures and
passed the unsigned build and launch smoke. Its complete iPad UI journey passed;
iPhone failed before the first history read while the scroll helper repeatedly swiped
the first hittable collection, which can select the library behind the editor sheet.
The focused correction binds every
reveal gesture to the new `draftEditorForm` identifier and keeps every assertion.
The retained failure artifact is `12126633882`, SHA-256
`96bf09374aeafe7490166ae74dac7039df15fedbe7ea2b6536eb2cf52f5cbb31`.
The runner still requires exactly one passed journey, zero failures/skips and successful
owned cleanup on each pinned iPhone/iPad destination. Swift/Xcode are unavailable in
the local preparation workspace. Both destinations must pass on the corrected head
before this integration qualifies for signed delivery.

Earlier [#181 native execution](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39095778902/job/117581802505)
passed its 19 model cases, including both retained delayed-open scenarios, and its
unsigned build/launch checks. Earlier [#188 harness execution](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39094714003/job/117578640861)
passed the pre-autosave journey on both pinned destinations. These results identify
their original revisions; they do not replace the combined candidate's exact-head
native model execution, unsigned compilation and revised two-destination UI journey.

Independent receiving review must cover the full cumulative source and this integration
delta. Preserve applicable exact-head checks and ordinary signed delivery; verify the
signed candidate's tree and parent before main integration. Link final receipts from
the PR. Physical-device, accessibility, unacknowledged process termination, complete
builder/Files-provider flows, real-data rights, release and broader issue acceptance
remain separately evidenced requirements.
