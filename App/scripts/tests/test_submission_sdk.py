import copy
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
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

    def run_cli(self, *arguments):
        return subprocess.run([
            sys.executable, str(SCRIPT), "--toolchain-pin", str(self.xcode_file),
            "--sdk-pin", str(self.sdk_file), *map(str, arguments),
        ], capture_output=True, text=True, timeout=10, check=False)

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
                self.assertEqual(receipt.resolve(), (destination / receipt.name).resolve())
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
        else:
            # A case-sensitive volume must not reject a genuinely separate path.
            alternate.mkdir()
            self.assertFalse(alternate.samefile(app))
            receipt = alternate / "receipt.json"
            result = self.run_cli("inspect", "--sdk", "iphoneos", "--app", app, "--output", receipt)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(receipt.read_text()), json.loads(result.stdout))


if __name__ == "__main__":
    unittest.main()
