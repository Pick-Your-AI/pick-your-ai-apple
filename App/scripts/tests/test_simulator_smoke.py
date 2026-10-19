import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "simulator_smoke", Path(__file__).resolve().parents[1] / "simulator-smoke.py")
SMOKE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SMOKE)

RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
OLDER_RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
EXISTING_PHONE = "aaaaaaaa-0000-4000-8000-000000000001"
EXISTING_PAD = "bbbbbbbb-0000-4000-8000-000000000002"
CREATED_PHONE = "ABCDEFAB-1234-4321-ABCD-000000000001"
CREATED_PAD = "ABCDEFAB-1234-4321-ABCD-000000000002"


def inventory():
    return {
        "runtimes": [
            {"identifier": OLDER_RUNTIME, "name": "iOS 18.5", "version": "18.5", "isAvailable": True},
            {"identifier": RUNTIME, "name": "iOS 26.2", "version": "26.2", "isAvailable": True},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "name": "iOS 27.0",
             "version": "27.0", "isAvailable": False},
        ],
        "devices": {
            OLDER_RUNTIME: [{"name": "iPad older", "udid": "cccccccc-0000-4000-8000-000000000003", "isAvailable": True}],
            RUNTIME: [
                {"name": "iPhone selected", "udid": EXISTING_PHONE, "isAvailable": True},
                {"name": "iPad selected", "udid": EXISTING_PAD, "isAvailable": True},
            ],
        },
        "devicetypes": [
            {"name": "iPhone selected", "identifier": "type.iphone"},
            {"name": "iPad selected", "identifier": "type.ipad"},
            {"name": "iPad older", "identifier": "type.older-ipad"},
        ],
    }


