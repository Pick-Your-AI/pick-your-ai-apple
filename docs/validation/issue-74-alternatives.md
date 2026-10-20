# #74: Alternative comparison and explicit replacement preparation

Status, 2026-10-19: **portable consumer preparation implemented and exercised;
native integration and issue acceptance remain open**. This record belongs to
[Apple #74](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/74). The
[bounded ownership claim](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/74#issuecomment-6278491704)
preserves the existing selected-editor, catalog and analysis receiving lanes.

## Problem and selected boundary

The accepted Transfer package can read immutable Builds, catalog items, evaluation
reports, evidence presentations and cost records. It did not provide a same-slot
alternative comparison or a confirmation lifecycle joining those inputs. A raw
catalog selection must not acquire an unsupported quality label, inherit the old
Build's ready/deployed state, or replace an acknowledged draft during inspection.

The new [proposal and comparison](../../Packages/PlannerTransfer/Sources/PlannerTransfer/SelectionAlternative.swift)
and [confirmation session](../../Packages/PlannerTransfer/Sources/PlannerTransfer/AlternativeReplacementSession.swift)
are portable consumers in the existing Transfer package. They introduce no new
wire schema, evaluator, pricing engine, source-use approval, persistence format,
remote service or App route. No production dependency changes. PlannerData is used
only by the existing Transfer test target for real SQLite caller tests.

The source starts at accepted main
`7431b7d666d46d37d0218b63e49b0f93ff04485d`, tree
`b891bf9fd1473523fdbaa503f026ba1a200490a1`. All 310 existing tracked files,
including every frozen schema/fixture, existing test, workflow and acceptance
ledger, were byte-identical before and after the portable execution. The three
new Swift files make its exact tested source map 313 leaves. This guide is a
later documentation addition, not another product execution.

The finite receiving base is signed main
`92dfbdb86b33e381d3c0c5866fcb15beacd2e16f`, tree
`cebea4ac67ec9d43ba68b00596d3e7c4cdd0a208`. It carries the accepted native-scope
guide correction in #414, the documentary #107 correction in #411 and the three
HistoricalResourceComparison additions in #371. Their complete source changes
were read and all 313 accepted entries are preserved. The four additions here
make the receiving candidate 317 leaves. Its later portable execution covers the
316-leaf map with the three new Swift files; this guide remains documentation.
The original source and execution identities below are not relabeled as that carry.

Placement follows the accepted [#22 platform/module decision](../decisions/issue-22-platform.md)
and [#23 service boundary](../decisions/issue-23-services.md). This validation record
does not replace a shared research record, move another client's acceptance path,
reserve a ledger version, or accept the full #74 outcome.

## Behavior and caller contract

`SelectionAlternative.prepare` admits one existing enabled selection and an exact
different catalog item/version of the same canonical kind. The Build's catalog
lock must match the supplied decoded catalog, and duplicate selection or catalog
identities fail rather than select an arbitrary record. Versions compare their
original UTF-8 bytes. Workload and deployment-mode replacements are outside this
same-workload comparison; they need their own changed-basis review.

The proposed Build changes only that selection's catalog identity/version, the
next revision, the caller's validated update timestamp, and lifecycle to `draft`.
It retains all roles, settings, other selections, links, objectives, locks and
private annotations. It passes the unchanged Build decoder again. No old
validation, readiness or deployment label qualifies the changed selection.
The proposal is available for hypothetical evaluation; it is not a saved head.

`AlternativeComparison` retains the original and hypothetical reports separately.
Each must independently name its own Build/revision and all five existing
catalog/rules/graph pins. Findings may name only existing selections. An ambiguous
rule/code/participant join and reuse of one report identity across the two Build
revisions fail admission. Outcome, severity, participants, original message,
remediation and evidence/source version remain inspectable on each side.
The local changed/unchanged comparison preserves exact UTF-8 for free-form finding
message, remediation, evidence path and source version, alongside the existing
exact nested JSON values. No frozen DTO equality or interface changes.

Finding transitions are presentation facts, not causal attribution. A failure on
both sides remains a persisting failure. Only an explicit pass for the same
rule/code/participants can be shown as reported resolved. A missing, unknown or
skipped result never becomes a resolution. A finding newly present in the report
is not automatically blamed on the candidate. A missing remediation is a visible
gap; this library does not invent a safe corrective action.

Evidence must name the actual component ID/version and retained catalog on its
side. The existing `EvidencePresentation` mapper supplies the displayed grade;
unavailable evidence and a recheck requirement remain explicit. These supplied
component records are not a complete claim-coverage inventory or a quality score.
No ranking, stronger-quality assertion, real source receipt or approval is created.

Costs use the existing `HistoricalCostScenario` and `HistoricalCostComparison`
admission. Both complete records retain exact decimal spelling, pricebook, period,
currency, rate IDs, methods, confidence, assumptions, warnings and unpriced
selections. A lower/equal/higher **reported-total** relation requires matching
period/currency/pricebook, complete declared coverage, no unpriced selection,
consistent nested currencies, and agreement between reported line amounts,
subtotal, tax and total. Otherwise it is not comparable. Arithmetic mismatches
are named separately. `ContractDecimal` compares the existing unbounded integer
and twelve-fractional-digit representation without binary floating point.
These checks do not authenticate rate applicability, quantity multiplication,
coverage completeness or an actual quote; the API's cost notice retains that limit.

The native receiving owner must follow this sequence:

1. Capture the actual local store identity, draft ID/revision and a fresh selection
   session ID. These are local controller values, never imported Build fields.
   Load the current acknowledged Build and exact catalog bytes.
2. Prepare an alternative and obtain any applicable governed report/evidence/cost
   inputs for its exact hypothetical revision. Missing inputs stay explicit.
   Creating, ordering or inspecting these immutable values has no storage writer.
3. Present the exact comparison through `AlternativeReplacementSession`. Every
   presentation and every newly constructed assessment gets a fresh generation.
   Retire it on dismissal, editing, navigation, lifecycle/authority loss or changed
   inputs; the owner's visible state must be retired before it awaits other work.
4. Only an explicit replacement action calls `confirm`. Supply the actual current
   local owner, Build, catalog and assessment. Cross-store/draft ownership,
   changed local revision/session, changed bytes, a new assessment, old callbacks,
   foreign sessions and duplicate confirmation reject. A stale token cannot
   retire a newer review. A current token is consumed even if fresh input checks fail.
5. The returned value is still uncommitted. After awaiting the session, the native
   owner must recheck its own selection/session and use the existing captured-ID,
   expected-revision durable write. A conflict requires explicit reconciliation;
   this component never retries. Display saved/current state only after the actual
   acknowledgment and the owner's normal post-await callback checks.

The actor serializes its own short transitions and contains no suspension points
inside them. It cannot atomically observe another actor's database, a SwiftUI
selection or a service. The last step is an explicit receiving obligation, not an
integrated behavior claim. Swift's current
[concurrency documentation](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/Concurrency.md#actors)
was read on 2026-10-19 for actor isolation and suspension boundaries; its published
documentation page required JavaScript, so the official source was used.

## Executed portable regression evidence

The [17 new methods](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/SelectionAlternativeTests.swift)
exercise the existing fictional fixtures and schema decoders. They supply
fictional report outcomes and evidence receipts; they do not run a new evaluator
or measure real quality/cost. Existing fixture files remain unchanged.

| Concrete case | Observed final result |
| --- | --- |
| Single-slot replacement of a ready Build | Only the selected catalog references, next revision, update time and draft lifecycle change; all other original values survive exact comparison and ordinary decode. |
| Invalid catalog, missing/cross-kind/same candidate, duplicate identities, disabled/T0 selection | Each rejected with its expected typed, payload-free error. |
| Canonically equivalent but byte-different candidate versions | Alias rejected; exact decomposed version accepted and retained. |
| Lower reported total with weaker component evidence | Fictional `100.000` versus `60.00` remains exact; source-checked versus unverified stays visible, alongside inherited failure, resolved rule, unknown and skipped outcomes. |
| Missing reports/remediation and removed/skipped/unknown findings | Explicit gaps and transitions; no invented resolution or candidate attribution. |
| Wrong Build/revision, each of five report pins, foreign participant, duplicate finding and reused report identity | Independently rejected. |
| Canonically equivalent but byte-different finding text and evidence versions | Changes to all four free-form fields and nested observed/expected text remain changed; identical-byte controls remain unchanged and original version bytes survive. |
| Evidence bound to the wrong component and a retracted current component record | Wrong binding rejected; retraction retains unverified/recheck state. |
| Partial/unknown/unpriced/mixed/period-mismatched or arithmetically inconsistent cost | No reported-total ordering; full original records and explicit mismatch remain. |
| Decimal totals beyond floating-point precision | Last fractional digit determines the correct relation; original spelling is retained. |
| Explicit confirmation, duplicate/foreign callback, dismissal and same-content reopening | Only the actual current one-shot review returns the proposal; the new review survives an old callback. |
| Build/catalog/assessment changes and identical wire content in another local store/draft/revision/session | Old confirmation rejects; restoring old content cannot revive a consumed review. |
| Actual SQLite preview, dismissal, explicit confirmation and save | Reopened durable selection is unchanged until the separate expected-revision save; the prior history payload remains, and the new saved record's analysis is not current. |
| Actual SQLite edit after confirmation but before replacement save | Existing expected-revision write rejects with `DraftStoreError.conflict`; newer edit and exactly two history records remain; no automatic retry. |

Both complete package commands used Swift **6.2.4**, target `x86_64-unknown-linux-gnu`, Swift 6 package
mode, two compiler jobs, and separate task-owned scratch/cache/config/security
paths. The installed compiler and dependency libraries were reused read-only.
No other lane's source, cache or output was removed. The disk was full during
intake, so temporary build output used a private RAM filesystem through the normal
automatic sandbox review; originals were retained in the lane's project evidence.

```sh
swift test --package-path Packages/PlannerTransfer --jobs 2
```

The latest receiving original, including the concrete review correction below and
accepted #371 source, ran **214 distinct XCTest methods: 202 passed, 12 skipped,
zero failures**, exit 0. All **17 alternatives methods** and **19 accepted resource
comparison methods** passed without a skip. XCTest took 28.653 seconds; the full
command including compilation took 35.248 seconds. All 316 source-map entries
were unchanged before and after this execution.

The native source declares **220 methods**. Twelve existing runtime skips are
five `RulesetCacheValidatorTests` and seven `SyntheticFixtureAdmissionTests` that
require native CryptoKit. Six more existing `NetworkArtifactRecoveryTests` are
entirely excluded on Linux by their unchanged `#if canImport(Darwin)` guard;
those six did not start and are not counted as skips. Complete source attendance
matches all 214 Linux-applicable methods exactly. All eighteen unexecuted native
methods require the normal Apple lane. The separate Swift Testing runner's
zero-test message adds no executed cases.

Receiving original log: 67,014 bytes, SHA-256
`4702d5b0c190a6178f42cd21f32b62390252d705327f411a1147bd3079630946`.
Its complete qualification, including all 220 source declarations, 214 actual
case outcomes and six conditional exclusions, is 80,339 bytes, SHA-256
`1e58f6190245bed345ac4a1d3a9eb8e23c764238db498d5bcb8c18db60447a46`.
Source maps, all class/method identities, commands and complete original logs are
retained for independent receiving inspection. Three local pkg-config/SQLite
discovery warnings remain; compilation and actual SQLite cases passed with the
retained library paths. No warning-free or Apple SDK result is claimed.

The preceding complete original on the 7431 base ran **194 distinct XCTest
methods: 182 passed, 12 skipped, zero failures**, exit 0, including all 16 then-new
methods. XCTest took 27.412 seconds; the full command took 34.596 seconds. Its
60,332-byte log has SHA-256
`420b2399ba16942297f57cbd0ff2adbd42e874fde442d9c5735c8397e1ab9894`; its
31,937-byte qualification has SHA-256
`ef4dc7340a20d554e89fe64ed6aac16ae53e33abbb7a02cd01b094ef75ac1335`.
The same six Darwin-only methods were excluded from that run. This earlier result
precedes the Unicode correction, its seventeenth method and the accepted resource
carry; it remains evidence for its original source only.

| Earlier actual attempt | Result and retained original |
| --- | --- |
| First compile, 10.161 seconds | Failed on a throwing expression inside `&&`; zero tests. Parsing tax/total before the boolean expression corrected it. Log 12,026 bytes, SHA-256 `409fcb254a3b62b72cd7af0c13de7890ee7b426e000123fbd0fa8cb8207e1885`. |
| First executable fixture run, 18.190 seconds | 15 methods: 13 pass, two failures. One objective edit accidentally removed required fields; one intended inconsistent subtotal was actually consistent with zero. The fixtures were corrected without weakening their assertions or production admission. Log 9,192 bytes, SHA-256 `57a175727480cc8dd5438253d3b77194fbaadb79811e4f434d366885c7428dce`. |
| Local-owner continuation compile, 4.506 seconds | Failed before tests because the new draft-revision helper used `Int64` while the actual `DraftRecord` uses `Int`. The local consumer type now matches that existing API. Log 29,936 bytes, SHA-256 `d3e2a88191271401bc42ada7924b2010beb32f0450ebe3c2939c5da6392421f0`. |
| Independent-review Unicode reproduction, 4.874 seconds | One method failed: changing only a canonically equivalent evidence source version produced unchanged instead of changed. The original 2,549-byte log has SHA-256 `11f8325e82900f2df30546dbf2973b5ea17c0cddf2ec3f2abc2f52003fd48c33`. |
| Consumer-local Unicode correction, 7.346 seconds | All 17 alternatives methods passed, zero failures/skips, before the receiving carry. The added method covers six text variants and identical-byte controls. Log 6,783 bytes, SHA-256 `19c283bd55dfc8d73b4a6cfe11ec296a09d107db6fbdb3b9be59559fa6376934`. |

The latest full execution above is the receiving recovery evidence; earlier attempts
retain their actual outcomes and exact source snapshots.

## Criterion and receiving disposition

Fresh #60 and #72 were open with no issue comments at intake. Their named outputs
gate integration acceptance; the live issues expressly permit preparation. The
actual main inspection found no integrated governed candidate picker or accessible
actionable-finding correction journey. Existing App receiving work remains with
[#391](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391),
[#412](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/412),
[#387](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/387) and
[#401](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/401).

| Exact live #74 criterion | Concrete evidence supplied | Remaining gate |
| --- | --- | --- |
| Recommendations never silently alter a saved selection or claim unsupported quality. | Portable immutable proposal/comparison, one-shot local-owner confirmation, exact input rejection and real SQLite preservation/conflict tests above. | Governed evaluator and Apple consumer receiving review; actual native caller and UI integration with all lifecycle/await boundaries. This component alone cannot enforce every external caller. |
| Offer cheaper alternatives with weaker evidence; expose tradeoffs and preserve the existing saved selection until the user confirms replacement. | Fictional lower reported-total/weaker-evidence comparison retains rule/evidence/price scope and unknowns; durable fixture stays unchanged until explicit confirmation plus its separate CAS write. | #60 current-build candidate output and #72 explanation/safe-next-step output; native alternative presentation and explicit replacement journey; qualified actual pricing/evidence must be supplied for real-data claims. |
| The alternative comparison and explicit replacement tests is linked with criterion results, exact versions, limitations and receiving-review disposition. | This record links all source/tests, original results, failure/recovery history, immutable starting source and handoff limits. | Published source/tree and exact prepared-source CI, independent receiving dispositions and the selected native integration evidence. |

Required review roles remain **governed evaluator and Apple consumer reviewers**.
Actual independent in-session review may supply its explicitly bounded technical
disposition under the maintainer's delegation; no separate person/account or
human approval is fabricated. The publishing PR must bind that review and the
actual source/tree, then qualify the repository's natural required checks and
ordinary signed main delivery. No manual unchanged-source job is requested.

No #74 criterion is marked complete by this preparation. Native SwiftUI rendering,
iPhone/iPad journeys, VoiceOver/Dynamic Type, real service/evidence/price approval,
physical-device behavior and release remain separate, unexecuted claims. The
original issue body, checkboxes, assignees, native relationships, Project fields
and captured acceptance ledger are unchanged.
