#!/usr/bin/env python3
"""Install/launch on an available iPhone and iPad simulator; no device claim."""
import json
import shlex
import subprocess
import sys
import uuid

COMMAND_TIMEOUT_SECONDS = 60
INSTALL_TIMEOUT_SECONDS = 3 * 60
BOOT_TIMEOUT_SECONDS = 5 * 60
CLEANUP_TIMEOUT_SECONDS = 60
DIAGNOSTIC_TIMEOUT_SECONDS = 15
APP_BUNDLE_ID = "invalid.pickyourai.localpreview"


def emit_output(stdout, stderr):
    # TimeoutExpired can contain bytes even when text=True was requested.
    for value, stream in ((stdout, sys.stdout), (stderr, sys.stderr)):
        if isinstance(value, bytes):
            value = value.decode("utf-8", errors="replace")
        if value:
            print(value, end="" if value.endswith("\n") else "\n", file=stream, flush=True)


def run(*args, timeout=COMMAND_TIMEOUT_SECONDS):
    command = shlex.join(args)
    print(f"Smoke command (deadline {timeout}s): {command}", flush=True)
    try:
        result = subprocess.run(args, capture_output=True, text=True, check=False, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        emit_output(error.stdout, error.stderr)
        print(f"Smoke command timed out after {timeout}s: {command}", file=sys.stderr, flush=True)
        raise
    emit_output(result.stdout, result.stderr)
    print(f"Smoke command exited {result.returncode}: {command}", flush=True)
    result.check_returncode()
    return result.stdout.strip()


def cleanup_simulator(udid):
    """Only a verified new ID returned by this invocation is eligible."""
    deleted = False
    for action in ("shutdown", "delete"):
        try:
            run("xcrun", "simctl", action, udid, timeout=CLEANUP_TIMEOUT_SECONDS)
            if action == "delete":
                deleted = True
        except (OSError, subprocess.SubprocessError) as error:
            print(f"Owned simulator {action} did not complete for {udid}: {error}", file=sys.stderr, flush=True)
    # An already-shutdown simulator can reject shutdown. Successful deletion
    # remains the decisive receipt, matching the actual UI runner's convention.
    return deleted


def collect_launch_diagnostics(udid):
    """Read only the verified owned simulator after its launch command failed."""
    commands = (
        ("xcrun", "simctl", "get_app_container", udid, APP_BUNDLE_ID, "app"),
        ("xcrun", "simctl", "spawn", udid, "log", "show", "--style", "compact",
         "--last", "2m", "--info", "--predicate",
         f'process == "Planner" OR eventMessage CONTAINS "{APP_BUNDLE_ID}"'),
    )
    for command in commands:
        try:
            run(*command, timeout=DIAGNOSTIC_TIMEOUT_SECONDS)
        except Exception as error:
            # Diagnostics are best effort. Their failure must not replace the
            # original launch failure or prevent the remaining finally cleanup.
            print(f"Launch diagnostic did not complete for {udid}: {error}", file=sys.stderr, flush=True)


def smoke_destination(device, runtime, family, existing_ids):
    udid = None
    cleanup_succeeded = False
    try:
        name = f"Planner-{family}-CI"
        output = run("xcrun", "simctl", "create", name, device["identifier"], runtime["identifier"])
        if uuid.UUID(output) in existing_ids:
            raise ValueError("Simulator create returned a pre-existing ID; refusing to use or clean it up")
        # Preserve simctl's exact spelling for all commands. A failed/timed-out
        # create, partial output or unparseable ID never establishes ownership.
        udid = output
        print(f"Owned simulator created by this run: {udid} ({name})", flush=True)
        print(f"Smoke launch: {device['name']}, iOS {runtime['version']}", flush=True)
        run("xcrun", "simctl", "boot", udid)
        run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=BOOT_TIMEOUT_SECONDS)
        run("xcrun", "simctl", "install", udid,
            ".build/native/Build/Products/Debug-iphonesimulator/Planner.app", timeout=INSTALL_TIMEOUT_SECONDS)
        try:
            run("xcrun", "simctl", "launch", "--terminate-running-process", udid, APP_BUNDLE_ID)
        except (OSError, subprocess.SubprocessError):
            collect_launch_diagnostics(udid)
            raise
        run("xcrun", "simctl", "terminate", udid, APP_BUNDLE_ID)
    finally:
        if udid is not None:
            cleanup_succeeded = cleanup_simulator(udid)
    if not cleanup_succeeded:
        raise ValueError(f"Owned simulator cleanup did not delete {udid}; inspect the retained command results")


def main():
    inventory = json.loads(run("xcrun", "simctl", "list", "--json"))
    existing_ids = {uuid.UUID(d["udid"]) for devices in inventory["devices"].values() for d in devices}
    runtimes = [r for r in inventory["runtimes"] if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
    if not runtimes:
        raise ValueError("No available iOS simulator runtime")
    runtime = max(runtimes, key=lambda r: tuple(int(v) for v in r["version"].split(".")))
    for family in ("iPhone", "iPad"):
        available = [d for d in inventory["devices"].get(runtime["identifier"], [])
                     if d.get("isAvailable") and d["name"].startswith(family)]
        if not available:
            raise ValueError(f"No available {family} for {runtime['name']}")
        compatible = available[0]
        device = next(d for d in inventory["devicetypes"] if d["name"] == compatible["name"])
        smoke_destination(device, runtime, family, existing_ids)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Simulator smoke could not complete: {error}", file=sys.stderr, flush=True)
        raise SystemExit(1) from error
