"""Portable runner checks; these do not execute Swift or an Apple UI."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("ui_journey", Path(__file__).resolve().parents[1] / "ui-journey.py")
journey = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(journey)


def inventory():
    return {
        "runtimes": [{"identifier": journey.RUNTIME, "isAvailable": True, "version": "18.5", "buildversion": "synthetic"}],
        "devices": {journey.RUNTIME: [
            {"name": name, "isAvailable": True, "udid": f"synthetic-{label}"}
            for label, name in journey.DESTINATIONS
        ]},
    }


class UIJourneyRunnerTests(unittest.TestCase):
    def test_exact_runtime_and_both_devices_are_preserved(self):
        data = inventory()
        before = copy.deepcopy(data)
        result = journey.select_devices(data)
        self.assertEqual(data, before)
        self.assertEqual([row["label"] for row in result], ["iphone", "ipad"])
        self.assertEqual(result[0]["runtime"]["buildversion"], "synthetic")
        self.assertEqual(result[1]["device"]["udid"], "synthetic-ipad")

    def test_newer_runtime_does_not_replace_required_runtime(self):
        data = inventory()
        data["runtimes"][0]["identifier"] = "com.apple.CoreSimulator.SimRuntime.iOS-99-0"
        with self.assertRaisesRegex(ValueError, "no fallback"):
            journey.select_devices(data)

    def test_unavailable_or_missing_runtime_fails(self):
        for runtimes in ([], [{"identifier": journey.RUNTIME, "isAvailable": False}]):
            data = inventory()
            data["runtimes"] = runtimes
            with self.assertRaises(ValueError):
                journey.select_devices(data)

    def test_missing_unavailable_or_ambiguous_device_fails(self):
        for kind in ("missing", "unavailable", "ambiguous"):
            with self.subTest(kind=kind):
                data = inventory()
                devices = data["devices"][journey.RUNTIME]
                if kind == "missing":
                    devices.pop()
                elif kind == "unavailable":
                    devices[-1]["isAvailable"] = False
                else:
                    devices.append(copy.deepcopy(devices[-1]))
                with self.assertRaises(ValueError):
                    journey.select_devices(data)

    def test_command_uses_checked_in_ui_target_and_exact_udid(self):
        command = journey.test_command("synthetic-iphone", Path("retained.xcresult"))
        self.assertEqual(command[:2], ["xcodebuild", "test"])
        self.assertIn("platform=iOS Simulator,id=synthetic-iphone", command)
        self.assertIn(f"-only-testing:{journey.TEST}", command)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", command)
        self.assertIn("retained.xcresult", command)
        self.assertNotIn("-allowProvisioningUpdates", command)
        self.assertNotIn("-retry-tests-on-failure", command)

    def test_summary_requires_exactly_one_passed_real_test(self):
        valid = {"result": "Passed", "totalTestCount": 1, "passedTests": 1,
                 "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
        self.assertTrue(journey.summary_passed(valid))
        for key, value in (("result", "Failed"), ("totalTestCount", 0), ("passedTests", 0),
                           ("failedTests", 1), ("skippedTests", 1), ("expectedFailures", 1)):
            with self.subTest(key=key):
                self.assertFalse(journey.summary_passed({**valid, key: value}))
        self.assertFalse(journey.summary_passed({}))

    def test_failed_first_destination_still_retains_both_results(self):
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence"

            def run_test(command, log_path):
                calls.append(command)
                Path(command[command.index("-resultBundlePath") + 1]).mkdir()
                log_path.write_text("Synthetic subprocess test double, not a UI execution.\n")
                return 65 if len(calls) == 1 else 0

            summary = {"result": "Passed", "totalTestCount": 1, "passedTests": 1,
                       "failedTests": 0, "skippedTests": 0}
            response = journey.subprocess.CompletedProcess([], 0, json.dumps(summary), "")
            with patch("sys.argv", ["ui-journey.py", "--evidence-directory", str(evidence)]), \
                    patch.object(journey.subprocess, "check_output", return_value=json.dumps(inventory())), \
                    patch.object(journey, "run_logged", side_effect=run_test), \
                    patch.object(journey.subprocess, "run", return_value=response):
                with self.assertRaisesRegex(SystemExit, "not verified passed"):
                    journey.main()
            self.assertEqual(len(calls), 2)
            outcomes = json.loads((evidence / "journey-results.json").read_text())
            self.assertEqual([row["verifiedPassed"] for row in outcomes], [False, True])
            self.assertTrue((evidence / "simulator-inventory.json").exists())
            self.assertTrue((evidence / "ipad-summary.json").exists())

    def test_existing_evidence_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory)
            retained = evidence / "existing-result.txt"
            retained.write_text("Keep this evidence")
            with patch("sys.argv", ["ui-journey.py", "--evidence-directory", str(evidence)]), \
                    patch.object(journey.subprocess, "check_output") as command:
                with self.assertRaises(FileExistsError):
                    journey.main()
                command.assert_not_called()
            self.assertEqual(retained.read_text(), "Keep this evidence")


if __name__ == "__main__":
    unittest.main()
