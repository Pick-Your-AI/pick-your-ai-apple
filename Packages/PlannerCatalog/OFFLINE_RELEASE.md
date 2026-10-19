# Exact offline artifact selection

`OfflineReleaseStore` adds an explicit local selection of one already retained
catalog/pricebook pair and one already retained ruleset. It advances the domain
selection boundary in [Apple #87](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/87)
and [#88](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/88). It does not
implement a downloader, automatic retry, background scheduler, draft editor,
production promotion or installed-airplane-mode acceptance.

## Preparation and activation are separate operations

The caller prepares resources through the existing
[pair/history cache](HISTORY.md) and [rules cache](RULES_CACHE.md). Preparation can
change those caches' own state. In particular, `CatalogCache.refresh` selects
the complete catalog/pricebook pair in its existing envelope. The selector does
not call either cache's refresh or retain methods and cannot roll back an
independent preparation operation.

Once the intended resources are retained, call `activate` with an explicit
`OfflineReleaseSelection`. The selector resolves the exact committed pair and
exact rules pin through the existing read-only history APIs. Those readers
revalidate their retained bytes, hashes, mandatory contract callbacks and
immutable metadata. Individually available catalog and pricebook pins cannot
be combined into a pair that was never committed together. The selector also
compares the returned catalog metadata by original UTF-8 bytes, including the
integer revision, and uses the rules cache's exact pin comparison.

Only after both lookups succeed does the selector synchronously replace its
own small selection file atomically. Missing resources, malformed requests,
validation errors or cancellation before this commit preserve the prior
selection. Overlapping activation attempts are rejected while the first awaits
its reads. A cancellation arriving after the synchronous replacement does not
undo the commit. An exact repeat, including reordered pair pins, preserves the
original selection bytes and date; it is not a freshness update.

The operation never writes, refreshes, evicts, clears or reactivates either
underlying cache. Tests compare their complete files before and after selection
operations. There is no second payload cache, release generation directory or
garbage collector.

## Reads, restart and unavailable resources

`load` returns `nil` only when no selection file exists. It reads one complete
selection record and returns only that tuple after revalidation. It never uses
the pair cache's active/latest value, chooses a rules version, or falls back to
another selection. An absent selected pair or ruleset has a distinct typed
unavailable error. Corrupt cache data and conflicting known pins remain errors.
The selection file is left intact so an explicit restoration can recover it.

A read may await the cache actors while another activation commits. Its result
still belongs wholly to the selection captured at the start of that read; this
is a consistent snapshot, not a claim that it is the latest selection at return
time. Keep one selector actor per app-controlled selection directory and one
actor per underlying cache directory. Cross-process or competing filesystem
writers are not coordinated by this component.

The current underlying caches retain immutable history without automatic
eviction and fail explicitly at their capacity limits. The selector does not
own that lifetime or pin a separate copy. If another component deletes or
replaces selected cache files, or a future accepted eviction policy removes
them, a subsequent read becomes unavailable. The selection record alone cannot
guarantee payload availability. Future eviction or account-isolation work must
coordinate its authoritative references before claiming that guarantee.

## Storage, dates and authority

The sole new file is `offline-selection-preview-v1.json`. Its bounded private
record stores the exact two artifact pins, rules pin and selection date. String
discriminators and string-encoded catalog revisions keep a future fractional
number from rounding into a recognized private format or integer revision.
Unknown formats, malformed records, nonregular files and over-limit input are
rejected without overwriting or deleting them. Reads use one open descriptor,
require a regular file and consume at most the configured limit plus one byte.
The default limit is 16 KiB; the maximum configurable limit is 64 KiB. Scalar
request bounds precede encoding and cache lookups. The existing pair/rules
formats and frozen artifact bytes are unchanged.

`CachedOfflineRelease` exposes the original component cache dates and the
separate finite `selectedAt` date. The latter records the caller's selection
clock and is preserved even when that clock is later observed as skewed or in
the future. It does not refresh cache dates or prove currentness. Cached checks
remain `unknown`; selecting three exact resources proves neither their semantic
compatibility nor that prices, evidence or rules are current.

Only public synthetic preview data is supported. Production mode fails before
filesystem or cache access. A private local selection is not a canonical
publisher manifest, source-use receipt, compatibility/graph/build result or
promotion approval. The full frozen Ruleset validator adapter remains the
separate [PR #214](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/214)
contribution; test header decoders are not that adapter. Do not store drafts,
accounts, credentials or raw evidence in this directory.

## Regression and receiving scope

The dedicated `OfflineReleaseStoreTests` cover explicit initial activation,
exact A/B reads after later cache preparation and restart, preserved original
bytes/dates, idempotent reordered selection, failed rules preparation, missing
and uncommitted combinations, conflicting/exact metadata, unsupported formats,
nonregular/oversized input, quota boundaries, cancellation during each actual
cache read, overlapping activation and controlled publication obstruction with
explicit restoration/retry. The obstruction test preserves the actual old
selection bytes in a backup while the external test deliberately replaces its
parent directory; it does not claim that an externally replaced path stayed
unchanged. Neither cache file is changed by the selector in these cases.

Run the focused suite with
`swift test --package-path Packages/PlannerCatalog --filter OfflineReleaseStoreTests`.
These are controlled header fixtures and storage/selection tests. Real hash and
retained-payload cases require CryptoKit; their conditional Linux skips are not
native passes. The configured Catalog and macOS/iOS SDK checks must qualify the
actual receiving source, with the existing storage regression/process-exit
and hosted storage gates applicable to this new durable selector. No simulator,
physical-device, OS scheduling or whole-issue acceptance follows from these
package results.
