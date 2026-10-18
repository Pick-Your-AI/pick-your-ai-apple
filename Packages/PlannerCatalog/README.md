# Atomic public catalog preview cache

Partial implementation for [Apple #87](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/87), [#88](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/88) and [#31](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/31). This standalone Swift 6 package stores an entire catalog/pricebook pair in one bounded local envelope. It neither downloads from an invented service nor publishes catalogs.

## Frozen input and cache boundary

Research revision `4addb4d45d3eadb4598262532823634980b8a1b5` was inspected on 2026-10-18. Existing [catalog-snapshot](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/4addb4d45d3eadb4598262532823634980b8a1b5/contracts/v1/schemas/catalog-snapshot.schema.json) and [pricebook](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/4addb4d45d3eadb4598262532823634980b8a1b5/contracts/v1/schemas/pricebook.schema.json) identify artifacts with `schema_version`, `id`, `revision`, `captured_at`. Catalog and pricebook identities need not be identical. The local `CacheManifest` pins each identity and SHA-256 of its exact unmodified bytes. Its `formatVersion` belongs exclusively to this internal cache format; it is not an extension of frozen v1, a publisher manifest, an accepted release tuple, or a source-rights receipt.

Callers must provide the frozen JSON Schema validation adapter. Header decoding and hash verification cannot establish full schema conformance. There is no permissive validator default. Test fixtures intentionally contain only synthetic headers to isolate cache mechanics; they are **not** production-shape canonical fixtures or conformance evidence. No bundled product catalog is added.

The package only admits `syntheticPreview`. Every returned snapshot is explicitly synthetic. `production` rejects before download and on load, including when a preview cache already exists. There is no user-supplied boolean that can authorize real-data promotion. Real mode remains unavailable until the canonical publisher/rights acceptance integration is implemented against an actual accepted receipt.

## Activation and recovery

- Use an app-controlled directory and one `CatalogCache` actor per directory; it is a single-process component, not an app-extension shared cache. A concurrent refresh is rejected; an old refresh cannot overwrite a later completion.
- Downloads remain in memory until both pins, digests, sizes and contract validators pass. The transport adapter must also bound streaming downloads before constructing `Data`; this package checks size after the callback returns.
- Activation uses one Foundation atomic file replacement. Cancellation is checked before and after each await and before synchronous commit. Cancellation after that commit boundary does not roll back a completed release. Retry starts the pair again and is safe after interrupted or duplicate delivery; byte-range resume is not claimed.
- A bounded ledger retains up to 2,048 observed artifact-version pins across restart and refresh. Reusing the same kind/schema/id/revision with different timestamp or digest is rejected, including previously active historical versions. Exhausting this bound fails closed until a separately reviewed migration/retention strategy exists; history is never silently evicted. The same envelope limit applies before commit and on load. Loading reads from one open file handle in chunks of at most 64 KiB and consumes at most the envelope limit plus one byte before rejecting oversize data. A separate path-size check cannot enforce that bound if a file grows or the path is a small symlink to a larger target.
- Failed validation/download/cancellation leaves the previous file untouched. Restart revalidates the complete envelope; corrupt on-disk active data is unavailable and retained for diagnosis, never returned partially or silently repaired. A corrupt active envelope also blocks refresh, preserving its version ledger for explicit diagnosis/recovery rather than silently forgetting immutable versions. This is not a guarantee against device power loss, disk hardware failure, or malicious modification of both manifest and data. Digests establish consistency, not publisher authenticity.
- Cached time and age are exposed. Current checks are always `unknown`; cached content alone does not prove current compatibility or pricing. Historical selection lookup and rules caching are not implemented here.
- The directory contains only public preview artifacts. Draft persistence belongs to the separate persistence package; account-private content must not use this cache. iOS writes select protection until first unlock. Locked-device behavior needs a device test.

Platform references inspected: [Foundation atomic writing](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic), [CryptoKit SHA256](https://developer.apple.com/documentation/cryptokit/sha256). The documentation endpoint served its JavaScript shell in this environment; the macOS/iOS SDK compile and runtime tests remain the concrete API verification. This cache provides cancellation semantics for a future foreground/background coordinator, not BGTaskScheduler registration or an assertion of OS scheduling.

The bounded-reader regressions distinguish exactly-at-limit invalid JSON from an
oversized envelope, reject a symlink whose target exceeds the limit even though
the link's own size is small, and retain both the link and target after rejection.
A separate recovery regression explicitly restores the original valid envelope
and checks the complete pair, cached date, synthetic status and unknown current
checks after restart. The two rejection tests do not require CryptoKit; successful
validated recovery requires the Apple hashing implementation. These controlled
filesystem tests do not simulate device interruption or prove a release receipt.
API references checked 2026-10-18:
[bounded FileHandle read](https://developer.apple.com/documentation/foundation/filehandle/read(uptocount:))
and [path attributes describe a symlink itself](https://developer.apple.com/documentation/foundation/filemanager/attributesofitem(atpath:)).

## Validation and remaining acceptance

### Package privacy manifest

The target explicitly bundles [PrivacyInfo.xcprivacy](Sources/PlannerCatalog/PrivacyInfo.xcprivacy).
The bounded reader uses `fstat` to check the opened cache object's regular-file
type. Apple lists `fstat` in the file-timestamp API category even when the caller
uses another field in that metadata structure. Reason `C617.1` covers metadata
access inside the app's own container. Keep the cache in that container; the
manifest does not justify inspecting arbitrary external paths. This component
uses the metadata locally and does not include it in transport requests.

`PrivacyManifestTests.testPackagedManifestDeclaresOnlyAppContainerFileMetadataReason`
loads the manifest from the built SwiftPM resource bundle and verifies its exact
category and reason. The package record does not determine the integrating app's
tracking, collection or store answers. The [#101 source inventory and release
reconciliation record](../../docs/validation/issue-101-privacy.md) retains the
required app-level checks and primary Apple references. Reassess the manifest
when API use, cache location or SDK composition changes.

### Package execution

Run `swift test` from this directory on macOS. The dedicated `macos-catalog-cache` workflow uses Xcode 16.4 / Swift 6, records the toolchain, exercises CryptoKit and compiles for iOS Simulator without signing. Linux can compile and run non-hashing guards, but hashing returns `unsupportedHashPlatform`; hash-dependent tests explicitly skip, not pass. Initial Linux Swift 6.0.3 check: 17 tests discovered, 5 executed successfully, 12 skipped, zero failures. Hosted Apple-platform results must be attached to the PR before merge.

| Live criterion | Implemented evidence | Remaining acceptance |
| --- | --- | --- |
| #87 offline use preserves edits without unavailable checks passed | Unknown current status, cached date/age; `testRestartPreservesPairAgeAndUnknownChecks`, missing-cache case | Integrate draft editing, rules and historical references; actual airplane-mode journey and receiving review |
| #87 incomplete/missing cache after restart | Missing cache returns nil; truncated/tampered envelope rejected without deletion | Native UI stale/unknown disclosure and draft edit/restart replay |
| #88 partial downloads never activate mixed release | Complete pair encoded in one atomic file; corrupt-download retention/retry, cancellation, duplicate and concurrent delivery tests | macOS CI receipt; receiving review |
| #88 OS cancellation retains old release/resumes safely | Actual task cancellation while second download is suspended leaves old pair active; retry activates complete pair | OS expiration-handler wiring, scheduling/low-connectivity integration and device replay; no scheduling guarantee |
| #31 real mode rejects reserved demo IDs | Production gate rejects every manifest and cached preview; synthetic IDs used only in tests | Canonical full-shape fixture inventory, native screen/export/screenshot labeling and supported-device evidence |
| Issue evidence and receiving disposition | Source identity, test names, limitations and workflow supplied here | Independent engineering review pending; product receiving review and issue closure remain separate |

No physical-device run, power-loss durability measurement, full-disk test, signing, release, publication rights, canonical schema conformance or production receiving approval is claimed by these unit tests.


## Bounded public artifact transport

On Apple platforms, `PublicArtifactClient` uses an ephemeral credential-free
URLSession and `AsyncBytes` to bound received bytes before returning a Data value.
It accepts HTTPS GETs only on the configured exact host/port, with no URL userinfo,
query or fragment. Every redirect is refused, even within the same origin. Cookies,
shared credentials, disk caches and automatic retries are disabled. Status, JSON
MIME type and advertised size are checked before body consumption; the actual
stream has an independent byte bound. Error values exclude URLs and server bodies.
Cancellation and all early exits cancel the underlying transfer.

Pass `client.fetch(artifactURL)` through the cache's downloader closure. The cache
still validates immutable pins, SHA-256, schema callback and both artifacts before
activation; the transport neither grants source-use rights nor authenticates data
by itself. Configure only explicitly authorized artifact URLs. “Public” describes the intended data, not an IP-address filter; this is not an SSRF sandbox for untrusted origins. Query-signed
URLs, credentials, API writes and production promotion are intentionally unsupported.
No endpoint is hard-coded or provisioned. No network request occurs on construction.

The eight new Apple-only regression tests cover real URLSession behavior with a
synthetic URLProtocol, exact/oversized streams, interruption, cancellation, HTTP
errors, MIME/length rejection, wrong-origin/credential URLs, redirect refusal,
redacted timeout and subsequent recovery. These are controlled transport fixtures,
not a live staging/TLS/physical-device receipt. They are excluded on Linux because
FoundationNetworking lacks the Apple AsyncBytes API. Existing catalog workflow
runs them on the selected macOS/Xcode toolchain and compiles for iOS. Hosted results
must pass for the exact PR head before merge. Related partial work: #44, #45, #87,
#99, #106; pagination, app integration, live services and device gates remain open.

Primary API references checked 2026-10-18:
[streaming bytes](https://developer.apple.com/documentation/foundation/urlsession/bytes(for:delegate:))
and [underlying task](https://developer.apple.com/documentation/foundation/urlsession/asyncbytes).


## Snapshot-consistent local discovery

`CatalogSearchIndex` searches a bounded local projection of already validated
canonical records. `CatalogSearchEntry` is an internal display projection, not a
new wire schema. An adapter must validate the original artifact and retain its
source-use/evidence semantics before installing entries; this index never promotes
data, infers compatibility, or turns a synthetic fixture into real product facts.

It installs at most 10,000 bounded entries atomically, rejects duplicate `(id, version)` keys and
changed bytes under the currently installed identity, and sorts deterministically
by folded title, kind, ID and version. Distinct versions of one item remain separate, preserving the frozen selection pin fields `catalog_item_id` and `catalog_item_version`. Kind is a filter and display field, not an extra namespace for a duplicate pin. The durable cache remains responsible for historical
immutable-version enforcement. Query/filter/page-size/sort-bound opaque tokens are valid
only for the issuing index and exact installed generation. Refresh during paging
throws `stalePage`; callers must discard the old displayed page collection and
restart, never concatenate different revisions. A failed install preserves the old
release. Reinstalling the identical release preserves active cursors.

Eight regression tests cover page boundaries, stable ordering, no duplicate composite keys and preservation of distinct versions,
refresh between pages and clean restart, foreign cursors, query/filter/limit drift,
normalized text search, immutable identity conflict, clear/missing state and input
bounds. Existing hosted catalog CI must execute these tests and compile iOS for the
exact final head. This is partial #45/#59 behavior; no actual API cursor contract,
live staging handoff, full canonical catalog decoder, UI, source inspection or
physical-device acceptance is claimed.

### Explicit local sort selection

`CatalogSearchSort.title` keeps the existing folded-title, kind, ID and version
order. Callers can instead request `.kind`, which orders by exact kind, folded
title, ID and version. Both are ascending display orders with deterministic
identity/version ties; neither sorts by compatibility, evidence, price or a
semantic interpretation of version strings. Missing specification values are
not evaluated by this display projection.

Sort is part of each opaque page token. Reusing a token after changing sort throws
`mismatchedPage`; restarting without a token produces the requested order from
the same immutable snapshot. An omitted sort means `.title`, so callers continuing
a kind-sorted page must pass `.kind` again. Query and kind filters retain their
existing normalization and exact-match behavior, and counts cover all matching
entries before pagination. The index has no access to drafts or selections.

Three additional regressions cover deterministic duplicate-label/version ties,
identical reinstall during pagination, both directions of sort mismatch, a clean
restart, and combined normalized query/kind filters with an empty result. Native
execution remains required on the exact candidate. This advances the local sorting portion of
[Apple #59](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/59). It does not
provide the catalog screen, saved filters, unknown-spec sorting policy, network
page failure/retry, accessibility journey or whole-issue receiving acceptance.
