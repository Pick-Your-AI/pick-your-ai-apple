import importlib.util
import io
import json
import os
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


class ReadBudgetProbe(io.BytesIO):
    """Reject a read request that would consume beyond the input budget."""

    def __init__(self, data, limit):
        super().__init__(data)
        self.limit = limit
        self.bytes_read = 0

    def read(self, size=-1):
        if size < 0 or size > self.limit + 1 - self.bytes_read:
            raise AssertionError("input requested an unbounded or over-budget read")
        data = super().read(size)
        self.bytes_read += len(data)
        return data


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

    @unittest.skipUnless(os.name == "posix", "POSIX FIFO and symlink inputs")
    def test_actual_cli_fifo_pin_fails_before_side_effects_and_regular_symlink_recovers(self):
        fifo = self.root / "pin.fifo"
        os.mkfifo(fifo)
        alias = self.root / "pin-link.json"
        alias.symlink_to(fifo)
        environment_file = self.root / "github-env"
        environment_file.write_text("EXISTING=value\n", encoding="utf-8")
        sentinel = self.root / "downstream-command-ran"
        for pin_path in (fifo, alias):
            with self.subTest(pin_path=pin_path.name):
                result = subprocess.run([
                    sys.executable, str(SCRIPT), "--pin", str(pin_path),
                    "--github-env", str(environment_file), "--", sys.executable, "-c",
                    "from pathlib import Path; Path(" + repr(str(sentinel)) + ").write_text('unexpected')",
                ], capture_output=True, text=True, timeout=10, check=False)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("Cannot read the Xcode pin", result.stderr)
                self.assertIn("input must be a regular file", result.stderr)
                self.assertIn("Restore", result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(environment_file.read_text(encoding="utf-8"), "EXISTING=value\n")
                self.assertFalse(sentinel.exists())
        fifo.unlink()
        fifo.write_bytes(self.pin_file.read_bytes())
        self.assertEqual(toolchain.load_pin(fifo), self.pin)
        self.assertEqual(toolchain.load_pin(alias), self.pin)

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

    def test_pin_read_limit_is_enforced_before_consuming_input(self):
        stream = ReadBudgetProbe(b" " * 4097, 4096)
        with patch.object(toolchain, "open", return_value=stream, create=True):
            with self.assertRaisesRegex(toolchain.SetupError, "pin file exceeds 4096 bytes"):
                toolchain.load_pin(self.pin_file)
        self.assertTrue(stream.closed)
        self.assertGreater(stream.bytes_read, 0)
        self.assertLessEqual(stream.bytes_read, 4097)

    def test_pin_exact_limit_accepts_and_one_extra_byte_rejects_then_recovers(self):
        original = self.pin_file.read_bytes()
        exact = original.ljust(4096, b" ")
        self.assertEqual(len(exact), 4096)
        self.pin_file.write_bytes(exact)
        self.assertEqual(toolchain.load_pin(self.pin_file), self.pin)
        self.pin_file.write_bytes(exact + b" ")
        with self.assertRaisesRegex(toolchain.SetupError, "pin file exceeds 4096 bytes"):
            toolchain.load_pin(self.pin_file)
        self.pin_file.write_bytes(original)
        self.assertEqual(toolchain.load_pin(self.pin_file), self.pin)

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
