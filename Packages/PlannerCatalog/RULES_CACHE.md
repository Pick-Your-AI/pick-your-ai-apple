# Exact pinned rules for synthetic offline previews

This is a bounded storage contribution to [Apple #87](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/87).
It retains the original bytes of explicitly pinned rules across restart. It has
no active or latest ruleset and does not activate a combined catalog/rules/prices
release. The existing [catalog/pricebook cache](HISTORY.md), application editing,
background scheduling and the frozen #198 receiving batch retain their scope.

## Admission and identity

`RulesetIdentity` contains the frozen Ruleset fields `schema_version`, `id`,
string `version` and `published_at`. It does not convert the version to a catalog
integer revision, normalize leading zeros or apply a different SemVer grammar.
Identity and pin equality/hashing compare the exact UTF-8 sequences. The full pin
also contains the lowercase SHA-256 of the original artifact bytes.

The cache requires a `@Sendable (Data) throws -> RulesetIdentity` validator at
initialization. The validator must fully validate the **same original bytes**
against the receiver's frozen Ruleset boundary and return their decoded identity.
There is no permissive default or built-in schema substitute in PlannerCatalog.
Request-field bounds alone are not contract
validation. In particular, they do not authorize a malformed ID, version or date.

PlannerTransfer supplies the concrete
[`FrozenRulesetCacheValidator.identity(for:)` adapter](../PlannerTransfer/Sources/PlannerTransfer/RulesetCacheValidator.swift).
It calls the existing whole-artifact `Ruleset.decode(data)` boundary before
returning the decoded `id`, string `version` and `publishedAt`. Successful
decoding already requires schema version `1.0.0`. A plausible metadata header
cannot bypass validation of the rules body, duplicate keys or whole-input bounds.
Decoder errors propagate without becoming a cache identity or an unavailable
record. Configure the cache explicitly in the receiving target:

```swift
import PlannerCatalog
import PlannerTransfer

let cache = try RulesetCache(directory: directory) {
    try FrozenRulesetCacheValidator.identity(for: $0)
}
```

PlannerCatalog remains independent of PlannerTransfer. The receiving Transfer
target depends on Catalog alongside its existing Core dependency; the cache and
selector implementations are unchanged. The adapter delegates to the reader
delivered through [#359](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/359),
preserving the original [#214 handoff](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/214#issuecomment-6258099318).
The selected frozen grammar admits a literal numeric-triplet version with an
optional prerelease; it does not admit arbitrary general-SemVer build metadata.
Accepted version and timestamp spellings are returned without normalization.

Hashing uses the existing `CatalogCache.sha256` facility. Store/hash the received
`Data`, never the decoder's normalized `encoded()` output. A digest proves byte
consistency, not publisher authenticity, source rights or usable policy semantics.
Only explicit `.syntheticPreview` operations are available; `.production` fails
before lookup, download or writing. Keep drafts, tokens and private evidence out
of this public-artifact cache.

## Retention, lookup and recovery

`retain(_:mode:now:download:)` accepts a bounded download closure; it performs no
networking itself. It validates existing history, rejects conflicts and capacity
exhaustion, receives and validates the original bytes, and replaces one complete
envelope. `load(_:mode:)` requires an exact full pin and revalidates every retained
record without writing or changing any selected release.

| Observation | Result |
| --- | --- |
| Exact retained pin | Original bytes, pin and last successful cached date |
| Missing file or unseen exact version | `nil`; no latest substitution or download |
| Same schema/ID/version with different timestamp or digest | `immutableVersionConflict`, including historical versions |
| Exact repeated retain | Reuses its record and updates only its successful cached date |
| Corrupt, incomplete or contract-rejected history | Rejected and preserved, even when another record was requested |
| Capacity exhausted | Explicit error with no eviction or partial publication |
| Cached content | Synthetic; `currentChecks` remains `unknown` |

The immutable key is schema version, ID and exact string version; publication
timestamp and digest are immutable metadata under that key. No records are
automatically discarded, so every committed identity remains represented by its
original bytes. There is no separate list of observed-but-never-retained versions.

Storage lives only in `rules-preview-v1.json`. Its internal version discriminator
is the JSON **string** `"1"`, avoiding numeric rounding during version admission.
Unsupported versions and malformed files are rejected without deletion. Earlier
catalog/pricebook format-1 and storage-version-2 files remain untouched: they never
stored rules bytes, so their presence cannot populate this cache. There is no
cross-file migration, downgrade rewrite or inferred rules version.

One actor must own each app-controlled cache directory. An overlapping retain is
rejected while its predecessor awaits bytes. Cancellation is checked before work,
after the download and before the synchronous commit. Download, hash, identity,
validator or publication failure before commit retains the previous file. A
cancellation arriving after commit does not undo it. A caller may explicitly
restore a previously validated complete file after investigating corruption;
there is no silent repair or fallback to another record.

The reader opens one nonblocking descriptor, rejects non-regular objects and
reads at most the configured envelope limit plus one byte. A symlink to a regular
file remains subject to the same actual read limit. The app controls directory
ownership; this is not a hostile-path sandbox or cross-process cache protocol.

Foundation's [atomic data write](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic)
provides the single-file replacement boundary. iOS also requests file protection
until first user authentication. This is not evidence of physical power-loss
durability, a transaction spanning the separate pair cache or an OS background
expiration-handler result.

| Engineering bound | Default / supported range |
| --- | --- |
| Original artifact bytes | 512 KiB / positive, at most 64 MiB |
| Retained rulesets | 32 / 1–128 |
| Exact encoded envelope bytes | `maximumArtifactBytes * 4 + 1,048,576` / positive, at most 512 MiB |
| Request ID and version | Nonempty, at most 256 UTF-8 bytes each |
| Request publication timestamp | Nonempty, at most 128 UTF-8 bytes |

These are implementation capacity bounds, not measured device budgets. Full
frozen-contract validation may impose tighter limits. Reducing a configured bound
below an existing cache makes it unavailable under that configuration and retains
the bytes for a compatible configuration.

## Validation and acceptance boundary

`RulesetCacheTests` exercises exact equality/hash values, side-effect-free guards,
missing namespaces, bounded non-regular/oversized reads, original history after
restart, repeated retention, immutable conflicts, digest/identity/validator
failures, corrupt-history recovery, exact quota boundaries, suspended cancellation,
overlap and a controlled filesystem obstruction followed by recovery and retry.
The filesystem fault moves the prior directory to an explicit backup before
obstructing its original path; its preserved bytes are checked, then restored.

The existing Catalog persistence fixtures are explicitly header-only synthetic bytes with a
controlled identity decoder. They test storage and mandatory callback behavior;
they do not execute the full Ruleset validator or establish policy,
publisher or source-use acceptance. Unicode equality controls exercise public
value semantics before contract admission, not admission of non-ASCII frozen IDs.

PlannerTransfer's `RulesetCacheValidatorTests` separately use the complete frozen
45-rule fixture through the real adapter. They cover whole-body rejection,
original bytes and distinct version spellings after restart, failed retention
with correction, exact-pin mismatch, corrupt older history when another or missing
pin is requested, and explicit offline selection after failed/corrected rules
preparation. Their pair-cache fixture validator is a closed test-only byte
allowlist, not a general Catalog/Pricebook contract implementation.

Run `swift test --package-path Packages/PlannerCatalog` and the storage regression
and actual process-exit commands in [PlannerData's guide](../PlannerData/README.md#reproduce).
Run the receiving adapter suite with
`swift test --package-path Packages/PlannerTransfer --filter RulesetCacheValidatorTests`.
Linux without CryptoKit explicitly skips hash-dependent persistence cases. A skip
or successful compile is not a persistence pass. The existing macOS Catalog and
unsigned iOS/SDK checks must execute the complete current source before delivery.
The Transfer checks qualify the added receiver dependency and integration suite;
no hashing fallback or workflow exception is introduced.

This contribution advances #87's pinned rules-storage subtask. Its full offline
cache/edit/restart acceptance still needs actual application integration and
receiving evidence beyond these cache/decoder/selection APIs. [#88](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/88)
still requires its real OS cancellation/background and complete-release evidence.
Physical-device, rights, service, store and release outcomes remain distinct.
