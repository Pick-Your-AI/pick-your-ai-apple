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
Manifest verification and parsing use the same bytes. Both the runner and Swift
vector exporter also verify every completed copy against that trusted manifest
before reading copied fixtures or executing copied reference code. Copied-byte
drift fails without a success result; restoring the pinned bytes permits a normal
retry. Copying also rechecks source-path containment.
The copied executable inputs are exactly those listed in the verified manifest;
no network schema retrieval or untracked source code is needed. The
[adoption limitations](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/ADOPTION.md)
apply: reference rules are proposals, not accepted vendor facts or deployment policy.

## Reproduce

Use Python 3.12 and a checkout of research at the pinned revision. The runner
requires the exact dependency versions in `requirements.txt` and records the
actual Python version. Install their reviewed wheel hashes from
`requirements-lock.txt`; [the environment record](environment-lock.md) lists
its platform coverage, primary artifact provenance and remaining limits. The
version manifest and existing runtime check are unchanged. Use a newly created
virtual environment for each installation so existing same-version packages
cannot bypass artifact checking. The selected Python's pip manages that environment
using its [supported `--python` option](https://pip.pypa.io/en/stable/topics/python-option/)
(pip 22.3 or newer). From this repository:

```sh
conformance_env=$(mktemp -d "${TMPDIR:-/tmp}/apple-conformance.XXXXXX")
python3.12 -m venv --without-pip "$conformance_env"
python3.12 -m pip --python "$conformance_env/bin/python" --isolated install \
  --index-url https://pypi.org/simple --require-hashes --only-binary=:all: \
  -r tools/conformance/requirements-lock.txt
python3.12 -m pip --python "$conformance_env/bin/python" --isolated check
export APPLE_CONFORMANCE_PYTHON="$conformance_env/bin/python"
export CONTRACT_ROOT=/path/to/pick-your-ai-research/contracts/v1
"$APPLE_CONFORMANCE_PYTHON" tools/conformance/run.py \
  --contract-root "$CONTRACT_ROOT" --output /tmp/apple-conformance.json
"$APPLE_CONFORMANCE_PYTHON" -m unittest discover \
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
without changing them or their targets. Native directory lookup with
[`Path.stat`](https://docs.python.org/3.12/library/pathlib.html#pathlib.Path.stat)
validates the raw selected contract root and output parent before alias resolution.
An ordinary file or missing prefix followed by `..` cannot be normalized away before cleanup.
Resolved directory identity is checked for consistency, and output ancestors are
also compared by [physical identity](https://docs.python.org/3.12/library/os.path.html#os.path.samestat)
to protect case variants on case-insensitive filesystems. Valid outside directory
aliases remain supported. These checks do
not make concurrent directory replacement race-free. Use a separate output path
for each concurrent run.

After accepting the destination, the runner removes any previous receipt before
checking source bytes or dependencies. A conformance failure exits nonzero with
no success report at that path. Success JSON is fully serialized and written to
a temporary sibling before atomic publication; write or publication failures also
exit nonzero and remove the temporary file. Import, argument and destination
preflight failures, including structural contract-root or output-parent failures,
occur before invalidation and leave existing files unchanged. A valid directory
whose frozen contents fail validation still invalidates its accepted receipt.
Harness regressions exercise an actual successful CLI run, source rejection and
recovery, plus protected paths, dependency rejection and partial-write failures.
Output-path regressions use isolated synthetic directories; their case-variant
check reports whether the actual filesystem supplies an alias or distinct directories.

## Shared report vectors and native regression detection

`export_swift_vectors.py` verifies the frozen manifest and exports 45 report
payloads with canonical schema expectations to the Swift test resource. Payloads
are JSON strings so the Swift test passes their exact UTF-8 bytes to the decoder.
The cases cover required fields, nulls, incompatible versions, unknown properties,
invalid enums and every outcome/severity combination with absent, null and literal
`unknown` evidence. Valid reports round-trip without collapsing outcome/severity.

```sh
"$APPLE_CONFORMANCE_PYTHON" tools/conformance/export_swift_vectors.py \
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
uses the shared source-copy containment check, re-verifies the completed frozen
manifest and copied bytes, checks 28 accepted and nine rejected cases with the
canonical schema consumer, and requires exact matching
bytes in both package resources. The [evidence state mapping](../../Packages/PlannerUI/EVIDENCE_RENDERING.md)
records the presence, conflict, skipped-rule and claim-grade boundaries, the
exact versions, and the separate native receiving gate. These synthetic inputs
do not establish source verification or a compatibility policy.

`qualify_evidence_rendering.py` qualifies the seven selected native UI test methods
using the existing strict XCTest parser and the explicit `PlannerEvidenceUITests` module.
The Core parser's default module and mutation criteria remain unchanged. The
workflow first requires the actual `xcodebuild test` command to succeed, then
rejects empty, skipped, duplicate, truncated or incorrectly named log receipts.
The [isolated real-app host](../evidence-rendering/README.md) preserves the original
failed direct-host native evidence and runs the four original rendering methods,
the accepted capture-date and copy-localization methods, and the
[visible-analysis identity test](../../docs/validation/visible-analysis.md) through
public UI automation. Each original source and execution record retains its own
method set; the current combined qualifier requires all seven. Both six-method
predecessors, the earlier five-method date-only receipt and synthetic receipt
fixtures cannot establish current native execution. Shared vector bytes remain
unchanged.

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
Each invocation keeps its configured deadline (`--timeout`, default 300 seconds).
On POSIX hosts, it starts a new session and terminates only that invocation's
process group after a wait timeout, then reaps the driver before propagating the
failure. An interrupted wait applies the same cleanup while the driver remains
unreaped; an already reaped PID is never reused for signaling. Compiler or test children that retain the group
cannot continue writing after a timeout. A child that deliberately starts another
session is outside this group boundary. Normal completions preserve their actual
exit status and combined output; no retry is added. Non-POSIX hosts retain
direct-child termination without a process-group claim. The implementation uses
Python's documented [new-session process creation and wait semantics](https://docs.python.org/3.12/library/subprocess.html#subprocess.Popen).
The source package is never changed. The selected package path must pass native
directory lookup before normalization or output cleanup. A regular-file or
missing prefix before `..`, including one inside a symlink target, cannot be
discarded to select a different usable package. Strict resolution then requires
the same observed directory identity. Invalid package lookup, resolution or
identity changes reject before any prior output is removed; valid directory
aliases remain supported. These observations do not make concurrent directory
replacement atomic or supported.
Before execution, the runner checks all
five fixed output names (the receipt, baseline log and three mutation logs).
Existing outputs must be regular files with one hard link; symlinks, shared
hardlinks, directories and other file types reject the invocation before any
previous output is removed. The supplied output directory may use an outside
directory alias, but may not traverse the source package even if a later alias
resolves outside it. This includes each intermediate absolute or relative link
target and traversal before `..`; links are inspected component by component.
Existing directory identity also protects case aliases on filesystems that treat
them as the same package. Link loops and non-directory or missing prefixes before
`..` fail before directory creation or cleanup. Resolution permits at most 64
directory-link expansions per invocation; longer chains fail during preflight.
A valid rerun clears all five previous outputs, then creates new logs and the
final success receipt exclusively. Files appearing after
preflight cannot be followed or overwritten. Use a separate evidence directory
per concurrent invocation; concurrent replacement of parent directories is not
supported. CI retains the logs and success receipt.
This supplements the existing deliberate XCTest failure probe and Python reference
mutations for #30/#104; it does not prove branch protection is enforced.

The exact-identity regression was reproduced against accepted main `8ca109963`:
renaming the reported required-field test to a method with an `Extra` suffix still
qualified under the former substring check. The corrected guard rejects it.
Portable tests exercise Linux and macOS XCTest spellings, unrelated similarly
named methods/classes, assertion identity, missing/duplicate/skipped results,
summary mismatches, empty successful baselines and stale-receipt removal.
Output regressions reproduce a real child-process invocation against a synthetic
package, exercise every destination with symbolic/hard links and nonregular
files, and verify rejected paths preserve source bytes and prior receipts.
Separate cases cover a source-traversing directory alias, safe outside aliases,
intermediate link chains and loops, failed-baseline cleanup and retry, and files
introduced after preflight. A filesystem-conditioned case test distinguishes an
actual package alias from a separately existing case variant; its case-insensitive
branch requires execution on such a filesystem. The core workflow runs this
stdlib-only suite normally and with `-O` in its existing macOS job before Swift
builds; both retained logs identify the case branch actually exercised.
These portable I/O and
synthetic-transcript checks are not a Swift execution receipt.
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

The package-path preflight regression was reproduced against accepted
`7dd9f7d1ad1a6590021b52bd303d16ffba697f47`. In owned synthetic inputs,
`evidence/baseline.log/../package` failed native lookup, but the CLI normalized
away the regular-file prefix and cleared prior outputs before execution failed.
A symlink to that invalid path reproduced the same result. Three added methods
cover eight rejected selectors, a valid directory alias with failed-baseline
cleanup and successful retry, and an observed directory-identity mismatch.
Against the original helper, two methods failed with seven assertions while the
valid-alias control passed. The correction passes all three focused methods and
all 25 methods normally and with `-O` on Python 3.12.14. Real CLI children use only
owned temporary packages and a deliberately absent executable or an explicitly
synthetic transcript producer; they do not execute Swift. The identity-mismatch
test models the changed resolution observation without claiming a concurrent
filesystem reproduction. All prior 22 methods and the three mutation anchors
remain intact. Actual current-source macOS qualification remains required.

The process-group correction was reproduced on accepted
`677be39da2472a859c204f4e6db0507e30a38559` using an owned synthetic Swift driver
that starts a compiler child. At each of the four invocation phases, the prior
runner timed out and reaped the driver while the child kept its sole FIFO writer
open. The corrected regression observes FIFO EOF, confirms driver reaping and
preserves an unrelated running process. It also checks retained partial logs,
absence of later-phase logs and the success receipt, and unchanged package bytes.
Another actual subprocess control preserves exit codes 0 and 7, argument order,
combined stdout/stderr and replacement decoding of invalid output bytes. These
two added methods extend the existing 25-method suite; they execute only bounded
Python fixtures and do not establish new Swift, macOS or simulator results.

Supported historical migration, rollback, approved executable policy, actual
service parity, simulator execution, device results and receiving acceptance are
still unverified. Rejection of unsupported versions is not successful migration.
