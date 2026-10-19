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

The initial hosted scan in #280 reported a conflicting license expression for
the exact typing-extensions wheel. The [bounded source proof](../../docs/validation/typing-extensions-license-proof.md)
records the complete artifact/license comparison, observed failure and required
guard conditions. It preserves the generic license policy and separate receiving gates.

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
documented command create a unique fresh virtual environment with the selected
Python and without inherited system packages. The selected interpreter's pip uses
its [supported `--python` option](https://pip.pypa.io/en/stable/topics/python-option/)
to manage the target environment without adding a second pip bootstrap. Installation
retains `--isolated`, the explicit public PyPI index, `--require-hashes`,
`--only-binary=:all:` and the artifact lock, followed by an isolated `pip check`
against that same target. The lock also carries the hash and binary options itself.
After successful installation and consistency checking, the workflow exports that
environment's Python path for every subsequent preparation command. A failed
installation cannot publish that path or proceed to the validation steps.

An actual offline probe with Python 3.12.14 and pip 26.2.1 reproduced the previous
workflow's gap: two harmless wheels had the same name and version but different
inert marker strings. After the different wheel was preinstalled, the prior
hash-required install reported `Requirement already satisfied`, returned success
and retained the different marker despite a lock for the reviewed wheel. Running
the locked install in a fresh environment installed the reviewed marker instead.
Pip's `--isolated` flag isolates its configuration; it does not empty site-packages
or verify a matching package that the installer considers already satisfied.
This fixture experiment establishes installer behavior, not contamination of a
hosted runner or execution of the real conformance/native suites.

The corrected workflow's actual install-step shell was also exercised with only
its public index and lock inputs replaced by harmless local fixtures. Two runs
created different environments, installed the reviewed marker, passed dependency
consistency and excluded the host's different preinstalled fixture. A wrong hash
and an omitted transitive pin each returned a failure without exporting an
interpreter. The bootstrap fixture remained unchanged in all four runs. All five
subsequent preparation commands retain their original arguments and explicitly
use the verified environment's Python; fresh hosted execution is still required.

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
