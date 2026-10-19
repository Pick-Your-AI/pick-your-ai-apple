# T6 quality guidance for a selected build

`T6QualityGuidance` provides a read-only package projection for Apple [#95](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/95). It retains the selected build, its recorded guardrail and evaluation selections, and an optional retained quality record. It supplies typed cautions and meaningful next steps without selecting a best run, recommending a threshold, executing a control, or granting quality approval.

This three-file slice follows [the scoped implementation claim](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/95#issuecomment-6263498879). It builds on the unchanged `HistoricalQualityScenario` service from [#354](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/354), whose original reviewed preparation is `9fc6e7d77f33e0092a2d9775964cfb01a00e4520`. That dependency and a later receiving composition require their own delivery and validation. This package addition does not merge or replace that source.

## Inputs and retained facts

```swift
// Both values came through the existing bounded, frozen-contract readers.
let guidance = try T6QualityGuidance(build: snapshot, run: selectedQualityRun)
let steps = guidance.nextSteps
let failedMeasurements = guidance.reportedFailedMeasurements
```

Omit `run` when no record was supplied for the selected build. `record == .notSupplied` means exactly that; it does not say that no evaluation exists elsewhere. Every non-nil record passes through the existing throwing `HistoricalQualityScenario(build:run:)` initializer. Its exact build ID, revision, selection uniqueness, suite kind/reference, and metric identity checks remain authoritative. Rejection propagates unchanged. The projection does not silently retry with another build or record.

`selections` preserves original array order, source positions, and complete JSON values for the `guardrail` and `evaluation_suite` kinds. The convenience `guardrails` and `evaluationSuites` arrays retain that order. Source positions distinguish duplicate IDs for inspection when no record is supplied; they are not reusable identities. A supplied record still rejects an ambiguous build under the existing admission service.

The full build, selected scenario, measurement order, Decimal values, original strings, catalog pins, roles, enabled flags, and raw settings remain available. An absent `gate_required` is distinct from `false`; an absent `minimum_score` is distinct from `0`. No setting is filled from an assumed default. Omitting optional T3–T5 selections does not remove the recorded T6 choices or disable this guidance.

## Facts and next steps

| Recorded input | Caution or retained result | Next meaningful step |
| --- | --- | --- |
| No guardrail selection | No guardrail selection was recorded | Review the controls needed by this workload and their evidence; application and platform controls may exist separately. |
| No evaluation selection | No evaluation suite was recorded | Select the suite before attaching its record. |
| All evaluation selections disabled | No enabled evaluation suite | Review the disabled evaluation choices. |
| An enabled suite but no supplied record | Quality record not supplied; failed measurements is `nil` | Supply a retained record for the exact build revision and selection. |
| Supplied run bound to a disabled suite | That suite is disabled, even if another suite is enabled | Review the disabled selection without discarding its historical record. |
| Reported run status `failed` | Run failure remains visible independently of measurement flags | Review the reported failures and original measurements and thresholds. |
| Any measurement reports `passed == false` | Those complete original measurements remain in source order | Review the reported failures even when the run label says `passed` or `incomplete`. |
| Reported run status `incomplete` | Incompleteness remains visible beside any known failure | Obtain the remaining results for this build revision. |
| Supplied record has no artifact references | Artifact references were not supplied | Review the original evidence separately; the record and any failure remain present. |
| Reported pass, or no false measurement flags | Empty failed-measurement array for the supplied record | Review evidence and applicable approvals; no quality approval is established. |

`reportedValuesOnly` and `approvalNotEstablished` accompany every projection. Run status and measurement flags are independent recorded facts. The code never recomputes `passed` from `observed`, `threshold`, or `comparator`, and never resolves a contradictory record in favor of a pass. An empty failed-measurement array is different from the `nil` returned when no record was supplied.

The typed `T6QualityNextStep` values have default explanatory `message` text. A UI can localize those typed steps using its existing presentation conventions. The messages describe the next configuration or evidence step; they do not expose internal validation machinery to the user.

## Consumer and compatibility boundary

The existing imported-build path can supply its selected `ImportedBuildLibraryModel` snapshot. The mounted build/comparison work in [#240](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/240) and [#198](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198) remains with its existing owners. No view is mounted or changed by this package slice.

Compatibility continues through the existing `EvaluationReport`, `EvaluationAnalysis`, `AnalysisStore`, and `EvaluationReportView` services. A caller can display a current, admitted compatibility report alongside this projection. The guidance does not accept a Boolean compatibility shortcut and does not replace report-derived identity or store-generation admission. The tests compose both paths through an actual decoded report and the existing store. Their synthetic T1/T2 findings are test inputs, not newly executed compatibility rules.

A compatibility result of `valid`/`ready` cannot supply a missing quality record or approve a reported quality pass. An `invalid`/`blocked` compatibility report also remains intact when a quality record reports a pass. After a build revision changes, the caller requests compatibility for the new identity and constructs new guidance for the new snapshot. The existing store rejects a late old response, and the existing quality scenario rejects a record for the old revision. Retained historical values remain unchanged.

This implementation has no network, file, artifact-fetch, persistence, export, execution, or approval side effects. Private notes and artifact URI strings remain original local values in the retained DTO; no preview, navigation, or automatic disclosure is added. A later consumer must apply its established display and transfer policy.

## Research and remaining acceptance

The relevant accepted handoffs are Research [#36 to #37](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/37#issuecomment-6254282660), [the #36 receiving record](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/36#issuecomment-6254300535), and [the #41 to #36 update](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/36#issuecomment-6254392681). They retain the distinction between scoped evidence, reported results, missing inputs, and release approval. This projection uses the existing frozen record fields; it does not adopt the proposed richer guardrail-decision vocabulary as a new contract.

The frozen deployment manifest already has approval fields. This slice does not implement that manifest reader, bind actual approval records and required scopes, establish an approving authority, or authenticate quality artifacts. Those concrete inputs and the separately owned deployment review remain necessary for any approval decision. No model ranking, recommended quality threshold, risk waiver, or eligibility rule is invented here.

The implementation is [T6QualityGuidance.swift](Sources/PlannerTransfer/T6QualityGuidance.swift); the regression class is [T6QualityGuidanceTests.swift](Tests/PlannerTransferTests/T6QualityGuidanceTests.swift). The following rows retain the three literal #95 criteria. Named methods specify expected package behavior; native execution and receiving results remain pending.

| Literal Apple #95 acceptance criterion | Concrete source and test coverage | Criterion result and remaining work |
| --- | --- | --- |
| Quality readiness cannot be inferred solely from schema or compatibility success. | The projection always retains `approvalNotEstablished`. `testAdmittedCompatibilityPassDoesNotSupplyQualityOrApproval` and `testReportedContradictionsAreNotRecalculatedOrPromoted` specify missing-record and reported-pass boundaries. | Partial source contribution; native results and actual evidence/approval inputs remain pending. No approval decision is produced. |
| Show compatibility pass with absent or failing quality thresholds; keep quality readiness unapproved and link actual measured artifacts separately. | `testAdmittedCompatibilityPassDoesNotSupplyQualityOrApproval` retains missing quality; `testCompatibilityPassKeepsFailedThresholdAndMissingArtifactsVisible` retains a reported failure beside admitted compatibility. `testExactDecimalsUnicodeAndPrivateReferencesRemainOriginalLocalValues` preserves inert artifact references separately. | Partial package coverage; no actual measured artifact is authenticated or supplied by these synthetic tests. Mount through the existing UI owner and qualify its evidence links separately. |
| The core T6 guardrail/quality guidance tests is linked with criterion results, exact versions, limitations and receiving-review disposition. | The linked 13-method class and commands below provide the reproducible test entry point. The original dependency preparation is the exact `9fc6e7d77f33e0092a2d9775964cfb01a00e4520` source identified above; execution receipts must identify each actual candidate and receiving tree. | Preparation record only. New Swift execution and final receiving disposition are pending; later source, tools, results and limitations must be recorded without relabeling the original dependency's results. |

The selected and omitted optional configurations are specified by `testOptionalTiersCanBeOmittedWithoutHidingT6Guidance`; `testIncompatibleCrossTierReportAndQualityRecordKeepSeparateOutcomes` covers a synthetic T1/T2 incompatibility. `testChangedRevisionRejectsOldQualityAndLateCompatibilityThenRecovers` specifies lineage rejection and recovery using the existing store and quality admission service. These cases supply no newly executed compatibility rules, measured workload, device result, or operational acceptance.

The new test class contains 13 methods covering the input combinations above, rejection/recovery, duplicate identities, exact decimals and Unicode, private values, settings absence versus false/zero, and original ordering. The package and its configured checks must execute them on the actual reviewed source. Portable Python conformance checks validate the unchanged frozen resources and reference cases; they do not compile Swift or execute these new methods.

```sh
swift test --package-path Packages/PlannerTransfer --filter T6QualityGuidanceTests
swift test --package-path Packages/PlannerTransfer
python3 Packages/PlannerTransfer/Tools/verify_contract.py
```

Execution receipts must retain their actual commit/tree and toolchain identities. This source addition alone does not complete #95, #96, #49, or #67, supply mounted UI evidence, or establish deployment readiness.
