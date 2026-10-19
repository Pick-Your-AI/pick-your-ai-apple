# Exact historical catalog and pricebook pairs

This is a bounded package contribution to [Apple #87](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/87),
with the existing atomic-refresh boundary from [#88](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/88).
The cache previously retained immutable version identities but only the active
pair's artifact bytes. A later activation could therefore make an older draft's
exact resource bytes unavailable after restart. The cache now retains complete
successfully validated pairs together with the active selection.

## Lookup and admission

`load(mode:)` still returns the active pair. `load(_:mode:)` looks up a complete
`CacheManifest` without writing, switching the active pair, refreshing its date,
combining separate releases, downloading data or creating a missing directory.
For example, an adapter holding the exact original two pins can call:

```swift
let historical = try await cache.load(originalManifest, mode: .syntheticPreview)
let active = try await cache.load(mode: .syntheticPreview)
```

Both full pins must match: kind, schema version, ID, revision, captured timestamp
and SHA-256. The two pins' array order is immaterial. Catalog and pricebook may
have different identities and revisions. A catalog from one retained pair and a
pricebook from another do not become a retained pair merely because both pins
are known. A duplicate exact refresh reuses the existing record and updates that
pair's cached date after successful validation, as the active-only API did.

| Observation | Result |
| --- | --- |
| Requested complete pair was retained | Its exact original bytes and last successful cached date |
| Missing cache, unseen pair, never-committed combination, or legacy identity whose bytes were not saved | `nil`, with no substitution or write |
| Same observed kind/schema/ID/revision but changed digest or captured timestamp | `immutableVersionConflict`, including historical versions |
| Invalid requested manifest | `invalidManifest` |
| Corrupt or incomplete stored record, invalid digest, identity or receiver contract | The existing specific rejection; bytes are preserved |
| Production mode | `productionReceiptUnavailable` before lookup or download |

Every read validates the whole retained envelope, including the known-pin ledger
and every historical pair. Corrupt history therefore makes the envelope
unavailable and blocks refresh, even when the requested active pair is intact.
The component does not discard a bad record and silently forget its identity.
An explicit external recovery may restore previously validated complete bytes;
there is no automatic repair, partial return or fallback to another revision.

Synthetic/public admission and the mandatory caller-supplied frozen-contract
validator remain unchanged. SHA-256 checks consistency of the exact bytes; it is
not publisher authentication or a source-use receipt. Historical content remains
synthetic and `currentChecks` remains `unknown`. These internal storage changes
do not extend frozen-v1 artifact schemas or implement rules caching.

## Bounded retention and upgrade

The single `active-preview-v1.json` path is retained so no second file or
cross-file migration commit is necessary. New successful refreshes write an
internal **storage version 2** envelope with `activeManifest`, `records` and
`knownPins`. The public `CacheManifest.formatVersion` remains 1. Each record
contains the complete manifest, unchanged artifact bytes, cached date and
synthetic marker.

Legacy format-1 envelopes remain readable without being rewritten. On the first
successful refresh, the available active pair and the new pair are committed
together with all previous known pins. Older identities whose bytes were never
saved remain explicit misses. A failed or canceled first refresh leaves the
legacy file unchanged. Unsupported storage versions are rejected and retained.

The version-2 shape deliberately omits legacy readers' required top-level
`manifest` and `artifacts` fields. Those readers fail before refreshing the
cache; they cannot silently drop its history. Version-2 envelopes with legacy
top-level fields mixed in are also rejected. Downgrade rewriting is unsupported.

| Bound | Default and supported configuration |
| --- | --- |
| Per artifact | Existing 8 MiB default; positive values up to 64 MiB |
| Complete retained pairs, including active | `maximumCachedPairs: 32`; accepted range 1–128 |
| Exact encoded envelope bytes | `maximumCacheBytes`, default `maximumArtifactBytes * 6 + 2,097,152` (50 MiB with default artifact size); positive values up to 512 MiB |
| Immutable observed version pins | Existing 2,048 maximum, including legacy identities without retained bytes |

These are engineering capacity limits, not measured device-performance budgets.
The default encoded budget admits two complete pairs at the maximum artifact
size plus metadata. Small pairs can fill more slots, subject to both bounds.
JSON encoding keeps Base64 slashes unescaped. The exact encoded byte count is
checked before directory creation and atomic replacement. The existing reader
uses the same configured cap and consumes at most that cap plus one byte from
one opened descriptor before rejecting oversize input.

Pair-count or known-pin exhaustion returns `historyLimitReached` before download.
Encoded-byte exhaustion returns `oversizedRelease` before publication. Existing
data is never evicted. An exact already-retained pair does not consume another
slot. Lowering a bound below an existing file's needs makes that file unavailable
under the lower configuration, while preserving it for a compatible configuration.
There is no authoritative draft-reference registry in this package, so automatic
garbage collection could delete bytes still needed by a draft and is not offered.

## Commit, cancellation and evidence boundaries

Refresh validates the existing envelope, checks immutable identities and slot
capacity, downloads and validates the new pair, then encodes all retained
records and the selected active manifest. One Foundation atomic replacement
publishes the complete result. Failure or cancellation before that synchronous
commit leaves the previous complete file unchanged. Cancellation after commit
does not undo the completed publication. One actor per app-controlled directory
and the existing overlap guard remain required; no cross-process coordination
or app-extension cache is added.

`CatalogCacheHistoryTests` covers exact A→B→restart→A lookup with B still active;
reordered pins and repeated reactivation at capacity; unknown combinations and
conflicting historical identities; legacy read-only behavior, successful and
failed promotion, and old-reader rejection; malformed/corrupt/missing records
and explicit recovery; mandatory validation of historical records; rejected
oversize or mismatched new artifacts; actual task cancellation during a suspended
download and overlapping refresh; controlled filesystem publication failure;
encoded capacity at exactly the limit and one byte below; and preservation of
the full legacy known-pin ledger. Existing bounded-reader tests keep their
original explicitly configured byte cap and assertions.

The retained baseline regression
`testRefreshRetainsOriginalPairBytesAfterLaterActivation` uses only the prior
public API and checks for the original artifact bytes after a later activation.
Its source can be copied unchanged onto main `71db949333d94958d7d7909a1dd16c51c2421e2e`
for a causal native comparison. Linux deliberately skips this and the other
hash-dependent behavior because the package requires actual Apple CryptoKit;
neither a skip nor a successful compile is a byte-retention pass.

Run `swift test --package-path Packages/PlannerCatalog` on the existing selected
macOS toolchain. Exact hosted macOS results, unsigned iOS Simulator compilation
and independent receiving review are required before delivery. Local compile
and non-hashing checks are reported separately. No new package dependency,
hashing fallback, workflow exception or secret is introduced.

This contribution does not complete #87. Draft editing and history integration,
rules resources, actual airplane-mode/locked-device journeys and receiving
acceptance remain open. Tests use synthetic header-only artifacts for cache
mechanics and controlled filesystem/download faults; they do not establish
canonical full-shape fixture conformance, physical power-loss durability,
full-disk behavior, background OS scheduling, production rights or release readiness.
