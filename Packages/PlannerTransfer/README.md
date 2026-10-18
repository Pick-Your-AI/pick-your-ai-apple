# Frozen-v1 catalog, snapshot and transfer boundaries

This portable Swift 6 package implements part of Apple [#32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32), [#33](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/33), [#82](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/82) and [#102](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/102). It has no storage, network, credential or UI authority. A successful parse establishes schema validity only, never compatibility, ownership, deployment readiness or source-use rights.

## API and integration

- `CatalogItem.decode(_:)` validates a single frozen-v1 catalog item, preserves its exact `CatalogKind` identity and every supported field, and returns an immutable value. Kind-specific specs and their required tier are checked against the unchanged canonical schema. No missing optional fact is filled in and no catalog item becomes a user selection.
- `CatalogSnapshot.decode(_:)` validates a complete frozen-v1 catalog envelope and every item before returning an immutable snapshot. It preserves catalog identity, exact revision, capture timestamp and item order. A malformed envelope or item rejects the entire document; this boundary cannot activate a cache or publish a partial catalog.
- `Ruleset.decode(_:)` validates a whole frozen-v1 rules artifact, including every recursive expression and operand alternative. It preserves all declarations and literals without evaluating compatibility or accepting a policy.
- `BuildTransfer.snapshot(fromDraftJSON:)` validates a complete frozen-v1 BuildSnapshot and returns an immutable value. Missing fields and fewer than two selections fail; no defaults, locks or synthetic values are inserted. Keep editor drafts in PlannerData even when this transition fails.
- `BuildTransfer.preview(_:)` accepts a bare snapshot or the existing web `pickyour.ai/build-export` version-1 envelope. Envelope provenance is untrusted metadata, not a verified catalog activation. `usesSyntheticData` is nil for bare imports; do not interpret that as production evidence.
- `ImportPreview.fork(localOwner:timestamp:)` explicitly creates a new UUID-based build identity, revision 1 and draft lifecycle. Source owner is replaced by the caller's local identity. Every lock, selection and link is retained. This API cannot overwrite an existing record; the integration must insert the returned value as a new draft only after user confirmation.
- `BuildTransfer.export(_:publicOwnerAlias:)` produces a bare frozen-v1 snapshot accepted by the web import boundary. The schema allowlist is enforced before and after projection. It removes notes, extensions and the original owner, requires an explicit public alias, and retains revision locks. The caller must obtain rights/confirmation for visible name, objectives and settings before sharing.

The package deliberately uses immutable schema-validated `JSONValue` with a typed `CatalogKind` discriminator instead of claiming generated per-field Codable DTO coverage for every catalog kind. Catalog decoding reuses the existing parser and validator without introducing a second schema engine or changing PlannerCore dependencies. `CatalogItem.encoded()` retains all supported fields for local serialization; it does not sanitize content or grant redistribution rights. `BuildSnapshot.encoded()` is an internal/private persistence serialization, **not** a sanitized sharing API; use `BuildTransfer.export` for Files/share sheets.

## Privacy and input limits

The transfer gate rejects secret references and credential-like property names. It also rejects account references, encryption-key references, approval tickets, index names and endpoint/artifact URLs because they can disclose private infrastructure, signed links or credentials. This is a conservative client transfer subset; it does not redefine the frozen schema. Notes/extensions on import are rejected rather than silently accepted. Export strips them before applying the transfer gate. A schema-valid snapshot containing these fields can remain local but cannot be transferred through this package. This is not arbitrary free-text secret detection: names, aliases and other allowed text require preview and deliberate user review. It provides no remote share capability or server authorization.

Input is bounded to 512 KiB of UTF-8, 48 nesting levels and 16,384 JSON nodes. Duplicate keys (including escaped aliases), invalid UTF-8, trailing input, wrong types/enums and unknown schema fields fail with payload-free error codes. JSON numeric tokens are restricted to at most 15 numeric digits, magnitude at most 9,007,199,254,740,991, and nonzero magnitude at least 10^-12; larger/smaller values fail explicitly rather than rounding. Money remains the exact schema-constrained decimal string. Leap-second timestamps are unsupported and rejected. URI checking implements an ASCII RFC3986 subset and rejects malformed percent escapes and all IP-literal (IPv6/IPvFuture) hosts; full general-purpose JSON Schema/URI conformance is not claimed.

## Pinned inputs and validation

`source-manifest.json` names the canonical research revision and SHA-256 hashes for the unchanged frozen build/selection/common/catalog-item/catalog-snapshot/ruleset schemas and synthetic build/catalog/ruleset fixtures. These hashes were compared with the research import manifest. Bundled schemas resolve locally; schema `$id` values never cause network requests. The evaluator implements only the keywords used by these resources. The 129-case shared corpus includes positive settings for all 29 selection kinds, per-kind unknown settings, wrong Boolean types, missing catalog version pins, and build version/date/decimal/empty-selection failures. Swift and Python Draft202012Validator with FormatChecker replay exactly the same JSON corpus. Synthetic fixtures are not real catalog or installed-application evidence.

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

Observed local evidence for this slice: Python 3.12/jsonschema 4.26.0 verified all six
source hashes, the existing 129 cases and the 1,635 catalog cases. Swift/Xcode are
absent in the implementation workspace, so the six new Swift tests have not run
locally. The existing transfer workflow will execute them and the reference verifier
on the exact PR head; native compilation, review and acceptance remain pending.

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

## Frozen ruleset syntax boundary (#32)

The ruleset schema and 45-rule synthetic example are copied byte-for-byte from
the same pinned research revision `7acbefbf4e4e700231e88be272bc89e3a73dde15`.
Their SHA-256 identities are
`b251e49774d7e6a34522555adefd40f56f5e647a8a2b4a69a0be0a4618b1a8d3`
and `05474568204fdbfd407cb4e4cfc9334e22fdf24e75111bed8990868926fab418`;
both are included in the nine-file source manifest. No frozen schema, policy
declaration, canonical fixture or earlier conformance vector is changed.

`Ruleset` retains the complete bounded `JSONValue`, ordered rule array, ID, version
and publication timestamp. Nested expression and operand objects must match exactly
one canonical `oneOf` branch; zero and multiple matches reject. A missing referenced
schema propagates as an unavailable resource even if another branch would match.
The existing whole-document byte/depth/node/numeric and duplicate-key limits apply
before validation. Normalized encoding reparses its exact bytes and requires equal
values within the same bounds. Optional owner absence, literal null/false and
on-unknown declarations remain distinct; no default, result or policy is inferred.

The deterministic `Tools/ruleset_vectors.py` generates 321 shared JSON-text cases
for the Python reference and Swift decoder. They cover all 15 expression operators,
three operand forms, seven metric names, three reference scopes, all 29 affected
kinds, required/unknown fields, malformed recursion, version/date/identity bounds,
and rule order/repeated identities. Most cases use one unchanged canonical rule
to bound replay work; the whole 45-rule source has its own case. Three canonical
positives explicitly exceed the established client numeric or strict terminal-newline
subset. Frozen version syntax rejects SemVer build metadata; the client does not
extend that rule. Eight Swift regressions add exact `oneOf` behavior, resource failure,
all-source preservation, duplicate keys and aggregate/encoding limits.

This is a schema-driven parsing boundary, not a rules evaluator or generated
per-field model set. A receiving graph/evaluator must apply accepted identity and
policy semantics; schema validity alone does not establish that repeated rule IDs
are usable. There is no cache activation, compatibility result, source-use acceptance,
network request or app UI change. Swift/Xcode are unavailable locally; the eight
new cases and unchanged existing suites require actual hosted execution and independent
receiving review. Catalog #179/#182 signed-main integration remains a prerequisite
for this stacked preparation. The broader #32 acceptance below remains open.

## Remaining acceptance

Independent code review and hosted macOS/iOS compilation are required before integration. A cross-package SQLite integration test now saves an empty draft, rejects snapshot export and malicious import, reopens the store, and verifies identical payload, locks, revision and history. PlannerData is a test-only dependency; the library remains independent. macOS 14 is the package testing floor; iOS 17 remains the product floor. #32 still needs generated per-field model coverage, other top-level contracts, supported migration dispositions, native conformance evidence and receiving contract review. The bounded catalog-item slice covers all 29 kind identities/spec validation alongside build and selection settings; it does not close the full work package. #33 still needs durable autosave-to-export UI integration with PlannerData. #82 still needs actual Files/share-sheet flows, cross-client UI round trips and approved privacy/source-use review. #102 still needs server cross-user access, capability guessing and Universal Link/device tests against the real service and signed app. These are partial issue deliverables, not issue-closure evidence. No hardware, signing, release or production claims are made.


## Local configuration comparison

`BuildComparison.compare(before, after)` advances Apple [#81](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/81)
using two immutable snapshots from the existing frozen-v1 boundary. It compares
objectives, version locks, policy, selection settings/roles/versions/enabled state,
and relationships. Selection/link IDs define the match; reordering those arrays
is immaterial. Each row preserves before/after values and the selection kind with
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

Twelve synthetic regression tests cover exact setting/lock differences, absent
workload inputs, added/removed/disabled selections, decimal strings, relationships,
deterministic ordering, ambiguous IDs, conflicting revision identity, privacy,
foreign extension measurements, fork identity and bounds. Native UI selection,
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
