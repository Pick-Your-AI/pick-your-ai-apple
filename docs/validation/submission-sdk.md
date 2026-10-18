# Unsigned submission SDK compatibility

## Purpose and selected versions

The established Xcode 16.4 / 16F6 development baseline compiles with SDK 18.5.
Apple's [current upload rule](https://developer.apple.com/news/upcoming-requirements/?id=04282026a),
checked 2026-10-18, has required Xcode 26 or later and a version-26 SDK since
2026-04-28. A successful launch on a newer simulator runtime cannot repair that
compile-time SDK gap. The [#113 policy matrix](issue-113-policy.md) records the
broader applicability review and unresolved release evidence.

The [new workflow](../../.github/workflows/submission-sdk.yml) adds an independent
unsigned compatibility check while retaining every existing development lane:

| Input | Exact selection and provenance |
| --- | --- |
| Runner family | GitHub-hosted `macos-15`; actual OS and image version are recorded for each execution. |
| Xcode | [submission-toolchain.json](../../App/submission-toolchain.json): 26.3, build 17C529, `/Applications/Xcode_26.3.app/Contents/Developer`. |
| Device and simulator SDKs | [submission-sdk.json](../../App/submission-sdk.json): `iphoneos` 26.2 and `iphonesimulator` 26.2. |
| Deployment target | The selected app minimum remains 17.0; each built product must report that exact value. This is separate from Apple's [current minimum upload deployment target of 13](https://developer.apple.com/news/upcoming-requirements/). |
| Source of installed versions | Official [runner-images inventory at 07cc2190cd4d100d9f69478219017720c02c40f6](https://github.com/actions/runner-images/blob/07cc2190cd4d100d9f69478219017720c02c40f6/images/macos/macos-15-Readme.md), file blob `7b7aa2607800f9735b3062b0229bca92376e7bd2`, image `20260824.0482.1`. The inventory lists Xcode 26.3 / 17C529 with both SDKs at 26.2. |

The inventory supports the engineering selection; it is not a guarantee that a
future `macos-15` image still contains the bundle. Runtime verification must pass
before any package or app build. The script does not download or choose another
Xcode, SDK or simulator runtime. A pin update requires a source-reviewed change
and a fresh observed compatibility result.

## Execution and evidence

The workflow uses pinned checkout and artifact actions, read-only repository
permission, no persisted Git credentials and no cache restore. Its Ubuntu scope
job runs the SDK rejection tests and the existing conservative documentation
comparison. Unknown source/configuration changes still allocate the macOS job;
manual dispatch always runs it. Same-PR concurrency retires superseded attempts.
The two explanatory policy/SDK guides join the reviewed documentation allowlist;
the new JSON pins, Python scripts and workflow remain native inputs. The existing
[bounded obsolete-run helper](obsolete-pr-checks.md) also recognizes this exact
workflow path, preserving current heads, manual runs and reruns under the same
guards as the other native checks.

On the macOS runner, [submission_sdk.py](../../App/scripts/submission_sdk.py)
first reuses the [existing Xcode verifier](../../App/scripts/toolchain.py) and
then probes both SDKs with that verified `DEVELOPER_DIR`. Wrong, unavailable or
unresponsive versions fail before the directory is written to `GITHUB_ENV`.
Only explicit build identity fields enter JSON receipts; inherited environment
values are not serialized.

Each invocation invalidates an earlier regular receipt at the requested
`--output` path before loading pins or inspecting an app. A rejected pin,
unavailable toolchain, mismatched product or failed CI environment write leaves
no earlier success at that path. Successful receipts are installed with an
atomic file replacement after verification and any requested environment write;
a failed publication removes its temporary file and emits no success JSON.
Output must be separate from `App/`, the selected pin files, the inspected app
bundle and `GITHUB_ENV`. Linked, shared or directory outputs are rejected without
removing their targets. Use an ordinary file beneath `.build/submission-evidence`
and a separate path for each operation, as the workflow does.

The native job then:

1. Records the actual checkout commit, tree and ordered parents, Xcode build,
   Swift compiler, macOS and runner image.
2. Requires absent explicit SwiftPM cache/scratch and Xcode derived-data/package
   paths. All five packages use local repository sources or system libraries.
3. Runs actual XCTest suites for PlannerCore, PlannerData, PlannerTransfer,
   PlannerCatalog and PlannerUI under the selected Xcode. A nonzero command or
   absent nonempty successful XCTest result fails the lane.
4. Builds the app's **Release** configuration for generic iOS Simulator and
   generic iOS device destinations, with `CODE_SIGNING_ALLOWED=NO`.
5. Checks each generated `Info.plist` for the exact Xcode build, SDK name,
   SDK/platform version, platform family and 17.0 deployment target. It retains
   the observed SDK build identifier and selected product identity fields.
6. Retains bounded-scope text and JSON evidence for 14 days, including failed
   steps. It does not retain an application bundle as a distribution artifact.

The `unsigned-submission-sdk-evidence` artifact contains `checkout.txt`, runner
and compiler identity, `sdk-selection.json`, five package test logs, separate
simulator/device build logs and successful `*-product.json` receipts. A missing
later receipt after an earlier failure is unexecuted work, not a passing check.
Inspect the actual logs and compare checkout/base/head identities before
attaching a receiving-review receipt or accepting a changed pin.

## Local reproduction and negative checks

The portable verifier tests run without Xcode:

```sh
python3 -m unittest discover -s App/scripts/tests -v
```

The added cases reject an old Xcode before execution; old, substituted, failed,
extra-output and timed-out SDK probes on both platform paths; incomplete or
weakened pins; a missing exact Xcode through the actual CLI; and built-product
SDK, platform, Xcode or deployment mismatches. They also prove a rejected second
SDK publishes neither a CI environment entry nor a receipt after the first
probes succeed. These controlled tests do not simulate a real native build.

The actual portable CLI regressions also run a successful product inspection,
replace its metadata with an invalid SDK, rerun the same command/output, and
verify the old success disappears. A subsequent valid retry must publish a
fresh complete receipt. Both device and simulator cases run; malformed pins,
failed environment writes, failed atomic publication and protected/linked output
paths have separate negative checks. The product plists in these tests are
synthetic inputs, not Xcode-built products or Apple submission evidence.

On a Mac with the selected bundle installed and its component/license setup
complete, first run:

```sh
python3 App/scripts/submission_sdk.py verify --output .build/submission-evidence/sdk-selection.json
```

The command selects no global toolchain. For an interactive terminal, run the
workflow's native commands with the explicit command environment below, after
the verifier succeeds:

```sh
DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer /usr/bin/xcrun swift test --package-path Packages/PlannerUI
```

Use the workflow's exact remaining package/build/inspection commands for the
complete lane, in a fresh checkout with the documented empty cache paths. In CI,
the verifier appends the validated directory for subsequent steps through
`--github-env "$GITHUB_ENV"`; an already set default is never accepted as proof.

## Acceptance boundary

Local portable tests establish guard behavior only. This lane's actual native
execution is **pending until its exact published revision runs successfully**;
no macOS, Swift, Xcode, physical-device or store execution is claimed by the
Linux source review that introduced it. Record a later observed run separately
with its exact test-merge identities and source-review receipt.

A passing lane supplies package compatibility and unsigned compilation evidence
for #26, #110, #113 and #114. It does not establish SwiftUI behavior on iPhone or
iPad, physical lifecycle/privacy/accessibility performance, registered app
identity, code signing, provisioning, an archive accepted by Apple, TestFlight,
App Review or an installed production version. Those named issue criteria stay
open until their actual evidence is supplied. The existing regression jobs keep
their own compiler and device/runtime responsibilities.
