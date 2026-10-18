#!/usr/bin/env python3
"""Run the real app UI journey on two fresh, process-owned iOS simulators.

Never resets app storage or erases/deletes a pre-existing simulator. Only verified
UDIDs returned by this invocation's create commands are eligible for cleanup.
Every invocation needs a new evidence directory, preserving earlier test results.
"""
import argparse
import json
from pathlib import Path
import shlex
import subprocess
import sys
import uuid

RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
DESTINATIONS = (("iphone", "iPhone SE (3rd generation)"), ("ipad", "iPad (10th generation)"))
TEST = "PlannerAppUITests/LocalDraftJourneyTests/testSavedNotesSurviveCloseReopenAndRelaunch"
TEST_TIMEOUT_SECONDS = 15 * 60


def select_devices(inventory):
    runtimes = [r for r in inventory["runtimes"] if r["identifier"] == RUNTIME and r.get("isAvailable")]
    if len(runtimes) != 1:
        raise ValueError("Required installed iOS 18.5 runtime unavailable or ambiguous; no fallback permitted")
    selected = []
    for label, name in DESTINATIONS:
        matches = [d for d in inventory["devicetypes"] if d["name"] == name]
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one installed device type {name}; found {len(matches)}")
        selected.append({"label": label, "deviceType": matches[0], "runtime": runtimes[0]})
    return selected


def test_command(udid, result_path):
    return [
        "xcodebuild", "test", "-project", "App/Planner.xcodeproj", "-scheme", "Planner",
        "-configuration", "Debug", "-sdk", "iphonesimulator",
        "-destination", f"platform=iOS Simulator,id={udid}", "-destination-timeout", "120",
        "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
        "-derivedDataPath", ".build/native", "-resultBundlePath", str(result_path),
        f"-only-testing:{TEST}", "CODE_SIGNING_ALLOWED=NO", "ONLY_ACTIVE_ARCH=YES",
    ]


def summary_passed(summary):
    # Fail closed for zero, skipped, failed, expected-failure, or unknown output.
    return (summary.get("result") == "Passed"
            and summary.get("totalTestCount") == 1
            and summary.get("passedTests") == 1
            and summary.get("failedTests") == 0
            and summary.get("skippedTests") == 0
            and summary.get("expectedFailures", 0) == 0)


def run_logged(command, log_path):
    print(shlex.join(command), flush=True)
    try:
        with log_path.open("w") as log:
            return subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                  text=True, check=False, timeout=TEST_TIMEOUT_SECONDS).returncode
    finally:
        # A file-backed stream remains available even after timeout/cancellation.
        if log_path.exists():
            print(log_path.read_text(), end="", flush=True)


def cleanup_simulator(udid):
    """Caller supplies only a verified ID created by this invocation."""
    results = {}
    for action in ("shutdown", "delete"):
        try:
            result = subprocess.run(["xcrun", "simctl", action, udid], capture_output=True,
                                    text=True, check=False, timeout=60)
            results[action] = {"exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
        except (OSError, subprocess.SubprocessError) as error:
            results[action] = {"error": str(error)}
    # Shutdown can legitimately report "already shutdown" after a build failure.
    # Successful deletion is the decisive owned-resource cleanup receipt.
    return results


def collect_summary(result_path, evidence, label, outcome):
    if not result_path.exists():
        outcome["summaryError"] = "No xcresult bundle was produced"
        return
    summary_run = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_path)],
        capture_output=True, text=True, check=False, timeout=60,
    )
    (evidence / f"{label}-summary.json").write_text(summary_run.stdout)
    (evidence / f"{label}-summary.stderr.txt").write_text(summary_run.stderr)
    outcome["summaryExitCode"] = summary_run.returncode
    if summary_run.returncode == 0:
        try:
            summary = json.loads(summary_run.stdout)
            outcome["verifiedPassed"] = outcome.get("xcodebuildExitCode") == 0 and summary_passed(summary)
        except (ValueError, AttributeError):
            outcome["summaryError"] = "Result summary was not the expected JSON object"


def run_destination(destination, evidence, existing_ids):
    label = destination["label"]
    result_path = evidence / f"{label}.xcresult"
    outcome = {"destination": destination, "test": TEST, "verifiedPassed": False, "cleanupSucceeded": False}
    owned_udid = None
    try:
        name = f"Planner-UI-{label}-{uuid.uuid4().hex[:12]}"
        output = subprocess.check_output(
            ["xcrun", "simctl", "create", name, destination["deviceType"]["identifier"], RUNTIME],
            text=True, timeout=60,
        ).strip()
        # Never act on an unverified or pre-existing ID if creation is uncertain.
        candidate = str(uuid.UUID(output))
        if candidate in existing_ids:
            raise ValueError("Simulator create returned a pre-existing ID; refusing to test or clean it up")
        # Normalize identity only for the ownership check. Xcode destination
        # matching requires the original simctl spelling, including letter case.
        owned_udid = output
        outcome["simulator"] = {"udid": owned_udid, "name": name, "createdByThisRun": True}
        (evidence / f"{label}-result.json").write_text(json.dumps(outcome, indent=2) + "\n")
        command = test_command(owned_udid, result_path)
        (evidence / f"{label}-command.txt").write_text(shlex.join(command) + "\n")
        try:
            outcome["xcodebuildExitCode"] = run_logged(command, evidence / f"{label}-tests.log")
        except subprocess.TimeoutExpired:
            outcome["error"] = f"xcodebuild exceeded {TEST_TIMEOUT_SECONDS} seconds"
        # Attempt a structured receipt even after an ordinary test timeout/failure.
        collect_summary(result_path, evidence, label, outcome)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        outcome["error"] = str(error)
    finally:
        if owned_udid is not None:
            outcome["cleanup"] = cleanup_simulator(owned_udid)
            outcome["cleanupSucceeded"] = outcome["cleanup"]["delete"].get("exitCode") == 0
        (evidence / f"{label}-result.json").write_text(json.dumps(outcome, indent=2) + "\n")
    return outcome


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-directory", type=Path, default=Path(".build/native-evidence/ui-journey"))
    args = parser.parse_args()
    evidence = args.evidence_directory.resolve()
    # Do not remove old bundles to make a repeated run appear new.
    evidence.mkdir(parents=True, exist_ok=False)
    inventory_text = subprocess.check_output(["xcrun", "simctl", "list", "--json"], text=True, timeout=60)
    (evidence / "simulator-inventory.json").write_text(inventory_text)
    inventory = json.loads(inventory_text)
    selected = select_devices(inventory)
    (evidence / "requested-destinations.json").write_text(json.dumps(selected, indent=2) + "\n")
    existing_ids = {str(uuid.UUID(d["udid"])) for devices in inventory["devices"].values() for d in devices}
    results = []
    for destination in selected:
        results.append(run_destination(destination, evidence, existing_ids))
        # Retain partial progress even if the second destination is interrupted.
        (evidence / "journey-results.json").write_text(json.dumps(results, indent=2) + "\n")
    if len(results) != len(DESTINATIONS) or not all(r["verifiedPassed"] and r["cleanupSucceeded"] for r in results):
        raise SystemExit("UI journey or owned-simulator cleanup failed on a pinned destination; inspect retained results")
    print("Verified one UI journey passed on each pinned iPhone/iPad simulator; no physical-device or release claim.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"UI journey could not complete: {error}", file=sys.stderr)
        raise SystemExit(1) from error
