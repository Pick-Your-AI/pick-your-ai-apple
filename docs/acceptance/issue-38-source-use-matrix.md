# #38: Apple source-use matrix (display, offline cache, export)

Planning issue: [Apple #38](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/38).
Named output: *Apple source-use matrix linked to research
[#41](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/41)/[#60](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/60)*.
This file is the Apple application-use record for that output. The issue and the
research-repository index name no file path
(`acceptance_path` is `null` in the
[pinned coverage ledger](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/da3c6045f84260506bd326bb24ddfa8a7e6a23e8/prompts/mobile/coverage.json)),
so this path follows the existing `docs/acceptance/issue-<n>-*.md` records; the
issue's owner may relocate it.

**Evidence tier: documentation only.** This record transcribes and pins research
decisions and reconciles them with the merged Apple policy gate. It executes no
Swift, simulator, device, service, real-source or release check, contains no rights
receipt, and does not grant or infer any permission. It is not legal advice.

## Conservative default

A use is **excluded** unless an exact dated rights row for that source, claim,
version, snapshot, use and scope is permitted, its conditions are satisfied, and a
separate accepted production-promotion receipt names that row. Unknown, denied,
revoked, conflicting or absent inputs exclude the source even when its URL is
public or the research table says "Yes". This is the behavior of the merged
[`SourceUsePolicy`](../../Packages/PlannerCore/Sources/PlannerCore/SourceUsePolicy.swift)
(see [policy evidence](../validation/source-use-policy.md)) and the research rule
that a missing or unestablished grant is "no for the project's current intake"
without being a finding about legal scope.

## Pinned research inputs (all fetched with `gh api`)

Research `main` was read at `da3d320e239a6d37a933963230f2eb3643d1d5c4`. The pin
used for the links below is the repository revision
[`2510f72c9d85e8dfafa9c085b67cecce3c3c1544`](https://github.com/Pick-Your-AI/pick-your-ai-research/commit/2510f72c9d85e8dfafa9c085b67cecce3c3c1544),
not a per-file change point. All three blobs are byte-identical at both
revisions. Last commits touching each file (per `gh api .../commits?path=`):
`rights-validation.md` at `2510f72c` (2026-10-19), `integrations.json` at
`3d395801` (2026-10-18) and `catalog-data-sources.md` at `cebbf593` (2026-10-18).

`2510f72c` is newer than `0009c66a`, the revision whose `rights-validation.md`
(blob `2fb0aa8d`) the #42 to #60 receipt reviewed. The only difference between
those two blobs is one line in the decision rule that turns the text
"#41 interim conflict order" into a link to the accepted #41 conflict order; no
row, permission, condition or date differs. `integrations.json` and
`catalog-data-sources.md` have the same blobs at both.

| Input | Pin | Git blob |
| --- | --- | --- |
| [#60 rights decisions](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/2510f72c9d85e8dfafa9c085b67cecce3c3c1544/research/market/rights-validation.md) | `2510f72c` | `742862530e30e08b73c3c73a7b2303c2ccec3183` |
| [Per-source evidence, dates and conditions](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/2510f72c9d85e8dfafa9c085b67cecce3c3c1544/research/market/integrations.json) | `2510f72c` | `159766a48d7ec4460cbdc327dd5033d9f1b137a7` |
| [#41 catalog data sources and reuse policy](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/2510f72c9d85e8dfafa9c085b67cecce3c3c1544/research/T0-configuration/catalog-data-sources.md) | `2510f72c` | `c862112312d45bbe13b9e9261b8f83ee581cafa6` |
| [#41 accepted T4 interface receipt](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/41#issuecomment-6242626857) | comment | n/a |
| [#60 model-metadata receipt (to #5/#6)](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/60#issuecomment-6242698806), [MCP registry receipt (to #27)](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/60#issuecomment-6244042769) | comments | n/a |
| [#60 scoped engineering receipt (GPUs.io exclusion, ten-source boundaries)](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/60#issuecomment-6248616771), [#42 to #60 shared/exported-view receipt](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/60#issuecomment-6260217715) | comments | n/a |

To reproduce a pin:
`gh api "repos/Pick-Your-AI/pick-your-ai-research/contents/research/market/rights-validation.md?ref=2510f72c9d85e8dfafa9c085b67cecce3c3c1544" --jq .sha`
must print the blob above.

**Revision drift.** [`source-use-policy.md`](../validation/source-use-policy.md) and
[`research-inputs-20261018.md`](../decisions/research-inputs-20261018.md) pin the
earlier revision
[`92111483`](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/92111483b8d52b1b05152391b2d73e9f59ca2fba/research/market/rights-validation.md).
Between that revision and `2510f72c` the table changed for **GPUs.io** (earlier
"usable for commercial display now"; now excluded from the current product for
retrieval, display and export by an accepted #39/#41 decision) and **Harness
Bench** (earlier "Display: Yes"; now "Paper only", with the repository collection
excluded). Use the rows below, not the older pin. The Apple gate itself is
unaffected because it consumes exact rows supplied at intake, not this table.

## Use mapping

The research table defines four uses: automated retrieval, internal research,
commercial display and redistribution ("export, API, feed or dataset").

| Apple operation | Research use consulted | Basis |
| --- | --- | --- |
| Apple display | Commercial display | Same activity. Row conditions, attribution and material limits also apply. |
| Export | Redistribution | The research definition of redistribution names "export". The #42 to #60 receipt states an export does not inherit display-only permission. |
| Offline cache | **None defined** | Research defines no device offline-cache use and no table cell covers it. Treated as **unknown => excluded** until a source-rights reviewer records which research use, if any, governs a copy persisted on the user's device. The nearest research text is the MCP-registry receipt ([#60 comment 6244042769](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/60#issuecomment-6244042769)), which accepts an "intended metadata retrieval/cache/display/downstream-registry boundary" for MCP registry metadata. That is a service-side metadata boundary for one source, respecting service limits and provenance, not a grant to persist data on an end user's device, and it does not extend to other sources. |
| Automated retrieval (not an Apple user-facing use) | Automated retrieval | Listed for completeness; a retrieval permission authorizes no display, cache or export. |

## Matrix

Every cell below is an exclusion today. Legend: **X (candidate)** = excluded now;
the research row permits the use only within its stated material and conditions,
so an exact rights row could later be created and promoted, but no field-level
dated rights row, conditions receipt or production-promotion receipt exists in
this repository. **X** = excluded (research row "No", an accepted product
exclusion, or no basis). **U** = unknown => excluded. Nothing here means granted.

All ten research integration records carry status "Not approved for integration".
"Last checked" is `last_checked` in `integrations.json`; the initial terms audit was
2026-10-16 and no later date implies a fresh legal review.

| Source (`product_id`) | Research: display / redistribution | Last checked | Apple display | Apple offline cache | Apple export | Material limits (research text unless marked as the Apple author's reading) |
| --- | --- | --- | --- | --- | --- | --- |
| models.dev (`models-dev`) | Yes / Yes | 2026-10-16 | X (candidate) | U | X (candidate) | Keep the MIT notice. No grant for upstream measurements, weights or provider branding. |
| ModelFit dataset (`modelfit`) | Yes / Yes | 2026-10-18 | X (candidate) | U | X (candidate) | CC BY 4.0: credit "ModelFit (modelfit.io)", link the licence, indicate changes; figures are ModelFit estimates. |
| llmfit (`llmfit`) | Yes / Yes | 2026-10-16 | X (candidate) | U | X (candidate) | Keep the MIT notice. Repository data only, not llmfit.org content. |
| MCP registry (`mcp-registry`) | Yes / Yes | 2026-10-16 | X (candidate) | U | X (candidate) | Metadata only; listing is not a certification; keep Pick Your AI annotations separate; server code keeps its own licence. *Apple author's reading, not research text:* the row's automated-retrieval condition mentions caching ("cache (design tolerates 24h downtime)"), which is a retrieval-side condition and is read here as not a device offline-cache grant. |
| Hugging Face Hub (`hugging-face`) | Yes / No | 2026-10-16 | X (candidate: factual identifiers only, i.e. id, revision, declared licence, size, with link) | U | X | Model-card text, files and redistribution only where each repository's licence allows. |
| Harness Bench (`harness-bench`) | Paper only / paper under CC BY 4.0, repository no | 2026-10-18 | X (candidate: paper v2 material only) | U | X (candidate: paper material only); X (repository tasks, code, trajectories) | Retain authors, title/version, licence links and change indications. No endorsement implied. `integrations.json` records `display: yes` with the paper-only condition; see the divergence note below. |
| GPUs.io (`gpus-io`) | Yes (conditional) / No | 2026-10-18 | X (accepted current-product exclusion) | X | X | Research table cell is conditional, but the accepted decision excludes retrieval, display and export; a cost estimate is no exception. Reconsider only with a specific permitted-use basis, such as written permission that covers the proposed product, and a new #39/#41/#60 review (research wording). `integrations.json` still records `display: yes` for this source but also carries `project_use_decision` with `commercial_display: false`; see the divergence note below. |
| BenchLM (`benchlm`) | No / No | 2026-10-18 | X | X | X | Display and redistribution need separate agreements; none obtained. Independently licensed publisher measurements keep their own rights. |
| OpenRouter (`openrouter`) | No / No | 2026-10-16 | X | X | X | Automated collection needs written permission; none obtained. |
| Artificial Analysis (`artificial-analysis`) | No / No | 2026-10-16 | X | X | X | Data Platform Terms s2.5 bar this product category without written consent; none obtained. |
| Any source without a row | none | none | X | X | X | #41 and #60: no row means research-note paraphrase with a link only. A public URL, passed rule or independent support grants no reuse. |

**Divergence between the pinned inputs.** `integrations.json` records
`reuse_permitted.display.value` as `yes` for both `harness-bench` and `gpus-io`,
while `rights-validation.md` narrows Harness Bench to "Paper only" and its
Consequences section records the accepted GPUs.io exclusion (mirrored in
`integrations.json` as `project_use_decision`). A reader using only the boolean
field would wrongly conclude display is open. This matrix takes the conservative,
narrower value from each source and treats the conditions text as binding.

Reading the matrix: **no source is currently authorized for any Apple production
display, offline-cache or export use.** The "X (candidate)" cells identify where an exact rights
row could be created and then promoted; they are not rights rows themselves. Only
`SourceUsePolicy.assess` returning `authorized` for the exact request may enable a use.

## How a row becomes an Apple rights row

`SourceRightsRow` needs a record reference, immutable 40-character revision, row
identity, terms reference and a Gregorian checked date. A future row built from
this research would cite the record `research/market/rights-validation.md`, revision
`2510f72c9d85e8dfafa9c085b67cecce3c3c1544` (or a later accepted revision), the
source's governing terms link from the table above, and the checked date above.
The research record has no row identifiers; the `product_id` shown is the only
stable per-source identifier in the pinned files, and its use as the Apple row
identity is a proposal for source-rights reviewers, not a settled decision. The
research decision is per source and use, not per displayed field, claim, version or
snapshot, so field-level rows still have to be supplied by trusted intake.

**Caveat: a structurally valid row authorizes nothing.** Every current research
record has status "Not approved for integration". No research row may found an
Apple rights row while it carries that status and no accepted production-promotion
receipt exists. A `SourceRightsRow` that merely passes the field checks, or a
promotion receipt authored by the Apple implementer to make `assess` return
`authorized`, does **not** authorize use. Authorization needs a real,
independently issued rights decision and promotion receipt plus a research-side
approval of the source for integration. The policy gate cannot detect a
self-authored receipt (see the receipt-authenticity limit in the
[policy evidence](../validation/source-use-policy.md)).

## Criterion results

| Live criterion | Result | Evidence and limit |
| --- | --- | --- |
| Every displayed production field has an applicable source-use decision | **Remains open** | No production field inventory, real-data display path or approved real snapshot exists in this repository. A repository search finds `SourceUse*` types only in the policy source, its tests and documentation, so no display, cache or export code path calls the gate yet. Default for every uninventoried field is excluded. |
| Trace display, offline cache and export uses to exact dated rights rows; unknown or revoked permission excludes the source even when its URL is public | **Partially evidenced (documentation and previously merged synthetic tests only)** | The matrix above traces each operation to the pinned dated research row or to "unknown => excluded". Enforcement of the exclusion with synthetic receipts is merged ([PR #138](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/138), [PR #403](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/403)) and described in the [policy evidence](../validation/source-use-policy.md); this change re-ran none of it. Not shown: application to real data surfaces, durable cache and export, notice and attribution display, receipt authenticity, or revocation propagation. Offline cache has no research use mapping. Pinned #41 rule (`catalog-data-sources.md`, failed-refresh paragraph): "If rights cease to permit display, hide affected values even in historical/shared views under #60/#42." Its change-event list likewise says a #60 rights decision change hides affected values "in every view, including historical and shared ones". No Apple surface implements or evidences this. |
| The Apple source-use matrix linked to #41/#60 is linked with criterion results, exact versions, limitations and receiving-review disposition | **Matrix, links, versions and limitations supplied here; receiving-review disposition remains open** | Pins above. No source-rights, evidence or publication reviewer or Apple-consumer disposition has been recorded. Reviewers are to be resolved from live assignees and agreed intake, not from role names. |

## Validation cases not executed

The issue's required replay of an approved real snapshot, a malformed or retracted
snapshot and an unavailable historical release, including provenance, atomic
activation and last-valid-state retention, is **unverified**. No rights receipt,
real-source replay, simulator, device, service, TestFlight, App Store or production
result is claimed. Linux or CI package tests of the policy establish portable
synthetic domain behavior only.

## Remaining acceptance

1. Source-rights decision on the offline-cache use mapping.
2. A field inventory for each Apple production surface and exact dated rights rows
   and promotion receipts for it (rights receipts are not producible by
   documentation work).
3. Wiring of display, offline-cache and export paths to the gate, with notices,
   attribution and revocation handling, and the replay cases above.
4. Receiving review by source-rights/evidence/publication reviewers and the Apple
   consumer.
5. Implementation and evidence of the pinned rule to hide values in historical and
   shared views when rights cease to permit display.
6. Refresh of this matrix when research rights revisions, source terms or Apple
   scope change. Changed material, terms or use returns to research #60/#41.
