# Locked transfer reference environment

Related to [Apple #103](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/103)
and its existing [dependency review delivery](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/230).
This slice replaces the inline transfer validator install at accepted main
`8ca109963bfca3a707b1af8b80aabcd9dd28fd8a`. It covers Python validation
dependencies. Native runtime dependencies, the hosted image, the Python binary,
release qualification and the separate conformance-preparation environment keep
their own inventories and gates.

## Selected format providers

The six frozen schema/fixture source hashes and both vector files remain unchanged.
The bundled schemas declare only `date-time` and `uri` formats. The validator stays
at `jsonschema==4.26.0`; its inspected wheel's `jsonschema/_format.py` registers
`rfc3339-validator` for timestamps and explicitly supports `rfc3986-validator`
for URI checking when `rfc3987` is absent.

The former `format` extra also resolves packages that these schemas do not use.
Primary release metadata identifies
[rfc3987 1.3.8](https://pypi.org/pypi/rfc3987/1.3.8/json) as GNU GPLv3+ and
[fqdn 1.6.0](https://pypi.org/pypi/fqdn/1.6.0/json) as MPL-2.0. Those declarations
are outside the reviewed dependency policy's allowlist. The upstream
`format-nongpl` extra still includes fqdn. This environment therefore selects the
two required supported providers explicitly, without extending that license policy
or installing the unused extras. This is a provider change, not a claim that the
old and new Python environments have identical dependency graphs.

The URI reference still follows the canonical schema's RFC3986 semantics.
The Swift client retains its documented narrower URI subset, including its
IP-literal exclusion; a positive reference URI probe is not new Swift admission.
Always create a fresh virtual environment: an unrelated installed `rfc3987`
would take precedence in jsonschema's provider selection.

## Complete Python dependency lock

[requirements.txt](requirements.txt) pins every required Python distribution,
including the conditional dependency on typing-extensions.
[requirements-provenance.json](requirements-provenance.json) maps each accepted
wheel filename to its exact SHA-256, byte count and primary release URL, and
retains the inspected metadata and format-source hashes.

| Distribution | Version | Declared license | Reason |
| --- | --- | --- | --- |
| [jsonschema](https://pypi.org/pypi/jsonschema/4.26.0/json) | 4.26.0 | MIT | Existing reference validator |
| [attrs](https://pypi.org/pypi/attrs/26.1.0/json) | 26.1.0 | MIT | Validator/referencing dependency |
| [jsonschema-specifications](https://pypi.org/pypi/jsonschema-specifications/2025.9.1/json) | 2025.9.1 | MIT | Validator vocabulary resources |
| [referencing](https://pypi.org/pypi/referencing/0.37.0/json) | 0.37.0 | MIT | Explicit local resource registry |
| [rpds-py](https://pypi.org/pypi/rpds-py/2026.9.1/json) | 2026.9.1 | MIT | Validator/referencing data structures |
| [rfc3339-validator](https://pypi.org/pypi/rfc3339-validator/0.1.4/json) | 0.1.4 | MIT | Required date-time provider |
| [rfc3986-validator](https://pypi.org/pypi/rfc3986-validator/0.1.1/json) | 0.1.1 | MIT | Required URI provider |
| [six](https://pypi.org/pypi/six/1.17.0/json) | 1.17.0 | MIT | Timestamp provider dependency |
| [typing-extensions](https://pypi.org/pypi/typing-extensions/4.16.0/json) | 4.16.0 | PSF-2.0 | Referencing dependency only on Python before 3.13 |

The existing [main transfer job117643078356](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39116428745/job/117643078356)
actually resolved jsonschema 4.26.0, attrs 26.1.0, specifications 2025.9.1,
referencing 0.37.0, rpds-py 2026.9.1, rfc3339-validator 0.1.4 and six 1.17.0 on
CPython 3.14/macOS arm64. These observed versions are preserved. The separate
preparation harness's jsonschema 4.25.1/rpds-py 0.30.0 declarations remain unchanged.

All 17 allowed wheel files were fetched from the versioned primary metadata URLs
on 2026-10-18 and independently matched to their recorded byte counts and SHA-256s.
The lock permits regular CPython 3.11–3.14 on macOS arm64/x86_64, plus CPython 3.12
on manylinux2014 x86_64 for the local check host. These are allowed artifact
targets, not execution receipts for every listed interpreter or architecture.
Other wheels, source distributions and build-time resolution are excluded.

The requirements file enables [pip hash-checking mode and binary-only installation](https://pip.pypa.io/en/stable/topics/secure-installs/)
and fixes the index to PyPI. The workflow also passes the security flags explicitly,
uses pip's isolated configuration mode, keeps dependency resolution enabled, and
runs `pip check`. No `--no-deps` shortcut can hide a missing transitive pin.
Release hashes lock inspected bytes; they do not establish absence of
vulnerabilities or independently verify publisher attestations. The declared
licenses are reviewed package metadata, not an audit of every bundled source or
the native release's redistribution obligations.

## Reproduce

From the repository root, using a supported interpreter:

```sh
transfer_validation_dir=$(mktemp -d)
python3 -m venv "$transfer_validation_dir"
"$transfer_validation_dir/bin/python" --version
"$transfer_validation_dir/bin/python" -m pip --isolated install --require-hashes --only-binary=:all: -r Packages/PlannerTransfer/Tools/requirements.txt
"$transfer_validation_dir/bin/python" -m pip check
"$transfer_validation_dir/bin/python" Packages/PlannerTransfer/Tools/verify_contract.py
```

The reference checker must report all six source hashes, 129 shared cases, all
29 catalog kinds and 1,635 catalog cases. It requires both format registrations
before running the corpus. Network access is needed for installation; validation
itself resolves only the pinned local resources. The workflow records its existing
`python3` interpreter; selecting or freezing a different Python/host image is
outside this dependency lock. Xcode 16.4/16F6, all Swift tests and unsigned simulator
compilation remain unchanged and required.

The additional format-provider probes are reproducible in the same fresh
environment:

```sh
"$transfer_validation_dir/bin/python" - <<'PY'
from jsonschema import FormatChecker

cases = {
    "uri": [
        (True, "https://example.com/a%20b?q=c#fragment"),
        (True, "mailto:person@example.com"), (True, "urn:example:test"),
        (True, "https://[2001:db8::1]/"),
        (True, "https://xn--bcher-kva.example/"),
        (False, "relative/path"), (False, "https://example.com/%GG"),
        (False, "https://[broken]/"), (False, "https://exämple.com/"),
        (False, "https://example.com/a b"), (False, "https://example.com/\x00"),
    ],
    "date-time": [
        (True, "2024-02-29T23:59:59Z"), (True, "2024-02-29t23:59:59z"),
        (True, "2026-10-18T12:34:56.123456+02:00"),
        (False, "2023-02-29T00:00:00Z"), (False, "2026-10-18T24:00:00Z"),
        (False, "2026-10-18T12:34:56"), (False, "2026-10-18 12:34:56Z"),
        (False, "2026-10-18T12:34:56+25:00"),
    ],
}
checker = FormatChecker()
assert set(cases) <= checker.checkers.keys()
for kind, probes in cases.items():
    for expected, value in probes:
        assert checker.conforms(value, kind) is expected, (kind, value)
print("19 format-provider probes passed.")
PY
```

## Actual rejection and recovery evidence

On 2026-10-18, a new Python 3.12.14 virtual environment with pip 25.0.1 installed
all nine applicable distributions from the exact required hashes. `pip check`,
the complete reference/vector checker and all 19 provider probes passed.
The exact installed provider registrations were also inspected; neither
rfc3987 nor fqdn was present.

A separate offline wheelhouse contained only the 17 fetched and hash-verified
artifacts. Real pip subprocesses produced these results:

| Case | Observed result |
| --- | --- |
| Change the first jsonschema wheel hash digit from `d` to `0` in a disposable lock copy | Exit 1 with the actual hash-mismatch diagnostic |
| Remove six's entire requirement/hash block from another disposable copy | Exit 1 requiring the transitive dependency to have a pinned version/hash |
| Restore the original complete lock | Exit 0 and complete wheel selection |
| Resolve CPython 3.14/macOS arm64 against the same lock | Exit 0 and the exact arm64 wheel selected |
| Resolve CPython 3.14/macOS x86_64 against the same lock | Exit 0 and the exact x86_64 wheel selected |

Cross-platform resolution downloads compatible wheels; it does not execute their
binaries or reproduce foreign-interpreter marker evaluation. The hosted native
job must validate its own actual interpreter and complete package execution.

In a second disposable environment, removing only rfc3986-validator caused the
actual reference checker to exit 1 at its missing-format guard. Reinstalling the
original hashed requirements restored all six hashes and both complete vector
corpora. The committed lock and the first successful environment were unchanged
throughout these negative cases.

These observations establish the bounded environment correction. Independent
receiving review and this changed workflow's actual hosted transfer result remain
delivery gates. The separate introduced-vulnerable/unacceptable-license dependency
PR drill, broader baseline and bundled-dependency audit, credential-custodian
rotation, service/device checks and final release inventory remain open under #103.
