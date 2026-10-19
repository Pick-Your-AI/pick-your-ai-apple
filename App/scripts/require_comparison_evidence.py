#!/usr/bin/env python3
"""Qualify the two comparison journeys' exported, test-owned evidence.

This validates exact XCTest attendance, observed UI matrix data and retained
attachment containers. It does not decode video, perform a human accessibility
study, establish physical-device behavior or substitute for artifact review.
Unknown xcresult export formats fail closed instead of weakening attendance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import zlib

FIXTURE_HASH = "7d5e39193254ad2830f74628aec91a8d95bd782329550f0438d717e4e92dd69e"
METHODS = {
    "testComparisonRetainsExactUnitsVersionsAndLimitRecovery": "default",
    "testComparisonAtAccessibilitySizeRetainsNavigationAndCompleteValues": "accessibility3",
}
CHECKPOINTS = ("two-selected", "three-selected", "four-exact-states", "complete-unit-conditions",
               "complete-record", "fifth-rejected", "remove-and-recover", "empty-recovery")
CASE = re.compile(r"^Test Case '-\[([^\]\r\n ]+) (test[A-Za-z0-9_]+)\]' (passed|failed|skipped) \([^\r\n]*\)\.$", re.M)
RECORDED = "Recorded declaration; not independently assessed"
MISSING = "Unknown: not recorded"
NA = "Not applicable: this field is not defined for this component kind"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def read_member(directory, name, maximum):
    require(isinstance(name, str) and name not in ("", ".", "..") and Path(name).name == name
            and "/" not in name and "\\" not in name, "Unsafe exported attachment path")
    path = directory / name
    require(not path.is_symlink() and path.is_file(), "Attachment must be a regular exported file")
    require(0 < path.stat().st_size <= maximum, "Empty or excessive attachment")
    data = path.read_bytes()
    require(0 < len(data) <= maximum, "Attachment changed beyond its bound")
    return data


def verify_png(data):
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), "Screenshot is not a PNG")
    position, kinds = 8, []
    while position < len(data):
        require(position + 12 <= len(data), "Truncated PNG chunk")
        size = struct.unpack(">I", data[position:position + 4])[0]
        end = position + 12 + size
        require(end <= len(data), "PNG chunk exceeds file")
        kind = data[position + 4:position + 8]
        payload = data[position + 8:position + 8 + size]
        expected = struct.unpack(">I", data[end - 4:end])[0]
        require(zlib.crc32(kind + payload) & 0xffffffff == expected, "PNG CRC mismatch")
        if not kinds:
            require(kind == b"IHDR" and size == 13, "PNG header is missing")
            width, height = struct.unpack(">II", payload[:8])
            require(width > 0 and height > 0, "PNG has no visible dimensions")
        kinds.append(kind)
        position = end
    require(kinds and kinds[-1] == b"IEND" and b"IDAT" in kinds, "PNG is incomplete")
    return width, height


def verify_movie(data):
    # ISO base-media containers include actual media bytes. This deliberately
    # does not claim a codec/frame/timeline audit from container presence alone.
    position, boxes = 0, {}
    while position < len(data):
        require(position + 8 <= len(data), "Truncated movie box")
        size, kind = struct.unpack(">I4s", data[position:position + 8])
        header = 8
        if size == 1:
            require(position + 16 <= len(data), "Truncated extended movie box")
            size = struct.unpack(">Q", data[position + 8:position + 16])[0]
            header = 16
        elif size == 0:
            size = len(data) - position
        require(size >= header and position + size <= len(data), "Invalid movie box bounds")
        boxes[kind] = boxes.get(kind, 0) + size - header
        position += size
    require(boxes.get(b"ftyp", 0) >= 8 and boxes.get(b"moov", 0) > 0 and boxes.get(b"mdat", 0) > 0,
            "Success recording has no complete movie/media container")


def selected(versions):
    return [{"name": f'"FICTIONAL Comparison fixture-v{v}"', "version": f'"fixture-v{v}"',
             "id": f'"cat.comparison.{"compute" if v <= 2 else "storage" if v <= 4 else "control"}"',
             "sha256": f'"{FIXTURE_HASH}"'} for v in versions]


def cells(states, values):
    return [{"state": state, "value": value} for state, value in zip(states, values)]


def verify_matrix(matrix, scenario, device):
    require(isinstance(matrix, dict), "Matrix is not an object")
    expected = {
        "schema_version": 1, "scenario": scenario, "fixture_sha256": FIXTURE_HASH,
        "catalog_id": "catalog.comparison.examples.v1", "catalog_revision": 1,
        "captured_at": "2026-10-19T00:00:00Z", "device": device,
        "layout": "componentComparisonAlignedFields" if device == "ipad" and scenario == "default" else "componentComparisonStackedFields",
        "dynamic_type": "accessibility3-subtree" if scenario == "accessibility3" else "system-default",
        "selected": selected([1, 2, 3, 4]), "recovered": selected([1, 3, 4, 5]),
        "disk_gb": cells([RECORDED, MISSING, NA, NA], ["0", None, None, None]),
        "network_gbps": cells([MISSING, RECORDED, NA, NA], [None, "0", None, None]),
        "region": cells([RECORDED, RECORDED, "Unknown: explicitly recorded as unknown", "Unknown: empty text recorded"],
                        ['"fixture-east"', '"fixture-west"', '"unknown"', '""']),
        "final_count": "Compare selected components (0 of 4)", "query": "FICTIONAL", "kind_sort_selected": True,
        "active_kinds": "Compute Profile, Storage",
        "accessibility_audits": ["visible-field-navigation:hitRegion,sufficientElementDescription",
                                 "visible-conditions:textClipped,sufficientElementDescription",
                                 "visible-empty-controls:hitRegion,sufficientElementDescription"],
    }
    require(set(matrix) == set(expected) | {"conditions"}, "Matrix fields are missing or unknown")
    for key, value in expected.items():
        require(matrix[key] == value and type(matrix[key]) is type(value), f"Incorrect observed comparison matrix: {key}")
    units = ["milliseconds/request", "seconds/request", "tokens/second", "requests/second"]
    conditions = matrix["conditions"]
    require(isinstance(conditions, list) and len(conditions) == 4, "Incomplete unit/condition cohort")
    for index, entry in enumerate(conditions):
        require(isinstance(entry, dict) and type(entry.get("amount")) is int and entry == {
            "amount": 1000 if index == 0 else 1, "unit": units[index],
            "region": ["fixture-east", "fixture-west", "unknown", ""][index],
            "offering": f"unqualified-fixture-v{index + 1}", "effective_at": "2026-10-19T00:00:00Z",
            "workload": "fictional-128-input-tokens",
            "qualification": "Fictional declaration; no conversion, ranking or rate applicability.",
        }, "Unit, amount or applicable-condition declaration changed")


def verify(directory, log_path, device):
    require(device in ("iphone", "ipad"), "Unknown pinned destination")
    require(directory.is_dir() and not directory.is_symlink(), "Export root is not a regular directory")
    log = log_path.read_bytes()
    records = CASE.findall(log.decode("utf-8"))
    expected = {("PlannerAppUITests.ComponentComparisonJourneyTests", name, "passed") for name in METHODS}
    require(len(records) == 2 and set(records) == expected, "Expected both exact journeys once, without failed, skipped or retried cases")
    manifest_bytes = read_member(directory, "manifest.json", 4 * 1024 * 1024)
    manifest = json.loads(manifest_bytes)
    require(isinstance(manifest, list) and len(manifest) == 2, "Expected exactly two test-owned attachment groups")
    seen_tests, seen_files, receipts = set(), set(), []
    for group in manifest:
        require(isinstance(group, dict), "Invalid attachment group")
        identifier = group.get("testIdentifier")
        names = {f"ComponentComparisonJourneyTests/{name}()": name for name in METHODS}
        names.update({f"PlannerAppUITests/ComponentComparisonJourneyTests/{name}()": name for name in METHODS})
        require(isinstance(identifier, str) and identifier in names, "Unknown test attachment owner")
        method = names[identifier]
        require(method not in seen_tests, "Duplicate test attachment group")
        seen_tests.add(method)
        attachments = group.get("attachments")
        require(isinstance(attachments, list) and 0 < len(attachments) <= 300, "Missing or excessive attachments")
        matrix_count, hierarchy, screenshots, movies, files = 0, set(), set(), 0, []
        for item in attachments:
            require(isinstance(item, dict), "Invalid attachment entry")
            name, human = item.get("exportedFileName"), item.get("suggestedHumanReadableName")
            require(isinstance(human, str) and isinstance(name, str) and name not in seen_files, "Missing or duplicate attachment identity")
            seen_files.add(name)
            data = read_member(directory, name, 512 * 1024 * 1024)
            files.append({"file": name, "name": human, **digest(data)})
            if human in ("comparison-matrix", "comparison-matrix.json"):
                verify_matrix(json.loads(data), METHODS[method], device)
                matrix_count += 1
            for checkpoint in CHECKPOINTS:
                if human in (f"comparison-accessibility-{checkpoint}", f"comparison-accessibility-{checkpoint}.txt"):
                    require(checkpoint not in hierarchy and b"Application" in data and b"Window" in data,
                            "Missing or duplicated accessibility hierarchy")
                    hierarchy.add(checkpoint)
                if human == f"comparison-screen-{checkpoint}" or human == f"comparison-screen-{checkpoint}.png":
                    require(checkpoint not in screenshots, "Duplicate checkpoint screenshot")
                    width, height = verify_png(data)
                    require(min(width, height) >= 320, "Screenshot is too small for a pinned native viewport")
                    require((width > height) if device == "ipad" else (height > width), "Screenshot orientation differs from its pinned journey")
                    screenshots.add(checkpoint)
            if Path(name).suffix.lower() in (".mp4", ".mov"):
                verify_movie(data)
                movies += 1
        require(matrix_count == 1, "Require one exact final observed matrix per journey")
        require(hierarchy == set(CHECKPOINTS) and screenshots == set(CHECKPOINTS), "Require every actual hierarchy and screenshot checkpoint")
        require(movies > 0, "No retained successful journey video; screen-capture configuration is not evidence")
        receipts.append({"test": identifier, "scenario": METHODS[method], "success_video_containers": movies, "attachments": files})
    require(seen_tests == set(METHODS), "A required journey is missing")
    return {"qualification": "Exact XCTest attendance, matrix assertions, original attachment hashes, PNG CRCs and bounded ISO media-box presence; no frame, physical-device or participant claim.",
            "device": device, "fixture_sha256": FIXTURE_HASH, "log": digest(log), "manifest": digest(manifest_bytes), "journeys": receipts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("attachments", type=Path)
    parser.add_argument("log", type=Path)
    parser.add_argument("device", choices=("iphone", "ipad"))
    args = parser.parse_args()
    print(json.dumps(verify(args.attachments, args.log, args.device), indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, UnicodeError) as error:
        print(f"Comparison evidence rejected: {error}", file=sys.stderr)
        raise SystemExit(1) from error
