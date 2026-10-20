#!/usr/bin/env python3
"""Verify the separate submission SDK pin and unsigned build-product metadata."""

import argparse
import errno
import json
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile

import toolchain


APP_ROOT = Path(__file__).resolve().parents[1]
SDK_PLATFORMS = {"iphoneos": "iPhoneOS", "iphonesimulator": "iPhoneSimulator"}
GUIDANCE = "See docs/validation/submission-sdk.md. No alternate toolchain or SDK was selected."


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", value):
        raise ValueError("versions must be explicit numeric major.minor[.patch] strings")
    return tuple(int(component) for component in value.split("."))


def load_sdk_pin(path):
    try:
        data = toolchain.read_bounded(path, 4096, "SDK pin exceeds 4096 bytes")
        pin = toolchain.parse_pin_json(data)
        if not isinstance(pin, dict) or set(pin) != {"sdkVersions", "minimumOSVersion"}:
            raise ValueError("expected exactly sdkVersions and minimumOSVersion")
        sdks = pin["sdkVersions"]
        if not isinstance(sdks, dict) or set(sdks) != set(SDK_PLATFORMS):
            raise ValueError("both device and simulator SDK versions must be pinned")
        if any(version(value) < (26, 0) for value in sdks.values()):
            raise ValueError("both SDK pins must meet Apple's iOS/iPadOS 26 upload floor")
        if version(pin["minimumOSVersion"]) < (13, 0):
            raise ValueError("deployment pin is below Apple's iOS/iPadOS 13 upload floor")
        return pin
    except (OSError, ValueError) as error:
        raise toolchain.SetupError(f"Cannot read the submission SDK pin: {error}. Restore {path}. {GUIDANCE}") from error


