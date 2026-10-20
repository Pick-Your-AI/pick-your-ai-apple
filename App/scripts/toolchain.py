#!/usr/bin/env python3
"""Verify the repository's exact Xcode pin before running native commands."""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

DEFAULT_PIN = Path(__file__).resolve().parents[1] / "toolchain.json"


class SetupError(Exception):
    pass


def read_bounded(path, maximum_bytes, oversized_message):
    """Read only the permitted input plus one byte needed to detect overflow."""
    def open_regular_file(name, flags):
        # A FIFO must not wait for a writer before its opened type is checked.
        descriptor = os.open(name, flags | getattr(os, "O_NONBLOCK", 0))
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise ValueError("input must be a regular file")
        except BaseException:
            os.close(descriptor)
            raise
        return descriptor

    with open(path, "rb", opener=open_regular_file) as stream:
        data = stream.read(maximum_bytes + 1)
    if len(data) > maximum_bytes:
        raise ValueError(oversized_message)
    return data


def load_pin(path):
    try:
        data = read_bounded(path, 4096, "pin file exceeds 4096 bytes")
        pin = json.loads(data)
        if not isinstance(pin, dict) or set(pin) != {"developerDirectory", "xcodeVersion", "xcodeBuildVersion"}:
            raise ValueError("expected exactly the documented pin fields")
        if any(not isinstance(value, str) or not value or any(ord(c) < 32 or ord(c) == 127 for c in value)
               for value in pin.values()):
            raise ValueError("pin fields must be nonempty text without control characters")
        directory = Path(pin["developerDirectory"])
        if not directory.is_absolute() or not str(directory).endswith(".app/Contents/Developer"):
            raise ValueError("developerDirectory must name an absolute Xcode.app/Contents/Developer path")
        if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", pin["xcodeVersion"]):
            raise ValueError("invalid Xcode version")
        if not re.fullmatch(r"[0-9A-Za-z]+", pin["xcodeBuildVersion"]):
            raise ValueError("invalid Xcode build version")
        return pin
    except (OSError, ValueError) as error:
        raise SetupError(f"Cannot read the Xcode pin: {error}. Restore {path} from the reviewed checkout; "
                         "see App/README.md#pinned-toolchain. No alternate toolchain was selected.") from error


def instructions(pin):
    return (f"Install Xcode {pin['xcodeVersion']} (build {pin['xcodeBuildVersion']}) from "
            "https://developer.apple.com/download/all/ at "
            f"{pin['developerDirectory']}. Open that Xcode once to complete its component and license setup, "
            "then rerun this command. See App/README.md#pinned-toolchain. "
            "No alternate installed Xcode was selected.")


def verify_pin(pin, runner=subprocess.run, environment=None):
    environment = dict(os.environ if environment is None else environment)
    directory = Path(pin["developerDirectory"])
    if not directory.is_dir():
        raise SetupError(f"Required developer directory is unavailable: {directory}. {instructions(pin)}")
    environment["DEVELOPER_DIR"] = str(directory)
    try:
        result = runner(["/usr/bin/xcodebuild", "-version"], env=environment, capture_output=True,
                        text=True, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SetupError(f"The pinned Xcode version probe could not finish. {instructions(pin)}") from error
    expected = [f"Xcode {pin['xcodeVersion']}", f"Build version {pin['xcodeBuildVersion']}"]
    if result.returncode != 0 or result.stdout.strip().splitlines() != expected:
        raise SetupError(f"The installed bundle does not report the exact required Xcode version/build. "
                         f"{instructions(pin)}")
    return environment


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pin", type=Path, default=DEFAULT_PIN, help="explicit pin file; never an inferred fallback")
    parser.add_argument("--github-env", type=Path, help="append the verified DEVELOPER_DIR for later CI steps")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="optional command after --, run with the verified pin")
    args = parser.parse_args(argv)
    try:
        pin = load_pin(args.pin)
        environment = verify_pin(pin)
        if args.github_env is not None:
            with args.github_env.open("a", encoding="utf-8") as output:
                output.write(f"DEVELOPER_DIR={environment['DEVELOPER_DIR']}\n")
        print(f"Verified Xcode {pin['xcodeVersion']} ({pin['xcodeBuildVersion']}) at "
              f"{pin['developerDirectory']}", flush=True)
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if command:
            return subprocess.run(command, env=environment, check=False).returncode
        return 0
    except SetupError as error:
        print(f"Native toolchain setup failed: {error}", file=sys.stderr)
        return 2
    except OSError:
        print("Native toolchain setup failed: the verified environment could not be written or the requested "
              "command could not be started. Check the supplied path/command and rerun; "
              "see App/README.md#pinned-toolchain.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
