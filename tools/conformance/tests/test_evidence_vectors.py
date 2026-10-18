"""Evidence exports must retain their real schema and byte-provenance failures."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location("evidence_export", HERE / "evidence_vectors.py")
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class EvidenceVectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.environ["CONTRACT_ROOT"]).resolve()

    def test_consumer_bytes_match_the_pinned_reference_and_all_named_states(self):
        result = exporter.bundle(self.root)
        encoded = (json.dumps(result, indent=2, sort_keys=True) + "\n").encode()
        for path in exporter.OUTPUTS:
            self.assertEqual(path.read_bytes(), encoded, path)
        cases = result["cases"]
        self.assertEqual(len(cases), 37)
        self.assertEqual(sum(case["valid"] for case in cases), 28)
        matrix = [case for case in cases if case["id"].startswith("evidence/outcome/")]
        self.assertEqual({(case["outcome"], case["severity"]) for case in matrix},
                         {(outcome, severity) for outcome in ("pass", "fail", "unknown", "skipped")
                          for severity in ("error", "warning", "info")})
        self.assertTrue(all(case["observed"] == ["absent", "explicitNull", "literalUnknown"] for case in matrix))
        self.assertTrue(all(case["expected"] == ["absent", "explicitNull", "literalUnknown"] for case in matrix))

    def test_either_consumer_drift_is_rejected_and_restored_bytes_recover(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = tuple(Path(directory) / str(index) / path.name for index, path in enumerate(exporter.OUTPUTS))
            for source, target in zip(exporter.OUTPUTS, paths):
                target.parent.mkdir(parents=True)
                shutil.copyfile(source, target)
            arguments = ["evidence_vectors.py", "--contract-root", str(self.root), "--check"]
            with patch.object(exporter, "OUTPUTS", paths), patch.object(sys, "argv", arguments):
                exporter.main()
                for path in paths:
                    original = path.read_bytes()
                    path.write_bytes(original.replace(b"Observed: explicit null", b"Observed: pass", 1))
                    with self.assertRaises(SystemExit) as rejected:
                        exporter.main()
                    self.assertEqual(rejected.exception.code, 1)
                    path.write_bytes(original)
                    exporter.main()

    def test_source_change_during_copy_is_rejected_before_any_case_is_accepted(self):
        copyfile = shutil.copyfile

        def corrupted_snapshot(source, target, *args, **kwargs):
            result = copyfile(source, target, *args, **kwargs)
            if Path(target).name == "evaluation-report.json":
                Path(target).write_bytes(Path(target).read_bytes() + b" ")
            return result

        with patch.object(exporter.shutil, "copyfile", side_effect=corrupted_snapshot):
            with self.assertRaisesRegex(ValueError, "hash mismatch: examples/evaluation-report.json"):
                exporter.bundle(self.root)
        self.assertEqual(len(exporter.bundle(self.root)["cases"]), 37)

    def test_reference_rejects_a_falsely_accepted_incompatible_payload(self):
        schema_results = exporter.reference.schema_results

        def incompatible_case(root, cases):
            changed = copy.deepcopy(cases)
            self.assertTrue(changed[0]["valid"])
            changed[0]["payload"]["schema_version"] = "2.0.0"
            return schema_results(root, changed)

        with patch.object(exporter.reference, "schema_results", side_effect=incompatible_case):
            with self.assertRaisesRegex(ValueError, "differs from the frozen schema: evidence/outcome/pass/error"):
                exporter.bundle(self.root)


if __name__ == "__main__":
    unittest.main()
