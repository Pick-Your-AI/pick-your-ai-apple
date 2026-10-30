import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

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


class UnavailableOutput(io.StringIO):
    def __init__(self, error_type=BrokenPipeError, failure="write", unavailable=True):
        super().__init__()
        self.error_type = error_type
        self.failure = failure
        self.unavailable = unavailable

    def write(self, value):
        if self.unavailable and self.failure == "write":
            raise self.error_type("synthetic unavailable output")
        return super().write(value)

    def flush(self):
        if self.unavailable and self.failure == "flush":
            raise self.error_type("synthetic unavailable output")
        return super().flush()


class CommandProcessFixture:
    """Translate only mocked command cases; never manufacture an OS process."""
    def __init__(self, args, pid):
        self.args, self.pid, self.returncode = args, pid, None
        self.stdout, self.stderr = io.StringIO(), io.StringIO()

    def communicate(self, timeout):
        result = subprocess.run(self.args, capture_output=True, text=True, errors="replace",
                                check=False, timeout=timeout)
        self.returncode = result.returncode
        return result.stdout, result.stderr

    def kill(self):
        if self.returncode is None:
            self.returncode = -signal.SIGKILL

    def wait(self, timeout):
        if self.returncode is None:
            self.returncode = -signal.SIGKILL
        return self.returncode


