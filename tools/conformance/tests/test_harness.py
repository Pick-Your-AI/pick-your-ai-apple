"""Harness regressions; use --contract-root's same frozen checkout via environment."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('conformance', HERE / 'run.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class HarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if 'CONTRACT_ROOT' not in os.environ:
            raise RuntimeError('Set CONTRACT_ROOT to the frozen research contracts/v1 directory')
        cls.root = Path(os.environ['CONTRACT_ROOT']).resolve()
        runner.verify_source(cls.root)
        cls.cases = runner.vectors(cls.root)

    def test_baseline_vectors_and_domain(self):
        results = runner.schema_results(self.root, self.cases) + runner.domain_results(self.root)
        self.assertTrue(all(r['passed'] for r in results), [r for r in results if not r['passed']])
        self.assertEqual(len({c['id'] for c in self.cases}), len(self.cases))

    def test_mutations_fail_specific_checks(self):
        results = {r['id']: r for r in runner.mutation_results(self.root, self.cases)}
        self.assertIn('build/missing/id', results['required-field']['failing_checks'])
        self.assertIn('decimal/precision', results['decimal']['failing_checks'])
        self.assertIn('rule/dimension-mismatch', results['rule']['failing_checks'])

    def test_manifest_tampering_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'IMPORT_MANIFEST.json').write_text('{}')
            with self.assertRaisesRegex(ValueError, 'manifest differs'):
                runner.verify_source(root)

    def test_payload_tampering_rejected_and_recovery(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'v1'
            shutil.copytree(self.root, root)
            path = root / 'examples/build.json'
            original = path.read_bytes()
            path.write_bytes(original + b' ')
            with self.assertRaisesRegex(ValueError, 'hash mismatch: examples/build.json'):
                runner.verify_source(root)
            path.write_bytes(original)
            runner.verify_source(root)

    def test_result_detects_inverted_expectation(self):
        case = copy.deepcopy(self.cases[0])
        case['valid'] = False
        self.assertFalse(runner.schema_results(self.root, [case])[0]['passed'])

    def test_bundle_is_deterministic(self):
        self.assertEqual(json.dumps(self.cases, sort_keys=True),
                         json.dumps(runner.vectors(self.root), sort_keys=True))


if __name__ == '__main__':
    unittest.main()
