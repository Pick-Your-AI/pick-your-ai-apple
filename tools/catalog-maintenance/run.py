#!/usr/bin/env python3
"""Closed synthetic maintenance rehearsal; no service, publisher or device claim."""
from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PHASES = ("seed", "maintain", "reopen", "exact-target")


class QualificationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise QualificationError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fixtures(contracts: Path):
    # Use the already provisioned, repository-pinned reference environment.
    require(importlib.metadata.version("jsonschema") == "4.25.1", "jsonschema pin")
    from jsonschema import Draft202012Validator, FormatChecker
    from referencing import Registry, Resource

    manifest = json.loads((HERE / "fixture-manifest.json").read_bytes())
    require(manifest["classification"] == "synthetic-only", "fixture classification")
    resources = []
    schemas = {}
    for name, expected in manifest["schemas"].items():
        require(Path(name).name == name, "schema filename")
        raw = (contracts / "schemas" / name).read_bytes()
        require(digest(raw) == expected, f"schema hash: {name}")
        schema = json.loads(raw)
        schemas[name] = schema
        if name != "component-registry.json":
            resources.append((schema["$id"], Resource.from_contents(schema)))
    registry = Registry().with_resources(resources)
    values = {}
    for name, entry in manifest["files"].items():
        require(Path(name).name == name, "fixture filename")
        raw = (HERE / "Sources" / "MaintenanceDrill" / "Fixtures" / name).read_bytes()
        require(len(raw) == entry["bytes"] and digest(raw) == entry["sha256"], f"fixture hash: {name}")
        Draft202012Validator(schemas[entry["schema"]], registry=registry,
                             format_checker=FormatChecker()).validate(json.loads(raw))
        values[name] = raw
    require(set(values) == {"catalog-a.json", "catalog-b.json", "pricebook-a.json",
                           "pricebook-b.json", "build-a.json"}, "complete fixture inventory")
    a = json.loads(values["catalog-a.json"])
    b = json.loads(values["catalog-b.json"])
    book_a = json.loads(values["pricebook-a.json"])
    book_b = json.loads(values["pricebook-b.json"])
    build = json.loads(values["build-a.json"])
    require(build["locks"]["catalog_snapshot_id"] == a["id"]
            and build["locks"]["pricebook_id"] == book_a["id"], "saved release locks")
    for catalog, book in ((a, book_a), (b, book_b)):
        members = {(item["id"], item["version"]) for item in catalog["items"]}
        require(all((rate["catalog_item_id"], rate["catalog_item_version"]) in members
                    for rate in book["rates"]), "rate/current catalog membership")
    require(a["id"] != b["id"] and book_a["id"] != book_b["id"], "distinct release identities")
    require(book_a["rates"][0]["unit_price"]["amount"] == "0.80"
            and book_b["rates"][0]["unit_price"]["amount"] == "0.95",
            "explicit illustrative correction")
    return values


def decode_bytes(value):
    require(isinstance(value, str), "base64 text")
    try:
        return base64.b64decode(value, validate=True)
    except (ValueError, TypeError) as error:
        raise QualificationError("invalid observed bytes") from error


