# Evaluation JSON evidence equality

This is a focused regression and correction for [Apple #104](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/104), based on accepted Apple source `666033a9f6621e3342b190e75725310fa71f8826`. It concerns representable `EvaluationJSONValue` values in decoded report evidence. The broader contract/domain work package and its prerequisite outputs remain open.

## Represented-value contract

`EvaluationJSONValue` stores arbitrary JSON evidence. Its strings and object member names must retain the decoded character sequence. For example, `"\u00e9"` and `"e\u0301"` contain different sequences, although Swift's ordinary `String` equality considers them canonically equivalent. Synthesized equality previously made these different evidence values equal, including through nested `observed` and `expected` report evidence.

The correction compares string UTF-8 sequences and checks the actual stored object member name after dictionary lookup. Array comparison remains ordered; object comparison remains independent of member order and recursively compares values. Numbers retain the existing `Decimal` equality and range checks. Alternate JSON escape spellings of the same decoded sequence remain equal. These distinctions follow the decoded-string comparison described in [RFC 8259 section 8.3](https://www.rfc-editor.org/rfc/rfc8259#section-8.3); this is not serialized-document byte comparison.

The existing `ContractJSONPreflight` safeguard is unchanged. It rejects canonically equivalent duplicate member names within one object before Foundation can collapse them. The new equality distinguishes two separately representable objects whose member names have different UTF-8 sequences; it does not admit both names into a single Swift dictionary. Caller-side dictionary construction can already have lost a spelling before the value reaches this type.

This change does not alter report decoding, the frozen schema, source authority, rule results, pricing, or admission decisions. Other free-text report fields retain their existing equality. The reproduced defect is evidence-value equality; no UI suppression, failed persistence, response-admission bypass, or universal exact-byte report equality is claimed.

## Focused cases

The new `EvaluationJSONEqualityTests` runs through the actual `EvaluationReport.decode` boundary with the accepted full report fixture. It substitutes only the first finding's evidence and retains all remaining findings and summary fields. The seven methods are:

| Method | Behavioral check |
| --- | --- |
| `testStringEvidenceDistinguishesCanonicalUnicodeSpellings` | Composed/decomposed Latin and Hangul evidence differs in both comparison directions; ordinary Swift string equivalence is an explicit control. |
| `testObjectMemberEvidenceDistinguishesCanonicalUnicodeSpellings` | Separate representable object member names retain different UTF-8 sequences. |
| `testNestedEvidenceChangesRemainVisibleInDecodedReports` | Nested string/member differences survive observed/expected comparison and encode/decode round trips without changing verdicts or summaries. |
| `testEquivalentJSONEscapesRetainEqualDecodedValues` | Literal and escaped representations of the same string/member sequence remain equal. |
| `testObjectOrderAndEquivalentDecimalValuesRemainEqual` | Reordered members, equivalent decimal spellings and negative/positive zero preserve existing equality. |
| `testArrayOrderTypesAndAbsentNullRemainDistinct` | Array order/length, JSON types, object values and absent versus explicit null remain distinct. |
| `testEquivalentDuplicateKeysRemainRejectedBeforeDictionaryCollapse` | Canonically equivalent, escaped-identical and nested duplicate member names retain the existing preflight rejection. |

The accepted `evaluation-report.json` fixture remains byte-identical: SHA-256 `039626962ef0f2c4f706614d775ad47eda1d148c58f736c98ad169fc153221f3`, frozen contract `1.0.0`, research input `7acbefbf4e4e700231e88be272bc89e3a73dde15`. The [Core README](../../Packages/PlannerCore/README.md) retains the complete source pins and existing validation limits.

## Actual portable verification

These commands ran on 2026-10-19 with the official Swift `6.1.2-RELEASE` Ubuntu 24.04 toolchain, reporting `Swift version 6.1.2` and target `x86_64-unknown-linux-gnu`. Its Swift.org detached signature was verified against the published key fingerprint `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`. The compiler and its required Ubuntu library were installed only in an isolated task directory; no system toolchain was replaced.

All 36 accepted Core files were checked against their Git blob identities before baseline execution. Each run recorded complete before/after hashes and modes for those files plus the same new test. All 37 inputs remained unchanged within every run. The corrected source changes only `EvaluationReport.swift`; the other 35 accepted files and the new seven-method fixture are identical across baseline and corrected runs.

| Actual run | UTC interval | XCTest result | Original log SHA-256 |
| --- | --- | --- | --- |
| Accepted production plus new fixture, Debug filter | 07:08:15–07:08:31 | 7 executed: 3 failed, 4 controls passed; 22 assertion failures; 0 skips; command exit 1 | `aa009da4f172aa032222fc8d0e1d9aec83c9269abb98fc43122b70cd014d9ae9` |
| Corrected production, same Debug filter | 07:13:28–07:13:34 | Same 7 executed: 7 passed; 0 failures/skips; exit 0 | `4c69055b1884c639214358e741c990ea74b2a6c929b7229ef67b60fd4976f612` |
| Corrected complete Debug suite | 07:18:49–07:18:58 | 120 distinct methods passed; 0 failures/skips; exit 0 | `5f86ba42e585eb48dbe3d45f61f8209f6971abcd64d80b113bf7104e6184995e` |
| Corrected complete Release suite | 07:19:48–07:20:15 | Same 120 distinct methods passed; 0 failures/skips; exit 0 | `a885a57ac7129744b1c6e2d1cdf84024df02477310295500a13dcb633401db67` |

The three baseline failures are the string, object-member and nested-report methods listed above. All four semantic/preflight controls pass before and after the correction. The complete Debug and Release method inventories match exactly, including all seven new methods. The original logs, per-method outcomes, compiler verification, commands and source manifests are retained separately; this note does not replace those originals.

The source executions occurred in the isolated package before this repository commit was created. Their manifests bind the actual files: corrected `EvaluationReport.swift` Git blob `e3f958bc64b8eec89b475f5a0874b703bad7ccb4` and test blob `7f7b23ad30fb18578c7b95cc5a486df9451a1ef9`. A later Git commit or receiving composition must not be described as the executed checkout merely because these two files are unchanged.

To reproduce with the selected toolchain and isolated build/cache locations, use the normal package commands:

```sh
swift test --package-path Packages/PlannerCore --filter EvaluationJSONEqualityTests
swift test --package-path Packages/PlannerCore
swift test --package-path Packages/PlannerCore -c release
```

## Receiving and remaining acceptance

Independent quality/source review and affected-consumer review must bind the published source and current-main composition. The existing [Core macOS/iOS workflow](../../.github/workflows/swift-core.yml) remains required. Its actual macOS Debug/Release and iPhone/iPad package outputs must retain attendance for all seven new methods and the existing suite; native SDK, mutation and renderer results retain their own source/artifact identities. This change does not alter a native selector, workflow, fixture inventory, or other package to bypass a gate.

The portable executions above establish Linux Core behavior only. They do not establish a macOS/iOS build, simulator or physical-device behavior, SwiftUI integration, a shipped release, or completion of #104's rule/decimal/required-field mutation evidence. The original #104 criteria and the named outputs of [#37](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37), [#70](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/70) and [#77](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/77) retain their own receiving gates.
