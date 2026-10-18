#!/usr/bin/env python3
"""Inspect exact reviewed privacy manifests inside an unsigned built Planner app."""

import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
MAX_ENTRIES = 10_000
MAX_DEPTH = 32
MAX_MANIFEST_BYTES = 65_536
EXPECTED = {
    "PlannerCatalog_PlannerCatalog.bundle/PrivacyInfo.xcprivacy": {
        "source": "Packages/PlannerCatalog/Sources/PlannerCatalog/PrivacyInfo.xcprivacy",
        "sha256": "06de9e3dc6e7a65630efd87685dd2d61e5297b00ef4d32a852aa2859430219f5",
        "category": "NSPrivacyAccessedAPICategoryFileTimestamp",
        "reason": "C617.1",
    },
    "PlannerUI_PlannerUI.bundle/PrivacyInfo.xcprivacy": {
        "source": "Packages/PlannerUI/Sources/PlannerUI/PrivacyInfo.xcprivacy",
        "sha256": "a3799663af4d176d8ce1d87b8f061deddd8ebe7083de64ef5406f9e4844d30f2",
        "category": "NSPrivacyAccessedAPICategoryUserDefaults",
        "reason": "CA92.1",
    },
}


class InventoryError(ValueError):
    pass


def read_regular(name, *, directory=None):
    descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_MANIFEST_BYTES:
            raise InventoryError("manifest must be a bounded regular file")
        data = stream.read(MAX_MANIFEST_BYTES + 1)
        if len(data) > MAX_MANIFEST_BYTES:
            raise InventoryError("manifest exceeds the byte bound")
        return data


def inspect_app(app, source_root=ROOT):
    app = Path(app)
    if app.suffix != ".app":
        raise InventoryError("select an existing built .app product")
    source_bytes = {}
    for relative, expected in EXPECTED.items():
        data = read_regular(Path(source_root) / expected["source"])
        if hashlib.sha256(data).hexdigest() != expected["sha256"]:
            raise InventoryError("source declaration no longer matches its reviewed inventory pin")
        source_bytes[relative] = data

    observed = {}
    visited = 0

    def scan(directory, prefix, depth):
        nonlocal visited
        if depth > MAX_DEPTH:
            raise InventoryError("built product exceeds the directory-depth bound")
        with os.scandir(directory) as entries:
            for entry in entries:
                visited += 1
                if visited > MAX_ENTRIES:
                    raise InventoryError("built product exceeds the entry bound")
                relative = f"{prefix}/{entry.name}" if prefix else entry.name
                info = entry.stat(follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    child = os.open(entry.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                    dir_fd=directory)
                    try:
                        scan(child, relative, depth + 1)
                    finally:
                        os.close(child)
                elif stat.S_ISREG(info.st_mode):
                    if entry.name != "PrivacyInfo.xcprivacy":
                        continue
                    if relative not in EXPECTED:
                        raise InventoryError("built product contains an unreviewed privacy-manifest location")
                    data = read_regular(entry.name, directory=directory)
                    if data != source_bytes[relative]:
                        raise InventoryError("bundled privacy manifest differs from its exact reviewed source")
                    observed[relative] = {**EXPECTED[relative], "bytes": len(data)}
                else:
                    raise InventoryError("built product contains a link or non-regular entry")

    directory = os.open(app, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        scan(directory, "", 0)
    finally:
        os.close(directory)
    if set(observed) != set(EXPECTED):
        raise InventoryError("built product is missing a reviewed package privacy manifest")
    return {
        "formatVersion": 1,
        "product": app.name,
        "manifestCount": len(observed),
        "manifests": [{"path": key, **observed[key]} for key in sorted(observed)],
        "scope": "Bundled declarations only; no binary API scan, network measurement, consent or release acceptance.",
    }


def output_ancestors(path):
    """Retain ancestry hidden inside directory-link targets, including before '..'."""
    pending = list(path.absolute().parents)
    seen = set()
    while pending:
        parent = pending.pop()
        if parent in seen:
            continue
        seen.add(parent)
        try:
            info = parent.stat()
        except FileNotFoundError as error:
            if parent.name == "..":
                raise InventoryError("evidence '..' traversal requires an existing directory") from error
        else:
            if not stat.S_ISDIR(info.st_mode):
                raise InventoryError("evidence parent components must be directories")
        yield parent.resolve()
        if parent.is_symlink():
            target = parent.readlink()
            if not target.is_absolute():
                target = parent.parent.resolve() / target
            pending.extend((target, *target.parents))


def prepare_output(path, app):
    # A failed retry must not leave a previous success in the uploaded evidence.
    lexical_app = Path(os.path.abspath(app))
    lexical_output = Path(os.path.abspath(path))
    if lexical_app == lexical_output or lexical_app in lexical_output.parents:
        raise InventoryError("evidence must be outside the inspected product")
    try:
        info = path.lstat()
    except FileNotFoundError:
        info = None
    if info is not None and not stat.S_ISREG(info.st_mode):
        raise InventoryError("evidence destination must be a regular file")
    try:
        output_locations = {lexical_output, path.resolve(), *output_ancestors(path)}
    except RuntimeError as error:
        raise InventoryError("evidence paths must resolve without directory-link loops") from error
    app_locations = {lexical_app}
    app_loop = False
    try:
        app_locations.add(Path(app).resolve())
    except RuntimeError:
        # Older pathlib versions report link loops as RuntimeError.
        app_loop = True
    except OSError as error:
        if error.errno != errno.ELOOP:
            raise
        app_loop = True
    if any(product == output or product in output.parents
           for product in app_locations for output in output_locations):
        raise InventoryError("evidence must be outside the inspected product")
    if info is not None:
        path.unlink()
    if app_loop:
        raise InventoryError("built product path contains a link loop")


def write_receipt(path, receipt):
    contents = json.dumps(receipt, indent=2, sort_keys=True) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=".privacy-inventory-", delete=False) as output:
            temporary = Path(output.name)
            output.write(contents)
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print(contents, end="")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        prepare_output(args.output, args.app)
        receipt = inspect_app(args.app)
        write_receipt(args.output, receipt)
        return 0
    except InventoryError as error:
        print(f"Privacy inventory rejected: {error}.", file=sys.stderr)
    except OSError:
        print("Privacy inventory rejected: file access or evidence publication failed.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
