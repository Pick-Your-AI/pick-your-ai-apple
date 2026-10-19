# PlannerCore

A dependency-free Swift 6 client library. The implementation selects Swift and a
portable domain boundary as engineering decisions; it does not settle the complete
app framework, backend, production data, signing or release decisions. There is no
SwiftUI application or service in this package. The package deployment floors are
iOS 17 and macOS 13 for compilation; macOS is a test host, not an added product.

## Implemented behavior

- `ContractDecimal` preserves frozen-v1 decimal strings and performs exact
  arbitrary-integer-precision comparison/addition, with at most 12 fractional
  digits. It never converts money through binary floating point.
- `ContractMoney` strictly decodes amount/currency and rejects unknown fields.
  `CostSummary` is a client projection of a separately produced estimate, not a
  pricing engine or replacement wire schema. Monthly budget assessment requires
  the matching build/revision, complete current 30-day coverage, supported meters,
  no unpriced selections and matching currency. Otherwise the result is a typed
  unknown; removing an expensive rate cannot produce a false budget pass.
- `EvaluationReport.decode` reads the frozen-v1 evaluation-report boundary with
  required/unknown-key, version, identity, enum, timestamp and evidence checks.
  Outcome, severity, compatibility result and deployment readiness stay distinct.
  It preserves the server's report and does not recompute or approve its claims.
  Numeric evidence and nesting have explicit client representation limits; rejected
  inputs are unsupported, never coerced into pass. This is not a full JSON Schema
  implementation or adoption of all 29 catalog kinds.
- `AnalysisStore` is an actor with request generations and full build/revision/lock
  identity. `receive(_:identity:for:)` requires identity derived from the validated
  response, not copied from the request. Old revisions, mismatched responses,
  earlier same-revision attempts, foreign requests, late cancellation and duplicate
  completion cannot replace or erase the latest result. Network transport remains
  outside the actor; cancellation is not relied upon for correctness.
- For frozen-v1 evaluations, `AnalysisIdentity.frozenV1Evaluation` names the
  expected build/revision, catalog snapshot, ruleset ID/version and dependency
  graph ID/revision. Supply these from the selected governed inputs. After
  `EvaluationReport.decode`, the typed `AnalysisStore<EvaluationReport>` overload
  `receive(_:for:)` derives the complete response identity from the validated
  report itself. It uses the existing generation/identity gate and preserves the
  entire returned report. Mismatched fields leave the attempt pending; the caller
  still owns timeout, failure and cancellation. Report ID, evaluation time and
  verdicts do not replace input pins or define an additional ordering policy.
  The generic store remains available for other explicitly identified payloads.
- `DependencyInvalidation` interprets eight explicit activation conditions and
  finds direct participants across immutable before/after contexts. Context-only
  activation changes include both endpoints; removed and disabled selection IDs
  remain available for retirement. The [activation and participant contract](DEPENDENCY_INVALIDATION.md)
  defines unknown handling, ordering, the validated Transfer adapter and the
  caller's remaining full-identity/evaluator responsibilities.

- `EvidencePresentation` retains original provenance and selected evidence identity,
  separates source inspection from accepted independent support, and distinguishes
  newer-snapshot notices from selected-tuple corrections requiring recheck. Capture
  dates do not create automatic expiry or source-use permissions.
  Source, inspection, independent-evidence and acceptance receipt references use
  exact UTF-8 equality, including when compared through the enclosing evidence
  presentation. Canonically equivalent text cannot substitute a different opaque
  receipt reference. Retrieval-method descriptions retain ordinary text equality;
  this identity boundary neither authenticates receipts nor changes evidence grades.
- `EvidenceValuePresence` and `EvidenceCollectionPresence` preserve absent, null,
  literal-unknown, empty and supplied states without deriving an outcome or a
  completeness claim. The [evidence mapping and decoder/UI vectors](../PlannerUI/EVIDENCE_RENDERING.md)
  connect these portable types to the separately qualified SwiftUI views.

