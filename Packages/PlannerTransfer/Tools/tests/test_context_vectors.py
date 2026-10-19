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


if __name__ == "__main__":
    unittest.main()
