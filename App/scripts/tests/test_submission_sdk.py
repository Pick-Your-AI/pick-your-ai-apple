import copy
from contextlib import redirect_stderr, redirect_stdout
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
