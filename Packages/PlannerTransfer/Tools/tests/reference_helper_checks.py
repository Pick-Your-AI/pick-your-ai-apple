"""Supplement the verifier gates with helper and environment-mode coverage.

This module is imported by the existing test_verify_contract.py CI entrypoint.
All child inputs are disposable copies; these are Python-only execution checks.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PACKAGE = Path(__file__).resolve().parents[2]
CORPUS_FILES = (
    'conformance.json', 'catalog-conformance.json', 'quality-conformance.json',
    'cost-conformance.json', 'resource-estimate-conformance.json',
    'placement-conformance.json',
    'dependency-graph-conformance.json',
    'ruleset-conformance.json',
    'catalog-snapshot-conformance.json',
)
MODES = ('normal', 'flag', 'environment')
BOOTSTRAP = r'''
import json
from pathlib import Path
import runpy
import sys

root, options = Path(sys.argv[1]), json.loads(sys.argv[2])
sys.path.insert(0, str(root / 'Tools'))
from jsonschema import Draft202012Validator, FormatChecker

if 'missing_format' in options:
    FormatChecker.checkers.pop(options['missing_format'])
verifier = root / 'Tools/verify_contract.py'
original = Draft202012Validator.is_valid
calls = 0

def observed(self, *args, **kwargs):
    global calls
    direct = sys._getframe(1).f_code.co_filename == str(verifier)
    result = original(self, *args, **kwargs)
    if direct:
        calls += 1
        if calls == options.get('flip_call'):
            return not result
    return result

Draft202012Validator.is_valid = observed
try:
    if 'helper' in options:
        module = __import__(options['helper'])
        module.apply_vector({'field': 1}, options['case'])
    else:
        script = root / 'Tools' / options.get('script', 'verify_contract.py')
        sys.argv = [str(script)]
        runpy.run_path(str(script), run_name='__main__')
finally:
    (root / 'trace.json').write_text(json.dumps({'validator_calls': calls}))
'''


class ReferenceHelperChecks(unittest.TestCase):
    def run_copy(self, mode, mutate=None, **options):
        with tempfile.TemporaryDirectory(prefix='apple-reference-helpers-') as directory:
            root = Path(directory)
            (root / 'Tools').mkdir()
            for tool in (PACKAGE / 'Tools').glob('*.py'):
                shutil.copy2(tool, root / 'Tools' / tool.name)
            for path in ('Sources/PlannerTransfer/Resources', 'Tests/PlannerTransferTests/Fixtures'):
                shutil.copytree(PACKAGE / path, root / path)
            shutil.copy2(PACKAGE / 'source-manifest.json', root / 'source-manifest.json')
            if mutate:
                mutate(root)
            environment = dict(os.environ)
            environment.pop('PYTHONOPTIMIZE', None)
            environment.pop('PYTHONPATH', None)
            if mode == 'environment':
                environment['PYTHONOPTIMIZE'] = '1'
            result = subprocess.run(
                [sys.executable, '-B', *(['-O'] if mode == 'flag' else []), '-c',
                 BOOTSTRAP, str(root), json.dumps(options)],
                env=environment, capture_output=True, text=True, timeout=30,
            )
            trace = json.loads((root / 'trace.json').read_text())
            return result, trace

    def require_failure(self, result, diagnostic):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(diagnostic, result.stderr)
        self.assertNotIn('Verified ', result.stdout)

    def test_real_validator_checks_every_case_in_all_python_modes(self):
        fixtures = PACKAGE / 'Tests/PlannerTransferTests/Fixtures'
        count = sum(len(json.loads((fixtures / name).read_text())) for name in CORPUS_FILES)
        previous = None
        for mode in MODES:
            with self.subTest(mode=mode):
                result, trace = self.run_copy(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, '')
                self.assertEqual(result.stdout.count('Verified '), len(CORPUS_FILES))
                self.assertEqual(trace['validator_calls'], count)
                if previous is not None:
                    self.assertEqual(result.stdout, previous)
                previous = result.stdout

    def test_unknown_vector_operations_fail_in_all_python_modes(self):
        for mode in MODES:
            for module in ('catalog_vectors', 'quality_vectors', 'cost_vectors'):
                for path in ([], ['field']):
                    case = dict(operation='typo', path=path, json='2')
                    with self.subTest(mode=mode, module=module, path=path):
                        result, _ = self.run_copy(mode, helper=module, case=case)
                        self.require_failure(result, 'Unsupported ')
            case = {'mutations': [dict(operation='typo', path=['field'], json='2')]}
            with self.subTest(mode=mode, module='placement_vectors'):
                result, _ = self.run_copy(mode, helper='placement_vectors', case=case)
                self.require_failure(result, 'Unsupported ')

    def test_environment_optimization_preserves_every_verifier_phase(self):
        def corrupt(root):
            path = root / 'source-manifest.json'
            manifest = json.loads(path.read_text())
            manifest['files'][next(iter(manifest['files']))] = '0' * 64
            path.write_text(json.dumps(manifest))

        result, trace = self.run_copy('environment', corrupt)
        self.require_failure(result, 'Source hash mismatch:')
        self.assertEqual(trace['validator_calls'], 0)
        for format_name in ('date-time', 'uri'):
            with self.subTest(format=format_name):
                result, trace = self.run_copy('environment', missing_format=format_name)
                self.require_failure(result, 'enable canonical format checks')
                self.assertEqual(trace['validator_calls'], 0)
        fixtures = PACKAGE / 'Tests/PlannerTransferTests/Fixtures'
        preceding = 0
        for name in CORPUS_FILES:
            cases = json.loads((fixtures / name).read_text())
            with self.subTest(wrong_result=name):
                result, trace = self.run_copy('environment', flip_call=preceding + 1)
                self.require_failure(result, cases[0]['name'])
                self.assertEqual(trace['validator_calls'], preceding + 1)
            preceding += len(cases)
        for name in CORPUS_FILES[1:]:
            def stale(root):
                path = root / 'Tests/PlannerTransferTests/Fixtures' / name
                path.write_text(path.read_text() + '\n')

            with self.subTest(stale=name):
                result, _ = self.run_copy('environment', stale)
                self.require_failure(result, 'Stale ')

    def test_environment_optimization_preserves_generator_freshness(self):
        for name in ('catalog', 'quality', 'cost', 'placement', 'dependency-graph', 'ruleset', 'catalog-snapshot'):
            def stale(root):
                path = root / 'Tests/PlannerTransferTests/Fixtures' / (name + '-conformance.json')
                path.write_text(path.read_text() + '\n')

            with self.subTest(generator=name):
                result, _ = self.run_copy('environment', stale, script=name.replace('-', '_') + '_vectors.py')
                self.require_failure(result, 'vectors are stale')
                self.assertNotIn('deterministic generation verified', result.stdout)

    def test_catalog_snapshot_generator_rejects_duplicate_case_identity(self):
        def duplicate_kind(root):
            path = root / 'Tests/PlannerTransferTests/Fixtures/catalog.json'
            catalog = json.loads(path.read_text())
            catalog['items'].append(catalog['items'][0])
            path.write_text(json.dumps(catalog))

        for mode in MODES:
            with self.subTest(mode=mode):
                result, _ = self.run_copy(mode, duplicate_kind, script='catalog_snapshot_vectors.py')
                self.require_failure(result, 'Duplicate catalog snapshot vector names')
                self.assertNotIn('deterministic generation verified', result.stdout)
