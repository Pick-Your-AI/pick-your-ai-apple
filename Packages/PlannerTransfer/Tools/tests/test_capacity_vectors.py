"""Exercise copy admission, regular-file admission and original module-state recovery."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOL = Path(__file__).resolve().parents[1] / "capacity_vectors.py"
SPEC = importlib.util.spec_from_file_location("capacity_vectors_copy_guard", TOOL)
VECTORS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VECTORS)


def module_state():
    return {name: value for name, value in sys.modules.items()
            if name == "tests" or name.startswith("tests.")}


class CapacityReferenceCopyChecks(unittest.TestCase):
    def test_changed_or_outside_consumer_schema_rejects_before_import_and_recovers(self):
        before, bytecode = module_state(), sys.dont_write_bytecode
        original_import = VECTORS.importlib.import_module
        original = (VECTORS.RESOURCE_ROOT / "catalog-snapshot.schema.json").read_bytes()
        with tempfile.TemporaryDirectory(prefix="capacity-resource-admission-") as directory:
            root = Path(directory) / "resources"; root.mkdir()
            target = root / "catalog-snapshot.schema.json"
            target.write_bytes(original + b"\n")
            with patch.object(VECTORS, "RESOURCE_ROOT", root):
                with patch.object(VECTORS.importlib, "import_module", wraps=original_import) as imports:
                    with self.assertRaisesRegex(ValueError, "^capacity consumer resource identity mismatch$"):
                        with VECTORS.reference():
                            self.fail("Changed bundled schema reached import")
                    self.assertEqual(imports.call_count, 0)
                self.assertEqual(target.read_bytes(), original + b"\n")
                target.unlink(); os.mkfifo(target, 0o600)
                identity = target.stat()
                with patch.object(VECTORS.importlib, "import_module", wraps=original_import) as imports:
                    with self.assertRaisesRegex(ValueError, "^capacity reference input must be a regular file$"):
                        with VECTORS.reference():
                            self.fail("FIFO consumer schema reached import")
                    self.assertEqual(imports.call_count, 0)
                self.assertEqual(target.stat().st_ino, identity.st_ino)
                outside = Path(directory) / "outside.schema.json"; outside.write_bytes(original)
                target.unlink(); target.symlink_to(outside)
                with patch.object(VECTORS.importlib, "import_module", wraps=original_import) as imports:
                    with self.assertRaisesRegex(ValueError, "^capacity consumer resource leaves its pinned root$"):
                        with VECTORS.reference():
                            self.fail("Outside consumer schema reached import")
                    self.assertEqual(imports.call_count, 0)
                self.assertEqual(outside.read_bytes(), original)
                target.unlink(); target.write_bytes(original)
                self.assert_valid_retry()
        self.assertEqual(module_state(), before)
        self.assertEqual(sys.dont_write_bytecode, bytecode)

    def assert_valid_retry(self):
        before, bytecode = module_state(), sys.dont_write_bytecode
        with VECTORS.reference() as (reader, copies):
            self.assertEqual(set(copies), VECTORS.PINNED_PATHS)
            self.assertEqual(Path(reader.__file__).read_bytes(),
                             copies["tests/t0_answer_attribution_prototype.py"])
            raw = VECTORS.encode(VECTORS.document({
                "/value": VECTORS.provided("retained", assumption=False, source="preset:retry")}))
            index = reader.AttributedAnswerIndex(raw)
            answer = index.read("/value", VECTORS.SCHEMAS["text"])
            self.assertEqual(index.original_bytes, raw)
            self.assertEqual(answer.value, "retained")
            self.assertFalse(answer.assumption)
            self.assertEqual(answer.source, "preset:retry")
        self.assertEqual(module_state(), before)
        self.assertEqual(sys.dont_write_bytecode, bytecode)

    def test_later_copy_cannot_execute_an_earlier_changed_module_and_retry_recovers(self):
        before, bytecode = module_state(), sys.dont_write_bytecode
        original_write = Path.write_bytes
        original_import = VECTORS.importlib.import_module
        changes = []

        def corrupt_earlier(path, raw):
            result = original_write(path, raw)
            if (path.name == "t0_answer_state_prototype.py"
                    and path.parent.parent.name.startswith("apple-capacity-reference-")):
                earlier = path.parent / "t0_answer_attribution_prototype.py"
                original_write(earlier, earlier.read_bytes()
                               + b'\nraise RuntimeError("changed_capacity_oracle_executed")\n')
                changes.append(earlier.name)
            return result

        with patch.object(Path, "write_bytes", corrupt_earlier):
            with patch.object(VECTORS.importlib, "import_module", wraps=original_import) as imports:
                with self.assertRaisesRegex(ValueError, "^copied capacity reference differs$"):
                    with VECTORS.reference():
                        self.fail("Changed completed reference reached its consumer")
                self.assertEqual(imports.call_count, 0)
        self.assertEqual(changes, ["t0_answer_attribution_prototype.py"])
        self.assertEqual(module_state(), before)
        self.assertEqual(sys.dont_write_bytecode, bytecode)
        self.assert_valid_retry()

    def test_alias_root_retains_outside_module_rejection_cleanup_and_valid_retry(self):
        before, bytecode = module_state(), sys.dont_write_bytecode
        original_temporary = VECTORS.tempfile.TemporaryDirectory
        original_import = VECTORS.importlib.import_module
        with original_temporary(prefix="capacity-root-alias-") as directory:
            root = Path(directory)
            physical = root / "physical"; physical.mkdir()
            alias = root / "alias"; alias.symlink_to(physical, target_is_directory=True)
            outside = root / "outside.py"; outside.write_text("# retained control\n")
            allocations = []

            def through_alias(*args, **kwargs):
                kwargs["dir"] = str(alias)
                temporary = original_temporary(*args, **kwargs)
                path = Path(temporary.name)
                self.assertNotEqual(path, path.resolve())
                allocations.append(path)
                return temporary

            def misplace(name, *args, **kwargs):
                module = original_import(name, *args, **kwargs)
                if name == "tests.t0_answer_attribution_prototype":
                    module.__file__ = str(outside)
                return module

            with patch.object(VECTORS.tempfile, "TemporaryDirectory", side_effect=through_alias):
                with patch.object(VECTORS.importlib, "import_module", side_effect=misplace):
                    with self.assertRaisesRegex(ValueError, "^capacity oracle imported outside verified copy$"):
                        with VECTORS.reference():
                            self.fail("Outside module location accepted")
                self.assertEqual(module_state(), before)
                self.assertEqual(sys.dont_write_bytecode, bytecode)
                self.assert_valid_retry()
            self.assertEqual(len(allocations), 2)
            self.assertEqual(list(physical.iterdir()), [])
            self.assertEqual(outside.read_text(), "# retained control\n")
        self.assertEqual(module_state(), before)
        self.assertEqual(sys.dont_write_bytecode, bytecode)

    def test_fifo_and_changed_pins_reject_before_import_without_changing_inputs(self):
        original_import = VECTORS.importlib.import_module
        before, bytecode = module_state(), sys.dont_write_bytecode
        with tempfile.TemporaryDirectory(prefix="capacity-input-admission-") as directory:
            root = Path(directory) / "reference"
            shutil.copytree(VECTORS.REFERENCE, root)
            target = root / "tests/t0_answer_attribution_prototype.py"
            original = target.read_bytes()
            manifest = (root / "source-manifest.json").read_bytes()
            target.unlink(); os.mkfifo(target, 0o600)
            identity = target.stat()
            with patch.object(VECTORS, "REFERENCE", root):
                with patch.object(VECTORS.importlib, "import_module", wraps=original_import) as imports:
                    with self.assertRaisesRegex(ValueError, "^capacity reference input must be a regular file$"):
                        with VECTORS.reference():
                            self.fail("FIFO reached import")
                    self.assertEqual(imports.call_count, 0)
                after = target.stat()
                self.assertEqual((after.st_dev, after.st_ino, after.st_mode),
                                 (identity.st_dev, identity.st_ino, identity.st_mode))
                self.assertEqual((root / "source-manifest.json").read_bytes(), manifest)
                target.unlink(); target.write_bytes(original + b"\n# changed input\n")
                with patch.object(VECTORS.importlib, "import_module", wraps=original_import) as imports:
                    with self.assertRaisesRegex(ValueError, "^capacity reference identity mismatch$"):
                        with VECTORS.reference():
                            self.fail("Changed pin reached import")
                    self.assertEqual(imports.call_count, 0)
                self.assertEqual(target.read_bytes(), original + b"\n# changed input\n")
                target.write_bytes(original)
                self.assert_valid_retry()
        self.assertEqual(module_state(), before)
        self.assertEqual(sys.dont_write_bytecode, bytecode)


if __name__ == "__main__":
    unittest.main()