class SimulatorSmokeTests(unittest.TestCase):
    def setUp(self):
        self.inventory = inventory()
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        # Keep every existing command fixture at its original run interface.
        # Real Python children still use the actual Popen and process group.
        real_popen, real_killpg = subprocess.Popen, getattr(os, "killpg", None)
        synthetic = {}

        def popen(args, **kwargs):
            if args[0] == sys.executable:
                return real_popen(args, **kwargs)
            self.assertEqual(kwargs, {"stdout": subprocess.PIPE, "stderr": subprocess.PIPE,
                                      "text": True, "errors": "replace", "start_new_session": True})
            pid = 2 ** 30 + len(synthetic)
            process = CommandProcessFixture(args, pid)
            synthetic[pid] = process
            return process

        def killpg(pid, sig):
            if pid in synthetic:
                self.assertEqual(sig, signal.SIGKILL)
                synthetic[pid].kill()
            else:
                real_killpg(pid, sig)

        popen_patch = patch.object(SMOKE.subprocess, "Popen", side_effect=popen)
        popen_patch.start()
        self.addCleanup(popen_patch.stop)
        if real_killpg is not None:
            group_patch = patch.object(SMOKE.os, "killpg", side_effect=killpg)
            group_patch.start()
            self.addCleanup(group_patch.stop)

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

    def test_real_child_invalid_text_preserves_success_and_nonzero_exit(self):
        for exit_code in (0, 23):
            with self.subTest(exit_code=exit_code):
                self.stdout, self.stderr = io.StringIO(), io.StringIO()
                program = ("import os, sys\n"
                           "os.write(1, b'child output \\xff\\n')\n"
                           "os.write(2, b'child error \\xfe\\n')\n"
                           f"sys.exit({exit_code})\n")
                with contextlib.redirect_stdout(self.stdout), contextlib.redirect_stderr(self.stderr):
                    if exit_code == 0:
                        self.assertEqual(SMOKE.run(sys.executable, "-c", program),
                                         "child output \ufffd")
                    else:
                        with self.assertRaises(subprocess.CalledProcessError) as caught:
                            SMOKE.run(sys.executable, "-c", program)
                        self.assertEqual(caught.exception.returncode, 23)
                        self.assertEqual(caught.exception.output, "child output \ufffd\n")
                        self.assertEqual(caught.exception.stderr, "child error \ufffd\n")
                self.assertIn("child output \ufffd\n", self.stdout.getvalue())
                self.assertIn("child error \ufffd\n", self.stderr.getvalue())
                self.assertIn(f"Smoke command exited {exit_code}:", self.stdout.getvalue())

    def test_real_child_invalid_create_diagnostic_preserves_owned_ids_and_commands(self):
        real_run = subprocess.run

        def effect(args, **kwargs):
            if args[2] == "create":
                output = (self.completed(args, **kwargs).stdout + "\n").encode("utf-8")
                program = (f"import os\nos.write(1, {output!r})\n"
                           "os.write(2, b'create diagnostic \\xff\\n')\n")
                return real_run([sys.executable, "-c", program], **kwargs)
            return self.completed(args, **kwargs)

        with self.commands(effect) as mocked:
            SMOKE.main()
        for udid in (CREATED_PHONE, CREATED_PAD):
            owned = [call for call in mocked.call_args_list
                     if len(call.args[0]) > 3 and call.args[0][3] == udid]
            self.assertEqual([call.args[0][2] for call in owned],
                             ["boot", "bootstatus", "install", "launch",
                              "terminate", "shutdown", "delete"])
            self.assertEqual([call.kwargs["timeout"] for call in owned],
                             [60, 300, 180, 60, 60, 60, 60])
        self.assertEqual(self.stderr.getvalue().count("create diagnostic \ufffd"), 2)

    def test_real_child_invalid_cleanup_text_preserves_timeout_and_attempts_delete(self):
        real_run = subprocess.run
        for cleanup_exit in (0, 9):
            with self.subTest(cleanup_exit=cleanup_exit):
                primary = []

                def effect(args, **kwargs):
                    if args[2] == "launch":
                        program = ("import os, time\n"
                                   "os.write(1, b'launch pending\\n')\ntime.sleep(30)\n")
                        try:
                            # Exercise a real timeout without waiting for the
                            # unchanged 60-second simulator command deadline.
                            return real_run([sys.executable, "-c", program],
                                            **{**kwargs, "timeout": 1})
                        except subprocess.TimeoutExpired as error:
                            primary.append(error)
                            raise
                    if args[2] in ("shutdown", "delete"):
                        program = ("import os, sys\n"
                                   "os.write(1, b'cleanup output \\xff\\n')\n"
                                   "os.write(2, b'cleanup error \\xfe\\n')\n"
                                   f"sys.exit({cleanup_exit})\n")
                        return real_run([sys.executable, "-c", program], **kwargs)
                    return self.completed(args, **kwargs)

                with self.commands(effect) as mocked, self.assertRaises(subprocess.TimeoutExpired) as caught:
                    SMOKE.main()
                self.assertEqual(len(primary), 1)
                self.assertIs(caught.exception, primary[0])
                self.assertEqual(caught.exception.timeout, 1)
                self.assertEqual(caught.exception.stdout, b"launch pending\n")
                self.assertEqual([call.args[0][2] for call in mocked.call_args_list],
                                 ["list", "create", "boot", "bootstatus", "install", "launch",
                                  "get_app_container", "spawn", "shutdown", "delete"])
                for call in mocked.call_args_list[-2:]:
                    self.assertEqual(call.args[0][3], CREATED_PHONE)
                    self.assertEqual(call.kwargs["timeout"], 60)

    def test_real_child_invalid_delete_text_does_not_qualify_failed_cleanup(self):
        real_run = subprocess.run

        def effect(args, **kwargs):
            if args[2] == "delete":
                program = ("import os, sys\n"
                           "os.write(2, b'owned device still present \\xff\\n')\n"
                           "sys.exit(9)\n")
                return real_run([sys.executable, "-c", program], **kwargs)
            return self.completed(args, **kwargs)

        with self.commands(effect) as mocked, self.assertRaisesRegex(
                ValueError, "Owned simulator cleanup did not delete " + CREATED_PHONE):
            SMOKE.main()
        self.assertEqual([call.args[0][2] for call in mocked.call_args_list],
                         ["list", "create", "boot", "bootstatus", "install", "launch",
                          "terminate", "shutdown", "delete"])
        self.assertIn("owned device still present \ufffd", self.stderr.getvalue())
        self.assertIn("Smoke command exited 9:", self.stdout.getvalue())

    def test_unavailable_command_output_still_attempts_both_owned_cleanup_commands(self):
        for error_type in (BrokenPipeError, ValueError):
            for failure in ("write", "flush"):
                with self.subTest(error=error_type.__name__, failure=failure):
                    self.stdout = UnavailableOutput(error_type, failure)
                    with self.commands() as mocked:
                        self.assertTrue(SMOKE.cleanup_simulator(CREATED_PHONE))
                    self.assertEqual([call.args[0] for call in mocked.call_args_list], [
                        ("xcrun", "simctl", "shutdown", CREATED_PHONE),
                        ("xcrun", "simctl", "delete", CREATED_PHONE),
                    ])
                    self.assertTrue(all(call.kwargs["timeout"] == 60
                                        for call in mocked.call_args_list))

    def test_unavailable_command_output_preserves_original_process_failure(self):
        for stream in ("stdout", "stderr"):
            for failure in ("write", "flush"):
                for outcome in ("timeout", "nonzero"):
                    with self.subTest(stream=stream, failure=failure, outcome=outcome):
                        self.stdout, self.stderr = io.StringIO(), io.StringIO()
                        setattr(self, stream, UnavailableOutput(failure=failure))
                        primary = subprocess.TimeoutExpired("launch", 60,
                                                            output=b"launch pending\n",
                                                            stderr=b"launch refused\n")
                        result = (primary if outcome == "timeout" else
                                  subprocess.CompletedProcess([], 23,
                                                              "launch pending\n", "launch refused\n"))
                        def effect(args, **kwargs):
                            if outcome == "timeout":
                                raise primary
                            return result

                        with self.commands(effect) as mocked:
                            if outcome == "timeout":
                                with self.assertRaises(subprocess.TimeoutExpired) as caught:
                                    SMOKE.run("xcrun", "simctl", "launch", CREATED_PHONE)
                                self.assertIs(caught.exception, primary)
                            else:
                                with self.assertRaises(subprocess.CalledProcessError) as caught:
                                    SMOKE.run("xcrun", "simctl", "launch", CREATED_PHONE)
                                self.assertEqual(caught.exception.returncode, 23)
                                self.assertEqual(caught.exception.output, "launch pending\n")
                                self.assertEqual(caught.exception.stderr, "launch refused\n")
                        self.assertEqual(len(mocked.call_args_list), 1)
                        self.assertEqual(mocked.call_args.args[0],
                                         ("xcrun", "simctl", "launch", CREATED_PHONE))
                        self.assertEqual(mocked.call_args.kwargs["timeout"], 60)
                        if stream == "stdout":
                            self.assertIn("launch refused", self.stderr.getvalue())
                        else:
                            self.assertIn("launch pending", self.stdout.getvalue())

    def test_output_failure_after_create_preserves_owned_identity_and_required_commands(self):
        for failing_udid in (CREATED_PHONE, CREATED_PAD):
            with self.subTest(udid=failing_udid):
                self.stdout = UnavailableOutput(unavailable=False)

                def effect(args, **kwargs):
                    result = self.completed(args, **kwargs)
                    if args[2] == "create" and result.stdout == failing_udid:
                        self.stdout.unavailable = True
                    return result

                with self.commands(effect) as mocked:
                    SMOKE.main()
                for udid in (CREATED_PHONE, CREATED_PAD):
                    owned = [call for call in mocked.call_args_list
                             if len(call.args[0]) > 3 and call.args[0][3] == udid]
                    self.assertEqual([call.args[0][2] for call in owned],
                                     ["boot", "bootstatus", "install", "launch",
                                      "terminate", "shutdown", "delete"])
                    self.assertEqual([call.kwargs["timeout"] for call in owned],
                                     [60, 300, 180, 60, 60, 60, 60])

    def test_unavailable_command_output_does_not_qualify_failed_deletion(self):
        self.stdout = UnavailableOutput()

        def effect(args, **kwargs):
            if args[2] == "delete":
                return subprocess.CompletedProcess(args, 9, "", "owned device still present")
            return self.completed(args, **kwargs)

        with self.commands(effect) as mocked, self.assertRaisesRegex(
                ValueError, "Owned simulator cleanup did not delete " + CREATED_PHONE):
            SMOKE.main()
        self.assertEqual([call.args[0][2] for call in mocked.call_args_list],
                         ["list", "create", "boot", "bootstatus", "install", "launch",
                          "terminate", "shutdown", "delete"])
        self.assertIn("owned device still present", self.stderr.getvalue())

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

    def test_install_observation_errors_preserve_success_and_primary_failure(self):
        for install_fails, sink_fails in ((False, False), (False, True), (True, False), (True, True)):
            with self.subTest(install_fails=install_fails, sink_fails=sink_fails):
                observed = []
                primary = subprocess.TimeoutExpired("install", 180)

                def effect(args, **kwargs):
                    if install_fails and args[2] == "install":
                        raise primary
                    if install_fails and args[2] in ("shutdown", "delete"):
                        raise subprocess.TimeoutExpired(args, 60)
                    return self.completed(args, **kwargs)

                def snapshot(udid, phase):
                    observed.append((udid, phase))
                    if phase in ("before-install", "install-failed"):
                        raise RuntimeError("private diagnostic detail must remain excluded")

                def observation_output(*args, **kwargs):
                    if sink_fails and args and '"smoke_snapshot"' in str(args[0]):
                        raise OSError("private observation-output failure")
                    print(*args, **kwargs)

                self.stdout = io.StringIO()
                with self.commands(effect, snapshot_effect=snapshot) as mocked, \
                        patch.object(SMOKE, "print", side_effect=observation_output, create=True):
                    if install_fails:
                        with self.assertRaises(subprocess.TimeoutExpired) as caught:
                            SMOKE.main()
                        self.assertIs(caught.exception, primary)
                    else:
                        SMOKE.main()
                self.assertEqual([x for x in observed if x[1] in ("before-install", "install-failed")],
                                 [(CREATED_PHONE, "before-install"), (CREATED_PHONE, "install-failed")]
                                 if install_fails else
                                 [(CREATED_PHONE, "before-install"), (CREATED_PAD, "before-install")])
                calls = [c.args[0] for c in mocked.call_args_list]
                self.assertEqual([c[2] for c in calls[-2:]], ["shutdown", "delete"])
                self.assertEqual(sum(c[2] == "launch" for c in calls), 0 if install_fails else 2)
                self.assertNotIn("private diagnostic detail", self.stdout.getvalue())
                self.assertNotIn("private observation-output", self.stdout.getvalue())
                records = [json.loads(line) for line in self.stdout.getvalue().splitlines()
                           if line.startswith("{") and '"smoke_snapshot"' in line]
                self.assertEqual([r["error"] for r in records], [] if sink_fails else ["RuntimeError", "RuntimeError"])


    def test_install_failure_real_probe_timeouts_preserve_redaction_and_cleanup(self):
        primary = subprocess.TimeoutExpired("install", 180, stderr=b"primary installation timeout\n")
        real_run = subprocess.run
        program = ("import time\n"
                   "print('101 1 S 0.0 128 /private/synthetic/installd\\n"
                   "102 1 S 0.0 128 /private/other --secret=excluded', flush=True)\n"
                   "time.sleep(30)\n")

        def effect(args, **kwargs):
            if args[0] == "/bin/ps":
                self.assertEqual(kwargs["timeout"], 1)
                return real_run((sys.executable, "-c", program), **kwargs)
            if args[0] == "/usr/bin/vm_stat":
                return subprocess.CompletedProcess(args, 0, "Pages free: 7.\n", "private stderr")
            if args[2] == "spawn":
                self.assertEqual(args, ("xcrun", "simctl", "spawn", CREATED_PHONE, "launchctl", "list"))
                return subprocess.CompletedProcess(args, 0, "123 0 com.apple.installd\n", "private stderr")
            if args[2] == "install":
                self.assertEqual(kwargs["timeout"], 180)
                raise primary
            if args[2] == "shutdown":
                raise subprocess.TimeoutExpired(args, 60)
            return self.completed(args, **kwargs)

        started = time.monotonic()
        with patch.object(SMOKE.subprocess, "run", side_effect=effect) as mocked, \
                patch.object(SMOKE.os, "getloadavg", return_value=(1.0, 2.0, 3.0)), \
                patch.object(SMOKE, "SNAPSHOT_TIMEOUT_SECONDS", 1), \
                contextlib.redirect_stdout(self.stdout), contextlib.redirect_stderr(self.stderr), \
                self.assertRaises(subprocess.TimeoutExpired) as caught:
            SMOKE.main()
        self.assertIs(caught.exception, primary)
        self.assertLess(time.monotonic() - started, 10)
        records = [json.loads(line) for line in self.stdout.getvalue().splitlines()
                   if line.startswith("{") and '"smoke_snapshot"' in line]
        self.assertEqual(len(records), 12)
        self.assertEqual([r["smoke_snapshot"] for r in records],
                         ["before-boot"] * 4 + ["before-install"] * 4 + ["install-failed"] * 4)
        self.assertTrue(all(r["owned_udid"] == CREATED_PHONE for r in records))
        processes = [r for r in records if r.get("probe") == "processes"]
        self.assertEqual([r["error"] for r in processes], ["timeout"] * 3)
        self.assertEqual([r["rows"] for r in processes], [["101 1 S 0.0 128 installd"]] * 3)
        self.assertNotIn("/private/", self.stdout.getvalue())
        self.assertNotIn("secret=excluded", self.stdout.getvalue())
        self.assertNotIn("private stderr", self.stdout.getvalue())
        calls = [c.args[0] for c in mocked.call_args_list]
        self.assertEqual(sum(c[0] == "/bin/ps" for c in calls), 3)
        actions = [c[2] for c in calls if c[0] == "xcrun"]
        self.assertEqual(actions, ["list", "create", "spawn", "boot", "bootstatus", "spawn",
                                   "install", "spawn", "shutdown", "delete"])
        self.assertEqual(calls[-1], ("xcrun", "simctl", "delete", CREATED_PHONE))
        self.assertIn("primary installation timeout", self.stderr.getvalue())


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

    def test_cleanup_reporting_failure_preserves_primary_error_and_deletion_requirement(self):
        for launch_fails in (False, True):
            for failed_actions in (("shutdown",), ("delete",), ("shutdown", "delete")):
                for sink_fails in (False, True):
                    with self.subTest(launch_fails=launch_fails, failed_actions=failed_actions,
                                      sink_fails=sink_fails):
                        self.stdout, self.stderr = io.StringIO(), io.StringIO()
                        primary = subprocess.TimeoutExpired("launch", 60)

                        def effect(args, **kwargs):
                            if launch_fails and args[2] == "launch":
                                raise primary
                            if args[2] in failed_actions:
                                raise subprocess.TimeoutExpired(args, 60)
                            return self.completed(args, **kwargs)

                        def cleanup_output(*args, **kwargs):
                            if (sink_fails and args and str(args[0]).startswith("Owned simulator ")
                                    and " did not complete for " in str(args[0])):
                                raise BrokenPipeError("synthetic cleanup-warning output failure")
                            print(*args, **kwargs)

                        with self.commands(effect) as mocked, \
                                patch.object(SMOKE, "print", side_effect=cleanup_output, create=True):
                            if launch_fails:
                                with self.assertRaises(subprocess.TimeoutExpired) as caught:
                                    SMOKE.main()
                                self.assertIs(caught.exception, primary)
                            elif "delete" in failed_actions:
                                with self.assertRaisesRegex(ValueError,
                                                            "Owned simulator cleanup did not delete " + CREATED_PHONE):
                                    SMOKE.main()
                            else:
                                SMOKE.main()

                        calls = mocked.call_args_list
                        destinations = ((CREATED_PHONE,) if launch_fails or "delete" in failed_actions
                                        else (CREATED_PHONE, CREATED_PAD))
                        cleanup = [call for call in calls if call.args[0][2] in ("shutdown", "delete")]
                        self.assertEqual([call.args[0] for call in cleanup],
                                         [("xcrun", "simctl", action, udid)
                                          for udid in destinations for action in ("shutdown", "delete")])
                        self.assertTrue(all(call.kwargs["timeout"] == 60 for call in cleanup))
                        self.assertEqual(sum(call.args[0][2] == "launch" for call in calls), len(destinations))
                        self.assertEqual(sum(call.args[0][2] == "terminate" for call in calls),
                                         0 if launch_fails else len(destinations))
                        self.assertEqual([call.args[0][2] for call in calls
                                          if call.args[0][2] in ("get_app_container", "spawn")],
                                         ["get_app_container", "spawn"] if launch_fails else [])

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

    def test_launch_observation_errors_preserve_success_and_primary_failure(self):
        for launch_fails in (False, True):
            for sink_fails in (False, True):
                with self.subTest(launch_fails=launch_fails, sink_fails=sink_fails):
                    self.stdout, self.stderr = io.StringIO(), io.StringIO()
                    observed = []
                    primary = subprocess.TimeoutExpired("launch", 60)

                    def effect(args, **kwargs):
                        if launch_fails and args[2] == "launch":
                            raise primary
                        if launch_fails and args[2] in ("shutdown", "delete"):
                            raise subprocess.TimeoutExpired(args, 60)
                        return self.completed(args, **kwargs)

                    def snapshot(udid, phase):
                        if phase in ("before-launch", "launch-failed"):
                            observed.append((udid, phase))
                            raise RuntimeError("private launch observer detail excluded")

                    def observation_output(*args, **kwargs):
                        if sink_fails and args and '"smoke_snapshot"' in str(args[0]):
                            raise OSError("private observation-output failure")
                        print(*args, **kwargs)

                    with self.commands(effect, snapshot_effect=snapshot) as mocked, \
                            patch.object(SMOKE, "print", side_effect=observation_output, create=True):
                        if launch_fails:
                            with self.assertRaises(subprocess.TimeoutExpired) as caught:
                                SMOKE.main()
                            self.assertIs(caught.exception, primary)
                        else:
                            SMOKE.main()
                    self.assertEqual(observed,
                                     [(CREATED_PHONE, "before-launch"), (CREATED_PHONE, "launch-failed")]
                                     if launch_fails else
                                     [(CREATED_PHONE, "before-launch"), (CREATED_PAD, "before-launch")])
                    calls = [call.args[0] for call in mocked.call_args_list]
                    self.assertEqual([args[2] for args in calls[-2:]], ["shutdown", "delete"])
                    self.assertEqual(sum(args[2] == "launch" for args in calls), 1 if launch_fails else 2)
                    self.assertEqual(sum(args[2] == "terminate" for args in calls), 0 if launch_fails else 2)
                    if launch_fails:
                        self.assertEqual([args[2] for args in calls[-4:]],
                                         ["get_app_container", "spawn", "shutdown", "delete"])
                    self.assertNotIn("private", self.stdout.getvalue() + self.stderr.getvalue())
                    records = [json.loads(line) for line in self.stdout.getvalue().splitlines()
                               if line.startswith("{") and '"smoke_snapshot"' in line]
                    self.assertEqual([record["error"] for record in records],
                                     [] if sink_fails else ["RuntimeError", "RuntimeError"])

    def test_launch_diagnostic_output_failure_preserves_primary_error_and_remaining_commands(self):
        for diagnostic_failure in ("timeout", "nonzero", "unavailable", "unexpected"):
            for cleanup_fails in (False, True):
                with self.subTest(diagnostic_failure=diagnostic_failure, cleanup_fails=cleanup_fails):
                    self.stdout, self.stderr = io.StringIO(), io.StringIO()
                    primary = subprocess.TimeoutExpired("launch", 60)

                    def effect(args, **kwargs):
                        if args[2] == "launch":
                            raise primary
                        if args[2] in ("get_app_container", "spawn"):
                            if diagnostic_failure == "timeout":
                                raise subprocess.TimeoutExpired(args, 15)
                            if diagnostic_failure == "nonzero":
                                return subprocess.CompletedProcess(args, 7, "", "diagnostic refused")
                            if diagnostic_failure == "unavailable":
                                raise FileNotFoundError("synthetic diagnostic unavailable")
                            raise RuntimeError("synthetic diagnostic failure")
                        if cleanup_fails and args[2] in ("shutdown", "delete"):
                            raise subprocess.TimeoutExpired(args, 60)
                        return self.completed(args, **kwargs)

                    def diagnostic_output(*args, **kwargs):
                        if args and str(args[0]).startswith("Launch diagnostic did not complete"):
                            raise BrokenPipeError("synthetic diagnostic output failure")
                        print(*args, **kwargs)

                    with self.commands(effect) as mocked, \
                            patch.object(SMOKE, "print", side_effect=diagnostic_output, create=True), \
                            self.assertRaises(subprocess.TimeoutExpired) as caught:
                        SMOKE.main()
                    self.assertIs(caught.exception, primary)
                    calls = mocked.call_args_list
                    self.assertEqual([call.args[0][2] for call in calls][-5:],
                                     ["launch", "get_app_container", "spawn", "shutdown", "delete"])
                    self.assertEqual(sum(call.args[0][2] == "launch" for call in calls), 1)
                    self.assertNotIn("terminate", [call.args[0][2] for call in calls])
                    for call in calls[-4:]:
                        self.assertEqual(call.args[0][3], CREATED_PHONE)
                        self.assertEqual(call.kwargs["timeout"],
                                         15 if call.args[0][2] in ("get_app_container", "spawn") else 60)

    def test_runtime_snapshot_not_attempted_before_verified_owned_creation(self):
        for boundary in ("inventory", "create", "partial", "malformed", "preexisting"):
            with self.subTest(boundary=boundary):
                observed = []
                def effect(args, **kwargs):
                    if args[2] == "list" and boundary == "inventory":
                        raise subprocess.TimeoutExpired(args, kwargs["timeout"])
                    if args[2] == "create":
                        if boundary in ("create", "partial"):
                            raise subprocess.TimeoutExpired(args, kwargs["timeout"],
                                output=CREATED_PHONE.encode() if boundary == "partial" else None)
                        output = "not-a-uuid" if boundary == "malformed" else EXISTING_PHONE.upper()
                        return subprocess.CompletedProcess(args, 0, output, "")
                    return self.completed(args, **kwargs)
                with self.commands(effect, snapshot_effect=lambda *args: observed.append(args)) as mocked, \
                        self.assertRaises((subprocess.TimeoutExpired, ValueError)):
                    SMOKE.main()
                self.assertEqual(observed, [])
                self.assertEqual([call.args[0][2] for call in mocked.call_args_list],
                                 ["list"] if boundary == "inventory" else ["list", "create"])

    def test_install_snapshots_follow_owned_boot_and_preserve_both_successful_launches(self):
        events = []
        def effect(args, **kwargs):
            events.append((args[2], args[3] if len(args) > 3 else None))
            return self.completed(args, **kwargs)
        def snapshot(udid, phase):
            events.append((phase, udid))
        with self.commands(effect, snapshot_effect=snapshot):
            SMOKE.main()
        phases = ("before-boot", "boot", "bootstatus", "before-install", "install", "before-launch",
                  "launch", "terminate", "shutdown", "delete")
        self.assertEqual([event for event in events if event[0] in phases],
                         [(phase, udid) for udid in (CREATED_PHONE, CREATED_PAD) for phase in phases])
        self.assertNotIn("install-failed", [event[0] for event in events])

    def test_install_failure_survives_failed_snapshot_probes_and_owned_cleanup_without_retry(self):
        for failure in ("timeout", "nonzero", "unavailable"):
            for cleanup_fails in (False, True):
                with self.subTest(failure=failure, cleanup_fails=cleanup_fails):
                    self.stdout, self.stderr = io.StringIO(), io.StringIO()
                    primary = (subprocess.TimeoutExpired("install", 180,
                               output=b"partial installation\n", stderr=b"installation pending\n")
                               if failure == "timeout" else FileNotFoundError("install unavailable"))
                    expected = subprocess.CalledProcessError if failure == "nonzero" else type(primary)
                    probes = []
                    def effect(args, **kwargs):
                        if args[0] == "/usr/bin/vm_stat":
                            probes.append((args, kwargs["timeout"]))
                            raise subprocess.TimeoutExpired(args, 3, output=b"Pages free: 9.\nprivate=excluded")
                        if args[0] == "/bin/ps":
                            probes.append((args, kwargs["timeout"]))
                            raise FileNotFoundError("private diagnostic path excluded")
                        if args[2] == "spawn":
                            probes.append((args, kwargs["timeout"]))
                            self.assertEqual(args, ("xcrun", "simctl", "spawn", CREATED_PHONE, "launchctl", "list"))
                            raise RuntimeError("private diagnostic detail excluded")
                        if args[2] == "install":
                            self.assertEqual(kwargs["timeout"], 180)
                            if failure == "nonzero":
                                return subprocess.CompletedProcess(args, 17, "partial installation\n", "installation refused\n")
                            raise primary
                        if cleanup_fails and args[2] in ("shutdown", "delete"):
                            raise subprocess.TimeoutExpired(args, 60, stderr=b"cleanup stalled\n")
                        return self.completed(args, **kwargs)
                    with patch.object(SMOKE.subprocess, "run", side_effect=effect) as mocked, \
                            patch.object(SMOKE.os, "getloadavg", side_effect=OSError("private load detail excluded")), \
                            contextlib.redirect_stdout(self.stdout), contextlib.redirect_stderr(self.stderr), \
                            self.assertRaises(expected) as caught:
                        SMOKE.main()
                    if failure == "nonzero":
                        self.assertEqual(caught.exception.returncode, 17)
                    else:
                        self.assertIs(caught.exception, primary)
                    calls = [c for c in mocked.call_args_list if c.args[0][:2] == ("xcrun", "simctl")
                             and c.args[0][2] != "spawn"]
                    self.assertEqual([c.args[0][2] for c in calls],
                                     ["list", "create", "boot", "bootstatus", "install", "shutdown", "delete"])
                    self.assertTrue(all(c.args[0][3] == CREATED_PHONE and c.kwargs["timeout"] == 60
                                        for c in calls[-2:]))
                    self.assertEqual(len(probes), 9)
                    self.assertTrue(all(timeout == 3 for _, timeout in probes))
                    records = [json.loads(line) for line in self.stdout.getvalue().splitlines() if line.startswith("{")]
                    records = [record for record in records if "smoke_snapshot" in record]
                    self.assertEqual([r["smoke_snapshot"] for r in records],
                                     ["before-boot"] * 4 + ["before-install"] * 4 + ["install-failed"] * 4)
                    self.assertTrue(all(r["owned_udid"] == CREATED_PHONE for r in records))
                    observations = [r for r in records if "probe" in r]
                    self.assertEqual([r["error"] for r in observations],
                                     ["timeout", "FileNotFoundError", "RuntimeError"] * 3)
                    self.assertEqual(observations[0]["rows"], ["Pages free: 9."])
                    self.assertEqual(observations[3]["rows"], ["Pages free: 9."])
                    self.assertNotIn("private", self.stdout.getvalue() + self.stderr.getvalue())
                    if failure != "unavailable":
                        self.assertIn("partial installation", self.stdout.getvalue())

    def test_second_install_failure_observes_only_its_owned_destination_after_phone_cleanup(self):
        observed = []
        primary = subprocess.TimeoutExpired("install", 180, output=b"tablet installation pending\n")
        def effect(args, **kwargs):
            if args[2] == "install" and args[3] == CREATED_PAD:
                raise primary
            return self.completed(args, **kwargs)
        with self.commands(effect, snapshot_effect=lambda udid, phase: observed.append((phase, udid))) as mocked, \
                self.assertRaises(subprocess.TimeoutExpired) as caught:
            SMOKE.main()
        self.assertIs(caught.exception, primary)
        self.assertEqual(observed, [("before-boot", CREATED_PHONE), ("before-install", CREATED_PHONE),
                                    ("before-launch", CREATED_PHONE), ("before-boot", CREATED_PAD),
                                    ("before-install", CREATED_PAD), ("install-failed", CREATED_PAD)])
        commands = [c.args[0] for c in mocked.call_args_list]
        self.assertEqual([args[3] for args in commands if args[2] == "install"], [CREATED_PHONE, CREATED_PAD])
        self.assertEqual([args[3] for args in commands if args[2] == "launch"], [CREATED_PHONE])
        self.assertEqual([args[3] for args in commands if args[2] == "terminate"], [CREATED_PHONE])
        self.assertEqual([args[3] for args in commands if args[2] == "delete"], [CREATED_PHONE, CREATED_PAD])
        self.assertNotIn("get_app_container", [args[2] for args in commands])


    def test_boot_failures_observe_only_owned_destination_and_preserve_primary_result(self):
        for action in ("boot", "bootstatus"):
            for failed_udid in (CREATED_PHONE, CREATED_PAD):
                for failure in ("timeout", "nonzero", "unavailable"):
                    for cleanup_fails in (False, True):
                        with self.subTest(action=action, udid=failed_udid, failure=failure,
                                          cleanup_fails=cleanup_fails):
                            self.stdout, self.stderr = io.StringIO(), io.StringIO()
                            events = []
                            deadline = 300 if action == "bootstatus" else 60
                            primary = (subprocess.TimeoutExpired(action, deadline, output=b"boot pending\n")
                                       if failure == "timeout" else FileNotFoundError("boot unavailable"))
                            expected = subprocess.CalledProcessError if failure == "nonzero" else type(primary)

                            def effect(args, **kwargs):
                                events.append((args[2], args[3] if len(args) > 3 else None))
                                if args[2] == action and args[3] == failed_udid:
                                    self.assertEqual(kwargs["timeout"], deadline)
                                    if failure == "nonzero":
                                        return subprocess.CompletedProcess(args, 17, "boot pending\n", "boot refused\n")
                                    raise primary
                                if cleanup_fails and args[2] in ("shutdown", "delete") and args[3] == failed_udid:
                                    raise subprocess.TimeoutExpired(args, 60)
                                return self.completed(args, **kwargs)

                            with self.commands(effect, snapshot_effect=lambda udid, phase: events.append((phase, udid))) as mocked, \
                                    self.assertRaises(expected) as caught:
                                SMOKE.main()
                            if failure == "nonzero":
                                self.assertEqual(caught.exception.returncode, 17)
                            else:
                                self.assertIs(caught.exception, primary)
                            failed_events = [name for name, udid in events if udid == failed_udid]
                            self.assertEqual(failed_events,
                                             ["before-boot", "boot"] + (["bootstatus"] if action == "bootstatus" else [])
                                             + ["boot-failed", "shutdown", "delete"])
                            commands = [call.args[0] for call in mocked.call_args_list]
                            reached = [CREATED_PHONE] if failed_udid == CREATED_PHONE else [CREATED_PHONE, CREATED_PAD]
                            self.assertEqual([args[3] for args in commands if args[2] == "boot"], reached)
                            self.assertEqual([args[3] for args in commands if args[2] == "delete"], reached)
                            successes = [] if failed_udid == CREATED_PHONE else [CREATED_PHONE]
                            for successful_action in ("install", "launch", "terminate"):
                                self.assertEqual([args[3] for args in commands if args[2] == successful_action], successes)
                            self.assertNotIn("get_app_container", [args[2] for args in commands])
                            self.assertTrue(all(call.kwargs["timeout"] == 60 for call in mocked.call_args_list[-2:]))
                            if failure != "unavailable":
                                self.assertIn("boot pending", self.stdout.getvalue())

    def test_boot_observer_and_output_errors_do_not_replace_success_or_primary_failure(self):
        for failed_action in (None, "boot", "bootstatus"):
            for sink_fails in (False, True):
                with self.subTest(failed_action=failed_action, sink_fails=sink_fails):
                    self.stdout, self.stderr = io.StringIO(), io.StringIO()
                    observed = []
                    primary = subprocess.TimeoutExpired(failed_action, 300 if failed_action == "bootstatus" else 60)

                    def effect(args, **kwargs):
                        if args[2] == failed_action:
                            raise primary
                        if failed_action and args[2] in ("shutdown", "delete"):
                            raise subprocess.TimeoutExpired(args, 60)
                        return self.completed(args, **kwargs)

                    def snapshot(udid, phase):
                        if phase in ("before-boot", "boot-failed"):
                            observed.append((udid, phase))
                            raise RuntimeError("private boot observer detail excluded")

                    def observation_output(*args, **kwargs):
                        if sink_fails and args and '"smoke_snapshot"' in str(args[0]):
                            raise OSError("private observation-output failure")
                        print(*args, **kwargs)

                    with self.commands(effect, snapshot_effect=snapshot) as mocked, \
                            patch.object(SMOKE, "print", side_effect=observation_output, create=True):
                        if failed_action:
                            with self.assertRaises(subprocess.TimeoutExpired) as caught:
                                SMOKE.main()
                            self.assertIs(caught.exception, primary)
                        else:
                            SMOKE.main()
                    self.assertEqual(observed, [(CREATED_PHONE, "before-boot"), (CREATED_PHONE, "boot-failed")]
                                     if failed_action else [(CREATED_PHONE, "before-boot"), (CREATED_PAD, "before-boot")])
                    calls = [call.args[0] for call in mocked.call_args_list]
                    self.assertEqual([args[2] for args in calls[-2:]], ["shutdown", "delete"])
                    self.assertEqual(sum(args[2] == "launch" for args in calls), 0 if failed_action else 2)
                    self.assertNotIn("private", self.stdout.getvalue() + self.stderr.getvalue())
                    records = [json.loads(line) for line in self.stdout.getvalue().splitlines()
                               if line.startswith("{") and '"smoke_snapshot"' in line]
                    self.assertEqual([record["error"] for record in records],
                                     [] if sink_fails else ["RuntimeError", "RuntimeError"])

    def test_boot_failure_observes_bounded_filtered_resources_without_retrying_readiness(self):
        primary = subprocess.TimeoutExpired("bootstatus", 300, output=b"Waiting on System App\n")
        def effect(args, **kwargs):
            if args[0] == "/usr/bin/vm_stat":
                self.assertEqual(kwargs["timeout"], 3)
                return subprocess.CompletedProcess(args, 0, "Pages free: 7.\nprivate=excluded\n", "private stderr")
            if args[0] == "/bin/ps":
                self.assertEqual(kwargs["timeout"], 3)
                return subprocess.CompletedProcess(args, 0,
                    "101 1 S 0.0 128 /private/synthetic/launchd_sim\n"
                    "102 1 S 0.0 128 /private/other --secret=excluded\n", "private stderr")
            if args[2] == "spawn":
                self.assertEqual(args, ("xcrun", "simctl", "spawn", CREATED_PHONE, "launchctl", "list"))
                self.assertEqual(kwargs["timeout"], 3)
                raise subprocess.TimeoutExpired(args, 3, output=b"- -9 com.apple.SpringBoard\nprivate=excluded")
            if args[2] == "bootstatus":
                self.assertEqual(kwargs["timeout"], 300)
                raise primary
            return self.completed(args, **kwargs)

        with patch.object(SMOKE.subprocess, "run", side_effect=effect) as mocked, \
                patch.object(SMOKE.os, "getloadavg", return_value=(1.0, 2.0, 3.0)), \
                contextlib.redirect_stdout(self.stdout), contextlib.redirect_stderr(self.stderr), \
                self.assertRaises(subprocess.TimeoutExpired) as caught:
            SMOKE.main()
        self.assertIs(caught.exception, primary)
        records = [json.loads(line) for line in self.stdout.getvalue().splitlines()
                   if line.startswith("{") and '"smoke_snapshot"' in line]
        self.assertEqual([record["smoke_snapshot"] for record in records], ["before-boot"] * 4 + ["boot-failed"] * 4)
        self.assertTrue(all(record["owned_udid"] == CREATED_PHONE for record in records))
        for offset in (0, 4):
            self.assertEqual(records[offset]["host_load_averages"], [1.0, 2.0, 3.0])
            self.assertEqual(records[offset + 1]["rows"], ["Pages free: 7."])
            self.assertEqual(records[offset + 2]["rows"], ["101 1 S 0.0 128 launchd_sim"])
            self.assertEqual(records[offset + 3]["error"], "timeout")
            self.assertEqual(records[offset + 3]["rows"], ["- -9 com.apple.SpringBoard"])
        commands = [call.args[0] for call in mocked.call_args_list if call.args[0][0] == "xcrun"]
        self.assertEqual([args[2] for args in commands],
                         ["list", "create", "spawn", "boot", "bootstatus", "spawn", "shutdown", "delete"])
        self.assertNotIn("private", self.stdout.getvalue() + self.stderr.getvalue())
        self.assertNotIn("secret=excluded", self.stdout.getvalue())
        self.assertIn("Waiting on System App", self.stdout.getvalue())

    def assert_launch_observation_is_non_authoritative(self, phase, failure):
        for failing_udid in (CREATED_PHONE, CREATED_PAD):
            with self.subTest(phase=phase, failure=failure, owned_udid=failing_udid):
                self.stdout, self.stderr = io.StringIO(), io.StringIO()
                observed, sink_failures = [], []
                primary = subprocess.TimeoutExpired("launch", 60,
                                                    output=b"original launch pending\n")
                original_collector = SMOKE.collect_runtime_snapshot

                def effect(args, **kwargs):
                    if phase == "launch-failed" and args[2] == "launch" and args[3] == failing_udid:
                        raise primary
                    return self.completed(args, **kwargs)

                def snapshot(udid, current_phase):
                    if udid == failing_udid and current_phase == phase:
                        observed.append((udid, current_phase))
                        if failure == "collector":
                            raise RuntimeError("private collector detail excluded")
                    original_collector(udid, current_phase)

                def observation_output(*args, **kwargs):
                    if failure == "sink" and args and '"smoke_snapshot"' in str(args[0]):
                        record = json.loads(args[0])
                        if record["owned_udid"] == failing_udid and record["smoke_snapshot"] == phase:
                            sink_failures.append((record["owned_udid"], record["smoke_snapshot"]))
                            raise OSError("private observation sink detail excluded")
                    print(*args, **kwargs)

                def probe(kind, command):
                    return {"probe": kind, "deadline_seconds": 3, "exit": 0,
                            "rows": [], "truncated": False}

                with self.commands(effect, snapshot_effect=snapshot) as mocked, \
                        patch.object(SMOKE, "snapshot_probe", side_effect=probe), \
                        patch.object(SMOKE.os, "getloadavg", return_value=(1.0, 2.0, 3.0)), \
                        patch.object(SMOKE, "print", side_effect=observation_output, create=True):
                    if phase == "launch-failed":
                        with self.assertRaises(subprocess.TimeoutExpired) as caught:
                            SMOKE.main()
                        self.assertIs(caught.exception, primary)
                    else:
                        SMOKE.main()

                self.assertEqual(observed, [(failing_udid, phase)])
                if failure == "sink":
                    self.assertTrue(sink_failures)
                    self.assertEqual(set(sink_failures), {(failing_udid, phase)})
                calls = mocked.call_args_list
                commands = [call.args[0] for call in calls]
                destinations = [CREATED_PHONE] if phase == "launch-failed" and failing_udid == CREATED_PHONE else [CREATED_PHONE, CREATED_PAD]
                self.assertEqual([args[3] for args in commands if args[2] == "launch"], destinations)
                for udid in destinations:
                    owned = [args[2] for args in commands if len(args) > 3 and args[3] == udid]
                    expected = ["boot", "bootstatus", "install", "launch"]
                    expected += ["get_app_container", "spawn"] if phase == "launch-failed" and udid == failing_udid else ["terminate"]
                    self.assertEqual(owned, expected + ["shutdown", "delete"])
                diagnostic_commands = [args for args in commands if args[2] in ("get_app_container", "spawn")]
                if phase == "launch-failed":
                    self.assertEqual(diagnostic_commands, [
                        ("xcrun", "simctl", "get_app_container", failing_udid,
                         "invalid.pickyourai.localpreview", "app"),
                        ("xcrun", "simctl", "spawn", failing_udid, "log", "show",
                         "--style", "compact", "--last", "2m", "--info", "--predicate",
                         'process == "Planner" OR eventMessage CONTAINS "invalid.pickyourai.localpreview"'),
                    ])
                    self.assertIn("original launch pending", self.stdout.getvalue())
                else:
                    self.assertEqual(diagnostic_commands, [])
                for call in calls:
                    action = call.args[0][2]
                    expected_timeout = {"bootstatus": 300, "install": 180,
                                        "get_app_container": 15, "spawn": 15}.get(action, 60)
                    self.assertEqual(call.kwargs["timeout"], expected_timeout)
                self.assertNotIn("private", self.stdout.getvalue() + self.stderr.getvalue())

    def test_before_launch_collector_failure_preserves_launch_and_owned_cleanup(self):
        self.assert_launch_observation_is_non_authoritative("before-launch", "collector")

    def test_before_launch_observation_sink_failure_preserves_launch_and_owned_cleanup(self):
        self.assert_launch_observation_is_non_authoritative("before-launch", "sink")

    def test_launch_failed_collector_failure_preserves_original_error_diagnostics_and_cleanup(self):
        self.assert_launch_observation_is_non_authoritative("launch-failed", "collector")

    def test_launch_failed_observation_sink_failure_preserves_original_error_diagnostics_and_cleanup(self):
        self.assert_launch_observation_is_non_authoritative("launch-failed", "sink")


