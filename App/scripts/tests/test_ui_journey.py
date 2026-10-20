"""Portable runner checks; these do not execute Swift or an Apple UI."""
import copy
import importlib.util
import json
from pathlib import Path
import re
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
                      first_create=None, cleanup_exit=0, omit_bundle=False, extra_args=()):
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
            # Synthetic log specimens exercise only the output gate, not an Apple UI.
            selected = [arg.removeprefix("-only-testing:") for arg in command if arg.startswith("-only-testing:")]
            log_path.write_text(self.method_log(selected))
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

        with patch("sys.argv", ["ui-journey.py", "--evidence-directory", str(evidence), *extra_args]), \
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

    def method_log(self, tests):
        rows = ["Synthetic XCTest log specimen; no native execution."]
        for test in tests:
            module, suite, method = test.split("/")
            identity = f"-[{module}.{suite} {method}]"
            rows += [f"Test Case '{identity}' started.", f"Test Case '{identity}' passed (0.001 seconds)."]
        return "\n".join(rows) + "\n"

    def test_combined_single_destination_retains_all_four_exact_methods(self):
        # Retain all six earlier cases, now with the planning-input journey.
        summary = {**PASSING, "totalTestCount": 7, "passedTests": 7}
        with tempfile.TemporaryDirectory() as directory:
            _, commands, tests, results, failure = self.exercise_main(directory, summary=summary,
                extra_args=("--suite", "all", "--destination", "ipad"))
            self.assertIsNone(failure)
            self.assertEqual(len(tests), 1)
            self.assertEqual(results[0]["destination"]["label"], "ipad")
            self.assertEqual(results[0]["tests"], list(journey.TESTS + journey.T6_TESTS + journey.PLANNING_TESTS))
            self.assertEqual(len(results[0]["tests"]), 7)
            self.assertTrue(results[0]["executionIdentitiesPassed"])
            self.assertTrue(results[0]["cleanupSucceeded"])
            self.assertEqual(len([c for c in commands if c[:3] == ["xcrun", "simctl", "create"]]), 1)

    def test_t6_results_require_both_declared_starts_and_passes(self):
        text = self.method_log(journey.T6_TESTS)
        self.assertEqual(len(journey.T6_TESTS), 4)
        self.assertTrue(journey.recorded_methods_passed(text, journey.T6_TESTS))
        self.assertFalse(journey.recorded_methods_passed(self.method_log(journey.TESTS), journey.T6_TESTS))
        for mutation in (text.replace("T6ReviewJourneyTests", "OtherTests"),
                         text.replace(" passed ", " skipped "),
                         text.replace(" started.\n", " unrecognized.\n"), text + text,
                         text.replace("testReportedFailureAndPendingPlanRemainVisibleWithoutDeploymentAction",
                                      "testAbsentQualityIsVisibleAfterReportedCompatibilityAndDismissal")):
            with self.subTest(log=mutation):
                self.assertFalse(journey.recorded_methods_passed(mutation, journey.T6_TESTS))

    def test_combined_summary_rejects_the_earlier_two_method_observation(self):
        self.assertFalse(journey.summary_passed(PASSING, journey.SUITES["all"]))
        self.assertTrue(journey.summary_passed({**PASSING, "totalTestCount": 7, "passedTests": 7}, journey.SUITES["all"]))

    def test_current_suite_requires_every_declared_app_method_without_same_count_substitution(self):
        root = Path(__file__).resolve().parents[2] / "PlannerAppUITests"
        actual = set()
        for path in root.glob("*.swift"):
            source = path.read_text()
            classes = list(re.finditer(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source))
            self.assertTrue(classes, path)
            for index, declaration in enumerate(classes):
                end = classes[index + 1].start() if index + 1 < len(classes) else len(source)
                actual.update("PlannerAppUITests/" + declaration.group(1) + "/" + name
                              for name in re.findall(r"\bfunc\s+(test\w+)\s*\(", source[declaration.end():end]))
        tests = journey.SUITES["all"]
        self.assertEqual(len(tests), len(set(tests)))
        self.assertEqual(set(tests), actual)
        text = self.method_log(tests)
        self.assertTrue(journey.recorded_methods_passed(text, tests))
        for item in tests:
            _, _, name = item.split("/")
            with self.subTest(missing=item):
                replaced = text.replace(" " + name + "]", " testUnrelatedPadding]")
                self.assertFalse(journey.recorded_methods_passed(replaced, tests))

    def test_expanded_suite_rejects_pre_export_and_missing_withdrawal_receipts(self):
        tests = journey.SUITES["all"]
        for total in (4, 5, 6):
            with self.subTest(old_total=total):
                summary = {**PASSING, "totalTestCount": total, "passedTests": total}
                self.assertFalse(journey.summary_passed(summary, tests))
                self.assertFalse(journey.recorded_methods_passed(self.method_log(tests[:total]), tests))

    def test_unknown_suite_or_destination_cannot_start_inventory(self):
        for args in (("--suite", "custom"), ("--destination", "newest")):
            with self.subTest(args=args), patch("sys.argv", ["ui-journey.py", *args]), \
                    patch.object(journey.subprocess, "check_output") as command:
                with self.assertRaises(SystemExit):
                    journey.main()
                command.assert_not_called()

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


    def exercise_inventory_failure(self, error, expected_output, representation, exit_code):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence"
            stderr_bytes = b"synthetic inventory stderr\x00\xff\n"

            def fail(command, **kwargs):
                # The original runner has no retained stderr stream. Still raise
                # the actual failure so its missing evidence is the regression.
                if kwargs.get("stderr") is not None:
                    kwargs["stderr"].write(stderr_bytes)
                raise error

            with patch("sys.argv", ["ui-journey.py", "--evidence-directory", str(evidence),
                                    "--suite", "all", "--destination", "iphone"]), \
                    patch.object(journey.subprocess, "check_output", side_effect=fail) as command, \
                    patch("time.monotonic", side_effect=[10.0, 70.25]), \
                    patch.object(journey, "select_devices") as select, \
                    patch.object(journey, "run_destination") as destination, \
                    patch.object(journey, "run_logged") as test, \
                    patch.object(journey, "collect_summary") as summary, \
                    patch.object(journey, "cleanup_simulator") as cleanup, \
                    patch.object(journey.subprocess, "run") as subprocess_run:
                with self.assertRaises(type(error)) as caught:
                    journey.main()
                self.assertIs(caught.exception, error)
                for downstream in (select, destination, test, summary, cleanup, subprocess_run):
                    downstream.assert_not_called()
            self.assertEqual((evidence / "simulator-inventory.stdout.bin").read_bytes(), expected_output)
            self.assertEqual((evidence / "simulator-inventory.stderr.bin").read_bytes(), stderr_bytes)
            attempt = json.loads((evidence / "simulator-inventory-attempt.json").read_text())
            self.assertEqual(attempt, {
                "phase": "simulator-inventory-before-device-selection",
                "command": ["xcrun", "simctl", "list", "--json"], "timeoutSeconds": 60,
                "requestedRuntime": journey.RUNTIME, "requestedDestination": "iphone",
                "simulatorCreatedByThisInvocation": False, "journeyStarted": False,
                "stderrFile": "simulator-inventory.stderr.bin", "outcome": "failed",
                "durationSeconds": 60.25, "errorClass": type(error).__name__,
                "error": str(error), "exitCode": exit_code,
                "stdout": {"file": "simulator-inventory.stdout.bin", "representation": representation,
                           "byteCount": len(expected_output)},
            })
            command.assert_called_once()
            self.assertEqual(command.call_args.args, (["xcrun", "simctl", "list", "--json"],))
            self.assertEqual(set(command.call_args.kwargs), {"text", "timeout", "stderr"})
            self.assertIs(command.call_args.kwargs["text"], True)
            self.assertEqual(command.call_args.kwargs["timeout"], 60)
            self.assertTrue(command.call_args.kwargs["stderr"].closed)
            self.assertEqual(Path(command.call_args.kwargs["stderr"].name), evidence / "simulator-inventory.stderr.bin")
            for name in ("simulator-inventory.json", "requested-destinations.json", "journey-results.json"):
                self.assertFalse((evidence / name).exists(), name)

    def test_inventory_timeout_retains_partial_bytes_text_or_absent_output_without_starting_a_journey(self):
        for output, raw, representation in ((b"partial\x00\xff", b"partial\x00\xff", "bytes"),
                                             ("partial \u03bb", "partial \u03bb".encode(), "text"),
                                             (None, b"", "absent"), (b"", b"", "bytes")):
            with self.subTest(representation=representation, output=output):
                error = journey.subprocess.TimeoutExpired(["xcrun", "simctl", "list", "--json"], 60, output=output)
                self.exercise_inventory_failure(error, raw, representation, None)

    def test_inventory_nonzero_or_launch_failure_retains_actual_exit_or_unknown_without_a_journey(self):
        command = ["xcrun", "simctl", "list", "--json"]
        cases = ((journey.subprocess.CalledProcessError(73, command, output=b"partial failure"),
                  b"partial failure", "bytes", 73),
                 (FileNotFoundError("synthetic missing xcrun"), b"", "absent", None))
        for error, output, representation, exit_code in cases:
            with self.subTest(error=type(error).__name__):
                self.exercise_inventory_failure(error, output, representation, exit_code)

    def test_successful_inventory_retains_the_original_json_and_attempt_before_both_journeys(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch("time.monotonic", side_effect=[4.0, 4.25]):
                evidence, commands, tests, results, failure = self.exercise_main(directory)
            self.assertIsNone(failure)
            self.assertEqual((evidence / "simulator-inventory.json").read_text(), json.dumps(inventory()))
            self.assertEqual((evidence / "simulator-inventory.stderr.bin").read_bytes(), b"")
            attempt = json.loads((evidence / "simulator-inventory-attempt.json").read_text())
            self.assertEqual(attempt["outcome"], "returned")
            self.assertEqual(attempt["exitCode"], 0)
            self.assertIsNone(attempt["errorClass"])
            self.assertEqual(attempt["durationSeconds"], 0.25)
            self.assertEqual(attempt["requestedDestination"], "both")
            self.assertFalse(attempt["simulatorCreatedByThisInvocation"])
            self.assertFalse(attempt["journeyStarted"])
            self.assertEqual(attempt["stdout"], {"file": "simulator-inventory.json", "representation": "text"})
            self.assertEqual(len([row for row in commands if row[:3] == ["xcrun", "simctl", "list"]]), 1)
            self.assertEqual(len(tests), 2)
            self.assertTrue(all(row["verifiedPassed"] and row["cleanupSucceeded"] for row in results))

    def test_inventory_receipt_write_failure_preserves_original_error_and_blocks_successful_progress(self):
        original_write = Path.write_text
        timeout = journey.subprocess.TimeoutExpired(["xcrun", "simctl", "list", "--json"], 60, output=b"partial")
        for original_error in (timeout, None):
            with self.subTest(original_error=original_error), tempfile.TemporaryDirectory() as directory:
                evidence = Path(directory) / "evidence"
                write_error = OSError("synthetic full evidence filesystem")

                def write(path, *args, **kwargs):
                    if path.name == "simulator-inventory-attempt.json":
                        raise write_error
                    return original_write(path, *args, **kwargs)

                with patch("sys.argv", ["ui-journey.py", "--evidence-directory", str(evidence)]), \
                        patch.object(journey.subprocess, "check_output", side_effect=original_error,
                                     return_value=json.dumps(inventory())) as command, \
                        patch.object(Path, "write_text", new=write), \
                        patch.object(journey, "select_devices") as select, \
                        patch.object(journey, "run_destination") as destination, \
                        patch.object(journey.subprocess, "run") as subprocess_run, \
                        patch("builtins.print") as printed:
                    expected_error = original_error if original_error is not None else write_error
                    with self.assertRaises(type(expected_error)) as caught:
                        journey.main()
                    self.assertIs(caught.exception, expected_error)
                    command.assert_called_once()
                    select.assert_not_called()
                    destination.assert_not_called()
                    subprocess_run.assert_not_called()
                    if original_error is not None:
                        printed.assert_called_once()
                        self.assertIn("Could not retain simulator inventory failure evidence", printed.call_args.args[0])
                        self.assertIs(printed.call_args.kwargs["file"], journey.sys.stderr)
                        self.assertEqual((evidence / "simulator-inventory.stdout.bin").read_bytes(), b"partial")
                    else:
                        printed.assert_not_called()
                self.assertFalse((evidence / "simulator-inventory-attempt.json").exists())
                self.assertFalse((evidence / "journey-results.json").exists())


    def test_inventory_stderr_close_and_diagnostic_io_errors_preserve_the_original_failure(self):
        command = ["xcrun", "simctl", "list", "--json"]
        cases = ((journey.subprocess.TimeoutExpired(command, 60, output=b"partial"), OSError("broken stderr")),
                 (journey.subprocess.CalledProcessError(73, command, output=b"partial"), OSError("broken stderr")),
                 (journey.subprocess.TimeoutExpired(command, 60, output=b"partial"), ValueError("closed stderr")),
                 (None, OSError("broken stderr")))
        original_open = Path.open
        for original_error, diagnostic_error in cases:
            with self.subTest(error=type(original_error).__name__, diagnostic=type(diagnostic_error).__name__), \
                    tempfile.TemporaryDirectory() as directory:
                evidence = Path(directory) / "evidence"
                close_error = OSError("synthetic stderr close failure")
                streams = []

                class CloseFailure:
                    def __init__(self, file):
                        self.file = file
                        self.close_attempts = 0

                    def write(self, data):
                        return self.file.write(data)

                    def __enter__(self):
                        return self

                    def __exit__(self, *args):
                        self.close()

                    def close(self):
                        self.close_attempts += 1
                        self.file.close()
                        raise close_error

                def opened(path, *args, **kwargs):
                    file = original_open(path, *args, **kwargs)
                    if path.name == "simulator-inventory.stderr.bin" and args == ("wb",):
                        wrapper = CloseFailure(file)
                        streams.append(wrapper)
                        return wrapper
                    return file

                def output(argv, **kwargs):
                    if kwargs.get("stderr") is not None:
                        kwargs["stderr"].write(b"retained synthetic stderr")
                    if original_error is not None:
                        raise original_error
                    return json.dumps(inventory())

                with patch("sys.argv", ["ui-journey.py", "--evidence-directory", str(evidence)]), \
                        patch.object(journey.subprocess, "check_output", side_effect=output) as called, \
                        patch.object(Path, "open", new=opened), \
                        patch.object(journey, "select_devices") as select, \
                        patch.object(journey, "run_destination") as destination, \
                        patch.object(journey, "cleanup_simulator") as cleanup, \
                        patch.object(journey.subprocess, "run") as subprocess_run, \
                        patch("builtins.print", side_effect=diagnostic_error) as printed:
                    expected = original_error if original_error is not None else close_error
                    with self.assertRaises(type(expected)) as caught:
                        journey.main()
                    self.assertIs(caught.exception, expected)
                    called.assert_called_once()
                    self.assertEqual(called.call_args.args, (command,))
                    self.assertIs(called.call_args.kwargs["text"], True)
                    self.assertEqual(called.call_args.kwargs["timeout"], 60)
                    for downstream in (select, destination, cleanup, subprocess_run):
                        downstream.assert_not_called()
                    self.assertEqual(len(streams), 1)
                    self.assertEqual(streams[0].close_attempts, 1)
                    self.assertTrue(streams[0].file.closed)
                    if original_error is not None:
                        printed.assert_called_once()
                        self.assertIn("Could not close simulator inventory stderr evidence", printed.call_args.args[0])
                    else:
                        printed.assert_not_called()
                self.assertEqual((evidence / "simulator-inventory.stderr.bin").read_bytes(), b"retained synthetic stderr")
                if original_error is not None:
                    attempt = json.loads((evidence / "simulator-inventory-attempt.json").read_text())
                    self.assertEqual(attempt["errorClass"], type(original_error).__name__)
                    self.assertEqual(attempt["outcome"], "failed")
                    self.assertEqual((evidence / "simulator-inventory.stdout.bin").read_bytes(), b"partial")
                else:
                    self.assertFalse((evidence / "simulator-inventory-attempt.json").exists())
                self.assertFalse((evidence / "journey-results.json").exists())



if __name__ == "__main__":
    unittest.main()
