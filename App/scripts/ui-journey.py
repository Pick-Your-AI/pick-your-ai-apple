#!/usr/bin/env python3
"""Run the real app UI journey on the pinned installed iPhone/iPad simulators.

Does not erase, delete, clone, or create a simulator or reset app storage. Every
invocation needs a new evidence directory, preserving earlier test results.
"""
import argparse
import json
from pathlib import Path
import shlex
import subprocess
import sys

RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
DESTINATIONS = (("iphone", "iPhone SE (3rd generation)"), ("ipad", "iPad (10th generation)"))
TEST = "PlannerAppUITests/LocalDraftJourneyTests/testSavedNotesSurviveCloseReopenAndRelaunch"


def select_devices(inventory):
    runtimes = [r for r in inventory["runtimes"] if r["identifier"] == RUNTIME and r.get("isAvailable")]
    if len(runtimes) != 1:
        raise ValueError("Required installed iOS 18.5 runtime unavailable or ambiguous; no fallback permitted")
    selected = []
    for label, name in DESTINATIONS:
        matches = [d for d in inventory["devices"].get(RUNTIME, []) if d["name"] == name and d.get("isAvailable")]
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one available {name} on iOS 18.5; found {len(matches)}")
        selected.append({"label": label, "device": matches[0], "runtime": runtimes[0]})
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
    with log_path.open("w") as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="", flush=True)
            log.write(line)
        return process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-directory", type=Path, default=Path(".build/native-evidence/ui-journey"))
    args = parser.parse_args()
    evidence = args.evidence_directory.resolve()
    # Do not remove old bundles to make a repeated run appear new.
    evidence.mkdir(parents=True, exist_ok=False)
    inventory_text = subprocess.check_output(["xcrun", "simctl", "list", "--json"], text=True)
    (evidence / "simulator-inventory.json").write_text(inventory_text)
    selected = select_devices(json.loads(inventory_text))
    (evidence / "simulator-selection.json").write_text(json.dumps(selected, indent=2) + "\n")
    results = []
    for destination in selected:
        label = destination["label"]
        result_path = evidence / f"{label}.xcresult"
        command = test_command(destination["device"]["udid"], result_path)
        (evidence / f"{label}-command.txt").write_text(shlex.join(command) + "\n")
        exit_code = run_logged(command, evidence / f"{label}-tests.log")
        outcome = {"destination": destination, "test": TEST, "xcodebuildExitCode": exit_code, "verifiedPassed": False}
        # Always try to retain structured results, including for a failed run.
        if result_path.exists():
            summary_run = subprocess.run(
                ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_path)],
                capture_output=True, text=True, check=False,
            )
            (evidence / f"{label}-summary.json").write_text(summary_run.stdout)
            (evidence / f"{label}-summary.stderr.txt").write_text(summary_run.stderr)
            outcome["summaryExitCode"] = summary_run.returncode
            if summary_run.returncode == 0:
                try:
                    summary = json.loads(summary_run.stdout)
                    outcome["verifiedPassed"] = exit_code == 0 and summary_passed(summary)
                except (ValueError, AttributeError):
                    outcome["error"] = "Result summary was not the expected JSON object"
        results.append(outcome)
        # Retain partial progress even if the second destination is interrupted.
        (evidence / "journey-results.json").write_text(json.dumps(results, indent=2) + "\n")
    if len(results) != len(DESTINATIONS) or not all(r["verifiedPassed"] for r in results):
        raise SystemExit("UI journey was not verified passed on both exact destinations; inspect retained results")
    print("Verified one UI journey passed on each pinned iPhone/iPad simulator; no physical-device or release claim.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"UI journey could not complete: {error}", file=sys.stderr)
        raise SystemExit(1) from error
