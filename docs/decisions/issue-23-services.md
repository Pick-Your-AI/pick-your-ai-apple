# #23: Shared-service integration requirements delta

Status: proposed Apple consumer requirements; shared hosting decision and receiving acceptance pending. [Baseline](README.md), [scope](issue-21-scope.md). Live [Android #35](https://github.com/Pick-Your-AI/pick-your-ai-android/issues/35) was refreshed 2026-10-18 with no comments; it still requests hosting selection and accepted operating responsibility. Its canonical receiving record remains website `docs/delivery/android/work-packages/01.04.md`, not a new Apple-owned replacement.

## Consume one service, do not infer one from a static site

Recommend Apple adapters consume the same versioned service/data releases as web and Android. Website coordination #15 supplies reviewed catalog/pricebook publication, #16 capacity/evidence, #17 saved/shared authorization and lifecycle, #18 labels/identifiers. The website baseline has frozen v1 reference API definitions; `servers: /v1` is a relative contract reference, not a production base URL or proof of deployment. No production origin, region, service owner or credentials are available here. Never call a guessed endpoint, add a second backend or treat static GoDaddy hosting as a write API.

| Responsibility | Apple integration requirement | Required canonical receipt |
| --- | --- | --- |
| Catalog and pricebook | Immutable identity/hash verification, bounded download, atomic promotion, permitted offline cache and stale labels | Website #15: base URL/release manifest, rights, freshness and rollback policy |
| Evaluation/cost/capacity | Bind request/results to build revision and catalog/rule/pricebook identities; reject stale callbacks; expose unknown/partial outcomes | Website #16 and governed evaluator/pricing: versioned interface, units and coverage |
| Guest build writes/history | Guest-scoped authority, immutable history/revision checks; durable local draft stays independent | Website #17: actual API, authorization, idempotency/conflict and deletion semantics |
| Share creation/read/revocation | Explicit public payload preview; no credentials/private notes; revoked/expired links fail without replacing active draft | Website #17: token scope, revocation, retention, abuse limits and safe browser fallback |
| Labels | Display canonical names while persisting stable IDs | Website #18: versioned identifiers and localization handoff |
| Operations | Distinct staging/production; timeout/cancellation and redacted errors/logs | Android #35: actual operator acceptance, region/data residence, backup/restore, incident and rollback ownership |

Contract version 1.0.0 is an available input, not a claim that it covers every desired operation. Add no invented endpoints, auth tokens, lifecycle states or idempotency headers. Missing transport semantics require coordinated versioned review through research #40 before integration. No automatic account/CloudKit backend.

## Alternatives and failure/recovery walkthrough

Purely static distribution can serve approved immutable read artifacts but cannot supply stateful authority/history/revocation; reject it as the whole core service. A local-only preview is useful independent preparation but cannot satisfy public sharing or production service acceptance. A second Apple backend creates divergent authority and is rejected. Hosting provider/runtime/database selection remains canonical Android #35's decision; this delta intentionally does not select or provision another topology.

| Required case | Expected behavior and recovery | Observed evidence |
| --- | --- | --- |
| Service outage or lost acknowledgment | Retain durable draft/permitted cache, disclose stale checks; retry writes only using agreed idempotency/reconciliation; never display false publication success | Desk requirements only; actual outage/retry unexecuted |
| Guest authority | Local draft works without account; remote writes require narrowly scoped server-enforced authority; reject revoked/foreign credentials | Interface requirement; no live server/token available |
| Data residency | Classify drafts, shares, telemetry and backups; keep uploads disabled until operator supplies locations, subprocessors and retention for accepted markets | Region/operator facts absent; no inferred residency from a domain |
| Old client / newer data | Explicit version negotiation/rejection, retain last compatible cache and draft; unsupported versions prompt safe update/recovery without destructive migration | Frozen schemas available; actual service compatibility window pending |
| Restore / rollback | Server restores require accepted RPO/RTO and drill evidence; client keeps prior validated snapshot on failed activation and requires explicit revalidation | No numeric promise or performed restore asserted |

## Exact handoff and criterion disposition

Request canonical #35 record specify chosen deployment and datastore; real staging/production base URLs and API versions; authentication/guest authority; region and retention; operator and custody acceptance; recovery/rollback responsibilities and receipts. Request website #15/#16/#17 attach exact versioned service/data artifacts and limitations. Apple can independently implement bounded parsing, fixture adapters, lifecycle and local durability tests once platform scope is accepted; none requires buying infrastructure.

| #23 criterion | Prepared evidence | Remaining acceptance |
| --- | --- | --- |
| Accepted integration ADR identifies endpoints and operating responsibility | Canonical authority map and explicit missing endpoint/operator fields | Actual canonical hosting/API/operator receipt and product/release receiving acceptance |
| Walk through outage, guest authority, residency and old-client migration; reject assumed static backend | Five case table and rejected topology alternatives | Service-specific failure/recovery execution after real integration inputs |
| Linked shared ADR and Apple delta with results/versions/limits/review | This delta preserves canonical website acceptance path and baseline revisions | Canonical record, exact publishing commit/PR/issue link and receiving receipt |
