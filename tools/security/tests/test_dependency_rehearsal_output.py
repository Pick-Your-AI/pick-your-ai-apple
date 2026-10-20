"""Actual-CLI output ownership and failed-attempt regressions for the drill."""
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SECURITY = Path(__file__).resolve().parents[1]
CASES = [
    "no-dependency-change",
    "vulnerable-development-dependency",
    "unapproved-license",
    "unresolved-license",
    "urgent-update-recovery",
    "patched-version-with-missing-review",
]


class DependencyRehearsalOutputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dependency-rehearsal-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.checkout = self.directory / "copied-checkout"
        self.security = self.checkout / "tools/security"
        self.security.mkdir(parents=True)
        self.outside = self.directory / "outside"
        self.outside.mkdir()
        self.script = self.security / "rehearse_dependency_review.py"
        self.guard = self.security / "check_dependency_review.py"
        self.script_bytes = (SECURITY / self.script.name).read_bytes()
        self.guard_bytes = (SECURITY / self.guard.name).read_bytes()
        self.script.write_bytes(self.script_bytes)
        self.guard.write_bytes(self.guard_bytes)

    def run_cli(self, output=None):
        command = [sys.executable, str(self.script)]
        if output is not None:
            command.extend(["--output", str(output)])
        return subprocess.run(
            command, cwd=self.directory,
            env={"PYTHONUTF8": "1", "PYTHONDONTWRITEBYTECODE": "1"},
            capture_output=True, text=True, timeout=20, check=False,
        )

    def assert_success(self, result, output=None):
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(output.read_text() if output is not None else result.stdout)
        self.assertIs(report["passed"], True)
        self.assertEqual([row["case"] for row in report["cases"]], CASES)
        self.assertEqual([row["actual_exit"] for row in report["cases"]], [0, 1, 1, 1, 0, 1])
        self.assertTrue(all(row["passed"] for row in report["cases"]))
        self.assertEqual(self.script.read_bytes(), self.script_bytes)
        self.assertEqual(self.guard.read_bytes(), self.guard_bytes)
        return report

    def test_stdout_and_external_receipt_preserve_the_six_case_results(self):
        printed = self.assert_success(self.run_cli())
        output = self.outside / "receipt.json"
        output.write_text('{"synthetic_prior_result":true}\n')
        written = self.assert_success(self.run_cli(output), output)
        self.assertEqual(written, printed)
        self.assertEqual(list(self.outside.iterdir()), [output])

    def test_checkout_destinations_cannot_overwrite_sources_or_create_receipts(self):
        sentinel = self.checkout / "synthetic-sentinel.txt"
        sentinel.write_text("preserve synthetic source\n")
        for output in (self.script, self.guard, sentinel, self.checkout / "new-receipt.json"):
            with self.subTest(output=output.name):
                before = output.read_bytes() if output.exists() else None
                result = self.run_cli(output)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn("outside the source checkout", result.stderr)
                self.assertEqual(output.read_bytes() if output.exists() else None, before)
                self.assertEqual(self.script.read_bytes(), self.script_bytes)
                self.assertEqual(self.guard.read_bytes(), self.guard_bytes)

    def test_final_links_preserve_their_targets_and_link_identity(self):
        for kind in ("source-symlink", "outside-symlink", "dangling-symlink",
                     "source-hardlink", "outside-hardlink"):
            with self.subTest(kind=kind):
                output = self.outside / kind
                target = self.guard if kind.startswith("source") else self.outside / (kind + "-target")
                if not kind.startswith("source") and kind != "dangling-symlink":
                    target.write_text("preserve synthetic target\n")
                if kind.endswith("symlink"):
                    output.symlink_to(target)
                else:
                    os.link(target, output)
                before = target.read_bytes() if target.exists() else None
                inode = output.lstat().st_ino
                result = self.run_cli(output)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn("regular file with one link", result.stderr)
                self.assertEqual(output.lstat().st_ino, inode)
                self.assertEqual(target.read_bytes() if target.exists() else None, before)
                self.assertEqual(self.script.read_bytes(), self.script_bytes)
                self.assertEqual(self.guard.read_bytes(), self.guard_bytes)
                output.unlink()

    def test_safe_external_parent_aliases_and_relative_outputs_are_supported(self):
        absolute = self.directory / "absolute-alias"
        relative = self.directory / "relative-alias"
        nested = self.directory / "nested-alias"
        absolute.symlink_to(self.outside, target_is_directory=True)
        relative.symlink_to("outside", target_is_directory=True)
        nested.symlink_to("relative-alias", target_is_directory=True)
        for alias in (absolute, relative, nested):
            with self.subTest(alias=alias.name):
                output = alias.relative_to(self.directory) / "receipt.json"
                self.assert_success(self.run_cli(output), self.outside / "receipt.json")
                self.assertTrue(alias.is_symlink())
        protected = self.directory / "source-alias"
        protected.symlink_to(self.security, target_is_directory=True)
        result = self.run_cli(protected / self.guard.name)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.guard.read_bytes(), self.guard_bytes)

    def test_cli_case_variants_follow_observed_directory_identity(self):
        variant = self.directory / "CoPiEd-ChEcKoUt"
        aliases = variant.exists() and os.path.samestat(variant.stat(), self.checkout.stat())
        if not aliases:
            variant.mkdir()
        for relative in (Path("synthetic-receipt.json"),
                         Path("tools/security") / self.script.name):
            with self.subTest(destination=str(relative), same_directory=aliases):
                output = variant / relative
                output.parent.mkdir(parents=True, exist_ok=True)
                if not output.exists():
                    output.write_bytes(b'Preserve this only for a protected source directory.\n')
                contents = output.read_bytes()
                before = output.lstat()
                result = self.run_cli(output)
                if aliases:
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("outside the source checkout", result.stderr)
                    self.assertEqual(output.read_bytes(), contents)
                    after = output.lstat()
                    self.assertEqual((after.st_dev, after.st_ino, after.st_mode, after.st_nlink),
                                     (before.st_dev, before.st_ino, before.st_mode, before.st_nlink))
                    self.assertEqual(self.script.read_bytes(), self.script_bytes)
                    self.assertEqual(self.guard.read_bytes(), self.guard_bytes)
                else:
                    self.assert_success(result, output)
        print("Dependency output: observed " +
              ("same-directory case alias" if aliases else "distinct case directories"))

    def test_modeled_case_alias_cannot_replace_source_wrapper(self):
        # Model just one case-insensitive OS lookup on any host. The actual CLI
        # case above reports the host's observed behavior separately. Resolution,
        # main(), output publication and any guard children remain real.
        spec = importlib.util.spec_from_file_location("dependency_rehearsal_case_alias", self.script)
        rehearsal = importlib.util.module_from_spec(spec)
        with patch.object(sys, "dont_write_bytecode", True):
            spec.loader.exec_module(rehearsal)
        alias = self.directory / "CoPiEd-ChEcKoUt"
        alias_prefix, actual_prefix = str(alias), str(self.checkout)
        original_stat, original_lstat, original_open = os.stat, os.lstat, os.open

        def translated(value):
            if isinstance(value, int):
                return value
            spelling = os.fspath(value)
            if isinstance(spelling, str) and (
                    spelling == alias_prefix or spelling.startswith(alias_prefix + "/")):
                return actual_prefix + spelling[len(alias_prefix):]
            return value

        def lookup_stat(value, *args, **kwargs):
            return original_stat(translated(value), *args, **kwargs)

        def lookup_lstat(value, *args, **kwargs):
            return original_lstat(translated(value), *args, **kwargs)

        def lookup_open(value, *args, **kwargs):
            return original_open(translated(value), *args, **kwargs)

        output = alias / "tools/security" / self.script.name
        before = self.script.lstat()
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(os, "stat", lookup_stat), patch.object(os, "lstat", lookup_lstat), \
                patch.object(os, "open", lookup_open), \
                patch.object(sys, "argv", [str(self.script), "--output", str(output)]), \
                redirect_stdout(stdout), redirect_stderr(stderr):
            resolved = output.parent.resolve(strict=True)
            source = Path(rehearsal.__file__).resolve(strict=True).parents[2]
            self.assertFalse(resolved.is_relative_to(source))
            self.assertTrue(os.path.samestat(resolved.stat(), self.security.stat()))
            status = rehearsal.main()
        self.assertEqual(status, 1, stdout.getvalue() + stderr.getvalue())
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("outside the source checkout", stderr.getvalue())
        self.assertEqual(self.script.read_bytes(), self.script_bytes)
        self.assertEqual(self.guard.read_bytes(), self.guard_bytes)
        after = self.script.lstat()
        self.assertEqual((after.st_dev, after.st_ino, after.st_mode, after.st_nlink),
                         (before.st_dev, before.st_ino, before.st_mode, before.st_nlink))

    def test_untraversable_parents_and_loops_preserve_unrelated_receipts(self):
        sentinel = self.outside / "receipt.json"
        sentinel.write_text('{"synthetic_sentinel":"preserve"}\n')
        before = sentinel.read_bytes()
        ordinary = self.directory / "ordinary-file"
        ordinary.write_text("not a directory\n")
        alias_file = self.directory / "alias-file-parent"
        alias_file.symlink_to("ordinary-file/../outside", target_is_directory=True)
        alias_missing = self.directory / "alias-missing-parent"
        alias_missing.symlink_to("missing-parent/../outside", target_is_directory=True)
        loop_a = self.directory / "loop-a"
        loop_b = self.directory / "loop-b"
        loop_a.symlink_to(loop_b, target_is_directory=True)
        loop_b.symlink_to(loop_a, target_is_directory=True)
        outputs = [
            ordinary / "../outside/receipt.json",
            self.directory / "missing-parent/../outside/receipt.json",
            alias_file / "receipt.json", alias_missing / "receipt.json",
            loop_a / "receipt.json", self.directory / "missing-directory/receipt.json",
            self.outside,
        ]
        for output in outputs:
            with self.subTest(output=str(output.relative_to(self.directory))):
                result = self.run_cli(output)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(sentinel.read_bytes(), before)
                self.assertEqual(ordinary.read_text(), "not a directory\n")
                self.assertTrue(loop_a.is_symlink() and loop_b.is_symlink())
                self.assertEqual(self.script.read_bytes(), self.script_bytes)
                self.assertEqual(self.guard.read_bytes(), self.guard_bytes)

    def test_malformed_child_repeat_removes_old_success_and_allows_recovery(self):
        output = self.outside / "receipt.json"
        self.assert_success(self.run_cli(output), output)
        self.guard.write_text('print("synthetic malformed child output")\n')
        failure = self.run_cli(output)
        self.assertEqual(failure.returncode, 1)
        self.assertEqual(failure.stdout, "")
        self.assertFalse(output.exists())
        self.assertIn("no current result was produced", failure.stderr)
        self.assertEqual(list(self.outside.iterdir()), [])
        self.guard.write_bytes(self.guard_bytes)
        self.assert_success(self.run_cli(output), output)

    def test_timed_out_child_repeat_removes_old_success(self):
        output = self.outside / "receipt.json"
        self.assert_success(self.run_cli(output), output)
        self.guard.write_text("import time\ntime.sleep(30)\n")
        failure = self.run_cli(output)
        self.assertEqual(failure.returncode, 1)
        self.assertEqual(failure.stdout, "")
        self.assertFalse(output.exists())
        self.assertIn("no current result was produced", failure.stderr)
        self.assertEqual(list(self.outside.iterdir()), [])

    def test_unexpected_case_exit_produces_an_explicit_failed_receipt(self):
        output = self.outside / "receipt.json"
        self.assert_success(self.run_cli(output), output)
        self.guard.write_text('print(\'{"synthetic_child":true}\')\n')
        failure = self.run_cli(output)
        self.assertEqual(failure.returncode, 1)
        report = json.loads(output.read_text())
        self.assertIs(report["passed"], False)
        self.assertEqual([row["case"] for row in report["cases"]], CASES)
        self.assertEqual([row["actual_exit"] for row in report["cases"]], [0] * 6)
        self.assertEqual([row["passed"] for row in report["cases"]],
                         [True, False, False, False, True, False])
        self.assertEqual(list(self.outside.iterdir()), [output])


if __name__ == "__main__":
    unittest.main()
