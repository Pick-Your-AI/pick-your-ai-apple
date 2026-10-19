# Apple #103: Dependency inventory and vulnerability response

Prepared for [Apple #103](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/103)
against main `a12ab324e499907bd15abf4b80709d0f02667ae1` on 2026-10-18. This is a
bounded repository dependency-control slice. The package manifests were inspected
as source; no release binary, provider credential or installed-device inventory was
available to this review. The independent receiving review and hosted dependency
API result must be attached to the delivering PR before this slice is accepted.

## Inventory at the inspected commit

| Surface | Dependency and version identity | Review boundary |
| --- | --- | --- |
| Native modules | Five first-party Swift packages: PlannerCore, PlannerData, PlannerTransfer, PlannerCatalog and PlannerUI. Their package dependency declarations use local paths only. | No third-party Swift package is declared at this exact source. PlannerTransfer and PlannerUI consume local PlannerData; PlannerData declares the CSQLite system-library wrapper. A future dependency or changed package manifest requires a new inventory review. |
| System runtime | Swift standard library; Foundation, SwiftUI, CryptoKit; system SQLite through CSQLite; Darwin on Apple and Glibc on the portable test host. | Supplied by the selected OS/toolchain, not independently pinned application packages. Exact shipped library versions, OS fixes and redistribution obligations require the actual signed release and its device/OS receipt. |
| Apple build tools | [Pinned Xcode 16.4 / build 16F6](../../App/toolchain.json), Swift 6 language mode and the workflow's recorded SDK/simulator versions. | The `macos-15` hosted image changes upstream. [Toolchain validation](toolchain-pin.md) records observed build identity and fresh-cache checks; it does not establish an immutable runner image or a security scan. |
| Python reference tools | `jsonschema==4.25.1`, `referencing==0.37.0`, `jsonschema-specifications==2025.9.1`, `attrs==26.1.0`, `rpds-py==0.30.0`, `PyYAML==6.0.3`, `typing-extensions==4.16.0`. | Exact declarations are in [requirements.txt](../../tools/conformance/requirements.txt). Package release hashes, a complete resolver lock and current vulnerability/license receipts are not supplied by version pins alone. These packages run during validation, not in the native app. |
| Transfer reference tools | `jsonschema[format]==4.26.0` is installed by the existing transfer workflow. | Format extras bring additional Python dependencies. That inline install and its transitive resolution are an explicit inventory gap for the dependency graph; a clean manifest diff cannot certify them. Lock, inventory and audit this environment before release qualification. |
| GitHub Actions already used | `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683`; `actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065`; `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02`. | Immutable source pins are present in the inspected workflows. Pinning does not prove their bundled Node dependencies are vulnerability-free. Review upstream advisories and the action's exact source when changing a pin. |
| Added dependency review action | `actions/dependency-review-action@907a6e9569212033966bc0b69d32473b046dd66b`, a GitHub-maintained source commit from 2026-10-16 whose metadata and instructions were directly inspected. | Its [action metadata](https://github.com/actions/dependency-review-action/blob/907a6e9569212033966bc0b69d32473b046dd66b/action.yml) requires Node 24. Its [documented license](https://github.com/actions/dependency-review-action/blob/907a6e9569212033966bc0b69d32473b046dd66b/LICENSE) is MIT. This metadata check is not a full audit of the action's bundled code or a pin of the hosted API/advisory database. |

Manifest SHA-256 receipts at the inspected commit:

| Path | SHA-256 |
| --- | --- |
| `Packages/PlannerCatalog/Package.swift` | `df9b59dcf932e71d75202bfe2d8ca512227997c5c316df766edb31930cc67fa7` |
| `Packages/PlannerCore/Package.swift` | `f58e02bf8fe1471534eaf54dd49804a6c6566bd00021eb3ce1f4d6d14a1e6748` |
| `Packages/PlannerData/Package.swift` | `6cdda5c0e1d933f2460a31ad71339dcd57bc1f3e78c83c28536b7e1a5f33c739` |
| `Packages/PlannerTransfer/Package.swift` | `4bf3eead2dfdce47f5cc3819f566256969ad8dd819e0598c2cdb765fdce9de88` |
| `Packages/PlannerUI/Package.swift` | `5713f342e9841c123b6dffcc629e90ab3c9ad6b74c4ec3e6e5e36026089dfa57` |
| `tools/conformance/requirements.txt` | `e56b1e9223306faefd848502e2b181a8cfa1ff674212f6c36fd7896999f2b3eb` |

The active native integration #198 changes local module wiring. Its final accepted
source must receive its own manifest inventory; this historical inventory does not
claim that another branch has been inspected or that future source is identical.

## Pull-request review behavior

The [dependency review workflow](../../.github/workflows/dependency-review.yml)
runs on normal `pull_request` events, including drafts. It has a read-only contents
token, no retained checkout credential, no PR-comment write permission and no
release secrets. It does not run on `pull_request_target`, change branch protection
or invoke an AI review service. It introduces no scheduled or paid external task.

The pinned GitHub action looks up dependency changes and advisory/license data.
All reported severities, from low upward, apply to runtime, development and unknown
scope. Warning-only mode is disabled. A dependency-graph/API failure remains a
failed check. The upstream action retries snapshot warnings for 120 seconds but
then proceeds with the available comparison, so those retries alone do not
establish complete source data. The whole job has a ten-minute timeout. GitHub documents public-repository availability and
the API/runtime requirements in its [upstream instructions](https://github.com/actions/dependency-review-action/blob/907a6e9569212033966bc0b69d32473b046dd66b/README.md).

The automatic license policy permits MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause,
ISC, PSF-2.0, Python-2.0, Zlib, CC0-1.0 and Unlicense. This is an engineering review
allowlist for this MIT-licensed repository. It is not a legal conclusion about an
uninspected package, its notices, embedded code, trademark or distribution terms.
The GitHub action evaluates SPDX expressions. A different license requires an
explicit, independently reviewed policy decision before adding the dependency;
the workflow contains no per-package or advisory exemption.

GitHub's action documents that an undetected license is reported without failing.
The supplementary [output guard](../../tools/security/check_dependency_review.py)
closes that specific gap: every `unresolved` entry fails, and an `unlicensed` entry
requires verified license evidence. The exact Action metadata gap,
[exact Transfer wheel classification](#exact-transfer-wheel-license-recovery) and
[exact conformance installer classification](typing-extensions-license-proof.md)
have separate source-verification paths. Every other `unlicensed` or
`forbidden` entry fails. All three arrays must be
present in their enclosing object; an absent category, wrong type or an unexpected
category fails. The raw dependency list can retain a null license even when the
action resolves and checks that license through GitHub's license API, so the
classified result controls acceptance. This is verified against the pinned
[license implementation](https://github.com/actions/dependency-review-action/blob/907a6e9569212033966bc0b69d32473b046dd66b/src/licenses.ts), not an assumed output shape.

Missing/malformed/truncated or duplicate-key review output also fails. The guard
requires explicit dependency/vulnerability arrays and complete changed-package
identity. An omitted legacy scope follows the upstream runtime interpretation;
an explicitly invalid scope fails, and all supported scopes are reviewed. It
rejects every reported added vulnerability. It prints aggregate counts, not raw
package metadata or payloads. Removed unsafe/unidentified dependencies can pass
when their replacement is reviewed and clean in this comparison.

The separate [snapshot verification step](../../tools/security/check_dependency_snapshots.py)
performs a read-only dependency-graph comparison at the **same base/head commit
SHAs from the pull-request event** after the action. The repository and API origin
are fixed; the token is never sent to a redirect or a pagination URL from another
origin, repository or commit pair. Every page's encoded snapshot-warning header
must be absent or decode to empty text. Malformed headers, remaining warnings,
incomplete pagination, API failure and mismatched dependency data fail. The full
normalized comparison must equal the action's dependency output, so a snapshot
that finishes only after an earlier partial action scan cannot supply a false
clean result. Changes in advisory or license metadata also require a fresh review.
The normalized projection/defaults match the pinned
[upstream schema](https://github.com/actions/dependency-review-action/blob/907a6e9569212033966bc0b69d32473b046dd66b/src/schemas.ts).

The verification bounds the total body to 1 MiB, pagination to twenty pages,
individual blocking reads to ten seconds, and processing to a sixty-second time
budget; a two-minute workflow step limit also applies. It does not silently
truncate a larger comparison. Its complete matching result establishes the
reported dependency-graph comparison for those commits, not coverage of
unsupported manifests, unsubmitted packages or every existing dependency.

The guard consumes action outputs through environment variables. It does not
interpolate dependency JSON into shell commands, reinterpret SPDX expressions,
fetch an alternative advisory feed, install a proposed dependency or infer that an empty
diff audited existing dependencies. Unsupported ecosystem coverage and unresolved
transitives remain review gaps. The check's existence does not prove it is a
branch-protection requirement.

The mandatory final guard also requires the original action outcome and a
successful exact-commit snapshot step. `continue-on-error` on the action allows
that guard to evaluate an observed failure; it does not accept the failure.
Absent, skipped, cancelled or unsupported outcomes fail. A failed action with
apparently clean or empty output also fails. Failed-action recovery requires one
of the separate exact Transfer or conformance proofs; the existing Action metadata-gap
recovery still requires the action to have succeeded. The final step runs with
`always()` so a skipped review cannot disappear from the acceptance decision.

## Exact pinned Action license recovery

After the [saved Dependency Graph enablement](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/230#issuecomment-6248379193),
unchanged source `915acc89cf135fdb1bda0b3704474c990c61b016` completed
[run 39113412122 attempt 2, job 117643998609](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39113412122/job/117643998609).
All 23 regressions, the upstream action and the exact snapshot comparison passed.
The final guard correctly rejected one unlicensed addition: the pinned review
Action had both `license: null` and `source_repository_url: null`. The two public
dependency rows and classified result are preserved in the
[observed-input fixture](../../tools/security/tests/fixtures/pinned-action-license-gap.json).
This failed run is not relabeled as a successful dependency review.

The exact Action's [MIT LICENSE](https://github.com/actions/dependency-review-action/blob/907a6e9569212033966bc0b69d32473b046dd66b/LICENSE)
was independently retrieved and inspected. Its immutable tree is
`b40f699a97606bd5e51943956ff4e9507ee1101f`, LICENSE blob
`cdfebd4e4322284fde560f21808182055976d9bf`, and 1,095 exact bytes have SHA-256
`399ebcd5cf53d2ba8f32e8d7c7aa77a64b959734f662c533f30b0e75d76012a1`.
The [retained licensed test copy](../../tools/security/tests/fixtures/dependency-review-action.LICENSE)
preserves those bytes and their notice.

For that single full matching added record, the guard can read the fixed GitHub
contents endpoint at the complete Action commit and require the exact file type,
path, blob, byte count, base64 encoding and SHA-256 above. The job supplies one
shared SPDX allowlist to the upstream action and guard; MIT must still be present.
Only a complete match resolves the one missing-source license result. Duplicate
or absent raw records, another manifest/name/PURL/version/scope, conflicting
license/source metadata, any vulnerable addition and every forbidden or unresolved
category retain rejection. Raw action and snapshot data remain unchanged; the
final aggregate report separately counts `pinned_license_resolutions`.

This read uses the existing read-only token only on the fixed GitHub API URL,
refuses redirects, accepts at most 64 KiB, and checks a ten-second deadline before
and after bounded reads with a ten-second socket timeout. A two-minute workflow
step bound also applies. Transport, metadata and content failures fail closed
without printing tokens or response bodies. No package is installed or executed.
The upstream `allow-dependencies-licenses` option remains absent: its pinned
[PURL matcher](https://github.com/actions/dependency-review-action/blob/907a6e9569212033966bc0b69d32473b046dd66b/src/purl.ts)
ignores versions and would exempt future package versions as well. No advisory
result, unknown license or future pin is exempted by this source proof.

The actual retained-input regression fails against the original guard and passes
with the immutable-license response supplied by a controlled HTTP double. All 31
local regression methods pass, including altered identities, duplicate/conflicting
records, removed MIT policy, changed license bytes/metadata, redirects, HTTP errors,
byte bounds and expired deadlines. A separate credential-free read of the actual
fixed public GitHub contents endpoint returned 2,542 bytes, SHA-256
`5f8227c354506f81d603b2c913b5c160badcb6a0eeaeaf1164e4634be46bb4a0`;
the real response verifier accepted its exact LICENSE metadata and MIT bytes.
This is a source-provenance API receipt, not a dependency advisory comparison.
The controlled tests exercise the real CLI entry point
but do not claim a hosted advisory or license scan. The corrected current-head
workflow must supply its own actual GitHub result before delivery. The exact
snapshot-completeness guard is unchanged. Existing bundled/transitive inventory,
release notices and the separate unacceptable-dependency/urgent-patch drill remain
required; this proves the inspected Action source license only.

## Exact Transfer wheel license recovery

[PR #266](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/266) at
`4b455d1efa8edf135bdba393089cca7ab32886ec` failed
[run 39140834572, job 117714734437](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39140834572/job/117714734437).
The dependency-comparison event base was
`1601ec4a1333fe2cea8871e32888e30c0b368aed`, with the PR head above. The actual
workflow checkout was `62d61aa6180dc4d3b22022c1b1afbb45a8e9f17d`, merging that head
into accepted main `17e03aa65c6f2b6e0465b4bab48787901fdf0523`. These are distinct
comparison and execution identities in the original log. The snapshot step
accepted all eleven compared rows without warnings and there were zero reported
vulnerabilities. The action rejected one `typing-extensions==4.16.0` addition in
`Packages/PlannerTransfer/Tools/requirements.txt`, with the composite expression
preserved in the [observed-input fixture](../../tools/security/tests/fixtures/pinned-transfer-license-conflict.json).
The original guard reproduced exit 1, one disallowed license and zero source
resolutions. An unmatched-manifest control also failed. These actual failures
remain part of the record.

The fixed [PyPI release](https://pypi.org/project/typing-extensions/4.16.0/) declares
`PSF-2.0`, which is already in the unchanged repository policy. Independent
inspection retrieved the complete wheel, read its `METADATA` declaration and
compared its embedded license byte for byte with the
[upstream LICENSE](https://github.com/python/typing_extensions/blob/f29cd28d8ed7642cafb1d18daf5aa41be6a5c0aa/LICENSE)
at the release's signed source commit. GitHub verified that commit's signature;
PyPI's trusted-publishing provenance identifies the same source commit. The
complete retrieved wheel was never installed or executed.

| Reviewed input | Exact bound |
| --- | --- |
| Transfer installer | 1,969 bytes; SHA-256 `49d2158183e44a47f0f66fd7ce6cb146ca52281015cfcd2e9dd2670724eb0344`. An [inert test fixture](../../tools/security/tests/fixtures/pinned-transfer-requirements.fixture) preserves the proposed installer bytes without adding its active manifest or feature to main. |
| Immutable wheel | `typing_extensions-4.16.0-py3-none-any.whl`, 45,571 bytes; SHA-256 `481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8`. The guard uses one fixed HTTPS artifact URL from that release. |
| Wheel metadata | `Name: typing_extensions`, `Version: 4.16.0`, `License-Expression: PSF-2.0`; 3,310 bytes with SHA-256 `b05084ca1d50879865178d9fff9fabeab61bdfb1f361bfbde95421ffc8f9be46`. |
| Embedded and upstream license | Both 13,936 bytes; SHA-256 `3b2f81fe21d181c499c59a256c8e1968455d6689d269aa85373bfb6af41da3bf`. |
| Signed source | Commit `f29cd28d8ed7642cafb1d18daf5aa41be6a5c0aa`, tree `9381f93c022005ef0f043b22c06be4e5205ecb9e`. |

The guard performs no installer or network lookup unless the original action
failed, snapshots succeeded, there are zero vulnerable additions, the existing
policy still includes `PSF-2.0`, and the single complete observed row matches in
both raw and forbidden outputs. All other license categories must be empty.
Missing, duplicate or conflicting raw records cannot borrow the proof. Another
manifest, version, scope, identity or classification remains rejected, including
the separately owned conformance lock proposal in
[PR #280](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/280).

For that exact case, the installer must be a regular, singly linked file of the
fixed size and digest. Nonblocking/no-follow file access rejects a missing file,
symlink, FIFO, directory, hardlink or changed bytes before network access. The
reviewed installer requires hashes and binary wheels and admits only the fixed
typing-extensions wheel hash for Python versions below 3.13. The fixed artifact
request carries no repository token, refuses redirects, uses at most 16 KiB per
read and accepts no more than the expected wheel length plus one overflow byte.
A ten-second socket timeout and a deadline checked before and after reads bound
retrieval; the existing two-minute final-step bound also remains. HTTP/transport,
length or digest failures retain rejection without printing payloads or tokens.
Only the complete reviewed bytes clear the one forbidden result and increment
`pinned_license_resolutions`; raw dependency/snapshot evidence is never rewritten.

The portable security suite passes all 43 methods: the original 31 plus twelve
Transfer cases. Transport unit tests use conspicuous controlled bytes with their
actual digest; they are not claims about the real wheel. Separately, the actual
unpatched CLI and immutable wheel recovered the captured eleven-row failure
with exit 0 and exactly one resolution. Four actual process controls retained
exit 1: an unmatched manifest, a `GPL-3.0-only` replacement classification, a
different added dependency with a low-severity vulnerability, and unexplained
upstream failure with clean output. Main without the qualifying change performs
no artifact lookup; the qualifying row with an absent or mismatched installer
fails. Byte bounds, transport/deadline errors, other categories and skipped or
missing outcomes are also covered by the portable suite.

This repair is prepared independently on main
`17e03aa65c6f2b6e0465b4bab48787901fdf0523`; it does not include the held Transfer
lock or native feature. Its source and hosted receiving checks still require
independent review. The #266 owner must receive this repair and obtain a fresh
successful exact-head dependency check before that failure is resolved. The
separate #280 proof must be composed and reviewed without broadening either
manifest's bound. No full dependency inventory, advisory baseline, native result
or complete #103 acceptance follows from this single artifact proof.

## Separate conformance and Transfer installer proofs

The [conformance proof](typing-extensions-license-proof.md) and the Transfer proof
above retain separate literal manifest paths, installer byte counts and SHA-256s.
Their previously reviewed row matchers and bounded artifact readers remain
unchanged. A successful lookup for one installer cannot supply the other's
required installer evidence, even though both bind the same immutable wheel.

Each matcher still requires one exact forbidden row, empty other categories and
one consistent raw package identity. A comparison containing both manifest rows
remains rejected, including a partial classification of only one of those rows.
No combined-row or partial recovery is introduced. The existing Action MIT proof,
generic policy, full snapshot comparison and unexplained-failure rejection remain
required. The final workflow guard always runs and receives the original Action
and snapshot outcomes.

The composed portable suite retains the original 31 methods, all 13 conformance
methods and all 12 Transfer methods. The two Transfer tests for an unreviewed
manifest now use an unrecognized third path; the separately supported conformance
path is covered by four additional boundary methods. Those cases require each
captured input to use its own lock, reject missing/swapped/changed matching locks
despite the other valid lock, reject mixed or partially classified two-manifest
comparisons, and reject a third manifest with both valid locks present. Controlled
transport bytes remain inert fixtures, not a new immutable-wheel or hosted receipt.
The original seven-row and eleven-row source observations above retain their own
identities. Fresh receiving checks must record their complete actual comparison.

## Observed local rejection and recovery

The portable implementation uses Python's standard library only. On Python 3.12.14
on 2026-10-18, the initial `915acc89` source's 23 regression methods passed. Thirteen output/CLI cases cover
all three dependency scopes, low-severity rejection, each actual license category,
upstream license resolution, malformed/duplicate/oversized/deep output, missing
secondary output, removal, urgent-update recovery and diagnostic payload exclusion.
Ten controlled comparison cases cover exact event identities, all-page warning
checks, snapshot/advisory changes after an earlier scan, same-origin pagination,
byte/page bounds, pinned schema defaults and redirect/token protection. These
comparison tests make no network requests.

Independent review found that original candidate `81d29bb` incorrectly expected
one license-result array. The [retained defect/recovery receipt](dependency-review-contract-regression.json)
replays the pinned clean three-array object against that exact original source:
it fails there and succeeds with the corrected source. Both source hashes and
observed CLI results are retained. The [pinned protocol fixtures](../../tools/security/tests/fixtures/pinned-action-contract.json)
link exact upstream source/test hashes and model empty, licensed, forbidden,
unresolved and unlicensed results. They are source-derived protocol cases, not
fabricated hosted advisory scan receipts.

The [retained six-case rehearsal](dependency-review-rehearsal.json) from that source invokes the
actual guard in separate processes with its synthetic input variables.
It preserves that historical guard's SHA-256 and Python version. Replaying the
corrected guard supplies explicit synthetic action/snapshot outcomes, retains all
six required exits and additionally reports zero
`pinned_license_resolutions` for these unrelated synthetic cases. The vulnerable and unapproved
packages are inert JSON descriptions with conspicuous synthetic identities; they
are never downloaded, resolved or executed.

| Rehearsal | Required result |
| --- | --- |
| No dependency changes with explicit complete output | Exit 0; zero additions and removals. |
| Synthetic critical vulnerability in a development dependency | Exit 1. |
| Synthetic action-classified unacceptable license | Exit 1. |
| Added dependency in the action's unlicensed category | Exit 1 even though upstream does not fail unlicensed results. |
| Remove the unsafe version and add a reviewed replacement | Exit 0; one removal and one addition. |
| Replacement present but the license-review output is missing | Exit 1; no clean result inferred. |

Reproduce from the repository root:

```sh
python3 -m unittest discover -s tools/security/tests -v
python3 tools/security/rehearse_dependency_review.py
git diff --check
```

This historical local review-output receipt does not itself establish GitHub
dependency discovery, advisory lookup or license classification. The subsequent
hosted exercise below supplies an actual unacceptable-license rejection and
correction for one supported inert manifest. It does not turn the synthetic
vulnerability inputs above into an observed advisory finding.

## Observed hosted license rejection and correction

The [structured hosted receipt](dependency-review-hosted-drill.json) records
[never-merge draft #259](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/259),
closed without merge at **2026-10-18 11:44:57 UTC**. Its isolated test base
`e2c3998c93ef6a672eb3789d7f6bce0f20e0c181`, tree
`e91780c2d64888f1195cb40166a1bdc34fe932d8`, combines the exact reviewed policy
source `c939aaec31afa55efe9c594495ba7a6831711d6f` and locked reference source
`3cfa7c523c95d5ebcb3518414ba157cd83cc8ec2`. The receipt pins their real ordered
parents, all eight inspected workflows and both literal installer inputs.
This test composition is separate from the product signing/main routes
[#230/#257](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/257) and
[#251](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/251).

The original head `36082b8bf2bbddefbf03788c54af34fabd3147e4` introduced only the
five-line inert `tools/security/drills/requirements.txt`. In
[run 39123830465, job 117664719345](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39123830465/job/117664719345),
all 31 security tests passed, the exact base/head snapshot matched one row with
no warnings, and GitHub classified `rfc3987@1.3.8` as `GPL-3.0-or-later`.
The pinned Action rejected that license; the final guard recorded
`accepted=false`, one disallowed license, zero other rejection categories and
exit status 1. A scan/transport error was not substituted for the required result.

After that observed failure was retained, a guarded branch advance published
`13c8f5f42db5f63632bc33346b07c018eb02cc57` with the failure head as its sole
parent. Only the inert manifest changed; its unacceptable declaration was removed
completely and all 146 other leaves remained identical. The replacement
`six==1.17.0` is an MIT metadata control, not a functional RFC-parser replacement.
In [run 39124371655, job 117666294093](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39124371655/job/117666294093),
all 31 tests passed again, the exact corrected snapshot matched one MIT row
without warnings, and the guard returned `accepted=true` with every rejection
count zero. Both actual checkout merges, source trees, full result objects,
job identities and decoded-log SHA-256 values are retained in the structured
receipt. Its [independent source/control review](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/259#pullrequestreview-5562767217)
covers the manifest strings and no-install boundary; receiving review of this
completed record belongs to its delivering PR.

Neither declaration was an installer input, and the draft was closed without
merging its failure head, correction head or test base into product history.
All ten unrelated drill-native runs were read back as cancelled; they supply no
passed product gate. No unsafe package was installed or executed by this exercise.

The isolated base also uses the [reviewed locked validator environment](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/3cfa7c523c95d5ebcb3518414ba157cd83cc8ec2/Packages/PlannerTransfer/Tools/reference-environment.md),
whose [provenance record](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/3cfa7c523c95d5ebcb3518414ba157cd83cc8ec2/Packages/PlannerTransfer/Tools/requirements-provenance.json)
pins nine conditional package declarations and 17 compatible wheel hashes.
[Actual transfer run 39121450000, job 117658223143](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39121450000/job/117658223143)
installed eight applicable packages with required hashes on Python 3.14.7;
`typing-extensions` was correctly excluded by its Python-below-3.13 marker.
The installed closure passed `pip check`, all six frozen hashes, 129 shared
cases, 29 kinds/1,635 catalog cases, 36 Swift tests and the unsigned simulator SDK
build on Xcode 16.4 / 16F6. This is exact-source transfer evidence, not all final
product gates, an installed release or a baseline vulnerability audit.

This exercise establishes the bounded review/removal/recovery path. It does not
perform a live credential rotation or establish shipped dependency versions,
system-library advisories, bundled Action dependency coverage, device/service
security acceptance or release approval. The responsibilities and remaining
criteria below continue to apply.

## Response responsibilities and patch procedure

The user delegated project engineering decisions and independent technical
reviews to the project controller. That permits the following repository work;
it does not invent an Apple Developer identity, secret custodian or service
operator. Required receiving roles come from [#103](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/103)
and the [threat register's T11](issue-98-data-threats.md).

| Responsibility | Accountable execution boundary |
| --- | --- |
| Intake and triage | Project controller records the exact advisory, affected pin, dependency path, runtime/build scope, reproducible version range and whether any deployed artifact is actually affected. Unknown exposure is recorded as unknown. Never publish a secret or private workload in an issue. |
| Patch preparation | The dependency's implementation owner supplies a scoped version/pin update, source/release provenance, dependency/notice changes and regression evidence. No arbitrary advisory exemption, removed check or warning-only change is a patch. |
| Independent review | An independent security/privacy engineering reviewer verifies applicability, the candidate diff, clean dependency metadata, new notices and the negative-to-recovery receipt. The affected service reviewer is also required if a deployed boundary is involved. An agent review must be identified as such. |
| Delivery and release | The project controller may perform the already-authorized signed/checked repository integration. The actual release operator verifies the built artifact and deployment boundary through the existing release issues. A merged version bump does not establish that every installed or deployed copy was replaced. |
| Credential rotation | The real provider/signing credential custodian must revoke/replace an exposed credential through its authoritative service, scope the replacement, verify old access fails and new authorized access works, and inspect audit evidence. No provider, signing identity or live credential is configured for this slice, so this actual operator drill remains unexecuted. |

For an urgent update, first determine whether the vulnerable dependency is present
in the affected build and which permissions/data it could reach. Isolate or stop
the affected project workflow through normal authorized controls if necessary;
preserve the incident evidence and unrelated workloads. Prepare the smallest
supported fixed pin or remove the dependency, then reproduce the affected failure
and complete the current package/app gates. Review changed licenses and bundled
transitives. Obtain independent receiving review, integrate normally, and verify
the authoritative installed/deployed version before marking that exposure fixed.

When credential exposure is possible, patching the package does not revoke an old
credential. The custodian's separate rotation receipt must record provider/resource
identity, old-credential rejection, replacement scope, successful authorized use
and audit disposition without including credential values. No such real rotation
is claimed by the synthetic dependency-update rehearsal.

## Criterion 2 receiving

The [actual receiving decision](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/103#issuecomment-6266646864),
posted on **2026-10-19 at 11:57:25 UTC**, accepts the second literal criterion only.
The coordinating ChatGPT agent acted as the delegated security/privacy engineering
reviewer after a separate in-session Apple reviewer read the complete record,
structured receipt and fresh issue discussion. The coordinating reviewer then
corroborated both complete original hosted logs, including their byte counts,
SHA-256s, exact snapshots and guard results, against the
[historical hosted receipt](dependency-review-hosted-drill.json). This is receiving
review of the original #259 execution; no new test run is claimed.

That JSON receipt reached valid-signed main through
[#293](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/293) at
`71db949333d94958d7d7909a1dd16c51c2421e2e` and remains unchanged at inspected main
`63df6b24b7bee4272bdcc8e75ad679202089110b`. The current Markdown record includes
later source-control amendments with their own historical identities and limits.
The accepted result is the unacceptable-license rejection/removal/recovery
rehearsal and the documented triage/rotation responsibilities described above.

Criteria **1 and 3** and all four implementation subtasks remain open. In particular,
**"Test urgent patch and credential rotation process" remains incomplete**: its
review/removal/recovery half is evidenced, but the actual credential-rotation test
was not performed. The current baseline/transitive inventory, applicable actual
custodian/service review and device/server/release checks retain their evidence
requirements. Whole #103 remains open; the historical JSON is unchanged.

## Criterion disposition

| Exact #103 criterion | Supplied evidence | Remaining acceptance |
| --- | --- | --- |
| Release dependencies and response path have reviewed evidence. | Historical source inventory at the exact main commit; independently reviewed PR policy and locked validator source; actual hosted license drill and exact-source transfer gate; response and receiving responsibilities. | Current baseline/transitive vulnerability/license inventory, actual signed product/destination evidence, final signed release inventory and affected operator/service review where applicable. A clean changed-manifest scan does not audit the baseline. |
| Introduce a vulnerable or unacceptable-license dependency in review and rehearse an urgent patch; document triage/rotation responsibilities without storing credentials. | The historical local regressions and six synthetic cases remain distinct. Closed, unmerged #259 now supplies actual unacceptable-license discovery, exact-snapshot rejection, declaration removal and corrected success, with 31 security tests passing on each head. Responsibilities and credential-free rotation receipt requirements are documented. | Accepted for criterion 2 by the [2026-10-19 receiving decision](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/103#issuecomment-6266646864). The separate credential-rotation test remains unexecuted. This observed license exercise is not an observed vulnerability/advisory or installed-release patch. |
| The dependency inventory and vulnerability-response drill is linked with criterion results, exact versions, limitations and receiving-review disposition. | This historical inventory, immutable locked-environment provenance, source-hashed local rehearsal, structured hosted failure/recovery receipt and explicit criteria/limits. | Link the independently reviewed signed product and record deliveries from #103, retain affected receiving dispositions, and close only criteria actually supported by those receipts. |

The repository guard and local drill advance #103; they do not close the full work
package or the separate device, service, signing, release or security findings.
