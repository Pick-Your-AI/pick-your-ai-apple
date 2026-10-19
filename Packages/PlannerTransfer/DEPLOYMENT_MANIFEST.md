# Frozen deployment declarations and a local proposed-plan pair

This is independent source preparation for [Apple #96](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/96),
under the [bounded preparation claim](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/96#issuecomment-6264716278).
It implements private local value handling in PlannerTransfer. It does not deliver
mounted UI, public sharing, storage, a deployment executor or an approval service.

## Immutable input and declaration boundary

The schema already defines approvals and deployment status. Its bytes are copied
unchanged from Research `7acbefbf4e4e700231e88be272bc89e3a73dde15`; this client adds no
fields, enum values or new contract version. The [source manifest](Tools/deployment_manifest_source_manifest.json)
and [standalone reference entry](Tools/deployment_manifest_vectors.py) pin:

| Input | SHA-256 |
| --- | --- |
| DeploymentManifest schema | `86bc716c906aca1299d9129eec08abec44378c26b5a97317d6310afe84d6b374` |
| Existing common schema | `0342ce2f1114e7276fc7f6a08ff5b86e8727caadd83ae4f443de9a7e1431c43c` |
| Explicitly synthetic deployment example | `c05603388efc50a15274d1e6fa8e25dac3c205377a1989bfb5b3a3e64face8ab` |

The frozen [adoption limits](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/ADOPTION.md)
remain applicable. Schema identifiers resolve locally; no schema URL is fetched.
The synthetic fixture's approver and report IDs are examples, never actual evidence.

`DeploymentManifest.decode` applies the accepted JSONParser's 512 KiB, depth 48,
16,384-node, duplicate-key and interoperable numeric limits before checking the
complete frozen schema through the existing FrozenValidator. Unsupported versions
and malformed required references fail without creating placeholder values.

The immutable value preserves all five declared statuses: `proposed`, `approved`,
`rejected`, `deployed` and `rolled_back`. It also preserves approval order,
duplicates, Unicode strings, evidence references, rollout strategy, notes and
optional field absence. A pending row with an `approved_at`, an approved status
with pending rows, or a declared deployment reference is not repaired or certified.
The schema admits these declarations; validation does not establish their truth.

Four canonical-positive cases are deliberately outside the existing client subset:
an identifier with a terminal newline, two unsupported numeric revisions and an
IP-literal rollback URI. These are explicit client limitations, not changes to the
canonical schema. The reader uses the same accepted parser and URI/date behavior
as the existing artifact boundaries.

## Proposed-only binding and local outputs

```swift
let build = try BuildTransfer.snapshot(fromDraftJSON: retainedBuildJSON)
let declaration = try DeploymentManifest.decode(suppliedManifestJSON)
let plan = try ProposedDeploymentPlan(build: build, manifest: declaration)
let artifacts = try plan.encodedLocally()
// artifacts.buildJSON and artifacts.manifestJSON are separate local values.
```

The pair requires `status == "proposed"`, exact UTF-8 build identity, equal retained
build revision and exactly one selection with the manifest's target ID. That
selection must have kind `deployment_target` and be enabled. Every matching ID is
counted before kind/enabled filtering, so an extra disabled or wrong-kind record
cannot hide ambiguity. The common schema does not require a `sel_` prefix.

The helper never downgrades a supplied approved/deployed declaration, promotes a
proposal because all its rows say approved, or manufactures a report/approver ID.
Its errors carry no private input values. It binds the explicitly supplied pair;
the caller must still establish that the retained Build is the intended current
revision before any user action. It does not read an editor, database or service.

Build locks, monitoring selections, optional tiers, policy and private fields remain
in the original BuildSnapshot. They are not inserted into DeploymentManifest,
which has no lock or monitoring fields. The two outputs are existing frozen JSON
artifacts, not a new archive or envelope. Absent rollback URI or monitoring stays
absent; the helper cannot certify that a missing operational requirement is met.

All report IDs and approval rows remain reported declarations. Neither a matching
ID nor schema/compatibility success demonstrates quality, source rights, readiness
or approved execution. A synthetic embedding/index dimension mismatch can remain
in a proposed plan without becoming a compatibility pass. The caller's disclosed
gaps and selected/omitted tier inputs are retained; this helper does not evaluate
those inputs or execute tools, training or infrastructure.

Frozen v1 requires four evidence IDs and at least one approval row. An incomplete
planning draft without those real inputs cannot become a complete manifest by
adding placeholders. It must stay an incomplete local draft or receive the actual
inputs through its existing consumer boundary.

`encodedLocally()` computes both outputs before returning either. Both artifacts
must reopen under the same bounds with equal admitted values; normalization may
expand a valid input beyond the byte limit and fail. Inputs remain immutable and a
new valid pair can be retried. No filesystem writes or cross-file atomicity are
promised. JSON whitespace, escaping and number spelling may normalize; decoded
strings, numeric values, ordering of arrays and optional absence do not change.

These bytes may contain private owner references, notes, endpoints and approval
identities. They are **private local serialization**, not a public export API or
authorization to share. The separate existing [BuildTransfer](Sources/PlannerTransfer/BuildTransfer.swift)
projection and its receiving privacy review remain unchanged. Files/share-sheet
integration belongs to its existing owner and needs its own admitted projection.

## Reproduce and interpret validation

The [16-method XCTest source](Tests/PlannerTransferTests/DeploymentManifestTests.swift)
includes the complete 133-vector corpus: 45 canonical-positive, 41 client-positive,
88 canonical-negative and four documented client-subset cases. Method declarations
are not execution evidence. Tests additionally cover raw duplicate and escaped
keys, byte/depth/node/numeric limits, every declared status, missing references,
private Unicode values, late invalid rows, exact binding, every duplicate target
shape, omitted/disabled tiers, known synthetic incompatibility, no status promotion
and failed local serialization followed by a successful retry.

Run the standalone reference entry in the existing hash-locked environment:

```sh
python -B Packages/PlannerTransfer/Tools/deployment_manifest_vectors.py
python -O -B Packages/PlannerTransfer/Tools/deployment_manifest_vectors.py
python -B -m unittest discover -s Packages/PlannerTransfer/Tools -p test_deployment_manifest_vectors.py -v
swift test --package-path Packages/PlannerTransfer --filter DeploymentManifestTests
```

The default Python command verifies all three immutable pins, deterministic corpus
bytes and every declared canonical outcome using Draft202012Validator with the
required URI/date format checkers. All gates use explicit exceptions under both
Python modes. It reads bounded regular input through an opened descriptor.
`--write` is a developer-only regeneration option for this new fixture, after all
canonical outcomes pass; it does not export an application plan.

The [seven permanent filesystem-control methods](Tools/test_deployment_manifest_vectors.py)
use only owned temporary fixtures. They retain the real generator regressions for
final-symlink refusal and fdopen acquisition cleanup, plus hardlink preservation,
bounded reads, partial/short-write/fsync/replace failure cleanup and successful
retry, and real bad-pin/manifest/corpus CLI failures followed by restored success
under normal and optimized Python. Platform-specific FIFO or link prerequisites
are explicit subcase skips when unavailable. The FIFO read runs in an owned child
with a timeout so a blocking-open regression cannot hang the test runner. A Linux
result is not a macOS or Windows execution claim. No real approval or deployment
record is used.

This ten-file donor leaves the independently owned shared `verify_contract.py`,
`source-manifest.json`, FrozenValidator, README and workflows untouched. The new
standalone Python entry is **not automatically called by the existing shared
reference workflow**, and the new standalone Python regression command is also
not automatically invoked there. Native package test discovery does include the new Swift
methods and their bundled vectors. A later shared-runner append requires an
explicit reviewed current-source integration; no existing green reference run is
credited with executing this entry.

Local commands, their original failures/recovery and exact source identities belong
in the accompanying preparation/PR receipt. A Python reference pass or Swift syntax
parse is not a compiled XCTest result. Applicable native Transfer, SDK and other
configured receiving gates remain required; physical-device and mounted-user-flow
evidence are separate. No such native/device execution is asserted by this guide.

## Criterion and receiving record

| Literal #96 criterion | Prepared source and authored checks | Remaining receiving evidence |
| --- | --- | --- |
| Plan export does not assert approved/deployed status without evidence. | Proposed-only constructor, no status downgrade/promotion, immutable declared approvals; reader explicitly preserves rather than verifies status. | Actual native method results and Apple/tier consumer review of the intended visible behavior. |
| Export an unapproved deployment plan; preserve pending approvals, locks and rollback requirements and show no claim that infrastructure was deployed. | Separate local Build/Manifest outputs; exact locks and declared rollback/pending rows; optional absence, ambiguity, private data and failed-output retry checks. | Currentness/evidence intake, admitted public/Files projection if selected, mounted UI and operational requirement review. This local pair does not write or deploy. |
| The core T6 proposed-plan export tests is linked with criterion results, exact versions, limitations and receiving-review disposition. | Linked 16-method source, 133 pinned reference cases, frozen inputs and explicit limitations in this record. | Exact executed source/command receipts, independent review and current receiving/main qualification; do not mark a declared method executed. |

The actual named prerequisite is [#95](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/95)'s
quality-versus-compatibility guidance output. Its [current source receiver #363](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/363)
remains its own source/native/acceptance record. #96 explicitly permits preparation
and fixtures independently; this donor does not claim adoption past that gate or
whole-issue completion. Existing #198/#240 mounted UI, #350 dependency participants,
#359 Ruleset and #37 neutral-wire/migration work retain their owners and source.