All tests are synthetic. The evaluation fixture is copied without byte changes
from research revision `7acbefbf4e4e700231e88be272bc89e3a73dde15`, frozen contract
1.0.0, SHA-256 `039626962ef0f2c4f706614d775ad47eda1d148c58f736c98ad169fc153221f3`.
[Canonical pricing semantics](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/docs/PRICING_AND_GATES.md)
and [adoption limits](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/ADOPTION.md)
remain authoritative. No frozen schema, evaluator or real-data publication is changed.
The [refreshed research handoff](../../docs/decisions/research-inputs-20261018.md)
pins the subsequently merged #126/#127 decisions and the scoped #41 receipt; it
does not infer global acceptance or add a freshness TTL.

## Run and qualify

From this directory, run `swift test`. There are no third-party package dependencies.
Also run `swift test -c release` to exercise optimized behavior. The shared report
resource is generated and verified against the same pinned canonical schema as the
Python reference checks; see [conformance reproduction](../../tools/conformance/README.md).
CI requires both implementations to agree on 45 identical report payloads and
checks that semantic mutations trigger the existing Swift regression assertions.
Linux Swift 6.0.3 validates portable logic only. The checked-in workflow selects
Xcode 16.4 build 16F6 on `macos-15`, verifies that exact toolchain is installed,
runs the package tests on macOS, and builds the package for the iOS Simulator SDK
without signing. It also injects an intentional failing XCTest in a disposable
copy and requires the Swift test command to fail for that assertion. The job logs
record the actual hosted image version; a missing Xcode pin fails rather than
selecting a different compiler. Runner inventory checked against the
[official image manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
on 2026-10-18. The image label itself is maintained upstream, not immutable.

The workflow uses PR events, read-only contents permission, no retained checkout
credentials and no release secrets. It does not change repository protection
settings or prove that a branch check is required. An iOS SDK compile is not a
simulator execution, physical-device result, signed app, TestFlight or release.
Refer to the delivering PR and its exact Actions runs for observed results.

## Issue-level acceptance limits

| Issues | Implemented slice | Remaining criteria |
| --- | --- | --- |
| #26, #29, #30 | Standalone package boundary, checked concurrency, macOS test and iOS SDK compile workflow | Xcode application targets, app/main-actor responsiveness, lifecycle and complete native check/protection qualification |
| #32 | This package supplies the report/money subset of the [accepted all-kind strategy](../PlannerTransfer/README.md#32-receiving-conformance-record) | Preserve the accepted bounded parser/public-decoder strategy; this subset adds no new #32 closure gate |
| #36 | Presence projection, retained report outcomes and [37 shared evidence decoder/UI vectors](../PlannerUI/EVIDENCE_RENDERING.md) | Actual native rendering, final exact-source receiving review and signed-main criterion reconciliation |
| #37 | Report/money decoding and explicit unknown/outcome states; pinned fixture roundtrip | Remaining contract/service and supported migration coverage under its own literal criteria |
| #47, #75 | Request/response identity and generation gates; typed frozen-v1 report admission; deterministic races, cancellation, wrong-response and reconnect tests | Real service transport and governed input adapters, actual UI visible-revision integration and receiving acceptance |
| #71 | Explicit activation and direct affected-kind/old-and-new-selection planning, with a validated frozen-graph adapter | Caller integration, complete-identity invalidation, governed evaluation, visible dirty/recheck state and actual UI/service receiving evidence |
| #77, #78 | Exact decimal arithmetic, complete-versus-partial coverage and budget guards | Canonical service scenario parity, actual line-item rounding and UI cost/coverage presentation |
| #42 | Evidence display grades, capture dates and retained-snapshot recheck state; [claim view mapping](../PlannerUI/EVIDENCE_RENDERING.md) | Catalog/service adapters, actual source inspection and acceptance receipts, saved-build integration and source-use gates |
| #37, #104 | Shared report vectors, Debug/Release Swift regressions and semantic mutation checks alongside reference checks | All-kind/service parity, historical migration, complete app/domain coverage and receiving disposition |

Product and service receiving decisions do not block these bounded library changes.
Actual integration needs the canonical endpoints, authority and versioned service
handoffs; real-data acceptance needs approved source-use/promotion receipts. App UI,
persistence and broader adapters are further implementation work, not claimed done
or excused solely by a missing local Xcode installation. Device, signing and release
acceptance require their respective environments/access and separate receipts.
