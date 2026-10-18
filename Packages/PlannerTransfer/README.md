# Frozen-v1 snapshot and transfer boundary

This portable Swift 6 package implements part of Apple [#32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32), [#33](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/33), [#49](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/49), [#82](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/82) and [#102](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/102). It has no storage, network, credential or UI authority. A successful parse establishes schema validity only, never compatibility, ownership, deployment readiness or source-use rights.

## API and integration

- `BuildTransfer.snapshot(fromDraftJSON:)` validates a complete frozen-v1 BuildSnapshot and returns an immutable value. Missing fields and fewer than two selections fail; no defaults, locks or synthetic values are inserted. Keep editor drafts in PlannerData even when this transition fails.
- `BuildTransfer.preview(_:)` accepts a bare snapshot or the existing web `pickyour.ai/build-export` version-1 envelope. Envelope provenance is untrusted metadata, not a verified catalog activation. `usesSyntheticData` is nil for bare imports; do not interpret that as production evidence.
- `ImportPreview.fork(localOwner:timestamp:)` explicitly creates a new UUID-based build identity, revision 1 and draft lifecycle. Source owner is replaced by the caller's local identity. Every lock, selection and link is retained. This API cannot overwrite an existing record; the integration must insert the returned value as a new draft only after user confirmation.
- `BuildTransfer.export(_:publicOwnerAlias:)` produces a bare frozen-v1 snapshot accepted by the web import boundary. The schema allowlist is enforced before and after projection. It removes notes, extensions and the original owner, requires an explicit public alias, and retains revision locks. The caller must obtain rights/confirmation for visible name, objectives and settings before sharing.

The package deliberately uses immutable schema-validated `JSONValue` instead of claiming generated Codable DTO coverage for every catalog kind. `BuildSnapshot.encoded()` is an internal/private persistence serialization, **not** a sanitized sharing API; use `BuildTransfer.export` for Files/share sheets.

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

`source-manifest.json` names the canonical research revision and SHA-256 hashes for the unchanged frozen build/selection/common/resource-estimate schemas and synthetic build/resource-estimate fixtures. These hashes were compared with the research import manifest. Bundled schemas resolve locally; schema `$id` values never cause network requests. The evaluator implements only the keywords used by these resources. The 129-case shared build corpus includes positive settings for all 29 selection kinds, per-kind unknown settings, wrong Boolean types, missing catalog version pins, and build version/date/decimal/empty-selection failures. The additional ResourceEstimate corpus is described below. Swift and Python Draft202012Validator with FormatChecker replay the same concrete payloads. Synthetic fixtures are not real catalog or installed-application evidence.

Run:

```sh
swift test --package-path Packages/PlannerTransfer
python3 -m venv /tmp/planner-transfer-validation
/tmp/planner-transfer-validation/bin/pip install 'jsonschema[format]==4.26.0'
/tmp/planner-transfer-validation/bin/python Packages/PlannerTransfer/Tools/verify_contract.py
```

The verifier explicitly requires date-time and URI format support; plain jsonschema without format dependencies can silently skip these checks. `.github/workflows/swift-transfer.yml` runs hash/reference parity, macOS Swift tests and unsigned iOS Simulator compilation with Xcode 16.4 (16F6). Local execution: Swift 6.0.3 on Ubuntu 24.04, ten tests passed; four source hashes and 129 canonical cases passed with Python 3.12/jsonschema 4.26.0. Hosted/physical evidence must be recorded separately when actually observed.

Implementation uses Foundation JSONDecoder only for individual JSON strings and JSONEncoder for value serialization; an explicit bounded parser detects duplicate keys before decoding. Apple [JSONDecoder documentation](https://developer.apple.com/documentation/foundation/jsondecoder) was checked on 2026-10-18 but returned a JavaScript shell; runtime behavior is covered by executable tests instead of claiming newly verified documentation semantics.

## Remaining acceptance

Independent code review and hosted macOS/iOS compilation are required before integration. A cross-package SQLite integration test now saves an empty draft, rejects snapshot export and malicious import, reopens the store, and verifies identical payload, locks, revision and history. PlannerData is a test-only dependency; the library remains independent. macOS 14 is the package testing floor; iOS 17 remains the product floor. #32 still needs broader catalog/model payload coverage and receiving contract review; this package covers build and selection settings, not every top-level contract. #33’s exact draft/snapshot boundary criteria are satisfied by the linked [criterion-specific receipt](../../docs/acceptance/issue-33-draft-snapshot-boundary.md), subject to its recorded receiving disposition; the earlier UI-integration gap is reconciled there. Actual UI autosave/termination remains #69 and Files workflows remain #82. #82 still needs actual Files/share-sheet flows, cross-client UI round trips and approved privacy/source-use review. #102 still needs server cross-user access, capability guessing and Universal Link/device tests against the real service and signed app. These are partial issue deliverables, not issue-closure evidence. No hardware, signing, release or production claims are made.


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
rejection. The normal transfer workflow verifies the six pinned inputs and Python
expectations before actual macOS tests and the unsigned iOS SDK build. Local Linux
execution and hosted Apple results require their own exact-commit receipts.

Parsing preserves a declaration; it does not make it an accepted estimate. Frozen
v1 enumerates metric and unit independently, so structurally admitted combinations
still require a dimensional policy. Declared `verified` confidence is not an
independent receiving receipt. Build/revision and selection references are preserved
without checking the current model/runtime/context/concurrency tuple or freshness.
This API computes neither capacity nor measured quality, accepts no source rights,
and sends no requests. #49's service, exact-tuple rejection, UI and receiving
conformance requirements remain open, alongside broader #32 contract adoption.
