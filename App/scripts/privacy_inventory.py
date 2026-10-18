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


def invalid_app_path_reason(error):
    """Recognize structural path failures without treating unknown access as safe."""
    if isinstance(error, OSError):
        return {
            errno.ELOOP: "contains a link loop",
            errno.ENOTDIR: "contains a non-directory prefix",
            errno.ENAMETOOLONG: "contains an overlong name",
        }.get(error.errno)
    if isinstance(error, RuntimeError):
        cause = error.__cause__ or error.__context__
        if ((isinstance(cause, OSError) and cause.errno == errno.ELOOP)
                or str(error).startswith("Symlink loop from ")):
            return "contains a link loop"
    return None


def app_prefix_identities(paths):
    """Retain non-directory input prefixes, including hidden link-target ancestry."""
    pending = [prefix for path in paths for prefix in (path, *path.parents)]
    seen = set()
    expanded_links = set()
    identities = set()
    failure = None
    while pending:
        prefix = pending.pop()
        if prefix in seen:
            continue
        seen.add(prefix)
        try:
            metadata = prefix.lstat()
        except FileNotFoundError:
            continue
        except OSError as error:
            reason = invalid_app_path_reason(error)
            if reason is None:
                raise
            failure = failure or reason
            continue
        if stat.S_ISLNK(metadata.st_mode):
            # lstat proves this parent is traversable without following the
            # final link. Relative targets belong to that actual directory.
            parent = prefix.parent.resolve()
            parent_metadata = parent.stat()
            identity = (metadata.st_dev, metadata.st_ino,
                        parent_metadata.st_dev, parent_metadata.st_ino)
            if identity in expanded_links:
                continue
            expanded_links.add(identity)
            target = prefix.readlink()
            if not target.is_absolute():
                target = parent / target
            # Preserve components before '..'; physical link+parent identity
            # prevents relative cycles from expanding without bound.
            pending.extend((target, *target.parents))
        elif not stat.S_ISDIR(metadata.st_mode):
            identities.add((metadata.st_dev, metadata.st_ino))
    return identities, failure


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
    app_failure = None
    try:
        app_locations.add(Path(app).resolve())
    except (RuntimeError, OSError) as error:
        app_failure = invalid_app_path_reason(error)
        if app_failure is None:
            if isinstance(error, RuntimeError):
                raise InventoryError("cannot establish the inspected product boundary") from error
            raise
    if any(product == output or product in output.parents
           for product in app_locations for output in output_locations):
        raise InventoryError("evidence must be outside the inspected product")
    # Different path spellings can identify the same directory on native volumes.
    identities = set()
    for product in app_locations:
        try:
            metadata = product.stat()
        except FileNotFoundError:
            continue
        except (RuntimeError, OSError) as error:
            reason = invalid_app_path_reason(error)
            if reason is None:
                if isinstance(error, RuntimeError):
                    raise InventoryError("cannot establish the inspected product identity") from error
                raise
            app_failure = app_failure or reason
        else:
            identities.add((metadata.st_dev, metadata.st_ino))
    # Do not normalize away a supplied non-directory prefix before '..'. An
    # invalid app can still name an owned file through a hidden link target.
    try:
        prefix_identities, prefix_failure = app_prefix_identities(
            {Path(app).absolute(), *app_locations})
    except RuntimeError as error:
        raise InventoryError("cannot establish the inspected product prefixes") from error
    identities.update(prefix_identities)
    app_failure = app_failure or prefix_failure
    for output in output_locations:
        try:
            metadata = output.lstat()
        except FileNotFoundError:
            continue
        if not stat.S_ISLNK(metadata.st_mode) and (metadata.st_dev, metadata.st_ino) in identities:
            raise InventoryError("evidence must be outside the inspected product")
    if info is not None:
        path.unlink()
    if app_failure is not None:
        raise InventoryError(f"built product path {app_failure}")


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
