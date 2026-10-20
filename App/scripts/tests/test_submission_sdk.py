import copy
from contextlib import redirect_stderr, redirect_stdout
import errno
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch


SCRIPT = Path(__file__).resolve().parents[1] / "submission_sdk.py"
sys.path.insert(0, str(SCRIPT.parent))
spec = importlib.util.spec_from_file_location("submission_sdk", SCRIPT)
submission = importlib.util.module_from_spec(spec)
spec.loader.exec_module(submission)


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


class SubmissionSDKTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.directory = self.root / "Pinned_Xcode.app" / "Contents" / "Developer"
        self.xcode = {"developerDirectory": str(self.directory), "xcodeVersion": "26.3", "xcodeBuildVersion": "17C529"}
        self.sdks = {"sdkVersions": {"iphoneos": "26.2", "iphonesimulator": "26.2"}, "minimumOSVersion": "17.0"}
        self.xcode_file = self.root / "xcode.json"
        self.xcode_file.write_text(json.dumps(self.xcode), encoding="utf-8")
        self.sdk_file = self.root / "sdks.json"
        self.sdk_file.write_text(json.dumps(self.sdks), encoding="utf-8")

    def probe_results(self):
        return [subprocess.CompletedProcess([], 0, value, "") for value in
                ("Xcode 26.3\nBuild version 17C529\n", "26.2\n", "26.2\n")]

    def test_exact_bundle_and_both_sdks_use_the_verified_environment(self):
        self.directory.mkdir(parents=True)
        inherited = {"DEVELOPER_DIR": "/old/Xcode.app", "UNCHANGED": "value"}
        runner = Mock(side_effect=self.probe_results())
        actual = submission.verify_sdks(self.xcode, self.sdks, runner=runner, environment=inherited)
        self.assertEqual(actual, {"DEVELOPER_DIR": str(self.directory), "UNCHANGED": "value"})
        self.assertEqual(inherited["DEVELOPER_DIR"], "/old/Xcode.app")
        self.assertEqual([call.args[0] for call in runner.call_args_list], [
            ["/usr/bin/xcodebuild", "-version"],
            ["/usr/bin/xcrun", "--sdk", "iphoneos", "--show-sdk-version"],
            ["/usr/bin/xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
        ])
        for call in runner.call_args_list:
            self.assertEqual(call.kwargs["env"], actual)
            self.assertEqual(call.kwargs["timeout"], 30)

    def test_wrong_or_failed_sdk_probe_rejects_each_platform(self):
        self.directory.mkdir(parents=True)
        for index in (1, 2):
            for result in [
                subprocess.CompletedProcess([], 0, "18.5\n", ""),
                subprocess.CompletedProcess([], 0, "26.3\n", ""),
                subprocess.CompletedProcess([], 0, "26.2\nextra\n", ""),
                subprocess.CompletedProcess([], 1, "26.2\n", "untrusted diagnostic"),
            ]:
                with self.subTest(index=index, result=result):
                    results = self.probe_results()
                    results[index] = result
                    with self.assertRaisesRegex(submission.toolchain.SetupError, "exact .* SDK 26.2"):
                        submission.verify_sdks(self.xcode, self.sdks, runner=Mock(side_effect=results), environment={})

    def test_sdk_timeout_and_missing_command_fail_closed(self):
        self.directory.mkdir(parents=True)
        for index in (1, 2):
            for error in (subprocess.TimeoutExpired("xcrun", 30), FileNotFoundError("unavailable")):
                with self.subTest(index=index, error=type(error).__name__):
                    results = self.probe_results()
                    results[index] = error
                    with self.assertRaisesRegex(submission.toolchain.SetupError, "could not finish"):
                        submission.verify_sdks(self.xcode, self.sdks, runner=Mock(side_effect=results), environment={})

    def test_xcode_below_upload_floor_is_rejected_before_execution(self):
        runner = Mock()
        with self.assertRaisesRegex(submission.toolchain.SetupError, "Xcode 26 or later"):
            submission.verify_sdks({**self.xcode, "xcodeVersion": "16.4"}, self.sdks, runner=runner)
        runner.assert_not_called()

    def test_invalid_sdk_pins_cannot_infer_a_platform_or_weaken_upload_floors(self):
        for mutate in [
            lambda pin: pin["sdkVersions"].pop("iphoneos"),
            lambda pin: pin["sdkVersions"].update(macosx="26.2"),
            lambda pin: pin["sdkVersions"].update(iphoneos="18.5"),
            lambda pin: pin["sdkVersions"].update(iphonesimulator="latest"),
            lambda pin: pin["sdkVersions"].update(iphoneos="26.2\nINJECTED=value"),
            lambda pin: pin.update(minimumOSVersion="12.0"),
            lambda pin: pin.update(minimumOSVersion=True),
            lambda pin: pin.update(fallback=True),
        ]:
            with self.subTest(mutation=mutate):
                value = copy.deepcopy(self.sdks)
                mutate(value)
                self.sdk_file.write_text(json.dumps(value), encoding="utf-8")
                with self.assertRaises(submission.toolchain.SetupError):
                    submission.load_sdk_pin(self.sdk_file)
        for value in ("{", "null", "[]", " " * 4097):
            with self.subTest(value=value[:16]):
                self.sdk_file.write_text(value, encoding="utf-8")
                with self.assertRaises(submission.toolchain.SetupError):
                    submission.load_sdk_pin(self.sdk_file)

    def test_actual_cli_missing_xcode_does_not_publish_environment_or_receipt(self):
        environment = self.root / "github-env"
        environment.write_text("EXISTING=value\n", encoding="utf-8")
        receipt = self.root / "receipt.json"
        receipt.write_text('{"earlier_verification": "passed"}\n', encoding="utf-8")
        result = subprocess.run([
            sys.executable, str(SCRIPT), "--toolchain-pin", str(self.xcode_file), "--sdk-pin", str(self.sdk_file),
            "verify", "--github-env", str(environment), "--output", str(receipt),
        ], capture_output=True, text=True, timeout=10, check=False)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("Install Xcode 26.3 (build 17C529)", result.stderr)
        self.assertEqual(environment.read_text(encoding="utf-8"), "EXISTING=value\n")
        self.assertFalse(receipt.exists())

    def test_rejected_second_sdk_does_not_publish_verified_xcode_environment(self):
        self.directory.mkdir(parents=True)
        environment = self.root / "github-env"
        environment.write_text("EXISTING=value\n", encoding="utf-8")
        receipt = self.root / "receipt.json"
        receipt.write_text('{"earlier_verification": "passed"}\n', encoding="utf-8")
        results = self.probe_results()
        results[2] = subprocess.CompletedProcess([], 0, "18.5\n", "")
        runner = Mock(side_effect=results)
        verify = submission.verify_sdks
        with patch.object(submission, "verify_sdks", side_effect=lambda xcode, sdks: verify(xcode, sdks, runner=runner, environment={})):
            code = submission.main([
                "--toolchain-pin", str(self.xcode_file), "--sdk-pin", str(self.sdk_file),
                "verify", "--github-env", str(environment), "--output", str(receipt),
            ])
        self.assertEqual(code, 2)
        self.assertEqual(runner.call_count, 3)
        self.assertEqual(environment.read_text(encoding="utf-8"), "EXISTING=value\n")
        self.assertFalse(receipt.exists())

    def test_verified_cli_publishes_only_selected_directory_and_build_identity(self):
        self.directory.mkdir(parents=True)
        environment = self.root / "github-env"
        receipt = self.root / "receipt.json"
        runner = Mock(side_effect=self.probe_results())
        verify = submission.verify_sdks
        with patch.object(submission, "verify_sdks", side_effect=lambda xcode, sdks: verify(
                xcode, sdks, runner=runner, environment={"UNRELATED_PRIVATE_VALUE": "never serialize"})):
            code = submission.main([
                "--toolchain-pin", str(self.xcode_file), "--sdk-pin", str(self.sdk_file),
                "verify", "--github-env", str(environment), "--output", str(receipt),
            ])
        self.assertEqual(code, 0)
        self.assertEqual(environment.read_text(encoding="utf-8"), f"DEVELOPER_DIR={self.directory}\n")
        self.assertEqual(json.loads(receipt.read_text(encoding="utf-8")), {"xcode": self.xcode, **self.sdks})
        self.assertNotIn("never serialize", receipt.read_text(encoding="utf-8"))

    def product_info(self, sdk):
        return {
            "DTXcodeBuild": "17C529", "DTSDKName": sdk + "26.2", "DTPlatformName": sdk,
            "DTPlatformVersion": "26.2", "MinimumOSVersion": "17.0",
            "CFBundleSupportedPlatforms": [submission.SDK_PLATFORMS[sdk]],
            "CFBundleIdentifier": "invalid.pickyourai.localpreview", "CFBundleExecutable": "Planner",
            "DTSDKBuild": "observed-by-hosted-job", "DTXcode": "2630",
            "UnexpectedAppMetadata": "must not enter receipt",
        }

    def write_product(self, info):
        app = self.root / "Planner.app"
        app.mkdir(exist_ok=True)
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        return app

    def test_both_built_products_retain_exact_sdk_build_and_deployment_metadata(self):
        for sdk in submission.SDK_PLATFORMS:
            with self.subTest(sdk=sdk):
                info = self.product_info(sdk)
                receipt = submission.inspect_product(self.write_product(info), sdk, self.xcode, self.sdks)
                self.assertEqual(receipt["DTSDKName"], sdk + "26.2")
                self.assertEqual(receipt["MinimumOSVersion"], "17.0")
                self.assertEqual(receipt["DTSDKBuild"], "observed-by-hosted-job")
                self.assertNotIn("UnexpectedAppMetadata", receipt)

    def test_built_product_cannot_substitute_old_sdk_wrong_platform_or_deployment(self):
        for field, value in [
            ("DTSDKName", "iphoneos18.5"), ("DTXcodeBuild", "16F6"),
            ("DTPlatformName", "iphonesimulator"), ("DTPlatformVersion", "18.5"),
            ("MinimumOSVersion", "26.0"), ("CFBundleSupportedPlatforms", ["iPhoneSimulator"]),
        ]:
            with self.subTest(field=field):
                info = self.product_info("iphoneos")
                info[field] = value
                with self.assertRaisesRegex(submission.toolchain.SetupError, field):
                    submission.inspect_product(self.write_product(info), "iphoneos", self.xcode, self.sdks)
        with self.assertRaises(submission.toolchain.SetupError):
            submission.inspect_product(self.write_product({}), "iphoneos", self.xcode, self.sdks)

    def test_missing_or_malformed_built_metadata_fails(self):
        app = self.root / "Planner.app"
        with self.assertRaises(submission.toolchain.SetupError):
            submission.inspect_product(app, "iphoneos", self.xcode, self.sdks)
        app.mkdir()
        for data in (b"not a plist", plistlib.dumps(["wrong shape"]), b" " * (1024 * 1024 + 1)):
            with self.subTest(data=data[:32]):
                (app / "Info.plist").write_bytes(data)
                with self.assertRaises(submission.toolchain.SetupError):
                    submission.inspect_product(app, "iphoneos", self.xcode, self.sdks)

    def test_sdk_pin_read_limit_is_enforced_before_consuming_input(self):
        stream = ReadBudgetProbe(b" " * 4097, 4096)
        with patch.object(submission.toolchain, "open", return_value=stream, create=True):
            with self.assertRaisesRegex(submission.toolchain.SetupError, "SDK pin exceeds 4096 bytes"):
                submission.load_sdk_pin(self.sdk_file)
        self.assertTrue(stream.closed)
        self.assertGreater(stream.bytes_read, 0)
        self.assertLessEqual(stream.bytes_read, 4097)

    def test_product_read_limit_is_enforced_before_consuming_input(self):
        limit = 1024 * 1024
        app = self.write_product(self.product_info("iphoneos"))
        stream = ReadBudgetProbe(b" " * (limit + 1), limit)
        with patch.object(submission.toolchain, "open", return_value=stream, create=True):
            with self.assertRaisesRegex(submission.toolchain.SetupError, "built Info.plist exceeds the inspection bound"):
                submission.inspect_product(app, "iphoneos", self.xcode, self.sdks)
        self.assertTrue(stream.closed)
        self.assertGreater(stream.bytes_read, 0)
        self.assertLessEqual(stream.bytes_read, limit + 1)

    def test_sdk_pin_exact_limit_accepts_and_one_extra_byte_rejects_then_recovers(self):
        original = self.sdk_file.read_bytes()
        exact = original.ljust(4096, b" ")
        self.assertEqual(len(exact), 4096)
        self.sdk_file.write_bytes(exact)
        self.assertEqual(submission.load_sdk_pin(self.sdk_file), self.sdks)
        self.sdk_file.write_bytes(exact + b" ")
        with self.assertRaisesRegex(submission.toolchain.SetupError, "SDK pin exceeds 4096 bytes"):
            submission.load_sdk_pin(self.sdk_file)
        self.sdk_file.write_bytes(original)
        self.assertEqual(submission.load_sdk_pin(self.sdk_file), self.sdks)

    def test_actual_cli_product_exact_limit_rejects_one_extra_byte_and_recovers_receipt(self):
        limit = 1024 * 1024
        for sdk in submission.SDK_PLATFORMS:
            with self.subTest(sdk=sdk):
                app = self.write_product(self.product_info(sdk))
                info_path = app / "Info.plist"
                original = info_path.read_bytes()
                exact = original.ljust(limit, b" ")
                self.assertEqual(len(exact), limit)
                receipt = self.root / "evidence" / f"bounded-{sdk}.json"
                arguments = ("inspect", "--sdk", sdk, "--app", app, "--output", receipt)
                info_path.write_bytes(exact)
                accepted = self.run_cli(*arguments)
                self.assertEqual(accepted.returncode, 0, accepted.stderr)
                expected = json.loads(accepted.stdout)
                self.assertEqual(json.loads(receipt.read_text()), expected)
                self.assertEqual(expected["DTSDKName"], sdk + "26.2")
                self.assertNotIn("UnexpectedAppMetadata", expected)

                info_path.write_bytes(exact + b" ")
                rejected = self.run_cli(*arguments)
                self.assertEqual(rejected.returncode, 2, rejected.stdout + rejected.stderr)
                self.assertIn("built Info.plist exceeds the inspection bound", rejected.stderr)
                self.assertEqual(rejected.stdout, "")
                self.assertFalse(receipt.exists())

                info_path.write_bytes(original)
                recovered = self.run_cli(*arguments)
                self.assertEqual(recovered.returncode, 0, recovered.stderr)
                self.assertEqual(json.loads(recovered.stdout), expected)
                self.assertEqual(json.loads(receipt.read_text()), expected)
                self.assertEqual(list(receipt.parent.glob(".submission-sdk-*.tmp")), [])

    def run_cli(self, *arguments):
        return subprocess.run([
            sys.executable, str(SCRIPT), "--toolchain-pin", str(self.xcode_file),
            "--sdk-pin", str(self.sdk_file), *map(str, arguments),
        ], capture_output=True, text=True, timeout=10, check=False)

    @unittest.skipUnless(os.name == "posix", "POSIX FIFO and symlink inputs")
    def test_actual_cli_fifo_pins_remove_old_receipts_and_regular_symlinks_recover(self):
        environment = self.root / "github-env"
        environment.write_text("EXISTING=value\n", encoding="utf-8")
        receipt = self.root / "selection.json"
        app = self.write_product(self.product_info("iphoneos"))
        for pin_path in (self.xcode_file, self.sdk_file):
            with self.subTest(pin_path=pin_path.name):
                original = pin_path.read_bytes()
                pin_path.unlink()
                os.mkfifo(pin_path)
                receipt.write_text('{"old_success": true}', encoding="utf-8")
                try:
                    rejected = self.run_cli("verify", "--github-env", environment, "--output", receipt)
                    self.assertEqual(rejected.returncode, 2, rejected.stdout + rejected.stderr)
                    self.assertIn("input must be a regular file", rejected.stderr)
                    self.assertIn("Restore", rejected.stderr)
                    self.assertEqual(rejected.stdout, "")
                    self.assertFalse(receipt.exists())
                    self.assertEqual(environment.read_text(encoding="utf-8"), "EXISTING=value\n")
                finally:
                    pin_path.unlink()
                    regular = pin_path.with_suffix(".regular")
                    regular.write_bytes(original)
                    pin_path.symlink_to(regular)
                recovered = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app, "--output", receipt)
                self.assertEqual(recovered.returncode, 0, recovered.stdout + recovered.stderr)
                self.assertEqual(json.loads(receipt.read_text(encoding="utf-8")), json.loads(recovered.stdout))
                self.assertEqual(json.loads(recovered.stdout)["DTSDKName"], "iphoneos26.2")
                self.assertEqual(environment.read_text(encoding="utf-8"), "EXISTING=value\n")

    @unittest.skipUnless(os.name == "posix", "POSIX FIFO and symlink inputs")
    def test_actual_cli_fifo_metadata_removes_old_receipts_and_regular_symlinks_recover(self):
        receipt = self.root / "product.json"
        for sdk in submission.SDK_PLATFORMS:
            for linked in (False, True):
                with self.subTest(sdk=sdk, linked=linked):
                    app = self.write_product(self.product_info(sdk))
                    info_path = app / "Info.plist"
                    original = info_path.read_bytes()
                    info_path.unlink()
                    fifo = self.root / f"{sdk}-{linked}.fifo" if linked else info_path
                    os.mkfifo(fifo)
                    if linked:
                        info_path.symlink_to(fifo)
                    receipt.write_text('{"old_success": true}', encoding="utf-8")
                    try:
                        rejected = self.run_cli("inspect", "--sdk", sdk, "--app", app, "--output", receipt)
                        self.assertEqual(rejected.returncode, 2, rejected.stdout + rejected.stderr)
                        self.assertIn("input must be a regular file", rejected.stderr)
                        self.assertEqual(rejected.stdout, "")
                        self.assertFalse(receipt.exists())
                    finally:
                        info_path.unlink()
                        regular = self.root / f"{sdk}-{linked}-regular.plist"
                        regular.write_bytes(original)
                        info_path.symlink_to(regular)
                    recovered = self.run_cli("inspect", "--sdk", sdk, "--app", app, "--output", receipt)
                    self.assertEqual(recovered.returncode, 0, recovered.stdout + recovered.stderr)
                    actual = json.loads(recovered.stdout)
                    self.assertEqual(json.loads(receipt.read_text(encoding="utf-8")), actual)
                    self.assertEqual(actual["DTSDKName"], sdk + "26.2")
                    self.assertNotIn("UnexpectedAppMetadata", actual)
                    self.assertEqual(list(receipt.parent.glob(".submission-sdk-*.tmp")), [])

    def test_actual_cli_failed_product_recheck_removes_success_and_valid_retry_recovers(self):
        for sdk in submission.SDK_PLATFORMS:
            with self.subTest(sdk=sdk):
                valid = self.product_info(sdk)
                app = self.write_product(valid)
                receipt = self.root / "evidence" / f"{sdk}.json"
                arguments = ("inspect", "--sdk", sdk, "--app", app, "--output", receipt)
                first = self.run_cli(*arguments)
                self.assertEqual(first.returncode, 0, first.stderr)
                self.assertEqual(json.loads(receipt.read_text())["DTSDKName"], sdk + "26.2")

                self.write_product({**valid, "DTSDKName": sdk + "18.5"})
                failed = self.run_cli(*arguments)
                self.assertEqual(failed.returncode, 2, failed.stdout + failed.stderr)
                self.assertIn("DTSDKName", failed.stderr)
                self.assertEqual(failed.stdout, "")
                self.assertFalse(receipt.exists())

                self.write_product(valid)
                recovered = self.run_cli(*arguments)
                self.assertEqual(recovered.returncode, 0, recovered.stderr)
                self.assertEqual(json.loads(receipt.read_text()), json.loads(recovered.stdout))
                self.assertEqual(list(receipt.parent.glob(".submission-sdk-*.tmp")), [])

    def test_actual_cli_environment_loop_clears_only_the_ordinary_receipt(self):
        environment = self.root / "github-env"
        environment.symlink_to(environment.name)
        receipt = self.root / "receipt.json"
        receipt.write_bytes(b"synthetic earlier verification receipt\n")
        failed = self.run_cli("verify", "--github-env", environment, "--output", receipt)
        self.assertEqual(failed.returncode, 2, failed.stderr)
        self.assertEqual(failed.stdout, "")
        self.assertIn("input contains a link loop", failed.stderr)
        self.assertNotIn("Traceback", failed.stderr)
        self.assertFalse(receipt.exists())
        self.assertTrue(environment.is_symlink())
        self.assertEqual(environment.readlink(), Path(environment.name))

    def test_actual_cli_invalid_pin_removes_the_previous_receipt_before_loading_inputs(self):
        app = self.write_product(self.product_info("iphoneos"))
        receipt = self.root / "product.json"
        arguments = ("inspect", "--sdk", "iphoneos", "--app", app, "--output", receipt)
        for pin in (self.xcode_file, self.sdk_file):
            with self.subTest(pin=pin.name):
                original = pin.read_bytes()
                self.assertEqual(self.run_cli(*arguments).returncode, 0)
                self.assertTrue(receipt.exists())
                pin.write_text("{", encoding="utf-8")
                try:
                    failed = self.run_cli(*arguments)
                    self.assertEqual(failed.returncode, 2)
                    self.assertEqual(failed.stdout, "")
                    self.assertFalse(receipt.exists())
                finally:
                    pin.write_bytes(original)

    def test_environment_write_failure_does_not_publish_a_success_receipt(self):
        self.directory.mkdir(parents=True)
        environment = self.root / "missing-directory" / "github-env"
        receipt = self.root / "receipt.json"
        receipt.write_text('{"earlier_verification": "passed"}\n', encoding="utf-8")
        runner = Mock(side_effect=self.probe_results())
        verify = submission.verify_sdks
        out, err = io.StringIO(), io.StringIO()
        with patch.object(submission, "verify_sdks", side_effect=lambda xcode, sdks: verify(
                xcode, sdks, runner=runner, environment={})), redirect_stdout(out), redirect_stderr(err):
            code = submission.main([
                "--toolchain-pin", str(self.xcode_file), "--sdk-pin", str(self.sdk_file),
                "verify", "--github-env", str(environment), "--output", str(receipt),
            ])
        self.assertEqual(code, 2)
        self.assertEqual(runner.call_count, 3)
        self.assertEqual(out.getvalue(), "")
        self.assertFalse(receipt.exists())
        self.assertFalse(environment.exists())

    def test_failed_atomic_receipt_publication_removes_temporary_and_previous_success(self):
        app = self.write_product(self.product_info("iphoneos"))
        receipt = self.root / "receipt.json"
        receipt.write_text('{"earlier_inspection": "passed"}\n', encoding="utf-8")
        out, err = io.StringIO(), io.StringIO()
        with patch.object(Path, "replace", side_effect=OSError("controlled publication failure")), \
                redirect_stdout(out), redirect_stderr(err):
            code = submission.main([
                "--toolchain-pin", str(self.xcode_file), "--sdk-pin", str(self.sdk_file),
                "inspect", "--sdk", "iphoneos", "--app", str(app), "--output", str(receipt),
            ])
        self.assertEqual(code, 2)
        self.assertEqual(out.getvalue(), "")
        self.assertFalse(receipt.exists())
        self.assertEqual(list(self.root.glob(".submission-sdk-*.tmp")), [])

    def test_receipt_paths_cannot_remove_pins_product_or_ci_environment(self):
        app = self.write_product(self.product_info("iphoneos"))
        environment = self.root / "github-env"
        environment.write_text("EXISTING=value\n", encoding="utf-8")
        protected = (self.xcode_file, self.sdk_file, app / "Info.plist")
        for path in protected:
            with self.subTest(path=path.name):
                before = path.read_bytes()
                result = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app, "--output", path)
                self.assertEqual(result.returncode, 2)
                self.assertIn("separate", result.stderr)
                self.assertEqual(path.read_bytes(), before)
        result = self.run_cli("verify", "--github-env", environment, "--output", environment)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(environment.read_text(), "EXISTING=value\n")
        alias = self.root / "directory-alias"
        alias.symlink_to(self.root, target_is_directory=True)
        result = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app,
                              "--output", alias / "xcode.json")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(self.xcode_file.read_text()), self.xcode)

    def test_linked_or_directory_receipts_are_rejected_without_changing_the_target(self):
        app = self.write_product(self.product_info("iphoneos"))
        target = self.root / "retained.json"
        target.write_text("retained source bytes\n", encoding="utf-8")
        symlink = self.root / "symlink.json"
        symlink.symlink_to(target)
        hardlink = self.root / "hardlink.json"
        hardlink.hardlink_to(target)
        directory = self.root / "directory.json"
        directory.mkdir()
        for path in (symlink, hardlink, directory):
            with self.subTest(path=path.name):
                result = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app, "--output", path)
                self.assertEqual(result.returncode, 2)
                self.assertIn("unshared regular file", result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertTrue(path.exists())
                self.assertEqual(target.read_text(), "retained source bytes\n")

    def test_actual_cli_rejects_product_traversal_before_removing_or_creating_receipts(self):
        app = self.write_product(self.product_info("iphoneos"))
        outside = self.root / "outside"
        outside.mkdir()
        escape = app / "escape"
        escape.symlink_to(outside, target_is_directory=True)
        app_alias = self.root / "Alias.app"
        app_alias.symlink_to(app, target_is_directory=True)
        parent_alias = self.root / "parent-alias"
        parent_alias.symlink_to(self.root, target_is_directory=True)
        inputs = {path: path.read_bytes() for path in
                  (self.xcode_file, self.sdk_file, app / "Info.plist")}
        retained = outside / "retained.json"
        sentinel = b"synthetic retained source bytes\n"
        product_paths = (app, parent_alias / app_alias.name)
        output_roots = (app, app_alias, parent_alias / app.name, parent_alias / app_alias.name)
        for product in product_paths:
            for output_root in output_roots:
                for existing in (True, False):
                    with self.subTest(product=product, output_root=output_root, existing=existing):
                        if existing:
                            retained.write_bytes(sentinel)
                        else:
                            retained.unlink(missing_ok=True)
                        result = self.run_cli("inspect", "--sdk", "iphoneos", "--app", product,
                                              "--output", output_root / "escape" / retained.name)
                        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                        self.assertIn("separate", result.stderr)
                        self.assertEqual(result.stdout, "")
                        self.assertEqual(retained.exists(), existing)
                        if existing:
                            self.assertEqual(retained.read_bytes(), sentinel)
                        for path, before in inputs.items():
                            self.assertEqual(path.read_bytes(), before)
                        for link, destination in ((escape, outside), (app_alias, app),
                                                  (parent_alias, self.root)):
                            self.assertTrue(link.is_symlink())
                            self.assertEqual(link.resolve(), destination.resolve())

    def test_actual_cli_allows_outside_parent_alias_and_preserves_failure_recovery(self):
        valid = self.product_info("iphoneos")
        app = self.write_product(valid)
        parent_alias = self.root / "parent-alias"
        parent_alias.symlink_to(self.root, target_is_directory=True)
        (self.root / "outside").mkdir()
        targets = {
            "safe-absolute": self.root / "evidence",
            "safe-relative": Path("outside") / ".." / "evidence",
            "safe-nested": Path("safe-relative"),
        }
        for name, target in targets.items():
            (self.root / name).symlink_to(target, target_is_directory=True)
        parents = (parent_alias / "evidence", *(self.root / name for name in targets))
        for parent in parents:
            with self.subTest(parent=parent):
                receipt = parent / "receipt.json"
                arguments = ("inspect", "--sdk", "iphoneos", "--app", app, "--output", receipt)
                first = self.run_cli(*arguments)
                self.assertEqual(first.returncode, 0, first.stderr)
                self.assertEqual(json.loads(receipt.read_text()), json.loads(first.stdout))

                self.write_product({**valid, "DTSDKName": "iphoneos18.5"})
                failed = self.run_cli(*arguments)
                self.assertEqual(failed.returncode, 2, failed.stdout + failed.stderr)
                self.assertIn("DTSDKName", failed.stderr)
                self.assertEqual(failed.stdout, "")
                self.assertFalse(receipt.exists())

                self.write_product(valid)
                recovered = self.run_cli(*arguments)
                self.assertEqual(recovered.returncode, 0, recovered.stderr)
                self.assertEqual(json.loads(receipt.read_text()), json.loads(first.stdout))
                self.assertEqual(list(receipt.parent.glob(".submission-sdk-*.tmp")), [])
        self.assertTrue(parent_alias.is_symlink())
        for name, target in targets.items():
            self.assertEqual((self.root / name).readlink(), target)

    def test_actual_cli_rejects_protected_traversal_inside_directory_link_targets(self):
        app = self.write_product(self.product_info("iphoneos"))
        outside = self.root / "outside"
        outside.mkdir()
        escape = app / "escape"
        escape.symlink_to(outside, target_is_directory=True)
        targets = {
            "hidden-absolute": escape,
            "hidden-relative": Path(app.name) / escape.name,
            "hidden-nested": Path("hidden-relative"),
            "hidden-dotdot-absolute": app / ".." / outside.name,
            "hidden-dotdot-relative": Path(app.name) / ".." / outside.name,
            "hidden-dotdot-nested": Path("hidden-dotdot-relative"),
        }
        for name, target in targets.items():
            (self.root / name).symlink_to(target, target_is_directory=True)
        inputs = {path: path.read_bytes() for path in
                  (self.xcode_file, self.sdk_file, app / "Info.plist")}
        retained = outside / "retained.json"
        sentinel = b"synthetic retained source bytes\n"
        for name in targets:
            for existing in (True, False):
                with self.subTest(target=name, existing=existing):
                    if existing:
                        retained.write_bytes(sentinel)
                    else:
                        retained.unlink(missing_ok=True)
                    result = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app,
                                          "--output", self.root / name / retained.name)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertIn("separate", result.stderr)
                    self.assertEqual(result.stdout, "")
                    self.assertEqual(retained.exists(), existing)
                    if existing:
                        self.assertEqual(retained.read_bytes(), sentinel)
                    for path, before in inputs.items():
                        self.assertEqual(path.read_bytes(), before)
                    self.assertEqual(escape.readlink(), outside)
                    for link, target in targets.items():
                        self.assertEqual((self.root / link).readlink(), target)

    def test_actual_cli_rejects_non_directory_or_missing_prefix_before_dotdot(self):
        app = self.write_product(self.product_info("iphoneos"))
        outside = self.root / "outside"
        outside.mkdir()
        ordinary = outside / "ordinary-file"
        ordinary.write_bytes(b"synthetic ordinary input\n")
        missing = outside / "missing-directory"
        retained = outside / "receipt.json"
        sentinel = b"synthetic retained receipt\n"
        for prefix in (ordinary, missing):
            targets = {
                prefix.name + "-absolute": prefix / "..",
                prefix.name + "-relative": Path(outside.name) / prefix.name / "..",
                prefix.name + "-nested": Path(prefix.name + "-relative"),
            }
            for name, target in targets.items():
                (self.root / name).symlink_to(target, target_is_directory=True)
            parents = (prefix / "..", *(self.root / name for name in targets))
            for parent in parents:
                for valid in (True, False):
                    info = self.product_info("iphoneos")
                    if not valid:
                        info["DTSDKName"] = "iphoneos18.5"
                    self.write_product(info)
                    inputs = {path: path.read_bytes() for path in
                              (self.xcode_file, self.sdk_file, app / "Info.plist", ordinary)}
                    for existing in (True, False):
                        with self.subTest(prefix=prefix.name, parent=parent, valid=valid, existing=existing):
                            if existing:
                                retained.write_bytes(sentinel)
                            else:
                                retained.unlink(missing_ok=True)
                            result = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app,
                                                  "--output", parent / retained.name)
                            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                            self.assertEqual(result.stdout, "")
                            self.assertNotIn("Traceback", result.stderr)
                            self.assertEqual(retained.exists(), existing)
                            if existing:
                                self.assertEqual(retained.read_bytes(), sentinel)
                            self.assertFalse(missing.exists())
                            for path, before in inputs.items():
                                self.assertEqual(path.read_bytes(), before)
                            for name, target in targets.items():
                                self.assertEqual((self.root / name).readlink(), target)

    def test_actual_cli_creates_missing_tail_directories_with_safe_aliases(self):
        valid = self.product_info("iphoneos")
        app = self.write_product(valid)
        for route in ("direct", "absolute", "relative", "nested"):
            with self.subTest(route=route):
                destination = self.root / (route + "-new") / "evidence"
                self.assertFalse(destination.exists())
                parent = destination
                if route != "direct":
                    target = destination if route == "absolute" else destination.relative_to(self.root)
                    alias = self.root / (route + "-alias")
                    alias.symlink_to(target, target_is_directory=True)
                    parent = alias
                    if route == "nested":
                        parent = self.root / "nested-outer-alias"
                        parent.symlink_to(alias.name, target_is_directory=True)
                receipt = parent / "receipt.json"
                arguments = ("inspect", "--sdk", "iphoneos", "--app", app, "--output", receipt)
                first = self.run_cli(*arguments)
                self.assertEqual(first.returncode, 0, first.stderr)
                self.assertEqual(json.loads(receipt.read_text()), json.loads(first.stdout))
                self.assertEqual(receipt.resolve(), destination.resolve() / receipt.name)
                self.write_product({**valid, "DTSDKName": "iphoneos18.5"})
                failed = self.run_cli(*arguments)
                self.assertEqual(failed.returncode, 2, failed.stdout + failed.stderr)
                self.assertFalse(receipt.exists())
                self.write_product(valid)
                recovered = self.run_cli(*arguments)
                self.assertEqual(recovered.returncode, 0, recovered.stderr)
                self.assertEqual(json.loads(receipt.read_text()), json.loads(recovered.stdout))
                self.assertEqual(list(destination.glob(".submission-sdk-*.tmp")), [])

    def test_actual_cli_resolution_failures_leave_inputs_and_outside_receipt_intact(self):
        app = self.write_product(self.product_info("iphoneos"))
        outside = self.root / "outside"
        outside.mkdir()
        retained = outside / "retained.json"
        retained.write_bytes(b"synthetic retained source bytes\n")
        ordinary = outside / "ordinary-file"
        ordinary.write_bytes(b"synthetic ordinary file\n")
        targets = {"loop": Path("loop"), "cycle-first": Path("cycle-second"),
                   "cycle-second": outside / "cycle-first"}
        for name, target in targets.items():
            (outside / name).symlink_to(target, target_is_directory=True)
        inputs = {path: path.read_bytes() for path in
                  (self.xcode_file, self.sdk_file, app / "Info.plist", retained, ordinary)}
        paths = (outside / "loop" / ".." / retained.name,
                 outside / "cycle-first" / ".." / retained.name, ordinary / retained.name)
        for path in paths:
            with self.subTest(path=path):
                result = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app, "--output", path)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("Submission SDK check failed:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)
                self.assertEqual(result.stdout, "")
                for source, before in inputs.items():
                    self.assertEqual(source.read_bytes(), before)
                for name, target in targets.items():
                    self.assertEqual((outside / name).readlink(), target)

    def test_receipt_distinguishes_case_aliases_from_separate_directories(self):
        app = self.write_product(self.product_info("iphoneos"))
        alternate = self.root / app.name.swapcase()
        if alternate.exists():
            # Exercise the real filesystem's case alias on native volumes.
            self.assertTrue(alternate.samefile(app))
            outside = self.root / "outside"
            outside.mkdir()
            (app / "escape").symlink_to(outside, target_is_directory=True)
            indirect = self.root / "indirect"
            indirect.symlink_to(alternate / "escape", target_is_directory=True)
            retained = outside / "retained.json"
            retained.write_bytes(b"synthetic retained bytes\n")
            for parent in (alternate / "escape", indirect):
                with self.subTest(parent=parent):
                    with patch.object(Path, "unlink") as invalidate:
                        with self.assertRaisesRegex(submission.toolchain.SetupError, "separate"):
                            submission.prepare_receipt(parent / retained.name, (app,))
                        invalidate.assert_not_called()
                    self.assertEqual(retained.read_bytes(), b"synthetic retained bytes\n")
            print("SDK receipt case-alias regression passed: physical alias; both protected paths rejected", flush=True)
        else:
            # A case-sensitive volume must not reject a genuinely separate path.
            alternate.mkdir()
            self.assertFalse(alternate.samefile(app))
            receipt = alternate / "receipt.json"
            result = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app, "--output", receipt)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(receipt.read_text()), json.loads(result.stdout))
            print("SDK receipt case-alias regression passed: distinct directory; ordinary receipt accepted", flush=True)

    def test_actual_cli_protected_input_loops_clear_success_and_repair_retry(self):
        app = self.write_product(self.product_info("iphoneos"))
        receipt = self.root / "receipt.json"
        arguments = ("inspect", "--sdk", "iphoneos", "--app", app, "--output", receipt)
        for protected in (self.xcode_file, self.sdk_file, app):
            with self.subTest(protected=protected.name):
                good = self.run_cli(*arguments)
                self.assertEqual(good.returncode, 0, good.stderr)
                self.assertEqual(json.loads(receipt.read_text()), json.loads(good.stdout))
                retained = protected.with_name(protected.name + ".retained")
                protected.rename(retained)
                protected.symlink_to(protected.name, target_is_directory=retained.is_dir())
                try:
                    failed = self.run_cli(*arguments)
                    self.assertEqual(failed.returncode, 2, failed.stderr)
                    self.assertEqual(failed.stdout, "")
                    self.assertIn("input contains a link loop", failed.stderr)
                    self.assertNotIn("Traceback", failed.stderr)
                    self.assertFalse(receipt.exists())
                    self.assertTrue(protected.is_symlink())
                    self.assertEqual(protected.readlink(), Path(protected.name))
                    self.assertTrue(retained.exists())
                    # The same failure with no old receipt creates no output.
                    absent = self.run_cli(*arguments)
                    self.assertEqual(absent.returncode, 2, absent.stderr)
                    self.assertEqual(absent.stdout, "")
                    self.assertFalse(receipt.exists())
                finally:
                    protected.unlink()
                    retained.rename(protected)
                recovered = self.run_cli(*arguments)
                self.assertEqual(recovered.returncode, 0, recovered.stderr)
                self.assertEqual(json.loads(receipt.read_text()), json.loads(recovered.stdout))
                self.assertEqual(list(receipt.parent.glob(".submission-sdk-*.tmp")), [])

    def test_protected_input_loops_still_check_later_boundaries_and_unsafe_receipts(self):
        app = self.write_product(self.product_info("iphoneos"))
        cycle = self.root / "cycle"
        cycle.symlink_to(cycle.name)
        retained = self.root / "retained.json"
        retained.write_bytes(b"synthetic ordinary receipt\n")
        linked = self.root / "linked.json"
        linked.symlink_to(retained.name)
        shared = self.root / "shared.json"
        shared.hardlink_to(retained)
        directory = self.root / "directory"
        directory.mkdir()
        for output in (self.sdk_file, app / "Info.plist", linked, shared, directory):
            with self.subTest(output=output.name):
                before = {path: path.read_bytes() for path in (self.sdk_file, app / "Info.plist", retained)}
                with patch.object(Path, "unlink") as invalidate:
                    with self.assertRaises(submission.toolchain.SetupError):
                        submission.prepare_receipt(output, (cycle, self.sdk_file, app))
                    invalidate.assert_not_called()
                for path, contents in before.items():
                    self.assertEqual(path.read_bytes(), contents)
                self.assertTrue(linked.is_symlink())
                self.assertEqual(retained.stat().st_nlink, 2)
                self.assertTrue(directory.is_dir())
        with patch.object(Path, "unlink") as invalidate:
            with self.assertRaises((submission.toolchain.SetupError, OSError)):
                submission.prepare_receipt(cycle / "receipt.json", (cycle, app))
            invalidate.assert_not_called()

    def test_protected_input_error_variants_defer_only_recognized_path_failures(self):
        app = self.write_product(self.product_info("iphoneos"))
        receipt = self.root / "receipt.json"
        original_resolve = Path.resolve
        for error, reason in ((OSError(errno.ELOOP, "SYNTHETIC_LOOP_DETAIL"), "link loop"),
                              (RuntimeError("Symlink loop from synthetic input"), "link loop"),
                              (NotADirectoryError(errno.ENOTDIR, "SYNTHETIC_PREFIX_DETAIL"), "non-directory prefix"),
                              (OSError(errno.ENAMETOOLONG, "SYNTHETIC_NAME_DETAIL"), "overlong name"),
                              (PermissionError(errno.EACCES, "SYNTHETIC_ACCESS_DETAIL"), None),
                              (OSError(errno.EIO, "SYNTHETIC_IO_DETAIL"), None),
                              (RuntimeError("SYNTHETIC_UNEXPECTED_RESOLUTION_ERROR"), None)):
            with self.subTest(error=type(error).__name__, message=str(error)):
                receipt.write_bytes(b"synthetic earlier success\n")

                def resolution(path, *args, **kwargs):
                    if path == self.sdk_file:
                        raise error
                    return original_resolve(path, *args, **kwargs)

                with patch.object(Path, "resolve", resolution):
                    if reason is None:
                        expected = type(error) if isinstance(error, OSError) else submission.toolchain.SetupError
                        with self.assertRaises(expected):
                            submission.prepare_receipt(receipt, (self.sdk_file, app))
                        self.assertEqual(receipt.read_bytes(), b"synthetic earlier success\n")
                    else:
                        with self.assertRaisesRegex(submission.toolchain.SetupError, reason):
                            submission.prepare_receipt(receipt, (self.sdk_file, app))
                        self.assertFalse(receipt.exists())
        # A later unrelated access error must stop cleanup after any recognized
        # unusable input, including a loop or invalid path components.
        cycle = self.root / "cycle"
        cycle.symlink_to(cycle.name)
        prefix = self.root / "ordinary-file"
        prefix.write_bytes(b"synthetic input prefix\n")

        def denied(path, *args, **kwargs):
            if path == app:
                raise PermissionError(errno.EACCES, "SYNTHETIC_ACCESS_DETAIL")
            return original_resolve(path, *args, **kwargs)

        for unusable in (cycle, prefix / "child", self.root / ("n" * 4096)):
            with self.subTest(unusable=unusable.name[:20]):
                receipt.write_bytes(b"synthetic earlier success\n")
                with patch.object(Path, "resolve", denied):
                    with self.assertRaises(PermissionError):
                        submission.prepare_receipt(receipt, (unusable, app))
                self.assertEqual(receipt.read_bytes(), b"synthetic earlier success\n")

        # A runtime whose non-strict resolve leaves a loop for stat has the
        # same outcome; a permission error at that stage remains conservative.
        original_stat = Path.stat
        for code in (errno.ELOOP, errno.ENOTDIR, errno.ENAMETOOLONG, errno.EACCES, errno.EIO):
            with self.subTest(stat_errno=code):
                receipt.write_bytes(b"synthetic earlier success\n")

                def inspection(path, *args, **kwargs):
                    if path == self.sdk_file:
                        raise OSError(code, "SYNTHETIC_STAT_DETAIL")
                    return original_stat(path, *args, **kwargs)

                with patch.object(Path, "resolve", lambda path, *a, **k: path.absolute()), patch.object(Path, "stat", inspection):
                    if code in (errno.ELOOP, errno.ENOTDIR, errno.ENAMETOOLONG):
                        with self.assertRaisesRegex(submission.toolchain.SetupError, "input contains"):
                            submission.prepare_receipt(receipt, (self.sdk_file, app))
                        self.assertFalse(receipt.exists())
                    else:
                        with self.assertRaises(OSError):
                            submission.prepare_receipt(receipt, (self.sdk_file, app))
                        self.assertEqual(receipt.read_bytes(), b"synthetic earlier success\n")

    def test_actual_cli_invalid_input_components_clear_success_and_repair_retry(self):
        app = self.write_product(self.product_info("iphoneos"))
        receipt = self.root / "receipt.json"
        prefix = self.root / "ordinary-file"
        prefix.write_bytes(b"synthetic input prefix\n")
        invalid_paths = ((prefix / "child", errno.ENOTDIR, "non-directory prefix"),
                         (self.root / ("n" * 4096), errno.ENAMETOOLONG, "overlong name"))
        for invalid, code, reason in invalid_paths:
            with self.assertRaises(OSError) as observed:
                invalid.stat()
            self.assertEqual(observed.exception.errno, code)
            for selected in ("sdk", "app"):
                with self.subTest(error=code, selected=selected):
                    def invoke(use_invalid):
                        return subprocess.run([
                            sys.executable, str(SCRIPT), "--toolchain-pin", str(self.xcode_file),
                            "--sdk-pin", str(invalid if use_invalid and selected == "sdk" else self.sdk_file),
                            "inspect", "--sdk", "iphoneos",
                            "--app", str(invalid if use_invalid and selected == "app" else app),
                            "--output", str(receipt),
                        ], capture_output=True, text=True, timeout=10, check=False)

                    good = invoke(False)
                    self.assertEqual(good.returncode, 0, good.stderr)
                    self.assertEqual(json.loads(receipt.read_text()), json.loads(good.stdout))
                    for attempt in range(2):
                        failed = invoke(True)
                        self.assertEqual(failed.returncode, 2, failed.stderr)
                        self.assertEqual(failed.stdout, "")
                        self.assertIn(reason, failed.stderr)
                        self.assertNotIn("Traceback", failed.stderr)
                        self.assertFalse(receipt.exists())
                        self.assertEqual(prefix.read_bytes(), b"synthetic input prefix\n")
                    recovered = invoke(False)
                    self.assertEqual(recovered.returncode, 0, recovered.stderr)
                    self.assertEqual(json.loads(receipt.read_text()), json.loads(recovered.stdout))
                    self.assertEqual(list(receipt.parent.glob(".submission-sdk-*.tmp")), [])

    def test_invalid_input_components_preserve_unsafe_outputs_and_input_prefix_identity(self):
        app = self.write_product(self.product_info("iphoneos"))
        prefix = self.root / "ordinary-file"
        prefix.write_bytes(b"synthetic input prefix\n")
        alias = self.root / "prefix-alias"
        alias.symlink_to(prefix.name)
        for invalid in (prefix / "child", alias / "child"):
            with self.subTest(invalid=invalid.parent.name):
                with patch.object(Path, "unlink") as invalidate:
                    with self.assertRaises(submission.toolchain.SetupError):
                        submission.prepare_receipt(prefix, (invalid, app))
                    invalidate.assert_not_called()
                self.assertEqual(prefix.read_bytes(), b"synthetic input prefix\n")
                self.assertTrue(alias.is_symlink())

        retained = self.root / "retained.json"
        retained.write_bytes(b"synthetic ordinary receipt\n")
        linked = self.root / "linked.json"
        linked.symlink_to(retained.name)
        shared = self.root / "shared.json"
        shared.hardlink_to(retained)
        directory = self.root / "directory"
        directory.mkdir()
        for invalid in (prefix / "child", self.root / ("n" * 4096)):
            for output in (self.sdk_file, app / "Info.plist", linked, shared, directory):
                with self.subTest(invalid=invalid.name[:20], output=output.name):
                    before = {p: p.read_bytes() for p in (prefix, self.sdk_file, app / "Info.plist", retained)}
                    with patch.object(Path, "unlink") as invalidate:
                        with self.assertRaises(submission.toolchain.SetupError):
                            submission.prepare_receipt(output, (invalid, self.sdk_file, app))
                        invalidate.assert_not_called()
                    for path, contents in before.items():
                        self.assertEqual(path.read_bytes(), contents)
                    self.assertTrue(linked.is_symlink())
                    self.assertEqual(retained.stat().st_nlink, 2)
                    self.assertTrue(directory.is_dir())

        # Unexpected prefix inspection errors must not justify invalidation.
        receipt = self.root / "ordinary-receipt.json"
        receipt.write_bytes(b"synthetic earlier success\n")
        original_lstat = Path.lstat
        for code in (errno.EACCES, errno.EIO):
            def inspection(path, *args, **kwargs):
                if path == prefix:
                    raise OSError(code, "SYNTHETIC_PREFIX_INSPECTION_DETAIL")
                return original_lstat(path, *args, **kwargs)

            with patch.object(Path, "lstat", inspection):
                with self.assertRaises(OSError):
                    submission.prepare_receipt(receipt, (prefix / "child", app))
            self.assertEqual(receipt.read_bytes(), b"synthetic earlier success\n")

    def test_actual_cli_preserves_input_prefixes_hidden_in_link_targets(self):
        app = self.write_product(self.product_info("iphoneos"))
        prefix = self.root / "ordinary-input-prefix"
        paths = []
        absolute = self.root / "absolute-link"
        absolute.symlink_to(prefix / "nested")
        paths.append(absolute / "sdk.json")
        relative = self.root / "relative-link"
        relative.symlink_to(Path(prefix.name) / "nested")
        paths.append(relative / "sdk.json")
        nested = self.root / "nested-link"
        nested.symlink_to(relative.name)
        paths.append(nested / "sdk.json")
        dotdot = self.root / "dotdot-link"
        dotdot.symlink_to(Path(prefix.name) / ".." / "outside")
        paths.append(dotdot / "sdk.json")
        # Also inspect a target introduced by the final selected link itself.
        paths.append(absolute)

        for invalid in paths:
            with self.subTest(invalid=invalid.parent.name + "/" + invalid.name):
                good = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app, "--output", prefix)
                self.assertEqual(good.returncode, 0, good.stderr)
                before = prefix.read_bytes()
                identity = (prefix.stat().st_dev, prefix.stat().st_ino)
                failed = subprocess.run([
                    sys.executable, str(SCRIPT), "--toolchain-pin", str(self.xcode_file),
                    "--sdk-pin", str(invalid), "inspect", "--sdk", "iphoneos",
                    "--app", str(app), "--output", str(prefix),
                ], capture_output=True, text=True, timeout=10, check=False)
                self.assertEqual(failed.returncode, 2, failed.stderr)
                self.assertEqual(failed.stdout, "")
                self.assertNotIn("Traceback", failed.stderr)
                self.assertEqual(prefix.read_bytes(), before)
                self.assertEqual((prefix.stat().st_dev, prefix.stat().st_ino), identity)
                self.assertTrue(all(path.is_symlink() for path in (absolute, relative, nested, dotdot)))

        # A separate ordinary output can still be invalidated for each of the
        # same unusable inputs; preserving an input prefix is not a blanket
        # refusal to clear unrelated earlier success.
        receipt = self.root / "separate-receipt.json"
        for invalid in paths:
            with self.subTest(separate_output_input=invalid.parent.name + "/" + invalid.name):
                good = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app, "--output", receipt)
                self.assertEqual(good.returncode, 0, good.stderr)
                failed = subprocess.run([
                    sys.executable, str(SCRIPT), "--toolchain-pin", str(self.xcode_file),
                    "--sdk-pin", str(invalid), "inspect", "--sdk", "iphoneos",
                    "--app", str(app), "--output", str(receipt),
                ], capture_output=True, text=True, timeout=10, check=False)
                self.assertEqual(failed.returncode, 2, failed.stderr)
                self.assertEqual(failed.stdout, "")
                self.assertFalse(receipt.exists())
                self.assertTrue(prefix.is_file())

    def test_actual_cli_relative_input_loop_is_bounded_and_invalidates_safe_receipt(self):
        app = self.write_product(self.product_info("iphoneos"))
        receipt = self.root / "receipt.json"
        arguments = ("inspect", "--sdk", "iphoneos", "--app", app, "--output", receipt)
        good = self.run_cli(*arguments)
        self.assertEqual(good.returncode, 0, good.stderr)
        retained = self.sdk_file.with_suffix(".retained")
        self.sdk_file.rename(retained)
        directory = self.root / "existing-directory"
        directory.mkdir()
        self.sdk_file.symlink_to(Path(directory.name) / ".." / self.sdk_file.name)
        try:
            failed = self.run_cli(*arguments)
            self.assertEqual(failed.returncode, 2, failed.stderr)
            self.assertEqual(failed.stdout, "")
            self.assertIn("input contains a link loop", failed.stderr)
            self.assertFalse(receipt.exists())
            self.assertTrue(self.sdk_file.is_symlink())
            self.assertTrue(retained.is_file())
        finally:
            self.sdk_file.unlink()
            retained.rename(self.sdk_file)
        recovered = self.run_cli(*arguments)
        self.assertEqual(recovered.returncode, 0, recovered.stderr)
        self.assertEqual(json.loads(receipt.read_text()), json.loads(recovered.stdout))


    def test_duplicate_json_sdk_members_fail_at_every_object_depth(self):
        original = json.dumps(self.sdks)
        cases = [
            ("top-sdk-object", '{"sdkVersions": {"iphoneos": "18.5"},' + original[1:]),
            ("deployment-floor", '{"minimumOSVersion": "12.0",' + original[1:]),
            ("nested-device", original.replace('"iphoneos": "26.2"',
                                              '"iphoneos": "18.5", "iphoneos": "26.2"')),
            ("nested-simulator", original.replace('"iphonesimulator": "26.2"',
                                                 '"iphonesimulator": "18.5", "iphonesimulator": "26.2"')),
            ("nested-identical", original.replace('"iphoneos": "26.2"',
                                                 '"iphoneos": "26.2", "iphoneos": "26.2"')),
            ("nested-escaped", original.replace('"iphoneos": "26.2"',
                                               '"iphoneos": "18.5", "\\u0069phoneos": "26.2"')),
        ]
        for name, data in cases:
            with self.subTest(case=name):
                self.sdk_file.write_text(data, encoding="utf-8")
                with self.assertRaisesRegex(submission.toolchain.SetupError, "duplicate object key"):
                    submission.load_sdk_pin(self.sdk_file)
                self.assertEqual(self.sdk_file.read_text(encoding="utf-8"), data)
        self.sdk_file.write_text(original, encoding="utf-8")
        self.assertEqual(submission.load_sdk_pin(self.sdk_file), self.sdks)

    def test_non_json_sdk_constants_cannot_be_hidden_by_later_members(self):
        original = json.dumps(self.sdks)
        for token in ("NaN", "Infinity", "-Infinity"):
            for location, data in [
                ("deployment", '{"minimumOSVersion": ' + token + ',' + original[1:]),
                ("nested-sdk", original.replace('"iphoneos": "26.2"',
                                               '"iphoneos": ' + token + ', "iphoneos": "26.2"')),
            ]:
                with self.subTest(token=token, location=location):
                    self.sdk_file.write_text(data, encoding="utf-8")
                    with self.assertRaisesRegex(submission.toolchain.SetupError, "non-JSON number"):
                        submission.load_sdk_pin(self.sdk_file)
                    self.assertEqual(self.sdk_file.read_text(encoding="utf-8"), data)
        self.sdk_file.write_text(original, encoding="utf-8")
        self.assertEqual(submission.load_sdk_pin(self.sdk_file), self.sdks)

    def test_unique_escaped_sdk_keys_and_member_order_preserve_pin_values(self):
        data = json.dumps(self.sdks, sort_keys=True, indent=2).replace('"iphoneos"', '"\\u0069phoneos"')
        self.sdk_file.write_text(data, encoding="utf-8")
        self.assertEqual(submission.load_sdk_pin(self.sdk_file), self.sdks)

    def test_actual_cli_ambiguous_pins_invalidate_receipts_and_valid_retry_recovers(self):
        xcode = self.xcode_file.read_text(encoding="utf-8")
        sdks = self.sdk_file.read_text(encoding="utf-8")
        cases = [
            ("xcode-duplicate", self.xcode_file, '{"xcodeVersion": "99.9",' + xcode[1:]),
            ("sdk-duplicate", self.sdk_file, sdks.replace('"iphoneos": "26.2"',
                                                        '"iphoneos": "18.5", "iphoneos": "26.2"')),
            ("xcode-nonfinite", self.xcode_file, '{"xcodeVersion": NaN,' + xcode[1:]),
            ("sdk-nonfinite", self.sdk_file, '{"minimumOSVersion": Infinity,' + sdks[1:]),
        ]
        for sdk in submission.SDK_PLATFORMS:
            app = self.write_product(self.product_info(sdk))
            receipt = self.root / "evidence" / f"json-{sdk}.json"
            arguments = ("inspect", "--sdk", sdk, "--app", app, "--output", receipt)
            for name, pin, data in cases:
                with self.subTest(sdk=sdk, case=name):
                    accepted = self.run_cli(*arguments)
                    self.assertEqual(accepted.returncode, 0, accepted.stderr)
                    expected = json.loads(accepted.stdout)
                    self.assertEqual(json.loads(receipt.read_text(encoding="utf-8")), expected)
                    before = pin.read_bytes()
                    pin.write_text(data, encoding="utf-8")
                    try:
                        rejected = self.run_cli(*arguments)
                        self.assertEqual(rejected.returncode, 2, rejected.stdout + rejected.stderr)
                        self.assertIn("Cannot read", rejected.stderr)
                        self.assertIn("Restore", rejected.stderr)
                        self.assertEqual(rejected.stdout, "")
                        self.assertFalse(receipt.exists())
                        self.assertEqual(pin.read_text(encoding="utf-8"), data)
                    finally:
                        pin.write_bytes(before)
                    recovered = self.run_cli(*arguments)
                    self.assertEqual(recovered.returncode, 0, recovered.stderr)
                    self.assertEqual(json.loads(recovered.stdout), expected)
                    self.assertEqual(json.loads(receipt.read_text(encoding="utf-8")), expected)
                    self.assertEqual(list(receipt.parent.glob(".submission-sdk-*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
