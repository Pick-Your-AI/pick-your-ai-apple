#!/usr/bin/env python3
"""Run the real app UI journey on two fresh, process-owned iOS simulators.

Never resets app storage or erases/deletes a pre-existing simulator. Only verified
UDIDs returned by this invocation's create commands are eligible for cleanup.
Every invocation needs a new evidence directory, preserving earlier test results.
"""
import argparse
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time
import uuid

RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
DESTINATIONS = (("iphone", "iPhone SE (3rd generation)"), ("ipad", "iPad (10th generation)"))
TESTS = (
    "PlannerAppUITests/LocalDraftJourneyTests/testSavedNotesSurviveCloseReopenAndRelaunch",
    "PlannerAppUITests/CatalogBrowserJourneyTests/testCatalogFiltersPaginationAndPinnedDetailsSurviveRelaunch",
)
T6_TESTS = (
    "PlannerAppUITests/T6ReviewJourneyTests/testAbsentQualityIsVisibleAfterReportedCompatibilityAndDismissal",
    "PlannerAppUITests/T6ReviewJourneyTests/testReportedFailureAndPendingPlanRemainVisibleWithoutDeploymentAction",
    "PlannerAppUITests/T6ReviewJourneyTests/testReportDisclosurePreviewAndFilesCancellationKeepThePrivatePlan",
    "PlannerAppUITests/T6ReviewJourneyTests/testLeavingImportedBuildsWithdrawsReportPreviewAndReopensRetainedInputs",
)
PLANNING_TESTS = (
    "PlannerAppUITests/LocalDraftJourneyTests/testPlanningInputsPreserveUnansweredInvalidTextAndRestoredRevisions",
)
SUITES = {"local": TESTS, "t6": T6_TESTS, "all": TESTS + T6_TESTS + PLANNING_TESTS}
# Allow the seven selected journeys to run after a fresh build; keep a finite bound.
TEST_TIMEOUT_SECONDS = 45 * 60


def report_inventory_evidence_error(message):
    try:
        print(message, file=sys.stderr)
    except (OSError, ValueError):
        # Closed streams also raise ValueError. Neither reporting failure may
        # replace the original command failure.
        pass


def collect_inventory(evidence, requested_destination):
    """Retain the single bounded inventory attempt before selecting any device."""
    command = ["xcrun", "simctl", "list", "--json"]
    attempt = {
        "phase": "simulator-inventory-before-device-selection",
        "command": command, "timeoutSeconds": 60,
        "requestedRuntime": RUNTIME, "requestedDestination": requested_destination,
        "simulatorCreatedByThisInvocation": False, "journeyStarted": False,
        "stderrFile": "simulator-inventory.stderr.bin",
    }
    started = time.monotonic()
    stderr = (evidence / attempt["stderrFile"]).open("wb")
    returned = False
    try:
        inventory_text = subprocess.check_output(command, text=True, timeout=60, stderr=stderr)
        returned = True
    except (OSError, subprocess.SubprocessError) as error:
        attempt.update(outcome="failed", durationSeconds=time.monotonic() - started,
                       errorClass=type(error).__name__, error=str(error),
                       exitCode=getattr(error, "returncode", None))
        try:
            # TimeoutExpired.output can be bytes even with text=True. Never
            # decode away malformed or partial output from a failed command.
            output = getattr(error, "output", None)
            representation = "absent" if output is None else "bytes" if isinstance(output, bytes) else "text"
            raw = b"" if output is None else output if isinstance(output, bytes) else output.encode("utf-8")
            (evidence / "simulator-inventory.stdout.bin").write_bytes(raw)
            attempt["stdout"] = {"file": "simulator-inventory.stdout.bin",
                                 "representation": representation, "byteCount": len(raw)}
            (evidence / "simulator-inventory-attempt.json").write_text(json.dumps(attempt, indent=2) + "\n")
        except OSError as evidence_error:
            report_inventory_evidence_error(f"Could not retain simulator inventory failure evidence: {evidence_error}")
        # Evidence failure must not replace the original command failure.
        raise
    finally:
        try:
            stderr.close()
        except OSError as close_error:
            if returned:
                raise
            report_inventory_evidence_error(f"Could not close simulator inventory stderr evidence: {close_error}")
    attempt.update(outcome="returned", durationSeconds=time.monotonic() - started,
                   errorClass=None, exitCode=0,
                   stdout={"file": "simulator-inventory.json", "representation": "text"})
    (evidence / "simulator-inventory.json").write_text(inventory_text)
    (evidence / "simulator-inventory-attempt.json").write_text(json.dumps(attempt, indent=2) + "\n")
    return inventory_text


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


