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
Any failure exits nonzero and does not write a new report; do not treat an old
output file as evidence of a new run.

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

`swift_mutations.py --package Packages/PlannerCore --output-dir /tmp/swift-mutations`
first runs the unmodified Swift suite, then changes required-field handling,
decimal ordering and request-generation acceptance in separate disposable copies.
Each mutation must trigger its named regression assertion and normal failed test
completion. Compile errors, crashes, timeouts and changed anchors do not qualify.
The source package is never changed. CI retains the logs and success receipt.
This supplements the existing deliberate XCTest failure probe and Python reference
mutations for #30/#104; it does not prove branch protection is enforced.

Supported historical migration, rollback, approved executable policy, actual
service parity, simulator execution, device results and receiving acceptance are
still unverified. Rejection of unsupported versions is not successful migration.
