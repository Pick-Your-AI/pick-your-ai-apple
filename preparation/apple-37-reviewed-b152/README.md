# Apple #37: archive of the reviewed current-storage preparation

This checkpoint preserves unsigned local commit
`37792e22b2fbe7997e05681f6d09c4053591fd1f`, tree
`b152fe7fb027731b9e7847d55f7ba749bedb8cdd`, with all **211** files and modes.
Its 32,781-byte ordinary Git bundle is a third incremental transport step after
the unchanged [original 08e archive](../apple-37-reviewed-08e/README.md) and
[reviewed b79 archive](../apple-37-reviewed-b79/README.md).

The container preserves recoverable source. The intended source branch remains
unpublished; this archive is not a receiving PR, signed-main delivery, current
native qualification or [Apple #37 completion](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37).
The source composition was independently reviewed on accepted main `40ca8ed3`
with canonical rendering correction `35d94b9a`. Actual successor native and
receiving gates remain separate. The two previous archive directories and every
other file in their public container `a8084fc9` remain unchanged.

## Preserved source and exact public inputs

The recovered wire fixture remains the original 1,273,770-byte Git blob
`69718936a83b83e91aca7a492e48720fd2fe6cce`, SHA-256
`499fd9a01780ac42fa9bf2ab8cf9e1195db27321fec36040451b553a8b9ea5f9`:
223 unique cases, 141 accepted and 82 rejected. The new archive reuses the
previously recovered blob. It changes no fixture representation or definition.

| New local commit | Tree | Ordered parents and preserved purpose |
| --- | --- | --- |
| `56723137` | `f912bae3` | Accepted `791c3558`, then archived `4f402183`; earlier current-main composition. |
| `1be65c1f` | `b61b6814` | `56723137`, then canonical `013acc54`; the earlier native-window correction. |
| `f0a51ac2` | `c0c92cc9` | Accepted `cd098e8e`, then `1be65c1f`; reviewed 31 accepted storage methods plus four migration methods, with exact observation guards. |
| `2a77c72d` | `bcae86ef` | Sole `f0a51ac2`; three reviewed Markdown receipt updates, including distinct Android receiving evidence and the original ENOSPC/recovery results. |
| `b240ee5d` | `e75a6f25` | Accepted `40ca8ed3`, then `2a77c72d`; exact accepted #35 completion row with unchanged #36/#37 rows. |
| `37792e22` | `b152fe7f` | `b240ee5d`, then canonical `35d94b9a`; the exact two-file macOS report-scroll correction. |

The final carry from `bcae86ef` changes only the accepted #35 index row and the
two canonical rendering blobs; all 208 other files/modes remain exact. The
whole source includes 40 feature paths and 171 unchanged accepted-main leaves.
Full local commit IDs, trees and ordered parents are fixed in
[CHECKPOINT.json](CHECKPOINT.json), together with every archive prerequisite.
These local historical commits do not acquire an accepted-main or native-pass
status merely by being recoverable.

The bundle requires these exact commits:

```text
4f4021839f268294ae7d132efdc1be7dc0bc5bd0
791c355812bfbbf8003941b59734118011d4734a
40ca8ed3065c04b63dc05e0e26ae0e84489083bf
cd098e8e19f5e4a1d90112379bc8ca089d81ec93
35d94b9a2e3e6213856b883092a8983452cee898
013acc542acdd83b18091a881ca6e2e744174c91
```

Fetch the complete public histories of accepted
`40ca8ed3065c04b63dc05e0e26ae0e84489083bf` and reviewed rendering source
`35d94b9a2e3e6213856b883092a8983452cee898`. Their ancestors supply the public
prerequisites, including the original `7d9724b1` source and historical `71db9493`
main used by the previous archives. Importing the two unchanged archives
supplies local `4f402183`. No shallow or alternate object database is required.

## Reconstruct the new bundle

Use the two previous directories' recipes first to produce their fixed
97,763-byte and 71,057-byte bundles. Then run this recipe from the current
directory with an unused output path. It binds the entire manifest, source,
public/prior-archive dependencies, ordered local history, part and original wire
identity to reviewed constants. All checks use explicit failures and remain
enabled with Python optimization. The exclusive output mode preserves existing
files. This is a transport recipe; no implementation file is rewritten.

```sh
python3 - /tmp/apple37-reviewed-b152-incremental.bundle <<'PY'
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
  "sourceCommit": "37792e22b2fbe7997e05681f6d09c4053591fd1f",
  "sourceTree": "b152fe7fb027731b9e7847d55f7ba749bedb8cdd",
  "sourceParents": [
    "b240ee5db68d9213bd308e1394ef4b6a3dcf73c4",
    "35d94b9a2e3e6213856b883092a8983452cee898"
  ],
  "containedRef": "refs/heads/preparation/apple-37-reviewed-b152-local-29a3",
  "sourceLeaves": 211,
  "baseArchive": {
    "containerCommit": "a8084fc926bcf6eba6dc04a55e8568f36ede4c1d",
    "containerTree": "1b8a57a75ec9a19e3782a996ae00478a40185f41",
    "directory": "../apple-37-reviewed-b79",
    "sourceCommit": "4f4021839f268294ae7d132efdc1be7dc0bc5bd0",
    "sourceTree": "b79f9a53a0c5a99de95fb228c7677fe8e5a61aad",
    "containedRef": "refs/heads/preparation/apple-37-reviewed-b79-local-29a3",
    "bundleBytes": 71057,
    "bundleSHA256": "ec29cbde71d09b385fddfaf585747fefa011ffcceea218fb2f10c51f5e8a6952",
    "originalDirectory": "../apple-37-reviewed-08e",
    "originalBundleBytes": 97763,
    "originalBundleSHA256": "a9783ffd55b34327f5ccaf98f493e327c62a651279e88e82585c50a5fa8431e4"
  },
  "publicBaselines": [
    {
      "commit": "40ca8ed3065c04b63dc05e0e26ae0e84489083bf",
      "role": "Accepted main at this source-composition review; complete public history supplies its prior accepted commits."
    },
    {
      "commit": "35d94b9a2e3e6213856b883092a8983452cee898",
      "role": "Canonical reviewed rendering source; complete public history supplies the original and intermediate rendering prerequisites. Native successor qualification remains pending."
    }
  ],
  "bundlePrerequisites": [
    "4f4021839f268294ae7d132efdc1be7dc0bc5bd0",
    "791c355812bfbbf8003941b59734118011d4734a",
    "40ca8ed3065c04b63dc05e0e26ae0e84489083bf",
    "cd098e8e19f5e4a1d90112379bc8ca089d81ec93",
    "35d94b9a2e3e6213856b883092a8983452cee898",
    "013acc542acdd83b18091a881ca6e2e744174c91"
  ],
  "bundleBytes": 32781,
  "bundleSHA256": "4e0ce508996d5e928de0d5c4309a4b3929ee55da8ec2ddc8b15d1c4933898ae9",
  "parts": [
    {
      "path": "apple37-reviewed-b152-incremental.bundle.part-01",
      "bytes": 32781,
      "sha256": "4e0ce508996d5e928de0d5c4309a4b3929ee55da8ec2ddc8b15d1c4933898ae9",
      "gitBlob": "a442bf353e192281f45d5a9be2c5c7e11eb6a47a",
      "base64Bytes": 43708
    }
  ],
  "localHistory": [
    {
      "commit": "567231376dbee275ac4494fd08cd5ab17fd06123",
      "tree": "f912bae3fcffe885c3d002de53b42d5823438915",
      "parents": [
        "791c355812bfbbf8003941b59734118011d4734a",
        "4f4021839f268294ae7d132efdc1be7dc0bc5bd0"
      ],
      "subject": "Prepare the reviewed conformance fixtures on accepted Apple main"
    },
    {
      "commit": "1be65c1f108eeee395f717cf2e4df867c6b1cd10",
      "tree": "b61b6814bf41b275c2bb51afacdb3d1dc17ab442",
      "parents": [
        "567231376dbee275ac4494fd08cd5ab17fd06123",
        "013acc542acdd83b18091a881ca6e2e744174c91"
      ],
      "subject": "Preserve the current 791 conformance composition locally"
    },
    {
      "commit": "f0a51ac21690bcbcd9893094e3f724cb4544aa87",
      "tree": "c0c92cc98fa6537ff0b28b824f746270bcbf4e6d",
      "parents": [
        "cd098e8e19f5e4a1d90112379bc8ca089d81ec93",
        "1be65c1f108eeee395f717cf2e4df867c6b1cd10"
      ],
      "subject": "Receive accepted storage inventory in reviewed conformance preparation"
    },
    {
      "commit": "2a77c72d504e35329fe42b19d6de2dfe08807ba8",
      "tree": "bcae86ef668a6177f58787e89f1408919ddb285d",
      "parents": [
        "f0a51ac21690bcbcd9893094e3f724cb4544aa87"
      ],
      "subject": "docs: retain exact conformance receiving and recovery evidence"
    },
    {
      "commit": "b240ee5db68d9213bd308e1394ef4b6a3dcf73c4",
      "tree": "e75a6f253ae6bc65526bf1d6f02060e399b11036",
      "parents": [
        "40ca8ed3065c04b63dc05e0e26ae0e84489083bf",
        "2a77c72d504e35329fe42b19d6de2dfe08807ba8"
      ],
      "subject": "merge: preserve accepted placement disposition with conformance preparation"
    },
    {
      "commit": "37792e22b2fbe7997e05681f6d09c4053591fd1f",
      "tree": "b152fe7fb027731b9e7847d55f7ba749bedb8cdd",
      "parents": [
        "b240ee5db68d9213bd308e1394ef4b6a3dcf73c4",
        "35d94b9a2e3e6213856b883092a8983452cee898"
      ],
      "subject": "merge: retain the reviewed canonical macOS report scroll correction"
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
  "status": "Recoverable exact reviewed local source archive only. No intended source branch publication, accepted-main delivery, native readiness, new behavior execution or issue completion is established by this packaging."
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

The new bundle is **32,781 bytes**, SHA-256
`4e0ce508996d5e928de0d5c4309a4b3929ee55da8ec2ddc8b15d1c4933898ae9`.
Its single part has the same bytes and digest; base64 transport is 43,708 bytes.

## Import all three archives into a new local Git database

Choose an unused recovery directory and retain the originals. Fetching public
history and importing these local archive refs need no existing branch rewrite.

```sh
git init --bare /tmp/apple37-b152-recovered.git
git -C /tmp/apple37-b152-recovered.git fetch --no-tags https://github.com/Pick-Your-AI/pick-your-ai-apple.git 40ca8ed3065c04b63dc05e0e26ae0e84489083bf:refs/heads/public-accepted-40ca 35d94b9a2e3e6213856b883092a8983452cee898:refs/heads/public-reviewed-35d
git -C /tmp/apple37-b152-recovered.git bundle verify /tmp/apple37-reviewed-preparation.bundle
git -C /tmp/apple37-b152-recovered.git fetch /tmp/apple37-reviewed-preparation.bundle refs/heads/preparation/apple-37-local-29a3:refs/heads/recovered-original
git -C /tmp/apple37-b152-recovered.git bundle verify /tmp/apple37-reviewed-b79-incremental.bundle
git -C /tmp/apple37-b152-recovered.git fetch /tmp/apple37-reviewed-b79-incremental.bundle refs/heads/preparation/apple-37-reviewed-b79-local-29a3:refs/heads/recovered-b79
git -C /tmp/apple37-b152-recovered.git bundle verify /tmp/apple37-reviewed-b152-incremental.bundle
git -C /tmp/apple37-b152-recovered.git fetch /tmp/apple37-reviewed-b152-incremental.bundle refs/heads/preparation/apple-37-reviewed-b152-local-29a3:refs/heads/recovered-b152
git -C /tmp/apple37-b152-recovered.git rev-parse refs/heads/recovered-b152
git -C /tmp/apple37-b152-recovered.git rev-parse refs/heads/recovered-b152^{tree}
git -C /tmp/apple37-b152-recovered.git fsck --strict --no-dangling
```

The final ref must be `37792e22b2fbe7997e05681f6d09c4053591fd1f`, tree
`b152fe7fb027731b9e7847d55f7ba749bedb8cdd`, ordered parents
`b240ee5db68d9213bd308e1394ef4b6a3dcf73c4` and
`35d94b9a2e3e6213856b883092a8983452cee898`. A separate worktree may then inspect
the recovered source without replacing any active checkout.

## Actual recovery and retained execution limits

On 2026-10-18, a new bare database fetched both exact public histories directly
from GitHub, with no alternates or shallow history. The original wire object
was absent before the first import, and the final source was absent before the
new increment. All three bundle verifications/imports and strict Git object
checks passed. The full 177-leaf original, 202-leaf prior and 211-leaf final
maps, all six new original commit objects/ordered parents and all 223 wire cases
matched the reviewed source. Recovery ran from 22:52:17.640921 to
22:52:18.571980 UTC, **0.931067383 seconds**. The complete 2,692-byte original
log has SHA-256 `f526f98d3db770bffb9819a654f179218fb27fe093c15a4c669ee23bd5b96c07`.
This executed object recovery and identity checks, with no application,
conformance behavior, Swift or native run.

The exact documented recipe passed 24 actual cases under `-OO` and
`PYTHONOPTIMIZE=2` in **7.794255340 seconds**. The valid control reproduced the
fixed bundle; altered/truncated bytes, source/ref/parent/prerequisite/history or
wire/bundle identity drift, an existing output and a missing argument failed
without replacing or creating an unintended output. Its complete 886-byte
original log has SHA-256
`7afe3b25da80730876baae4ec405bc96fdd3d91b49e04720d8f7304b9b964b20`.
These controls test archival reconstruction, not application behavior.

The recovered source preserves the exact previously reviewed evidence:

- The original full harness run at `c0c92cc9` had **45 passes and one ENOSPC
  failure** across 46 methods. Its later focused CLI recovery method alone
  passed after an actual 4 MiB write/fsync/size check; it is not relabeled as a
  new complete 46-method run. The independent 12-method receipt-guard replay
  remains a third, separately attributed execution.
- The older Linux wire run and 30-method/20-observation storage execution keep
  their original source, toolchain, loader/compiler failures and crash-replay
  times. The current **31 + 4 = 35** storage inventory is a reviewed requirement,
  without a new 35-method native result from this archive.
- Android's accepted consumer source and original hosted `b0d2d370` receipt
  retain the same 223 wire cases and **34 Android-private** observations. The
  Apple fixture's **20 SQLite observations** retain their separate formats and
  execution. Later Android signed delivery is source preservation, with no
  new run attributed to an older checkout.
- Canonical rendering source `35d94b9a` preserves the actual `013acc54` /
  `c21ad8ad` macOS result of three rendering passes and one shared-case scroll
  failure. Its separate original iPhone/iPad passes remain distinct. The
  successor's required native jobs were pending at this source review; the
  archive does not turn the scroll correction into an observed rendering pass.
- The accepted #35 placement index row remains exactly from `40ca8ed3`, with
  its actual `791c3558` post-main Transfer receipt. New conformance receipts do
  not alter that completed criterion disposition or imply new placement tests.

No original failed evidence is removed, no paid or duplicate native job is
started, and no source/PR/main/issue acceptance is implied by archive publication.
The intended implementation still needs its current prerequisite and receiving
qualification through the normal signed route. Refs #37.
