# Native evidence rendering host

This isolated Xcode project exercises the production `ClaimEvidenceView` and
`EvaluationReportView` through a running SwiftUI application and public
[XCTest UI automation](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication).
It is a test tool with no distribution/archive target. It does not start the
Planner editor, open a `DraftStore`, contact a service or implement another
evidence projection. The application and UI-test target use local packages only.

`EvidenceRenderingTests` runs in the separate `PlannerEvidenceUITests` process.
Its four methods retain the original checks:

- All 28 valid shared payloads render their existing outcome, severity, presence
  and conflict text; other outcome/severity labels remain absent.
- The already reported pass/ready state stays separate from missing support at
  requested widths 375 and 820 with an accessibility text size. A horizontal
  viewport exposes the wide view on a compact screen.
- Seven original-status/inspection/support scenarios preserve the existing
  claim grade and never infer independent verification from a source claim.
- Three freshness/correction scenarios preserve retained identities, with a
  correction requiring recheck and no independent grade.

Both native targets copy the same existing
[37-case resource](../../Packages/PlannerUI/Tests/PlannerUITests/Fixtures/evidence-vectors.json).
The app decodes only IDs, payloads and validity; it does not read `visibleText`.
Tests send only one of four scenario-group IDs in launch arguments. Expected
strings stay in the test process and are never installed in app accessibility
labels. The original Core tests still execute all 37 decoder cases, including
the nine rejections and recovery of the prior report.

The test asserts a foreground app, the selected fixture ID and exact sequence
position, and actual native static-text elements under the content container.
It collects native text while scrolling, including later materialized content in
the negative assertions. On macOS the case and position use exact String values;
content retains both nonempty labels and String values from each static-text
element. A non-String value or an element with neither form fails instead of
being silently dropped. iOS continues to use labels. An empty tree, missing text,
wrong case, incomplete sequence or content that does not settle within the
bounded scan fails. The app uses its
normal SwiftUI window/scene lifecycle. There is no private accessibility activation,
view reflection or host-computed expected text.

On macOS, a foreground process with no own-app windows is prepared through its
standard **File > New Window** command. The existing English launch settings
identify that native menu. The command must exist and be enabled; it is used
only when the window query is empty, before the original error and case-marker
checks. An existing window with missing or wrong content receives no retry or
replacement window. A second window query just before selecting the command
dismisses the menu without creating another window if a window has appeared.
This fixture setup retains the normal `WindowGroup`, four
separate process launches, exact scenario/position checks and bounded waits.

## Actual failed predecessor and current qualification

