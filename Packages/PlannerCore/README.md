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

- `EvidencePresentation` retains original provenance and selected evidence identity,
  separates source inspection from accepted independent support, and distinguishes
  newer-snapshot notices from selected-tuple corrections requiring recheck. Capture
  dates do not create automatic expiry or source-use permissions.

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
| #32, #36, #37 | Report/money decoding and explicit unknown/outcome states; pinned fixture roundtrip | All 29 kinds, generated model/validator coverage, UI semantics, other-client parity and supported migration tests |
| #47, #75 | Request/response identity and generation gates; deterministic races, cancellation, wrong-response and reconnect tests | Real service adapters, actual UI visible-revision integration and receiving acceptance |
| #77, #78 | Exact decimal arithmetic, complete-versus-partial coverage and budget guards | Canonical service scenario parity, actual line-item rounding and UI cost/coverage presentation |
| #36, #42 | Evidence display grades, capture dates and retained-snapshot recheck state | Catalog/service adapters, actual source inspection and acceptance receipts, UI integration and source-use gates |
| #104 | Swift boundary, decimal and concurrency regressions alongside existing reference mutation tests | Complete app/domain regression coverage and receiving disposition |

Product and service receiving decisions do not block these bounded library changes.
Actual integration needs the canonical endpoints, authority and versioned service
handoffs; real-data acceptance needs approved source-use/promotion receipts. App UI,
persistence and broader adapters are further implementation work, not claimed done
or excused solely by a missing local Xcode installation. Device, signing and release
acceptance require their respective environments/access and separate receipts.
