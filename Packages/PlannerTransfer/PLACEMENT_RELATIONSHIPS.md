# Apple #35 placement and relationship conformance

Named output for [Apple #35](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/35):
**placement/relationship mapping and unsupported-tuple vectors**. This record
receives the existing frozen-v1 transport boundary after the accepted
[#32 model strategy](README.md#32-receiving-conformance-record). The selected
implementation is immutable `JSONValue: Encodable`, the bounded `JSONParser`, and
the public validated `BuildTransfer.snapshot(fromDraftJSON:)` and
`CatalogItem.decode(_:)` entrypoints. No new runtime model, evaluator, service,
schema field, implicit migration or production catalog record is introduced.

The client retains representable values exactly. It rejects unsupported fields
with `TransferError.schemaViolation` and unsupported artifact versions with
`TransferError.unsupportedVersion`. A schema-valid tuple can still have unresolved
binding, memory or context semantics: the mapping and vectors below expose those
gaps explicitly. A successful round-trip establishes structural preservation,
never runtime placement, compatible hardware, complete evidence or deployment
readiness.

## Inputs and version authority

The reconstruction baseline is signed Apple
[`13e67df89309289b42fd9302c5908041739d9d11`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/13e67df89309289b42fd9302c5908041739d9d11).
The unchanged [source manifest](source-manifest.json) pins Research
`7acbefbf4e4e700231e88be272bc89e3a73dde15`, contract **1.0.0**. The applicable inputs
are these original bytes; the two quality and two resource pins received by later
slices remain unchanged too.

| Input | SHA-256 |
| --- | --- |
| Build schema | `1beacb0b01fcdea0b8b47357cdf2e99d80a10b8a4218aaac9e3b6af55391b42a` |
| Selection schema | `f8f189c6555fec41e616c32f081d06fab9f966b0fa4891ddca55580f577d51a8` |
| Common schema | `0342ce2f1114e7276fc7f6a08ff5b86e8727caadd83ae4f443de9a7e1431c43c` |
| Synthetic build | `26762208769a8cf1012b4f33b1c1608556d275187ce21117d0b9632cdf951864` |
| Catalog-item schema | `81c960c6e7dfe046634062e3f9ce5a1089b1d88adbd9fd45d9a67dcfc0339a25` |
| Synthetic catalog | `2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8` |

Current semantic references were read at Research
[`8c8c876606b8d581b43afdd675b78d8bbec78966`](https://github.com/Pick-Your-AI/pick-your-ai-research/commit/8c8c876606b8d581b43afdd675b78d8bbec78966):
[contract mapping](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/8c8c876606b8d581b43afdd675b78d8bbec78966/docs/CONTRACT_MAPPING.md),
[frozen adoption rules](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/8c8c876606b8d581b43afdd675b78d8bbec78966/contracts/v1/ADOPTION.md),
[deployment/CD-2/5/6/7/11/13 queue](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/8c8c876606b8d581b43afdd675b78d8bbec78966/research/T0-configuration/deployment-mode.md#open-contract-decisions),
[context mapping](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/8c8c876606b8d581b43afdd675b78d8bbec78966/research/T1-model-selection/context-window.md#comparison-fields-and-contract-mapping)
and [T2 allocation/topology proposals](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/8c8c876606b8d581b43afdd675b78d8bbec78966/research/T2-infrastructure/contract-proposals.md#contract-gaps-requiring-decisions).
Research #40's [2026-10-18 owner disposition](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/40#issuecomment-6249840407)
accepts bounded prototype mechanics with constraints and explicitly adopts no
field, encoding, migration or executable rule. This client slice does not expand
that disposition. The separate A100/P4de proposal facts likewise do not authorize
pooled memory or deployment eligibility.

## Field and behavior mapping

`BuildSnapshot.value` retains the complete validated build; `CatalogItem.value`
and `spec` retain catalog facts. The following paths describe those existing
wire fields, not a second set of client properties.

| Concern | Frozen-v1 representation retained by Swift | Interpretation and unsupported boundary |
| --- | --- | --- |
| Identity and versions | Build `id`, `revision`, `schema_version`, complete `locks`; selection `id`, `kind`, `catalog_item_id`, `catalog_item_version` | No catalog refresh, rebinding, version substitution or lifecycle promotion occurs during serialization. Syntactically valid identifiers and version pins still require exact retained-source association at the consuming boundary. |
| Component roles and state | Each selection's exact `role`, `enabled`, kind-specific `settings` and array position | Role is a constrained string, not a placement enum. Duplicate kind/role or selection IDs remain structurally representable and unresolved. A decoder does not choose the first candidate or discard disabled components. CD-6/CD-13 own binding and applicability. |
| Directed relationships | Every link's `id`, `from_selection_id`, `to_selection_id`, all 17 canonical `relation` labels and optional Boolean `required` | Direction, order, repeated edges, cycles and explicit false survive. Absence stays absent. The frozen schema does not establish graph completeness, endpoint existence or unique deployment binding; those checks remain separate. |
| Hybrid and access labels | Catalog `deployment_mode.spec.mode` accepts `api`, `managed`, `self_hosted`, `hybrid`; model selection `settings.serving_mode` accepts `api` or `weights` | These labels round-trip. The wire representation does not record per-component runtime operator, reserved/shared capacity or placement allocations. API protocol/access is not proof of who operates the runtime. Mixed local/API access paths cannot imply automatic hybrid rule applicability. CD-2/CD-6/CD-7 apply. |
| CPU and hardware facts | Accelerator `accelerator_type`, `backends`, required `vram_gb`; compute profile `cpu_cores`, required `ram_gb`, optional `accelerator_ref` and `accelerator_count` | An explicit `cpu` fact is retained, including supplied zero VRAM. Missing required memory is rejected, never filled with zero. Optional accelerator facts remain absent, not proof of CPU-only placement. CD-2/T2-C03 own device-instance, pool and allocation semantics. |
| Per-device versus host memory | Accelerator `vram_gb` and `interconnect` stay separate from profile `ram_gb` and `accelerator_count` | Device memory is not multiplied into a usable pool or added to host RAM. A label such as `nvlink` does not prove allocatable capacity. No undocumented GB/GiB reinterpretation or unified-memory overlap is introduced. |
| Counts and parallelism | Selected accelerator `device_count`, `tensor_parallel_groups`; engine `tensor_parallel_size`; profile `instances` | Each distinct input survives, including contradictory values. The client does not equate groups, devices, ranks and instances or infer a feasible partition. |
| Context and serving routes | Selected `requested_context_tokens`, `reserved_output_tokens`, model `max_output_tokens`; catalog model `context_window_tokens`/`max_output_tokens`; optional policy `max_allowed_tokens`; workload averages | Values retain their individual meaning and location. No automatic sum, minimum, shared-window conversion, independent input cap or provider-route override is invented. Missing optional limits remain missing; required facts fail when absent. CD-5/CD-6/CD-11 own stage binding, route overrides and shared/separate limits. Existing historical v1 meanings are not rewritten. |
| Adapter/base relationships | Selection `use_adapter`, `derived_from` link, catalog `base_model_ref` where supplied | These references do not themselves prove consistent selected base/version, inherited deployment or joint engine/artifact support. CD-6 and the affected model/engine owners retain that decision. |
| Logical agent memory and extensions | `memory_store` settings and `stored_in` links; namespaced local `extensions` | Logical memory TTL is not device memory capacity. An opaque `x_memory_pool` extension remains local data, not an adopted pool model. The existing public transfer gate rejects extensions; this record does not use them to bypass contract governance. |

The boundaries retain their existing byte, numeric, depth, node, duplicate-key,
UTF-8 and schema limitations documented in the [package README](README.md#privacy-and-input-limits).
The new vectors neither loosen those limits nor claim complete JSON Schema
implementation. Canonical acceptance versus the existing client subsets remains
explicit in the original catalog/quality corpora.

## Reproducible placement vectors

The [generator](Tools/placement_vectors.py) produces
[98 compact mutations](Tests/PlannerTransferTests/Fixtures/placement-conformance.json)
over the unchanged original build/catalog fixtures. The fixture SHA-256 is
`59d5be49578224f3e82bd0c040fdee8d68bbb35c9d19ef7c95d13e397a1bffab`.
There are **73 build cases and 25 catalog cases**. Each case records its source
fixture, exact mutation paths and JSON values, canonical/client structural
expectations, a descriptive disposition, the decision queue and the reason.
`disposition` is test documentation, not an extra runtime status or policy engine.

| Disposition | Count | Expected structural result and covered examples |
| --- | ---: | --- |
| `preserved` | 30 | Both consumers accept and Swift reopens the same complete value. All 17 relation labels, direction, required true/false/absence, roles, disabled selection, four mode labels, separate memory facts/counts and context quantities. |
| `unresolved` | 20 | Both consumers accept the wire shape; interpretation remains unresolved. Mixed API/weight components, duplicate IDs/roles, two engine candidates, dangling/repeated/cyclic/empty links, absent optional facts, retained version pin, adapter binding, opaque extensions and distinct request counts. |
| `unsupported-field` | 24 | Both consumers reject 17 build and seven catalog additions. Component `deployment`/`placement`, pool/allocation/unified-memory fields, link role/allocation fields, independent input/shared-total/route-override fields and sequence expansion cannot be smuggled into v1. |
| `invalid-contract` | 24 | Both consumers reject 12 required-fact omissions, six legacy/future version inputs and six invalid role/relation/type/bound values. No coercion, defaults or silent migration. |

The [Swift tests](Tests/PlannerTransferTests/PlacementRelationshipTests.swift) run
the same mutations through the public decoders and exact `JSONValue` decimal
representation. All 50 accepted payloads must retain every field and round-trip;
all 48 rejected payloads must return the stated typed error. Additional assertions
inspect the concrete hybrid, direction, disabled, per-device/host/count/context
values and missing fields. Rejection/recovery checks retain the previous immutable
snapshot and locks, preserve rejected input, then successfully reopen the original
bytes. Duplicate `role` and escaped `r\u006fle` aliases must fail before schema
acceptance. These are parser/local snapshot recovery results, not a storage crash
or device-relaunch claim.

The [reference verifier](Tools/verify_contract.py) first checks all ten original
source hashes and deterministic regeneration, then executes the exact same
mutated payloads through `jsonschema` **4.26.0**
`Draft202012Validator` with the existing local registry and `FormatChecker`.
It also retains the 129 build/selection, 1,635 catalog, 202 quality and 223 resource
cases: **2,287 structural cases** including placement. The resource schema/example
and its cases were received separately; the original reconstruction below had
eight pins and no resource corpus. Those historical counts remain unchanged.
It performs structural schema validation, not the illustrative reference
compatibility evaluator or a serving-runtime experiment.

```sh
python3 Packages/PlannerTransfer/Tools/placement_vectors.py
python3 -m venv /tmp/planner-placement-validation
/tmp/planner-placement-validation/bin/pip install 'jsonschema[format]==4.26.0'
/tmp/planner-placement-validation/bin/python Packages/PlannerTransfer/Tools/verify_contract.py
swift test --package-path Packages/PlannerTransfer
git diff --check
```

## Original reconstruction and failure/recovery record

The source candidate was reconstructed after the original workspace became
unavailable, as recorded in [the issue checkpoint](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/35#issuecomment-6249873693).
The previous unpublished tree `4ce658553b96a37cde87501ec0d17f40d80e3245` and its
reported tests are historical; none of those results is attributed to this tree.

| Check | Actual result for this reconstruction |
| --- | --- |
| Python 3.12 / `jsonschema[format]` 4.26.0 reference replay | Passed all eight original hashes, 129 build/selection cases, 1,635 catalog cases, 202 quality cases and all 98 placement cases. The original imports and production source were unchanged. |
| First placement reference attempt | Failed `logical-memory-store-is-not-device-memory`: the draft synthetic TTL of zero violates the frozen minimum. Corrected the test payload to 24 hours; the subsequent full reference replay passed. The schema and expected valid/unresolved disposition were not weakened. |
| Swift 6.1.2 / Ubuntu 24.04.3 local package execution | Passed **49 unique XCTest cases**, each with one start and one pass, zero failures/skips, in 16.544 seconds. All four new placement methods passed, including the full 98-vector replay. Actual log SHA-256: `7a20eb88e2c974b8d6e8a1dedd243d80131a3394536f132f2f56c17375c478f2` (15,783 bytes). |
| Hosted macOS Swift / iOS Simulator SDK at original preparation | Not yet executed at this stage. The subsequent actual receiving execution is recorded separately below. |
| Receiving review and signed delivery at original preparation | Not yet completed at this stage. The later immutable reviews and signed delivery below supersede this historical pending state. |

The recovered environment initially lacked `libncurses.so.6` and SQLite development
headers; default compiler caches were read-only and the process sandbox interrupted
one compilation. Those attempts executed no XCTest cases. Recovery used the
PGP-verified official Swift 6.1.2 release, Ubuntu's signed package index for local
runtime/header extraction (SQLite 3.45.1-1ubuntu2.8), explicit project cache/include
paths and an authorized scoped test invocation. No system package, repository
source or assertion was changed to make the qualified run pass. The independently
reviewable source and fixture are the ones executed by that 49-case run.

## Signed receiving delivery and exact native evidence

The original reconstructed source was independently reviewed at
[`f58440e2`](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/269):
[contract and affected-client disposition](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/269#pullrequestreview-5563081670)
accepted the literal conditional v1-gap scope; the independent
[generator, fixture and reference review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/269#pullrequestreview-5563085360)
also found no source blocker. Later accepted-main composition preserved the
authored placement values, tests and limits while retaining accepted resource,
storage, toolchain and security work.

| Stage | Exact identity and observed result |
| --- | --- |
| Actual receiving execution | [Transfer run 39155271307 / job 117757238409](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39155271307/job/117757238409) checked out `4841d1c35a2912888da70c18437a1bce0b011257`, tree `b70ed1eb9a618acc510774dfbb024af93c9572cc`, ordered parents `71db949333d94958d7d7909a1dd16c51c2421e2e` and `d1013b2d2168393da0fbe23e1f5a471cf78f0111`. All **57 unique XCTest methods** passed with zero failures/skips, including all four placement methods and all 98 shared placement cases. The reference verifier passed **ten pins and 2,287 cases**, followed by unsigned iOS Simulator SDK compilation. Xcode **16.4 / 16F6**, Apple Swift **6.1.2**, and the actual commands are retained in the original job. |
| Original receiving log | Complete original job log: **129,079 bytes**, SHA-256 `7e5a0ce45a43ee083c87eee0b2f1440b4168141320d2406eb1adbbc94ed25c48`. The original method starts/passes, fixture results and checkout were independently qualified in the [final receiving review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/286#pullrequestreview-5564844903). This is inspection of that actual execution, not an additional native run. |
| Signed main delivery | Normal reviewed [#286](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/286) delivered valid signed `791c355812bfbbf8003941b59734118011d4734a`, tree `e85a7658a922704d93b76718c622edc5b2731e3c`, sole accepted parent `4a93e5e0667593b1fa78f838fc9f62312514b0c7`. All seven authored placement entries match the actual receiving composition above. Its later accepted carry was independently reviewed; the original execution is not reassigned to that later tree. |
| Subsequent source preservation | Accepted main `cd098e8e19f5e4a1d90112379bc8ca089d81ec93`, tree `d84af99ce5d5ddc8160daf3da8360247426697e5`, preserves all seven placement entries and every Transfer production decoder blob from `791c`. Its separate typed-evaluation, WAL-admission and synthetic-fixture deliveries have their own evidence. Additional package test methods are not retroactively included in the earlier 57-method run. |
| Applicable post-main verification | Automatic [Transfer run 39164536352 / job 117784641978](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39164536352/job/117784641978) actually checked out delivered `791c355812bfbbf8003941b59734118011d4734a`, tree `e85a7658a922704d93b76718c622edc5b2731e3c`. Its complete original log qualifies all **57 exact source-declared XCTest methods**, including all four placement methods, with zero failures/unexpected results/skips. The single complete test root ran from **2026-10-18 21:37:21.599 to 21:37:33.763**, with a 12.164-second root duration. The actual reference verifier passed the same **ten pins and 2,287 cases**, including all 98 placement dispositions. Xcode **16.4 / 16F6**, Apple Swift **6.1.2**, `jsonschema[format]` **4.26.0**, and the unsigned generic iOS Simulator SDK build are recorded. Every job step succeeded. |
| Original post-main log and scope | Complete original log: **129,182 bytes**, SHA-256 `86e0c01557f0ea37645b68d6680fbcac9483118bb23a3aef7d47659a37e1b135`. Original bytes were preserved and compared exactly with the retrieved job log; all seven test-source hashes and complete method starts/passes were qualified against `791c/e85a`. This is a separate actual post-main execution, not a relabeled receiving run. Fresh `cd098e8e` readback preserves the seven placement entries and every Transfer production decoder blob. It does not turn the older 57-method run into execution of subsequent test additions. |

The delegated Apple reviewer subsequently read the complete mapping, generator,
tests and actual original Transfer log and recorded an
[independent literal-criterion receiving assessment](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/35#issuecomment-6255099761).
That assessment accepts all three artifact criteria within the explicit v1-gap
branch and retained the applicable post-main check, which is now satisfied by
the actual execution and source-preservation readback above. The named prerequisite,
[#32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32#issuecomment-6249160321),
was already accepted and completed. Neither the selected macOS test host nor an
unsigned simulator SDK compilation establishes physical-device behavior, a
serving runtime, full UI journeys or released software.

The [final issue-specific receiving receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/35#issuecomment-6255505233)
subsequently qualified that same original post-main log and all preserved source
identities, reconciled all four implementation subtasks and all three artifact
criteria, and recorded the completed disposition. Fresh live readback confirms
Apple #35 is **closed / completed**, with all seven named checkboxes checked.
The earlier queued and open-state findings remain historical; this record carries
the actual completed receipt without a second issue-state change.

## Literal criterion disposition and handoff

| Criterion from live Apple #35 | Artifact, check and receiving disposition | Final disposition |
| --- | --- | --- |
| Client preserves canonical relationships and exposes unsupported representation gaps. | Accepted by the linked contract/client and issue-specific receiving reviews. The validated public boundary, mapping and actual 98-vector replay preserve original values and explicitly distinguish unresolved semantics from rejected additional fields. | Satisfied within the frozen v1 boundary; the applicable actual post-main Transfer result and fresh source preservation are qualified above. |
| Round-trip hybrid placement, component roles and memory pools; a v1 representation gap remains unsupported and routes to research Pick-Your-AI/pick-your-ai-research#40 instead of an undocumented field. | Accepted through the criterion's explicit v1-gap branch. Four catalog mode labels, mixed access paths, role-bound IDs and directed links round-trip. Existing per-device/host memory facts stay separate. Full physical pools/allocation, component deployment, binding and route-budget representations remain unsupported under CD-2/5/6/7/11; attempts to add fields fail with the documented typed errors. | Satisfied through the explicit conditional gap disposition. No new pool representation, contract adoption or executable runtime capability is claimed or required by that disposition. |
| The placement/relationship mapping and unsupported-tuple vectors is linked with criterion results, exact versions, limitations and receiving-review disposition. | Accepted by the linked issue-specific receiving assessment: this record and its immutable fixture/generator retain exact versions/hashes, actual positive/negative/recovery results, original failures, signed delivery and named limits. The [acceptance map](../../docs/acceptance/README.md) points here. | Satisfied by the linked record, exact original receiving/post-main evidence and source identities. The final issue-specific receipt reconciles this completed criterion. |

All three literal criteria have the recorded receiving assessment and their
applicable execution evidence; the issue-specific receipt records their completed
reconciliation. This does not add unrelated native, device, service or whole-epic
completion conditions to the accepted mapping.

The existing [Android #37](https://github.com/Pick-Your-AI/pick-your-ai-android/issues/37)
remains the counterpart coordination issue; this delivery changes no Android
implementation or its stricter executable-applicability criteria. Contract and
affected-client receiving review are delegated within the authorized project
work, with actual reviews linked to exact candidate commits. Research #40 retains
versioned adoption and migration authority; #41 retains evidence policy, #42 saved
semantics and #60 source-use rights. None of those shared issues closes because
this Apple mapping lands. Runtime compatibility/applicability, new API adoption,
physical-device behavior, signed application distribution and production operation
remain separate work packages with their own literal acceptance gates.