class SimulatorSmokeTests(unittest.TestCase):
    def setUp(self):
        self.inventory = inventory()
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()

    def completed(self, args, **kwargs):
        action = args[2]
        output = ""
        if action == "list":
            output = json.dumps(self.inventory)
        elif action == "create":
            output = CREATED_PHONE if args[3] == "Planner-iPhone-CI" else CREATED_PAD
        elif action == "launch":
            output = "invalid.pickyourai.localpreview: 123\n"
        return subprocess.CompletedProcess(args, 0, output, "")

    @contextlib.contextmanager
    def commands(self, effect=None, snapshot_effect=None):
        with patch.object(SMOKE.subprocess, "run", side_effect=effect or self.completed) as mocked, \
                patch.object(SMOKE, "collect_runtime_snapshot", side_effect=snapshot_effect), \
                contextlib.redirect_stdout(self.stdout), contextlib.redirect_stderr(self.stderr):
            yield mocked

    def test_success_preserves_destinations_launch_checks_and_exact_owned_ids(self):
        with self.commands() as mocked:
            SMOKE.main()
        calls = mocked.call_args_list
        self.assertNotIn("get_app_container", [c.args[0][2] for c in calls])
        self.assertNotIn("spawn", [c.args[0][2] for c in calls])
        creates = [c.args[0] for c in calls if c.args[0][2] == "create"]
        self.assertEqual(creates, [
            ("xcrun", "simctl", "create", "Planner-iPhone-CI", "type.iphone", RUNTIME),
            ("xcrun", "simctl", "create", "Planner-iPad-CI", "type.ipad", RUNTIME),
        ])
        for call in calls:
            args = call.args[0]
            expected_timeout = {"bootstatus": 300, "install": 180}.get(args[2], 60)
            self.assertEqual(call.kwargs["timeout"], expected_timeout)
            self.assertTrue(call.kwargs["capture_output"])
            if args[2] not in ("list", "create"):
                udid = args[3]
                self.assertIn(udid, (CREATED_PHONE, CREATED_PAD))
        for udid in (CREATED_PHONE, CREATED_PAD):
            args = [c.args[0] for c in calls]
            self.assertIn(("xcrun", "simctl", "install", udid,
                           ".build/native/Build/Products/Debug-iphonesimulator/Planner.app"), args)
            self.assertIn(("xcrun", "simctl", "launch", udid,
                           "invalid.pickyourai.localpreview"), args)
            self.assertIn(("xcrun", "simctl", "terminate", udid, "invalid.pickyourai.localpreview"), args)
            self.assertIn(("xcrun", "simctl", "shutdown", udid), args)
            self.assertIn(("xcrun", "simctl", "delete", udid), args)
            self.assertIn(f"Owned simulator created by this run: {udid}", self.stdout.getvalue())

    def test_timeout_retains_partial_stdout_stderr_command_and_deadline(self):
        error = subprocess.TimeoutExpired(("synthetic-command", "argument"), 60,
                                          output=b"partial output\n", stderr=b"partial error\n")
        with self.commands(error) as mocked:
            with self.assertRaises(subprocess.TimeoutExpired) as caught:
                SMOKE.run("synthetic-command", "argument")
        self.assertIs(caught.exception, error)
        self.assertEqual(mocked.call_args.kwargs["timeout"], 60)
        self.assertIn("partial output", self.stdout.getvalue())
        self.assertIn("partial error", self.stderr.getvalue())
        self.assertIn("timed out after 60s: synthetic-command argument", self.stderr.getvalue())

    def test_real_child_deadline_retains_output_and_returns_without_its_full_sleep(self):
        started = time.monotonic()
        program = "import time\nprint('synthetic partial output', flush=True)\ntime.sleep(30)\n"
        with contextlib.redirect_stdout(self.stdout), contextlib.redirect_stderr(self.stderr), \
                self.assertRaises(subprocess.TimeoutExpired) as caught:
            SMOKE.run(sys.executable, "-c", program, timeout=1)
        self.assertLess(time.monotonic() - started, 10)
        emitted = caught.exception.stdout
        if isinstance(emitted, bytes):
            emitted = emitted.decode("utf-8")
        self.assertEqual(emitted.strip(), "synthetic partial output")
        self.assertEqual(self.stdout.getvalue().splitlines().count("synthetic partial output"), 1)
        self.assertIn("timed out after 1s", self.stderr.getvalue())

    def test_failed_launch_stays_failed_and_cleans_its_owned_simulator(self):
        def effect(args, **kwargs):
            if args[2] == "launch":
                return subprocess.CompletedProcess(args, 23, "launch output", "launch refused")
            return self.completed(args, **kwargs)
        with self.commands(effect) as mocked, self.assertRaises(subprocess.CalledProcessError) as caught:
            SMOKE.main()
        self.assertEqual(caught.exception.returncode, 23)
        actions = [c.args[0][2] for c in mocked.call_args_list]
        self.assertEqual(actions[-4:], ["get_app_container", "spawn", "shutdown", "delete"])
        self.assertNotIn("terminate", actions)
        self.assertIn("launch refused", self.stderr.getvalue())

    def test_launch_timeout_collects_bounded_owned_diagnostics_before_cleanup(self):
        primary = subprocess.TimeoutExpired("launch", 60, output=b"launch pending\n")

        def effect(args, **kwargs):
            if args[2] == "launch":
                raise primary
            if args[2] == "get_app_container":
                return subprocess.CompletedProcess(args, 0, "/synthetic/Planner.app\n", "")
            if args[2] == "spawn":
                return subprocess.CompletedProcess(args, 0, "synthetic app launch diagnostic\n", "")
            return self.completed(args, **kwargs)

        with self.commands(effect) as mocked, self.assertRaises(subprocess.TimeoutExpired) as caught:
            SMOKE.main()
        self.assertIs(caught.exception, primary)
        calls = mocked.call_args_list
        self.assertEqual([c.args[0][2] for c in calls],
                         ["list", "create", "boot", "bootstatus", "install", "launch",
                          "get_app_container", "spawn", "shutdown", "delete"])
        self.assertEqual(calls[-4].args[0],
                         ("xcrun", "simctl", "get_app_container", CREATED_PHONE,
                          "invalid.pickyourai.localpreview", "app"))
        self.assertEqual(calls[-3].args[0],
                         ("xcrun", "simctl", "spawn", CREATED_PHONE, "log", "show",
                          "--style", "compact", "--last", "2m", "--info", "--predicate",
                          'process == "Planner" OR eventMessage CONTAINS "invalid.pickyourai.localpreview"'))
        for call in calls[-4:-2]:
            self.assertEqual(call.kwargs["timeout"], 15)
        self.assertEqual(calls[-5].kwargs["timeout"], 60)
        for call in calls[-2:]:
            self.assertEqual(call.kwargs["timeout"], 60)
        self.assertIn("launch pending", self.stdout.getvalue())
        self.assertIn("/synthetic/Planner.app", self.stdout.getvalue())
        self.assertIn("synthetic app launch diagnostic", self.stdout.getvalue())

    def test_diagnostic_errors_preserve_launch_failure_and_both_cleanup_attempts(self):
        for failure in ("timeout", "nonzero", "unavailable", "unexpected"):
            for cleanup_fails in (False, True):
                with self.subTest(failure=failure, cleanup_fails=cleanup_fails):
                    primary = subprocess.TimeoutExpired("launch", 60, stderr=b"primary launch error\n")

                    def effect(args, **kwargs):
                        if args[2] == "launch":
                            raise primary
                        if args[2] in ("get_app_container", "spawn"):
                            self.assertEqual(args[3], CREATED_PHONE)
                            self.assertEqual(kwargs["timeout"], 15)
                            if failure == "timeout":
                                raise subprocess.TimeoutExpired(args, 15, output=b"partial diagnostic\n")
                            if failure == "nonzero":
                                return subprocess.CompletedProcess(args, 7, "", "diagnostic refused")
                            if failure == "unavailable":
                                raise FileNotFoundError("diagnostic utility unavailable")
                            raise RuntimeError("unexpected diagnostic failure")
                        if cleanup_fails and args[2] in ("shutdown", "delete"):
                            raise subprocess.TimeoutExpired(args, 60, stderr=b"cleanup stalled\n")
                        return self.completed(args, **kwargs)

                    with self.commands(effect) as mocked, self.assertRaises(subprocess.TimeoutExpired) as caught:
                        SMOKE.main()
                    self.assertIs(caught.exception, primary)
                    calls = mocked.call_args_list
                    self.assertEqual([c.args[0][2] for c in calls][-5:],
                                     ["launch", "get_app_container", "spawn", "shutdown", "delete"])
                    self.assertEqual(sum(c.args[0][2] == "launch" for c in calls), 1)
                    for call in calls[-2:]:
                        self.assertEqual(call.args[0][3], CREATED_PHONE)
                        self.assertEqual(call.kwargs["timeout"], 60)
                    self.assertIn("Launch diagnostic did not complete", self.stderr.getvalue())

    def test_second_destination_failure_diagnoses_only_its_own_simulator(self):
        def effect(args, **kwargs):
            if args[2] == "launch" and args[3] == CREATED_PAD:
                return subprocess.CompletedProcess(args, 23, "", "iPad launch refused")
            return self.completed(args, **kwargs)

        with self.commands(effect) as mocked, self.assertRaises(subprocess.CalledProcessError) as caught:
            SMOKE.main()
        self.assertEqual(caught.exception.returncode, 23)
        commands = [c.args[0] for c in mocked.call_args_list]
        diagnostics = [args for args in commands if args[2] in ("get_app_container", "spawn")]
        self.assertEqual([args[3] for args in diagnostics], [CREATED_PAD, CREATED_PAD])
        self.assertEqual([args[3] for args in commands if args[2] == "delete"], [CREATED_PHONE, CREATED_PAD])
        self.assertEqual(sum(args[2] == "launch" for args in commands), 2)

    def test_boot_timeout_preserves_failure_and_attempts_both_bounded_cleanup_commands(self):
        error = subprocess.TimeoutExpired("bootstatus", 300, output=b"Waiting for boot")
        def effect(args, **kwargs):
            if args[2] == "bootstatus":
                raise error
            return self.completed(args, **kwargs)
        with self.commands(effect) as mocked, self.assertRaises(subprocess.TimeoutExpired) as caught:
            SMOKE.main()
        self.assertIs(caught.exception, error)
        calls = mocked.call_args_list
        self.assertEqual([c.args[0][2] for c in calls], ["list", "create", "boot", "bootstatus", "shutdown", "delete"])
        for call in calls[-2:]:
            self.assertEqual(call.args[0][3], CREATED_PHONE)
            self.assertEqual(call.kwargs["timeout"], 60)
        self.assertIn("Waiting for boot", self.stdout.getvalue())
        self.assertIn("timed out after 300s", self.stderr.getvalue())

    def test_install_timeout_preserves_failure_output_and_bounded_cleanup_without_retry(self):
        for cleanup_fails in (False, True):
            with self.subTest(cleanup_fails=cleanup_fails):
                primary = subprocess.TimeoutExpired(
                    "install", 180, output=b"partial installation\n", stderr=b"installation pending\n")

                def effect(args, **kwargs):
                    if args[2] == "install":
                        self.assertEqual(kwargs["timeout"], 180)
                        raise primary
                    if cleanup_fails and args[2] in ("shutdown", "delete"):
                        raise subprocess.TimeoutExpired(args, 60, stderr=b"cleanup stalled\n")
                    return self.completed(args, **kwargs)

                with self.commands(effect) as mocked, self.assertRaises(subprocess.TimeoutExpired) as caught:
                    SMOKE.main()
                self.assertIs(caught.exception, primary)
                calls = mocked.call_args_list
                self.assertEqual([c.args[0][2] for c in calls],
                                 ["list", "create", "boot", "bootstatus", "install", "shutdown", "delete"])
                for call in calls[-2:]:
                    self.assertEqual(call.args[0][3], CREATED_PHONE)
                    self.assertEqual(call.kwargs["timeout"], 60)
                self.assertIn("partial installation", self.stdout.getvalue())
                self.assertIn("installation pending", self.stderr.getvalue())
                self.assertIn("timed out after 180s: xcrun simctl install", self.stderr.getvalue())

    def test_shutdown_timeout_still_attempts_deletion_and_preserves_launch_requirements(self):
        def effect(args, **kwargs):
            if args[2] == "shutdown":
                raise subprocess.TimeoutExpired(args, 60, stderr=b"shutdown pending")
            return self.completed(args, **kwargs)
        with self.commands(effect) as mocked:
            SMOKE.main()
        calls = [c.args[0] for c in mocked.call_args_list]
        self.assertEqual(sum(args[2] == "launch" for args in calls), 2)
        self.assertEqual(sum(args[2] == "terminate" for args in calls), 2)
        self.assertEqual([args[3] for args in calls if args[2] == "delete"], [CREATED_PHONE, CREATED_PAD])
        self.assertIn("shutdown pending", self.stderr.getvalue())

    def test_failed_delete_fails_an_otherwise_successful_smoke(self):
        def effect(args, **kwargs):
            if args[2] == "delete":
                return subprocess.CompletedProcess(args, 9, "", "owned device still present")
            return self.completed(args, **kwargs)
        with self.commands(effect), self.assertRaisesRegex(ValueError, "cleanup did not delete"):
            SMOKE.main()
        self.assertIn("owned device still present", self.stderr.getvalue())

    def test_cleanup_errors_do_not_replace_the_original_boot_timeout(self):
        primary = subprocess.TimeoutExpired("bootstatus", 300, output=b"boot not ready")
        def effect(args, **kwargs):
            if args[2] == "bootstatus":
                raise primary
            if args[2] in ("shutdown", "delete"):
                raise subprocess.TimeoutExpired(args, 60, stderr=b"cleanup stalled")
            return self.completed(args, **kwargs)
        with self.commands(effect) as mocked, self.assertRaises(subprocess.TimeoutExpired) as caught:
            SMOKE.main()
        self.assertIs(caught.exception, primary)
        self.assertEqual([c.args[0][2] for c in mocked.call_args_list][-2:], ["shutdown", "delete"])
        self.assertIn("boot not ready", self.stdout.getvalue())
        self.assertIn("cleanup stalled", self.stderr.getvalue())

    def test_create_timeout_never_uses_or_cleans_its_partial_id(self):
        def effect(args, **kwargs):
            if args[2] == "create":
                raise subprocess.TimeoutExpired(args, 60, output=CREATED_PHONE.encode())
            return self.completed(args, **kwargs)
        with self.commands(effect) as mocked, self.assertRaises(subprocess.TimeoutExpired):
            SMOKE.main()
        self.assertEqual([c.args[0][2] for c in mocked.call_args_list], ["list", "create"])
        self.assertIn(CREATED_PHONE, self.stdout.getvalue())
        self.assertNotIn("Owned simulator created by this run:", self.stdout.getvalue())

    def test_unparseable_or_case_variant_preexisting_ids_are_never_used_or_cleaned(self):
        for returned in ("not-a-uuid", CREATED_PHONE + "\n" + CREATED_PAD, EXISTING_PHONE.upper()):
            with self.subTest(returned=returned):
                def effect(args, **kwargs):
                    if args[2] == "create":
                        return subprocess.CompletedProcess(args, 0, returned, "")
                    return self.completed(args, **kwargs)
                with self.commands(effect) as mocked, self.assertRaises(ValueError):
                    SMOKE.main()
                self.assertEqual([c.args[0][2] for c in mocked.call_args_list], ["list", "create"])

    def test_inventory_timeout_never_creates_or_cleans_a_device(self):
        def effect(args, **kwargs):
            raise subprocess.TimeoutExpired(args, 60, output=b"partial inventory")
        with self.commands(effect) as mocked, self.assertRaises(subprocess.TimeoutExpired):
            SMOKE.main()
        self.assertEqual([c.args[0][2] for c in mocked.call_args_list], ["list"])
        self.assertIn("partial inventory", self.stdout.getvalue())

    def test_missing_family_does_not_fallback_to_the_older_runtime(self):
        self.inventory["devices"][RUNTIME].pop()
        with self.commands() as mocked, self.assertRaisesRegex(ValueError, "No available iPad for iOS 26.2"):
            SMOKE.main()
        creates = [c.args[0] for c in mocked.call_args_list if c.args[0][2] == "create"]
        self.assertEqual(len(creates), 1)
        self.assertEqual(creates[0][-1], RUNTIME)

    def test_unavailable_runtime_never_creates_a_device(self):
        for runtime in self.inventory["runtimes"]:
            runtime["isAvailable"] = False
        with self.commands() as mocked, self.assertRaisesRegex(ValueError, "No available iOS simulator runtime"):
            SMOKE.main()
        self.assertEqual([c.args[0][2] for c in mocked.call_args_list], ["list"])


    def test_runtime_snapshot_filters_process_arguments_services_and_resource_fields(self):
        process_text = (
            "101 1 S 2.5 4096 /Applications/Simulator.app/Contents/MacOS/Simulator\n"
            "102 101 R+ 0.0 8192 /private/host/path/Planner\n"
            "103 1 S 9.0 16384 /private/host/private-program --secret=excluded\n"
            "104 1 S 1.0 512 Planner --secret=excluded\n")
        rows, truncated = SMOKE.snapshot_rows("processes", process_text)
        self.assertEqual(rows, ["101 1 S 2.5 4096 Simulator", "102 101 R+ 0.0 8192 Planner"])
        self.assertFalse(truncated)
        service_text = (
            "PID Status Label\n"
            "201 0 com.apple.SpringBoard\n"
            "- -9 com.apple.runningboardd\n"
            "202 0 UIKitApplication:invalid.pickyourai.localpreview[private-suffix]\n"
            "203 0 UIKitApplication:private.unrelated.application[secret]\n")
        rows, truncated = SMOKE.snapshot_rows("services", service_text)
        self.assertEqual(rows, ["201 0 com.apple.SpringBoard", "- -9 com.apple.runningboardd",
                               "202 0 invalid.pickyourai.localpreview"])
        self.assertFalse(truncated)
        rows, _ = SMOKE.snapshot_rows("memory", b"Pages free:  42.\nsecret=excluded\nSwapouts: 7.\n")
        self.assertEqual(rows, ["Pages free: 42.", "Swapouts: 7."])

    def test_runtime_snapshot_reports_truncation_at_row_and_character_bounds(self):
        source = "\n".join("1 0 S 0.0 1 Planner" for _ in range(100))
        rows, truncated = SMOKE.snapshot_rows("processes", source)
        self.assertEqual(len(rows), 40)
        self.assertTrue(truncated)
        with patch.object(SMOKE, "SNAPSHOT_MAX_CHARS", 20):
            rows, truncated = SMOKE.snapshot_rows("processes", source)
        self.assertEqual(rows, ["1 0 S 0.0 1 Planner"])
        self.assertTrue(truncated)

    def test_runtime_snapshot_uses_exact_owned_service_scope_and_short_deadlines(self):
        def effect(args, **kwargs):
            output = {
                "/usr/bin/vm_stat": "Pages free: 7.\n",
                "/bin/ps": "101 1 S 1.0 200 Planner\n",
                "xcrun": "123 0 com.apple.SpringBoard\n",
            }[args[0]]
            return subprocess.CompletedProcess(args, 0, output, "private stderr must not be emitted")
        with patch.object(SMOKE.subprocess, "run", side_effect=effect) as mocked, \
                patch.object(SMOKE.os, "getloadavg", return_value=(1.0, 2.0, 3.0)), \
                contextlib.redirect_stdout(self.stdout):
            SMOKE.collect_runtime_snapshot(CREATED_PHONE, "before-launch")
        calls = mocked.call_args_list
        self.assertEqual([c.args[0] for c in calls], [
            ("/usr/bin/vm_stat",),
            ("/bin/ps", "-axo", "pid=,ppid=,state=,%cpu=,rss=,comm="),
            ("xcrun", "simctl", "spawn", CREATED_PHONE, "launchctl", "list")])
        self.assertTrue(all(c.kwargs["timeout"] == 3 for c in calls))
        records = [json.loads(line) for line in self.stdout.getvalue().splitlines()]
        self.assertEqual(len(records), 4)
        self.assertTrue(all(r["owned_udid"] == CREATED_PHONE and r["smoke_snapshot"] == "before-launch" for r in records))
        self.assertEqual(records[0]["host_load_averages"], [1.0, 2.0, 3.0])
        self.assertEqual([r["rows"] for r in records[1:]],
                         [["Pages free: 7."], ["101 1 S 1.0 200 Planner"], ["123 0 com.apple.SpringBoard"]])
        self.assertNotIn("private stderr", self.stdout.getvalue())

    def test_runtime_snapshot_probe_failures_are_observations_and_do_not_stop_remaining_probes(self):
        failures = [
            subprocess.TimeoutExpired("memory", 3, output=b"Pages free: 9.\nsecret=excluded"),
            FileNotFoundError("private path excluded"),
            RuntimeError("private detail excluded"),
        ]
        with patch.object(SMOKE.subprocess, "run", side_effect=failures) as mocked, \
                patch.object(SMOKE.os, "getloadavg", side_effect=OSError("private load failure")), \
                contextlib.redirect_stdout(self.stdout):
            SMOKE.collect_runtime_snapshot(CREATED_PHONE, "launch-failed")
        self.assertEqual(mocked.call_count, 3)
        records = [json.loads(line) for line in self.stdout.getvalue().splitlines()]
        self.assertEqual(records[0]["host_load_averages"], {"error": "OSError"})
        self.assertEqual([r["error"] for r in records[1:]], ["timeout", "FileNotFoundError", "RuntimeError"])
        self.assertEqual(records[1]["rows"], ["Pages free: 9."])
        self.assertNotIn("private", self.stdout.getvalue())
        self.assertNotIn("secret", self.stdout.getvalue())

    def test_runtime_snapshot_real_deadline_preserves_only_filtered_partial_output(self):
        program = "import time\nprint('Pages free: 7.\\nsecret=excluded', flush=True)\ntime.sleep(30)\n"
        started = time.monotonic()
        with patch.object(SMOKE, "SNAPSHOT_TIMEOUT_SECONDS", 1):
            result = SMOKE.snapshot_probe("memory", (sys.executable, "-c", program))
        self.assertLess(time.monotonic() - started, 10)
        self.assertEqual(result["error"], "timeout")
        self.assertEqual(result["deadline_seconds"], 1)
        self.assertEqual(result["rows"], ["Pages free: 7."])
        self.assertNotIn("secret", json.dumps(result))

    def test_runtime_snapshots_preserve_launch_order_primary_error_and_owned_cleanup(self):
        events = []
        primary = subprocess.TimeoutExpired("launch", 60, output=b"primary launch remains failed\n")
        def effect(args, **kwargs):
            events.append((args[2], args[3] if len(args) > 3 else None))
            if args[2] == "launch" and args[3] == CREATED_PAD:
                raise primary
            return self.completed(args, **kwargs)
        def snapshot(udid, phase):
            events.append((phase, udid))
        with self.commands(effect, snapshot_effect=snapshot), self.assertRaises(subprocess.TimeoutExpired) as caught:
            SMOKE.main()
        self.assertIs(caught.exception, primary)
        self.assertEqual([e for e in events if e[0] in ("before-launch", "launch", "launch-failed", "terminate", "shutdown", "delete")], [
            ("before-launch", CREATED_PHONE), ("launch", CREATED_PHONE),
            ("terminate", CREATED_PHONE), ("shutdown", CREATED_PHONE), ("delete", CREATED_PHONE),
            ("before-launch", CREATED_PAD), ("launch", CREATED_PAD), ("launch-failed", CREATED_PAD),
            ("shutdown", CREATED_PAD), ("delete", CREATED_PAD)])
        self.assertIn("primary launch remains failed", self.stdout.getvalue())

    def test_runtime_snapshot_not_attempted_before_owned_successful_installation(self):
        for action in ("create", "bootstatus", "install"):
            with self.subTest(action=action):
                observed = []
                def effect(args, **kwargs):
                    if args[2] == action:
                        raise subprocess.TimeoutExpired(args, kwargs["timeout"])
                    return self.completed(args, **kwargs)
                with self.commands(effect, snapshot_effect=lambda *args: observed.append(args)), \
                        self.assertRaises(subprocess.TimeoutExpired):
                    SMOKE.main()
                self.assertEqual(observed, [])


if __name__ == "__main__":
    unittest.main()
