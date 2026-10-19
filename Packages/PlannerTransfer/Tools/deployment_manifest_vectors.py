"""Standalone frozen DeploymentManifest pins and Swift/Python reference vectors.

Default execution is read-only. --write regenerates only this slice's fixture.
Use the adjacent hash-locked requirements.txt; no network or research checkout is
needed. This entry is deliberately not wired into the independently owned shared
verify_contract.py. It verifies declarations, not approval or deployment evidence.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Tools/deployment_manifest_source_manifest.json"
VECTORS = ROOT / "Tests/PlannerTransferTests/Fixtures/deployment-manifest-conformance.json"
REVISION = "7acbefbf4e4e700231e88be272bc89e3a73dde15"
SOURCES = {
    "contracts/v1/schemas/deployment-manifest.schema.json":
        ("Sources/PlannerTransfer/Resources/deployment-manifest.schema.json",
         "86bc716c906aca1299d9129eec08abec44378c26b5a97317d6310afe84d6b374"),
    "contracts/v1/schemas/common.schema.json":
        ("Sources/PlannerTransfer/Resources/common.schema.json",
         "0342ce2f1114e7276fc7f6a08ff5b86e8727caadd83ae4f443de9a7e1431c43c"),
    "contracts/v1/examples/deployment-manifest.json":
        ("Tests/PlannerTransferTests/Fixtures/deployment-manifest.json",
         "c05603388efc50a15274d1e6fa8e25dac3c205377a1989bfb5b3a3e64face8ab"),
}


def read_regular(path, limit=2 * 1024 * 1024):
    """Read bounded regular input through its opened descriptor, without FIFO wait."""
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NONBLOCK", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
                raise ValueError("nonregular or oversized reference input")
            data = stream.read(limit + 1)
            if len(data) > limit:
                raise ValueError("oversized reference input")
            return data
    finally:
        os.close(descriptor)


def write_vectors(path, data):
    """Stage complete bytes before replacing a regular/missing fixture entry."""
    def output_mode():
        try:
            info = path.lstat()
        except FileNotFoundError:
            return None
        if not stat.S_ISREG(info.st_mode):
            raise ValueError("nonregular reference output")
        return stat.S_IMODE(info.st_mode)

    mode = output_mode()
    with tempfile.TemporaryDirectory(prefix=".deployment-vectors-", dir=path.parent) as owned:
        staged = Path(owned) / "vectors.json"
        with staged.open("xb") as stream:
            if stream.write(data) != len(data):
                raise OSError("incomplete reference output")
            stream.flush()
            os.fsync(stream.fileno())
        if mode is not None:
            staged.chmod(mode)
        output_mode()
        os.replace(staged, path)


def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate reference member")
        result[key] = value
    return result


def decoded(data):
    return json.loads(data, object_pairs_hook=reject_duplicates)


def sources():
    manifest = decoded(read_regular(MANIFEST))
    expected = {
        "repository": "Pick-Your-AI/pick-your-ai-research",
        "revision": REVISION, "contractVersion": "1.0.0",
        "files": [{"source": source, "target": target, "sha256": digest}
                  for source, (target, digest) in SOURCES.items()],
    }
    if manifest != expected:
        raise ValueError("changed frozen source manifest")
    result = {}
    for source, (target, digest) in SOURCES.items():
        data = read_regular(ROOT / target)
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError("frozen source hash mismatch")
        result[Path(source).name] = decoded(data)
    return result


def vectors(example, schema):
    """Explicit expected outcomes, independently checked by the canonical validator."""
    result = []

    def add(name, value, valid=True, client=None, limit=None):
        row = {"name": name, "json": json.dumps(value, ensure_ascii=False, separators=(",", ":")),
               "canonicalValid": valid, "clientValid": valid if client is None else client}
        if limit is not None:
            row["clientLimit"] = limit
        result.append(row)

    def changed(name, key, value, valid=False, **options):
        payload = copy.deepcopy(example)
        payload[key] = value
        add(name, payload, valid, **options)

    add("canonical-proposed-synthetic", example)
    for key in schema["required"]:
        payload = copy.deepcopy(example)
        del payload[key]
        add("missing-" + key, payload, False)
    for key in schema["properties"]:
        changed("null-" + key, key, None)
    changed("unknown-top-level-field", "unreviewed_extension", True)
    changed("unsupported-schema-version", "schema_version", "2.0.0")
    changed("number-schema-version", "schema_version", 1)
    for key in ("id", "build_id", "compatibility_report_id", "quality_run_id",
                "cost_estimate_id", "resource_estimate_id"):
        for label, value in (("short", "ab"), ("uppercase", "BAD.fixture"),
                             ("too-long", "a" * 121), ("array", [])):
            changed(label + "-" + key, key, value)
        changed("max-length-" + key, key, "a" * 120, True)
    changed("terminal-newline-id", "id", "manifest.fixture.1\n", True, client=False,
            limit="Existing client identifier regex requires strict end-of-input.")
    changed("valid-nonprefixed-target-id", "deployment_target_selection_id", "target", True)
    changed("maximum-target-id", "deployment_target_selection_id", "a" * 80, True)
    changed("oversized-target-id", "deployment_target_selection_id", "a" * 81)
    for label, value in (("uppercase", "sel_TARGET"),
                         ("empty", ""), ("numeric", 1)):
        changed(label + "-target-id", "deployment_target_selection_id", value)
    for label, value in (("zero", 0), ("negative", -1), ("fraction", 1.5),
                         ("boolean", True), ("string", "1")):
        changed(label + "-revision", "build_revision", value)
    changed("fifteen-significant-digit-revision", "build_revision", 123456789012345, True)
    changed("sixteen-significant-digit-revision", "build_revision", 1234567890123456, True,
            client=False, limit="Existing client numeric subset permits at most 15 significant digits.")
    changed("above-safe-integer-revision", "build_revision", 9007199254740992, True,
            client=False, limit="Existing client numeric subset excludes integers above 2^53-1.")
    for status in ("proposed", "approved", "rejected", "deployed", "rolled_back"):
        changed("declared-status-" + status, "status", status, True)
    changed("unknown-status", "status", "ready")
    changed("boolean-status", "status", True)
    for strategy in ("canary", "blue_green", "rolling", "manual"):
        changed("rollout-" + strategy, "rollout_strategy", strategy, True)
    changed("unknown-rollout", "rollout_strategy", "automatic")
    changed("empty-approvals", "approvals", [])
    changed("object-approvals", "approvals", {})
    for decision in ("pending", "approved", "rejected"):
        for scope in ("security", "owner", "finance", "compliance"):
            row = {"approver_ref": "fixture.private.é", "decision": decision, "scope": scope}
            changed("approval-" + decision + "-" + scope, "approvals", [row], True)
    for key in ("approver_ref", "decision", "scope"):
        row = copy.deepcopy(example["approvals"][0])
        del row[key]
        changed("missing-approval-" + key, "approvals", [row])
        row[key] = None
        changed("null-approval-" + key, "approvals", [row])
    for key, value in (("approver_ref", ""), ("decision", "accepted"), ("scope", "runtime"),
                       ("extra", "unreviewed"), ("approved_at", "2026-02-30T09:00:00Z")):
        row = copy.deepcopy(example["approvals"][0])
        row[key] = value
        changed("invalid-approval-" + key, "approvals", [row])
    row = copy.deepcopy(example["approvals"][0])
    row["approved_at"] = "2024-02-29T09:00:00+01:00"
    changed("pending-with-declared-approval-time", "approvals", [row, row], True)
    for label, timestamp in (("leap-day", "2024-02-29T23:59:59Z"),
                             ("fraction-offset", "2026-10-16T09:00:00.001-05:30")):
        changed(label + "-requested-at", "requested_at", timestamp, True)
    for label, timestamp in (("bad-day", "2026-02-29T09:00:00Z"),
                             ("no-zone", "2026-10-16T09:00:00"),
                             ("bad-hour", "2026-10-16T24:00:00Z")):
        changed(label + "-requested-at", "requested_at", timestamp)
    for label, uri in (("https", "https://fixture.invalid/rollback/a%20b#v1"),
                       ("urn", "urn:fixture:rollback:1"), ("file", "file:///private/fixture")):
        changed(label + "-rollback", "rollback_artifact_uri", uri, True)
    changed("ipv6-rollback", "rollback_artifact_uri", "https://[::1]/rollback", True, client=False,
            limit="Existing client URI subset excludes IP-literal hosts.")
    for label, uri in (("relative", "rollback/v1"), ("space", "https://fixture.invalid/a b"),
                       ("bad-percent", "https://fixture.invalid/%zz")):
        changed(label + "-rollback", "rollback_artifact_uri", uri)
    changed("empty-deployment-reference", "deployment_reference", "", True)
    changed("declared-private-deployment-reference", "deployment_reference", "private.fixture/é", True)
    changed("empty-notes", "notes", [], True)
    changed("ordered-repeated-unicode-notes", "notes", ["é", "e\u0301", "é"], True)
    changed("wrong-note-item", "notes", [True])
    return result


def encoded_vectors(rows):
    return (json.dumps(rows, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="regenerate this slice's vector fixture")
    args = parser.parse_args(argv)
    inputs = sources()
    if not {"date-time", "uri"} <= FormatChecker().checkers.keys():
        raise ValueError("install the adjacent hash-locked reference requirements")
    schema = inputs["deployment-manifest.schema.json"]
    common = inputs["common.schema.json"]
    registry = Registry().with_resources((s["$id"], Resource.from_contents(s)) for s in (schema, common))
    validator = Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())
    rows = vectors(inputs["deployment-manifest.json"], schema)
    if len({row["name"] for row in rows}) != len(rows):
        raise ValueError("duplicate generated vector identity")
    for row in rows:
        if validator.is_valid(decoded(row["json"])) != row["canonicalValid"]:
            raise ValueError("canonical mismatch: " + row["name"])
        if row["canonicalValid"] != row["clientValid"] and not row.get("clientLimit"):
            raise ValueError("undocumented client subset")
    data = encoded_vectors(rows)
    if args.write:
        write_vectors(VECTORS, data)
    if read_regular(VECTORS) != data:
        raise ValueError("stale deployment manifest vectors")
    print(f"Verified 3 frozen source pins and {len(rows)} DeploymentManifest vectors; "
          f"canonical-positive={sum(row['canonicalValid'] for row in rows)}, "
          f"client-positive={sum(row['clientValid'] for row in rows)}, "
          f"explicit-client-subsets={sum(row['canonicalValid'] != row['clientValid'] for row in rows)}.")
    print("Structural declarations only; no approval, quality, deployment or native execution inferred.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print("DeploymentManifest reference verification failed: " + str(error), file=sys.stderr)
        raise SystemExit(2) from None
