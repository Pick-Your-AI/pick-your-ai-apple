# Frozen-v1 catalog, resource, quality-record, snapshot and transfer boundaries

This portable Swift 6 package implements part of Apple [#32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32), [#33](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/33), [#49](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/49), [#82](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/82) and [#102](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/102). It has no storage, network, credential or UI authority. A successful parse establishes schema validity only, never compatibility, ownership, deployment readiness or source-use rights.

## API and integration

- `CatalogItem.decode(_:)` validates a single frozen-v1 catalog item, preserves its exact `CatalogKind` identity and every supported field, and returns an immutable value. Kind-specific specs and their required tier are checked against the unchanged canonical schema. No missing optional fact is filled in and no catalog item becomes a user selection.
- `CatalogSnapshot.decode(_:)` validates a complete frozen-v1 catalog envelope and every item before returning an immutable snapshot. It preserves catalog identity, exact revision, capture timestamp and item order. A malformed envelope or item rejects the entire document; this boundary cannot activate a cache or publish a partial catalog.
- `QualityEvaluationRun.decode(_:)` validates a frozen-v1 quality record and retains the supplied build/suite identities, timestamps, recorded status and measurements. Typed views preserve exact supported decimals, optional absence and array order. This structural boundary performs no evaluation, evidence authentication or current-build binding.
- `ResourceEstimate.decode(_:)` validates a frozen-v1 resource estimate artifact while preserving its exact decimal strings, ordered declarations and optional source absence. Parsing performs no capacity evaluation, dimensional qualification or current-build binding.
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

Input is bounded to 512 KiB of UTF-8, 48 nesting levels and 16,384 JSON nodes. Duplicate keys (including escaped aliases), invalid UTF-8, trailing input, wrong types/enums and unknown schema fields fail with payload-free error codes. JSON numeric tokens are restricted to at most 15 significant coefficient digits, 128 token bytes, exponent -64 through 64, magnitude at most 9,007,199,254,740,991, and nonzero magnitude at least 10^-12; larger/smaller values fail explicitly rather than rounding. Money remains the exact schema-constrained decimal string. Leap-second timestamps are unsupported and rejected. URI checking implements an ASCII RFC3986 subset and rejects malformed percent escapes and all IP-literal (IPv6/IPvFuture) hosts; full general-purpose JSON Schema/URI conformance is not claimed.

## Pinned inputs and validation

`source-manifest.json` names the canonical research revision and SHA-256 hashes for the unchanged frozen build/selection/common/catalog-item/catalog-snapshot/quality-evaluation-run/resource-estimate schemas and synthetic build/catalog/quality/resource-estimate fixtures. These hashes were compared with the research import manifest. Bundled schemas resolve locally; schema `$id` values never cause network requests. The evaluator implements only the keywords used by these resources. The 129-case shared build corpus includes positive settings for all 29 selection kinds, per-kind unknown settings, wrong Boolean types, missing catalog version pins, and build version/date/decimal/empty-selection failures. The additional CatalogItem, CatalogSnapshot, QualityEvaluationRun and ResourceEstimate corpora are described below. Swift and Python Draft202012Validator with FormatChecker replay the same concrete payloads. Synthetic fixtures are not real catalog or installed-application evidence.

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

Accepted output: [Apple #32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32),
the hash-pinned Swift boundary model/validator conformance report. Normal reviewed
[#252](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/252) delivered this
record on 2026-10-18 as verified signed main
[`971e8ea6500c52a5be0493c7686ffc7dc7792cb4`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/971e8ea6500c52a5be0493c7686ffc7dc7792cb4),
tree `de2d6f1cd5235bec2bc6bceec7dbf56b8f6fc877`, with sole accepted parent
`8ca109963bfca3a707b1af8b80aabcd9dd28fd8a`. The
[source acceptance review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/248#pullrequestreview-5562609585)
and [receiving review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/252#pullrequestreview-5562651805)
accept all three literal criteria and this exact model strategy. The
[completed receiving receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32#issuecomment-6249160321)
records issue closure. The original native results below retain their own source
and receiving identities; the documentation delivery supplied no new native run.

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

Observed local evidence for this envelope slice: all seven source hashes, the
existing 129 build/selection cases, 1,635 item cases and 77 envelope cases passed
the Python reference verifier. Swift/Xcode are absent in this workspace; the six
new Swift tests require the hosted transfer workflow before integration. This
remains partial #32 work, with the broader model, migration and receiving-review
requirements listed below unchanged.

## Remaining acceptance

Independent code review and hosted macOS/iOS compilation remain required for new code. A cross-package SQLite integration test now saves an empty draft, rejects snapshot export and malicious import, reopens the store, and verifies identical payload, locks, revision and history. PlannerData is a test-only dependency; the library remains independent. macOS 14 is the package testing floor; iOS 17 remains the product floor. #32's accepted all-kind boundary and explicit model/representation limits are reconciled in the [receiving conformance record](#32-receiving-conformance-record) and its completed signed-delivery receipt. #33’s exact draft/snapshot boundary criteria are satisfied by the linked [criterion-specific receipt](../../docs/acceptance/issue-33-draft-snapshot-boundary.md), subject to its recorded receiving disposition; the earlier UI-integration gap is reconciled there. Actual UI autosave/termination remains #69 and Files workflows remain #82. #82 still needs actual Files/share-sheet flows, cross-client UI round trips and approved privacy/source-use review. #102 still needs server cross-user access, capability guessing and Universal Link/device tests against the real service and signed app. No broader hardware, release or production claims are made.


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

## Quality-record conformance slice (#32 / #49)

`QualityEvaluationRun` adds the remaining quality-record decode boundary using the
existing bounded parser and the existing frozen-schema evaluator. Its schema and
synthetic example are copied byte-for-byte from research revision
`7acbefbf4e4e700231e88be272bc89e3a73dde15` and match that revision's import manifest:

| Resource | SHA-256 |
| --- | --- |
| `schemas/quality-evaluation-run.schema.json` | `ed6b3f60805428e3788ce27fa224fb3d5008998f0637f24723bf65eea546a959` |
| `examples/quality-evaluation-run.json` | `bc0abc0b33e2b6bf77fc4609ac88a73981068eac6fabf604c255f58fec954a6d` |

Only `decode(_:)` can construct the immutable run. Typed views expose recorded
status, comparator and measurement values while `value` retains every supported
field. Build revision and sample size remain integral `Decimal` values rather than
being narrowed to a machine integer. The frozen schema permits arbitrary positive
JSON integers and arbitrary measurement numbers; this client retains the explicit
numeric subset described above and rejects unsupported inputs without rounding.
This does not claim whole-schema numeric interoperability with other clients.

Optional notes remain absent, empty or populated as supplied; a measurement unit
can be absent or an empty string. Required artifacts may be empty. Measurement
order, duplicate metric names, duplicate artifact URIs and private text survive
round trips. Artifact URIs remain inert strings, including supported non-HTTP
schemes. `encoded()` is local serialization retaining private content, with exact
semantic value comparison and the decoder's bounds applied to its returned bytes.
It is not a sanitizing export, evidence upload or source-use approval.

The frozen schema does not enforce timestamp order, measurement/comparator/pass
consistency, aggregate status consistency, unit semantics or current build/suite
resolution. Decoding preserves those reported facts without computing a score,
turning an `incomplete` label into failure, or assigning a quality/compatibility
verdict. A schema-valid synthetic score remains synthetic and unverified.

`Tools/quality_vectors.py` deterministically generates 202 compact mutations shared
by Python and Swift. They cover all required fields, null/type/enum/additional-field
failures, identifier/date/URI checks, optional distinctions, reported labels and
numeric boundaries. The 18 deliberate client differences are three terminal-newline
identifiers, two unbounded positive integers, twelve measurement numeric cases and
one IP-literal URI. Swift inserts the raw replacement JSON before decoding so its
test helper cannot round a numeric token through `Double` or Foundation bridging.

Original local reference validation on 2026-10-18 passed eight source hashes, the existing
129 transfer and 1,635 catalog cases, and all 202 quality cases using Python 3.12.14
with `jsonschema[format]==4.26.0`, including active URI and date-time format checking.
Nine new Swift tests are declared for typed preservation, shared vectors, absence,
uninterpreted labels, exact numbers, duplicate keys, resource bounds, sanitized
errors and normalized-output rejection. Swift/Xcode execution was unavailable in
that preparation environment; subsequent actual hosted macOS Swift and unsigned
iOS SDK results retain their own exact-commit receipts.

This advances #32 transport coverage and #49 quality-record preparation. It does
not establish qualified evaluation execution, exact-current-workload evidence,
resource-estimate binding, live service/fault handling, UI delivery or receiving
acceptance. The existing #49 prerequisites (Apple #44, Apple #34 and Android #79)
and its remaining criteria remain open. The separate #32 all-kind boundary
disposition is recorded above. Frozen contracts, service ownership and other active
artifact-boundary implementations are unchanged.

## External resource estimate artifact boundary

`ResourceEstimate.decode(_:)` validates the complete frozen-v1 resource-estimate
artifact and returns an immutable `JSONValue` plus its ordered `estimates`. The
public identity accessors retain `id`, `build_id`, `build_revision` and
`generated_at`. Each estimate retains its metric, exact decimal **string**, unit,
estimator ID/version, declared confidence, assumptions, selection IDs and optional
source URI. No numeric value passes through binary floating point. Omitted sources
stay absent, partial metric coverage stays partial, and repeated estimates remain
present in their original order.

The schema and complete two-estimate synthetic example are copied byte-for-byte
from research `7acbefbf4e4e700231e88be272bc89e3a73dde15`. Their SHA-256 values are
`39ab5d061f9021ce14e1f987717441cff04d1a40f76db5582d343d599a5d876c` and
`41469a377c0b428e779c269eb052fa8f455b4768e2add3c137b5e465a79a362f`, respectively.
The unchanged default validator still loads build/selection/common; the immutable
resource decoder selects only its resource-estimate/common schemas.

The public decoder applies the same 512 KiB, depth, node, numeric and duplicate-key
limits to the whole artifact before validating every entry. A malformed later
entry rejects the entire artifact. Duplicate selection IDs within an entry fail
the frozen schema's uniqueness rule. `encoded()` reparses the exact normalized
bytes under the same limits and requires value equality, so expanding string
escapes cannot produce a representation that the decoder cannot reopen.

`Tools/resource_estimate_vectors.py` deterministically creates **223** exact
JSON-text cases: **112 canonical-positive / 111 canonical-negative**, with
**106 client-positive** results. It covers all five metrics, four units and four
declared confidence values, required/unknown fields, decimal types and spelling,
identities, revisions, timestamps, selection uniqueness, optional source syntax,
and a malformed final entry. Six canonical-positive inputs are deliberately outside
the existing client representation: a large numeric revision; an IP-literal source
URI; and the terminal-newline exceptions in the ID, build ID, selection ID and
decimal-string dollar-anchored patterns. The corpus records each distinction.

Eight Swift tests replay that shared corpus and separately check complete fixture
round trips, arbitrary integer-length decimal strings with twelve fractional digits,
source absence, preserved foreign/partial/repeated declarations, escaped duplicate
keys and selection aliases, aggregate bounds, output expansion and payload-free
rejection. The combined transfer workflow verifies all eleven pinned inputs and Python
expectations before actual macOS tests and the unsigned iOS SDK build. Local Linux
execution and hosted Apple results require their own exact-commit receipts.

Parsing preserves a declaration; it does not make it an accepted estimate. Frozen
v1 enumerates metric and unit independently, so structurally admitted combinations
still require a dimensional policy. Declared `verified` confidence is not an
independent receiving receipt. Build/revision and selection references are preserved
without checking the current model/runtime/context/concurrency tuple or freshness.
This API computes neither capacity nor measured quality, accepts no source rights,
and sends no requests. #49's service, exact-tuple rejection, UI and receiving
conformance requirements remain open. The separate #32 all-kind boundary
disposition is recorded above.
