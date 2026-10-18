# Apple #20: Target users and interrupted guest journeys

Status: **reviewable preparation draft, not an accepted decision or participant validation**. Prepared 2026-10-17 UTC for [Apple #20](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/20), planning coordinate IOS-01.01. No implementation, contract changes, participant recruitment/outreach, interviews, prototype sessions or accounts were performed. No completion checkboxes are claimed.

## Intake and decision boundary

Live read on 2026-10-17: #20 is open, unassigned, has no comments and was last updated `2026-10-17T03:29:30Z`; the Apple open-PR endpoint returned no PRs. This draft does not assign a reviewer or owner. Required receiving role: **product/release decision reviewer**, identity and disposition pending. #20 has no native prerequisite; independent research preparation is possible. Canonical acceptance-record placement remains gated by [#22](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/22). This draft may be published as a reversible preparatory proposal under `docs/proposals/`; neither that location nor the current working copy decides the canonical acceptance-record path. Device baseline, framework, minimum OS, durable storage, service topology and release scope remain undecided.

Read Apple AGENTS.md, CONTRIBUTING.md and docs/REPOSITORY_SCOPE.md. The pinned shared/platform prompts were read at `d0a1f8b05b90e7e7087fb2f06890265ab5d42606`; [research PR #111](https://github.com/Pick-Your-AI/pick-your-ai-research/pull/111) was still open/unmerged at intake. They are proposed guidance, not accepted delivery evidence. No overlapping Apple PR was found; this does not prove that no contributor has unpublished work.

The two paths below are candidate product experiences for review. “Expected” means a proposed observable outcome, never an observed app behavior. An iPhone or iPad is the planning client; neither journey assumes it is the machine that runs the proposed AI stack. Draft persistence, public sharing and account continuity are different capabilities. A saved indicator, if offered, must describe the durability actually achieved.

## Pinned source register

Research file links below all pin revision `7acbefbf4e4e700231e88be272bc89e3a73dde15`, fetched 2026-10-17 UTC. No separate source-hash manifest was retained with the original proposal. Source provenance here is the immutable Git revision and file links, not a claim of independently retained download hashes; mutable issue/PR metadata is a dated intake observation. Repository documents are primary evidence of what the project says, not primary customer behavior. Embedded surveys and contributor walkthroughs were not independently reproduced in this run; their numeric claims are not re-used here.

| ID | Source | What this draft can consume | Limit / acceptance boundary |
| --- | --- | --- | --- |
| S1 | [Customers and jobs](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/research/market/customers.md) | Ten hypothesized segments; explicit separation of user, buyer and approver; candidate jobs | Desk personas, no interviews. No demonstrated mobile demand, interruption frequency or willingness to pay |
| S2 | [Customer validation protocol](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/research/market/customer-validation.md) and [#63](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/63) | Neutral recent-decision reconstruction; baseline before concept; explicit outreach/consent gates | Approval package only; validation not started. Do not repurpose protocol proposals as approved recruitment or acceptance thresholds |
| S3 | [PCPartPicker transfer note](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/research/market/pcpartpicker.md) | Five explicit UX hypotheses concerning components, conflicts, missing evidence, versioned sharing and costs | Walkthrough inaccessible; no current filter/save/share behavior observed by that contributor. No new access attempt made here |
| S4 | [MVP analysis](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/research/market/mvp-analysis.md), [#58](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/58) | Conditional hybrid local-versus-API decision workflow; alternatives to narrow or stop | Recommendation for validation only. Does not approve Apple release scope or supply measured demand |
| S5 | [Substitute validation](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/research/market/substitute-validation.md), [#66](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/66) | Prior contributors reported generated advice and bounded device-first observations; Flocci contradiction/export evidence remains incomplete | No Apple validation; generated suggestions are not successful runtime execution. #66 still open |
| S6 | [Workload #2](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/2), [deployment #3](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/3) | Workload, constraints and deployment trade-offs are upstream decision domains | Both open at fetch; do not invent accepted input defaults, taxonomies or hybrid representation from planning text |
| S7 | [Build schema](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/schemas/build.schema.json), [selection schema](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/schemas/selection.schema.json), [adoption](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/ADOPTION.md) | Frozen contract 1.0.0 boundaries, versioned build and catalog selections; outcomes pass/fail/unknown/skipped | Schemas and fixtures are not deployed services or product evidence. No fields added; incomplete editor state must not be misrepresented as a valid exported build |

## Candidate users and jobs

These are **scenario roles, not validated personas or newly selected market segments**. They deliberately overlap existing S1 segments rather than inventing customer demographics.

| Role | Candidate job and trigger | Constraints to explore | What remains unknown |
| --- | --- | --- | --- |
| Compact-iPhone guest, individual developer or local-AI enthusiast | Make an initial, explainable stack shortlist for a public toy workload; return after interruption; share a reviewed decision | Small viewport, touch input, no account, incomplete knowledge, intermittent connection | Whether users choose this work on phones, tolerate structured input, or need public sharing; who pays/approves |
| iPad keyboard user, application developer or consultancy contributor | Compare local and hosted alternatives, leave an unfinished stack, resume without reconstructing selections, then share rationale | Keyboard/focus, resizing/multitasking, potentially more than one open draft, no assumption of account | Whether iPad is used for this job, how drafts are abandoned, expected keyboard shortcuts or cross-device continuity |

Desired candidate outcomes: identify selected and unresolved components, explain compatibility/evidence/cost limitations, recover the intended draft, and deliberately choose what to share. Success, effort, satisfaction, frequency and monetary value have **not** been measured. No success threshold or schedule is set here.

## Journey A: compact iPhone guest, build to interruption to share

Input scenario A: synthetic public workload “choose options for answering questions about a small public FAQ.” No real PDFs, credentials, workplace information or personal content. User does not yet know request volume, target latency or budget. Catalog labels in a later prototype must say synthetic unless a separately approved real-data tuple is supplied.

| Step | User intent / action | Expected candidate behavior for review | Failure or recovery branch | Basis |
| --- | --- | --- | --- | --- |
| A1 Enter | Open the planner without signing in | Explain planning scope; allow discovering the guest path and device-versus-deployment distinction | Unsupported OS/device is disclosed without claiming an installable app exists | S1, S4; A01 |
| A2 Frame job | Choose workload and local/API comparison, leaving unknown inputs unanswered | Show unknowns and their consequence; preserve user-entered constraints; no invented numeric defaults | Invalid values remain correctable with clear field context | S6, S7; A02 |
| A3 Assemble | Choose a candidate model and relevant components; defer optional breadth | Show selections and why a choice applies; keep core evaluation, guardrail, cost-coverage and deployment-readiness concerns visible | Missing or unavailable catalog item does not silently become another selection | S3, S7; A03 |
| A4 Inspect | Read one conflict and one unresolved evidence/cost item | Distinguish fail, unknown and skipped; show source/version context; partial subtotal is not a complete bill | Offline/stale results are labelled; not mistaken for a fresh pass | S7; A04 |
| A5 Interrupt | Leave while editing an unfinished selection, before any confirmed durable save | Communicate actual save state. Candidate restoration retains the last confirmed durable revision, without claiming unacknowledged text survived | App termination/storage failure before acknowledgment may lose an edit; disclose this boundary and preserve the last intact draft | A05; no observation |
| A6 Return | Cold-open the planner and identify the prior draft | Offer the correct unfinished draft, unresolved items and last-known save state; preserve selections on screen-size change | Missing/corrupt draft: explain recovery options, do not silently start over or claim recovery; never wipe other drafts | A05, A06 |
| A7 Review/share | Resume, review unresolved warnings, inspect share content and invoke share | Show whether output is a local export or an authorized shared snapshot; confirm public fields and exclude private/secret fields | Cancel returns to draft. Failed publication retains draft and cannot report a working link; guest remote writes require service authority | S7; A07 |
| A8 Revisit | Open the shared artifact later | Identify pinned snapshot versus editable draft and stale/missing validation | Revoked, malformed or unsupported link explains condition; no silent overwrite of active draft | A07, A08 |

## Journey B: iPad keyboard user abandons an unfinished stack

Input scenario B uses the same synthetic workload, with two candidate alternatives and an unfinished cost/constraint field. This controls workload differences while examining interaction and recovery; it is not a quantitative comparison experiment. iPad keyboard support and device/OS matrix require scope review.

| Step | User intent / action | Expected candidate behavior for review | Failure or recovery branch | Basis |
| --- | --- | --- | --- | --- |
| B1 Enter / navigate | Start as a guest; navigate and choose comparison using a hardware keyboard | Discoverable controls, meaningful focus order and visible focus; no touch-only essential step | Unsupported shortcut should not trigger a destructive action; alternative navigation remains discoverable | A09 |
| B2 Compare | Move between two alternatives and inspect constraints/source details | Keep each selection attached to its own draft/revision; resizing should preserve semantic selection | Narrow window can change layout without changing data; focus should remain meaningful | S7; A03, A09 |
| B3 Edit / abandon | Change an unfinished field, then switch away before completion | Make durable versus pending state distinguishable; no claim that keyboard focus commits data | Termination during pending write, locked storage or unavailable persistence is a negative case, not assumed autosave | A05, A09 |
| B4 Return | Reopen after termination, with another draft or link potentially active | Identify which draft to resume; restore confirmed work, not a different draft or stale asynchronous result | Multiple windows/drafts remain an unresolved scope choice; test only accepted branches and clearly state unsupported branches | A06, A10 |
| B5 Resume keyboard | Continue exactly where useful, amend missing constraints, review comparison | Focus lands predictably; errors can be found and corrected without touch; unknown inputs remain unknown | Removed catalog version cannot silently replace the pinned selection; revalidation is explicit | S7; A04, A09 |
| B6 Share or leave again | Review the output and share/export, or deliberately keep it unfinished | Same content/privacy and version guarantees as A7; incomplete draft is not presented as deploy-ready | Remote failure, cancel, expired authority or unsupported export preserve local work and explain the condition | A07 |

### Comparison for receiving review

Both roles need identity of the resumed draft, honest persistence acknowledgment, preserved unknowns, source/version awareness and deliberate sharing. Compact iPhone adds visibility and touch/reading-space pressure; iPad adds keyboard focus and resize/window-state pressure. These are design hypotheses, not observed differences between user populations. Neither path requires an account in the scenario. Guest local recovery must be reviewed separately from optional account-backed cross-device continuity; one does not prove the other.

## Evidence and assumption register

Every mobile inference below is unvalidated. Confidence is stated for the source boundary, not probability of product success. Validation means a future authorized activity, not work already done.

| ID | Claim/status | Evidence and confidence boundary | Gap / falsifier | Proposed validation and responsible role needed |
| --- | --- | --- | --- | --- |
| E01 | Existing customer material is desk research/protocol, not participant findings | S1/S2 explicitly say so; high confidence in document status | No accepted mobile participant evidence found in these inputs | Product reviewer must identify any newer accepted evidence before claiming validation |
| E02 | Transfer ideas are hypotheses, not observed PCPartPicker interactions | S3 explicitly says none of five hypotheses was observed; high confidence in source statement | Access restrictions prevent that walkthrough | Review original ideas on their merit; do not bypass access or imply competitor parity |
| E03 | Current substitute evidence leaves a consequential test open | S5 reports access-gated Flocci contradiction/export test; high for recorded limitation, not current product behavior | Later accepted #66 result may narrow or stop the candidate proposition | Research consuming owner supplies accepted revision/disposition |
| A01 | Guests want to plan on compact phones | S1 developer/enthusiast jobs, S4 recommendation; mobile extrapolation only | People may use phones only to view links, or not use this tool | Later approved recent-decision interviews; product decision reviewer |
| A02 | Progressive workload questions with explicit unknowns help | S6 asks this research question; no mobile observation | Unknown handling may confuse users or insufficiently constrain choices | Desk review now; authorized prototype study later; workload owner |
| A03 | Structured component comparison is worth the interaction effort | S3/S4 hypothesis | Existing substitute or simple document may suffice | Compare against current alternative only after approved research; product reviewer |
| A04 | Users can interpret source/version, unknowns and partial costs correctly | S7 provides technical boundaries, not comprehension evidence | Users may read unknown as pass or partial subtotal as full price | Synthetic comprehension scenarios now; later consented study; evidence/pricing reviewers |
| A05 | Resuming a confirmed durable draft is the right interruption promise | Required case in #20; no implemented persistence | Storage/termination can break the promise; persistence policy undecided | State-transition review now; future fault-injection on chosen implementation; persistence reviewer |
| A06 | A resumable-draft choice prevents incorrect restoration | #20 required case; no user evidence | Too many drafts, misleading names or stale state may select wrong work | Synthetic two-draft review; future cold/warm/device tests; experience reviewer |
| A07 | Guest sharing is useful and understandable | S3 hypothesis, S7 versioned objects | Sharing may not be required; backend/rights/auth may prohibit it | Preview-only desk scenario now; approved lifecycle/share service and rights review before implementation |
| A08 | Versioned links and explicit revisit status are understandable | S3 hypothesis, S7 technical boundaries | Snapshot/current distinction may confuse users | Synthetic revisit cases; saved-build and product reviewers |
| A09 | Keyboard/focus/resize support makes the iPad path usable | Required iPad case, not participant observation | Layout may trap focus or lose edit context | Future keyboard and assistive-technology device tests on accepted matrix; accessibility reviewer |
| A10 | More than one draft/window requires explicit recovery identity | Recovery risk analysis only | Multiple scenes may be excluded from initial scope | Scope owner accepts supported/unsupported branches; no multiwindow implementation implied |

No user/buyer/approver roles, preferences, emotions, pain intensity, elapsed task times, conversion rates or willingness-to-pay conclusions have been manufactured.

## Negative, recovery and unsupported journeys

| Case | Candidate expected outcome / recovery | Current evidence state and scope condition |
| --- | --- | --- |
| N1 Offline before catalog load | Explain unavailable data; keep existing permitted draft/cache usable where supported | Unexecuted; caching rights and service/data scope pending |
| N2 Offline after draft edit | Distinguish local durable state from queued remote state; no “synced” claim without acknowledgment | Unexecuted; storage/outbox policy not chosen |
| N3 Termination before/after durable acknowledgment | Before: disclose unconfirmed-edit risk. After: recover correct committed revision or expose failure | Unexecuted; requires implementation and device evidence |
| N4 Storage full, locked or corrupt | Clear persistence failure; preserve valid data; retry or user-controlled recovery | Unexecuted; no migration/recovery mechanism selected |
| N5 Stale callback or concurrent scene | Never overwrite a newer active draft silently; surface conflict if supported | Unexecuted; concurrency policy/scope pending |
| N6 Missing catalog version, stale rule or unsupported meter | Preserve original selection/version and explain revalidation/cost-coverage gap | Unexecuted; canonical data/evidence contracts needed |
| N7 Invalid, revoked, expired or wrong-host share | Explain failure; preserve active draft; do not bypass authorization | Unexecuted; universal-link/service decisions pending |
| N8 Share cancel or lost server acknowledgment | Return without losing draft; avoid duplicate remote writes if retry is supported | Unexecuted; no service idempotency claim made |
| N9 Import newer/invalid contract or private fields | Reject unsupported content safely, preview supported changes, never replace draft silently | Unexecuted; format limits and import scope pending |
| N10 Keyboard-only, VoiceOver, large text, rotation, narrow window | Essential actions remain understandable/reachable; data and meaningful focus preserved | Unexecuted; future simulator and physical-device evidence recorded separately |
| N11 Sign-in/device transfer/account sync | No continuity promise in guest scenario; describe supported local/export path honestly | Account capability is scope-gated; not required or implemented by this draft |
| N12 Run stack, buy hardware/API credit, subscribe, publish community post | Explain that planning does not execute, purchase or publish | Out of this preparation; separate explicit scope/authority required |
| N13 Additional Apple platforms or unsupported OS | No implied Mac/watch/TV/spatial support | Matrix and expansion decisions outstanding |
| N14 Uninstalled-app universal link | Browser fallback only if approved and implemented; no implied website write API | Unexecuted; static website boundary retained |

## Authorized no-participant usability scenarios

These are desk-review scripts prepared within the present drafting mandate. They authorize no recruitment and were **not executed against an app or prototype**. Use synthetic data; no customer files, credentials or contact information. Future execution requires a reviewable prototype/artifact, supported device matrix and any applicable authority. Do not collect personal telemetry by implication.

| Scenario | Replay steps | Expected review question | Observed result / record required |
| --- | --- | --- | --- |
| U1 Compact guest interruption | Follow A1–A5; stop before acknowledgment; cold return A6; compare retained fields to last confirmed revision | Does the wording distinguish pending and saved work without promising impossible recovery? | Unexecuted. Record artifact hash, device/OS or paper prototype, state before/after and lost edits |
| U2 iPad abandonment | Follow B1–B3 with keyboard; terminate; resume B4–B6; repeat with resize | Can the intended draft and unresolved field be identified and reached using keyboard alone? | Unexecuted. Record keyboard/focus trace, widths, scene state and restoration evidence |
| U3 Evidence ambiguity | Present one fail, one unknown and one skipped check with a partial subtotal | Could a reviewer mistake uncertainty or missing cost for a successful full result? | Unexecuted. Record exact labels/source tuple and identified ambiguity, not a fabricated comprehension score |
| U4 Contradictory constraints | Synthetic “fully offline” plus “requires hosted API”; inspect explanation | Does conflict remain visible rather than silently relaxing a constraint? | Unexecuted. Requires canonical rule fixture; expected conflict is a scenario, not new policy |
| U5 Share boundary | Preview draft with synthetic private note and credential-reference placeholder; cancel; simulate remote failure; revisit revoked link | Are excluded fields, version identity and failure states clear without losing local work? | Unexecuted. Record sanitized payload difference and failure/recovery result |
| U6 Two drafts / stale return | Edit draft A, open B, then simulate delayed result from A | Is the draft identity preserved, or does a stale event replace B? | Unexecuted. Only if accepted scope supports this state; otherwise record explicit unsupported branch |

Later participant testing must use the approved #63 recruitment, consent, retention and anonymized reporting decisions, a named research owner, approved task script and non-leading baseline. No permission is inferred from this draft. Qualitative observations, internal expert review, synthetic checks and participant validation must remain separate evidence classes. Product/release reviewer must set any completion thresholds; none is guessed here.

## Interfaces, artifact identity and criterion coverage

Changed interfaces: **none**. Candidate touchpoints for later receiving review: workload/deployment inputs (research Pick-Your-AI/pick-your-ai-research#2/#3); frozen build `id`, `revision`, `owner_ref`, `lifecycle`, `locks`, `selections`, `links`; selection `catalog_item_id`/`catalog_item_version`, role, enabled and settings. No field values, unknown encodings or lifecycle transitions are newly defined. Incomplete editor data may need an approved representation outside a valid exported build; do not mutate frozen v1 to make the draft convenient. Review semantics through Pick-Your-AI/pick-your-ai-research#40 and Pick-Your-AI/pick-your-ai-research#42, cost through Pick-Your-AI/pick-your-ai-research#39, evidence through Pick-Your-AI/pick-your-ai-research#41, rights through Pick-Your-AI/pick-your-ai-research#60, and shared services through Apple #23 and existing canonical coordination.

Artifact: this document reuses draft-1 dated 2026-10-17 from Apple commit `70b92e91045570b8699c4c814058778da68478cd`. The 2026-10-18 preparation revision removes unsupported claims that a source-hash manifest accompanied the original. The delivering PR and its head commit identify this revision; publication does not make this the canonical acceptance record. Independent agent technical review checked source claims at the pinned research revision and identified the missing-manifest defect; it does not supply product/release receiving acceptance. A later receiving reviewer must review the exact delivered artifact version and link their disposition after the canonical path is accepted.

| Exact #20 acceptance criterion | Artifact and check | Observed / failed / recovery result | Receiving review | Remaining gap |
| --- | --- | --- | --- | --- |
| Reviewed journey map distinguishes evidence from assumptions. | Journeys A/B, source register and E01–E03/A01–A10 | Desk preparation distinguishes source statements from mobile hypotheses; independent draft-quality review only; product/release receiving review pending | Pending; product/release reviewer unassigned | Accountable assignee, receiving reviewer and signed disposition |
| Compare a guest on a compact iPhone and an iPad keyboard user who abandons an unfinished stack; document recovery and unsupported journeys without treating desk research as participant validation. | A1–A8, B1–B6, comparison, N1–N14, U1/U2 | Required cases documented; every actual app/participant result unexecuted. Recovery expectations are proposals | Pending | Approved scope/device matrix, accepted behavior and appropriate future evidence |
| The journey map and evidence/assumption register is linked with criterion results, exact versions, limitations and receiving-review disposition. | Pinned S1–S7 Git revision and paths, this table | Local linked package prepared; no canonical issue acceptance-record link or receiving receipt claimed | Pending explicitly, no invented signoff | #22 path decision, publication through normal signed-commit/PR gates, exact-version receiving review |

Implementation subtasks: jobs/guest journeys drafted; evidence-to-assumption mapping drafted; no-participant scenarios prepared; unchanged interfaces, unexecuted implementation evidence, pending review and limitations recorded. These are preparation outcomes, not checked completion of the live issue.

## Smallest remaining owner/reviewer intake

1. Assign accountable Apple #20 owner and identify product/release receiving reviewer through live GitHub authority. Research assignees do not automatically own Apple delivery.
2. Review the candidate role selection and both interruption journeys. Record accepted, narrowed, rejected or deferred sections, with rationale; keep alternative “phone primarily views shared builds” and “existing substitute suffices” open.
3. Resolve canonical acceptance path via #22; retain guest/local versus remote/account boundaries and scope decisions in #21/#23. No blanket requirement to close all research issues is added.
4. Supply accepted inputs where required, especially draft/snapshot/revalidation semantics and real catalog/evidence tuples. Record exact producer revision, consumer and limitations; a research merge alone is insufficient.
5. Link receiving review to the exact artifact and reconcile all criteria before issue closure. No participant validation is required merely to pretend desk research is complete; if participant evidence is needed for a decision, request its separate approved study and keep that decision pending.

This draft introduces no delivery date, estimate, owner commitment, framework choice, new backend, release authority or production-readiness assertion.
