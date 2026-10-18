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
It collects labels while scrolling, including later materialized content in the
negative assertions. An empty tree, missing text, wrong case, incomplete sequence
or content that does not settle within the bounded scan fails. The app uses its
normal SwiftUI window/scene lifecycle. There is no private accessibility activation,
view reflection or host-computed expected text.

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

Local correction preparation used Swift 6.1.2 syntax parsing for both new Swift
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
