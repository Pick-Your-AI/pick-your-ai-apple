#!/usr/bin/env python3
"""Install/launch on an available iPhone and iPad simulator; no device claim."""
import json
import os
import re
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


SNAPSHOT_TIMEOUT_SECONDS = 3
SNAPSHOT_MAX_ROWS = 40
SNAPSHOT_MAX_CHARS = 4096
SNAPSHOT_PROCESSES = frozenset({
    "simctl", "Simulator", "SimulatorTrampoline", "simulatord",
    "CoreSimulatorService", "com.apple.CoreSimulator.CoreSimulatorService",
    "launchd_sim", "SpringBoard", "backboardd", "runningboardd",
    "launchservicesd", "installd", "Planner",
})
SNAPSHOT_SERVICES = frozenset({
    "com.apple.SpringBoard", "com.apple.backboardd", "com.apple.runningboardd",
    "com.apple.lsd", "com.apple.installd",
})


def snapshot_rows(kind, output):
    """Release only fixed resource fields; never print raw process arguments."""
    if isinstance(output, bytes):
        output = output.decode("utf-8", errors="replace")
    rows, size, truncated = [], 0, False
    for line in (output or "").splitlines():
        selected = None
        if kind == "memory":
            if re.fullmatch(r"Mach Virtual Memory Statistics: \(page size of [0-9]+ bytes\)", line):
                selected = line
            elif re.fullmatch(r"(Pages (free|active|inactive|speculative|wired down|purgeable|stored in compressor|occupied by compressor)|Pageouts|Swapins|Swapouts):\s+[0-9]+\.", line):
                selected = " ".join(line.split())
        elif kind == "processes":
            fields = line.split(None, 5)
            if len(fields) == 6:
                pid, parent, state, cpu, rss, path = fields
                name = path.rsplit("/", 1)[-1]
                if (name in SNAPSHOT_PROCESSES and re.fullmatch(r"[0-9]+", pid)
                        and re.fullmatch(r"[0-9]+", parent) and re.fullmatch(r"[A-Za-z+<>-]+", state)
                        and re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", cpu)
                        and re.fullmatch(r"[0-9]+", rss)):
                    selected = " ".join((pid, parent, state, cpu, rss, name))
        elif kind == "services":
            fields = line.split(None, 2)
            if len(fields) == 3:
                pid, status, label = fields
                app_label = f"UIKitApplication:{APP_BUNDLE_ID}"
                if label == app_label or label.startswith(app_label + "["):
                    label = APP_BUNDLE_ID
                if (label in SNAPSHOT_SERVICES or label == APP_BUNDLE_ID) and re.fullmatch(r"-|[0-9]+", pid) and re.fullmatch(r"-?[0-9]+", status):
                    selected = " ".join((pid, status, label))
        if selected is not None:
            if len(rows) == SNAPSHOT_MAX_ROWS or size + len(selected) > SNAPSHOT_MAX_CHARS:
                truncated = True
                break
            rows.append(selected)
            size += len(selected)
    return rows, truncated


def snapshot_probe(kind, command):
    """A short read-only observation; its failure cannot qualify or fail launch."""
    output = None
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=False,
                                timeout=SNAPSHOT_TIMEOUT_SECONDS)
        status = {"exit": result.returncode}
        output = result.stdout
    except subprocess.TimeoutExpired as error:
        status = {"error": "timeout"}
        output = error.stdout
    except Exception as error:
        status = {"error": type(error).__name__}
    rows, truncated = snapshot_rows(kind, output)
    return {"probe": kind, "deadline_seconds": SNAPSHOT_TIMEOUT_SECONDS,
            **status, "rows": rows, "truncated": truncated}


def collect_runtime_snapshot(udid, phase):
    """Observe this verified owned destination without waiting for readiness."""
    try:
        load = list(os.getloadavg())
    except Exception as error:
        load = {"error": type(error).__name__}
    print(json.dumps({"smoke_snapshot": phase, "owned_udid": udid,
                      "host_load_averages": load}, sort_keys=True), flush=True)
    commands = (
        ("memory", ("/usr/bin/vm_stat",)),
        ("processes", ("/bin/ps", "-axo", "pid=,ppid=,state=,%cpu=,rss=,comm=")),
        ("services", ("xcrun", "simctl", "spawn", udid, "launchctl", "list")),
    )
    for kind, command in commands:
        try:
            observation = snapshot_probe(kind, command)
            print(json.dumps({"smoke_snapshot": phase, "owned_udid": udid,
                              **observation}, sort_keys=True), flush=True)
        except Exception as error:
            print(json.dumps({"smoke_snapshot": phase, "owned_udid": udid,
                              "probe": kind, "error": type(error).__name__},
                             sort_keys=True), flush=True)


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
            try:
                print(f"Owned simulator {action} did not complete for {udid}: {error}", file=sys.stderr, flush=True)
            except Exception:
                # Warning output must not stop owned cleanup or replace the
                # original operation failure.
                pass
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
            try:
                print(f"Launch diagnostic did not complete for {udid}: {error}", file=sys.stderr, flush=True)
            except Exception:
                # An unavailable output sink cannot stop the remaining probes.
                pass


def observe_runtime(udid, phase):
    """Reuse bounded filtered probes without changing required operations or cleanup."""
    try:
        collect_runtime_snapshot(udid, phase)
    except Exception as error:
        try:
            print(json.dumps({"smoke_snapshot": phase, "owned_udid": udid,
                              "error": type(error).__name__}, sort_keys=True), flush=True)
        except Exception:
            # Even an unavailable observation sink must not replace the actual
            # boot/install outcome or prevent finally from attempting owned cleanup.
            pass


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
        observe_runtime(udid, "before-boot")
        try:
            run("xcrun", "simctl", "boot", udid)
            run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=BOOT_TIMEOUT_SECONDS)
        except (OSError, subprocess.SubprocessError):
            observe_runtime(udid, "boot-failed")
            raise
        observe_runtime(udid, "before-install")
        try:
            run("xcrun", "simctl", "install", udid,
                ".build/native/Build/Products/Debug-iphonesimulator/Planner.app", timeout=INSTALL_TIMEOUT_SECONDS)
        except (OSError, subprocess.SubprocessError):
            observe_runtime(udid, "install-failed")
            raise
        observe_runtime(udid, "before-launch")
        try:
            # This simulator was just created and the app just installed. There
            # is no earlier runner-owned app process to terminate before launch.
            run("xcrun", "simctl", "launch", udid, APP_BUNDLE_ID)
        except (OSError, subprocess.SubprocessError):
            observe_runtime(udid, "launch-failed")
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
