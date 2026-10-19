# Activation and direct dependency participants

This is a bounded implementation slice for Apple
[#71](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/71). It supplies a
pure planning function and a separate adapter for the existing validated frozen
graph. It does not call an evaluator, retire stored results, schedule work or
change the existing `AnalysisStore` generation and complete-identity gates.

The activation vocabulary comes from the frozen v1
[dependency semantics](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/docs/DEPENDENCIES.md).
The schema, graph example, decoder and reference vectors remain unchanged. This
consumer is an explicit client interpretation of that vocabulary; decoding a
graph continues to preserve its labels without executing them.

## Inputs and activation

`DependencyInvalidation.Context<Kind>` retains an ordered immutable array of
selection IDs, kinds and enabled flags, plus explicit optional serving mode and
production decisions. Only enabled selections contribute to activation. Disabled
and removed identities remain relevant to the result through the before/after
arrays. The Core package has no dependency on Transfer and defines no alternate
29-kind wire enum. `DependencyParticipantKind` identifies the six optional roles
needed by the predicates; Transfer's existing `CatalogKind` supplies them.

| Condition | Active when | Unknown when |
| --- | --- | --- |
| `always` | Always | Never |
| `self_hosted` | Mode is self-hosted or hybrid | Mode is unresolved |
| `non_api` | Mode is managed, self-hosted or hybrid | Mode is unresolved |
| `rag_enabled` | An enabled RAG pipeline exists | Never for a complete supplied selection projection |
| `agents_enabled` | An enabled agent framework exists | Never for a complete supplied selection projection |
| `fine_tuning_enabled` | Any enabled training framework, training compute, training dataset or fine-tuned model exists | Never for a complete supplied selection projection |
| `if_selected` | Both endpoint kinds have enabled selections | Never for a complete supplied selection projection |
| `production_only` | The caller supplies `production: true` | Production is unresolved |

The four representable modes match the frozen catalog's `spec_deployment_mode`
enum: API, managed, self-hosted and hybrid. Managed is non-API, but does not enable
the local-serving `self_hosted` predicate. Otherwise the condition is inactive.
Removing one T5 kind does not disable
fine-tuning while another enabled T5 kind remains. Missing mode or production is
`unknown`, never guessed from catalog identifiers, lifecycle labels or a default
API decision. An incomplete selection list is not a complete context: callers
must finish admission/resolution before using this API rather than representing
unknown optional membership as an empty list.

## Which edges participate

The caller supplies `changedKinds` from the actual edit, together with complete
before/after contexts. The algorithm visits every input edge once and compares
its old and new activity. An edge participates if its activity changed, or a
declared changed kind is either endpoint and the edge is not inactive in both
contexts. Thus API to self-hosted, or its reverse, considers the frozen
`dep.accelerator.model` edge even when only `deployment_mode` was edited.
Transitions between unknown and either known state are considered. Stable
unknown/unknown remains conservative for an incident edit; it does not expand
every unrelated edit across all unresolved branches.

Both endpoint kinds of a participating edge enter `affectedKinds`, which also
always includes all declared changed kinds. Newly affected kinds do not become
new seeds: the result is direct participation, not a transitive traversal. This
makes cycles and self edges finite and independent of traversal order. All four
relationship labels can supply participants; `informs` is not converted into a
hard requirement, and participation implies no compatibility outcome or severity.

`participatingEdges` preserves each original array index and its before/after
activity in input order. Duplicate IDs and duplicate rows keep distinct indices.
The result's kind collections are sets with no presentation order.
`affectedSelectionIDs` includes every old or new selection whose kind is affected,
including disabled records and selections absent from the new context. It follows
first occurrence in the before array, then the after array, deduplicating IDs by
exact UTF-8 bytes. It does not normalize or invent an identity. The generic Core
projection expects already admitted source identities; Transfer applies its
existing public validation before constructing them.

## Validated Transfer consumer

`BuildSnapshot.dependencyContext(mode:production:)` preserves all admitted
selection IDs/kinds/enabled flags from the existing immutable Build. Serving mode
and production remain explicit caller-resolved inputs. The graph adapter maps
every activation case exhaustively and preserves the original edge order. Its
`DependencyParticipantPlan` carries graph ID/revision alongside the Core result;
the original graph retains every relationship, rationale and source field.

```swift
import PlannerCore
import PlannerTransfer

let before = oldBuild.dependencyContext(mode: .api, production: false)
let after = newBuild.dependencyContext(mode: .selfHosted, production: false)
let plan = validatedGraph.affectedParticipants(
    changedKinds: [.deploymentMode], before: before, after: after)
// The caller binds these to the complete old/new Build and governed input tuple.
let selectionIDsToReconsider = plan.participants.affectedSelectionIDs
```

This adds a production dependency from PlannerTransfer to the existing local
PlannerCore product. Core stays dependency-free; the existing Transfer test
package closure already includes Core, Data and Catalog. No wire kind, schema,
resource, source pin or generated corpus changes.

## Caller obligations and evidence

The plan is not a cache-validity proof. Before retiring/replacing results or
requesting evaluation, the caller must retain the complete old/new Build identity,
all changed kinds, graph identity/revision and governed catalog/ruleset/input
bindings. Same-kind replacements, parameter edits and input changes remain real
edits even if activation is unchanged. A pin/revision change still invalidates
the whole analysis identity; this helper cannot authorize reuse of unaffected
fragments. Existing `AnalysisStore` admission and generation behavior is unchanged.

The source adds seventeen Core XCTest methods and five Transfer methods. They cover
mode-only transitions on the actual frozen edge, distinct managed/local-serving
participation, all activation labels, all
unknown/known mode pairs, production transitions, optional disable/removal, T5
membership, immutable old/new IDs, byte-exact identity deduplication, duplicate/
self/cyclic rows, finite direct behavior, all four retained relationships and
rejection before the validated adapter. These are source-declared tests; actual
execution and its exact checkout/toolchain belong to the delivering PR's receipts.

Run `swift test --package-path Packages/PlannerCore` and the same command with
`-c release`, then `swift test --package-path Packages/PlannerTransfer`. The
existing Core, Transfer and submission SDK workflows also compile and execute
their applicable package tests. No historical Android or Apple run is evidence
that these new methods executed.

#71 remains open for actual caller/evaluator integration, visible dirty/recheck
state, complete-identity behavior at that caller and UI/service receiving
acceptance. This implementation does not adopt unsupported physical-pool or
placement semantics, change a shared service, or supply physical-device/release
evidence.