HEARTBEAT_PROGRAM = r"""
import json, os, sys, time
path, original_parent, lifetime, stop = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
end = time.monotonic() + lifetime
counter = 0
with open(path, "a", buffering=1) as stream:
    while time.monotonic() < end and os.path.isdir(os.path.dirname(path)) and not os.path.exists(stop):
        stream.write(json.dumps({"counter": counter, "pid": os.getpid(),
                                "ppid": os.getppid(), "original_parent": original_parent,
                                "pgid": os.getpgrp(), "sid": os.getsid(0)}) + "\n")
        counter += 1
        time.sleep(0.025)
"""

PARENT_COMMAND_PROGRAM = r"""
import json, os, pathlib, subprocess, sys, time
folder, mode, heartbeat_program = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
(folder / "parent.json").write_text(json.dumps({"pid": os.getpid(), "pgid": os.getpgrp(),
                                              "sid": os.getsid(0)}))
kwargs = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL} if mode == "nonzero" else {}
child = subprocess.Popen([sys.executable, "-c", heartbeat_program,
                          str(folder / "child.jsonl"), str(os.getpid()), "6", str(folder / "stop-heartbeats")], **kwargs)
print("owned parent output", flush=True)
print("owned parent error", file=sys.stderr, flush=True)
end = time.monotonic() + 2
while time.monotonic() < end:
    path = folder / "child.jsonl"
    if path.exists() and len(path.read_text().splitlines()) >= 2:
        break
    time.sleep(0.01)
else:
    raise RuntimeError("synthetic child did not establish its heartbeat")
if mode == "running-parent":
    time.sleep(6)
else:
    raise SystemExit(23 if mode == "nonzero" else 0)
"""

