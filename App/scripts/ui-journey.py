#!/usr/bin/env python3
"""Run the real app UI journey on two fresh, process-owned iOS simulators.

Never resets app storage or erases/deletes a pre-existing simulator. Only verified
UDIDs returned by this invocation's create commands are eligible for cleanup.
Every invocation needs a new evidence directory, preserving earlier test results.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import threading
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


class InventoryObserver:
    """Observe one pending inventory call without changing its command or result."""
    delay_seconds = 20
    budget_seconds = 10

    def __init__(self, evidence):
        self.evidence = evidence
        self.stopped = threading.Event()
        self.worker = threading.Thread(target=self.capture, daemon=True)
        self.deadline = None

    def start(self):
        self.worker.start()

    def stop(self):
        self.stopped.set()
        # The observer reaps only its own diagnostic child when cancelled.
        # A stuck OS launch or file operation must not hold the inventory caller.
        self.worker.join(timeout=1)

    def command(self, argv, stem, timeout):
        record = {"command": argv, "stdoutFile": stem + ".stdout.bin",
                  "stderrFile": stem + ".stderr.bin", "outcome": "not-started"}
        remaining = self.deadline - time.monotonic()
        if self.stopped.is_set() or remaining <= 0:
            record["reason"] = "inventory-finished" if self.stopped.is_set() else "observer-budget-exhausted"
            return record
        bound = min(timeout, remaining)
        record["timeoutSeconds"] = bound
        process = None
        started = time.monotonic()
        try:
            with (self.evidence / record["stdoutFile"]).open("xb") as stdout, \
                    (self.evidence / record["stderrFile"]).open("xb") as stderr:
                if self.stopped.is_set() or time.monotonic() - started >= bound:
                    record["reason"] = "inventory-finished-or-observer-budget-exhausted"
                    return record
                process = subprocess.Popen(argv, stdout=stdout, stderr=stderr)
                record["diagnosticPID"] = process.pid
                if self.stopped.is_set():
                    record["outcome"] = "cancelled"
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=0.5)
                while process.poll() is None:
                    if self.stopped.is_set() or time.monotonic() - started >= bound:
                        record["outcome"] = "cancelled" if self.stopped.is_set() else "timed-out"
                        process.kill()
                        process.wait(timeout=0.5)
                        break
                    self.stopped.wait(0.05)
                if record["outcome"] == "not-started":
                    record["outcome"] = "returned"
                record["exitCode"] = process.returncode
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=0.5)
        record["durationSeconds"] = time.monotonic() - started
        return record

    @staticmethod
    def processes(raw):
        # comm excludes argument/environment fields. Preserve its full reported
        # spelling, including spaces; it is not a verified binary identity.
        if len(raw) > 1024 * 1024:
            raise ValueError("Diagnostic process table exceeded one MiB")
        rows = []
        for line in raw.decode("utf-8").splitlines():
            if not line.strip():
                continue
            fields = line.split(None, 7)
            if len(fields) != 8:
                raise ValueError("Diagnostic process table has incomplete fields")
            pid, parent = fields[:2]
            if not pid.isdecimal() or not parent.isdecimal() or int(pid) <= 0:
                raise ValueError("Diagnostic process table has an invalid identity")
            rows.append({"pid": int(pid), "parentPID": int(parent),
                         "reportedStartTime": " ".join(fields[2:7]), "reportedCommand": fields[7]})
        return rows

    @staticmethod
    def targets(rows, parent_pid):
        child = [row for row in rows if row["parentPID"] == parent_pid
                 and Path(row["reportedCommand"]).name in ("xcrun", "simctl")]
        service = [row for row in rows if Path(row["reportedCommand"]).name == "simdiskimaged"]
        # An ambiguous service or child is evidence, never permission to pick one.
        return [group[0] for group in (child, service) if len(group) == 1]

    def capture(self):
        if self.stopped.wait(self.delay_seconds):
            return
        record = {"scope": "same-pending-inventory-attempt", "delaySeconds": self.delay_seconds,
                  "budgetSeconds": self.budget_seconds, "parentPID": os.getpid(),
                  "selectionIsInferred": True,
                  "identityLimit": "PID/PPID/start-time/comm rechecks are reported snapshots, not a process handle or verified binary identity.",
                  "environment": {key: os.environ[key] for key in
                                  ("DEVELOPER_DIR", "ImageOS", "ImageVersion", "RUNNER_OS", "RUNNER_ARCH")
                                  if key in os.environ}, "commands": [], "samples": []}
        self.deadline = time.monotonic() + self.budget_seconds
        owns_directory = False
        try:
            if self.stopped.is_set():
                return
            # All diagnostic filesystem work belongs to this daemon, including
            # setup and the initial marker. The inventory caller never waits on it.
            self.evidence.mkdir(exist_ok=False)
            owns_directory = True
            (self.evidence / "pending.json").write_text(json.dumps({
                "observerStarted": True, "inventoryStillPendingAtStart": not self.stopped.is_set(),
                "completionFile": "observation.json",
            }) + "\n")
            table = self.command(["/bin/ps", "-ww", "-ax", "-o", "pid=,ppid=,lstart=,comm="], "processes", 2)
            record["commands"].append(table)
            if table["outcome"] != "returned" or table["exitCode"] != 0:
                return
            rows = self.processes((self.evidence / table["stdoutFile"]).read_bytes())
            relevant = [row for row in rows if row["parentPID"] == record["parentPID"]
                        or Path(row["reportedCommand"]).name in
                        ("simdiskimaged", "com.apple.CoreSimulator.CoreSimulatorService")]
            record["relevantProcesses"] = relevant
            selected = self.targets(rows, record["parentPID"])
            record["selectedTargets"] = selected
            for index, target in enumerate(selected):
                if self.stopped.is_set():
                    break
                stem = "target-" + str(index)
                check = self.command(["/bin/ps", "-ww", "-p", str(target["pid"]),
                                      "-o", "pid=,ppid=,lstart=,comm="], stem + "-identity", 1)
                record["commands"].append(check)
                if (check["outcome"] != "returned" or check["exitCode"] != 0
                        or self.processes((self.evidence / check["stdoutFile"]).read_bytes()) != [target]):
                    record["samples"].append({"target": target, "outcome": "identity-unavailable-or-changed"})
                    continue
                sample_file = self.evidence / (stem + "-sample.txt")
                if sample_file.exists():
                    raise FileExistsError("Refusing to overwrite a diagnostic sample")
                sample = self.command(["/usr/bin/sample", str(target["pid"]), "1", "10",
                                       "-file", str(sample_file)], stem + "-sample-command", 3)
                record["commands"].append(sample)
                record["samples"].append({"target": target, "sampleFile": sample_file.name,
                                          "outcome": sample["outcome"], "exitCode": sample.get("exitCode")})
        except Exception as error:
            # Diagnostics are optional: launch, parse, close, or evidence errors
            # cannot substitute for the original inventory outcome.
            record["diagnosticError"] = {"class": type(error).__name__, "message": str(error)}
        finally:
            record["inventoryStillPendingAtFinish"] = not self.stopped.is_set()
            if owns_directory:
                try:
                    (self.evidence / "observation.json").write_text(json.dumps(record, indent=2) + "\n")
                except Exception as error:
                    report_inventory_evidence_error(f"Could not retain inventory observer evidence: {error}")


def start_inventory_observer(evidence):
    if sys.platform != "darwin":
        return None
    try:
        directory = evidence / "inventory-observer"
        observer = InventoryObserver(directory)
        observer.start()
        return observer
    except Exception:
        # Optional startup cannot introduce diagnostic file or stream I/O on
        # the inventory caller. Missing evidence never establishes completion.
        return None


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
    observer = start_inventory_observer(evidence)
    try:
        inventory_text = subprocess.check_output(command, text=True, timeout=60, stderr=stderr)
        returned = True
        returned_duration = time.monotonic() - started
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
        if observer is not None:
            try:
                observer.stop()
            except Exception:
                # Preserve the command outcome without adding diagnostic I/O
                # to its shutdown path, even if the optional observer fails.
                pass
        try:
            stderr.close()
        except OSError as close_error:
            if returned:
                raise
            report_inventory_evidence_error(f"Could not close simulator inventory stderr evidence: {close_error}")
    attempt.update(outcome="returned", durationSeconds=returned_duration,
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
