# Native catalog browsing — bounded synthetic slice

Tracks [Apple #59](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/59).

## User behavior

The **Demo catalog** tab browses the existing fictional frozen-v1 catalog. Search
matches name, kind and identifier; kind filters combine with the search, and the
user can choose deterministic name or kind order. Clear filters resets all three
settings. Counts describe the complete matching set, while Load more components
adds the next page in that exact order.

Each row retains both item ID and item version. Inspecting a row opens its pinned
catalog/item identities and explicitly unknown compatibility and price estimates.
The resource's `billing_class` and `status` do not become current pricing or
compatibility conclusions. Sorting applies only to display names and kinds; there
is no unqualified compatibility, price or unknown-spec ranking.

Local filter preferences survive model recreation and process relaunch. They
contain only query, kind selections and sort in a bounded versioned envelope;
opaque page tokens never persist. Invalid preferences fall back to default
filters without altering unrelated settings. The browser has no draft store,
selection writer, network origin or production-data switch. Notes remain in their
own first tab. Explicit build selection is a later integration criterion.

## State and recovery

Every search has a new request identity. A canceled source operation that still
returns cannot replace newer filters, rows, counts, notices or loading state.
Ordinary next-page failure retains the acknowledged rows, exact catalog pin,
count, active filters and cursor; Retry requests that same page. Empty results
are a successful result with an identity and zero count, distinct from an
unavailable first page.

A stale cursor or changed catalog identity clears the complete displayed page
collection and requests an explicit reload. The model preserves the selected
filters and never concatenates two releases. Successful pages must retain total
count and distinct ID/version identities. Component details capture the selected
row's catalog pin, so a subsequent refresh cannot relabel an already opened
historical detail as a newer release.

## Fixture and dependencies

The bundled `catalog-preview.json` is byte-identical to
[the canonical fixture](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/examples/catalog.json):
SHA-256 `2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8`.
It retains all 29 `FICTIONAL` names and the `2026.10-demo` versions. The source
checks the bundled bytes and full `CatalogSnapshot` boundary before projecting
search fields. The work runs on its source actor, away from the UI actor.
Concurrent initial requests use the same index and an identical idempotent
installation, preserving both issued cursors.

This slice consumes the preserved catalog-item implementation from #179, catalog
envelope from #182, and display sorting from #183. Their source and tests remain
intact. Delivery must preserve the independently accepted main receipts and the
canonical editor/Files integration. A combined candidate can exercise these
dependencies before their main deliveries; it does not independently close or
supersede those source PRs.

## Validation and remaining acceptance

Eight model/source regressions exercise the exact synthetic fixture, concurrent
initialization, filter persistence and distinct versions, failed-page retry,
cancellation-ignoring late reads, refresh between pages, invalid preferences and
queries, and empty versus unavailable results. Tests use the real search actor
and controlled continuations; they do not shorten production delays or seed app
storage. The native editor model suite and unsigned iOS app build must run on the
exact proposed tree. Existing native checks and pinned source validators remain
required; local whitespace/reference checks are not Swift execution evidence.

The following parts of #59 remain separate and must not be reported complete
from package tests: actual search/filter/sort UI interaction on the pinned iPhone
and iPad, physical VoiceOver/Dynamic Type and keyboard qualification, service
pagination failure, a qualified real-data catalog, compatibility-aware known/
unknown/incompatible result presentation, and explicit selection into a full
build while preserving its editing context. No complete #59 receiving receipt,
device, store or production outcome is claimed by this bounded implementation.

Reproduce the portable pinned contract checks with:

```sh
python Packages/PlannerTransfer/Tools/verify_contract.py
git diff --check
```

On the pinned Xcode/macOS host, run the full UI-model suite and app build using
the checked-in native workflow. Inspect the eight `CatalogBrowserModelTests`
results in its retained logs before accepting the model/source gate.
