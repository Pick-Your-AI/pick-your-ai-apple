# Frozen-v1 catalog, snapshot and transfer boundaries

This portable Swift 6 package implements part of Apple [#32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32), [#33](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/33), [#82](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/82) and [#102](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/102). It has no storage, network, credential or UI authority. A successful parse establishes schema validity only, never compatibility, ownership, deployment readiness or source-use rights.

## API and integration

- `CatalogItem.decode(_:)` validates a single frozen-v1 catalog item, preserves its exact `CatalogKind` identity and every supported field, and returns an immutable value. Kind-specific specs and their required tier are checked against the unchanged canonical schema. No missing optional fact is filled in and no catalog item becomes a user selection.
- `CatalogSnapshot.decode(_:)` validates a complete frozen-v1 catalog envelope and every item before returning an immutable snapshot. It preserves catalog identity, exact revision, capture timestamp and item order. A malformed envelope or item rejects the entire document; this boundary cannot activate a cache or publish a partial catalog.
- `BuildTransfer.snapshot(fromDraftJSON:)` validates a complete frozen-v1 BuildSnapshot and returns an immutable value. Missing fields and fewer than two selections fail; no defaults, locks or synthetic values are inserted. Keep editor drafts in PlannerData even when this transition fails.
- `BuildTransfer.preview(_:)` accepts a bare snapshot or the existing web `pickyour.ai/build-export` version-1 envelope. Envelope provenance is untrusted metadata, not a verified catalog activation. `usesSyntheticData` is nil for bare imports; do not interpret that as production evidence.
- `ImportPreview.fork(localOwner:timestamp:)` explicitly creates a new UUID-based build identity, revision 1 and draft lifecycle. Source owner is replaced by the caller's local identity. Every lock, selection and link is retained. This API cannot overwrite an existing record; the integration must insert the returned value as a new draft only after user confirmation.
- `BuildTransfer.export(_:publicOwnerAlias:)` produces a bare frozen-v1 snapshot accepted by the web import boundary. The schema allowlist is enforced before and after projection. It removes notes, extensions and the original owner, requires an explicit public alias, and retains revision locks. The caller must obtain rights/confirmation for visible name, objectives and settings before sharing.

The package deliberately uses immutable schema-validated `JSONValue` with a typed `CatalogKind` discriminator instead of claiming generated per-field Codable DTO coverage for every catalog kind. Catalog decoding reuses the existing parser and validator without introducing a second schema engine or changing PlannerCore dependencies. `CatalogItem.encoded()` retains all supported fields for local serialization; it does not sanitize content or grant redistribution rights. `BuildSnapshot.encoded()` is an internal/private persistence serialization, **not** a sanitized sharing API; use `BuildTransfer.export` for Files/share sheets.

## Privacy and input limits

`BuildSnapshot.encoded()` reparses its exact normalized output and verifies the
original immutable value before returning bytes for local persistence. Compact
input can expand when JSON strings are escaped; output beyond the same decoding
limits fails explicitly instead of returning an unreadable saved representation.
Private notes/extensions and exact locks remain intact in this local operation.
Sharing still requires the separate `BuildTransfer.export` projection and review.
The native transfer suite includes a slash-expansion rejection and private-field
round-trip regression; only actual hosted results establish Swift execution.

The transfer gate rejects secret references and credential-like property names. It also rejects account references, encryption-key references, approval tickets, index names and endpoint/artifact URLs because they can disclose private infrastructure, signed links or credentials. This is a conservative client transfer subset; it does not redefine the frozen schema. Notes/extensions on import are rejected rather than silently accepted. Export strips them before applying the transfer gate. A schema-valid snapshot containing these fields can remain local but cannot be transferred through this package. This is not arbitrary free-text secret detection: names, aliases and other allowed text require preview and deliberate user review. It provides no remote share capability or server authorization.

Input is bounded to 512 KiB of UTF-8, 48 nesting levels and 16,384 JSON nodes. Duplicate keys (including escaped aliases), invalid UTF-8, trailing input, wrong types/enums and unknown schema fields fail with payload-free error codes. JSON numeric tokens are restricted to at most 15 numeric digits, magnitude at most 9,007,199,254,740,991, and nonzero magnitude at least 10^-12; larger/smaller values fail explicitly rather than rounding. Money remains the exact schema-constrained decimal string. Leap-second timestamps are unsupported and rejected. URI checking implements an ASCII RFC3986 subset and rejects malformed percent escapes and all IP-literal (IPv6/IPvFuture) hosts; full general-purpose JSON Schema/URI conformance is not claimed.

## Pinned inputs and validation

`source-manifest.json` names the canonical research revision and SHA-256 hashes for the unchanged frozen build/selection/common/catalog-item/catalog-snapshot schemas and synthetic build/catalog fixtures. These hashes were compared with the research import manifest. Bundled schemas resolve locally; schema `$id` values never cause network requests. The evaluator implements only the keywords used by these resources. The 129-case shared corpus includes positive settings for all 29 selection kinds, per-kind unknown settings, wrong Boolean types, missing catalog version pins, and build version/date/decimal/empty-selection failures. Swift and Python Draft202012Validator with FormatChecker replay exactly the same JSON corpus. Synthetic fixtures are not real catalog or installed-application evidence.

Run:

```sh
swift test --package-path Packages/PlannerTransfer
python3 -m venv /tmp/planner-transfer-validation
/tmp/planner-transfer-validation/bin/pip install 'jsonschema[format]==4.26.0'
/tmp/planner-transfer-validation/bin/python Packages/PlannerTransfer/Tools/verify_contract.py
```

The verifier explicitly requires date-time and URI format support; plain jsonschema without format dependencies can silently skip these checks. `.github/workflows/swift-transfer.yml` runs hash/reference parity, macOS Swift tests and unsigned iOS Simulator compilation with Xcode 16.4 (16F6). Local execution: Swift 6.0.3 on Ubuntu 24.04, ten tests passed; four source hashes and 129 canonical cases passed with Python 3.12/jsonschema 4.26.0. Hosted/physical evidence must be recorded separately when actually observed.

Implementation uses Foundation JSONDecoder only for individual JSON strings and JSONEncoder for value serialization; an explicit bounded parser detects duplicate keys before decoding. Apple [JSONDecoder documentation](https://developer.apple.com/documentation/foundation/jsondecoder) was checked on 2026-10-18 but returned a JavaScript shell; runtime behavior is covered by executable tests instead of claiming newly verified documentation semantics.

## Catalog-item conformance slice (#32)

Inputs remain frozen contract `1.0.0`, research revision
`7acbefbf4e4e700231e88be272bc89e3a73dde15`. The new resources are copied byte-for-byte
and compared with that revision's `IMPORT_MANIFEST.json`:

| Resource | SHA-256 |
| --- | --- |
| `schemas/catalog-item.schema.json` | `81c960c6e7dfe046634062e3f9ce5a1089b1d88adbd9fd45d9a67dcfc0339a25` |
| `examples/catalog.json` | `2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8` |

The canonical synthetic catalog has one item for each of the 29 kinds. The item
boundary validates common metadata, every conditional spec, kind/tier pairing,
required fields, enums, wrong types (including Boolean/number distinctions), numeric
bounds, identifiers, formats, uniqueness and additional-field rules. Optional fields,
explicit unknown billing, provenance and namespaced extensions remain intact. The
catalog schema defines no money/rate/budget field: such additions are rejected even
when their money object is correctly formatted. Existing build/selection conformance
continues to reject numeric money and retain exact decimal strings.

`Tools/catalog_vectors.py` generates 1,635 compact test mutations from the pinned
schema and fixture. It does not generate product defaults or alter canonical inputs.
The existing `Tools/verify_contract.py` verifies deterministic regeneration and
compares every mutated item with Python Draft202012Validator/FormatChecker. Swift
`CatalogItemTests` applies the same mutations and exercises the public decoder,
round-tripping successful results. Separate tests cover all 29 kind identities,
duplicate/escaped keys, size/depth/complexity limits and uninferred optional facts.
Run `python3 Packages/PlannerTransfer/Tools/catalog_vectors.py` to check regeneration;
`--write` updates only the synthetic mutation file.

Six cases explicitly distinguish canonical acceptance from this client's stricter
numeric range, IP-literal URI, and terminal-newline pattern limits. The existing
leap-second, precision and size/depth/complexity limits also remain in force. Unsupported
representations fail rather than being rounded, discarded or reported as a canonical
schema failure. This is a bounded schema-driven item decoder, not whole JSON Schema
conformance, generated per-field DTOs, approved real catalog activation or an Apple
UI integration. The separate envelope boundary below validates a whole snapshot.

Original preparation evidence for this slice: Python 3.12/jsonschema 4.26.0 verified
all six source hashes, the existing 129 cases and the 1,635 catalog cases. Swift/Xcode
were absent in that implementation workspace. Subsequent actual hosted source and
receiving runs are recorded below; the earlier lack of local Apple tooling is not
the current native-validation disposition.

## #32 receiving conformance record

Reviewed output: [Apple #32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32),
the hash-pinned Swift boundary model/validator conformance report, refreshed on
2026-10-18. This record reconciles the three live acceptance criteria against the
delivered catalog, build and selection boundaries. Its publishing PR supplies the
independent receiving disposition for this exact documentation and model strategy;
issue closure follows reviewed signed-main delivery of the record.

### Delivered model strategy

The engineering choice is a single immutable `JSONValue: Encodable` representation,
bounded `JSONParser` decoding, the exhaustive 29-case `CatalogKind` discriminator,
and schema validation before a
`CatalogItem` or `BuildSnapshot` can be constructed. `FrozenValidator` reads the
unchanged frozen per-kind field definitions and conditional selection settings.
It validates fields that generated Codable containers alone would otherwise need
to duplicate, including unknown properties, enum values, kind/tier pairing and
required settings. Public construction retains the bounded raw parser so duplicate
keys cannot disappear before validation. Encoding rechecks the exact output's
reopening limits and value preservation.

This delivers the requested all-kind Swift decode/validation behavior through the
already independently reviewed model architecture. No generated per-field Swift
DTOs are claimed. Adding such convenience types is a separate ergonomics choice,
not missing kind or spec validation. The issue's title and implementation checklist
are reconciled explicitly with this accepted schema-driven implementation rather
than asserting that a code generator ran.

### Exact source, native execution and delivery

| Stage | Immutable identity and observed result |
| --- | --- |
| Frozen inputs | Contract `1.0.0`, research revision `7acbefbf4e4e700231e88be272bc89e3a73dde15`. [source-manifest.json](source-manifest.json) records the six SHA-256 values for build, selection, common and catalog-item schemas plus the two synthetic examples. Bundled resources are byte-identical to the canonical import; no schema identifier is used as a network endpoint. |
| Reviewed source | [#216](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/216), source `8f60ad0c458f4fbf5f48182c7655be55f94471bd`, tree `7572b62c1a30fd0574a100e30758a15eccbf8ea9`. Independent in-session full source review covered the discriminator, parser/validator, generator, verifier, tests, manifest and documentation. Normal squash produced verified signed `1aaf515526bfa347c3f1176771c4b4dbe78a4d08` with the same tree. |
| Actual source execution | [Run 39105885010 / job 117611605590](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39105885010/job/117611605590) checked out prepared merge `441675ff394c38256d0ac67ba5de0299407875b7`, tree `7572b62c1a30fd0574a100e30758a15eccbf8ea9`, with ordered parents `7952f0cbedc8b19c03b6491197cf1160054c3cd7` and reviewed source `8f60ad0c458f4fbf5f48182c7655be55f94471bd`. It passed all 32 XCTest cases, six source hashes, 129 build/selection cases and 1,635 catalog cases, followed by unsigned iOS Simulator SDK compilation. Xcode 16.4 / build 16F6, Apple Swift 6.1.2. |
| Actual receiving execution | [#227 run 39112613078 / job 117631807159](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39112613078/job/117631807159) checked out `7de9b112fa1fe7744d30a3b0c2851eaf04f33b5d`, tree `b0f809e6bb831665e4829fc87a33396d754aeb60`. It independently passed the same six hash checks, 129 and 1,635 vectors, all 32 XCTest cases with zero failures/skips, and unsigned iOS Simulator compilation under Xcode 16.4 / 16F6 and Swift 6.1.2. This is macOS XCTest plus SDK compilation, not an iPhone/iPad UI or physical-device claim. |
| Accepted main | Normal reviewed #227 squash delivered verified signed `0ece6114ae2d639992346e8c1bb3ae239dbb1999`, tree `491624da29fd8b5b48af7e9087845fa861ee3b57`. [Review 5562335593](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/227#pullrequestreview-5562335593) and [delivery receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/227#issuecomment-6248229756) preserve the actual receiving checkout and subsequent documentation-only main advance. |
| Current-main preservation | At signed `8ca109963bfca3a707b1af8b80aabcd9dd28fd8a`, the catalog/build/selection parser, validators, models, fixtures, vectors and verifier remain byte-identical to the reviewed source. The only subsequent changes within this package are its README and the separately reviewed configuration comparison source/tests. Current-main code comparison is source-preservation evidence, not a claim that the older native run executed the later tree. |

### Criterion results and failure recovery

| Live #32 criterion | Evidence and disposition |
| --- | --- |
| Swift accepts valid fixtures and rejects incompatible contract payloads. | `CatalogItemTests.testAll29CanonicalKindsDecodeWithoutLosingFieldsOrIdentity` decodes all 29 canonical items, checks the exact kind set and metadata, compares every parsed field, and round-trips each immutable result. The shared catalog test replays every supported positive and malformed negative through the public decoder. Build/selection validation additionally covers all 29 conditional settings. These methods actually passed in both hosted runs above. |
| Decode all 29 kinds and wrong enums/types, missing required fields and non-decimal money; compare canonical validation results and reject incompatible versions. | The 1,635 catalog vectors include 588 cases accepted by both consumers, 1,041 rejected by both and six explicitly declared client subsets. They cover every required common/spec field, unknown enums/properties, wrong types including Boolean/number distinctions, supported enum choices and incompatible `schema_version`. The identical 129-case build/selection bundle includes 122 selection vectors and seven build vectors; `numericMoney` rejects a numeric `monthly_budget_amount`, while the valid decimal string stays exact. The canonical catalog defines no money field, so the catalog tests also reject invented price/rate/budget fields rather than importing rates into facts. Python Draft202012Validator/FormatChecker independently determines canonical outcomes; Swift checks its declared client outcomes and preserves every successful value. |
| The hash-pinned Swift boundary model/validator conformance report is linked with criterion results, exact versions, limitations and receiving-review disposition. | This section, its unchanged manifest and the linked source/receiving jobs provide the requested reproducible record. Source review and signed delivery are already complete. The record's publishing PR records independent delegated engineering/contract receiving review of the exact criterion mapping and schema-driven model choice. That review is an in-session technical disposition, not a fabricated human, service, product-data or release approval. |

Malformed inputs throw payload-free errors before returning a validated value.
Duplicate/escaped-key, byte/depth/node and unsupported-version tests exercise this
failure boundary. Every accepted mutation is encoded and reopened unchanged. The
slash-expansion regression rejects an output that exceeds its own reopening bound,
then decodes the untouched original input again. These are concrete decode and
serialization recovery results; this package has no persistence or network side
effect to roll back. Run the unchanged commands under [Pinned inputs and
validation](#pinned-inputs-and-validation) to reproduce the reference and Swift work.

### Limits and remaining separate outcomes

The six canonical/client differences are deliberately rejected large and tiny JSON
numbers, IP-literal URIs, and terminal-newline ID/currency/extension-key patterns.
The existing 512 KiB, 48-level, 16,384-node, 15-digit/numeric-magnitude and leap-second
limits also remain in force. Acceptance covers this disclosed client subset; it
does not assert acceptance of every theoretically valid JSON Schema payload.
Money remains a decimal string, and optional absence, explicit unknowns and
unverified provenance never become invented values or approval.

The previous remaining-work sentence grouped generated per-field DTOs, every other
top-level artifact, migration and device evidence under #32. Those are not extra
live acceptance criteria. This record replaces that broad closure condition with
the actual all-kind boundary criteria and the explicitly reviewed implementation
choice. Existing envelope, ruleset, graph, resource, cost and quality work retains
its own reviewed source and integration lanes. No pending PR is counted as delivered
by this record. Placement/CPU/unified-memory semantics and unsupported tuples remain
#35; evidence presentation is #36; cross-client and migration acceptance is #37;
catalog publication and real-data qualification are #40–43; live adapters and UI,
physical-device and release gates remain in their own work packages. The accepted
#22 framework/module decision supplies #32's prerequisite; broader downstream
completion is not inferred.

## Catalog-snapshot envelope (#32)

The envelope uses the same frozen contract and research revision as the item
boundary above. `schemas/catalog-snapshot.schema.json` is copied byte-for-byte from
the canonical `contracts/v1` directory, with SHA-256
`a5af428386768b698d280a18bf99c0e52364ee397a2075685213b3d0762693a4`, matching
that revision's `IMPORT_MANIFEST.json`. No schema rule, source fixture or existing
item vector changes.

`CatalogSnapshot` retains the original immutable `JSONValue` and an ordered array
of validated `CatalogItem` values. Its revision remains an exact `Decimal` within
the existing numeric representation limits. The timestamp is retained as supplied;
schema-valid time metadata does not prove freshness. Required metadata, additional
fields, revision minimum/type, date-time format and nonempty item cardinality are
checked with the same locally bundled validator. Each of the 29 item kinds uses
the existing item validation before any snapshot is returned.

The frozen schema permits duplicate item identities. This boundary preserves them,
including conflicting source claims, so a receiving graph or catalog activation
policy must resolve or reject them explicitly. It never deduplicates, chooses a
winner, grants source rights or interprets a catalog as approved production data.

The 512 KiB, 48-level and 16,384-node limits apply to the entire catalog, even when
every individual item would fit. Oversized catalogs fail explicitly. A larger or
paged representation requires a separately reviewed contract and consumer path.
`CatalogSnapshot.encoded()` reparses its exact output and checks value equality
before returning local serialization, so normalization cannot silently produce
bytes outside the reopening boundary. It is not a sanitized sharing API.

`Tools/catalog_snapshot_vectors.py` generates 77 compact envelope mutations. The
reference verifier applies those exact mutations with the existing item-vector
helper and checks Python Draft202012Validator/FormatChecker outcomes. Cases cover
metadata, malformed roots, empty/mixed item arrays, nested invalid input for all
29 kinds, ordering, duplicate identities and unsupported versions. Two cases mark
the existing stricter large-number and terminal-newline limits separately from
canonical schema acceptance. `CatalogSnapshotTests` replays the same corpus and
adds aggregate byte/node/depth, duplicate/escaped-key, identity-preservation and
serialization-expansion regressions.

Original preparation evidence for this envelope slice: all seven source hashes, the
existing 129 build/selection cases, 1,635 item cases and 77 envelope cases passed
the Python reference verifier. Swift/Xcode were absent in that implementation
workspace. The later actual native executions below supersede that tooling gap;
the envelope remains a separate top-level artifact boundary rather than an added
criterion for the accepted all-kind report in #32.

### Receiving evidence after catalog delivery (2026-10-18)

The tooling observations above describe the original implementation slices.
The catalog prerequisite is now delivered on signed main through [#227](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/227),
commit `0ece6114ae2d639992346e8c1bb3ae239dbb1999`. Its actual receiving
[transfer job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39112613078/job/117631807159)
passed 32 Swift tests, six source hashes, 129 build/selection cases, 1,635 item
cases and unsigned iOS Simulator SDK compilation.

The original envelope candidate also completed actual Xcode 16.4 / Swift 6.1.2
[native validation](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/182#issuecomment-6246002448):
36 Swift tests, all seven hashes and the 129 + 1,635 + 77 reference cases passed,
followed by unsigned iOS Simulator SDK compilation. That source-stage result
predates the two later serialization regressions retained from accepted main.

The #182 receiving candidate `412d6d01083cc5f8e8627635da7fd11cad92d9cd` preserved
every executable, schema, fixture, test and tool input from the separately executed
Swift 6.1.2 Linux composition:
38 XCTest cases passed with zero failures or skips in 5.068 seconds after a
6.34-second build. Its retained 12,928-byte log has SHA-256
`9e0c2166eb6788e18ecc1586f197054cd28034bc53089080fe67d78f13b51a94`.
That source identity check did not rerun those inputs or turn the portable result
into Apple execution.

The later actual [#182 transfer job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39116407061/job/117643015395)
checked out `e625080eb80d49693d445293ed6adb581b289230`, tree
`a73fb503726e7d3a0275c4dce3a4cfabd137a683`, with ordered parents accepted catalog
main `0ece6114ae2d639992346e8c1bb3ae239dbb1999` and that receiving candidate.
Xcode 16.4 / 16F6 and Apple Swift 6.1.2 passed all seven source hashes,
129 build/selection + 1,635 catalog-item + 77 envelope cases, all 38 XCTest cases
with zero failures/skips, and unsigned iOS Simulator SDK compilation. All eleven
source checks completed successfully. Normal reviewed squash produced verified
signed `94f436653f46421a8bb983224df055b3fd05241a` with that exact tree and sole
accepted parent `0ece6114ae2d639992346e8c1bb3ae239dbb1999`.

These are source/signing-stage results. Later main compositions retain their own
actual receiving checks; this record does not relabel those 38 cases as execution
of additional comparison, UI or contract changes. Catalog activation, source-use
rights, physical-device behavior and production release remain separate outcomes.

The subsequently accepted [#252 conformance record](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/252),
delivered on signed main `971e8ea6500c52a5be0493c7686ffc7dc7792cb4`, governs #32's
three literal all-kind boundary criteria and accepted immutable model strategy.
Earlier preparation statements grouping generated per-field DTOs, other top-level
artifacts and migration under #32 are superseded by that criterion-specific
disposition. The envelope's separate delivery does not add a new #32 closure gate
or claim completion of other work packages.

## Remaining acceptance

Independent code review and hosted macOS/iOS compilation remain required for new code. A cross-package SQLite integration test now saves an empty draft, rejects snapshot export and malicious import, reopens the store, and verifies identical payload, locks, revision and history. PlannerData is a test-only dependency; the library remains independent. macOS 14 is the package testing floor; iOS 17 remains the product floor. #32's delivered all-kind boundary and explicit model/representation limits are reconciled in the [receiving conformance record](#32-receiving-conformance-record); its exact record review and signed publication govern closure. #33’s exact draft/snapshot boundary criteria are satisfied by the linked [criterion-specific receipt](../../docs/acceptance/issue-33-draft-snapshot-boundary.md), subject to its recorded receiving disposition; the earlier UI-integration gap is reconciled there. Actual UI autosave/termination remains #69 and Files workflows remain #82. #82 still needs actual Files/share-sheet flows, cross-client UI round trips and approved privacy/source-use review. #102 still needs server cross-user access, capability guessing and Universal Link/device tests against the real service and signed app. No broader hardware, release or production claims are made.


## Local configuration comparison

`BuildComparison.compare(before, after)` advances Apple [#81](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/81)
using two immutable snapshots from the existing frozen-v1 boundary. It compares
objectives, version locks, policy, selection settings/roles/versions/enabled state,
and relationships. Selection/link IDs define the match; reordering those arrays
is immaterial. IDs remain identity coordinates even when their text matches a
private field name: a selection named `notes` or a link named `secret` still has
its public configuration compared. Privacy rules apply to actual field names and
values within the record, not to its ID. Each row preserves before/after values and the selection kind with
its T0–T6 display group from the canonical
[contract mapping](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/afa7513bd278791ffd7e751fb11f9869549ecd13/docs/CONTRACT_MAPPING.md).
Missing values stay absent, distinct from zero, false and empty values. Decimal
strings remain exact. The comparison cannot edit, restore, export or save either input.

A duplicate selection/link ID is rejected even when the frozen JSON Schema admits
it. Different content claiming one build ID/revision is rejected; merely reordering
selections/links is permitted. At most 2,048 difference rows are returned; exceeding
that bound fails explicitly and yields no misleading truncated comparison.

Private owner references, notes and extension contents are excluded. Known private
infrastructure and credential-reference values are replaced by a hidden marker,
without retaining their bytes in the result or error. Free-text build names and
other allowed setting values are local display content, not automatically safe to
share. This API is not an export projection.

Imported lifecycle labels and extension measurements have no authority here.
Quality, capacity, compatibility and cost remain explicitly unqualified: this
comparison neither accepts measurements nor computes a price difference. Qualified
outcome/estimate comparison requires separate exact-build evidence with matching
workload, locks, units, conditions and source approval. An unknown result is never
rendered as zero or an endorsement.

Sixteen synthetic regression tests cover exact setting/lock differences, absent
workload inputs, added/removed/disabled selections, decimal strings, relationships,
deterministic ordering, ambiguous IDs, conflicting revision identity, privacy,
foreign extension measurements, fork identity and bounds. The four identifier
regressions cover changed, added and removed selections/links with field-like IDs,
while requiring nested notes/extensions to remain excluded and private settings
to remain hidden. Native UI selection,
qualified outcomes/costs and physical accessibility review remain separate #81
acceptance work. Hosted macOS/iOS checks are required before merge; a Linux run
does not establish native UI or device behavior.

Local validation on 2026-10-18: official Swift 6.0.3 for Ubuntu 24.04 with system
SQLite 3.45.1 passed all 24 PlannerTransfer tests, including the twelve comparison
cases and the existing canonical/transfer/durable-draft cases. The temporary Linux
toolchain and development headers are not repository dependencies or release inputs.

Catalog serialization reparses the exact encoded bytes before returning them. Compact
input can expand during JSON normalization; output beyond the same decoder bounds
is rejected rather than returned as bytes that cannot be reopened. A near-limit
slash-expansion regression covers this boundary; native execution remains required.
