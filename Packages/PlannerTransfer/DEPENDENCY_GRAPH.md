# Frozen dependency graph boundary

This contributes bounded transport and preservation to Apple [#32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32),
[#35](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/35) and
[#71](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/71). It does not evaluate
compatibility, activate dependencies, determine affected selections or approve the
canonical example as executable policy.

## Contract and API

`DependencyGraph.decode(_:)` validates the complete document through the existing
bounded JSON parser and unchanged frozen schema. It returns immutable `value`,
graph identity/revision and ordered `DependencyEdge` values. Every edge preserves
its identifier, dependent kind, prerequisite kind, relationship, activation label
and rationale. Endpoint kinds reuse all 29 `CatalogKind` cases; the four
relationships and eight activation labels retain their exact wire identities.

The graph's direction is explicit: `dependentKind` depends on `dependsOnKind`.
The decoder never reverses edges or treats `informs` as a hard requirement. An
activation such as `production_only` remains data until an accepted consumer
interprets it. Repeated identifiers, repeated edges, self edges and cycles remain
in their original order because frozen v1 does not prohibit them. A receiver that
needs a unique or acyclic graph must apply separately reviewed policy; silently
dropping edges would change the supplied artifact.

The entire document must fit the existing 512 KiB, 48-level and 16,384-node
limits. Existing interoperable numeric bounds apply to revision; the public
`Decimal` property represents an already validated positive integer. Unknown
fields, kinds, relationship/activation labels and incompatible versions fail.
Duplicate keys, including escaped aliases, fail before schema validation. One
invalid edge rejects the entire graph. No partially validated value escapes.

`encoded()` is local serialization. It reparses the exact output and compares
the value before returning, so normalization cannot produce bytes that exceed
the same reopening bounds. This grants no sharing, source-use or publication
authority and retains the parser's documented representation limits.

## Unchanged pinned inputs

Both inputs match research revision `7acbefbf4e4e700231e88be272bc89e3a73dde15`
and its `IMPORT_MANIFEST.json` byte for byte. They are recorded in the existing
`source-manifest.json`; schema references resolve locally.

| Canonical source | SHA-256 |
| --- | --- |
| `schemas/dependency-graph.schema.json` | `fb6a8bb42a9424d4ff2b520301f816c247789a3d70d1124afea1a8dc5ed5bd75` |
| `examples/dependency-graph.json` | `e9b3bca19a9cf8241fd74f6618824882a3413649822add88be1ac93cb3f1bacc` |

These are frozen example inputs, not measured product evidence or a source-rights
receipt. No generator, schema, reference evaluator or source authority in research
is changed.

## Reproduce and observed evidence

```sh
python3 Packages/PlannerTransfer/Tools/dependency_graph_vectors.py
python3 Packages/PlannerTransfer/Tools/verify_contract.py
swift test --package-path Packages/PlannerTransfer
```

Use the existing pinned `jsonschema[format]==4.26.0` reference environment. The
graph generator writes only its synthetic compact mutation resource when invoked
with `--write`; its default mode verifies deterministic bytes. The same 150 cases
run through Python Draft202012Validator/FormatChecker and the public Swift decode
boundary. They cover every endpoint kind and relationship/activation combination,
required fields, wrong/null types, unsupported fields/versions and malformed mixed
edge arrays. Three cases explicitly record canonical acceptance outside the
client's large-number and terminal-newline identifier subset.

Six Swift tests also cover the unchanged complete example, exact typed direction
and labels, round trips, duplicate/escaped keys, byte/depth/aggregate-node limits,
preserved repeated/cyclic/self edges and serialization expansion. They do not
replace service, device, UI or graph-policy tests.

Local preparation on 2026-10-18 passed all eight pinned source hashes, the existing
129 build/selection and 1,635 catalog cases, all 150 new graph cases, deterministic
regeneration and whitespace checks. Swift and Xcode are unavailable in this local
workspace; native execution and independent receiving review remain required
before ordinary signed-main integration. A source review or Python pass is not
a Swift runtime receipt.

## Issue-specific limits

| Required output | Implemented boundary | Remaining acceptance |
| --- | --- | --- |
| #32 accepts valid frozen payloads and rejects incompatible ones | Graph schema/identity/edge validation, typed labels and shared reference vectors | Actual native execution, other top-level/model/migration requirements and receiving contract review |
| #35 preserves canonical relationships and exposes representation gaps | Existing kind-level edges round-trip without invented placement fields; `placement`, `component_role`, `memory_pool` and `hybrid` activation mutations reject | Accepted per-selection hybrid/role/memory-pool representation, versioned migration and Apple integration |
| #71 rechecks affected components after changes | Exact directed graph is available to an eventual governed consumer | Activation policy, dirty-state propagation, evaluator binding, stale-result handling and real UI/service integration |

Frozen v1's kind-level dependency graph cannot encode the full hybrid placement,
component-role or memory-pool tuple requested by #35. Those gaps remain
unsupported and route to research [#40](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/40)
for a versioned contract decision. No undocumented field or inferred default is
added here. All three issues remain open until their complete criteria and
receiving evidence are satisfied.
