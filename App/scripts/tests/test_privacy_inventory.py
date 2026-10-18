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


if __name__ == "__main__":
    unittest.main()
