import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / "toolchain.py"
spec = importlib.util.spec_from_file_location("native_toolchain", SCRIPT)
toolchain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(toolchain)


class ToolchainPinTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.directory = self.root / "Pinned_Xcode.app" / "Contents" / "Developer"
        self.pin = {"developerDirectory": str(self.directory), "xcodeVersion": "16.4", "xcodeBuildVersion": "16F6"}
        self.pin_file = self.root / "pin.json"
        self.pin_file.write_text(json.dumps(self.pin), encoding="utf-8")

    def test_actual_cli_missing_pin_fails_actionably_before_environment_or_command(self):
        environment_file = self.root / "github-env"
        environment_file.write_text("EXISTING=value\n", encoding="utf-8")
        sentinel = self.root / "downstream-command-ran"
        result = subprocess.run([
            sys.executable, str(SCRIPT), "--pin", str(self.pin_file), "--github-env", str(environment_file), "--",
            sys.executable, "-c", "from pathlib import Path; Path(" + repr(str(sentinel)) + ").write_text('unexpected')",
        ], capture_output=True, text=True, timeout=10, check=False)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("Required developer directory is unavailable", result.stderr)
        self.assertIn("Install Xcode 16.4 (build 16F6)", result.stderr)
        self.assertIn(str(self.directory), result.stderr)
        self.assertIn("https://developer.apple.com/download/all/", result.stderr)
        self.assertIn("App/README.md#pinned-toolchain", result.stderr)
        self.assertIn("No alternate installed Xcode was selected", result.stderr)
        self.assertEqual(environment_file.read_text(encoding="utf-8"), "EXISTING=value\n")
        self.assertFalse(sentinel.exists())
        print("Observed production CLI unavailable-pin rejection: " + result.stderr.strip())

    def test_missing_pin_never_probes_a_global_default(self):
        runner = Mock()
        with self.assertRaisesRegex(toolchain.SetupError, "unavailable"):
            toolchain.verify_pin(self.pin, runner=runner, environment={"DEVELOPER_DIR": "/another/Xcode.app"})
        runner.assert_not_called()

    def test_exact_version_uses_the_explicit_directory_without_mutating_inherited_environment(self):
        self.directory.mkdir(parents=True)
        inherited = {"DEVELOPER_DIR": "/another/Xcode.app", "UNCHANGED": "value"}
        runner = Mock(return_value=subprocess.CompletedProcess([], 0, "Xcode 16.4\nBuild version 16F6\n", ""))
        actual = toolchain.verify_pin(self.pin, runner=runner, environment=inherited)
        self.assertEqual(actual, {"DEVELOPER_DIR": str(self.directory), "UNCHANGED": "value"})
        self.assertEqual(inherited["DEVELOPER_DIR"], "/another/Xcode.app")
        call = runner.call_args
        self.assertEqual(call.args[0], ["/usr/bin/xcodebuild", "-version"])
        self.assertEqual(call.kwargs["env"]["DEVELOPER_DIR"], str(self.directory))
        self.assertEqual(call.kwargs["timeout"], 30)

    def test_wrong_version_build_or_failed_probe_cannot_be_accepted(self):
        self.directory.mkdir(parents=True)
        for code, output in [
            (0, "Xcode 16.3\nBuild version 16F6\n"),
            (0, "Xcode 16.4\nBuild version 16F7\n"),
            (0, "Xcode 16.4\nBuild version 16F6\nunexpected extra output\n"),
            (1, "Xcode 16.4\nBuild version 16F6\n"),
        ]:
            with self.subTest(code=code, output=output):
                runner = Mock(return_value=subprocess.CompletedProcess([], code, output, "untrusted diagnostic"))
                with self.assertRaisesRegex(toolchain.SetupError, "exact required"):
                    toolchain.verify_pin(self.pin, runner=runner, environment={})

    def test_probe_timeout_or_unavailable_command_stays_a_setup_failure(self):
        self.directory.mkdir(parents=True)
        for error in [subprocess.TimeoutExpired("xcodebuild", 30), FileNotFoundError("missing")]:
            with self.subTest(error=type(error).__name__):
                with self.assertRaisesRegex(toolchain.SetupError, "could not finish"):
                    toolchain.verify_pin(self.pin, runner=Mock(side_effect=error), environment={})

    def test_invalid_pin_cannot_inject_a_ci_environment_entry_or_infer_missing_fields(self):
        for mutate in [
            lambda value: value.update(developerDirectory="relative/Xcode.app/Contents/Developer"),
            lambda value: value.update(developerDirectory=str(self.directory) + "\nINJECTED=value"),
            lambda value: value.update(xcodeVersion="latest"),
            lambda value: value.update(xcodeBuildVersion=True),
            lambda value: value.pop("xcodeBuildVersion"),
            lambda value: value.update(fallback="another"),
        ]:
            with self.subTest(mutation=mutate):
                value = dict(self.pin)
                mutate(value)
                self.pin_file.write_text(json.dumps(value), encoding="utf-8")
                with self.assertRaises(toolchain.SetupError):
                    toolchain.load_pin(self.pin_file)

    def test_malformed_oversized_or_unreadable_pin_fails_without_inference(self):
        for data in ["{", "[]", "null", " " * 4097]:
            with self.subTest(data=data[:16]):
                self.pin_file.write_text(data, encoding="utf-8")
                with self.assertRaisesRegex(toolchain.SetupError, "Restore"):
                    toolchain.load_pin(self.pin_file)
        with self.assertRaisesRegex(toolchain.SetupError, "Restore"):
            toolchain.load_pin(self.root / "absent.json")

    def test_verified_cli_environment_and_command_preserve_exact_pin_and_exit_status(self):
        environment_file = self.root / "github-env"
        verified = {"DEVELOPER_DIR": str(self.directory), "UNCHANGED": "value"}
        with patch.object(toolchain, "verify_pin", return_value=verified), \
             patch.object(toolchain.subprocess, "run", return_value=subprocess.CompletedProcess([], 7)) as run:
            code = toolchain.main(["--pin", str(self.pin_file), "--github-env", str(environment_file),
                                   "--", "selected-native-command", "argument with spaces"])
        self.assertEqual(code, 7)
        self.assertEqual(environment_file.read_text(encoding="utf-8"),
                         "DEVELOPER_DIR=" + str(self.directory) + "\n")
        self.assertEqual(run.call_args.args[0], ["selected-native-command", "argument with spaces"])
        self.assertEqual(run.call_args.kwargs["env"], verified)


if __name__ == "__main__":
    unittest.main()
