#!/usr/bin/env python3
"""Verify the separate submission SDK pin and unsigned build-product metadata."""

import argparse
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
        data = path.read_bytes()
        if len(data) > 4096:
            raise ValueError("SDK pin exceeds 4096 bytes")
        pin = json.loads(data)
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
        data = (app / "Info.plist").read_bytes()
        if len(data) > 1024 * 1024:
            raise ValueError("built Info.plist exceeds the inspection bound")
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


def prepare_receipt(path, protected_paths):
    """Invalidate earlier success without removing input files or following links."""
    if path is None:
        return None
    try:
        # Resolve directory aliases, but never follow the final output component.
        output = path.parent.resolve() / path.name
        traversed = [output, *receipt_ancestors(path)]
        boundaries = [protected.resolve() for protected in protected_paths]
    except RuntimeError as error:
        # Python versions that report link loops as RuntimeError still use the
        # ordinary CLI failure boundary, before any earlier receipt is removed.
        raise toolchain.SetupError("Receipt paths must resolve without directory-link loops.") from error
    for boundary in boundaries:
        if any(candidate.is_relative_to(boundary) for candidate in traversed):
            raise toolchain.SetupError("Receipt output must be separate from source, pin, product and CI environment inputs.")
    try:
        existing = output.lstat()
    except FileNotFoundError:
        return output
    if not stat.S_ISREG(existing.st_mode) or existing.st_nlink != 1:
        raise toolchain.SetupError("Receipt output must be an unshared regular file (no links or directories).")
    output.unlink()
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
