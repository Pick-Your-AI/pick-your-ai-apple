# Analysis identity: exact input admission and validation

This is a bounded implementation and reproducibility record for
[Apple #75 / IOS-09.06](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/75).
The [three-path reservation](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/75#issuecomment-6256840249)
covers the generic analysis store, its new identity regressions and this record.
It does not complete the issue's service, visible-revision or reconnect acceptance.

## Changed behavior and boundary

The generic [AnalysisIdentity](../../Packages/PlannerCore/Sources/PlannerCore/AnalysisStore.swift)
accepts opaque build IDs, revisions and version-lock keys/values. Swift's
[String equality](https://developer.apple.com/documentation/swift/string)
treats canonically equivalent Unicode spellings as equal. For example,
`caf\u{00e9}` and `cafe\u{0301}` have different UTF-8 bytes even though Swift's
text comparison considers them equivalent. Synthesized identity equality
therefore admitted a response for byte-distinct inputs and failed to retire
pending/current work when the selected opaque identity changed.

Identity equality now compares the original UTF-8 build/revision sequences and
the complete set of exact UTF-8 lock key/value entries. Lock-map insertion order
has no meaning. No text is normalized or rewritten, and no new syntax restriction
is imposed. The existing `[String: String]` input still has Swift dictionary key
semantics; equality compares the entries actually supplied and cannot recover
keys already collapsed while the caller constructed that dictionary.

A byte-distinct response is rejected without consuming the active request.
Selecting byte-distinct inputs immediately invalidates pending and current
results; a late receive, failure or cancellation from the retired request cannot
change the new state. An exact identity reconstructed with another lock insertion
order preserves the pending/current result. Request generations and all actor
transition code remain unchanged.

The [typed frozen-v1 evaluation adapter](../../Packages/PlannerCore/Sources/PlannerCore/EvaluationAnalysis.swift)
remains separate. Its response comes from
[EvaluationReport.decode](../../Packages/PlannerCore/Sources/PlannerCore/EvaluationReport.swift),
whose relevant IDs are ASCII-constrained, revisions are positive integers and
ruleset versions use the existing ASCII version profile. This reproduction uses
the generic store's unrestricted opaque inputs; it does not demonstrate a bypass
through that validated adapter or an installed app. The decoder, frozen schema,
fixtures, evaluator and transport are unchanged.

## Reproducible cases

The six methods in
[AnalysisIdentityTests](../../Packages/PlannerCore/Tests/PlannerCoreTests/AnalysisIdentityTests.swift)
use actual actor calls and method-local state. They cover:

- Build ID, revision, lock key and lock value spelling differences, in both
  composed-to-decomposed and decomposed-to-composed directions.
- Response rejection followed by acceptance of the exact matching response on
  the still-pending request.
- Selection changes followed separately by each late receive, failure and
  cancellation, then recovery with a new exact request.
- Invalidation of an already-current result after a byte-distinct selection.
- Exact lock-map reordering, missing/changed entries, and preservation of pending
  and current state after a genuinely identical reselection.

All inputs and results are synthetic. No network cancellation or timing sleep is
used to make an obsolete callback harmless.

From the repository root, using the selected Swift toolchain and writable
task-local package/compiler caches:

```sh
swift test --package-path Packages/PlannerCore --jobs 1 --filter AnalysisIdentityTests
swift test --package-path Packages/PlannerCore --jobs 1
swift test --package-path Packages/PlannerCore --jobs 1 --configuration release
```

## Actual local execution

The baseline was signed accepted main
`83bd1e612f00b62cf9099ad65579bc77ed19cad5`, including the separately accepted
source-use identity correction. Adding only the six new tests produced tree
`1d9c3c676d2563beb12e2a693f25cb8767ddb6e4`: four methods failed with 96 assertion
failures while both positive-control methods passed. This is a failing test
receipt, not a compiler/setup failure.

Adding the 15-line identity equality correction produced tested tree
`14f4ca6c9bbdc645ae538a2ca2350aa26a523ead`. Actual Linux
`x86_64-unknown-linux-gnu` Swift 6.1.2 runs then passed all six focused methods,
all 100 Core Debug methods and all 100 Core Release methods, with zero failures
or skips. The same 193 source-file hashes and modes were verified before and
after every command. This documentation was added after those executions; the
tested Swift source and tests are unchanged.

| Original command log | Result | SHA-256 |
| --- | --- | --- |
| `identity-red.log` | 6 methods: 4 failed, 2 passed; 96 assertion failures; exit 1 | `33a571ceea4d2efce3c17f318f9c975f8607062a87bd3e9fe551652921ee2269` |
| `identity-green.log` | 6 passed; exit 0 | `35622760b92e47fd2c4b35cef14925826d0a046b50759936d1fde160e15d2fb6` |
| `core-debug.log` | 100 passed; exit 0 | `2f04b1f5903c888530ed67cd26d109d65f6b99f046963e509830935e34d8e4ab` |
| `core-release.log` | 100 passed; exit 0 | `82ff645f5868c18c1af88bd8b85e88670f7deb8559ff0d009b5954ce7ae1440f` |

The retained originals include full commands, actual toolchain output and
per-command source proofs. Host clock strings in the XCTest logs are retained
as emitted; they are not substituted for GitHub execution timestamps. The
separate Swift Testing footer reports zero tests because these methods execute
through XCTest; it does not replace the XCTest counts above.

## Receiving and criterion disposition

Independent source review, the configured macOS/iOS SDK workflow and exact
current-main receiving checks remain delivery gates. Record their actual heads,
trees, native results and review links on the delivering PR and #75; do not
relabel these Linux executions as native or as a later composition.

| Original #75 acceptance criterion | Evidence from this slice | Remaining acceptance |
| --- | --- | --- |
| Only analysis for the visible revision receives current status. | Exact generic input comparison and actor selection/response regressions | Governed service inputs, the #71 recomputation/unavailability output and actual visible-revision UI integration |
| Reconnect while three successive revisions finish out of order; only the visible revision is current and cancellation cannot erase the latest matching result. | Full existing Core suite remains green; new byte-distinct selection and late-callback cases are deterministic package executions | Integrated three-revision reconnect and cancellation replay through the actual transport and visible UI |
| The race/cancellation/reconnect reproducibility log is linked with criterion results, exact versions, limitations and receiving-review disposition. | This bounded negative/recovery record pins exact source, toolchain, commands and log digests | Exact native delivery receipts, the complete integrated replay and governed-evaluator/Apple-consumer receiving disposition |

All three issue criteria remain open for their full scopes. This change grants
no new rights, production data, service deployment, physical-device, TestFlight,
App Store or installed-release acceptance.
