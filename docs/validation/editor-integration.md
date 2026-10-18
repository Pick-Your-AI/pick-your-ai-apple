# Combined editor, startup and native journey integration

This receipt retains the canonical #198 source history and its named results. The later [catalog/editor receiving composition](catalog-editor-receiving.md) preserves these behaviors and tests with separate current totals and execution gates.

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

## Receiving union with comparison and import preparation

The receiving tree was prepared on accepted main
`0397de2095506440a3516438550cd38289afc31e` and reconciled with signed main
`86107aaed183b8064ca1f5f0bee1c8a8672ae691`. It keeps the pinned toolchain,
empty-cache assertions, security and toolchain receipts, bounded obsolete-run
maintenance, conservative documentation-scope preflights, and the exact reviewed
catalog sort delivered through [#203](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/203).
The accepted local serializer's bounded round-trip guard and its two regressions
also remain alongside the imported-library wrapper validation. The accepted
platform decision is preserved in the reconciled repository scope. The source and
workflow changes in this candidate still require every native job; a skipped
documentation job is not execution evidence. It then retains these independently
reviewed component versions:

| Component | Consumed source | Union check |
| --- | --- | --- |
| Corrected editor and UI journey | [#198](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198), `6d3501cc90aeb98f872f7289c8c9b4946b84f9f7` | Editor model/view, autosave/history tests, selected-draft startup tests, actual UI journey and owned runner remain byte-identical |
| Comparison and atomic imported-library CRUD | Signed [#193](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/193), `7deb8ddff5fb58efbceb74d89d0fe8404a3db4c1` | Canonical comparison presentation and prepared-duplicate transaction/tests retained; wrapper validation, revision checks and committed-ID baseline invalidation retained |
| Preview/export worker and cancellation correction | [#208](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/208), `16e5e364e2236eb044a6307f498619a562d873f8` | All three preparation/model/test files and the import view match the reviewed source; cancellation rejects both late success and error |

Workflow reconciliation retains the main toolchain and fresh-cache paths, all
thirteen required imported-library test names, the 28-case storage/abrupt-exit gates,
and the complete actual iPhone/iPad journey. No source component was replaced with
another implementation. The README combines the pin/setup instructions with the
editor, startup, comparison, CRUD and worker behavior instead of dropping either
side of the integration conflicts.

The combined PlannerUI package declares 68 cases: 22 editor/library, 13 autosave,
two bounded history, 20 imported-library, six startup, two independent-store and
three comparison-presentation tests. All 26 portable pin/runner tests passed in this
receiving checkout, and 27 critical source/test/maintenance blobs were compared
against their exact listed revisions. This source composition and portable execution
do not establish a combined Swift or UI pass. The frozen final receiving head needs
independent integration review and actual hosted native execution before delivery.

## Earlier execution and remaining gates

The retained #208 worker source `16e5e364e2236eb044a6307f498619a562d873f8`
failed native compilation in
[run 39102893041 / job 117602617289](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39102893041/job/117602617289).
Two export tests accessed `JSONValue.object`, which is an internal helper in the
separate transfer module. The correction destructures the public `.object` enum
case at both sites, failing explicitly if the exported root is not an object, and
retains both exact alias assertions. No production API, case name or native gate
changes. The failed source did not execute its model suite; the same test bytes in
the first combined `29e4055cbdc23a27732059550639d2140b28653a` candidate also require
this correction before its 68 declared cases can compile and execute.

The corrected combined head `460f9a833277a0601ba11ab774f64ee371baa555` subsequently
executed all **68 model cases with zero failures** in 26.935 seconds in
[run 39107785886 / job 117617303097](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39107785886/job/117617303097).
Its unsigned app build and both launch smokes passed. iPad completed the full
production-autosave/undo/redo/discard/deletion journey in 230.667 seconds; iPhone
failed in 69.661 seconds at `LocalDraftJourneyTests.swift:236`, because six upward
swipes of the exact `draftEditorForm` did not reveal `loadRevisions`. The iPhone
had already reopened the exact durable notes after process relaunch. Frames before
and after the swipes show the same focused title, software keyboard and obscured
lower Form. This is a different failure from the earlier invalid startup geometry.
Both destinations executed one test with zero skips, and both owned deletions
returned exit code zero. Artifact `12130423258` is 87,422,438 bytes; its downloaded
archive matches SHA-256
`94dcec95d6d25bebf6bdcf7d9eda2f5e32cf67b1820cebfd2ae18430f12f439b`.

The focused follow-up adds a visible **Done editing** keyboard control for both
editor fields and makes the UI journey use it, requiring the software keyboard to
disappear before scrolling the Form. Clearing focus neither calls Save nor changes
the model's text, history or discard rules. All 68 model names, production debounce,
durable revision assertions, owned cleanup, native pins and both destination gates
remain. The changed view and UI journey still require fresh native execution;
the 460 result is retained failure evidence, not acceptance of this correction.

The keyboard-control head `8ab4358c1b892db20e20e5876cbb63342186d2eb` then ran in
[run 39112764752 / job 117632218026](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39112764752/job/117632218026).
All **68 model cases passed with zero failures** in 27.478 seconds; the unsigned
app build and both launch smokes also passed. The complete iPhone journey passed
in 231.216 seconds. iPad failed in 213.814 seconds at
`LocalDraftJourneyTests.swift:265`, waiting for `finishDraftEditing` to be hittable
after the synthetic oversized paste. It had already reopened the exact durable
undo/redo title and notes. The recording identifies the obstruction: the system's
first-use keyboard gesture tutorial covers the app's otherwise present Done
editing control. Its automatically rotating pages show Undo, Undo and Redo, and
Copy and Paste with Continue. The summaries contain one executed test per device,
one iPad failure and zero skips. Both owned deletions returned exit zero. Artifact
`12131687533` is 111,650,150 bytes; its complete downloaded archive matches SHA-256
`df4d7e08e8525f7a1c9caeccca2925fb81cc33f12ac2afbb7539949157dfd2ba`.

The focused test-only follow-up identifies those three exact tutorial sentences
after Paste, uses Continue only for that known introduction, and requires it to
disappear together with its Continue button. Both retained accessibility captures
include a trailing newline in the Undo sentence; the exact membership list includes
that observed variant alongside the plain sentence. The other two labels match
without a trailing newline. A three-second appearance bound
accommodates the first-use overlay;
unknown dialogs still fail the normal strict control checks. The exact pasted
title is checked again after dismissal. The product view, all 68 model tests,
production debounce, real validation failure, dirty discard, history and durable
reopening assertions, runner, pins and both destination gates remain unchanged.
The failed 8ab run is preserved; the correction requires fresh native execution.

## Accepted-main history recovery

The current-main composition incorporates signed history recovery
`8ca109963bfca3a707b1af8b80aabcd9dd28fd8a` from #237 into the canonical editor,
including the exact newline-label supplement `b9f2052fb4f083f4164334e083ec40118c488696`.
It preserves the editor's input and per-field generations, queued-save drain,
undo/redo, discard freeze, acknowledgement rules and production autosave. A history
read records or clears only its own notice; action notices retain priority over
history notices, which retain priority over library-refresh notices. Clearing the
history context clears its corresponding notice.

All 22 existing library model test methods remain unchanged. The three accepted history
recovery methods are retained with only the existing `autosaveWait: nil` injection
used by deterministic model tests. They cover failed-page context and successful
retry, independent conflict guidance, and an outstanding library-refresh failure.
The composed package contains 71 unique model cases. The native workflow requires
the three new methods to report passed in addition to its existing 13 imported-build
method checks. Both full pinned UI journeys and owned cleanup remain mandatory.

The prior 68-case results remain attributed to their original sources. The combined
`877f8f16447be2698ba43079ff4ef8066f85a2c4`, tree
`1bfc17779920d4e12b41e20f58288e97d37fe30c`, subsequently executed in
[run 39118569803 / job 117649322901](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39118569803/job/117649322901).
The actual test checkout `d9a4f7fd6be9f61996fed5bc4b0698ed3067867e` has that same tree.
All **71 model cases passed with zero failures** in 26.516 seconds, including all
three accepted history regressions. The unsigned app build and both launch smokes
passed. The complete iPhone journey passed in 216.071 seconds; iPad failed in
149.385 seconds at `LocalDraftJourneyTests.swift:288`, waiting for
`finishDraftEditing` to become hittable and enabled after synthetic Paste. Its
durable undo/redo reopening had already passed. Each destination executed one test
with zero skips; both owned deletions returned exit zero and cleanup succeeded.

The complete retained artifact `12135102483` is 107,853,028 bytes. Its independently
downloaded ZIP passes CRC checks and has SHA-256
`c6bf8aa9696b9db3c1effe61c70892aa32008620152fe09e47104c690dbc3e4a`.
The iPad recording at 134 and 137 seconds shows the Undo tutorial covering Done;
at 145 seconds it has rotated to Copy and Paste. The decoded app payload
`mtI7JpDswgc6pR8uZlVuoIZ7GMI80Qa_nk6SGQK2Ql3zYkEGkSKWnGAEGKEmfJ4uwvJzjjswTTc58ZEKqmsw7g`
contains 17,500,648 bytes, SHA-256
`89c2e93f94830d1fa579e167423664b855aaaac8d6c9ca7db2c97d32427d7ec3`.
It records the raw Undo label with trailing U+000A, then the query snapshot at
11:23:30.459750 with trailing U+0020 and no matching result from the prior list.
The decoded runner payload
`Mc3cSCwIIXbV7AlI2Dlm4USB478IKmjuv4Sel7qLuDuESVM08gviqnpe8YjfM4WWPGuQx_G_3Zgigo_NefP6lg`
contains 6,889,709 bytes, SHA-256
`763f9b9aa66a7e945dba3fb39c27af8754cc57ef0fbf12db6ea898406c84b0b0`.
The focused follow-up retains the raw label and adds only the exact observed
trailing-space form. Continue must still be identified through a known sentence,
both the button and tutorial must disappear, and the complete pasted value must
remain unchanged before the strict Done/keyboard/Form checks. Production code,
autosave, failed validation, dirty discard, runner and destination gates are unchanged.
The failed 877 result is preserved; the corrected source requires fresh native
execution and both complete pinned journeys before signed delivery.

The original #198 source package contains 52 XCTest cases: 22 editor/library model,
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

The corrected `6d3501cc90aeb98f872f7289c8c9b4946b84f9f7` attempt in
[run 39102630153 / job 117601837621](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39102630153/job/117601837621)
again passed all 52 model cases, unsigned build and launch smoke. Its complete iPad
journey passed in 237.305 seconds. iPhone failed in 43.669 seconds at the first
`newDraft` hittability query, before opening the editor. Its retained debug attachment
reports `{{inf, inf}, {0.0, 0.0}}` for the entire main window and every ancestor,
while the screen recording shows the normally rendered Notes page and toolbar.
That evidence supports an automation geometry/readiness failure; it does not prove
the iPhone Form correction or justify changing app layout or weakening assertions.
Both owned cleanups succeeded. The result summaries contain one iPhone failure,
one iPad pass and zero skips. Artifact `12127539603` is 63,026,446 bytes; its downloaded
archive was independently checked against SHA-256
`82c5435875330478714f458d4ab0d63bdb992ee19e704931212ff8f92a1af432`.

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

## Completed corrected editor execution

The exact query-label correction at
`8e76d0ee3db9659df4b7c96bef0eb0c70909ea52` completed
[run 39124384850 / job 117666403863](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39124384850/job/117666403863).
The actual checkout was `1626e530da7577cab88f9c7718896c3a48319564`, with ordered
parents `a86b0bf88abdb8f9c2177fd54ea4d5f22bb5ddf7` and that source head. Git Data
independently confirms tree `d61176786e1886e16bced6788c8052126a9aeb7e` equals the
reviewed source. The gate verified Xcode 16.4/16F6 and Swift 6.1.2 before execution.

All **71 model cases passed with zero failures** in 28.281 seconds. The unsigned
app build and both launch checks passed. The complete production-autosave,
durable undo/redo, rejected-amendment, discard and deletion journey passed on
iPhone SE (3rd generation), iOS 18.5, in **279.590 seconds**, and on iPad
(10th generation), iOS 18.5, in **244.912 seconds**. Each actual result summary
contains exactly one passing test, zero failures, zero expected failures and zero
skips. Both runner receipts identify devices created by that run and record
successful cleanup. Both deletions exited zero; both shutdown commands retained
exit 149 with the explicit already-Shutdown diagnostic.

Artifact [12136704709](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39124384850/artifacts/12136704709)
was independently downloaded and rehashed: 5,556,775 bytes, SHA-256
`6382cf178df4ed916bc4a8016a646138f497f69ab7b275f505167bba5cbde548`.
The exact iPhone and iPad summary hashes are
`c6fa6588a9f688c184e15a956daf037a7f0f35b4971ededf3c4d83473184198f`
and `65956fe0bf5681e6a8e75c733bb35daa1d81470b7f0ecad19a47c268a9facaaf`.
Core, Storage, Catalog and macOS Transfer native jobs also passed on that head.

The separate Transfer documentation-scope job still failed with the recorded
disposable-fixture cleanup error. The [foreground-maintenance correction](native-scope.md#disposable-git-fixture-lifetime)
at `10cd075c` is preserved for receiving execution; this successful UI result
does not erase that failed gate or prove the fixture diagnosis. The later
[comparison/catalog/current-contract union](comparison-preparation.md) requires
its own 96-case UI and 57-case Transfer execution, both complete Notes and catalog
journeys on each pinned destination, normal signing and receiving review. None
of those expanded-source results, physical-device or release acceptance is
inferred from this successful 71-case source run. All earlier failures above remain.
