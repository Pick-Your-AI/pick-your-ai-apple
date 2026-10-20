# Persistent summary: package projection preparation

This record supports [Apple #68](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/68) with an immutable PlannerTransfer projection for an exact visible Build, supplied evaluation findings and reported cost. It provides package source and local execution evidence. All three literal acceptance criteria remain partial: persistent native presentation, rapid editor integration and the corresponding UI receiving evidence still require their existing consumers.

The source starts from accepted `e742379f9a474e632a998f1586515f4cb1280b18` (tree `7cee8aaf7036f72b04bcc7c0d622ff5120c055c8`). The [finite source claim](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/68#issuecomment-6284998314) records the three additive paths and the 2026-10-20 07:15 UTC source checkpoint. That checkpoint is not a main delivery reservation. The implementation uses the accepted e742 inputs; the separate #66 and #67 contributions are not dependencies of this source.

## Source and consumer boundary

The complete implementation is [BuildSummaryProjection.swift](../../Packages/PlannerTransfer/Sources/PlannerTransfer/BuildSummaryProjection.swift), with [BuildSummaryProjectionTests.swift](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/BuildSummaryProjectionTests.swift). This guide is the third added path. Existing application, SwiftUI views, schemas, fixtures, dependencies, workflows, package manifests and acceptance-map rows are unchanged.

The helper accepts a [BuildSnapshot](../../Packages/PlannerTransfer/Sources/PlannerTransfer/BuildTransfer.swift) already admitted by the frozen schema. It does not construct a valid Build from an incomplete form. In particular, the frozen schema requires at least two selections; an empty selection array still produces `TransferError.schemaViolation` before a context can be made. The native editor's intermediate forms and their summary presentation remain with that consumer.

Canonical [#391](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391) retains its editor, #64 planning inputs, cost presentation, local ownership, Files and T6 routes. [#387](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/387) retains the visible-analysis observable adapter and its native receiving work. This projection does not replace either owner or adopt their pending source. Existing #69 restoration and #70 report-admission work is also separate. The #65, #72 and #78 outputs named by #68 remain the intended integration inputs; their completion is not inferred here.

This type performs no network request, actor scheduling, storage, navigation, evaluation, pricing, automatic replacement or mutation of a Build. It retains the complete original values for inspection. Test inputs are the existing committed fictional Build/cost fixtures and explicitly fictional producer findings; no real customer payload, price quote or product-support evidence is introduced.

## Exact visible context and response admission

`BuildSummaryContext` holds the complete immutable Build and creates a fresh local UUID. The caller retains this context while presenting one visible snapshot. It creates a new context whenever inputs or selected record change, and when account, route or owner authority changes, including restoration to earlier identical bytes. A fresh UUID is created by the initializer rather than accepted from a decoded document. It is a local freshness discriminator, not authentication, authorization or producer evidence.

Context equality includes the exact Build and UUID. The accepted `JSONValue` equality preserves exact string bytes, and existing `AnalysisIdentity` equality preserves exact UTF-8 identifiers and lock values. A different same-revision snapshot cannot reuse a prior captured context. The caller remains responsible for its actual ownership transitions; the package cannot observe an account or route change on its own.

Evaluation request identities contain the accepted report tuple: Build ID/revision, catalog snapshot ID, ruleset ID/version and dependency graph ID/revision. Cost request identities contain the recorded Build ID/revision and optional pricebook ID. Both include `local_summary_context` only in the existing opaque, in-memory AnalysisIdentity lock map. No frozen wire field is added. Missing optional pricebook input produces no cost request identity.

`BuildSummaryEvaluation` checks the independently supplied report tuple against its captured context, rejects finding participants absent from that Build, and retains the report unchanged. Context construction rejects duplicate selection identities because they would make participant association ambiguous. It does not evaluate a rule, change a reported counter, combine outcome with severity, infer readiness or grade evidence.

`BuildSummaryCost` reuses [HistoricalCostScenario](../../Packages/PlannerTransfer/Sources/PlannerTransfer/HistoricalCostComparison.swift) admission for the recorded Build/revision/pricebook, unique selections/line IDs and known participants. Its complete captured Build must equal the context Build. This is recorded-value admission; it does not qualify price applicability, arithmetic, coverage, freshness or a budget result.

Each response wrapper derives its analysis identity from the supplied response fields plus its captured local context. The consumer must not label arbitrary response bytes with the identity copied from an initiating request. The existing [AnalysisStore](../../Packages/PlannerCore/Sources/PlannerCore/AnalysisStore.swift) remains the request-generation and response-admission authority. A retry with unchanged inputs still receives a new store generation. This projection creates no requests and does not accept or cancel them.

The native consumer supplies its actual current store states to `BuildSummaryProjection`. For current data, the projection requires the request identity to match the visible context, the full captured context to equal the visible context, and the response-derived identity to match that request. This additional check also rejects a manually assembled current enum containing a value from a different captured context. It cannot independently prove the provenance of a caller-fabricated store state; callers must use the existing store correctly.

| Supplied state | Projected state | Current findings or cost amount |
| --- | --- | --- |
| Unavailable, with no identity or the matching identity | Unavailable with the original reason | Withheld |
| Unavailable with a foreign identity | Stale | Withheld |
| Matching pending request | Pending | Withheld |
| Foreign pending request | Stale | Withheld |
| Current request, response and full context all match | Current retained value | Available within the reported-value limits below |
| Any mismatch in a current input | Stale | Withheld |

Evaluation and cost remain independently available. A pending cost does not discard a matching evaluation, and a pending evaluation does not promote or discard an independently matching cost. Cancellation and disconnection remain explicit unavailable reasons. The current-value accessor returns no prior report or estimate for a pending, unavailable or stale state.

## Choices, reported cost and inspections

Choices preserve the complete original selection JSON in order, together with ID, kind, role, enablement and exact catalog references. Disabled entries remain visible as disabled. Settings, links and the full Build remain unchanged. No required participant, deployment mode, catalog fact, component name or starter recommendation is manufactured.

The cost projection always carries `reportedValuesOnly` and retains the original scenario, warnings and unpriced selections. Exact decimal strings and currency values remain in their existing types; no conversion through binary floating point or amount arithmetic is introduced.

| Supplied recorded cost | Headline descriptor | Additional retained caution |
| --- | --- | --- |
| Complete coverage with internally matching currencies and no unpriced selections | Reported complete amount | It is still a reported value, not a qualified total or quote |
| Partial coverage with matching currencies | Reported partial amount, including an explicit recorded zero | Partial coverage and any unpriced selections |
| Unknown coverage, including a recorded zero | Withheld | Unknown coverage |
| Complete coverage while unpriced selections remain | Withheld | Unpriced selections and inconsistent complete coverage |
| Any subtotal, tax, total or line-item currency differs from the record currency | Withheld | Mixed currencies |
| Missing, pending, disconnected or stale cost | No current amount | Existing availability state |

These checks do not establish that otherwise matching recorded arithmetic is correct. In particular, a reported complete amount is not a budget-satisfied or pricing-authority result. Canonical #391 cost presentation is unchanged and remains a separate integrated consumer.

Inspection descriptors preserve fail/unknown findings in producer order. Each carries the exact finding and zero-based display ordinal, not a newly stable rule or selection identity. Repeated rule findings remain separate rows. The original report retains all pass/skipped findings, counters, outcomes, severities, evidence and the distinction between absent, empty and whitespace-only remediation.

A nonblank remediation is passed through verbatim for inspection. Blank remediation supplies no invented fix. The text is data: it does not authorize Markdown execution, a deep link, navigation, a credential request or a replacement. A non-ready report with no fail/unknown findings requests inspection of the supplied report. Missing evaluation or cost produces a corresponding inspection target; partial, unknown, inconsistent or warned cost remains inspectable. These are consumer targets, not executable corrective actions or a ranking of policy severity.

A reported pass, a ready label or an empty findings list does not become an overall product-success declaration. This package supplies no evidence-backed starter rationale without governed input. Native navigation, prioritization, visible reachability and accessible announcements remain consumer work.

## Tests and actual local originals

The new suite contains 24 source-declared methods. It covers ordered choices, frozen empty-Build rejection, ambiguous/unknown participants, all seven evaluation identity fields, complete report retention, repeated findings, absent/blank/verbatim remediation, non-ready and empty-reported-pass behavior, long exact amounts, partial/unknown zero, contradictory complete coverage, nested mixed currencies, full-snapshot cost binding, absent pricebook, pending/unavailable states, same-revision context retirement, actual store generations and late responses, cancellation and disconnection. The tests exercise the actual accepted public types and `AnalysisStore`, including a response from another context that cannot replace the current one.

Actual execution used Swift 6.1.2 on x86_64 Linux, one compilation job and task-owned build/cache/output directories. Existing read-only Swift and system-library inputs were reused. No Apple SDK or native test was run by these local commands. The complete source map before and after each execution was checked.

| Exact source tree and execution | Actual result | Original log |
| --- | --- | --- |
| Initial `580ce0fe8f97f6c3f1588d931a17c94e6b0a53be`; focused SwiftPM command | Compilation failed after 21.751 seconds; zero test methods executed. One XCTest autoclosure contained `await store.state`. | 6,617 bytes; SHA-256 `32f84844fc27b9287aea6939e1df12c3d8c7917e0bcf2c9645d9e860d58cc710` |
| Corrected `265e938681e62e7ea4d3f92ac1810d6f79363b09`; focused SwiftPM command | All 24 methods passed, zero failures/skips, 1.145 seconds test time; 19.559535 seconds including build | 9,713 bytes; SHA-256 `40ae6e600247c0f1d74117ec7a8f37e368b0697a76bd71ea092ddc5b7352913b` |
| Same corrected tree; direct execution of the binary built by that focused command | All 238 compiled methods completed: 226 passed and 12 explicitly skipped, zero failures; 28.002 seconds test time, 28.032375 seconds process time | 70,259 bytes; SHA-256 `d3d129427dc2677a16b589c60715c0171c9fa911e36f1b278ff8e7d631c3f56f` |

The two-region correction changes only the new test file. It awaits actor state before the XCTest autoclosure and replaces an invalid empty-selection fixture with exact frozen-schema rejection. Independent source review identified the latter before any test execution; it is not recorded as an observed runtime failure. Production source, frozen admission and all 334 accepted base leaves remained unchanged. The initial compiler original and its complete 336-input map are retained separately.

The corrected focused command ran from 2026-10-20 06:48:38.899088 to 06:48:58.458943 UTC. The direct full-binary command ran from 06:49:33.065430 to 06:50:01.098219 UTC. These external UTC timestamps are distinct from XCTest's local display clock. The exact full binary was 14,150,584 bytes with SHA-256 `6a9b288dcc2ee0ab0eafff32caa02ed3f4199840dcec14f674c1f8a107618903`. The complete compiled discovery list matched all 238 executed identities; all 24 added methods passed in both successful runs.

Twelve existing methods explicitly skip because CryptoKit is unavailable in this Linux environment: five RulesetCacheValidator methods and seven SyntheticFixtureAdmission methods. Six existing NetworkArtifactRecovery methods are guarded by `canImport(Darwin)` and were not compiled. These 18 methods are not claimed as passed. The exact names, original skip records, all 244 source-declared identities, command/environment records, per-file source pins and original binary identity are retained in the pure qualification proof: 97,264 bytes, SHA-256 `0e8ca2f4f37e9b8742269deaaf8d9428fb5ca14871c57d879018c42c5cc1c928`.

The complete suite was run directly through the source-bound XCTest binary already built by the successful focused SwiftPM command. There was no failed full SwiftPM run for this #68 source. This is local Linux package evidence, not a transfer of #66/#67 results or a claim that all platforms passed. Adding this guide after execution does not relabel the executed tree.

For a normal host with the required dependencies, reproduce the focused methods and complete package using `swift test --package-path Packages/PlannerTransfer --filter BuildSummaryProjectionTests` and `swift test --package-path Packages/PlannerTransfer`. The retained original commands additionally specify the exact Swift 6.1.2 binary, package/cache/security paths, SQLite library inputs and single compilation job. Normal repository native/SDK gates follow reviewed publication and remain required for their configured scope.

## Literal criterion and receiving disposition

| Literal #68 criterion | Current evidence | Remaining receiving work |
| --- | --- | --- |
| Summary remains truthful and reachable during component selection. | Validated-snapshot projection, preserved reported values and exact context/currentness source with 24 passing methods. | Native persistent visibility, reachability and accessible behavior during actual selection. Partial. |
| Keep summary visible through rapid selection changes and partial pricing; its findings, cost coverage and next action must match the visible revision. | Full captured-context binding, existing store generation tests, late-response rejection, reported partial/unknown cost and inspection-only targets. | Integration with the actual editor and named inputs, rapid native selections, restoration/ownership and partial-pricing presentation. Partial. |
| The persistent summary and stale-analysis UI tests is linked with criterion results, exact versions, limitations and receiving-review disposition. | This source/test/guide packet, exact original results and explicit historical/platform limits. | Independent final receiving review, signed delivery and integrated persistent-summary/stale-analysis UI evidence. Partial. |

Root independently reviewed the complete implementation, support contracts and corrected tests, then reproduced the entire original qualification with all 336 executed source inputs, 238 compiled outcomes and the retained initial compiler failure. Its source/original review is clear, with proof SHA-256 `3726ebeacc764e1cae086b0483a364d529c99ce4ecbb3c67de72c441cc051ded`. The second independent source review identified the invalid empty fixture, then cleared the exact two-region correction and independently qualified all 24 corrected focused outcomes; its successor proof is SHA-256 `98e51caf07bd9503d1ae10f099cafefb7c4ef1d143c11209d6e6f67b366887a5`. That peer readback did not execute the product or independently qualify the full 238-method run. Final guide/receiving review and ordinary repository delivery remain separate steps. No formal approval, named-owner acceptance, issue closure, physical-device test, store submission or release is inferred.

The next consumer handoff must preserve the actual visible Build and local context lifecycle, use the actual current AnalysisStore states, display reported cost limits, treat inspection text as data, and retain intermediate-form behavior. It must supply the real native evidence before the corresponding #68 criteria can be received. No unrelated service, hardware or whole-prerequisite closure gate is added by this package preparation.