def same_json_value(left, right):
    """Preserve Boolean identity while retaining numeric equality, including 1.0 == 1."""
    if isinstance(left, bool) or isinstance(right, bool):
        return left is right
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(same_json_value(left[key], right[key]) for key in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(same_json_value(a, b) for a, b in zip(left, right, strict=True))
    return left == right


def qualify_history(mode, results, inputs):
    require(mode in ("portable", "native"), "known mode")
    require(len(results) == 3, "three original process phases")
    expected_build = inputs["build-a.json"]
    first = results[0]
    for phase, value in zip(PHASES[:3], results, strict=True):
        require(same_json_value(value["format"], 1) and value["phase"] == phase and value["mode"] == mode,
                "actual phase/mode identity")
        require(value["classification"] == "synthetic-only" and value["status"] == "passed",
                "actual successful fixture phase")
        for key in ("draft", "neighbour", "history", "neighbour_history", "baseline"):
            require(same_json_value(value[key], first[key]), f"preserved original {key}")
        require(decode_bytes(value["draft"]["payload_base64"]) == expected_build
                and same_json_value(value["draft"]["revision"], 1) and value["draft"]["analysis_is_current"] is False,
                "actual saved bytes and currentness")
        require(len(value["history"]) == 1 and same_json_value(value["history"][0], value["draft"]),
                "one exact historical revision")
        require(decode_bytes(value["neighbour"]["payload_base64"]) == b'{"synthetic":"unrelated"}'
                and same_json_value(value["neighbour"]["revision"], 1)
                and value["neighbour"]["analysis_is_current"] is False,
                "unaffected other draft")
        require(same_json_value(value["neighbour_history"], [value["neighbour"]]), "other history")
        baseline = value["baseline"]
        build = json.loads(expected_build)
        selected = next(item for item in build["selections"]
                        if item["catalog_item_id"] == "cat.compute_profile.fixture")
        expected_identity = {"component_id": selected["catalog_item_id"],
                             "component_version": selected["catalog_item_version"],
                             "catalog_snapshot_id": build["locks"]["catalog_snapshot_id"]}
        require(all(baseline[key] == val for key, val in expected_identity.items()), "observed saved tuple")
        require(baseline["display_grade"] == "independentlyVerified"
                and baseline["original_status"] == "verified" and baseline["review_requirement"] == "none",
                "explicit synthetic initial grade")
        if phase == "seed":
            require(value["warnings"] == [], "no fabricated seed warning")
        else:
            require([item["event"] for item in value["warnings"]] ==
                    ["correction", "retraction", "later-notices", "unrelated-retraction"], "complete warning observations")
            for warning in value["warnings"]:
                require(all(warning[key] == val for key, val in expected_identity.items())
                        and warning["original_status"] == "verified", "warning preserves historical identity/status")
                affected = warning["event"] != "unrelated-retraction"
                require(warning["review_requirement"] == ("recheckRequired" if affected else "none")
                        and warning["display_grade"] == ("unverified" if affected else "independentlyVerified"),
                        "correct warning/current grade")
        cache = value["catalog_cache"]
        if mode == "portable":
            require(cache == {"status": "unexecuted",
                              "reason": "portable-scope-does-not-emulate-CryptoKit"}, "no native cache credit")
        else:
            require(cache["status"] == "passed" and cache["current_checks"] == "unknown", "cache outcome")
            expected_controls = (["pricebook-download-failure", "cancelled-second-artifact", "production-denied"]
                                 if phase == "maintain" else ["production-denied"])
            require(cache["controls"] == expected_controls, "actual recovery/production-denial controls")
            for label, version in (("active", "a" if phase == "seed" else "b"), ("retained", "a")):
                record = cache[label]
                require(record["is_synthetic"] is True, "synthetic cache record")
                pin_entries = record["manifest"]["pins"]
                require(isinstance(pin_entries, list) and len(pin_entries) == 2,
                        "exact cached pair cardinality")
                pins = {pin["kind"]: pin for pin in pin_entries}
                require(set(pins) == {"catalog", "pricebook"}, "complete pair")
                for kind in pins:
                    raw = inputs[f"{kind}-{version}.json"]
                    parsed = json.loads(raw)
                    require(decode_bytes(record[f"{kind}_base64"]) == raw, "exact actual cache bytes")
                    require(pins[kind]["sha256"] == digest(raw), "cache digest")
                    require(same_json_value(pins[kind]["identity"],
                            {key: parsed[key] for key in ("schema_version", "id", "revision", "captured_at")}),
                            "full cached identity")
            require(same_json_value(cache["retained"], first["catalog_cache"]["retained"]), "historical cache unchanged")
    return {"scope": f"{mode}-history-and-domain-replay", "original_processes": 3,
            "physical_device": False, "canonical_feed": False, "rendered_ui": False}


def qualify_target(value, mode):
    require(value["status"] == "passed" and value["phase"] == "exact-target"
            and value["mode"] == mode and value["classification"] == "synthetic-only"
            and same_json_value(value["format"], 1), "exact-target original identity")
    require(value["target_version_utf8"] == [195, 169] and value["other_version_utf8"] == [101, 204, 129],
            "two byte-distinct versions")
    require(value["observed"]["review_requirement"] == "none", "wrong version cannot target retained evidence")


def source_hashes():
    paths = [HERE / "Package.swift", HERE / "run.py", HERE / "fixture-manifest.json"]
    paths += sorted((HERE / "Sources").rglob("*"))
    for name in ("PlannerCore", "PlannerData", "PlannerCatalog", "PlannerTransfer"):
        package = REPO / "Packages" / name
        paths += [package / "Package.swift", *sorted((package / "Sources").rglob("*"))]
    return {str(path.relative_to(REPO)): digest(path.read_bytes()) for path in paths if path.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contracts", required=True, type=Path)
    parser.add_argument("--executable", required=True, type=Path)
    parser.add_argument("--mode", required=True, choices=("portable", "native"))
    parser.add_argument("--output", required=True, type=Path, help="new directory outside the repository")
    args = parser.parse_args()
    values = fixtures(args.contracts)
    require(args.executable.is_file(), "existing compiled executable")
    output = args.output.absolute()
    require(not output.resolve().is_relative_to(REPO), "output outside source checkout")
    output.mkdir(mode=0o700, exist_ok=False)
    state = output / "state"
    state.mkdir(mode=0o700)
    before = source_hashes()
    receipt = {"format": 1, "classification": "synthetic-only", "mode": args.mode,
               "source_inputs": before, "executable_sha256": digest(args.executable.read_bytes()),
               "fixture_inputs": {name: digest(raw) for name, raw in values.items()},
               "commands": [], "history_qualification": None, "full_rehearsal_qualified": False,
               "limitations": ["No real feed/publisher rights", "No installed older client",
                               "No rendered UI or physical device", "No issue #121 closure"]}
    observed = []
    try:
        for phase in PHASES:
            command = [str(args.executable.resolve()), args.mode, phase, str(state)]
            started = time.time()
            timed_out = False
            try:
                result = subprocess.run(command, capture_output=True, timeout=40, check=False)
            except subprocess.TimeoutExpired as error:
                timed_out = True
                result = subprocess.CompletedProcess(command, -1, error.stdout or b"", error.stderr or b"")
            require(len(result.stdout) + len(result.stderr) <= 1_048_576, "bounded original output")
            (output / f"{phase}.stdout.json").write_bytes(result.stdout)
            (output / f"{phase}.stderr.log").write_bytes(result.stderr)
            receipt["commands"].append({"argv": command, "started_unix": started,
                                        "elapsed_seconds": time.time() - started, "exit": result.returncode,
                                        "timed_out": timed_out,
                                        "stdout_sha256": digest(result.stdout), "stderr_sha256": digest(result.stderr)})
            require(source_hashes() == before, "source unchanged across original execution")
            require(result.returncode == 0, f"actual {phase} failed; retained original is not a pass")
            value = json.loads(result.stdout)
            if phase == "exact-target":
                qualify_target(value, args.mode)
            else:
                observed.append(value)
                if phase == "reopen":
                    receipt["history_qualification"] = qualify_history(args.mode, observed, values)
        receipt["full_rehearsal_qualified"] = args.mode == "native"
        receipt["status"] = "passed"
    except Exception as error:
        receipt["status"] = "failed"
        receipt["failure"] = str(error)
    finally:
        receipt["source_after"] = source_hashes()
        if receipt["source_after"] != before:
            receipt["status"] = "failed"
            receipt["failure"] = "source changed"
            receipt["full_rehearsal_qualified"] = False
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps({"status": receipt["status"], "receipt": str(output / "receipt.json"),
                          "history_qualification": receipt["history_qualification"],
                          "full_rehearsal_qualified": receipt["full_rehearsal_qualified"]}))
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
