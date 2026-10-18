# Conformance preparation dependency artifacts

This is a bounded artifact-integrity contribution to
[Apple #103](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/103).
It covers the seven existing Python validation dependencies used by the frozen
conformance preparation job. Broader release, operating-system, credential and
device/service acceptance remains open.

## Two manifests with distinct purposes

[`requirements.txt`](requirements.txt) remains the exact version manifest consumed
by `run.py`'s existing runtime check. Its bytes and all seven versions are unchanged.
[`requirements-lock.txt`](requirements-lock.txt) is the installer input: it pins
those same versions to the reviewed wheel hashes and enables hash checking and
binary-only installation. It adds no package extras or optional format providers.
The existing `FormatChecker()` behavior and frozen schema/vector bytes are unchanged.

| Validation package | Existing version | Declared license | Admitted wheels |
| --- | --- | --- | --- |
| jsonschema | 4.25.1 | MIT | One platform-independent wheel |
| referencing | 0.37.0 | MIT | One platform-independent wheel |
| jsonschema-specifications | 2025.9.1 | MIT | One platform-independent wheel |
| attrs | 26.1.0 | MIT | One platform-independent wheel |
| rpds-py | 0.30.0 | MIT | CPython 3.12: Linux x86_64, macOS x86_64 and arm64 |
| PyYAML | 6.0.3 | MIT | CPython 3.12: Linux x86_64, macOS x86_64 and arm64 |
| typing-extensions | 4.16.0 | PSF-2.0 | One platform-independent wheel |

The preparation workflow still selects Python 3.12.14 on `ubuntu-24.04`.
The eleven allowed artifacts also include the two regular CPython 3.12 macOS
architectures for the documented local preparation command. Inspecting their
wheel contents does not establish macOS execution. Other Python minors, free
threaded interpreters, operating systems and architectures need a separately
reviewed compatible lock; source builds are not an automatic fallback.

## Primary source and integrity evidence

[`requirements-provenance.json`](requirements-provenance.json) retains the exact
release-metadata URL, byte count and SHA-256 for each package, its declared Python
and dependency requirements, and every admitted wheel's filename, immutable file
URL, byte count, SHA-256, tags and embedded metadata identity. It also records the
digests of the license files actually packaged in those wheels. All eleven wheel
downloads were independently hashed and their embedded package names and versions
matched to the corresponding release before this lock was prepared. Foreign
platform wheels were inspected without loading or executing them.

The sources are PyPI's public release JSON and its referenced
`files.pythonhosted.org` artifacts. PyPI documents the
[release metadata and file digests](https://docs.pypi.org/api/json/); pip documents
[mandatory hash checking and binary-only installation](https://pip.pypa.io/en/stable/topics/secure-installs/).
All non-extra dependencies declared by the seven packages are included at their
existing compatible versions. The resolver remains enabled, so an unlisted
transitive requirement cannot silently bypass the hash boundary. On the selected
Python 3.12 runtime, referencing requires typing-extensions; the existing explicit
pin is retained rather than made conditional or removed.

## Installation and verification

Follow the [complete preparation commands](README.md#reproduce). The workflow and
documented install use `python -m pip --isolated install`, an explicit public PyPI
index, `--require-hashes`, `--only-binary=:all:` and the artifact lock, followed by
`python -m pip check`. The lock also carries the hash and binary options itself.
Use a fresh virtual environment when reviewing an update; a preinstalled package
is not evidence that its download passed the current hash check.

Required receiving evidence is a fresh isolated install with all seven exact
versions, a successful dependency consistency check, and the existing frozen
reference, schema/domain, mutation, Pricebook, raw-JSON, harness and identical
Swift-vector preparation commands. Also exercise the actual installer against a
changed artifact or hash and an omitted transitive pin: both must fail without
admitting an unreviewed package. Those installer rejections and Python preparation
results remain separate from native Swift, simulator and physical-device checks.

When updating a dependency, review its primary release metadata and all selected
wheel identities, hashes, licenses and transitive requirements. Update both
manifests and the provenance together, verify the fresh install and negative
cases, run the documented preparation commands, and obtain independent receiving
review plus the actual hosted dependency-policy and preparation results. Do not
reuse this lock to change the separate transfer validator's provider contract.

The Python interpreter, pip bootstrap, host image, system libraries and release
dependencies are outside this seven-package artifact lock. Matching a reviewed
hash proves artifact integrity, not absence of vulnerabilities or deployment
readiness. This change supplies no credential rotation, external service action,
catalog evidence, Apple build, installed result or broad #103 acceptance.