def test_command(udid, result_path, tests=TESTS):
    return [
        "xcodebuild", "test", "-project", "App/Planner.xcodeproj", "-scheme", "Planner",
        "-configuration", "Debug", "-sdk", "iphonesimulator",
        "-destination", f"platform=iOS Simulator,id={udid}", "-destination-timeout", "120",
        "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
        "-derivedDataPath", ".build/native", "-resultBundlePath", str(result_path),
        *[f"-only-testing:{test}" for test in tests], "CODE_SIGNING_ALLOWED=NO", "ONLY_ACTIVE_ARCH=YES",
    ]


def summary_passed(summary, tests=TESTS):
    # Fail closed for zero, skipped, failed, expected-failure, or unknown output.
    return (summary.get("result") == "Passed"
            and summary.get("totalTestCount") == len(tests)
            and summary.get("passedTests") == len(tests)
            and summary.get("failedTests") == 0
            and summary.get("skippedTests") == 0
            and summary.get("expectedFailures", 0) == 0)


def recorded_methods_passed(text, tests=TESTS):
    """Require each selected real XCTest start/pass once, as well as the summary."""
    expected = {(module + "." + suite, method) for module, suite, method in
                (test.split("/") for test in tests)}
    starts = re.findall(r"^Test Case '-\[([^ ]+) (test\w+)\]' started\.$", text, re.M)
    results = re.findall(r"^Test Case '-\[([^ ]+) (test\w+)\]' (passed|failed|skipped) \([^\r\n]+\)\.$", text, re.M)
    return (len(expected) == len(tests) == len(starts) == len(results)
            and set(starts) == expected and {tuple(row[:2]) for row in results} == expected
            and all(row[2] == "passed" for row in results))


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


def collect_summary(result_path, evidence, label, outcome, tests=TESTS):
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
            outcome["executionIdentitiesPassed"] = recorded_methods_passed(
                (evidence / f"{label}-tests.log").read_text(), tests)
            outcome["verifiedPassed"] = (outcome.get("xcodebuildExitCode") == 0
                and summary_passed(summary, tests) and outcome["executionIdentitiesPassed"])
        except (ValueError, AttributeError):
            outcome["summaryError"] = "Result summary was not the expected JSON object"


def run_destination(destination, evidence, existing_ids, tests=TESTS):
    label = destination["label"]
    result_path = evidence / f"{label}.xcresult"
    outcome = {"destination": destination, "tests": list(tests), "verifiedPassed": False, "cleanupSucceeded": False}
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
        command = test_command(owned_udid, result_path, tests)
        (evidence / f"{label}-command.txt").write_text(shlex.join(command) + "\n")
        try:
            outcome["xcodebuildExitCode"] = run_logged(command, evidence / f"{label}-tests.log")
        except subprocess.TimeoutExpired:
            outcome["error"] = f"xcodebuild exceeded {TEST_TIMEOUT_SECONDS} seconds"
        # Attempt a structured receipt even after an ordinary test timeout/failure.
        collect_summary(result_path, evidence, label, outcome, tests)
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
    parser.add_argument("--suite", choices=tuple(SUITES), default="local")
    parser.add_argument("--destination", choices=("both", "iphone", "ipad"), default="both")
    args = parser.parse_args()
    tests = SUITES[args.suite]
    evidence = args.evidence_directory.resolve()
    # Do not remove old bundles to make a repeated run appear new.
    evidence.mkdir(parents=True, exist_ok=False)
    inventory_text = collect_inventory(evidence, args.destination)
    inventory = json.loads(inventory_text)
    selected = select_devices(inventory)
    if args.destination != "both":
        selected = [row for row in selected if row["label"] == args.destination]
    (evidence / "requested-destinations.json").write_text(json.dumps(selected, indent=2) + "\n")
    existing_ids = {str(uuid.UUID(d["udid"])) for devices in inventory["devices"].values() for d in devices}
    results = []
    for destination in selected:
        results.append(run_destination(destination, evidence, existing_ids, tests))
        # Retain partial progress even if the second destination is interrupted.
        (evidence / "journey-results.json").write_text(json.dumps(results, indent=2) + "\n")
    if len(results) != len(selected) or not all(r["verifiedPassed"] and r["cleanupSucceeded"] for r in results):
        raise SystemExit("UI journey or owned-simulator cleanup failed on a pinned destination; inspect retained results")
    print(f"Verified {len(tests)} declared UI journeys passed on {', '.join(row['label'] for row in selected)}; "
          "no physical-device or release claim.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"UI journey could not complete: {error}", file=sys.stderr)
        raise SystemExit(1) from error