def verify_sdks(xcode_pin, sdk_pin, runner=subprocess.run, environment=None):
    if version(xcode_pin["xcodeVersion"]) < (26, 0):
        raise toolchain.SetupError(f"Submission checks require Xcode 26 or later. {GUIDANCE}")
    verified_environment = toolchain.verify_pin(xcode_pin, runner=runner, environment=environment)
    for sdk, expected in sdk_pin["sdkVersions"].items():
        try:
            result = runner(["/usr/bin/xcrun", "--sdk", sdk, "--show-sdk-version"],
                            env=verified_environment, capture_output=True, text=True, timeout=30, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise toolchain.SetupError(f"The pinned {sdk} SDK probe could not finish. {GUIDANCE}") from error
        if result.returncode != 0 or result.stdout.strip().splitlines() != [expected]:
            raise toolchain.SetupError(f"The selected Xcode does not report the exact {sdk} SDK {expected}. {GUIDANCE}")
    return verified_environment


def inspect_product(app, sdk, xcode_pin, sdk_pin):
    if sdk not in SDK_PLATFORMS:
        raise toolchain.SetupError("Only the pinned iOS device or simulator product can be inspected.")
    try:
        data = toolchain.read_bounded(
            app / "Info.plist", 1024 * 1024, "built Info.plist exceeds the inspection bound")
        info = plistlib.loads(data)
        if not isinstance(info, dict):
            raise ValueError("built Info.plist must contain a dictionary")
        expected = {
            "DTXcodeBuild": xcode_pin["xcodeBuildVersion"],
            "DTSDKName": sdk + sdk_pin["sdkVersions"][sdk],
            "DTPlatformName": sdk,
            "DTPlatformVersion": sdk_pin["sdkVersions"][sdk],
            "MinimumOSVersion": sdk_pin["minimumOSVersion"],
            "CFBundleSupportedPlatforms": [SDK_PLATFORMS[sdk]],
        }
        for key, value in expected.items():
            if info.get(key) != value:
                raise ValueError(f"built {key} does not match the reviewed pin")
        # Retain only explicit build identity fields, not arbitrary app metadata.
        fields = (*expected, "CFBundleIdentifier", "CFBundleExecutable", "DTSDKBuild", "DTXcode")
        return {key: info.get(key) for key in fields}
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise toolchain.SetupError(f"Unsigned {sdk} product metadata verification failed: {error}. {GUIDANCE}") from error


def receipt_ancestors(path):
    """Inspect supplied ancestors and ancestry hidden inside directory-link targets."""
    pending = list(path.parents)
    seen = set()
    while pending:
        ancestor = pending.pop()
        if ancestor in seen:
            continue
        seen.add(ancestor)
        try:
            metadata = ancestor.stat()
        except FileNotFoundError as error:
            # Missing tail directories can be created after validation, but
            # resolving '..' must not erase a nonexistent traversal prefix.
            if ancestor.name == "..":
                raise toolchain.SetupError("Receipt '..' traversal requires an existing directory.") from error
        else:
            if not stat.S_ISDIR(metadata.st_mode):
                raise toolchain.SetupError("Receipt parent components must be directories.")
        yield ancestor.resolve()
        if ancestor.is_symlink():
            target = ancestor.readlink()
            if not target.is_absolute():
                target = ancestor.parent.resolve() / target
            # Retain each target prefix, including those before an internal '..'.
            pending.extend((target, *target.parents))


def invalid_input_path_reason(error):
    """Recognize unusable selected paths, not access or unexpected I/O errors."""
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


def input_prefix_identities(paths):
    """Retain ordinary input prefixes, including those hidden by link targets."""
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
            reason = invalid_input_path_reason(error)
            if reason is None:
                raise
            failure = failure or reason
            continue
        if stat.S_ISLNK(metadata.st_mode):
            # lstat establishes a traversable parent without following this
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
            # Do not resolve away a non-directory prefix before an internal
            # '..'. Physical link+parent identity bounds cyclic expansion.
            pending.extend((target, *target.parents))
        elif not stat.S_ISDIR(metadata.st_mode):
            identities.add((metadata.st_dev, metadata.st_ino))
    return identities, failure


def prepare_receipt(path, protected_paths):
    """Invalidate earlier success without removing input files or following links."""
    if path is None:
        return None
    try:
        # Resolve directory aliases, but never follow the final output component.
        output = path.parent.resolve() / path.name
        traversed = [output, *receipt_ancestors(path)]
    except RuntimeError as error:
        # Python versions that report link loops as RuntimeError still use the
        # ordinary CLI failure boundary, before any earlier receipt is removed.
        raise toolchain.SetupError("Receipt paths must resolve without directory-link loops.") from error
    boundaries = []
    identities = set()
    input_failure = None
    for protected in protected_paths:
        # Even an input that cannot resolve retains its supplied-path boundary.
        locations = [protected.absolute()]
        boundaries.extend(locations)
        try:
            boundary = protected.resolve()
            boundaries.append(boundary)
            locations.append(boundary)
            try:
                metadata = boundary.stat()
            except FileNotFoundError:
                metadata = None
        except (RuntimeError, OSError) as error:
            # Path.resolve reports ELOOP as RuntimeError on older Python;
            # newer versions can leave it for the following stat to detect.
            reason = invalid_input_path_reason(error)
            if reason is None:
                if isinstance(error, RuntimeError):
                    raise toolchain.SetupError("Cannot establish protected input boundaries before changing the receipt.") from error
                raise
            input_failure = input_failure or reason
        else:
            if metadata is not None:
                identities.add((metadata.st_dev, metadata.st_ino))
        # An invalid child can name a real file through a hidden link target.
        # Inspect both supplied and available resolved paths even when resolve
        # normalized away a non-directory prefix before an internal '..'.
        try:
            prefix_identities, prefix_failure = input_prefix_identities(locations)
        except RuntimeError as error:
            raise toolchain.SetupError("Cannot establish protected input prefixes before changing the receipt.") from error
        identities.update(prefix_identities)
        input_failure = input_failure or prefix_failure
    for boundary in boundaries:
        if any(candidate.is_relative_to(boundary) for candidate in traversed):
            raise toolchain.SetupError("Receipt output must be separate from source, pin, product and CI environment inputs.")
    # Path spelling is not filesystem identity on case-insensitive volumes.
    # Keep lexical checks for missing paths and inspect the final component
    # without following it, just as the receipt validity check below does.
    for candidate in traversed:
        try:
            metadata = candidate.lstat()
        except FileNotFoundError:
            continue
        if not stat.S_ISLNK(metadata.st_mode) and (metadata.st_dev, metadata.st_ino) in identities:
            raise toolchain.SetupError("Receipt output must be separate from source, pin, product and CI environment inputs.")
    try:
        existing = output.lstat()
    except FileNotFoundError:
        existing = None
    if existing is not None:
        if not stat.S_ISREG(existing.st_mode) or existing.st_nlink != 1:
            raise toolchain.SetupError("Receipt output must be an unshared regular file (no links or directories).")
        output.unlink()
    if input_failure is not None:
        raise toolchain.SetupError(f"A selected source, pin, product or CI environment input {input_failure}.")
    return output


def write_receipt(path, receipt):
    contents = json.dumps(receipt, indent=2, sort_keys=True) + "\n"
    if path is not None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                             prefix=".submission-sdk-", suffix=".tmp", delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(contents)
            temporary.replace(path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    print(contents, end="", flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain-pin", type=Path, default=APP_ROOT / "submission-toolchain.json")
    parser.add_argument("--sdk-pin", type=Path, default=APP_ROOT / "submission-sdk.json")
    commands = parser.add_subparsers(dest="operation", required=True)
    verify = commands.add_parser("verify", help="probe the installed Xcode and both actual SDKs before selecting CI environment")
    verify.add_argument("--github-env", type=Path)
    verify.add_argument("--output", type=Path)
    inspect = commands.add_parser("inspect", help="check an existing built app's metadata; does not execute an app or submit it")
    inspect.add_argument("--sdk", choices=tuple(SDK_PLATFORMS), required=True)
    inspect.add_argument("--app", type=Path, required=True)
    inspect.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        protected = [APP_ROOT, args.toolchain_pin, args.sdk_pin]
        if args.operation == "inspect":
            protected.append(args.app)
        elif args.github_env is not None:
            protected.append(args.github_env)
        output = prepare_receipt(args.output, protected)
        xcode_pin = toolchain.load_pin(args.toolchain_pin)
        sdk_pin = load_sdk_pin(args.sdk_pin)
        if args.operation == "verify":
            environment = verify_sdks(xcode_pin, sdk_pin)
            if args.github_env is not None:
                with args.github_env.open("a", encoding="utf-8") as stream:
                    stream.write(f"DEVELOPER_DIR={environment['DEVELOPER_DIR']}\n")
            write_receipt(output, {"xcode": xcode_pin, **sdk_pin})
        else:
            write_receipt(output, inspect_product(args.app, args.sdk, xcode_pin, sdk_pin))
        return 0
    except toolchain.SetupError as error:
        print(f"Submission SDK check failed: {error}", file=sys.stderr)
        return 2
    except OSError:
        print(f"Submission SDK check failed: cannot write the supplied evidence/environment path. {GUIDANCE}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