COMMAND_DRIVER_PROGRAM = r"""
import contextlib, importlib.util, io, json, pathlib, subprocess, sys, time
source, folder, mode, parent_program, heartbeat_program = sys.argv[1:]
spec = importlib.util.spec_from_file_location("isolated_smoke", source)
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)
out, err = io.StringIO(), io.StringIO()
group_signals, real_killpg = [], smoke.os.killpg
def record_group_signal(group, sig):
    group_signals.append({"pgid": group, "signal": int(sig)})
    return real_killpg(group, sig)
smoke.os.killpg = record_group_signal
started = time.monotonic()
with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
    try:
        smoke.run(sys.executable, "-c", parent_program, folder, mode, heartbeat_program, timeout=1)
        result = {"exception": None}
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
        def text(value):
            return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else value
        result = {"exception": type(error).__name__, "timeout": getattr(error, "timeout", None),
                  "returncode": getattr(error, "returncode", None),
                  "stdout": text(error.stdout), "stderr": text(error.stderr)}
    result["elapsed_seconds"] = time.monotonic() - started
    result["next_command"] = smoke.run(sys.executable, "-c", "print('next owned command')", timeout=1)
result["reported_stdout"], result["reported_stderr"] = out.getvalue(), err.getvalue()
result["group_signals"] = group_signals
print(json.dumps(result))
"""


