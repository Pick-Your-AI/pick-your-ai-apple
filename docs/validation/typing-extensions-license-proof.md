# Exact typing-extensions license classification

This records the bounded source evidence and proposed gate correction for the
`typing-extensions==4.16.0` addition in [Apple #280](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/280).
It is an engineering classification resolution for one reviewed artifact and
installer. Broader [#103](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/103)
acceptance, release licensing, credentials and device/service evidence remain open.

## Observed failure

Dependency job [117692891082](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39133373285/job/117692891082)
checked prepared commit `39d83c4f2b0aeb1911c28f35505862136925e28c`, tree
`b79ee3cf0a77b484d2248ec1789363ecffc29a16`, for base `074ae4bffec6066d3fe6e6a5fe47ab429dde54ed`
and head `cbbec29ec1087db88f867982d95f52b8dfad9b0d`. All 31 then-existing
security regressions passed. The complete snapshot matched seven dependency rows
without warnings. The upstream Action reported no vulnerable addition but marked
one license as forbidden; both the upstream step and the final guard failed.

The retained [classification fixture](../../tools/security/tests/fixtures/typing-extensions-license-classification.json)
contains that exact row and its surrounding six MIT additions, the complete three
license categories, source identities and decoded-log digest. The reported
expression combines Python, GPL, BSD and 0BSD terms with `AND`. This expression is
retained unchanged as the required input to the narrowly matched recovery.

## Reviewed primary artifact

The [official PyPI release](https://pypi.org/project/typing-extensions/4.16.0/)
declares `PSF-2.0`; its wheel's embedded `METADATA` has the same license expression
and names `LICENSE`. The PyPI provenance names upstream publishing commit
`f29cd28d8ed7642cafb1d18daf5aa41be6a5c0aa`. At that exact signed commit,
[`pyproject.toml`](https://github.com/python/typing_extensions/blob/f29cd28d8ed7642cafb1d18daf5aa41be6a5c0aa/pyproject.toml)
declares version 4.16.0, `PSF-2.0` and the same license filename. The complete
[`LICENSE`](https://github.com/python/typing_extensions/blob/f29cd28d8ed7642cafb1d18daf5aa41be6a5c0aa/LICENSE)
is byte-for-byte identical to the wheel's packaged license.

That license separates Python release history and GPL compatibility from the
actual grants. Its history explicitly says “GPL-compatible doesn't mean that
we're distributing Python under the GPL.” The terms identify PSF License Version 2;
documentation code has a PSF/0BSD choice. The full historical CNRI, BeOpen and CWI
notices remain present. The reviewed source therefore supports the declared
PSF-2.0 license for this exact wheel; it does not establish a general GPL or 0BSD
allowance for other software.

| Reviewed input | Bytes | SHA-256 |
| --- | ---: | --- |
| Universal wheel | 45,571 | `481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8` |
| Embedded package metadata | 3,310 | `b05084ca1d50879865178d9fff9fabeab61bdfb1f361bfbde95421ffc8f9be46` |
| Embedded and upstream LICENSE | 13,936 | `3b2f81fe21d181c499c59a256c8e1968455d6689d269aa85373bfb6af41da3bf` |
| Upstream pyproject | 3,613 | `78bc1fcc5e354c7586d13a9d3311f1c6475c2de5354b170924ebdbef956a9528` |
| Exact conformance artifact lock | 1,359 | `39f16918d39968c6e26183c2d09399b49cc071bf751a7c3beff4577dd3717c23` |

The [existing artifact provenance](../../tools/conformance/requirements-provenance.json)
retains the release JSON identity and immutable wheel URL. No wheel archive or raw
hosted log is committed. The source review inspected all archive members and the
entire license; the running guard needs only a bounded hash check of that already
reviewed immutable archive, without extraction, installation or execution.

## Gate boundary

The generic license allowlist and `evaluate()` category rejection are unchanged.
The only new source resolution requires all of the following:

- The upstream outcome is exactly `failure` and the independent exact-commit
  snapshot step completed successfully. Missing, cancelled, skipped or unknown
  outcomes fail.
- Exactly one forbidden row matches every observed field, including the complete
  expression, package URL/version, runtime scope and literal conformance lock
  path. The raw changes contain that row once with no conflicting same-URL row.
  Any other invalid category or any reported vulnerability prevents recovery.
- The existing policy explicitly includes `PSF-2.0`, and execution is this
  repository's ordinary pull-request review.
- The literal installer is a single-link regular file opened without following a
  symbolic link. Its complete size and digest match the reviewed hash-only,
  binary-only lock. A different declaration or future lock change needs review.
- A fixed public HTTPS request retrieves the exact 45,571-byte wheel within the
  ten-second deadline. Redirects, unsuccessful statuses, short/long responses and
  changed hashes fail. No repository token or other credential is sent to the
  artifact host, and no URL is taken from review payloads.

The workflow permits the upstream step to continue so its mandatory snapshot and
final decision guards can process this documented failure. GitHub distinguishes
the step's original [outcome from its adjusted conclusion](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#steps-context);
the final guard consumes `outcome`. A failed upstream step with otherwise clean
or empty output has no verified recovery and is rejected. Snapshot failure still
fails the job and cannot supply the required success outcome. The final guard
has no continue-on-error setting. The earlier exact Action MIT proof still
requires a successful upstream step and retains its original source boundary.

This proof covers only the current conformance installer. Other manifests,
versions, license expressions or artifacts are not implicitly admitted. If the
upstream classification later reports the declared allowed license successfully,
the ordinary successful path accepts it without this exception or network proof.

## Executed verification and remaining receiving evidence

Replaying the exact retained seven-row input through the unchanged original guard
produced one disallowed license and exit 1. The corrected guard then actually
downloaded and hashed the fixed wheel without a repository token and returned
exit 0, seven additions, one pinned license resolution and no rejection counters.
That local replay uses the recorded upstream/snapshot outcomes; it does not
claim a new advisory query or a fresh hosted workflow result.

All 44 security test methods passed with zero skips, including the original 31 and
13 new methods with identity, policy, workflow-outcome, duplicate/category,
filesystem, transport, deadline and byte-mutation cases. Transport unit tests use
inert synthetic bytes and a matching test-only digest; they are separate from
the actual immutable-wheel download above. All six synthetic CLI rehearsal cases
also retained their expected results. No validation-package version, provider,
schema, vector, conformance runner or native source changed in this correction.

Independent source/security receiving review, an actual corrected current-head
hosted dependency result, normal native/signing checks and final current-main
composition remain required for delivery. The original hosted failure stays
recorded; it is not rewritten as a pass.
