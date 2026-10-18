# Scoped research inputs consumed by the Swift core

Refreshed 2026-10-18 UTC. Merge status and explicit receiving receipts take priority
over stale draft/open prose inside a record. A merged partial record does not
close its producer issue or approve every proposed extension.

| Input | Verified identity and disposition | Apple use and limits |
| --- | --- | --- |
| Research #126 / #40 | [Merged record](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/565f4512ed6a38dfc21c83c92babe5b3bed64e24/research/T0-configuration/component-schema-compatibility.md), merge `565f4512ed6a38dfc21c83c92babe5b3bed64e24`, 2026-10-18 00:18:48 UTC | Preserve separate outcome and severity; rule success is not independent evidence verification. #40 remains open. Proposed v1.1/v2 migrations, fields and rule changes are not silently implemented in frozen v1 |
| Research #127 / #41 | [Merged record](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/92111483b8d52b1b05152391b2d73e9f59ca2fba/research/T0-configuration/catalog-data-sources.md), merge `92111483b8d52b1b05152391b2d73e9f59ca2fba`, 2026-10-18 00:19:21 UTC | Consume the scoped evidence mapping and freshness rules below. Price-specific freshness, region/currency and price conflicts remain unresolved |
| #41 T4 interface | [Explicit accepted receipt](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/41#issuecomment-6242626857) | Source-checked-only uses unverified; historical verified labels do not prove reproduction. Hosted services retain capture-date version and selected snapshot. New snapshots do not automatically expire builds; no invented TTL |
| #60 rights | [Per-source, per-use table at the same revision](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/92111483b8d52b1b05152391b2d73e9f59ca2fba/research/market/rights-validation.md) and the #41 receipt | The table, exact source scope and conditions govern each use. No source row means research-note paraphrase/link only; automated retrieval, commercial display and redistribution are not permitted by default. A public URL, passed rule or independently supported claim grants no reuse rights |
| Research #111 mobile prompts | PR remains open; mobile receiving acceptance is absent | Retain the no-merge boundary. Do not treat the proposed prompt migration as accepted implementation or release authority |

## Client behavior

The evidence presentation projection retains the original provenance status and
selected evidence identity. It may show independent verification only with an
explicit accepted independent-support receipt, never from an old `verified` value
alone. A source-check flag requires the claim text to have actually been inspected;
a page URL or unrendered table cell does not fill a missing claim. User-supplied and
estimated provenance remain distinguishable. This is display/domain state, not a
new wire schema or mass relabeling of stored history.

Version-pinned facts remain pinned. Current-state facts show their capture date.
The client does not invent an age cutoff. New-release/new-snapshot notifications
are distinct from selected-tuple corrections or retractions that require recheck;
retained historical identity is not overwritten. Price freshness remains an input
from the canonical service/producer, so the budget API requires explicit current,
expired or unknown applicability and does not derive it from a guessed TTL.

The rights table is a separate gate before real ingestion, caching, display or
export. No source data is ingested by this change. MCP registry metadata permission
is limited to metadata and its recorded conditions; a listing is not a security
certification and does not grant rights to server code. Conditional source rows
are not blanket grants covering upstream measurements or artifacts. No paid API,
collection campaign or backend is activated here.

## Available native validation

The preceding Swift implementation, [Apple PR #133](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/133),
merged at `3f5fd13c14b4af1af08490fb3784adcb90a35955` after independent technical
review and successful [macOS CI](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39083560619).
That run records macOS 15.7.9, Xcode 16.4 build 16F6, Apple Swift 6.1.2 and runner
image `macos15 20260907.0337.1`: 32 package tests passed, the unsigned iOS Simulator
SDK build succeeded, and the intentional XCTest probe failed as expected.

This disproves a blanket local-Xcode blocker for portable code and CI compilation.
It does not establish simulator execution, UI behavior, physical-device testing,
service acceptance, signed installation or release. The follow-up PR carries the
additional evidence-projection test results at its own commit; this historical
run is not reused as proof that later changes passed.