class SimulatorCommandOwnershipTests(unittest.TestCase):
    @staticmethod
    def heartbeat(path):
        rows = []
        if path.exists():
            for line in path.read_text().splitlines():
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    # A killed writer may leave an incomplete final record.
                    pass
        return rows

    @staticmethod
    def stop_fixture_process(process):
        # Retain the private direct-child handle as the ownership anchor. A
        # completed communicate()/poll() may already have released its group ID.
        if process.returncode is not None:
            return
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        finally:
            for stream in (process.stdout, process.stderr):
                if stream is not None:
                    stream.close()
        process.wait(timeout=2)

    def assert_owned_process_boundary(self, mode):
        # Every fixture has its own session and a finite self-expiry. The outer
        # supervisor signals only still-unreaped direct children; indirect
        # heartbeat writers receive a private cooperative stop request.
        with tempfile.TemporaryDirectory(prefix="smoke-owned-process-") as directory:
            folder = Path(directory)
            sentinel = subprocess.Popen([sys.executable, "-c", HEARTBEAT_PROGRAM,
                                         str(folder / "sentinel.jsonl"), str(os.getpid()), "12",
                                         str(folder / "stop-heartbeats")],
                                        start_new_session=True, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL)
            driver = None
            try:
                ready_deadline = time.monotonic() + 2
                while len(self.heartbeat(folder / "sentinel.jsonl")) < 2 and time.monotonic() < ready_deadline:
                    time.sleep(0.01)
                self.assertGreaterEqual(len(self.heartbeat(folder / "sentinel.jsonl")), 2)
                driver = subprocess.Popen([sys.executable, "-c", COMMAND_DRIVER_PROGRAM,
                                           str(Path(SMOKE.__file__).resolve()), str(folder), mode,
                                           PARENT_COMMAND_PROGRAM, HEARTBEAT_PROGRAM],
                                          start_new_session=True, stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE, text=True)
                # Generous wall-clock cap only prevents a wedged driver from hanging
                # the suite; the behavioral bound is the elapsed_seconds assertion.
                stdout, stderr = driver.communicate(timeout=30)
                self.assertEqual(driver.returncode, 0, stderr)
                result = json.loads(stdout)
                parent = json.loads((folder / "parent.json").read_text())
                # Signal authority is limited to the fixture's own new session.
                # start_new_session makes the command its own group and session
                # leader. Inheriting the driver's group (driver.pid) would be a
                # lost-isolation regression and must not satisfy this check.
                self.assertEqual(parent["pgid"], parent["pid"])
                self.assertEqual(parent["sid"], parent["pgid"])
                self.assertNotEqual(parent["pgid"], driver.pid)
                self.assertNotEqual(parent["pgid"], sentinel.pid)
                time.sleep(0.10)
                first = self.heartbeat(folder / "child.jsonl")
                sentinel_first = self.heartbeat(folder / "sentinel.jsonl")
                time.sleep(0.20)
                second = self.heartbeat(folder / "child.jsonl")
                sentinel_second = self.heartbeat(folder / "sentinel.jsonl")
                observed = {"mode": mode, "parent": parent, "driver_pid": driver.pid,
                            "sentinel_pid": sentinel.pid, "exception": result["exception"],
                            "timeout": result.get("timeout"), "returncode": result.get("returncode"),
                            "elapsed_seconds": result["elapsed_seconds"],
                            "child_samples": [len(first), len(second)],
                            "sentinel_samples": [len(sentinel_first), len(sentinel_second)],
                            "observed_orphan": any(row["ppid"] != parent["pid"] for row in second),
                            "next_command": result["next_command"],
                            "group_signals": result["group_signals"]}
                print("owned-command-fixture " + json.dumps(observed, sort_keys=True), flush=True)
                self.assertEqual(result["exception"], "CalledProcessError" if mode == "nonzero" else "TimeoutExpired")
                self.assertEqual(result["returncode"] if mode == "nonzero" else result["timeout"],
                                 23 if mode == "nonzero" else 1)
                self.assertIn("owned parent output", result["stdout"])
                self.assertIn("owned parent error", result["stderr"])
                self.assertEqual(result["next_command"], "next owned command")
                self.assertLess(result["elapsed_seconds"], 4)
                self.assertGreater(len(first), 0)
                self.assertGreater(len(sentinel_second), len(sentinel_first))
                self.assertIsNone(sentinel.poll(), "unrelated sentinel was terminated")
                if mode == "exited-parent":
                    self.assertTrue(observed["observed_orphan"], "parent exit was not actually observed")
                if mode == "nonzero":
                    self.assertEqual(result["group_signals"], [], "reaped process-group identity must not be signalled")
                    self.assertGreater(len(second), len(first), "completed command descendants are outside timeout cleanup")
                else:
                    self.assertEqual(len(second), len(first), "owned descendant still writes after command failure")
                    self.assertEqual(result["group_signals"], [{"pgid": parent["pid"], "signal": int(signal.SIGKILL)}])
            finally:
                # This request occurs only after the behavioral assertions. The
                # heartbeat also stops if its private directory is removed and
                # always retains its finite lifetime, even if cleanup is cut off.
                (folder / "stop-heartbeats").touch()
                for process in (driver, sentinel):
                    if process is not None:
                        self.stop_fixture_process(process)

    @unittest.skipUnless(os.name == "posix", "requires POSIX process-group ownership")
    def test_fixture_cleanup_signals_only_unreaped_direct_process_handles(self):
        completed = Mock(pid=2 ** 30, returncode=0)
        with patch.object(os, "killpg") as group:
            self.stop_fixture_process(completed)
        group.assert_not_called()
        completed.poll.assert_not_called()
        completed.wait.assert_not_called()

        live = Mock(pid=2 ** 30, returncode=None)
        live.stdout, live.stderr = io.StringIO(), io.StringIO()
        with patch.object(os, "killpg") as group:
            self.stop_fixture_process(live)
        group.assert_called_once_with(live.pid, signal.SIGKILL)
        live.poll.assert_not_called()
        live.wait.assert_called_once_with(timeout=2)
        self.assertTrue(live.stdout.closed)
        self.assertTrue(live.stderr.closed)

    @unittest.skipUnless(os.name == "posix", "requires POSIX process-group ownership")
    def test_timeout_stops_pipe_holding_descendant_after_observed_parent_exit(self):
        self.assert_owned_process_boundary("exited-parent")

    @unittest.skipUnless(os.name == "posix", "requires POSIX process-group ownership")
    def test_timeout_stops_running_parent_and_owned_descendant(self):
        self.assert_owned_process_boundary("running-parent")

    @unittest.skipUnless(os.name == "posix", "requires POSIX process-group ownership")
    def test_nonzero_exit_preserves_result_without_signalling_reaped_group(self):
        self.assert_owned_process_boundary("nonzero")

    @unittest.skipUnless(os.name == "posix", "requires POSIX process-group ownership")
    def test_cleanup_errors_preserve_original_timeout_and_finite_reap_budget(self):
        command = ("synthetic-required-command", "argument")
        error = subprocess.TimeoutExpired(command, 7, output=b"partial output\n", stderr=b"partial error\n")
        process = Mock(pid=2 ** 30, returncode=None)
        process.stdout, process.stderr = io.StringIO(), io.StringIO()
        process.communicate.side_effect = error
        process.kill.side_effect = OSError("synthetic kill failure")
        process.wait.side_effect = subprocess.TimeoutExpired(command, SMOKE.COMMAND_REAP_TIMEOUT_SECONDS)
        out, err = io.StringIO(), io.StringIO()
        with patch.object(SMOKE.subprocess, "Popen", return_value=process) as popen, \
                patch.object(SMOKE.os, "killpg", side_effect=OSError("synthetic group failure")) as group, \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                self.assertRaises(subprocess.TimeoutExpired) as caught:
            SMOKE.run(*command, timeout=7)
        self.assertIs(caught.exception, error)
        popen.assert_called_once_with(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      text=True, errors="replace", start_new_session=True)
        process.communicate.assert_called_once_with(timeout=7)
        group.assert_called_once_with(process.pid, signal.SIGKILL)
        process.kill.assert_called_once_with()
        process.wait.assert_called_once_with(timeout=5)
        self.assertTrue(process.stdout.closed)
        self.assertTrue(process.stderr.closed)
        self.assertIn("partial output", out.getvalue())
        self.assertIn("partial error", err.getvalue())
        self.assertIn("Owned command reap did not complete: TimeoutExpired", err.getvalue())
        self.assertIn("timed out after 7s", err.getvalue())

    def test_non_posix_preserves_existing_required_command_contract(self):
        command = ("synthetic-required-command", "argument")
        timeout = subprocess.TimeoutExpired(command, 7, output=b"partial", stderr=b"error")
        for outcome in (subprocess.CompletedProcess(command, 0, "success\n", ""),
                        subprocess.CompletedProcess(command, 23, "output", "error"), timeout):
            with self.subTest(outcome=type(outcome).__name__, status=getattr(outcome, "returncode", None)):
                kwargs = {"side_effect": outcome} if isinstance(outcome, Exception) else {"return_value": outcome}
                with patch.object(SMOKE.os, "name", "nt"), \
                        patch.object(SMOKE.subprocess, "run", **kwargs) as runner, \
                        patch.object(SMOKE.subprocess, "Popen") as popen, \
                        contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    if outcome is timeout:
                        with self.assertRaises(subprocess.TimeoutExpired) as caught:
                            SMOKE.run(*command, timeout=7)
                        self.assertIs(caught.exception, timeout)
                    elif outcome.returncode:
                        with self.assertRaises(subprocess.CalledProcessError) as caught:
                            SMOKE.run(*command, timeout=7)
                        self.assertEqual((caught.exception.returncode, caught.exception.stdout, caught.exception.stderr),
                                         (23, "output", "error"))
                    else:
                        self.assertEqual(SMOKE.run(*command, timeout=7), "success")
                runner.assert_called_once_with(command, capture_output=True, text=True, errors="replace",
                                               check=False, timeout=7)
                popen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
