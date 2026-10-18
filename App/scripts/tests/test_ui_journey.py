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
PREEXISTING = "ABCDEF01-2345-4678-9ABC-DEF012345678"
CREATED = ("10000000-0000-0000-0000-000000000001", "20000000-0000-0000-0000-000000000001")
PASSING = {"result": "Passed", "totalTestCount": 2, "passedTests": 2,
           "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}


def inventory():
    return {
        "runtimes": [{"identifier": journey.RUNTIME, "isAvailable": True, "version": "18.5", "buildversion": "synthetic"}],
        "devicetypes": [{"name": name, "identifier": f"synthetic-{label}"} for label, name in journey.DESTINATIONS],
        "devices": {journey.RUNTIME: [{"name": "Never touch this existing simulator", "udid": PREEXISTING}]},
    }


class UIJourneyRunnerTests(unittest.TestCase):
    def test_exact_runtime_and_both_device_types_are_preserved(self):
        data = inventory()
        before = copy.deepcopy(data)
        result = journey.select_devices(data)
        self.assertEqual(data, before)
        self.assertEqual([row["label"] for row in result], ["iphone", "ipad"])
        self.assertEqual(result[0]["runtime"]["buildversion"], "synthetic")
        self.assertEqual(result[1]["deviceType"]["identifier"], "synthetic-ipad")
        self.assertNotIn("udid", result[0])

    def test_newer_runtime_does_not_replace_required_runtime(self):
        data = inventory()
        data["runtimes"][0]["identifier"] = "com.apple.CoreSimulator.SimRuntime.iOS-99-0"
        with self.assertRaisesRegex(ValueError, "no fallback"):
            journey.select_devices(data)

    def test_unavailable_missing_or_ambiguous_runtime_fails(self):
        valid = inventory()["runtimes"][0]
        for runtimes in ([], [{**valid, "isAvailable": False}], [valid, valid]):
            data = inventory()
            data["runtimes"] = runtimes
            with self.assertRaises(ValueError):
                journey.select_devices(data)

    def test_missing_or_ambiguous_device_type_fails(self):
        for kind in ("missing", "ambiguous"):
            with self.subTest(kind=kind):
                data = inventory()
                if kind == "missing":
                    data["devicetypes"].pop()
                else:
                    data["devicetypes"].append(copy.deepcopy(data["devicetypes"][-1]))
                with self.assertRaises(ValueError):
                    journey.select_devices(data)

    def test_no_preexisting_simulator_is_required(self):
        data = inventory()
        data["devices"] = {}
        self.assertEqual(len(journey.select_devices(data)), 2)

    def test_command_uses_real_ui_target_exact_udid_and_active_architecture(self):
        command = journey.test_command(CREATED[0], Path("retained.xcresult"))
        self.assertEqual(command[:2], ["xcodebuild", "test"])
        self.assertIn(f"platform=iOS Simulator,id={CREATED[0]}", command)
        self.assertEqual(
            [arg.removeprefix("-only-testing:") for arg in command if arg.startswith("-only-testing:")],
            list(journey.TESTS),
        )
        self.assertEqual(len(journey.TESTS), 2)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", command)
        self.assertIn("ONLY_ACTIVE_ARCH=YES", command)
        self.assertIn("retained.xcresult", command)
        self.assertNotIn("-allowProvisioningUpdates", command)
        self.assertNotIn("-retry-tests-on-failure", command)

    def test_summary_requires_both_passed_real_tests(self):
        self.assertTrue(journey.summary_passed(PASSING))
        for key, value in (("result", "Failed"), ("totalTestCount", 0), ("passedTests", 0),
                           ("totalTestCount", 1), ("passedTests", 1), ("totalTestCount", 3),
                           ("failedTests", 1), ("skippedTests", 1), ("expectedFailures", 1)):
            with self.subTest(key=key):
                self.assertFalse(journey.summary_passed({**PASSING, key: value}))
        self.assertFalse(journey.summary_passed({}))

    def exercise_main(self, directory, *, first_exit=0, first_timeout=False, summary=PASSING,
                      first_create=None, cleanup_exit=0, omit_bundle=False):
        evidence = Path(directory) / "evidence"
        commands = []
        test_commands = []
        creates = iter((first_create if first_create is not None else CREATED[0], CREATED[1]))

        def output(command, **kwargs):
            commands.append(command)
            if command[2] == "list":
                return json.dumps(inventory())
            self.assertEqual(command[:3], ["xcrun", "simctl", "create"])
            self.assertEqual(command[-1], journey.RUNTIME)
            value = next(creates)
            if isinstance(value, Exception):
                raise value
            return value

        def run_test(command, log_path):
            test_commands.append(command)
            if not omit_bundle:
                Path(command[command.index("-resultBundlePath") + 1]).mkdir()
            log_path.write_text("Synthetic subprocess test double, not a UI execution.\n")
            if first_timeout and len(test_commands) == 1:
                raise journey.subprocess.TimeoutExpired(command, journey.TEST_TIMEOUT_SECONDS)
            return first_exit if len(test_commands) == 1 else 0

        def run(command, **kwargs):
            commands.append(command)
            if command[:2] == ["xcrun", "xcresulttool"]:
                return journey.subprocess.CompletedProcess(command, 0, json.dumps(summary), "")
            self.assertEqual(command[:2], ["xcrun", "simctl"])
            self.assertIn(command[2], ("shutdown", "delete"))
            return journey.subprocess.CompletedProcess(command, cleanup_exit, "", "synthetic cleanup")

        with patch("sys.argv", ["ui-journey.py", "--evidence-directory", str(evidence)]), \
                patch.object(journey.subprocess, "check_output", side_effect=output), \
                patch.object(journey, "run_logged", side_effect=run_test), \
                patch.object(journey.subprocess, "run", side_effect=run), \
                patch("builtins.print"):
            failure = None
            try:
                journey.main()
            except SystemExit as error:
                failure = error
        results = json.loads((evidence / "journey-results.json").read_text())
        return evidence, commands, test_commands, results, failure

    def test_success_cleans_only_created_ids_and_retains_both_results(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence, commands, tests, results, failure = self.exercise_main(directory)
            self.assertIsNone(failure)
            self.assertEqual(len(tests), 2)
            cleanups = [c for c in commands if c[1] == "simctl" and c[2] in ("shutdown", "delete")]
            self.assertEqual([c[-1] for c in cleanups], [CREATED[0], CREATED[0], CREATED[1], CREATED[1]])
            self.assertFalse(any(PREEXISTING in command for command in commands))
            self.assertTrue(all(r["verifiedPassed"] and r["cleanupSucceeded"] for r in results))
            self.assertTrue((evidence / "ipad-summary.json").exists())
            self.assertTrue((evidence / "iphone-result.json").exists())

    def test_created_id_spelling_is_preserved_for_xcode_and_cleanup(self):
        # simctl returns uppercase hex; Xcode's destination matching is case-sensitive.
        created = "ABCDEF12-3456-4789-ABCD-EF1234567890"
        with tempfile.TemporaryDirectory() as directory:
            evidence, commands, tests, results, failure = self.exercise_main(directory, first_create=created)
            self.assertIsNone(failure)
            self.assertIn(f"platform=iOS Simulator,id={created}", tests[0])
            self.assertEqual(results[0]["simulator"]["udid"], created)
            self.assertIn(created, (evidence / "iphone-command.txt").read_text())
            cleanups = [c for c in commands if c[:2] == ["xcrun", "simctl"] and c[2] in ("shutdown", "delete")]
            self.assertEqual([c[-1] for c in cleanups[:2]], [created, created])

    def test_failed_first_destination_still_attempts_and_cleans_both(self):
        with tempfile.TemporaryDirectory() as directory:
            _, commands, tests, results, failure = self.exercise_main(directory, first_exit=65)
            self.assertIsNotNone(failure)
            self.assertEqual(len(tests), 2)
            self.assertEqual([r["verifiedPassed"] for r in results], [False, True])
            self.assertEqual(len([c for c in commands if c[:3] == ["xcrun", "simctl", "delete"]]), 2)

    def test_test_timeout_still_collects_results_cleans_and_attempts_ipad(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence, _, tests, results, failure = self.exercise_main(directory, first_timeout=True)
            self.assertIsNotNone(failure)
            self.assertEqual(len(tests), 2)
            self.assertEqual([r["verifiedPassed"] for r in results], [False, True])
            self.assertIn("exceeded", results[0]["error"])
            self.assertTrue(results[0]["cleanupSucceeded"])
            self.assertTrue((evidence / "iphone-summary.json").exists())

    def test_unverified_or_preexisting_create_result_is_never_used_or_deleted(self):
        for create_result in ("not-a-uuid", PREEXISTING, PREEXISTING.lower(),
                              journey.subprocess.TimeoutExpired(["xcrun", "simctl", "create"], 60)):
            with self.subTest(result=str(create_result)), tempfile.TemporaryDirectory() as directory:
                _, commands, tests, results, failure = self.exercise_main(directory, first_create=create_result)
                self.assertIsNotNone(failure)
                self.assertEqual(len(tests), 1)
                self.assertFalse(results[0]["cleanupSucceeded"])
                self.assertNotIn("simulator", results[0])
                deletes = [c[-1] for c in commands if c[:3] == ["xcrun", "simctl", "delete"]]
                self.assertEqual(deletes, [CREATED[1]])

    def test_bad_or_missing_summary_cannot_pass_but_does_cleanup(self):
        for summary in ({}, [], {**PASSING, "skippedTests": 1}):
            with self.subTest(summary=summary), tempfile.TemporaryDirectory() as directory:
                _, _, _, results, failure = self.exercise_main(directory, summary=summary)
                self.assertIsNotNone(failure)
                self.assertTrue(all(not r["verifiedPassed"] and r["cleanupSucceeded"] for r in results))
        with tempfile.TemporaryDirectory() as directory:
            _, _, _, results, failure = self.exercise_main(directory, omit_bundle=True)
            self.assertIsNotNone(failure)
            self.assertTrue(all("No xcresult" in r["summaryError"] for r in results))

    def test_cleanup_failure_is_retained_and_fails_the_runner(self):
        with tempfile.TemporaryDirectory() as directory:
            _, _, _, results, failure = self.exercise_main(directory, cleanup_exit=1)
            self.assertIsNotNone(failure)
            self.assertTrue(all(r["verifiedPassed"] and not r["cleanupSucceeded"] for r in results))
            self.assertEqual(results[0]["cleanup"]["delete"]["exitCode"], 1)

    def test_shutdown_error_still_attempts_deletion(self):
        with patch.object(journey.subprocess, "run", side_effect=[
            journey.subprocess.TimeoutExpired([], 60),
            journey.subprocess.CompletedProcess([], 0, "", ""),
        ]) as run:
            result = journey.cleanup_simulator(CREATED[0])
        self.assertIn("error", result["shutdown"])
        self.assertEqual(result["delete"]["exitCode"], 0)
        self.assertEqual(run.call_args_list[1].args[0], ["xcrun", "simctl", "delete", CREATED[0]])

    def test_evidence_write_failure_after_creation_still_cleans_owned_simulator(self):
        original_write = Path.write_text
        failed = False
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory)

            def write(path, *args, **kwargs):
                nonlocal failed
                if path.name == "iphone-result.json" and not failed:
                    failed = True
                    raise OSError("Synthetic evidence write failure")
                return original_write(path, *args, **kwargs)

            with patch.object(journey.subprocess, "check_output", return_value=CREATED[0]), \
                    patch.object(journey.subprocess, "run", return_value=journey.subprocess.CompletedProcess([], 0, "", "")) as run, \
                    patch.object(Path, "write_text", new=write):
                result = journey.run_destination(journey.select_devices(inventory())[0], evidence, {PREEXISTING})
            self.assertFalse(result["verifiedPassed"])
            self.assertTrue(result["cleanupSucceeded"])
            self.assertIn("Synthetic evidence write failure", result["error"])
            self.assertEqual(run.call_args_list[-1].args[0], ["xcrun", "simctl", "delete", CREATED[0]])

    def test_run_logged_has_a_bounded_timeout_and_retains_partial_log(self):
        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "timeout.log"

            def timeout(command, **kwargs):
                self.assertEqual(kwargs["timeout"], journey.TEST_TIMEOUT_SECONDS)
                kwargs["stdout"].write("Partial synthetic log before timeout\n")
                raise journey.subprocess.TimeoutExpired(command, kwargs["timeout"])

            with patch.object(journey.subprocess, "run", side_effect=timeout):
                with self.assertRaises(journey.subprocess.TimeoutExpired):
                    journey.run_logged(["synthetic-test-command"], log_path)
            self.assertIn("Partial synthetic log", log_path.read_text())

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
