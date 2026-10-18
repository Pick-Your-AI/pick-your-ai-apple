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
- A bounded ledger retains up to 2,048 observed artifact-version pins across restart and refresh. Reusing the same kind/schema/id/revision with different timestamp or digest is rejected, including previously active historical versions. Exhausting this bound fails closed until a separately reviewed migration/retention strategy exists; history is never silently evicted. The envelope size is checked identically before commit and before load.
- Failed validation/download/cancellation leaves the previous file untouched. Restart revalidates the complete envelope; corrupt on-disk active data is unavailable and retained for diagnosis, never returned partially or silently repaired. A corrupt active envelope also blocks refresh, preserving its version ledger for explicit diagnosis/recovery rather than silently forgetting immutable versions. This is not a guarantee against device power loss, disk hardware failure, or malicious modification of both manifest and data. Digests establish consistency, not publisher authenticity.
- Cached time and age are exposed. Current checks are always `unknown`; cached content alone does not prove current compatibility or pricing. Historical selection lookup and rules caching are not implemented here.
- The directory contains only public preview artifacts. Draft persistence belongs to the separate persistence package; account-private content must not use this cache. iOS writes select protection until first unlock. Locked-device behavior needs a device test.

Platform references inspected: [Foundation atomic writing](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic), [CryptoKit SHA256](https://developer.apple.com/documentation/cryptokit/sha256). The documentation endpoint served its JavaScript shell in this environment; the macOS/iOS SDK compile and runtime tests remain the concrete API verification. This cache provides cancellation semantics for a future foreground/background coordinator, not BGTaskScheduler registration or an assertion of OS scheduling.

## Validation and remaining acceptance

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
