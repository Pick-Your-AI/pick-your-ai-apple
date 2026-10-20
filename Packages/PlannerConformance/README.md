# Shared wire conformance and Apple local migrations

The [current a3/986 continuation](#current-receiving-continuation--2026-10-20-a3986)
below records completed, failed and incomplete originals and the separate source
proposal. Earlier receiving sections retain their dated source and decisions.

The [2026-10-20 receiving evidence](#receiving-evidence--2026-10-20) below records the current prepared outputs and actual delegated decisions. Earlier preparation and pending-status accounts retain their original dates.

This is the named **language-neutral conformance bundle and Apple migration
results** for [Apple #37](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37).
`PlannerConformance` is a test-only package consuming existing `PlannerCore` and
`PlannerTransfer` boundaries. It defines no app product, production model,
validator, evaluator or service. The fixtures are synthetic.

This record distinguishes original Apple local preparation from the separately
accepted Android test consumer and the current archival recovery below. The
receiving composition includes the accepted named prerequisite outputs. Its
current Apple native execution, final receiving disposition and signed-main
delivery remain separate gates. No Apple #37 criterion is marked complete by
source recovery alone.

## Pinned inputs and exact consumer boundary

The [wire bundle](Tests/PlannerConformanceTests/Fixtures/cross-client-v1.json)
has version `apple-cross-client-1`, SHA-256
`8ae0d15ae236003d350d17066dfd1928cbe8a339095dac0299f4fefd4303d8cf`.
The separately executed `41c6772c` preparation used the preceding bundle
`8151da7e58e21f29acc5e1594950f1425bc2fb77eb46863a24df91ee39205cf4`;
the evidence-profile continuation below requires its own receiving qualification.
The original archive and previously executed consumer bundle remains
`499fd9a01780ac42fa9bf2ab8cf9e1195db27321fec36040451b553a8b9ea5f9`.
The current bundle changes only source-pin metadata for the accepted placement
adapter, its checked helper and the complete 41-case evidence source; all 223 complete case rows, including every
payload byte, and every other bundle field remain unchanged. Current execution
and the original consumer receipts retain their separate source identities.
Its [input lock](../../tools/conformance/cross-client-lock.json) pins every
consumed original and the canonical website runtime closure. The unchanged
frozen contract is `1.0.0`, Research revision
[`7acbefbf4e4e700231e88be272bc89e3a73dde15`](https://github.com/Pick-Your-AI/pick-your-ai-research/tree/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1),
with original manifest SHA-256
`ef6d5801eec10f3169e2bf84653e7026b33088e305a987991ec52faadcd7f554`.
The [adoption boundary](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/ADOPTION.md)
still governs versioning and executable policy.

| Consumer | Actual selected entrypoint | What its result means |
| --- | --- | --- |
| Swift build | `BuildTransfer.snapshot(fromDraftJSON:)` | Validated local immutable snapshot; this is distinct from public import/export and source-use permission. |
| Swift catalog | `CatalogItem.decode` | Bounded validated item with its complete supported value retained. |
| Swift selection | Existing `FrozenValidator.check` with `selection.schema.json` through test access | Existing conditional selection validation; no new public selection API is introduced. |
| Swift report | `EvaluationReport.decode` | Producer-supplied outcomes, severity, identities and evidence survive; no compatibility result is recomputed. |
| Python | Existing preparation runner's `schema_results`, using verified original schemas and exact `jsonschema[format]` 4.25.1 environment | Canonical schema expectation for the same concrete payload; no replacement domain evaluator. |
| Website | Unchanged `src/contracts/validation.ts` and generated validators at [`dc66a9e269917ab7241c7d08fd0e7f2a2f039872`](https://github.com/Pick-Your-AI/pickyour.ai/tree/dc66a9e269917ab7241c7d08fd0e7f2a2f039872/src/contracts), after `validatorsReady` | Actual existing contract validator on Node 24.19.0 with Ajv 8.20.0 and ajv-formats 3.0.1; browser journeys and services are separate. |
| Android test consumer | Existing `FrozenSchemaValidator` and strict typed JSON read/serialize/reopen, through the test-only `CrossClientFixtureAdapter` received by [Android #432](https://github.com/Pick-Your-AI/pick-your-ai-android/pull/432) | Actual repository Gradle fixture execution and exact named XML observations are qualified below. Installed-app behavior and production evaluator parity remain separate. |
| Another future unshipped consumer | The same JSON interface below | Its execution remains explicitly unverified until that consumer produces an actual qualified receipt. |

The bundle contains **223 identical payloads: 141 accepted and 82 rejected**.
Swift processes 85 builds, 61 catalog items, 33 selections and 44 reports.
The original Swift/Python/website runs and the separately qualified Android test
consumer agree on these expectations. This is a bounded
shared profile, not a claim of whole-schema, arbitrary-number or arbitrary-encoding
equivalence. The original complete Core/Transfer suites remain in their workflows,
including catalog's six and quality's eighteen documented client exclusions.

| Input group | Coverage retained in the bundle |
| --- | --- |
| Canonical examples | Original build/report bytes and all 29 catalog/selection kinds. |
| [Reviewed #35 placement output](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/e027fa8edaedb2ebfe11ede8ddd028e1e4c278b9/Packages/PlannerTransfer/PLACEMENT_RELATIONSHIPS.md) | All 98 original cases materialized: 30 preserved, 20 unresolved, 24 unsupported fields and 24 invalid contracts. |
| [#36 evidence output](../PlannerUI/EVIDENCE_RENDERING.md) | All 37 original payload strings, byte-identical: 28 accepted and nine rejected. |
| Explicit boundary additions | Required/unknown/null fields; unsupported wire versions; retained component revision strings; missing locks; incomplete drafts; decimal strings beyond binary64 precision; rejection of numeric or literal-unknown money. |

The input lock names `apple-cross-client-1/original-evidence-37` explicitly.
It first verifies the complete 41-case Core evidence file at SHA-256
`12e4ce069d9bdf3055d5eb1400a33b3643a2860403d111ac95dd92bd09a81b72`.
All source identities must equal the 37 selected IDs followed by the four named
excluded IDs, in their exact order. The selected rows and all other source
fields must reproduce the entire original 48,128-byte canonical evidence file
at `9db8c150e7666549cd4ddeacf57bcbd4a0277c193090f9d55a7f90e22154d7be`.
Missing, duplicate, reordered, renamed or additional rows, changed selected
payload bytes or expectations, and changed source metadata reject before the
placement adapter or canonical schema consumer is invoked.

The four additional #72 cases are `evidence/explanation/reported-action`,
`evidence/explanation/absent-action`, `evidence/explanation/empty-action` and
`evidence/explanation/whitespace-action`. They remain unchanged in the complete
41-case Core/UI resources and their accepted tests. They are explicitly outside
this original 223-case shared profile; this record does not claim cross-client
coverage of all 41 evidence cases. Relative to the preceding `8151da7e` bundle,
only `inputPins.evidence.sha256` changes. Restoring that one pin recovers the
preceding bundle byte-for-byte, preserving its original execution attribution.

The distinction between a structurally accepted and an unresolved placement case
is retained as `disposition`. Duplicate bindings, missing optional facts, unknown
evidence or opaque extensions do not become runtime fit, memory pooling, an
allocation, an independently supported grade or permission to execute. A supplied
report outcome of `pass` is retained without treating absent evidence as support.
The full supplied role labels, directed links, source locks and independent
context/device/host counts remain observable after Swift serialization/reopening.

## Language-neutral input and result interface

Each wire case has a unique `id`, one of the four `contract` names above, the
canonical `schema` filename, `payloadJSON`, its `payloadSHA256`, the expected
Boolean `valid`, a bounded reason and an optional placement `disposition`.
The receiver must hash and pass the **UTF-8 bytes of `payloadJSON` itself** to its
existing boundary. It must not validate the enclosing case object, substitute a
different example or convert decimal strings into numeric values. The generator
compares every case with the actual frozen Python schema consumer before writing
or accepting the bundle.

Every receiver reports one observation per ID with this shape:

```json
{
  "bundleVersion": "apple-cross-client-1",
  "id": "canonical/build",
  "accepted": true,
  "preserved": true
}
```

`accepted` is the observed decoder/validator result. For accepted inputs,
`preserved` must be true: Swift compares the full decoded value, serializes it,
reopens it, and checks identity/value equality with typed JSON values, keeping
Booleans distinct from numbers. The website compares the original
parsed value with its validator's returned value. For rejected inputs `preserved`
is JSON null; serialization failure must never be mislabeled as decoder rejection.
Report missing IDs, duplicate IDs, mismatches and unsupported consumer boundaries
explicitly. The same bytes and expected profile are consumed by the actual
Android fixture run below; that test receipt does not establish an installed
Android application or production evaluator.

The Swift test output prefixes these observations with `APPLE_WIRE_CASE`; the
website uses `WEB_WIRE_CASE` and emits one final `WEB_WIRE_RUN` with exact source,
runtime and fixture pins only after all cases agree. These log prefixes are
framing for evidence capture, not additional wire fields or production protocols.

## Accepted Android test consumer

[Android #432](https://github.com/Pick-Your-AI/pick-your-ai-android/pull/432)
received the existing neutral profile as a bounded fixture consumer. Its normal
signed main delivery is
[`033ace652059bd78079bf133e6cabccd9465ecb1`](https://github.com/Pick-Your-AI/pick-your-ai-android/commit/033ace652059bd78079bf133e6cabccd9465ecb1),
tree `c4db701e93365495d3d3b955a6b168013ad64e20`, sole accepted parent
`e8241ef4ea75071339e6a945e48fc6d433819ffa`. The
[accepted consumer record and lock](https://github.com/Pick-Your-AI/pick-your-ai-android/blob/033ace652059bd78079bf133e6cabccd9465ecb1/docs/CONFORMANCE_FIXTURES.md)
retain the original Apple `08e54247` preparation and its durable archive as their
producer identity. They do not relabel that archive as Apple main delivery.

Android's 43,929-byte gzip is lossless transport for the same 1,273,770-byte
neutral JSON. Its SHA-256 is
`c1e66aa954c20354ec607ceb8f90a90c599a8748ab10dcff17ce63fda8bf366c`;
bounded decompression reproduces the original `499fd9a0` hash above, all 223
payload strings and the same 141 accepted/82 rejected expectations. Android adds
no second neutral producer, new shared version or migration definition.

The actual repository Gradle receiving checkout was
`b0d2d3708bece4cc2667362ccd327b20ac166ad3`, tree
`c0143b9c92dbc28e312de7d40769a99a482d3f09`, ordered parents
`ced002ddb32ceaad2a2a2dcdf4fb438f2a1c0bc9` and signed source
`e7731a69b28fb19e8e34e24054317b7e51a727ba`. The
[independent original-receipt review](https://github.com/Pick-Your-AI/pick-your-ai-android/pull/432#pullrequestreview-5564990088)
qualifies all **225 named wire tests and 35 named private migration tests**:
223 wire observations and 34 Android-local observations, zero failures/skips or
duplicate cases. The original 65,948-byte qualified JSON has SHA-256
`5fafe550d216cfdc8ca6d117700db1b8e4d6e8bf3f4497774c82e9f10c96646a`.
The exact canonical qualifier independently reproduces those original bytes
from the original XML and preserves typed Boolean/null observation values.
All 24 receipt guards also pass in that actual receiving job. The
[later accepted-main preservation review](https://github.com/Pick-Your-AI/pick-your-ai-android/pull/432#pullrequestreview-5565145648)
keeps the authored fixture/qualifier bytes and complete tested core workflow
while carrying accepted source into the delivered `c4db701e` tree. These are
original `b0d2/c0143` results with reviewed later preservation, not new execution
at `033ace/c4db`.

The separate `android-local-migrations-1` bundle uses ten fixed historical inputs
and 34 scenarios over Android's private formats 1–5. Its 183,586 bytes have
SHA-256 `f480f236e7f93e737095c7f53c3fa30ab38df1e86bc41059305b0ca11591206b`.
Those private migration, interruption/retry, stale-revision and retained-history
observations are distinct from the six Apple SQLite descriptions and 20 Apple
observations below. They do not establish a shared wire-format upgrade or equal
storage version numbers across platforms.

This accepted Android fixture slice supplies an actual consumer of the published
interface. Android #49 remains partial, with its own named prerequisite and
receiving dispositions; no production evaluator, installed-app journey, service,
physical-device or whole-issue acceptance is inferred here. The original local
JVM and standalone Gradle preparation receipts remain separate from the actual
repository receiving execution above.

## Historical Apple storage and rollback

The separate language-neutral
[migration descriptions](../PlannerData/Tests/PlannerDataTests/Fixtures/migration-cases.json)
have version `apple-local-migrations-1`, SHA-256
`244e97154bb19b77b454280ba73fabe06a0f75f4fe353fdf5f265509e6100394`.
They describe Apple SQLite rows and exact original payload strings. They are not
Android local formats and do not adopt a shared wire successor.

| Historical fixture | Required observed behavior |
| --- | --- |
| `v1-empty-draft` | Upgrade an incomplete editable draft without inventing snapshot fields. |
| `v1-locked-history` | Preserve exact bytes, source locks, literal/null distinctions and both revisions through the two migration steps. |
| `v2-restored-history` | Retain all three revisions and their existing restoration provenance. |
| `v3-retired-identity` | Reopen current storage, preserve history and continue rejecting delayed use of the retired UUID. |
| `v1-canonical-snapshot` | Retain the exact original 14,681-byte frozen build through the local upgrade; its hash must equal the canonical input. |
| `v2-opaque-future-wire-draft` | Preserve opaque draft bytes containing a future wire label without claiming those bytes are a valid snapshot. |

All six descriptions reach or reopen local version 3. The existing migration
implementation remains unchanged. Four new test methods add **20 separately
identified observations**: six migration/reopen results, eight interrupted-step
rollback/retry results, three unsupported-storage-version retention/recovery
results and three history-restoration/stale-revision results.

Every pending migration step is interrupted through the existing SQLite fault
hook. The test requires the complete original database bytes and original
`user_version` to remain unchanged before a successful retry. Unsupported storage
versions `-1`, `4` and `99` produce the existing typed error and retain the unknown
database. Recovery reopens a **separate copy of a known-compatible original
backup**; it never relabels the unknown database or claims an installed binary
downgrade. Restoring an old draft revision appends a new revision, preserves all
original history and rejects a stale expected revision.

All 31 accepted draft-store methods, including future-history restoration
rejection, all five WAL/hot-journal cases, actual `SQLITE_FULL` recovery,
corrupt-record isolation and the
separate-process `_exit(73)` crash replay remain required. With the 35 pending-write
methods and four migration methods, the exact storage set is 70. Fixture fault injection is distinct
from actual process exit, physical power loss, protected-data/device behavior
and recovery of a deployed application or service.

## Reproduce and qualify

Use the repository's exact preparation Python environment and the verified
Research checkout described in the [preparation instructions](../../tools/conformance/README.md).
From the Apple repository:

```sh
python tools/conformance/cross_client.py --contract-root "$CONTRACT_ROOT" --check
python -m unittest discover -s tools/conformance/tests -v
swift test --package-path Packages/PlannerConformance -Xswiftc -warnings-as-errors
swift test --package-path Packages/PlannerData --scratch-path .build-storage -Xswiftc -warnings-as-errors
python3 tools/storage/crash_replay.py .build-storage/debug/DraftCrashProbe
```

Only `--write` intentionally regenerates the owned synthetic wire fixture. The
optional `--placement-root` is for read-only prerequisite preparation; its three
placement inputs must match the exact lock before code is imported. Ordinary
receiving CI consumes the delivered files in the same Apple checkout.

The generator loads the placement adapter and `contract_checks` helper only from
their individually verified temporary copies. An ambient module of that name
cannot substitute its implementation. The previous module entry is restored on
both successful and failed adapter imports. The accepted Transfer generators
and their optimized-Python checks remain unchanged.

For the actual website reference, use a read-only checkout at the pinned website
revision, Node 24.19.0 and its existing lock. Install its production dependencies
with `npm ci --ignore-scripts --omit=dev`, then run from Apple:

```sh
node tools/conformance/web_consumer.mjs /path/to/pinned-website-checkout
```

The actual preparation run retrieved six small runtime archives from that lock,
verified their full SHA-512 integrity before extracting them, and executed only
the pinned 11-file source/runtime closure. The reusable runner verifies every
original byte and copies that closure to a private temporary directory before
importing the unchanged TypeScript entrypoint. It awaits the actual generated
validators. No website source is modified or deployed.

`consumer_receipts.py` requires the actual retained command status, all exact
named XCTest starts/passes and matching nonempty summary, plus every expected
observation **inside its correct test method**. It rejects failure/skip/duplicate/
truncated sessions, wrong modules, missing/extra/moved observations, duplicate or
escaped-alias JSON properties, false results and integer substitutes for Booleans.
Native CI requires explicit `PlannerConformanceTests` or `PlannerDataTests`
module identity. Local Linux's shorter XCTest spelling is accepted only with
`--allow-bare-linux` and is labeled `bare-linux-compatible`; it cannot establish
an Apple module identity.

```sh
python3 tools/conformance/consumer_receipts.py wire --log /tmp/wire.log \
  --exit-code 0 --output /tmp/wire-receipt.json
python3 tools/conformance/consumer_receipts.py migration --log /tmp/storage.log \
  --exit-code 0 --output /tmp/storage-receipt.json
```

Supply the actual command status; a manually supplied zero or synthetic log is
not execution provenance. Output must be outside the repository with an existing
parent and must not replace the input log, a link or a directory. An accepted old
receipt is invalidated before qualification; complete success is published
atomically. The workflows also remove their scoped old receipt before starting
the real test command, so an early command failure cannot retain old success.

The existing [Transfer workflow](../../.github/workflows/swift-transfer.yml) adds
the four-method/223-vector macOS execution and exact receipt. The existing
[Storage workflow](../../.github/workflows/swift-storage.yml) requires all 70
methods and 20 observations on macOS and each of its selected iPhone/iPad
simulators, alongside its existing crash replays and SDK compile. The
[preparation workflow](../../.github/workflows/contract-preparation.yml) checks
the derived bytes and all adversarial guards. No additional job or runner is
introduced. A Swift macOS wire result is not relabeled as executing those 223
cases on another OS or device.

## Current archival recovery and accepted prerequisites

On 2026-10-19, the recovery restored the original reviewed `08e54247`,
`b79f9a53` and `b152fe7f` source trees from the three verified Git bundles at
[archive commit `b0c4e108`](https://github.com/Pick-Your-AI/pick-your-ai-apple/tree/b0c4e1084c37e64d4a1b07ec6191cbfffc51901a/preparation).
The final original commit remains
`37792e22b2fbe7997e05681f6d09c4053591fd1f`, with its original parents and
211 source files. All bundle hashes, original Git identities and the complete
1,273,770-byte wire fixture were verified before composition. The archival
branch and original contributions remain unchanged.

The first restored receiver started from signed accepted main
[`666033a9`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/666033a9f6621e3342b190e75725310fa71f8826).
Its accepted production files and existing tests remain intact. The workflow
composition retains the current hash-locked Python environment, conservative
native selection and exact accepted evidence-rendering checks. The recovered
wire generator also uses the accepted frozen-source copy helper, which rechecks
physical containment at copy time and verifies every copied byte before any
placement adapter or schema consumer runs. A same-byte outside symlink must
fail just as a changed frozen file does; both fixtures restore their original
inputs and require a successful retry.

The initial resolved receiving source passed all 63 Python conformance methods.
An additional outside-symlink regression then reproduced a real missing-copy-
containment failure in the archived generator. Its correction changes the copy
boundary and guard fixtures; it preserves every wire payload and expected
consumer outcome. The corrected five-method generator suite passes, including
both copy-boundary failures before consumer execution and successful retries.
These are distinct local Python checks, not a new Swift, website or Android
execution. The original preparation runs below retain their original sources,
failures and subsequent recovery results.

### Current receiving continuation

The current local continuation also preserves accepted main through
[`ee2b3adf`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/ee2b3adfc99869d71141425f31b38a0ebf3cf3bc).
Its regular-input helper is used for the recovered generator's separate
manifest reread as well as its verified source copy. A real FIFO substituted
after copying reproduced a blocking read in the earlier producer. The corrected
read rejects that input before the placement adapter or schema reference can
consume it. The unchanged regression checks the FIFO identity, restores the
manifest and requires a successful full-bundle retry. This correction preserves
all six wire input pins and every one of the 223 wire payloads.

The complete current Python suite executed local commit
`ccf280e323a8af195d825a221e1dd88b648fc31b`, tree
`33c44eb3bdeaab0899ebe93df03c28026f8cc851`, with ordered parents
`e02bf7b6ec871bcd2561da642d0ecbe1b8b3c217` and accepted `ee2b3adf`.
Its 279-file source map contains 19 exact corrected contribution entries and
260 exact accepted-main entries. Every source file and all 46 frozen input
files remained unchanged during execution. This paragraph was added after
that run; it does not assign execution to a later documentation commit.

| Actual local Python run on 2026-10-19 | Observed result | Original log SHA-256 |
| --- | --- | --- |
| Corrected first receiver, tree `4a295ffd` | All 64 methods passed; 86.630 seconds. | `abe1db64a5edcce2f22541272edf06518ac37edd33243fb5c96d44c50c66f19f` |
| New manifest/FIFO regression, tree `33155fb7`, unchanged producer | The one method failed on the actual blocked reread; 6.731 seconds. | `9e79ed5e3ee0fd41981d542acc45fc0c257062e2e4be452fc147d00ec8faa691` |
| Corrected manifest reader, tree `95dad5a0`, identical regression | All six cross-client methods passed; 20.464 seconds. | `431abffd95291d019d8dea3c31168eb8861e6519de0158d38678e6288e01cf3c` |
| Complete current suite, commit `ccf280e3` / tree `33c44eb3` | All 76 declared methods executed exactly once and passed; zero failures, errors or skips; 98.824 seconds at 11:32:14.110905–11:33:53.228492 UTC. | `e69b9196fe352d3a58acba90045407411381b9a51537d93da82ace7f98ee6f01` |

The last command used the accepted pinned Python environment and frozen
Research input tree, from the repository root:

```sh
python -B -m unittest discover -s tools/conformance/tests -v
```

Its original log is 13,843 bytes; the qualified
76-method/source-preservation receipt is 9,589 bytes with SHA-256
`30076ae4eb9bd2f3dc73f8a0eb0d6b008c91f39fd0d37fb5f2d9e7bc4ec9bab7`.
These Python results retain their own source identities and do not establish
new Swift, simulator, website or Android execution, public source delivery or
whole-issue acceptance. The archived `37792e22` ancestry remains intact locally
and in the verified bundles; the public `b0c4e108` archive is its storage anchor.

At the earlier `ccf280e3` receiving source, the required native inventory was four
wire methods with 223 observations and 35 storage methods with 20 migration
observations on each configured platform. Actual receiving execution and source-bound review remain
required before any criterion is reconciled. The separately owned opt-in
[CD11 consumer proposal #346](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/346)
retains its own source and receiving lane; this recovery does not adopt a new
contract version or duplicate that implementation.

### Accepted placement-helper integration

The first actual receiving [Contract preparation run39275765462](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39275765462),
job `118139537620`, checked out signed `32290d7f`, tree `490cf8b5`, and stopped
with `Pinned cross-client input differs: placementAdapter`. Accepted
[#364](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/364) replaces the
placement adapter's optimization-sensitive assertions with a separate checked
helper. The original 33,502-byte failed log has SHA-256
`1b64c886d245d26efaf319c4e068091a44f23bb9ea22c1b162eaa30859d9dece`.
Its preceding reference/pricebook/raw-wire/evidence stages passed; later harness
and artifact steps were skipped. None of that failure is relabeled as recovery.

The correction pins both accepted files and loads only their verified copies,
with the module-state restoration described above. A hash-only update reproduced
an ambient-helper binding failure before the hostile helper was invoked. The
unchanged regression now rejects that substitution, verifies the accepted
helper's unknown-operation guard and retains all 223 expected case results.
Two other new methods cover helper-byte drift before any adapter/reference
consumption with a successful retry, and restoration after an adapter import
failure. All six previous cross-client methods remain unchanged.

| Actual local correction check on 2026-10-19 | Observed result | Original log SHA-256 |
| --- | --- | --- |
| Tree `861f477f`, original producer with current input pins and new regression | The one new method failed because the adapter bound the ambient helper. | `ed4e6137e4f18c37acfa5809b0dd634d198a20d3f4273845fcfc415498e4ecf6` |
| Corrected tree `d532cafb`, ordinary Python | All nine cross-client methods passed in 33.743 seconds. | `9ef3e0512f2a4eb38fb7965ebbfbcc7dd9a92030de59038d989d2f3170d610bb` |
| Same tree `d532cafb`, optimized Python | All nine methods passed in 24.014 seconds. | `0ad19d5210469e499e657fb26ecee9c133303e5784b92976b37a7c4843407521` |
| Tree `5ee6d575`, complete preparation suite | All 83 declared methods passed in 135.580 seconds at 15:29:56.257278–15:32:12.278200 UTC; every one of its 299 source files remained unchanged. | `ed3b798fec4caa989fb657ec26f3bad6b5dd060fe2de1b17b3291da1eb5e306d` |

Tree `5ee6d575` differs from the nine-method tree only in this package's README;
this subsequent results paragraph and the current rendering-count correction
were written after those runs. The regenerated bundle differs from original
blob `69718936` only in `inputPins`: the accepted adapter hash and the new checked
helper entry. Replacing that metadata with the original metadata reproduces
every original fixture byte. Its new blob is `1566506e`, with the current full
SHA-256 listed above. Swift/native and affected-client receiving qualification
must retain the new bundle identity; the old consumer runs still describe the
original artifact even though every tested payload and expectation is unchanged.

## Actual preparation evidence and remaining receiving gates

These runs used the recovered local environment on 2026-10-18. They are fresh
preparation runs, not relabeled receipts from an earlier unavailable workspace.
The Swift wire test source blob is
`8a53fc608512d87307c59702dfae4908240fd472`; the Data fixture test source blob is
`45d695ae1d029589749af617f0c0075931676452`. Both consume unchanged production
decoder/storage code. The explicit local receipt option was used for Linux.

These historical executions belong to the reviewed preparation preserved by the
[recoverable archive](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/78cb2675356e7d00167b645cc7c993d2425fd2fa/preparation/apple-37-reviewed-08e/README.md).
The archive restores exact source tree `08e54247b998d005ed831bfaeabad7731f3e7a8a`;
its publication is separate from current-main, native and implementation acceptance.

| Actual execution | Observed result | Retained log identity |
| --- | --- | --- |
| Swift 6.1.2, Linux wire package | Four unique XCTest methods passed; 223 case observations; all 141 accepted values preserved; zero failures/skips. | 32,383 bytes; SHA-256 `e1678baf9da24e34e64c64d52601cf122fa8f2c491533e6f753e57aa6d81f3ec`. |
| Node 24.19.0, actual pinned website validator | 223 observations, 141 accepted/82 rejected, preserved accepted values; successful command and complete final source/runtime receipt. | 31,305 bytes; SHA-256 `d17fbc2b3ad065c6893124c02fbef3aca9ab1a991fb84681899e1fbe48c5be80`. |
| Python 3.12, exact preparation dependencies | All 223 expectations match the verified original schemas; four generator adversarial methods pass. | Generator tests: 854 bytes; SHA-256 `6521cf19b175a08601afcf25a8dc3797db19a561ac81f1b1147e76337fc858e8`. |
| Swift 6.1.2, Linux Data package | All 25 original and four new methods pass; 20 exact migration observations; zero failures/skips. | 13,675 bytes; SHA-256 `94975b28cc1205e589bf19e151d9f1739cc0691f937cb4e1cb8bbdabaa72d0d9`. |
| Python standard-library receipt guards | Ten adversarial methods pass, including module identity, stale receipt and failure/recovery checks. | 1,979 bytes; SHA-256 `c246d53a074f687ab172cd5869a41d0de18f4758785a079599c300dc4454ab66`. |
| Complete Python conformance harness | All 44 methods pass, including the 30 retained guards and the 14 new generator/consumer methods; 23.643 seconds. | 7,758 bytes; SHA-256 `d7cc375602155bdb7d8f50e524f10167542af42cb9c22dae9eb7b62eaad3b2a5`. |
| Existing separate-process crash replay, rebuilt Swift 6.1.2 Linux probe | Actual abrupt exits after history write, before commit and during migration preserve the durable revision; command exits successfully. | 101 bytes; SHA-256 `0a09d012cf2c06fc9df737ca3396d2249a7e731999fe37f3bd94f0609d7a7d23`. |
| Independent Data fixture review and Swift 6.1.2 Linux replay | The Android receiving reviewer read all three exact fixture/package/test blobs and unchanged production migration/CAS code, then independently built and passed all four new methods and 20 observations; 1.425 seconds, zero failures/skips. | 8,072 bytes; SHA-256 `6f37b749c1c161a46fa5a534ff4d25b34ccff4dcb2b30bea81156bc68800e12d`. |

An initial proposed positive money value with 18 fractional digits was rejected
by the actual frozen schema. It was corrected to the explicit 12-digit limit;
no schema or decoder requirement was weakened. The first wire build attempt
omitted the recovered compiler's library path, and the next identified two
throwing Boolean-expression compile errors in the new test helper. Those attempts
are retained separately from the successful execution above. The corrected
helper also keeps decoder acceptance distinct from later serialization failure.

### Historical accepted restoration correction

Signed main [9c744450](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/9c744450d689690f66ab6a28aa146a1318917464)
received the independently reviewed [#298 restoration correction](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/298).
The `04d44920` preparation preserved its exact production guard and complete new
`DraftStoreTests.testRestoreRejectsFutureHistoryWithoutChangingReadableDrafts`
method. Its strict receipt required all 26 then-accepted storage methods plus the
same four migration methods and 20 observations. An older 29-case receipt, a
padded total, a wrong test class or a skipped restoration case cannot qualify.
The original 25-plus-four execution above remains historical; it does not execute
the new 30-method union. That union was separately executed from exact
source tree `04d4492059720b2854ee78053a5708ffe20cc5e0` on Swift 6.1.2/Linux,
with warnings treated as errors. All 30 unique methods passed with zero failures
or skips in 1.986 seconds of test time (17.860 seconds including the fresh build).
The strict local receipt qualified all 30 method identities and all 20 migration
observations. The 13,955-byte original log has SHA-256
`1bd55aa33c5b262b000faf77fe2c3a055bdf4f6f0f37cabe19eb47e7530a81cc`.
All 11 receipt/adversarial methods also passed in 0.400 seconds; their 2,170-byte
log has SHA-256 `c5ae65f97dfa932939bd86b75024d13230b04f16220f4cec65e5debb766c2a73`.
The existing crash replay was run again against that newly built probe and passed
all three abrupt-exit positions in 0.210 seconds. Its new 101-byte log has the same
deterministic SHA-256 `0a09d012cf2c06fc9df737ca3396d2249a7e731999fe37f3bd94f0609d7a7d23`;
the command and execution times distinguish this run from the earlier receipt.

An initial build of this exact source terminated with compiler signal 4 before
any XCTest method ran. Its 6,353-byte failed log is retained with SHA-256
`a6be51b1635336615098595ddac2f9842cadebb38fe38a8aae85c8ddab2bb9b9`.
The successful retry used the same installed compiler, flags and source with
fresh owned caches in the ordinary execution environment. No source requirement
was weakened. These local executions do not establish the separately required
current receiving macOS/iPhone/iPad results.
Any later accepted storage change must receive the same exact-method review;
another open source branch is not an additional prerequisite by itself.

### Earlier accepted WAL and journal carry

That preparation received signed main
[`cd098e8e`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/cd098e8e19f5e4a1d90112379bc8ca089d81ec93),
including the accepted [#306 storage correction](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/306)
in [`c2305005`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/c23050050c9ce46f35aee73e2f80b7b638cba159).
Its complete production guard and five additional WAL/hot-journal methods remain
unchanged. That strict receipt required all **31 accepted storage methods plus
four migration methods**, with the same 20 migration observations. The bounded
guard tests compare the required set with all source-declared `DraftStoreTests`
methods and reject a missing, skipped or wrongly classified WAL/journal method,
a padded total and the older complete 30-method receipt. They are synthetic
receipt checks, not Swift execution.

The actual 30-method execution at `04d44920` above remains historical. That
source composition did not claim a new 35-method Swift or native execution;
the current larger required set is recorded below.
The accepted main's separate typed-report adapter and synthetic-admission tests
are preserved, without relabeling earlier wire or native receipts as executing
those later source changes.

The exact reviewed local storage-inventory composition is tree
`c0c92cc98fa6537ff0b28b824f746270bcbf4e6d`. Its original regression, capacity
failure and focused recovery retain separate execution identities:

| Actual check | Result and scope | Original log identity |
| --- | --- | --- |
| Initial inventory regression before the five required names were added | One method failed on exactly the five accepted WAL/journal identities omitted from the required set. The correction adds those required names without changing existing receipt parsing or observations. | 1,378 bytes; SHA-256 `eb662a02672a2c6b8531f6e17b7dba8f6e114b10e0b501614810cbd325693d3d`. |
| Full corrected conformance harness at `c0c92cc9` | 46 methods: 45 passed and the existing CLI source-copy/recovery method failed with actual `ENOSPC` while copying `postgres_reference.sql`. All 12 receipt guards passed in this run. This is a retained failed full run. | 9,044 bytes; SHA-256 `ae1c856a8a7637c1e56ea6d77a6f0d6f20e1674af2aa3aad4a280cf4da65af01`. |
| Independent receiving reviewer, same 12 receipt guards | All 12 methods passed in 0.449 seconds; source and exact 31-plus-four method inventory were independently checked. No Swift or native execution. | 2,367 bytes; SHA-256 `7c3a78eb02628e31e43d2036ce30bbb4b7177524fa0fb6682893d96a5c960787`. |
| Focused CLI recovery retry at unchanged `c0c92cc9` | After an actual 4 MiB temporary write/fsync capacity probe succeeded and its file was removed, only the previously failing method was rerun. It passed in 9.565 seconds, at 2026-10-18 22:16:10.930554–22:16:20.876110 UTC. The 46-method run was not repeated. | 252 bytes; SHA-256 `5cac832a04747975c7b540e66b687fcbb247dee9a56e59505d25f073963c6a45`. |

Both independent source reviews preserve all accepted production files, the
four migration methods and every original wire byte. The receipt-only update
that records these outcomes adds no Swift, native, browser or JVM execution.

### Accepted pending-write composition

Signed main
[`294a152d96a8ee6e31e975f4303fc58e17842f40`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/294a152d96a8ee6e31e975f4303fc58e17842f40)
received [#382's bounded local pending-write queue](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/382).
The receiving composition preserves that implementation, its separate crash
probe, all 35 queue tests and the original draft implementation. It retains this
package's four migration methods and their bundled resources.

The strict migration receipt now requires the complete current session:

| Exact source class | Required methods |
| --- | ---: |
| `DraftStoreTests` | 31 |
| `PendingBuildWriteStoreTests` | 35 |
| `MigrationFixtureTests` | 4 |
| Total | 70 |

All 20 migration observations remain mandatory inside their exact owning methods.
Module identity, sequential framing, strict JSON field/type comparisons,
duplicate/skip/failure rejection and input fixture pins are unchanged. The wire
receipt still requires its four methods and 223 observations; no wire payload,
migration description or source input pin changes in this composition.

The Storage workflow preserves both independent crash replays and all existing
native commands. Its simulator aggregate is 70 rather than the accepted queue
source's 66, while the named queue guards and 31/35 class footers remain.
The package manifest keeps both crash executables and the migration resources.
These are source requirements; they do not establish that a native run executed.

The bounded local Python 3.12.14 receipt checks ran on 2026-10-19:

| Actual local check | Result and exact source | Original log |
| --- | --- | --- |
| Old-cohort regression before the required-set correction | One synthetic method fails specifically `ValueError not raised`: the unchanged earlier checker accepts all 20 observations with only the previous 35-method cohort. Frozen tree `5ede62c5f84f37eca3ef499e8b0ea9112ac55653`. | 1,051 bytes; SHA-256 `ba8139b885af3c094c17a5c87e33de9dd785788dba79b5e9c9415200ae7c41fa`. |
| Corrected ordinary receipt guards | All 14 methods pass, including all 12 prior guards and the two new pending-write attendance regressions. Frozen tree `da101b15e5e31aefcd0f5ccb4a54fe65680109ac`; 0.635 seconds of unittest time. | 2,723 bytes; SHA-256 `6391d4028421c41456b3981f177a98d0a88da786d571a020e659191bfc69c9e1`. |
| Same corrected guards under optimized Python | All 14 methods pass at the same exact source; 0.647 seconds of unittest time. | 2,723 bytes; SHA-256 `5b2d5649fd8b36e9fbfbeb5e723b9741c1e2434ca435a0ebd6107ab55ae1deeb`. |

Both new regression bodies are identical in the before/after source snapshots.
The complete old 35-method receipt is rejected even with all 20 migration
observations. For every new queue method, omission with either an unchanged or
corrected total, an unrelated class, skipping and failure are rejected. The full
70-method synthetic session succeeds. Every captured source file is unchanged
during each local run. The later documentation-only amendment does not change
those executed checker, test, Swift, fixture or workflow bytes.

These are synthetic log-validation checks, not 70-method Swift execution,
SQLite interruption outcomes or native migration observations. The original
Transfer framing failure and simulator launch failure retain their actual
earlier source attribution. Current configured native and SDK qualification,
the two disclosed receiving decisions and signed-main #37 acceptance remain
pending.

| Exact live #37 criterion | Concrete artifact/result | Receiving disposition and remaining gap |
| --- | --- | --- |
| All clients agree on pinned cross-platform fixtures and migration behavior. | The 223-case profile has matching actual Swift/Python/website and Android test-consumer outcomes. Apple and Android private migration observations retain their separately versioned meanings and failure/recovery scopes. | Complete current Apple native/prerequisite integration and final contract/affected-client receiving disposition. An additional unshipped consumer remains unverified until it executes the published interface. |
| Run identical version-pinned vectors through Swift and available references; a future unshipped client uses the published harness interface and remains explicitly unverified. | The original Swift/Python/website runs plus the separately qualified Android repository test execution above, with exact source/runtime/input pins and typed observations. | Current configured Apple native receipts and independently reviewed signed receiving composition remain pending. No browser journey, installed Android app, service or physical-device result is inferred. |
| The language-neutral conformance bundle and Apple migration results is linked with criterion results, exact versions, limitations and receiving-review disposition. | This record links both bundles, all consumer entrypoints, commands, actual preparation evidence, failure/recovery behavior and remaining limits. | Final PR/receiving reviews, exact signed-main identity and post-delivery criterion reconciliation remain pending. |

The three named prerequisite outputs retain their actual boundaries: [#33's
completed draft/snapshot transition](../../docs/acceptance/issue-33-draft-snapshot-boundary.md),
[#35's completed placement disposition](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/35#issuecomment-6255505233)
with its signed `791c/e85a` delivery and original post-main Transfer evidence,
and [#36's accepted decoder/rendered evidence output](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/36#issuecomment-6250594302)
at signed `939e291a`, received by [#335](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/335).
The original #277 `c21ad8ad` macOS rendering result remains
[three passes and one scroll failure](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/277#issuecomment-6255648533);
it is not relabeled as the later corrected rendering execution. Accepted main
now contains all three named outputs. Final #37 still requires its own current
native composition and contract/client receiving disposition. No unrelated
upstream device, service, store or full-epic closure is invented as a prerequisite.

Research [#40](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/40),
[#41](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/41) and
[#42](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/42) retain contract,
evidence and saved-build semantic authority. Actual shared-service integration,
browser journeys, installed mobile behavior, physical-device and release
qualification keep their separate issue gates.
No frozen source, wire schema, production model or repository ownership is changed.

## Receiving evidence — 2026-10-20

This dated section records the current received evidence for
[Apple #37](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37).
The earlier preparation, failure and recovery accounts above retain their
original dates and source identities. Their then-pending statements do not
replace the current observations below. This section does not mark the issue
complete or claim a main delivery that has not happened.

### Exact source and observed preparation

The contribution is
[`66aef338b6a70909ee6663b5da98023bb25e6f36`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/66aef338b6a70909ee6663b5da98023bb25e6f36),
tree `43bc23b9fc4acd081e70a5ad1d442f336a2ac03c`, with ordered parents
`74d8387faa4d0354f6a5a6ff4afd97393d21f0c7` and
`2a800687deb0e2c5356b226d309e36cc14f7b087`. Its
[guarded adoption](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/383#issuecomment-6281264343)
preserves both contributions and the existing implementation and receiving
roles. The contributor commit is unsigned. The
[public source review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/383#pullrequestreview-5580563868)
covers its two README resolutions and the unchanged remainder of that merge.

The completed current Apple observations in this section belong to the actual valid-signed
preparation
[`41c6772c86f227b6f487f89af8e4448655b0ecad`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/41c6772c86f227b6f487f89af8e4448655b0ecad),
with the same `43bc23b9` tree and ordered parents
`[2a800687deb0e2c5356b226d309e36cc14f7b087, 66aef338b6a70909ee6663b5da98023bb25e6f36]`.
Each linked current Apple job checked out that preparation. A later documentation
commit carrying this record does not become the execution identity.

Accepted main subsequently reached
[`7f16020b21d890c9a391c8d4936e67ab33c4760e`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/7f16020b21d890c9a391c8d4936e67ab33c4760e).
The reviewed, conflict-free source composition with `66aef338` is tree
`6b8de7aecd18d7459454358ebc3847f89a3c63f7`: it retains all 341 contribution-tree
entries and adds the four accepted #416 entries. This is a source preservation
finding. The `41c6772c` results are not assigned to that larger tree or to an
unperformed main push.

### Current wire, reference and migration observations

The selected wire input remains `apple-cross-client-1`, frozen contract `1.0.0`,
canonical Research
[`7acbefbf4e4e700231e88be272bc89e3a73dde15`](https://github.com/Pick-Your-AI/pick-your-ai-research/tree/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1).
All 43 manifest-listed canonical inputs retain their original bytes. The current
wire fixture is blob `1566506e4bbf22508be6f089bde9670d112a2feb`, SHA-256
`8151da7e58e21f29acc5e1594950f1425bc2fb77eb46863a24df91ee39205cf4`.
Its 223 distinct case IDs have 141 accepted/preserved and 82
rejected/preservation-null expectations. There are 220 distinct payload digests;
three intentionally repeated payload pairs have different case IDs. Exact
case attendance and complete values, rather than a unique-payload total, define
this profile.

The seven callable input pins, the complete current Swift wire and migration
methods, and the original artifact contents were checked against immutable
source. Original logs, their artifact copies and generated typed receipts agree.

| Actual current output | Observed result at `41c6772c` | Public original evidence |
| --- | --- | --- |
| Swift wire consumer and existing Transfer suite | All 203 Transfer methods and all four exact wire methods pass. Every one of the 223 complete typed observations occurs inside its required method: 141 accepted with preserved values and 82 rejected with null preservation. The strict qualifier succeeds; the generic unsigned iOS Simulator compile also succeeds. | [Transfer job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066774/job/118404849482), [two-member wire artifact](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066774/artifacts/12239120342) |
| Canonical Python and producer preparation | Both 21-method acceptance cohorts and all 88 conformance methods pass. All 137 schema payload results, six typed domain checks and three detected semantic mutants agree with the pinned inputs. The actual current canonical producer check verifies all 223 wire cases. | [Contract job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066744/job/118404703776), [preparation report](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066744/artifacts/12234596867) |
| Apple local migration on macOS | All 70 exact Storage methods and all 20 typed, method-scoped migration observations pass. | [Storage job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066786/job/118404966211), [three-platform Storage artifact](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066786/artifacts/12238403161) |
| Apple local migration on iPhone Simulator | The same 70-method set and all 20 observations pass on the selected iPhone simulator. | Same Storage job and artifact, with a separate platform log and receipt |
| Apple local migration on iPad Simulator | The same 70-method set and all 20 observations pass on the selected iPad simulator. | Same Storage job and artifact, with a separate platform log and receipt |
| Actual crash and recovery checks | Ten original draft-driver guards and eleven pending-write-driver guards pass. The compiled probes execute all three draft/future-migration exits and six pending-write cuts; recovery preserves the tested durable state. | Same Storage job and artifact; driver and native outcomes remain distinct |

The exact Storage cohort is 31 `DraftStoreTests`, 35
`PendingBuildWriteStoreTests` and four `MigrationFixtureTests`: 210 named method
executions across the three platforms. Each platform's 20 migration observations
contain six migration/reopen results, eight rollback/retry boundaries, three
unsupported-version retention/compatible-backup recoveries and three history
restorations. The six fixture descriptions still use
`apple-local-migrations-1`, SHA-256
`244e97154bb19b77b454280ba73fabe06a0f75f4fe353fdf5f265509e6100394`.
The current Storage run used Xcode 16.4 build 16F6, Swift 6.1.2 and the selected
iOS 18.5 simulator runtime. Its macOS, iPhone and iPad receipts are distinct
executions, not a multiplication of one platform's output.

The current strict log framing remains required. Earlier broken framing is not
accepted by relaxing method identity, ownership, JSON types or whole-session
attendance. The synchronous observation emitters and complete 70-method receipt
now have actual successful current outputs. Earlier failed full runs and their
separately identified corrections remain in the history above and in #383.

The canonical reference subprocess reports success, but its individual method
output is captured by its parent and is not present in the original job stream.
This record therefore retains aggregate reference success and the exposed typed
report; it does not invent a separate named child-method attendance list.

### Available references retain their actual execution identities

The original reference bundle is blob
`69718936a83b83e91aca7a492e48720fd2fe6cce`, SHA-256
`499fd9a01780ac42fa9bf2ab8cf9e1195db27321fec36040451b553a8b9ea5f9`.
Every complete case row, `payloadJSON` byte sequence, expected Boolean/null
value, reason and disposition equals the current `1566506e` bundle. Every other
non-`inputPins` field is also exact. Replacing only the accepted placement-adapter
and helper metadata reproduces the complete original bytes in both directions.
This comparison supports reuse of the same observed vectors; it does not claim
that an old consumer executed the later metadata file.

| Available reference | Actual retained result and boundary | Receiving evidence |
| --- | --- | --- |
| Android repository test consumer | The original signed `3b5a8eaecb4c618c4a2c926b64e9a7312af4f0bb` preparation executes 260 distinct tests: 223 wire observations, 34 Android-private migration observations and three guards. All 24 receipt controls pass. The recovered original XMLs reproduce the entire original 65,948-byte qualified JSON. The ZIP, log, source, JAR, inventory and packaged schemas were recovered and compared; no consumer was rerun. | [Actual Android Core job](https://github.com/Pick-Your-AI/pick-your-ai-android/actions/runs/39282506990/job/118159391651), [original artifact](https://github.com/Pick-Your-AI/pick-your-ai-android/actions/runs/39282506990/artifacts/12201343431), and [accepted consumer source record](https://github.com/Pick-Your-AI/pick-your-ai-android/pull/432#pullrequestreview-5564990088) |
| Website contract validator | The unchanged `dc66a9e269917ab7241c7d08fd0e7f2a2f039872` validator and 4,851-byte harness use the same eleven closure pins, Node 24.19.0, Ajv 8.20.0 and ajv-formats 3.0.1. The publicly retained original review records 223 observed cases, 141 accepted/deeply preserved and 82 rejected/null. The old raw console was not reacquired after workspace loss; this is attributed original evidence with exact current source/input equivalence, not a new execution. | [Original observation record](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37#issuecomment-6273342904), [independent original review](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37#issuecomment-6273752891), and [current website-reference receiving decision](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37#issuecomment-6283186508) |
| Future unshipped consumer | Explicitly unverified until it executes the published input/result interface and produces its own qualified observations. | No execution is inferred from a source port or another client's result. |

Apple-private storage versions 1–3 and Android-private formats 1–5 keep their
own definitions and failure/recovery observations. They are not a common on-disk
migration protocol. The shared result is agreement on this pinned structural
admission and typed-preservation profile, together with the explicitly versioned
private migration boundaries.

### Literal criteria and receiving roles

The contract-governance and affected-client reviewers have each made an actual
**ACCEPT WITH CONSTRAINTS** decision for source `66aef338`, tree `43bc23b9` and
the current `41c6772c` evidence. Both reviewed version 2 of the complete 2026-10-20 receiving section
and its index amendment, including all three literal criteria and four tasks. The affected-client delegate independently joined all 223 current Swift,
canonical and recovered Android rows and all three 70-method/20-observation
Storage receipts. The website-reference portion has the separately linked
acceptance above. These are disclosed in-session project-delegate judgments,
not named-person approvals, separate-account formal votes or substitutes for
repository rules. Their accepted content still requires incorporation,
publication and actual delivery reconciliation; it does not approve unseen
changes or assign `41c6772c` outputs to a later source.

| Literal #37 criterion | Current receiving disposition | Remaining recording or delivery work |
| --- | --- | --- |
| All clients agree on pinned cross-platform fixtures and migration behavior. | Contract governance and the affected-client delegate accept the concrete pinned profile with constraints. Current Swift/Python, the actual historical Android consumer and the attributed website original agree on the same complete 223 rows. Current Apple migrations have all 20 observations on each of three platforms; Android-private migrations remain separately versioned. | Preserve the two actual joint dispositions and the stated client/version limits through the subsequent source and delivery checks. |
| Run identical version-pinned vectors through Swift and available references; a future unshipped client uses the published harness interface and remains explicitly unverified. | Both receiving roles accept current Swift and the available-reference evidence. Full input equivalence supports reuse of the actual historical Android/website results; their dates and original bundle identities remain literal. | Preserve the explicit unverified status of any additional unshipped consumer. Complete the selected configured delivery gates. |
| The language-neutral conformance bundle and Apple migration results is linked with criterion results, exact versions, limitations and receiving-review disposition. | This amendment links the two versioned bundles, current original jobs/artifacts, concrete criterion outcomes and the actual receiving roles. Both receiving roles accepted the evidence package and version 2 record content with constraints. This continuation preserves those decisions and separately records the later failure status and source correction. | Publish the reviewed amendment with both actual decisions, link it from #37, then reconcile the configured gates, actual signed delivery and post-main results. No unseen amendment or future run is approved. |

The four implementation tasks are mapped to concrete outputs: the shared
223-row bundle and existing Python/web/Android interfaces; the historical-import
and unsupported-version cases; the actual migration, rollback and crash outputs;
and this versioned record of changed test interfaces, evidence, decisions and
remaining limits. No production decoder schema, service, frozen contract,
repository ownership or #346 implementation lane changes in this record.

### Other configured results and remaining delivery gates

The current preparation also has completed public Core and Catalog jobs and the
macOS renderer. Core passes all 151 methods in each configured debug, release,
iPhone, iPad and mutation-baseline cohort, both six-method Core rendering cohorts,
and the intended mutation/negative controls. Catalog passes all 92 methods and
its unsigned generic Simulator compile. The macOS evidence renderer passes six
exact methods and all 64 source-defined scenario checks, with five retained
screenshot attachments. Its result bundle records nine build warnings; this is
not a warning-free or visual pixel-equivalence claim.

Public evidence: [Core](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066710/job/118404829182),
[Catalog](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066735/job/118404898456),
and [macOS renderer](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066728/job/118404774780).
All eight portable jobs are complete: six conservative scope jobs (including
the SDK job's additional portable controls), dependency review and Contract
preparation remain in their actual workflow groups. Their 431 literal passing observations cover 230
distinct method identities; repeated scope cohorts are not counted as distinct
methods. Every scope decision selected native work on the real 19-path change.

At the 04:44 UTC checkpoint on 2026-10-20, the
[native simulator job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066728/job/118404774801)
and final `native-ui` job had completed with failure. The actual simulator
original passes all 81 host guards, all 25 editor-model methods and the unsigned
generic simulator build. Its first owned iPhone 17 Pro / iOS 26.2 destination
then reaches the unchanged 300-second `simctl bootstatus -b` deadline while
waiting on System App. No app install or launch and no iPad creation occurs.
Shutdown and deletion of that exact owned device each succeed. The retained
load and bounded diagnostic-probe timeouts are observations; they do not prove
an underlying cause or authorize a changed deadline. The
[original failure artifact](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066728/artifacts/12241212098)
retains all 16 original members.

The [native SDK job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066791/job/118404936631)
and [Catalog maintenance job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39354066733/job/118404703649)
now have completed successful public job states. Their distinct original logs
and artifacts are retained; this statement records those job outcomes without
assigning their output to another source. The failed whole-UI gate, repository
approval requirements, actual signed integration and post-main observation
remain open. No original job is restarted or its failure removed by this record.

### Accepted #419 evidence-source continuation

Accepted main subsequently reached
[`e742379f9a474e632a998f1586515f4cb1280b18`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/e742379f9a474e632a998f1586515f4cb1280b18).
Its four additional report-explanation cases remain in both complete 41-case
Core/UI resources and all accepted native tests. The normal source merge with
`66aef338` is conflict-free, but the unchanged cross-client producer rejects its
changed evidence file at the exact input pin. That rejection was reproduced
locally without changing any source bytes.

The receiving correction explicitly selects the original 37 evidence cases
through the named profile described above. It verifies the whole 41-case file,
all selected and excluded IDs in order, and the entire original canonical
37-case file hash before adapter/reference consumption. The four explanation
cases are explicit exclusions from this original shared profile. The correction
changes only `inputPins.evidence.sha256` in the wire bundle, producing blob
`cc3ce4f61269f38e87be79ca80daa21608cc8a45`, SHA-256
`8ae0d15ae236003d350d17066dfd1928cbe8a339095dac0299f4fefd4303d8cf`.
Every complete case row and every other bundle field equals the actually
executed `1566506e` bundle; restoring the single source pin recovers all of its
original bytes. The earlier `69718936` available-reference comparison also
remains exact through this metadata-only chain.

Actual local validation of this correction passes all 92 conformance methods,
all 11 focused cross-client methods under optimized Python, and the canonical
223-case CLI check. The two added methods exercise eleven explicit rejection
conditions for missing, duplicate, reordered, renamed or extra identities and
changed selected bytes, expectations or metadata. Each requires rejection
before adapter/reference consumption and successful restoration/retry. The
complete accepted Core/UI resources, Swift observation emitters, native
qualifiers and configured workflows are preserved.

These local correction results are separate from all `41c6772c` observations
above. The next normal receiving source must retain its own immutable source
and preparation identities and qualify its actual configured outputs. The
completed joint decisions remain scoped to the concrete received profile and
version 2 record. The later profile correction has its own source review and
local results; no new native result or final signed delivery is inferred.

The retained evidence does not establish physical-device behavior, VoiceOver,
browser journeys, installed Android behavior, remote service integration,
production evaluator parity, arbitrary future payloads, TestFlight review or
store/release approval. Temporary SQLite/probe binaries are not represented as
retained artifact files. Screenshot bytes and recorded UI assertions do not
constitute a separate visual review. The named #33/#35/#36 prerequisite outputs
remain the concrete outputs already linked above; unrelated epic and release
scope is not silently added to or completed by #37.

## Current receiving continuation — 2026-10-20, a3/986

This is a newly assembled dated amendment to the exact public record. Every
preceding byte, including the `41c6772c` evidence and decisions, remains intact.
A separately accepted private proposal had a 10,623-byte dated section and a
17,361-byte two-document patch. Its original text remains retained in its own
checkpoint but is not presently accessible to this assembly. This amendment is
written from the public record and current originals. It is not represented as
byte-identical to that private proposal or as inheriting its exact-text approval.

### Source and fixed profile

The current public contributor is
[`a3a4648eba7cb9aa77d33c3b57c4f6d1da223410`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/a3a4648eba7cb9aa77d33c3b57c4f6d1da223410),
tree `61da7d50c7138514e948f5474912dde474366c41`, ordered parents
`[66aef338b6a70909ee6663b5da98023bb25e6f36, e742379f9a474e632a998f1586515f4cb1280b18]`.
The [public source review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/383#pullrequestreview-5581139627)
covers this unsigned contribution and the full accepted 41-case Core/UI source.

The current Apple executions below checked out valid-signed preparation
[`9861d6db49046d7f66549fa757e811b10c22c78c`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/9861d6db49046d7f66549fa757e811b10c22c78c),
the same `61da7d50` tree, with ordered parents `[e742379f, a3a4648e]`.
These results are not assigned to later accepted main, this amendment or the
proposed workflow split. Earlier `41c6772c` results keep their original identity.

The current wire fixture is blob `cc3ce4f61269f38e87be79ca80daa21608cc8a45`,
SHA-256 `8ae0d15ae236003d350d17066dfd1928cbe8a339095dac0299f4fefd4303d8cf`.
Its `apple-cross-client-1/original-evidence-37` profile verifies the complete
41-case input, the exact 37 selected and four excluded IDs in order, and the
whole original canonical 37-case file before consumption. The four explanation
cases remain present in the complete accepted Core/UI resources and tests, and
explicitly outside this 223-case shared profile.

Every complete case row, payload string, Boolean/null expectation, reason and
disposition remains exact through `cc3ce4f6` → `1566506e` → `69718936`. The
whole-file inverses change only the documented source-pin metadata. There are
223 case IDs, 141 accepted/preserved and 82 rejected/null expectations, with 220
distinct payload digests. Repeated payload bytes are not missing case IDs.
Frozen contract `1.0.0` and Research `7acbefbf4e4e700231e88be272bc89e3a73dde15`
remain unchanged; no full 41-case cross-client coverage is claimed.

### Completed current originals

| Actual `9861d6db` output | Qualified observation | Public original evidence |
| --- | --- | --- |
| Canonical preparation | Both 21-method acceptance cohorts and all 92 conformance methods pass. The report has 137 schema results, six typed domain checks and three detected semantic mutants; the actual canonical producer check verifies all 223 current wire cases. | [Contract job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393128/job/118472274678), [report artifact](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393128/artifacts/12244165728) |
| Swift Transfer and wire | All 220 Transfer methods, four exact wire methods and 223 complete typed observations pass, with each observation inside its required method. The original strict receipt reconstructs exactly. All 19 host methods, nine canonical parity summaries and the unsigned generic Simulator compile also succeed. | [Transfer job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393123/job/118477890408), [wire artifact](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393123/artifacts/12247988779) |
| Apple Storage | macOS, iPhone Simulator and iPad Simulator each execute 70 exact methods and 20 typed, method-scoped migration observations: 210 method executions and 60 observations. All 21 driver guards, three actual draft/future-migration exits and six pending-write cuts pass. | [Storage job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393202/job/118478018147), [three-platform artifact](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393202/artifacts/12247477353) |
| Native SDK | The original has 558 passing Swift method executions, 81 host guards and 20 migration observations, with two unsigned Release product builds. These are configured package/SDK outputs, not installed-app or release approval. | [SDK job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393191/job/118477507610), [SDK artifact](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393191/artifacts/12247795115) |
| Other completed checks | Catalog passes 92 methods and its unsigned generic Simulator compile. The eight portable jobs have 435 literal passing observations across 234 distinct method identities; repeated scope cohorts are not distinct methods. All scope decisions require native work for the actual 19-path comparison. | [Catalog job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393215/job/118477957581), [dependency job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393183/job/118472274773), and [source check records](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/383) |

The independent Contract qualification has SHA-256
`7367517cf1f58a384539b201745261178d72b1461ee0098d28ddfd8ecc028240`.
The compressed Transfer qualification has SHA-256
`9bb440f14b35443edd7579b2546ce51fec1998b2f8027e31d7f428d294455d6b`;
the Storage qualification has SHA-256
`8610a4e14b05101ce95824efa11d62d9b40f21817c1eb685e7cbc482e5a49fef`.
They bind the immutable source, original logs, exact attendance, generated
receipts and retained artifact members. Opaque xcresult objects that were only
hash-bound are not described as semantically decoded. Temporary database and
probe binaries are not described as retained archive members.

Storage remains 31 draft-store, 35 pending-write and four migration methods.
Each platform's 20 observations cover six migration/reopen cases, eight
interrupted-step rollback/retries, three unsupported-version/compatible-backup
cases and three history restorations. All six fixture descriptions and the
original migration hash remain unchanged. Apple and Android private storage
formats and migration version numbers remain separate.

### Incomplete and failed originals

The [Core job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393187/job/118478040315)
started at 09:01:45 UTC and ended with a cancelled conclusion at 09:42:52 UTC.
Its 1,809,007-byte original log has SHA-256
`5607ff1ff24205274f4a8b99ad03c8e857e928ee748c07644a9b8c90d5f0bb6e`.
All four complete macOS debug, release, iPhone and iPad package sessions pass
151 methods each: 604 completed executions. Both 27-method host cohorts pass.
The iPhone renderer completes six methods and its strict qualifier. The iPad
renderer completes five and starts the sixth before the literal cancellation.
No failed renderer assertion is demonstrated. The later intentional-failure and
semantic-mutation steps are skipped; this is not a complete successful Core run.

The [34,189,286-byte Core archive](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393187/artifacts/12255956116),
log and metadata were captured once. Initial archive capture enumerated 773 safe
CRC-valid members. The independent full renderer/xcresult interpretation remains
pending while the shared analysis executor is unavailable. Source and literal
lifecycle analysis do not infer the missing iPad result or an underlying cause.
The 40-minute limit covers the whole serial job; that source-defined scheduling
constraint does not establish who or what cancelled it.

The separate [native simulator job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393144/job/118477424697)
failed. Its original passes 81 host guards, 25 model methods and the unsigned
generic Simulator build. The owned iPhone boots, then the unchanged 180-second
app-install command reaches its deadline. No app launch or iPad execution occurs;
owned-device cleanup succeeds. The cause remains unproved. This differs from
the earlier `41c6772c` 300-second boot-readiness failure.

The separate [native-evidence-rendering job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393144/job/118477424636)
completed successfully at 11:04:05 UTC with all nine steps successful. Its
original log contains six exact macOS renderer methods, all 68 source-defined
scenarios in their owning methods and the strict six-method qualifier's passing
line. This separately completed macOS job does not complete the cancelled Core
iPad session or the failed installed-app check.

The 1,252,811-byte renderer log has SHA-256
`2610667923bbb97b6beab42f3728d2ab503880cd77717d7711fe8a72c3ce2441`.
The [4,045,627-byte rendering artifact](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393144/artifacts/12260620567)
was captured once. Its API and original upload digests agree; independent archive
member, xcresult and screenshot inspection remain pending executor access. The
source/log qualification does not claim image comparison, VoiceOver or another
platform's outcome.

The [`native-ui` aggregate](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393144/job/118592858135)
failed at 11:04:12 UTC. Its actual gate receives `RENDERING_RESULT=success` and
`SIMULATOR_RESULT=failure`, then exits 1; the parent UI workflow is completed
with a failure conclusion. The original simulator failure is retained and no
successful retry is inferred. The [Catalog maintenance job](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39375393140/job/118472274624)
has a completed successful job state and one retained original log/artifact
capture; its independent archive audit remains pending. No result from another
source substitutes for that audit.

### Current receiving decisions and literal criteria

The contract-governance and affected-client delegates each made an actual
**ACCEPT WITH CONSTRAINTS** continuation for `a3a4648e` / `9861d6db` / `61da7d50`
and the existing version-4 public record. Each independently joined all 223
current Swift/canonical/historical Android rows, the full 37-of-41 projection,
both complete fixture-byte inverses and the current three-platform Storage
evidence. These are disclosed in-session project-role judgments, not named-person
or separate-account formal approvals.

The compressed governance decision has SHA-256
`d56e1d6d3bd5b6779694fd8b8db8a9f644aae959b1cfbb286135af47526d0c2a`.
The affected-client decision has SHA-256
`6d1c21364d84a6b47949e89d500e1073056b05ad5b9507164ac9d7dfbb61ec39`.
The prior `41c6772c` / version-2 decisions remain intact. Those actual decisions
do not approve unseen native output, the proposed workflow split or newly
assembled text by association. This amendment has its own concrete content and
publication review.

| Literal #37 criterion | Current evidence disposition | Remaining boundary |
| --- | --- | --- |
| All clients agree on pinned cross-platform fixtures and migration behavior. | Both actual current roles accept the bounded profile. Current Swift/Python agrees with historically observed Android and website rows; Apple and Android private migrations remain separately versioned and attributed. | Preserve client/version limits and real receiving judgments through incorporation and delivery. No installed-client or common on-disk format claim follows. |
| Run identical version-pinned vectors through Swift and available references; a future unshipped client uses the published harness interface and remains explicitly unverified. | Current Swift and canonical checks consume the fixed profile. Whole-row and byte inverses support comparison with actual older Android/website observations, without changing their execution identities. | Any additional unshipped consumer remains unverified. Complete configured gates and ordinary delivery of the final reviewed source. |
| The language-neutral conformance bundle and Apple migration results is linked with criterion results, exact versions, limitations and receiving-review disposition. | This new dated amendment links current originals and records the actual role decisions while preserving the complete prior record. | Complete this concrete amendment's content review and public linking, then reconcile final configured results, signed delivery and actual post-main observations. This dated text alone does not close the issue. |

Android remains actual signed `3b5a8eae` execution of original `69718936`:
223 wire observations, 34 Android-private migration observations and three
guards. The website remains the attributed original `dc66a9e2` validator/harness
execution; its raw console was not reacquired after workspace loss. The
[website receiving decision](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37#issuecomment-6283186508)
and original public references above retain their scope. No consumer was rerun
solely because input-pin metadata changed or a scratch copy disappeared.

### Source continuation and delivery limits

Accepted [1cea369a](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/1cea369a68239ed16fe381d466d9247d855f3c9c)
changes four reviewed #421 maintenance paths. Its union with `a3a4648e` is
`21eab53b59794574688ef51e272183c992ceb211`, preserving all 19 authored and four
accepted paths. No `9861d6db` outcome is assigned to its nine new maintenance
regression methods before their actual execution.

The proposed [Core workflow](../../.github/workflows/swift-core.yml) separates
Core validation, the complete iPhone renderer and complete iPad renderer into
three macOS jobs. All six renderer methods, 68 scenarios, exact destinations,
assertions and strict qualifiers remain unchanged. The final `macos-core`
aggregate runs with `always()`. Native work requires scope success and all three
native successes. Its audited-skip branch requires explicit successful
`native_required=false` and all three native jobs skipped. Missing, failed,
cancelled or unexpectedly skipped required work cannot pass.

Each native job keeps a 40-minute limit; the aggregate has five minutes. Two
additional macOS allocations and independent renderer builds are required; no
faster runner availability is promised. The unchanged selector/audit pins keep
package-only comparisons conservative until a separate reviewed refresh.
Exact allowlisted documentation-only comparisons retain their existing skip
rule. The [native scope guide](../../docs/validation/native-scope.md) records
these boundaries and unchanged per-PR concurrency.

This source-reviewed budget change is not a new native observation, a proven
cancellation fix, or relaxed method attendance or operation deadlines. A later
ordinary same-PR source advance may retire an older workflow under the existing
concurrency rule. Any such outcome must be recorded as source-lifecycle
cancellation, never as a passing original or old-source retry. The original
renderer and UI aggregate are now terminal. Their original logs, metadata and
renderer artifact capture remain separate from this proposed source and its
future configured execution.

#37 remains open. The concrete amendment's public incorporation/review links,
successful configured gates on the final actual receiving source, normal signed
delivery and post-main reconciliation require their own observations. Nothing
here closes unrelated #30, the separate #346 lane, installed mobile or physical
device behavior, VoiceOver, browser journeys, remote service integration,
production evaluator parity, TestFlight or store/release approval.
