# Apple #37: recoverable reviewed preparation

This directory preserves the exact reviewed conformance and local-migration
preparation as a segmented Git bundle. Reassembling and importing it restores
unsigned local commit `6eec8878e1456d2e7cad78399702a33461093ce8`, tree
`08e54247b998d005ed831bfaeabad7731f3e7a8a`, with sole prerequisite parent
`7d9724b16136546b686d87f29acf9bd95ca9c2eb`.

This is an archival checkpoint. Its containing branch is not the intended source
branch or a receiving delivery. The source remains the historical, independently
reviewed nineteen-path preparation; it has not acquired current-main or native
qualification through packaging. The [Apple #37 record](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37)
retains the named prerequisite and acceptance boundaries.

## Exact preserved objects

[CHECKPOINT.json](CHECKPOINT.json) records both ordered parts, their lengths and
SHA-256 hashes, the complete bundle identity, restored commit/tree and original
wire fixture identity. Concatenation produces a 97,763-byte version-2 Git bundle,
SHA-256 `a9783ffd55b34327f5ccaf98f493e327c62a651279e88e82585c50a5fa8431e4`.
The parts are transport packaging; the original source and fixture bytes are
unchanged. Each part stays below 50,001 bytes, avoiding another upload of the
1,273,770-byte plaintext fixture through the stalled transport.

The recovered source contains all 177 original leaves and modes. Its single
neutral wire bundle has 223 cases, 141 accepted and 82 rejected, and SHA-256
`499fd9a01780ac42fa9bf2ab8cf9e1195db27321fec36040451b553a8b9ea5f9`.
The original 98 placement dispositions, all 37 evidence inputs, six Apple-local
migration descriptions, typed consumers, strict receipt checks and complete
preparation record remain exactly those reviewed objects.

## Recover and verify

Use a clone with the public prerequisite commit available. From this directory,
reassemble into a new file outside the repository; an existing output is refused:

```sh
python3 - /tmp/apple37-reviewed-preparation.bundle <<'PY'
import hashlib
import json
from pathlib import Path
import sys

def require(condition, message):
    if not condition:
        raise SystemExit(message)


require(len(sys.argv) == 2, "Supply the new output bundle path")
manifest = json.loads(Path("CHECKPOINT.json").read_text(encoding="utf-8"))
expected_identity = {
    "format": "git-bundle-checkpoint-1",
    "sourceCommit": "6eec8878e1456d2e7cad78399702a33461093ce8",
    "sourceTree": "08e54247b998d005ed831bfaeabad7731f3e7a8a",
    "prerequisiteCommit": "7d9724b16136546b686d87f29acf9bd95ca9c2eb",
    "containedRef": "refs/heads/preparation/apple-37-local-29a3",
    "bundleBytes": 97763,
    "bundleSHA256": "a9783ffd55b34327f5ccaf98f493e327c62a651279e88e82585c50a5fa8431e4",
}
expected_parts = [
    {
        "path": "apple37-reviewed-preparation.bundle.part-01",
        "bytes": 50000,
        "sha256": "fc4bcb6a2130a88a75de35bfd0f554d6f85804017dc2d4b923b05735533e821f",
        "gitBlob": "67547f9962ea0498c2efce73c2021835ec858d99",
        "base64Bytes": 66668,
    },
    {
        "path": "apple37-reviewed-preparation.bundle.part-02",
        "bytes": 47763,
        "sha256": "48cfac499ef7a47c0b46545db29e936cbad89b063ad58b56c0ae4583c7ffb32e",
        "gitBlob": "b93c97ed3c88e9e8d134628ea17f8f00d92bb301",
        "base64Bytes": 63684,
    },
]
expected_wire = {
    "path": "Packages/PlannerConformance/Tests/PlannerConformanceTests/Fixtures/cross-client-v1.json",
    "bytes": 1273770,
    "sha256": "499fd9a01780ac42fa9bf2ab8cf9e1195db27321fec36040451b553a8b9ea5f9",
}
require(isinstance(manifest, dict), "Expected the reviewed checkpoint object")
for field, value in expected_identity.items():
    require(manifest.get(field) == value, "Unexpected checkpoint identity: " + field)
require(manifest.get("parts") == expected_parts, "Unexpected ordered part identities")
require(manifest.get("wireFixture") == expected_wire, "Unexpected original wire identity")
chunks = []
for part in expected_parts:
    data = Path(part["path"]).read_bytes()
    require(len(data) == part["bytes"], "Part length differs: " + part["path"])
    require(hashlib.sha256(data).hexdigest() == part["sha256"],
            "Part hash differs: " + part["path"])
    chunks.append(data)
bundle = b"".join(chunks)
require(len(bundle) == expected_identity["bundleBytes"], "Bundle length differs")
require(hashlib.sha256(bundle).hexdigest() == expected_identity["bundleSHA256"],
        "Bundle hash differs")
with Path(sys.argv[1]).open("xb") as output:
    output.write(bundle)
print(expected_identity["sourceCommit"], expected_identity["sourceTree"])
PY
```

From the clone, import the checked bundle into a separate local ref:

```sh
git fetch --no-tags origin 7d9724b16136546b686d87f29acf9bd95ca9c2eb
git bundle verify /tmp/apple37-reviewed-preparation.bundle
git fetch /tmp/apple37-reviewed-preparation.bundle refs/heads/preparation/apple-37-local-29a3:refs/heads/recovered/apple-37-reviewed
git rev-parse refs/heads/recovered/apple-37-reviewed^{tree}
git fsck --strict --no-dangling
```

The tree must be `08e54247b998d005ed831bfaeabad7731f3e7a8a`. A separate
worktree can then be created from the recovered commit without replacing an
existing checkout. Its `Packages/PlannerConformance/README.md` contains the
complete original execution identities, source pins and reproduction commands.

## Actual archive verification and remaining work

On 2026-10-18, recovery was executed in a fresh local Git database containing only
a depth-one fetch of prerequisite `7d9724b1`. The original wire object was absent
before import. Bundle verification and fetch succeeded; strict Git object checks,
the recovered commit/tree, all 177 leaves/modes and the complete original wire
length/hash matched. The exact 776-byte restoration log has SHA-256
`4952f2e1f1cab5353040c4376a50d137ee13defcfb25115101e9d993515b194b`.
This is an actual Git recovery check, not another Swift or native test run.

Later source publication must retain the canonical producer and reconcile the
exact accepted Data test inventory and named #33/#35/#36 outputs, including the
corrected native evidence harness. Actual configured native results, independent
current-main review and normal signed delivery remain required. The archived
25-plus-four Data inventory remains a preparation identity, not a claim about
that later accepted union. The archive changes no literal criterion, issue state,
shared wire version, other-client execution or release acceptance. Refs #37.