At source `7d9724b16136546b686d87f29acf9bd95ca9c2eb`, prepared checkout
`29579d01a9369c0daa6365c3683ebe0617377e6a` / tree
`0c7c83e063af73785e4a124419767e6728c0cfb4`, the original package unit tests
created `NSHostingView`/`UIHostingController` windows and walked their native
accessibility containers. Both actual hosted runs returned empty trees: all
four methods failed with 238 assertions on each platform. Those results remain
in [the UIKit receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/277#issuecomment-6251477827)
and [the AppKit receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/277#issuecomment-6251515543).

| Original actual run | Retained complete job log |
| --- | --- |
| Core job 117690241313, run 39132448744 | 619,702 UTF-8 bytes; SHA-256 `893a5aebf4cb451085743e7a7fea8bd9dbcd949a7ddc30a00aaf58dcc4490eb9` |
| Native UI job 117690235303, run 39132448736 | 127,236 UTF-8 bytes; SHA-256 `291bb70a9f2c5a83e9368318101c10c9ddcf6f3b308d3a5b403ccc65c313e031` |

The correction moves the same behavioral obligations to this real application
boundary. Current-source native execution remains pending until the configured
jobs actually finish. Syntax parsing, source review and synthetic receipt tests
do not qualify its native behavior.

The subsequent [Core run 39141330983 / job 117716271583](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39141330983/job/117716271583)
at source `04f7b8bbe44115ec4d25bb62da40bf3ad6836ec2` and prepared checkout
`46ab56ae1153ddd009f82b424ca4a3224db5540c` reached the new iPhone harness
build, then failed before executing a rendering method. Xcode 16.4 / 16F6
compiled the harness for `x86_64-apple-ios-simulator` while its local
`PlannerCore` dependency supplied `arm64-apple-ios-simulator`. The harness
project now sets `ONLY_ACTIVE_ARCH = YES` for Debug, which the shared test
scheme selects. This aligns the application and UI-test targets with the
architecture of the selected destination without choosing an architecture by
name. Apple's [build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)
documents this setting; checked 2026-10-18. Release configuration, production
App configuration, all four rendering methods and their exact-text/negative
assertions remain unchanged. Fresh native execution on the selected macOS,
iPhone and iPad destinations is still required; the failed build supplies no
rendering pass or later mutation result.

At the next source `fddd221fca5a96fd0746776f6afcff911f8790ea`, prepared
checkout `e79c39a81305439114831d4ac3de080ce78b4aa2` / tree
`ce8336ee4464b86afaffe8161f0d1a1f8dde582a`, the original
[Core/iPhone/iPad receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/277#issuecomment-6253844126)
qualified all four actual rendering methods on each selected iPhone and iPad.
The separate [macOS job 117734702792 / run 39147645030](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39147645030/job/117734702792)
passed all 23 editor-model methods, built the test app and launched all four UI
methods in the foreground, then failed each first-case `label` predicate. Those
four failures in 54.044 seconds remain failed evidence; later production-app
build/launch steps were skipped.

The complete original macOS artifact `12148150605` is 93,703,324 bytes,
SHA-256 `fe4a70cacfc6e83c811759e71152d12bb8bee3c66d9bd6c3da677123f0ef31a0`.
Its retained accessibility descriptions expose the case and position as values,
body strings as values, and some headings as labels. The
[independent original diagnostic readback](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/277#issuecomment-6254194471)
records the exact decoded objects and hashes. This reader correction follows
those actual observations: macOS identity and position stay exact, and body
text includes both forms in the same positive and negative assertions. It does
not populate text from expected strings or relax a missing/invalid observation.
All four method identities, fixtures, scan bounds and forbidden outcome, severity
and grade checks remain required. Fresh macOS, iPhone and iPad execution on the
corrected source is still required; the preceding iOS passes belong to their
original source and prepared checkout.

Local accessibility-reader preparation parsed the corrected test source with
Swift 6.1.2 for both `arm64-apple-macosx15.0` and
`arm64-apple-ios17.0-simulator` conditional branches. This was syntax parsing,
not an Apple SDK compilation. All 30 existing pinned conformance methods passed
in 10.102 seconds, including both strict rendering-receipt methods and the
unchanged shared-vector checks. All 15 native-scope methods passed in 1.139
seconds. These results do not qualify corrected native rendering.

At source `d73ef71d64c13262211ef3872eac2ca0ea9c48c0`, prepared checkout
`a228a01d1c58cff68fd63b6726a6a709da15541b` / tree
`d48dc497be7e0536855b489c185143b5dc53337e`, the next
[macOS run 39160744445 / job 117773371470](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39160744445/job/117773371470)
passed all 23 editor-model methods and the seven-scenario claims method. The
remaining three rendering methods failed at the initial case-marker existence
assertion; the foreground assertion passed. Their complete captured app trees
contain menus and a Touch Bar, with no window or harness element. **File > New
Window** is present and enabled in each tree. The
[original archive receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/277#issuecomment-6254852976)
and [independent diagnostic readback](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/277#issuecomment-6254868328)
retain the exact artifact, decoded descriptions and hashes. No restoration
dialog or underlying OS restoration cause was established; the three failures
remain failures, and later build/launch stages in that job were skipped.

The bounded setup correction uses that observed native command to acquire the
fixture window. Apple's [menu-bar guide](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui)
documents the standard `WindowGroup` command; checked 2026-10-18. It changes no
host, scenario loader, production view, fixture, assertion expectation, scan
bound, Xcode project or workflow. The macOS 14 deployment target and iOS launch
path remain unchanged. Current-source execution must still pass all four
rendering methods on macOS, iPhone and iPad. This setup does not qualify default
launch restoration or any production application lifecycle.

The earlier local native-host preparation used Swift 6.1.2 syntax parsing for both new Swift
files; it did not compile an Apple SDK. The exact `jsonschema[format]` 4.25.1
reference environment passed all 30 conformance methods in 28.833 seconds, including both
updated explicit-module/session receipt methods and the unchanged 37-vector
checks. The complete log is 5,122 bytes, SHA-256
`0d317c9d3a77667056a023ee2fe9d11b18856dcbfec5a3053e0ec701175ddc83`.
All 15 conservative native-scope methods passed in 1.959 seconds; that log is
2,131 bytes, SHA-256
`73ae6cc35e69fd4eee2ccca906fb0f4fef9d1e601600e5d37857e079073bab2a`.
The 37 unique Xcode project objects, their references and input paths, and the
active shared UI-test scheme were checked locally. Actual Xcode project loading,
Apple SDK compilation and application/test execution remain hosted gates.

The existing native UI job runs all original editor-model methods, then these
four macOS UI tests before its separate production-app build/launch checks. The
existing Core job runs these four UI tests on its selected iPhone and iPad,
alongside all original Core and mutation gates. Both retain exact logs and
`.xcresult` bundles. No extra workflow job, remote task or parallel runner is
introduced.

From the repository root with the selected Apple toolchain:

```sh
xcodebuild test -project tools/evidence-rendering/EvidenceHarness.xcodeproj \
  -scheme EvidenceHarness -destination 'platform=macOS' \
  -only-testing:PlannerEvidenceUITests/EvidenceRenderingTests \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

For iOS, use the actual inventoried simulator UUID instead of the macOS
destination, as the checked-in Core workflow does. Require the real command to
succeed, retain its output, then run
`python3 tools/conformance/qualify_evidence_rendering.py /path/to/actual-test.log`.
The qualifier requires exactly one complete `All tests` or `Selected tests`
session, the explicit `PlannerEvidenceUITests` module and all four unique named
passes with zero failures/skips. The older `PlannerUITests` module, a bare class
name, duplicate sessions and compile-only logs cannot qualify this host.

This bounded native accessibility-text check is separate from physical devices,
full VoiceOver interaction, localization, pixel layout/contrast, signed release
and integration of these views into a complete user journey. The
[evidence mapping](../../Packages/PlannerUI/EVIDENCE_RENDERING.md) remains the
criterion-specific record for Apple #36.
