# #23: Shared-service integration requirements delta

Status, 2026-10-19: **All three #23 decision criteria and four implementation
subtasks accepted through the actual Apple product/release engineering
[receiving decision](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/23#issuecomment-6265740527).**
The implementation and activation gates below remain unchanged.

Historical preparation status, 2026-10-18: **Apple consumer delta updated against the accepted canonical
hosting decision; Apple receiving acceptance remains pending.** [Baseline](README.md),
[Apple scope](issue-21-scope.md). The original [#131 preparation](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/131)
and its [issue receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/23#issuecomment-6243744177)
remain historical evidence. They preceded the selected hosting decision below.

## Accepted canonical input

[Android #347](https://github.com/Pick-Your-AI/pick-your-ai-android/pull/347) delivered
the reviewed [service baseline](https://github.com/Pick-Your-AI/pick-your-ai-android/blob/4c753bd69f3857d9b15051be86078948e61074ac/docs/SERVICE_BASELINE.md)
at valid signed commit `4c753bd69f3857d9b15051be86078948e61074ac`, tree
`617417c922bde926d052d9c2b4ba3920d0377751`, sole parent
`ceb15c5f505eb791a9427c12e152678da1bad2f0`. Its five decision-document blobs are
byte/mode-identical to reviewed source `0a04903a89203ac199617fe3051453e0c5a997a6`,
tree `7c7ac5f07147a6eda6476d193c18c77fc9cad21f`. The service baseline blob is
`ee4327017de31a129bd5fe1f5b59233769599e4c`.

[Product/Android decision review 5563320716](https://github.com/Pick-Your-AI/pick-your-ai-android/pull/344#pullrequestreview-5563320716)
accepts the bounded hosting decision and its explicit operating gate.
[Apple affected-client review 5563316183](https://github.com/Pick-Your-AI/pick-your-ai-android/pull/344#pullrequestreview-5563316183)
clears that precise handoff while retaining Apple #23's separate acceptance.
Neither review supplies a deployed origin, operating person's agreement or
executed service recovery. The canonical [01.04 receiving record](https://github.com/Pick-Your-AI/pick-your-ai-android/blob/4c753bd69f3857d9b15051be86078948e61074ac/docs/delivery/android/work-packages/01.04.md)
now resides in Android under its accepted [ADR 0005](https://github.com/Pick-Your-AI/pick-your-ai-android/blob/4c753bd69f3857d9b15051be86078948e61074ac/docs/decisions/0005-android-35-acceptance-record.md).
That ADR moves only Android's record and preserves its original website history;
this Apple delta keeps its existing path and creates no replacement shared record.

Consume the selected future **single TypeScript/Node API and managed PostgreSQL
on Render in Frankfurt**, separately deployed from the static website. The
canonical baseline owns the exact initial sizing, Node/PostgreSQL families,
provider sources, cost assumptions and provisional recovery targets. These are
engineering choices and qualification targets, not measured Apple latency,
accepted spending, deployed infrastructure or a service-level commitment.

The selected future server package is
`Pick-Your-AI/pickyour.ai/services/planner-api`, subject to its existing canonical
owner/coordinator and operations review before dependent server implementation.
This location is not an existing package or an Apple implementation assignment.
The Shared-service operating owner, separate recovery custodian and receiving
reviewer have defined responsibilities; actual people, account/custody access and
ongoing response acceptance remain the baseline's explicit **O1** gate.

## Consume one service, do not infer one from a static site

Apple adapters consume the same accepted service/data releases as web and Android.
Website coordination #15 supplies reviewed catalog/pricebook publication, #16
capacity/evidence, #17 saved/shared authorization and lifecycle, and #18
labels/identifiers. Their live assignee at this handoff is `PUSHINGSQUARES`; that
implementation ownership is not acceptance of a new ongoing operating role.
No production origin, credential or actual operating agreement is supplied here.
Keep the static GoDaddy frontend and its operations-owned deployment unchanged.

Apple's selected #21 scope retains public remote sharing as an intended core
journey. Local export cannot replace it. Android's guest-local J1–J4 and
conditional J5 govern Android activation only; they do not defer canonical service
work for an accepted Apple or website consumer. Conversely, the hosting decision
does not activate an Apple feature or close either client's downstream work.

| Responsibility | Apple integration requirement | Required canonical receipt |
| --- | --- | --- |
| Catalog and pricebook | Immutable identity/hash verification, bounded download, atomic promotion, permitted offline cache and stale labels | Website #15: actual base URL/release identity, rights, freshness and eligible rollback. Original artifact bytes and their hashes remain distinct from indexed database metadata |
| Evaluation/cost/capacity | Bind request/results to build revision and catalog/graph/rule/pricebook identities; reject stale callbacks; expose unknown/partial outcomes | Website #16 and governed evaluator/pricing: adopted read interface, exact tuple, units and coverage; no unqualified fit or quality result |
| Guest build writes/history | Guest-scoped server authority, immutable history and revision checks; durable local draft stays independent | Website #17 and Research #40/#42: actual authority, retry/receipt-retention, conflict, history and deletion contracts; an uncertain acknowledgment requires durable-head reconciliation |
| Share creation/read/revocation | Explicit public payload preview; credentials/private notes excluded; retired links cannot replace the active draft | Website #17 and Research #40/#42: distinct creator/viewer authority, revocation, retention, abuse limits and safe browser fallback |
| Labels | Display canonical names while persisting stable IDs | Website #18: versioned identifiers and localization handoff; no invented display field or version alias |
| Operations | Distinct staging/production; bounded requests/cancellation and redacted errors/logs | Accepted #35 design plus actual O1–O6 operator, location/custody, isolation, restore, deployment and response evidence |

## Released interfaces and missing Apple transport inputs

The original [frozen OpenAPI 1.0.0](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/api/openapi.yaml)
is 12,079 bytes, SHA-256
`6a08d7230c23576889167da6cff48d95093da9dc04d4bfa6ece443ff35089a79`.
Its relative server is `/v1`, with 13 paths and 14 operations. The inherited
`bearerAuth` requirement applies to reads as well as writes; there is no anonymous
override in these operations. A separately approved public artifact channel may
serve permitted static bytes, but it does not remove this frozen API requirement.

| Existing frozen endpoint family | Defined operations and Apple use | Boundary still needed |
| --- | --- | --- |
| `/component-kinds`, `/catalog/snapshots/{snapshot_id}`, `/dependencies/{dependency_id}`, `/rulesets/{ruleset_id}`, `/pricebooks/{pricebook_id}` | Five `GET` operations read pinned kinds/catalog/graph/rules/rates; ruleset `version` is a required query parameter | Actual approved origin and authority, qualified artifact/reuse receipts and catalog discovery/version-selection semantics |
| `/builds`, `/builds/{build_id}` | `POST` creates, `GET` reads the current head, and `PUT` conditionally updates; writes already require `Idempotency-Key`, with `If-Match` on update and a `409` conflict response | Canonical guest issuance/object scope, durable retry reconciliation and adopted list/history/fork/delete/share extensions |
| `/builds/{build_id}/evaluate` | `POST` evaluates the selected build revision with optional estimate references | Approved evaluator/policy and exact evidence tuple; no schema-validity-to-compatibility inference |
| `/builds/{build_id}/resource-estimates`, `/builds/{build_id}/quality-runs` | Two `POST` operations retain qualified producer records | Apple resource/quality read endpoints remain a governed extension; publishing routes are not read substitutes or permission to run benchmarks |
| `/builds/{build_id}/estimate-cost` | `POST` requests a selected build revision/pricebook/period estimate | Qualified rates and explicit coverage; missing prices stay unpriced |
| `/builds/{build_id}/compatible-options` | `GET` reads kind/role-specific options without mutating the build | Approved policy, revision/tuple binding and unavailable-evidence behavior |
| `/builds/{build_id}/deployment-proposals` | `POST` creates a planning/approval artifact | No runtime execution, cloud purchase or automatic deployment authority |

These are contract paths, not live base URLs or observed HTTP behavior. Token
issuance, guest/account transfer, collection paging, list/history/delete/share,
resource/evidence reads and newer-version negotiation are not manufactured from
the relative `/v1` server. [Apple #34](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/34)
consumes the canonical Android #36 / Research #40 extension and affected-owner
review. No new endpoint, header, token epoch, lifecycle state or automatic
account/CloudKit backend is introduced by this delta.

## Alternatives and failure/recovery walkthrough

The accepted upstream comparison selects one canonical API/database over a static
site alone, a second provider/control surface for the same bounded service, a
self-managed server, or per-client backends. Apple adopts that selected topology;
it does not select another host. Static distribution remains useful for specifically
approved immutable public artifacts. A local-only preview remains useful for
independent preparation; neither supplies stateful history, revocation or Apple's
intended public sharing by itself.

The following desk walkthrough was performed on 2026-10-18 against the exact
accepted baseline, its W1–W9/O1–O6 decisions and the original frozen operations.
It checks the Apple consequences of those inputs, not a live HTTP/database path.

| Required case | Apple decision and failure/recovery result | Remaining execution or input |
| --- | --- | --- |
| Service outage or commit with lost acknowledgment | Retain the durable draft and permitted cache; disclose stale/unavailable checks. A lost response may follow a committed new head. Reconcile actual authority/head/receipt before retry, and never invent publication success or assume the old head remains current | Actual API outage/concurrency/retry tests and adopted receipt-retention contract; baseline W2/W3, O5/O6 |
| Guest or retired authority | Local draft access remains independent of an account. Frozen service reads/writes retain bearer authority; object IDs, imported owner fields or a share link do not supply creator powers. A late response cannot restore retired authority or overwrite a newer selection | Actual token issuance, cross-object denial, revocation and client cancellation tests; canonical website #17, W1/W8 and O3/O5 |
| Data residency and offline copies | Frankfurt is the selected service region, not a claim about all backup/support/control-plane locations or legal compliance. Classify draft/share/cache/diagnostic data; enable private upload only after accepted location, rights and retention inputs. Offline permission and freshness are separate from network availability | Actual O2 account/location/category assessment and approved reuse; no residency inferred from a domain |
| Old client / newer data | Retain the last compatible pinned cache and durable draft when versions/schema are unsupported. Require adopted negotiation, migration and rollback compatibility before remote activation; do not silently rewrite frozen v1 or accept an unknown successor | Actual compatibility window and #34 governed vectors, W7 and O5; no guessed negotiation header |
| Mobile latency, cancellation and offline recovery | The selected single region supplies a deployment target, not measured mobile latency. Keep network work asynchronous, bind results to environment/principal/build/revision, preserve local editing through timeouts, and discard superseded responses | Actual supported-network/lifecycle measurements, approved request/page bounds and #29/#75/#88 receiving tests; no latency or background-scheduling promise |
| Restore or publication rollback | Keep the prior validated client snapshot only while its reuse remains eligible. A restored server may contain obsolete rights, revocations, deletions or acknowledged-operation state; hold private reads/writes/sharing until current authority is reconciled. Failed restore validation leaves the candidate inactive | Actual isolated PITR and independent-export drills, measured distinct loss/time windows and O4 custody. Upstream targets remain provisional, not an Apple SLA or executed result |

## Exact handoff and criterion disposition

The deployment/datastore choice, region target, role responsibilities and recovery
design are now supplied by the accepted canonical decision. Their implementation
and operating receipts remain separate. The live canonical website #15–#18
assignees are preserved; no Apple or Android agent assumes their implementation
or human operating commitments.

| Canonical handoff | Available input | Explicit remaining gate |
| --- | --- | --- |
| Android #35 / accepted service baseline | Exact selected topology, source placement, environment/location/custody/recovery design and reviewed O1–O6 map | O1 actual operating/recovery acceptance; O2 actual account, location/retention and authorized quote; O3 exercised isolation/credential controls; O4 both restore paths; O5 adopted contracts/data; O6 qualified deployment/response |
| Website #15/#18 | Existing canonical artifact and label authority; five frozen read operations | Real approved origins/releases, source-use and freshness receipts, versioned discovery/labels and Apple promotion acceptance |
| Website #16; Research #39/#41 | Canonical capacity/quality and pricing/evidence authority; frozen write/request shapes | Qualified exact-build artifacts, units/coverage and adopted Apple resource/evidence reads |
| Website #17; Research #40/#42 | Existing frozen optimistic-write headers and current-head operation | Accepted guest and object authority, idempotency lifecycle, list/history/fork/delete/share/retention/revocation interfaces |
| Apple #21/#24/#34 and affected-client receiving | Accepted engineering scope/account choices and reviewed upstream Apple handoff | Each actual adapter, lifecycle, device and release criterion remains separate from the accepted Apple integration decision; Android product completion is not a global blocker |

Apple may continue bounded parsing, labelled fixture adapters, lifecycle and local
durability work under the accepted platform scope. Those outputs do not establish
the missing service facts or require a second backend or purchased infrastructure.

## Apple receiving decision — 2026-10-19

At **11:05:28 UTC**, the coordinating ChatGPT agent in session `4b6445` made the
actual [complete Apple product/release engineering receiving decision](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/23#issuecomment-6265740527)
under the maintainer's delegated project authority. It accepts all three literal
decision criteria and all four implementation subtasks. An independent in-session
reviewer separately assessed the design, literal criteria and source preservation.
This agrees the canonical engineering service responsibilities and cross-client
handoff; it does not supply a person's ongoing operating or custody commitment.

The decision binds the original 16,736-byte delta, Git blob
`7af84dbbbb7ea471de83f42ee3bc2c1304de8824`, SHA-256
`46323473eefabb4c4ed987ba84db149b1b75f2a98522f29e94ac56156098b02d`.
That source was delivered through [#288](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/288)
and [#289](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/289) at signed main
`17e03aa65c6f2b6e0465b4bab48787901fdf0523`, tree
`3e9e6e8206488aa3154acd7a4ad1c88915ee1823`, and remained byte-identical at the
receiving decision's inspected main `9e40c79b6eb37273a821d8eddf1c00d57ad4b33c`.
The original [source review 5563641583](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/288#pullrequestreview-5563641583),
[receiving review 5563665882](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/289#pullrequestreview-5563665882)
and [delivery receipt 6251780553](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/23#issuecomment-6251780553)
retain their preparation/delivery scope and actual execution identities. They are
not backdated as the new product/release decision or as checks of this amendment.

Both named prerequisite outputs are received. Android #35 supplies the accepted
`4c753bd69f3857d9b15051be86078948e61074ac` decision above, including its explicit
open O1 operating gate. [Apple #21's actual receiving record](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/21)
accepts the required scope-matrix output delivered at signed
`391e636e73e3a2b8879997009017b7e1a08e67f6`; its
[scope artifact](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/391e636e73e3a2b8879997009017b7e1a08e67f6/docs/decisions/issue-21-scope.md)
is blob `69280f570463d07a6e8a906b45953ab505403c9a`, unchanged at the receiving
decision's inspected main. #21's separate real-data tuple remains incomplete;
that tuple is not the named scope-matrix output required by #23's native edge.

The issue requests an architecture decision and explicitly includes unresolved
owner decisions in its validation. Actual origins, deployed versions, adopted
guest/object authority, operating/custody acceptance and O1–O6 execution remain
required for their applicable implementation or activation stages. They are not
missing inputs to this completed decision. The selected future service arrangement,
website/research ownership, core public-sharing outcome and all failure/recovery
requirements above are preserved; no endpoint, paid resource or remote feature is
created or activated by receiving the decision.

| Exact #23 implementation subtask | Receiving disposition |
| --- | --- |
| Consume the canonical backend hosting decision and document Apple API needs. | Accepted: the exact canonical #35 decision, frozen endpoint families and Apple requirements are linked above. |
| Check latency, privacy, authentication and offline constraints. | Accepted: the six desk cases and responsibility map preserve these constraints and their actual implementation limits. |
| Agree service owner and cross-client handoff without creating another backend. | Accepted: Apple adopts the canonical engineering responsibilities, operating/recovery roles and existing website service lanes; actual O1 commitments remain open. |
| Record changed interfaces, implementation evidence, reviewer disposition and unresolved limitations. | Accepted: original interface pins, source delivery, scoped reviews, the dated receiving decision and remaining activation gates are recorded without a runtime claim. |

| Exact #23 criterion | Current artifact/design result | Receiving disposition and continuing boundary |
| --- | --- | --- |
| Accepted service integration ADR identifies endpoints and operating responsibility. | The selected shared topology, all released route families, implementation ownership and O1–O6 responsibility gates are identified against signed #347 | Accepted as an architecture decision by the dated receiving receipt. Contract routes remain distinct from deployed origins; actual versions, authority and operating/custody acceptance remain activation inputs. |
| Walk through service outage, guest authority, data residency and old-client migration; reject a design that assumes the static website already operates a backend. | Six explicit Apple desk cases consume the selected canonical design and reject static write authority; uncertain commits, retired authority and incompatible/withdrawn data have safe recovery boundaries | Accepted for the six documented decision cases. Actual service/client failure tests retain their separate implementation scope; the walkthrough is not runtime evidence. |
| The shared hosting/API responsibility ADR and Apple requirements delta is linked with criterion results, exact versions, limitations and receiving-review disposition. | Exact signed canonical decision, original frozen bytes, upstream reviews, accepted record placement and this unchanged Apple artifact path are linked | Accepted decision content and handoff: the historical signed delivery and the actual 2026-10-19 Apple receiving disposition are linked above. Main delivery and final issue reconciliation of this factual amendment are separate events. |

This update changes documentation only. Original issue criteria, assignments,
native prerequisites, Project values and the captured acceptance ledger remain
unchanged. Historical source/route/hash, criterion, link and whitespace checks
retain the identities in their original receipts. No new CI result or main
delivery is asserted for this factual amendment, and no Swift, simulator, HTTP,
database, backup, device, store or production execution is claimed for the
receiving decision.
