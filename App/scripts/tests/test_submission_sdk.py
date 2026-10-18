import copy
import importlib.util
import json
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


if __name__ == "__main__":
    unittest.main()
