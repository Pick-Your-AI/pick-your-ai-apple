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

Original local preparation on 2026-10-18 passed all eight pinned source hashes,
129 build/selection and 1,635 catalog cases, all 150 graph cases, deterministic
regeneration and whitespace checks. Swift and Xcode were unavailable in that
implementation workspace. The later actual hosted execution below supersedes
that tooling gap; the earlier Python result remains separately attributed.

### Actual receiving execution (2026-10-18)

The [#246 Transfer run 39120275091 / job 117654328957](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39120275091/job/117654328957)
checked out `c6dd87ca76b2d956d1224da55beed44f57fdc91d`, tree
`de006e023bdbb5fcd9429b71b01a6110923c8275`, with ordered parents accepted main
`8ca109963bfca3a707b1af8b80aabcd9dd28fd8a` and verified signed graph source
`1b120031636574c43e34949787fd1bd335820478`. Xcode 16.4 / build 16F6 and Swift 6.1.2
passed all eight source hashes, the 129 + 1,635 + 150 shared reference cases, all
42 XCTest cases with zero failures or skips, and unsigned iOS Simulator SDK
compilation. The actual inventory includes all six graph methods and the four
accepted-main comparison-ID regressions in addition to the earlier source suite.

Independent source and receiving reviews are linked in [#239](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/239)
and [#246](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/246).
The recorded execution belongs to that exact older receiving tree. Later main
compositions must preserve accepted changes, receive independent review and meet
their applicable current checks before normal signed-main delivery. This record
does not relabel the earlier run as execution of a later tree or infer graph
policy, application journeys, physical-device behavior or production activation.

## Issue-specific limits

| Required output | Implemented boundary | Remaining acceptance |
| --- | --- | --- |
| #32 accepts valid frozen payloads and rejects incompatible ones | Graph schema/identity/edge validation, typed labels and shared reference vectors extend the accepted all-kind boundary | The [accepted #32 conformance record](README.md#32-receiving-conformance-record) governs its three literal criteria and immutable model strategy; this graph is a separate artifact boundary, not an added issue-closure requirement |
| #35 preserves canonical relationships and exposes representation gaps | Existing kind-level edges round-trip without invented placement fields; `placement`, `component_role`, `memory_pool` and `hybrid` activation mutations reject | Accepted per-selection hybrid/role/memory-pool representation, versioned migration and Apple integration |
| #71 rechecks affected components after changes | Exact directed graph is available to an eventual governed consumer | Activation policy, dirty-state propagation, evaluator binding, stale-result handling and real UI/service integration |

Frozen v1's kind-level dependency graph cannot encode the full hybrid placement,
component-role or memory-pool tuple requested by #35. Those gaps remain
unsupported and route to research [#40](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/40)
for a versioned contract decision. No undocumented field or inferred default is
added here. #35 and #71 remain open until their complete criteria and receiving
evidence are satisfied.

[#32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32) was completed
through the independently reviewed [#252 conformance record](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/252),
delivered on verified signed main `971e8ea6500c52a5be0493c7686ffc7dc7792cb4`.
Its accepted immutable model strategy and all-kind criterion mapping supersede
earlier preparation statements that grouped generated per-field DTOs, other
top-level artifacts and migration into additional #32 closure requirements.
The graph's separate integration neither reopens those criteria nor completes
#35's placement representation or #71's governed evaluation and UI work.
