"""The context oracle must admit all completed copies before importing any."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


TOOL = Path(__file__).resolve().parents[1] / "context_vectors.py"
SPEC = importlib.util.spec_from_file_location("context_vectors_copy_guard", TOOL)
VECTORS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VECTORS)


class ContextReferenceCopyChecks(unittest.TestCase):
    def test_later_copy_corruption_cannot_reach_import_and_valid_retry_recovers(self):
        original_write = Path.write_bytes
        original_import = VECTORS.importlib.import_module
        previous_modules = {name: value for name, value in sys.modules.items()
                            if name == "tests" or name.startswith("tests.")}
        previous_bytecode = sys.dont_write_bytecode
        corruptions = []

        def corrupt_earlier_copy(path, raw):
            result = original_write(path, raw)
            if (path.name == "t0_answer_state_prototype.py"
                    and path.parent.parent.name.startswith("apple-context-reference-")):
                earlier = path.parent / "context_budget_binding_prototype.py"
                original_write(earlier, earlier.read_bytes()
                               + b'\nraise RuntimeError("late_copy_probe_executed")\n')
                corruptions.append(earlier.name)
            return result

        with patch.object(Path, "write_bytes", corrupt_earlier_copy):
            with patch.object(VECTORS.importlib, "import_module", wraps=original_import) as imports:
                with self.assertRaisesRegex(ValueError, "^copied context reference differs$"):
                    with VECTORS.reference():
                        self.fail("A changed completed copy reached the oracle consumer")
                self.assertEqual(imports.call_count, 0)
        self.assertEqual(corruptions, ["context_budget_binding_prototype.py"])
        self.assertEqual({name: value for name, value in sys.modules.items()
                          if name == "tests" or name.startswith("tests.")}, previous_modules)
        self.assertEqual(sys.dont_write_bytecode, previous_bytecode)

        with VECTORS.reference() as (binding, reader, budget, copies):
            self.assertEqual(set(copies), VECTORS.PINNED_PATHS)
            for module in (binding, reader, budget):
                self.assertEqual(Path(module.__file__).read_bytes(),
                                 copies["tests/" + Path(module.__file__).name])
            record = binding.ContextRecord(copies["tests/fixtures/context-budget-binding.json"],
                                           copies["tests/fixtures/context-budget-answers.json"])
            result = record.evaluate(record.scope, enabled=True, evidence_eligible=True)
            self.assertEqual(result.outcome.value, "fail")
            self.assertEqual(result.reason, "normalized_context_screen")
        self.assertEqual({name: value for name, value in sys.modules.items()
                          if name == "tests" or name.startswith("tests.")}, previous_modules)
        self.assertEqual(sys.dont_write_bytecode, previous_bytecode)

    def test_aliased_temporary_root_keeps_containment_and_valid_recovery(self):
        original_temporary = VECTORS.tempfile.TemporaryDirectory
        original_import = VECTORS.importlib.import_module
        previous_modules = {name: value for name, value in sys.modules.items()
                            if name == "tests" or name.startswith("tests.")}
        previous_bytecode = sys.dont_write_bytecode
        with original_temporary(prefix="context-root-alias-") as directory:
            root = Path(directory)
            physical = root / "physical"
            physical.mkdir()
            alias = root / "alias"
            alias.symlink_to(physical, target_is_directory=True)
            outside = root / "outside.py"
            outside.write_text("# synthetic module-location control\n")
            allocations = []

            def through_alias(*args, **kwargs):
                kwargs["dir"] = str(alias)
                temporary = original_temporary(*args, **kwargs)
                spelled = Path(temporary.name)
                self.assertNotEqual(spelled, spelled.resolve())
                allocations.append(spelled)
                return temporary

            def misplace_module(name, *args, **kwargs):
                module = original_import(name, *args, **kwargs)
                if name == "tests.context_budget_prototype":
                    module.__file__ = str(outside)
                return module

            with patch.object(VECTORS.tempfile, "TemporaryDirectory", side_effect=through_alias):
                with patch.object(VECTORS.importlib, "import_module", side_effect=misplace_module):
                    with self.assertRaisesRegex(ValueError, "^context oracle imported outside verified copy$"):
                        with VECTORS.reference():
                            self.fail("An outside module location was accepted through the alias")
                self.assertEqual({name: value for name, value in sys.modules.items()
                                  if name == "tests" or name.startswith("tests.")}, previous_modules)
                self.assertEqual(sys.dont_write_bytecode, previous_bytecode)

                with VECTORS.reference() as (binding, reader, budget, copies):
                    for module in (binding, reader, budget):
                        path = Path(module.__file__).resolve()
                        self.assertTrue(path.is_relative_to(physical.resolve()))
                        self.assertEqual(path.read_bytes(), copies["tests/" + path.name])
                    record = binding.ContextRecord(copies["tests/fixtures/context-budget-binding.json"],
                                                   copies["tests/fixtures/context-budget-answers.json"])
                    result = record.evaluate(record.scope, enabled=True, evidence_eligible=True)
                    self.assertEqual(result.outcome.value, "fail")
                    self.assertEqual(result.reason, "normalized_context_screen")

            self.assertEqual(len(allocations), 2)
            self.assertEqual(list(physical.iterdir()), [])
            self.assertEqual(outside.read_text(), "# synthetic module-location control\n")
        self.assertEqual({name: value for name, value in sys.modules.items()
                          if name == "tests" or name.startswith("tests.")}, previous_modules)
        self.assertEqual(sys.dont_write_bytecode, previous_bytecode)


if __name__ == "__main__":
    unittest.main()
