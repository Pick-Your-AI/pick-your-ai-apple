# Frozen v1 conformance preparation

Related issues: [#32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32),
[#37](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37), and
[#104](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/104).
This is framework-neutral, synthetic fixture preparation. It does not choose the
application framework, module structure, deployment topology or OS matrix gated
by #22/#23. It is not an acceptance record or a competing evaluator/backend.

The runner consumes the canonical research import from a read-only checkout.
`contract-lock.json` pins its revision, contract/fixture versions and import
manifest hash; every imported file must match that manifest before reference
code executes. Research branches may advance without changing the frozen bytes.
The copied executable inputs are exactly those listed in the verified manifest;
no network schema retrieval or untracked source code is needed. The
[adoption limitations](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/ADOPTION.md)
apply: reference rules are proposals, not accepted vendor facts or deployment policy.

## Reproduce

Use Python 3.12 and a checkout of research at the pinned revision. The runner
requires the exact dependency versions in `requirements.txt` and records the
actual Python version. From this repository:

```sh
python3.12 -m venv /tmp/apple-conformance-venv
/tmp/apple-conformance-venv/bin/pip install -r tools/conformance/requirements.txt
export CONTRACT_ROOT=/path/to/pick-your-ai-research/contracts/v1
/tmp/apple-conformance-venv/bin/python tools/conformance/run.py \
  --contract-root "$CONTRACT_ROOT" --output /tmp/apple-conformance.json
/tmp/apple-conformance-venv/bin/python -m unittest discover \
  -s tools/conformance/tests -v
```

All 11 canonical example families receive positive vectors, a negative vector
for each required top-level field, unsupported-version rejection and unknown
field rejection. Numeric JSON money is rejected. Domain checks use the existing
canonical reference, including missing-resource unknown, dimension mismatch and
exact decimal comparisons beyond binary64 precision. The complete canonical
reference test suite also runs in a disposable copy.

Mutation testing deliberately removes a required field from the copied schema,
changes the reference decimal conversion to binary floating point, and forces
reference equality comparisons to pass. Each mutation must fail the applicable
checks; original files stay untouched. Harness tests verify hash tampering,
recovery after restoring bytes, inverted expectations and deterministic vectors.

## Consumer interface and evidence limits

The output JSON contains `lock`, `python`, `dependencies`, `schema_results`,
`domain_results`, `mutations`, `canonical_reference`, `vectors` and `limitations`.
Each vector has a unique `id`, schema filename, concrete JSON `payload` and
expected boolean `valid`. A future Swift consumer can replay these identical
payloads against the pinned schemas and compare its result for every ID. Do not
normalize decimal strings into binary floating point. The output is generated,
not committed; retain it with the producing Apple commit in review/CI evidence.
A zero exit status requires all baseline checks and all three mutations to pass.
The output must be outside the frozen contract and conformance tool directories,
with an existing directory parent. An existing destination must be a regular file
with one hardlink; symbolic links, directories and other file types are rejected
without changing them or their targets. Parent-directory aliases are resolved
before checking these boundaries. Use a separate output path for each concurrent
run.

After accepting the destination, the runner removes any previous receipt before
checking source bytes or dependencies. A conformance failure exits nonzero with
no success report at that path. Success JSON is fully serialized and written to
a temporary sibling before atomic publication; write or publication failures also
exit nonzero and remove the temporary file. Import, argument and destination
preflight failures occur before invalidation and leave existing files unchanged.
Harness regressions exercise an actual successful CLI run, source rejection and
recovery, plus protected paths, dependency rejection and partial-write failures.

## Shared report vectors and native regression detection

`export_swift_vectors.py` verifies the frozen manifest and exports 45 report
payloads with canonical schema expectations to the Swift test resource. Payloads
are JSON strings so the Swift test passes their exact UTF-8 bytes to the decoder.
The cases cover required fields, nulls, incompatible versions, unknown properties,
invalid enums and every outcome/severity combination with absent, null and literal
`unknown` evidence. Valid reports round-trip without collapsing outcome/severity.

```sh
python tools/conformance/export_swift_vectors.py \
  --contract-root "$CONTRACT_ROOT" \
  --output Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures/evaluation-vectors.json \
  --check
```

Omit `--check` only to regenerate the checked-in resource after reviewing changes.
The check also verifies the original Swift report fixture hash. Python CI fails on
any generated-byte drift. Swift tests consume the resource in Debug and Release;
neither hand-edited expected results nor a passing Python run establishes Swift
parity. Require both checks for the same commit. This is partial #32/#37/#104
coverage for evaluation reports only, not all 29 catalog kinds or service parity.
The decoder's documented number/depth/timestamp exclusions remain client limits.

`evidence_vectors.py --contract-root "$CONTRACT_ROOT" --check` adds 37 shared
evidence inputs for the Core decoder and actual SwiftUI rendering tests. It
re-verifies a disposable copy of the frozen inputs, checks 28 accepted and nine
rejected cases with the canonical schema consumer, and requires exact matching
bytes in both package resources. The [evidence state mapping](../../Packages/PlannerUI/EVIDENCE_RENDERING.md)
records the presence, conflict, skipped-rule and claim-grade boundaries, the
exact versions, and the separate native receiving gate. These synthetic inputs
do not establish source verification or a compatibility policy.

`qualify_evidence_rendering.py` qualifies the four selected native UI test methods
using the existing strict XCTest parser and the explicit `PlannerEvidenceUITests` module.
The Core parser's default module and mutation criteria remain unchanged. The
workflow first requires the actual `xcodebuild test` command to succeed, then
rejects empty, skipped, duplicate, truncated or incorrectly named log receipts.
The [isolated real-app host](../evidence-rendering/README.md) preserves the original
failed direct-host native evidence and runs the four rendering methods through
public UI automation; it does not change production views or the shared bytes.

`swift_mutations.py --package Packages/PlannerCore --output-dir /tmp/swift-mutations`
first runs the unmodified Swift suite, then changes required-field handling,
decimal ordering and request-generation acceptance in separate disposable copies.
The baseline must contain complete, uniquely identified XCTest cases, zero failures
or skips, a matching nonzero suite total, and passes from all three exact named
regressions. Compile-only output and the separate Swift Testing zero-test footer
cannot qualify. Each mutation must execute only its exact selected regression,
trigger that test's expected assertion, and complete with a matching failed
XCTest suite summary. A class or method that only contains the expected name
does not qualify. Duplicate results, unexpected failures, truncated output,
compile errors, crashes, timeouts and changed anchors do not qualify.
The source package is never changed. CI retains the logs and success receipt.
This supplements the existing deliberate XCTest failure probe and Python reference
mutations for #30/#104; it does not prove branch protection is enforced.

The exact-identity regression was reproduced against accepted main `8ca109963`:
renaming the reported required-field test to a method with an `Extra` suffix still
qualified under the former substring check. The corrected guard rejects it.
Portable tests exercise Linux and macOS XCTest spellings, unrelated similarly
named methods/classes, assertion identity, missing/duplicate/skipped results,
summary mismatches, empty successful baselines and stale-receipt removal.
The corrected parser also accepts the actual 67-case baseline and all three
deliberate failures retained in [core run 39108049392](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39108049392),
artifact `12129239361`, verified SHA-256
`df5b91c70d2ba2dd193e8f84d69eb47b3bfc12f0daac11176d176567996093e2`.
That replay verifies compatibility with historical log bytes; it is not a fresh
Swift execution. A subsequent fresh local run using Swift 6.1.2 on Linux executed
all 67 unchanged baseline cases successfully, then detected all three actual
semantic mutations through their expected XCTest assertions. The run used
task-scoped caches and required no change to application or test sources.
The changed runner must still complete its actual hosted macOS core workflow on
the reviewed candidate before delivery; Linux execution is separate evidence.

Supported historical migration, rollback, approved executable policy, actual
service parity, simulator execution, device results and receiving acceptance are
still unverified. Rejection of unsupported versions is not successful migration.
