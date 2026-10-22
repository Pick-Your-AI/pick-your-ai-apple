# Explicit bundled synthetic dependency graph

This package input supplies one exact frozen synthetic graph to a Build that
explicitly locks that graph's ID and revision. It is an input for the reviewed
uncommitted settings boundary; it does not add a native editor or save a Build.

## Fixed source

The original Research example at commit
`7acbefbf4e4e700231e88be272bc89e3a73dde15`,
`contracts/v1/examples/dependency-graph.json`, is already independently pinned by
[source-manifest.json](source-manifest.json). Its 17,959 original bytes have
SHA-256 `e9b3bca19a9cf8241fd74f6618824882a3413649822add88be1ac93cb3f1bacc`,
graph ID `dependencies.core.1`, revision `1`, and 59 directed edges.

The new production resource is an exact byte copy of the existing test fixture.
`Package.swift` copies the separate `SyntheticInputs` directory, while the
existing `Resources` directory continues to contain the frozen schemas only.
The source manifest, original fixture, schema files and reference verifier are
unchanged. This directory separation preserves the verifier's schema inventory;
it does not bypass the input's fixed-digest and whole-document checks.

## Admission and ownership

`BuildDependencyGraphInput.bundledSynthetic(for:)` is an explicit opt-in.
It reads only the named production-bundle resource, bounds that read, compares
the complete original bytes against the fixed digest, calls the existing
`DependencyGraph.decode`, and matches the graph ID and exact Decimal revision
against the supplied Build locks. Foreign IDs or revisions stay unavailable.
There is no latest lookup, network request, arbitrary-response pin or fallback.

The returned value has private construction and immutable graph, original Data,
hash and `frozenSyntheticFixture` qualification. No caller-supplied approval
Boolean, graph, digest or public constructor can manufacture that qualification.
Hashing is unavailable on unsupported platforms and fails closed.
The internal bytes entry point used by the bundle loader and adversarial tests
retains the same fixed pin; it accepts no alternate expected hash or validator.

Graph admission remains structural. The existing frozen decoder retains
schema-allowed repeated edge identities, self-edges and cycles unchanged.
This input does not establish executable graph policy, compatibility, readiness,
publisher or source-use approval, or a complete catalog/rules/graph tuple.
An explicit synthetic input never upgrades an imported Build's provenance.

A later native receiving change must capture this input with the selected row,
local revision and editing session. It must retain the existing settings
validation, durable expected-revision write and stale-result retirement.
`BuildSettingsEdit.prepare` remains unchanged and produces only an uncommitted
proposal. No imported-record, DraftStore, form, native journey, wire-contract
or existing owner's branch changes are included here.

## Source-specific verification

The eight new package methods exercise the actual production-bundle factory and
its shared fixed-pin admission path: the exact resource and qualification,
foreign ID, changed and wide revision, schema-valid same-identity tamper,
equivalent JSON with different bytes, oversized/truncated input, immutable byte
copies, and the existing uncommitted settings consumer.

The test fixture and expected digest remain independent of the newly packaged
copy. Successful public-factory execution therefore requires the real production
resource to be present at its declared subdirectory. Existing graph decoding and
settings tests are retained.

This proposal has no Swift execution receipt yet. It requires its own concrete
source to compile and pass the configured package, resource and receiving gates.
Earlier source reviews and SDK/Transfer results retain their original identities
and do not establish execution of this provider or its new resource.

## Remaining general-input contract

Frozen Build locks contain only graph ID and revision. They do not provide a
graph digest, URL or issuer. A general graph provider still needs an explicitly
selected source-qualified pin and immutable exact-byte retention policy.
Computing a digest after an arbitrary download does not establish that it is the
intended production graph. Other locked graphs remain unavailable here.

This package addition does not complete native settings forms, persistence,
updated-result presentation, cancellation or replacement behavior, or the
broader Apple #67 acceptance criteria.
