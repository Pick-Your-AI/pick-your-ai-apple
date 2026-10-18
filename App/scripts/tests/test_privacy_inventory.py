"""Synthetic built-product filesystem controls; no Apple build or release claim."""

import contextlib
import errno
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "privacy_inventory.py"
SPEC = importlib.util.spec_from_file_location("privacy_inventory", SCRIPT)
inventory = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inventory)


class PrivacyInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.app = self.root / "Planner.app"
        self.app.mkdir()
        # The executable and unrelated ordinary resources are deliberately not
        # parsed or treated as privacy declarations by this bounded inventory.
        (self.app / "Planner").write_bytes(b"SYNTHETIC_EXECUTABLE_NOT_A_REAL_MACH_O")
        (self.app / "Info.plist").write_bytes(b"verified by the separate SDK metadata check")
        for relative, expected in inventory.EXPECTED.items():
            target = self.app / relative
            target.parent.mkdir(parents=True)
            target.write_bytes((inventory.ROOT / expected["source"]).read_bytes())
        self.output = self.root / "evidence" / "privacy.json"

    def tearDown(self):
        self.temporary.cleanup()

    def invoke(self):
        out, error = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(error):
            status = inventory.main(["--app", str(self.app), "--output", str(self.output)])
        return status, out.getvalue(), error.getvalue()

    def test_complete_real_source_bytes_are_bound_to_each_actual_product_location(self):
        status, out, error = self.invoke()
        self.assertEqual((status, error), (0, ""))
        result = json.loads(self.output.read_text())
        self.assertEqual(json.loads(out), result)
        self.assertEqual(result["manifestCount"], 2)
        self.assertEqual([row["path"] for row in result["manifests"]], sorted(inventory.EXPECTED))
        for row in result["manifests"]:
            actual = (self.app / row["path"]).read_bytes()
            self.assertEqual(row["sha256"], hashlib.sha256(actual).hexdigest())
            self.assertEqual(row["bytes"], len(actual))
            self.assertEqual(row["reason"], inventory.EXPECTED[row["path"]]["reason"])
        self.assertEqual(list(self.output.parent.glob(".privacy-inventory-*")), [])

    def test_source_only_or_missing_one_bundle_never_satisfies_built_product_inventory(self):
        for relative in inventory.EXPECTED:
            with self.subTest(relative=relative):
                target = self.app / relative
                original = target.read_bytes()
                target.unlink()
                with self.assertRaisesRegex(inventory.InventoryError, "missing"):
                    inventory.inspect_app(self.app)
                target.write_bytes(original)
        with self.assertRaises(inventory.InventoryError):
            inventory.inspect_app(inventory.ROOT)

    def test_changed_reason_format_or_swapped_bundle_rejects_and_retry_recovers(self):
        first, second = [self.app / key for key in inventory.EXPECTED]
        original = first.read_bytes()
        for changed in [original.replace(b"C617.1", b"CA92.1"), original + b"\n",
                        second.read_bytes(), b"invalid plist PRIVATE_MANIFEST_SENTINEL"]:
            with self.subTest(changed=changed[:20]):
                first.write_bytes(changed)
                status, out, error = self.invoke()
                self.assertEqual(status, 2)
                self.assertEqual(out, "")
                self.assertNotIn("PRIVATE_MANIFEST_SENTINEL", error)
                self.assertFalse(self.output.exists())
        first.write_bytes(original)
        self.assertEqual(self.invoke()[0], 0)

    def test_duplicate_root_or_additional_sdk_manifest_is_not_silently_ignored(self):
        source = next(iter(inventory.EXPECTED.values()))
        for relative in ["PrivacyInfo.xcprivacy", "UnexpectedSDK.framework/PrivacyInfo.xcprivacy",
                         "Nested/PlannerUI_PlannerUI.bundle/PrivacyInfo.xcprivacy"]:
            with self.subTest(relative=relative):
                target = self.app / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((inventory.ROOT / source["source"]).read_bytes())
                with self.assertRaisesRegex(inventory.InventoryError, "unreviewed"):
                    inventory.inspect_app(self.app)
                target.unlink()

    def test_source_pin_change_rejects_even_when_app_and_source_change_together(self):
        source_root = self.root / "source"
        for relative, expected in inventory.EXPECTED.items():
            target = source_root / expected["source"]
            target.parent.mkdir(parents=True, exist_ok=True)
            changed = (inventory.ROOT / expected["source"]).read_bytes() + b"\n"
            target.write_bytes(changed)
            (self.app / relative).write_bytes(changed)
        with self.assertRaisesRegex(inventory.InventoryError, "source declaration"):
            inventory.inspect_app(self.app, source_root)

    def test_symlinked_app_bundle_manifest_and_unrelated_link_reject_without_following(self):
        app_link = self.root / "Linked.app"
        app_link.symlink_to(self.app, target_is_directory=True)
        with self.assertRaises(OSError):
            inventory.inspect_app(app_link)
        target = self.app / next(iter(inventory.EXPECTED))
        saved = self.root / "saved-manifest"
        target.rename(saved)
        target.symlink_to(saved)
        with self.assertRaisesRegex(inventory.InventoryError, "link"):
            inventory.inspect_app(self.app)
        target.unlink()
        saved.rename(target)
        bundle = target.parent
        saved_bundle = self.root / "saved-bundle"
        bundle.rename(saved_bundle)
        bundle.symlink_to(saved_bundle, target_is_directory=True)
        with self.assertRaisesRegex(inventory.InventoryError, "link"):
            inventory.inspect_app(self.app)
        bundle.unlink()
        saved_bundle.rename(bundle)
        (self.app / "ignored-link").symlink_to(self.root / "missing-private-target")
        with self.assertRaisesRegex(inventory.InventoryError, "link"):
            inventory.inspect_app(self.app)

    def test_fifo_oversized_resource_and_bounded_traversal_fail_closed(self):
        target = self.app / next(iter(inventory.EXPECTED))
        original = target.read_bytes()
        target.unlink()
        os.mkfifo(target)
        with self.assertRaisesRegex(inventory.InventoryError, "non-regular"):
            inventory.inspect_app(self.app)
        target.unlink()
        with target.open("wb") as stream:
            stream.truncate(inventory.MAX_MANIFEST_BYTES + 1)
        with self.assertRaisesRegex(inventory.InventoryError, "bounded"):
            inventory.inspect_app(self.app)
        target.write_bytes(original)
        with mock.patch.object(inventory, "MAX_ENTRIES", 1):
            with self.assertRaisesRegex(inventory.InventoryError, "entry bound"):
                inventory.inspect_app(self.app)
        with mock.patch.object(inventory, "MAX_DEPTH", 0):
            with self.assertRaisesRegex(inventory.InventoryError, "directory-depth"):
                inventory.inspect_app(self.app)
        self.assertEqual(inventory.inspect_app(self.app)["manifestCount"], 2)

    def test_failed_retry_removes_stale_success_and_atomic_publication_failure_leaves_none(self):
        self.assertEqual(self.invoke()[0], 0)
        target = self.app / next(iter(inventory.EXPECTED))
        original = target.read_bytes()
        target.unlink()
        status, out, error = self.invoke()
        self.assertEqual((status, out), (2, ""))
        self.assertIn("missing", error)
        self.assertFalse(self.output.exists())
        target.write_bytes(original)
        with mock.patch.object(inventory.os, "replace", side_effect=OSError("PRIVATE_WRITE_SENTINEL")):
            status, out, error = self.invoke()
        self.assertEqual((status, out), (2, ""))
        self.assertNotIn("PRIVATE_WRITE_SENTINEL", error)
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.output.parent.glob(".privacy-inventory-*")), [])
        self.assertEqual(self.invoke()[0], 0)

    def test_real_cli_loop_and_missing_app_retries_remove_the_previous_success(self):
        loop = self.root / "Loop.app"
        loop.symlink_to(loop)
        parent_loop = self.root / "LoopDirectory"
        parent_loop.symlink_to(parent_loop, target_is_directory=True)
        for selected in [loop, parent_loop / "Planner.app", self.root / "Missing.app"]:
            with self.subTest(selected=selected.name):
                good = subprocess.run(
                    [sys.executable, str(SCRIPT), "--app", str(self.app), "--output", str(self.output)],
                    capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(good.returncode, 0, good.stderr)
                self.assertEqual(json.loads(self.output.read_text())["manifestCount"], 2)
                failed = subprocess.run(
                    [sys.executable, str(SCRIPT), "--app", str(selected), "--output", str(self.output)],
                    capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(failed.returncode, 2, failed.stderr)
                self.assertEqual(failed.stdout, "")
                self.assertNotIn("Traceback", failed.stderr)
                self.assertTrue(failed.stderr.startswith("Privacy inventory rejected: "))
                self.assertFalse(self.output.exists())

    def test_oserror_loop_resolution_clears_success_and_preserves_unsafe_output(self):
        self.assertEqual(self.invoke()[0], 0)
        original_resolve = Path.resolve

        def newer_python_loop(path, *args, **kwargs):
            if path == self.app:
                raise OSError(errno.ELOOP, "PRIVATE_LOOP_SENTINEL")
            return original_resolve(path, *args, **kwargs)

        with mock.patch.object(Path, "resolve", newer_python_loop):
            status, out, error = self.invoke()
        self.assertEqual((status, out), (2, ""))
        self.assertNotIn("PRIVATE_LOOP_SENTINEL", error)
        self.assertFalse(self.output.exists())

        target = self.app / next(iter(inventory.EXPECTED))
        before = target.read_bytes()
        self.output = target
        with mock.patch.object(Path, "resolve", newer_python_loop):
            self.assertEqual(self.invoke()[0], 2)
        self.assertEqual(target.read_bytes(), before)

    def test_product_or_linked_evidence_destinations_are_preserved_and_rejected(self):
        original = self.app / next(iter(inventory.EXPECTED))
        before = original.read_bytes()
        self.output = original
        self.assertEqual(self.invoke()[0], 2)
        self.assertEqual(original.read_bytes(), before)
        self.output = self.root / "evidence-link.json"
        other = self.root / "retained.json"
        other.write_text("PRIVATE_EXISTING_EVIDENCE")
        self.output.symlink_to(other)
        self.assertEqual(self.invoke()[0], 2)
        self.assertTrue(self.output.is_symlink())
        self.assertEqual(other.read_text(), "PRIVATE_EXISTING_EVIDENCE")
        outside = self.root / "outside"
        outside.mkdir()
        retained = outside / "retained.json"
        retained.write_text("KEEP_EXTERNAL_RECEIPT")
        (self.app / "escape").symlink_to(outside, target_is_directory=True)
        self.output = self.app / "escape" / "retained.json"
        self.assertEqual(self.invoke()[0], 2)
        self.assertEqual(retained.read_text(), "KEEP_EXTERNAL_RECEIPT")
        alias = self.root / "Alias.app"
        alias.symlink_to(self.app, target_is_directory=True)
        self.app = alias
        self.assertEqual(self.invoke()[0], 2)
        self.assertEqual(retained.read_text(), "KEEP_EXTERNAL_RECEIPT")

    def test_real_cli_parent_aliases_cannot_hide_a_product_escape_destination(self):
        # Reproduce system-ancestor aliases such as /var -> /private/var on
        # every host, without mocking pathlib or changing the existing test.
        parent_alias = self.root / "parent-alias"
        parent_alias.symlink_to(self.root.resolve(), target_is_directory=True)
        selected_alias = self.root / "Alias.app"
        selected_alias.symlink_to(self.app, target_is_directory=True)
        outside = self.root / "outside"
        outside.mkdir()
        retained = outside / "retained.json"
        (self.app / "escape").symlink_to(outside, target_is_directory=True)
        output = parent_alias / "Planner.app" / "escape" / "retained.json"
        manifest = self.app / next(iter(inventory.EXPECTED))
        original = manifest.read_bytes()
        for selected in [self.app.resolve(), parent_alias / "Alias.app"]:
            for existing in [True, False]:
                with self.subTest(selected=selected.name, existing=existing):
                    if existing:
                        retained.write_text("KEEP_EXTERNAL_RECEIPT")
                    else:
                        retained.unlink(missing_ok=True)
                    result = subprocess.run(
                        [sys.executable, str(SCRIPT), "--app", str(selected), "--output", str(output)],
                        capture_output=True, text=True, timeout=10,
                    )
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(result.stdout, "")
                    self.assertEqual(retained.exists(), existing)
                    if existing:
                        self.assertEqual(retained.read_text(), "KEEP_EXTERNAL_RECEIPT")
                    self.assertIn("evidence must be outside the inspected product", result.stderr)
                    self.assertNotIn("Traceback", result.stderr)
                    self.assertEqual(manifest.read_bytes(), original)
                    self.assertTrue((self.app / "escape").is_symlink())
                    self.assertTrue(selected_alias.is_symlink())

    def test_real_cli_outside_evidence_under_a_parent_alias_can_publish_and_retry(self):
        parent_alias = self.root / "parent-alias"
        parent_alias.symlink_to(self.root.resolve(), target_is_directory=True)
        output = parent_alias / "evidence" / "privacy.json"
        retained = self.root / "unrelated.json"
        retained.write_text("KEEP_UNRELATED_RECEIPT")
        command = [sys.executable, str(SCRIPT), "--app", str(parent_alias / "Planner.app"),
                   "--output", str(output)]
        good = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual((good.returncode, good.stderr), (0, ""))
        self.assertEqual(json.loads(output.read_text())["manifestCount"], 2)
        self.assertEqual(json.loads(good.stdout), json.loads(output.read_text()))
        manifest = self.app / next(iter(inventory.EXPECTED))
        original = manifest.read_bytes()
        manifest.unlink()
        failed = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(failed.returncode, 2, failed.stderr)
        self.assertEqual(failed.stdout, "")
        self.assertIn("missing", failed.stderr)
        self.assertFalse(output.exists())
        self.assertEqual(retained.read_text(), "KEEP_UNRELATED_RECEIPT")
        manifest.write_bytes(original)
        recovered = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual((recovered.returncode, recovered.stderr), (0, ""))
        self.assertEqual(json.loads(output.read_text())["manifestCount"], 2)
        self.assertEqual(list(output.parent.glob(".privacy-inventory-*")), [])

    def test_real_cli_hidden_link_target_ancestry_cannot_escape_the_product(self):
        outside = self.root / "outside"
        outside.mkdir()
        escape = self.app / "escape"
        escape.symlink_to(outside, target_is_directory=True)
        selected_alias = self.root / "Alias.app"
        selected_alias.symlink_to(self.app, target_is_directory=True)
        targets = {
            "hidden-absolute": escape,
            "hidden-relative": Path(self.app.name) / escape.name,
            "hidden-nested": Path("hidden-relative"),
            "hidden-dotdot-absolute": self.app / ".." / outside.name,
            "hidden-dotdot-relative": Path(self.app.name) / ".." / outside.name,
            "hidden-dotdot-nested": Path("hidden-dotdot-relative"),
        }
        for name, target in targets.items():
            (self.root / name).symlink_to(target, target_is_directory=True)
        inputs = {self.app / relative: (self.app / relative).read_bytes()
                  for relative in ["Planner", "Info.plist", *inventory.EXPECTED]}
        retained = outside / "retained.json"
        sentinel = b"OWNED_SYNTHETIC_RECEIPT\n"
        for selected in (self.app, selected_alias):
            for name in targets:
                for existing in (True, False):
                    with self.subTest(selected=selected.name, target=name, existing=existing):
                        if existing:
                            retained.write_bytes(sentinel)
                        else:
                            retained.unlink(missing_ok=True)
                        result = subprocess.run(
                            [sys.executable, str(SCRIPT), "--app", str(selected),
                             "--output", str(self.root / name / retained.name)],
                            capture_output=True, text=True, timeout=10,
                        )
                        self.assertEqual(result.returncode, 2, result.stderr)
                        self.assertEqual(result.stdout, "")
                        self.assertIn("evidence must be outside the inspected product", result.stderr)
                        self.assertNotIn("Traceback", result.stderr)
                        self.assertEqual(retained.exists(), existing)
                        if existing:
                            self.assertEqual(retained.read_bytes(), sentinel)
                        for path, before in inputs.items():
                            self.assertEqual(path.read_bytes(), before)
                        self.assertEqual(escape.readlink(), outside)
                        self.assertEqual(selected_alias.readlink(), self.app)
                        for link, target in targets.items():
                            self.assertEqual((self.root / link).readlink(), target)

    def test_real_cli_safe_link_targets_can_create_receipts_and_retry(self):
        outside = self.root / "outside"
        outside.mkdir()
        retained = self.root / "unrelated.json"
        retained.write_bytes(b"OWNED_UNRELATED_RECEIPT\n")
        manifest = self.app / next(iter(inventory.EXPECTED))
        original = manifest.read_bytes()
        for route in ("absolute", "relative", "nested", "dotdot-absolute",
                      "dotdot-relative", "dotdot-nested"):
            with self.subTest(route=route):
                destination = self.root / ("new-" + route) / "evidence"
                self.assertFalse(destination.exists())
                destination.parent.mkdir()
                target = destination.parent if route == "absolute" else destination.parent.relative_to(self.root)
                if route.startswith("dotdot"):
                    target = outside / ".." / destination.parent.relative_to(self.root)
                    if route != "dotdot-absolute":
                        target = target.relative_to(self.root)
                alias = self.root / ("safe-" + route)
                targets = {alias: target}
                if route.endswith("nested"):
                    inner = self.root / ("inner-" + route)
                    inner.symlink_to(target, target_is_directory=True)
                    targets[inner] = target
                    target = Path(inner.name)
                    targets[alias] = target
                alias.symlink_to(target, target_is_directory=True)
                output = alias / destination.name / "privacy.json"
                command = [sys.executable, str(SCRIPT), "--app", str(self.app),
                           "--output", str(output)]
                good = subprocess.run(command, capture_output=True, text=True, timeout=10)
                self.assertEqual((good.returncode, good.stderr), (0, ""))
                self.assertEqual(json.loads(output.read_text()), json.loads(good.stdout))
                self.assertEqual(json.loads(good.stdout)["manifestCount"], 2)
                self.assertEqual(output.resolve(), destination.resolve() / output.name)
                manifest.unlink()
                failed = subprocess.run(command, capture_output=True, text=True, timeout=10)
                self.assertEqual(failed.returncode, 2, failed.stderr)
                self.assertEqual(failed.stdout, "")
                self.assertIn("missing", failed.stderr)
                self.assertFalse(output.exists())
                manifest.write_bytes(original)
                recovered = subprocess.run(command, capture_output=True, text=True, timeout=10)
                self.assertEqual((recovered.returncode, recovered.stderr), (0, ""))
                self.assertEqual(json.loads(output.read_text()), json.loads(good.stdout))
                self.assertEqual(list(destination.glob(".privacy-inventory-*")), [])
                self.assertEqual(retained.read_bytes(), b"OWNED_UNRELATED_RECEIPT\n")
                for link, expected in targets.items():
                    self.assertEqual(link.readlink(), expected)

    def test_real_cli_invalid_output_traversal_preserves_inputs_and_existing_receipts(self):
        outside = self.root / "outside"
        outside.mkdir()
        retained = outside / "retained.json"
        ordinary = outside / "ordinary-file"
        ordinary.write_bytes(b"OWNED_ORDINARY_INPUT\n")
        missing = outside / "missing-directory"
        targets = {"loop": Path("loop"), "cycle-first": Path("cycle-second"),
                   "cycle-second": outside / "cycle-first"}
        parents = [outside / "loop" / "..", outside / "cycle-first" / ".."]
        for prefix in (ordinary, missing):
            parents.append(prefix / "..")
            for route in ("absolute", "relative", "nested"):
                name = prefix.name + "-" + route
                target = prefix / ".."
                if route == "relative":
                    target = Path(prefix.name) / ".."
                elif route == "nested":
                    target = Path(prefix.name + "-relative")
                targets[name] = target
                parents.append(outside / name)
        for name, target in targets.items():
            (outside / name).symlink_to(target, target_is_directory=True)
        inputs = {self.app / relative: (self.app / relative).read_bytes()
                  for relative in ["Planner", "Info.plist", *inventory.EXPECTED]}
        inputs[ordinary] = ordinary.read_bytes()
        sentinel = b"OWNED_SYNTHETIC_RECEIPT\n"
        for parent in parents:
            for existing in (True, False):
                with self.subTest(parent=parent, existing=existing):
                    # Keep every baseline regression independent if an older
                    # helper created this originally missing temporary prefix.
                    if missing.exists():
                        missing.rmdir()
                    self.assertFalse(missing.exists())
                    if existing:
                        retained.write_bytes(sentinel)
                    else:
                        retained.unlink(missing_ok=True)
                    result = subprocess.run(
                        [sys.executable, str(SCRIPT), "--app", str(self.app),
                         "--output", str(parent / retained.name)],
                        capture_output=True, text=True, timeout=10,
                    )
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertEqual(result.stdout, "")
                    self.assertNotIn("Traceback", result.stderr)
                    self.assertTrue(result.stderr.startswith("Privacy inventory rejected: "))
                    self.assertEqual(retained.exists(), existing)
                    if existing:
                        self.assertEqual(retained.read_bytes(), sentinel)
                    self.assertFalse(missing.exists())
                    for path, before in inputs.items():
                        self.assertEqual(path.read_bytes(), before)
                    for name, target in targets.items():
                        self.assertEqual((outside / name).readlink(), target)

    def test_controlled_directory_identity_cannot_remove_an_outside_receipt(self):
        # Model two spellings with one directory identity while retaining real
        # path traversal and receipt files. This is not a native case-fold result.
        alias = self.root / "controlled-product-alias"
        alias.mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        escape = alias / "escape"
        escape.symlink_to(outside, target_is_directory=True)
        indirect = self.root / "indirect"
        indirect.symlink_to(escape, target_is_directory=True)
        retained = outside / "retained.json"
        sentinel = b"OWNED_SYNTHETIC_RECEIPT\n"
        alias_spellings = {alias, alias.resolve()}
        product_identity = self.app.stat()
        original_lstat = Path.lstat

        def observed_lstat(path, *args, **kwargs):
            observed = original_lstat(path, *args, **kwargs)
            return product_identity if path in alias_spellings else observed

        for parent in (escape, indirect):
            with self.subTest(parent=parent.name):
                retained.write_bytes(sentinel)
                rejection = None
                with mock.patch.object(Path, "lstat", new=observed_lstat):
                    try:
                        inventory.prepare_output(parent / retained.name, self.app)
                    except inventory.InventoryError as error:
                        rejection = str(error)
                self.assertTrue(retained.exists(), "a protected directory identity lost its outside receipt")
                self.assertEqual(retained.read_bytes(), sentinel)
                self.assertEqual(rejection, "evidence must be outside the inspected product")
                self.assertEqual(escape.readlink(), outside)
                self.assertEqual(indirect.readlink(), escape)

    def test_real_filesystem_case_aliases_or_distinct_directories(self):
        alternate = self.root / self.app.name.swapcase()
        if alternate.exists():
            self.assertTrue(alternate.samefile(self.app))
            outside = self.root / "outside"
            outside.mkdir()
            escape = self.app / "escape"
            escape.symlink_to(outside, target_is_directory=True)
            indirect = self.root / "indirect"
            indirect.symlink_to(alternate / escape.name, target_is_directory=True)
            retained = outside / "retained.json"
            for parent in (alternate / escape.name, indirect):
                with self.subTest(parent=parent):
                    retained.write_bytes(b"OWNED_SYNTHETIC_RECEIPT\n")
                    result = subprocess.run(
                        [sys.executable, str(SCRIPT), "--app", str(self.app),
                         "--output", str(parent / retained.name)],
                        capture_output=True, text=True, timeout=10,
                    )
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("evidence must be outside the inspected product", result.stderr)
                    self.assertEqual(retained.read_bytes(), b"OWNED_SYNTHETIC_RECEIPT\n")
                    self.assertEqual(escape.readlink(), outside)
                    self.assertEqual(indirect.readlink(), alternate / escape.name)
        else:
            alternate.mkdir()
            self.assertFalse(alternate.samefile(self.app))
            output = alternate / "privacy.json"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--app", str(self.app), "--output", str(output)],
                capture_output=True, text=True, timeout=10,
            )
            self.assertEqual((result.returncode, result.stderr), (0, ""))
            self.assertEqual(json.loads(output.read_text()), json.loads(result.stdout))
            self.assertEqual(json.loads(result.stdout)["manifestCount"], 2)


if __name__ == "__main__":
    unittest.main()
