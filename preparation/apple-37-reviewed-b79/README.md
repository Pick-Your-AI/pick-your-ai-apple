# Apple #37: incremental archive of the reviewed receiving preparation

This checkpoint preserves exact unsigned local commit
`4f4021839f268294ae7d132efdc1be7dc0bc5bd0`, tree
`b79f9a53a0c5a99de95fb228c7677fe8e5a61aad`, without modifying any implementation
or repeating the stalled whole-fixture upload. Its 71,057-byte incremental Git
bundle is imported **after** the unchanged
[original reviewed preparation archive](../apple-37-reviewed-08e/README.md).
Both archives and the specified public Git history restore all 202 final files,
modes, original commit bytes and ordered parents.

The containing archive branch is a recovery record. It is not the intended
source branch, a receiving PR, signed main delivery, native qualification or
[Apple #37 acceptance](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37).
This is the reviewed historical composition on accepted `71db9493`; it does not
claim to contain later accepted-main changes or the subsequent correction of
the known macOS evidence-harness failure.

## What the incremental archive preserves

The original archive's 1,273,770-byte neutral fixture remains exactly Git blob
`69718936a83b83e91aca7a492e48720fd2fe6cce`, SHA-256
`499fd9a01780ac42fa9bf2ab8cf9e1195db27321fec36040451b553a8b9ea5f9`.
Its 223 unique cases still contain 141 accepted and 82 rejected outcomes.
The incremental bundle reuses that recovered object; it does not contain a new
producer definition, altered fixture or replacement wire representation.

The exact preserved local source history is:

| Commit | Tree | Ordered parents and purpose |
| --- | --- | --- |
| `6eec8878` | `08e54247` | Sole `7d9724b1`; original nineteen-path preparation, recovered from the original archive. |
| `24d23c19` | `9b4147a6` | Sole `6eec8878`; independently reviewed accepted-storage and strict 30-method inventory supplement, with historical receipts retained. |
| `07d837ef` | `62c8731b` | `4841d1c3`, then `24d23c19`; reviewed placement/current-71 receiving composition plus the exact storage and acceptance-record conflict resolutions. |
| `d53ba455` | `28894140` | `07d837ef`, then `fddd221f`; automatic carry of the corrected dedicated evidence test host. |
| `4f402183` | `b79f9a53` | Sole `d53ba455`; one documented storage-method count corrected from 29 to 30, with all other 201 leaves unchanged. |

These are source and archival identities. In particular, prepared placement
commit `4841d1c3` and evidence source `fddd221f` are not relabeled as accepted
main by appearing in this history. The actual final source review covered the
two conflict resolutions, all 202 leaves, the complete original execution
receipts and the final one-token documentation change.

## Required public history and the original archive

[CHECKPOINT.json](CHECKPOINT.json) pins the final source, the original archival
container, both ordered parts, every bundle prerequisite and the complete raw
fixture identity. The incremental bundle is 71,057 bytes, SHA-256
`ec29cbde71d09b385fddfaf585747fefa011ffcceea218fb2f10c51f5e8a6952`.
Its parts contain 50,000 and 21,057 bytes. These are transport segments of an
ordinary Git bundle; they do not change the recovered repository files.

The full public history of accepted main
`71db949333d94958d7d7909a1dd16c51c2421e2e` supplies prerequisites `13e67df8`,
`bcf4c771` and `71db9493`. Public reviewed source
`7d9724b16136546b686d87f29acf9bd95ca9c2eb` is the original archive's prerequisite.
Recovering that archive supplies `6eec8878` and its original wire blob.
The exact incremental bundle header therefore requires five commits:

```text
13e67df89309289b42fd9302c5908041739d9d11
bcf4c771641e62b30812e67bff86cf6b221c92cb
6eec8878e1456d2e7cad78399702a33461093ce8
7d9724b16136546b686d87f29acf9bd95ca9c2eb
71db949333d94958d7d7909a1dd16c51c2421e2e
```

First use the original directory's explicit-check reconstruction recipe to
produce `/tmp/apple37-reviewed-preparation.bundle`. Its expected length is
97,763 bytes and its SHA-256 is
`a9783ffd55b34327f5ccaf98f493e327c62a651279e88e82585c50a5fa8431e4`.
The original four archival files remain unchanged.

## Reconstruct this incremental bundle

Run the following from this directory. All identities are fixed in the recipe;
changing the manifest or parts fails before an output file is created. The
checks remain active under optimized Python, and an existing output is refused.

```sh
python3 - /tmp/apple37-reviewed-b79-incremental.bundle <<'PY'
import hashlib
import json
from pathlib import Path
import sys


def require(condition, message):
    if not condition:
        raise SystemExit(message)


require(len(sys.argv) == 2, "Supply the new incremental bundle output path")
expected = json.loads(r'''
{
  "format": "git-bundle-incremental-checkpoint-1",
  "sourceCommit": "4f4021839f268294ae7d132efdc1be7dc0bc5bd0",
  "sourceTree": "b79f9a53a0c5a99de95fb228c7677fe8e5a61aad",
  "sourceParent": "d53ba455dd2ab7169c938408758807904b78d0ad",
  "containedRef": "refs/heads/preparation/apple-37-reviewed-b79-local-29a3",
  "sourceLeaves": 202,
  "baseArchive": {
    "containerCommit": "78cb2675356e7d00167b645cc7c993d2425fd2fa",
    "containerTree": "b37348542be960a426acf2e4ec9307954643be0f",
    "directory": "../apple-37-reviewed-08e",
    "sourceCommit": "6eec8878e1456d2e7cad78399702a33461093ce8",
    "sourceTree": "08e54247b998d005ed831bfaeabad7731f3e7a8a",
    "containedRef": "refs/heads/preparation/apple-37-local-29a3",
    "bundleBytes": 97763,
    "bundleSHA256": "a9783ffd55b34327f5ccaf98f493e327c62a651279e88e82585c50a5fa8431e4"
  },
  "publicBaselines": [
    {
      "commit": "71db949333d94958d7d7909a1dd16c51c2421e2e",
      "role": "Accepted main used by this historical receiving composition; fetch its complete public history."
    },
    {
      "commit": "7d9724b16136546b686d87f29acf9bd95ca9c2eb",
      "role": "Public reviewed prerequisite source for the original archive; not an accepted-main delivery."
    }
  ],
  "bundlePrerequisites": [
    "13e67df89309289b42fd9302c5908041739d9d11",
    "bcf4c771641e62b30812e67bff86cf6b221c92cb",
    "6eec8878e1456d2e7cad78399702a33461093ce8",
    "7d9724b16136546b686d87f29acf9bd95ca9c2eb",
    "71db949333d94958d7d7909a1dd16c51c2421e2e"
  ],
  "bundleBytes": 71057,
  "bundleSHA256": "ec29cbde71d09b385fddfaf585747fefa011ffcceea218fb2f10c51f5e8a6952",
  "parts": [
    {
      "path": "apple37-reviewed-b79-incremental.bundle.part-01",
      "bytes": 50000,
      "sha256": "5373c665130b03a8f9c00a794c2b0531907f437cda09c9bdc11268e0e1e80ecc",
      "gitBlob": "c6caad61f250dbe40542b639909a4361f1c6f684",
      "base64Bytes": 66668
    },
    {
      "path": "apple37-reviewed-b79-incremental.bundle.part-02",
      "bytes": 21057,
      "sha256": "8687266cc8bd6f34b11a38c891f8b9a40d33d2e46ccc356c3fe5728a1a2aa531",
      "gitBlob": "471781001a42cea5dd8279f43b93ad8c8ca46c4a",
      "base64Bytes": 28076
    }
  ],
  "wireFixture": {
    "path": "Packages/PlannerConformance/Tests/PlannerConformanceTests/Fixtures/cross-client-v1.json",
    "bytes": 1273770,
    "sha256": "499fd9a01780ac42fa9bf2ab8cf9e1195db27321fec36040451b553a8b9ea5f9",
    "gitBlob": "69718936a83b83e91aca7a492e48720fd2fe6cce",
    "cases": 223,
    "accepted": 141,
    "rejected": 82
  },
  "status": "Recoverable exact reviewed historical source archive only. No intended source branch, accepted-main delivery, native readiness, new behavior execution or issue completion is established by this packaging."
}
''')
manifest = json.loads(Path("CHECKPOINT.json").read_text(encoding="utf-8"))
require(manifest == expected, "Checkpoint identity or ordered parts differ")
chunks = []
for part in expected["parts"]:
    data = Path(part["path"]).read_bytes()
    require(len(data) == part["bytes"], "Part length differs: " + part["path"])
    require(hashlib.sha256(data).hexdigest() == part["sha256"],
            "Part SHA-256 differs: " + part["path"])
    git_blob = hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()
    require(git_blob == part["gitBlob"], "Part Git identity differs: " + part["path"])
    require(4 * ((len(data) + 2) // 3) == part["base64Bytes"],
            "Part transport length differs: " + part["path"])
    chunks.append(data)
bundle = b"".join(chunks)
require(len(bundle) == expected["bundleBytes"], "Incremental bundle length differs")
require(hashlib.sha256(bundle).hexdigest() == expected["bundleSHA256"],
        "Incremental bundle SHA-256 differs")
with Path(sys.argv[1]).open("xb") as output:
    output.write(bundle)
print(expected["sourceCommit"], expected["sourceTree"])
PY
```

## Import both archives into a new local Git database

Choose an unused recovery directory. Fetch complete public history rather than
a depth-limited baseline; no existing checkout or branch needs replacement.

```sh
git init --bare /tmp/apple37-b79-recovered.git
git -C /tmp/apple37-b79-recovered.git fetch --no-tags https://github.com/Pick-Your-AI/pick-your-ai-apple.git 71db949333d94958d7d7909a1dd16c51c2421e2e:refs/heads/public-accepted-71 7d9724b16136546b686d87f29acf9bd95ca9c2eb:refs/heads/public-reviewed-7d
git -C /tmp/apple37-b79-recovered.git bundle verify /tmp/apple37-reviewed-preparation.bundle
git -C /tmp/apple37-b79-recovered.git fetch /tmp/apple37-reviewed-preparation.bundle refs/heads/preparation/apple-37-local-29a3:refs/heads/recovered-original-08e
git -C /tmp/apple37-b79-recovered.git bundle verify /tmp/apple37-reviewed-b79-incremental.bundle
git -C /tmp/apple37-b79-recovered.git fetch /tmp/apple37-reviewed-b79-incremental.bundle refs/heads/preparation/apple-37-reviewed-b79-local-29a3:refs/heads/recovered-reviewed-b79
git -C /tmp/apple37-b79-recovered.git rev-parse refs/heads/recovered-reviewed-b79
git -C /tmp/apple37-b79-recovered.git rev-parse refs/heads/recovered-reviewed-b79^{tree}
git -C /tmp/apple37-b79-recovered.git fsck --strict --no-dangling
```

The final commit must be `4f4021839f268294ae7d132efdc1be7dc0bc5bd0` and its
tree must be `b79f9a53a0c5a99de95fb228c7677fe8e5a61aad`. Its sole parent is
`d53ba455dd2ab7169c938408758807904b78d0ad`. The recovered wire path and complete
length/hash are pinned in the manifest; Git preserves that exact original blob.
A separate worktree can be created from the recovered local ref for inspection.

## Actual recovery proof and retained execution boundaries

On 2026-10-18, both baselines were fetched directly from the public repository
into a new bare Git database with no alternates and no shallow history. The
original wire object and final local source were absent before their respective
archive imports. Both bundle verifications/imports and strict Git object checks
passed. The original 177-leaf tree, all 202 final files/modes, five original
commit objects with their ordered parents, and the entire raw 223-case fixture
matched the reviewed local objects. The operation ran from
19:48:37.237595 to 19:48:38.367276 UTC (1.129743181 seconds). Its complete
1,709-byte original log has SHA-256
`649a3c11499151234c3ef13d47791755eb1f9262f762dcb3a7f354283c409f99`.
This is an actual recovery/byte-preservation check; no application or conformance
behavior was executed by that check.

The literal reconstruction recipe also passed 24 actual cases under both
`-OO` and `PYTHONOPTIMIZE=2`: the valid bundle matched exactly, while changed or
truncated parts, fixed-identity drift, an existing output and a missing output
argument were rejected without replacing or creating an unintended output.
The complete 848-byte original log has SHA-256
`fc7b078398e9310362fb6259bd7f045ae8f5baca0fa5874ba2e0162fbb26675d`.
These checks exercise archival reconstruction, not application behavior.

The reviewed source retains the following distinct execution scopes:

| Evidence | Exact executed scope retained |
| --- | --- |
| Python harness | 45 passing methods on `28894140`, original log 7,949 bytes / SHA-256 `3e7bb43270beb402ee225eea70cb8da74253531e7c14e700f7c6f726eeb5c013`. The final `b79f9a53` change is the one documentation token only. |
| Swift wire consumer | Four methods and all 223 typed observations on `28894140`, original Linux log 34,497 bytes / SHA-256 `0a83ac5912773377877877580d4439a36d1dd54051764b7e39f0b3c37907e3f0`. The prior loader exit 127 happened before compilation/tests and remains separate. |
| Swift local storage | The 30-method/20-observation Linux execution belongs to `04d44920`, original log 13,955 bytes / SHA-256 `1bd55aa33c5b262b000faf77fe2c3a055bdf4f6f0f37cabe19eb47e7530a81cc`. Exact source/receipt preservation was reviewed through `9b4147a6` and the final union. The earlier compiler SIGILL ran no tests; the later three process-exit replay points have their own execution times. |
| Evidence rendering | The canonical dedicated-host source received actual four-method iPhone and iPad results at prepared `e79c39a8`. Its separate macOS job `117734702792` compiled and launched the app but failed all four methods at the case-readiness assertion before content assertions; no macOS rendering pass is claimed. |

The complete failed macOS log is 340,591 bytes, SHA-256
`5eccaf48be5360aeb3d708de6004dfb7aec1525f36c247ea3362e21895d8e154`.
The active canonical #277 owner retains the correction lane. This archive does
not substitute for that fix, fresh current-main composition, required native
receiving checks, independent receiving review or normal signed delivery.
The original empty-accessibility-tree and architecture compilation failures
also remain historical failures. No Android implementation, production evaluator
parity, physical-device, store or release evidence is inferred. Refs #37.
