# Exact build identity at the budget boundary

This bounded correction contributes to [Apple #78](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/78).
The [scope reservation](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/78#issuecomment-6257028799)
keeps the existing cost presentation, native rendering and receiving work with
their current owners.

## Behavior

The public [CostSummary](../../Packages/PlannerCore/Sources/PlannerCore/CostCoverage.swift)
projection accepts a supplied build identity. Its budget assessment must belong
to that exact build and revision. Swift's normal String equality treats
canonically equivalent Unicode spellings as equal. At accepted source
`83bd1e612f00b62cf9099ad65579bc77ed19cad5`, an estimate for
`build.caf\u{00e9}` therefore assessed a budget for the byte-distinct
`build.cafe\u{0301}` as though it were the same build.

The build check now compares the supplied UTF-8 sequences. A different sequence
returns `unknown(staleBuild)` before a satisfied or exceeded verdict is possible.
All supplied values remain unchanged. Revision, period, rate applicability,
coverage, missing costs, unsupported meters, exact decimal arithmetic and
currency checks keep their existing order and behavior.

The frozen-v1 identifier schema restricts build IDs to ASCII. The reproduced
defect is in this public projection API; this evidence establishes no bypass
through the validated wire reader or application UI. No identifier normalization,
wire change, new pricing calculation or source-use permission is introduced.

## Regression and actual execution

The new `CostCoverageTests.testCanonicallyEquivalentBuildIDsRequireTheirOwnEstimate`
method checks both encoding directions at amounts 0, 20 and 110 against a budget
of 100. Those six wrong-build cases must remain stale. Independently reconstructed
exact identities retain their expected verdict, a changed revision remains
stale, and receiving an estimate for the newly selected identity recovers.
The six preceding cost test methods and their helpers remain unchanged.

Actual local execution used Swift 6.1.2 on x86_64 Linux, serial SwiftPM jobs,
the unchanged package dependencies and task-owned caches:

| Source and invocation | Actual XCTest result |
| --- | --- |
| Original production helper plus the new focused regression | Seven methods executed: six preceding methods passed; the new method failed its six wrong-build assertions. |
| Corrected complete debug Core package | All 95 declared methods passed; zero failures or skips; 5.469-second test summary. |
| Corrected complete optimized Core package, ordinary process access | All 95 declared methods passed; zero failures or skips; 1.580-second test summary. |

The initial optimized full-package and focused-cost invocations under restricted
process access each aborted with SIGILL during execution. Their original logs
remain retained as failed runs. The focused attempt passed the new method before
the crash while an unchanged cost method was starting. The identical source then
passed the complete optimized suite with ordinary process access; no source or
test was removed or modified between these invocations. This records the observed
execution boundary without assigning an unverified runtime root cause.

Retained original log identities:

| Log | UTF-8 bytes | SHA-256 |
| --- | ---: | --- |
| Original focused failure | 6,768 | `a31f1fdeb25bf1376aca2d848256f5a168c23035e9977d808d40aca33714e3d0` |
| Corrected complete debug | 24,959 | `eeca3bb65456974f468b6bf2d88bdc341693351d6d597225c7c569e6b5f76169` |
| Initial optimized failure | 3,993 | `99caa459492b823c45b52eed359218e2cc03d591c834588353cfec995cf56fe4` |
| Focused optimized failure | 2,613 | `bfbcf4340424553eb220012f0f60cf8f9e38865f16aa7318e6191c182670eafe` |
| Corrected complete optimized | 24,765 | `e58ecbc0ab0df84b2e1a32d742c42132c4066cf304199371fad3b6714bfba58d` |

Reproduce from the repository root with a working Swift toolchain and writable
compiler/package caches:

```sh
swift test --jobs 1 --package-path Packages/PlannerCore --filter CostCoverageTests
swift test --jobs 1 --package-path Packages/PlannerCore
swift test --jobs 1 --package-path Packages/PlannerCore -c release
```

Independent receiving review, all applicable exact-source macOS/iOS checks and
ordinary signed delivery remain required. These synthetic package results do not
supply canonical service pricing, rendering/accessibility results, physical-device
or release acceptance. The complete #78 criteria remain open.
