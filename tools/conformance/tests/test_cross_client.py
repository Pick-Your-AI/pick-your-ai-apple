"""Golden wire expectations must agree with the immutable canonical consumer."""
from copy import deepcopy
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import types
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cross_client as exporter


class CrossClientVectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contract = Path(os.environ['CONTRACT_ROOT']).resolve()
        cls.placement = Path(os.environ['PLACEMENT_ROOT']).resolve() if os.environ.get('PLACEMENT_ROOT') else None

    def test_all_consumer_bytes_match_all223_canonical_expectations(self):
        result = exporter.bundle(self.contract, self.placement)
        encoded = exporter.encoded_bundle(result)
        self.assertEqual(exporter.OUTPUT.read_bytes(), encoded)
        self.assertEqual(exporter.sha256(encoded), exporter.LOCK['wireFixture']['sha256'])
        self.assertEqual(len(result['cases']), 223)
        self.assertEqual(sum(case['valid'] for case in result['cases']), 141)
        inputs = exporter.checked_inputs(self.placement)
        cases = {case['id']: case for case in result['cases']}
        source = json.loads(inputs['evidence'])
        profile = exporter.evidence_cases(inputs['evidence'])
        self.assertEqual(len(source['cases']), 41)
        self.assertEqual(len(profile), 37)
        self.assertEqual([case['id'] for case in profile], exporter.LOCK['evidenceProfile']['caseIDs'])
        self.assertEqual(exporter.sha256(exporter.encoded_bundle(dict(source, cases=profile))),
                         exporter.LOCK['evidenceProfile']['sha256'])
        for case in profile:
            self.assertEqual(cases[case['id']]['payloadJSON'], case['payloadJSON'])
            self.assertEqual(cases[case['id']]['valid'], case['valid'])
        for case_id in exporter.LOCK['evidenceProfile']['excludedSourceCaseIDs']:
            self.assertNotIn(case_id, cases)
        placement = [case for case in result['cases'] if case['id'].startswith('placement/')]
        self.assertEqual(len(placement), 98)
        self.assertEqual({label: sum(case['disposition'] == label for case in placement)
                          for label in ['preserved', 'unresolved', 'unsupported-field', 'invalid-contract']},
                         {'preserved': 30, 'unresolved': 20, 'unsupported-field': 24, 'invalid-contract': 24})
        decimal = json.loads(cases['boundary/build/exact-decimal-string']['payloadJSON'])
        self.assertEqual(decimal['objectives']['monthly_budget_amount'], '9007199254740993.000000000001')

    def require_profile_rejections_before_consumption(self, variants, message):
        inputs = exporter.checked_inputs(self.placement)
        baseline = exporter.bundle(self.contract, self.placement)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, entry in exporter.LOCK['inputs'].items():
                path = root / entry['path']
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(inputs[name])
            evidence = root / exporter.LOCK['inputs']['evidence']['path']
            with patch.object(exporter, 'ROOT', root):
                for label, changed in variants.items():
                    with self.subTest(change=label):
                        contents = exporter.encoded_bundle(changed)
                        lock = deepcopy(exporter.LOCK)
                        lock['inputs']['evidence']['sha256'] = exporter.sha256(contents)
                        evidence.write_bytes(contents)
                        try:
                            with patch.object(exporter, 'LOCK', lock), \
                                    patch.object(exporter, 'load_placement_adapter') as load_adapter, \
                                    patch.object(exporter.reference, 'schema_results') as consume:
                                with self.assertRaisesRegex(ValueError, message):
                                    exporter.bundle(self.contract)
                                load_adapter.assert_not_called()
                                consume.assert_not_called()
                            self.assertEqual(evidence.read_bytes(), contents)
                        finally:
                            evidence.write_bytes(inputs['evidence'])
                self.assertEqual(exporter.bundle(self.contract), baseline)

    def test_evidence_profile_requires_exact_source_case_identity_order_and_count(self):
        source = json.loads(exporter.checked_inputs(self.placement)['evidence'])
        variants = {name: deepcopy(source) for name in [
            'missing-original', 'missing-excluded', 'duplicate-original', 'reordered-original',
            'reordered-excluded', 'renamed-excluded', 'unrecognized-extra',
        ]}
        variants['missing-original']['cases'].pop(0)
        variants['missing-excluded']['cases'].pop()
        variants['duplicate-original']['cases'][1] = deepcopy(source['cases'][0])
        variants['reordered-original']['cases'][0:2] = list(reversed(source['cases'][0:2]))
        variants['reordered-excluded']['cases'][-2:] = list(reversed(source['cases'][-2:]))
        variants['renamed-excluded']['cases'][-1]['id'] = 'evidence/unreviewed-explanation'
        variants['unrecognized-extra']['cases'].append(dict(source['cases'][-1], id='evidence/unreviewed-extra'))
        self.require_profile_rejections_before_consumption(
            variants, 'Pinned cross-client evidence profile identities differ')

    def test_evidence_profile_rejects_changed_original_bytes_even_with_a_new_source_pin(self):
        source = json.loads(exporter.checked_inputs(self.placement)['evidence'])
        variants = {name: deepcopy(source) for name in [
            'payload-bytes', 'expectation', 'row-metadata', 'source-metadata',
        ]}
        variants['payload-bytes']['cases'][0]['payloadJSON'] += ' '
        variants['expectation']['cases'][0]['valid'] = not source['cases'][0]['valid']
        variants['row-metadata']['cases'][0]['unreviewed'] = True
        variants['source-metadata']['unreviewed'] = True
        self.require_profile_rejections_before_consumption(
            variants, 'Pinned cross-client evidence profile bytes differ')

    def test_each_input_pin_rejects_drift_before_importing_the_placement_adapter(self):
        inputs = exporter.checked_inputs(self.placement)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = {}
            for name, entry in exporter.LOCK['inputs'].items():
                path = root / entry['path']
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(inputs[name])
                paths[name] = path
            with patch.object(exporter, 'ROOT', root):
                self.assertEqual(exporter.checked_inputs(), inputs)
                for name, path in paths.items():
                    path.write_bytes(inputs[name] + b' ')
                    with self.assertRaisesRegex(ValueError, 'Pinned cross-client input differs: ' + name):
                        exporter.checked_inputs()
                    path.write_bytes(inputs[name])
                self.assertEqual(exporter.checked_inputs(), inputs)

    def test_a_falsely_accepted_future_payload_fails_the_actual_reference(self):
        original = exporter.cases

        def bad_expectation(inputs, adapter):
            cases = deepcopy(original(inputs, adapter))
            value = json.loads(cases[0]['payloadJSON'])
            value['schema_version'] = '99.0.0'
            cases[0]['payloadJSON'] = json.dumps(value)
            return cases

        with patch.object(exporter, 'cases', side_effect=bad_expectation):
            with self.assertRaisesRegex(ValueError, 'differs from frozen schema: canonical/build'):
                exporter.bundle(self.contract, self.placement)
        self.assertEqual(len(exporter.bundle(self.contract, self.placement)['cases']), 223)

    def test_verified_placement_helper_ignores_ambient_module_and_restores_it(self):
        ambient = types.ModuleType('contract_checks')
        ambient.require = Mock(side_effect=AssertionError('Unverified helper executed'))
        original_cases = exporter.cases

        def check_adapter(inputs, adapter):
            self.assertIsNot(adapter.require, ambient.require)
            with self.assertRaisesRegex(ValueError, 'Unsupported placement vector operation: unknown'):
                adapter.apply_vector({'value': 1}, {
                    'mutations': [{'path': ['value'], 'operation': 'unknown', 'json': '2'}],
                })
            return original_cases(inputs, adapter)

        with patch.dict(sys.modules, {'contract_checks': ambient}), \
                patch.object(exporter, 'cases', side_effect=check_adapter):
            result = exporter.bundle(self.contract, self.placement)
            self.assertIs(sys.modules['contract_checks'], ambient)
            ambient.require.assert_not_called()
        self.assertEqual(len(result['cases']), 223)
        self.assertEqual(sum(case['valid'] for case in result['cases']), 141)

    def test_placement_helper_pin_drift_rejects_before_consumption_and_recovers(self):
        inputs = exporter.checked_inputs(self.placement)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, entry in exporter.LOCK['inputs'].items():
                path = root / entry['path']
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(inputs[name])
            helper = root / exporter.LOCK['inputs']['placementChecks']['path']
            original = helper.read_bytes()
            with patch.object(exporter, 'ROOT', root):
                baseline = exporter.bundle(self.contract)
                helper.write_bytes(original + b'\n')
                with patch.object(exporter.importlib.util, 'spec_from_file_location',
                                  wraps=exporter.importlib.util.spec_from_file_location) as load_adapter, \
                        patch.object(exporter.reference, 'schema_results',
                                     wraps=exporter.reference.schema_results) as consume:
                    with self.assertRaisesRegex(ValueError, 'Pinned cross-client input differs: placementChecks'):
                        exporter.bundle(self.contract)
                    load_adapter.assert_not_called()
                    consume.assert_not_called()
                self.assertEqual(helper.read_bytes(), original + b'\n')
                helper.write_bytes(original)
                self.assertEqual(exporter.bundle(self.contract), baseline)

    def test_placement_helper_module_state_recovers_after_adapter_import_failure(self):
        original_spec = exporter.importlib.util.spec_from_file_location
        ambient = types.ModuleType('contract_checks')
        ambient.require = Mock(side_effect=AssertionError('Unverified helper executed'))

        def failing_spec(name, location):
            spec = original_spec(name, location)
            if name == 'cross_client_placement':
                def fail_adapter(module):
                    self.assertIsNot(sys.modules['contract_checks'], ambient)
                    raise RuntimeError('Controlled adapter import failure')
                spec.loader.exec_module = fail_adapter
            return spec

        with patch.dict(sys.modules, {'contract_checks': ambient}):
            with patch.object(exporter.importlib.util, 'spec_from_file_location', side_effect=failing_spec):
                with self.assertRaisesRegex(RuntimeError, 'Controlled adapter import failure'):
                    exporter.bundle(self.contract, self.placement)
            self.assertIs(sys.modules['contract_checks'], ambient)
            ambient.require.assert_not_called()
            self.assertEqual(len(exporter.bundle(self.contract, self.placement)['cases']), 223)
            self.assertIs(sys.modules['contract_checks'], ambient)

    def test_frozen_input_change_during_snapshot_copy_fails_before_reference_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'v1'
            shutil.copytree(self.contract, root)
            source = root / 'examples/build.json'
            original = source.read_bytes()
            baseline = exporter.bundle(root, self.placement)
            original_inputs = exporter.checked_inputs

            def change_after_verification(placement_root=None):
                result = original_inputs(placement_root)
                source.write_bytes(original + b' ')
                return result

            try:
                with patch.object(exporter, 'checked_inputs', side_effect=change_after_verification), \
                        patch.object(exporter.importlib.util, 'spec_from_file_location',
                                     wraps=exporter.importlib.util.spec_from_file_location) as load_adapter, \
                        patch.object(exporter.reference, 'schema_results',
                                     wraps=exporter.reference.schema_results) as consume:
                    with self.assertRaisesRegex(ValueError, 'Frozen import hash mismatch: examples/build.json'):
                        exporter.bundle(root, self.placement)
                    load_adapter.assert_not_called()
                    consume.assert_not_called()
                self.assertEqual(source.read_bytes(), original + b' ')
            finally:
                source.write_bytes(original)
            exporter.reference.verify_source(root)
            self.assertEqual(exporter.bundle(root, self.placement), baseline)


    def test_source_redirect_during_copy_is_rejected_before_consumption_and_recovers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'v1'
            shutil.copytree(self.contract, root)
            source = root / 'examples/build.json'
            original = source.read_bytes()
            outside = Path(directory) / 'outside-build.json'
            outside.write_bytes(original)
            baseline = exporter.bundle(root, self.placement)
            original_inputs = exporter.checked_inputs

            def redirect_after_verification(placement_root=None):
                result = original_inputs(placement_root)
                source.unlink()
                source.symlink_to(outside)
                return result

            try:
                with patch.object(exporter, 'checked_inputs', side_effect=redirect_after_verification), \
                        patch.object(exporter.importlib.util, 'spec_from_file_location',
                                     wraps=exporter.importlib.util.spec_from_file_location) as load_adapter, \
                        patch.object(exporter.reference, 'schema_results',
                                     wraps=exporter.reference.schema_results) as consume:
                    with self.assertRaisesRegex(ValueError, 'Frozen import hash mismatch: examples/build.json'):
                        exporter.bundle(root, self.placement)
                    load_adapter.assert_not_called()
                    consume.assert_not_called()
                self.assertTrue(source.is_symlink())
                self.assertEqual(outside.read_bytes(), original)
            finally:
                source.unlink()
                source.write_bytes(original)
            exporter.reference.verify_source(root)
            self.assertEqual(exporter.bundle(root, self.placement), baseline)


    def test_manifest_fifo_replacement_rejects_before_adapter_or_reference_and_recovers(self):
        probe = textwrap.dedent(r'''
            import json, os, stat, sys
            from pathlib import Path
            from unittest.mock import patch
            sys.path.insert(0, sys.argv[1])
            import cross_client as exporter
            root = Path(sys.argv[2])
            placement = Path(sys.argv[3]) if sys.argv[3] else None
            manifest = root / 'IMPORT_MANIFEST.json'
            original_copy = exporter.reference.copy_verified_source
            replacements = []

            def replace_after_verified_copy(*args, **kwargs):
                result = original_copy(*args, **kwargs)
                manifest.unlink()
                os.mkfifo(manifest, 0o600)
                replacements.append(manifest.stat())
                print(json.dumps({'event': 'fifo-replacement'}), flush=True)
                return result

            with patch.object(exporter.reference, 'copy_verified_source',
                              side_effect=replace_after_verified_copy), \
                    patch.object(exporter.importlib.util, 'spec_from_file_location',
                                 wraps=exporter.importlib.util.spec_from_file_location) as load_adapter, \
                    patch.object(exporter.reference, 'schema_results',
                                 wraps=exporter.reference.schema_results) as consume:
                try:
                    exporter.bundle(root, placement)
                except ValueError as error:
                    if 'Conformance input must be a regular file:' not in str(error):
                        raise
                else:
                    raise AssertionError('Replaced manifest was accepted')
                load_adapter.assert_not_called()
                consume.assert_not_called()
            if len(replacements) != 1:
                raise AssertionError('Expected exactly one manifest replacement')
            after = manifest.stat()
            before = replacements[0]
            if not stat.S_ISFIFO(after.st_mode) or \
                    (after.st_dev, after.st_ino, after.st_mode) != \
                    (before.st_dev, before.st_ino, before.st_mode):
                raise AssertionError('FIFO identity changed during rejection')
            print(json.dumps({'event': 'rejected-before-consumption'}), flush=True)
        ''')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'v1'
            shutil.copytree(self.contract, root)
            manifest = root / 'IMPORT_MANIFEST.json'
            original = manifest.read_bytes()
            baseline = exporter.bundle(root, self.placement)
            result = None
            timeout_output = ''
            try:
                try:
                    result = subprocess.run(
                        [sys.executable, '-B', '-u', '-c', probe, str(exporter.HERE),
                         str(root), str(self.placement) if self.placement else ''],
                        capture_output=True, text=True, timeout=3)
                except subprocess.TimeoutExpired as error:
                    output = error.stdout or b''
                    timeout_output = output.decode() if isinstance(output, bytes) else output
                self.assertTrue(stat.S_ISFIFO(manifest.stat().st_mode))
            finally:
                manifest.unlink()
                manifest.write_bytes(original)
                exporter.reference.verify_source(root)
                self.assertEqual(exporter.bundle(root, self.placement), baseline)
            self.assertIsNotNone(result, 'Manifest reread blocked after replacement: ' + timeout_output)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            events = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(events, [
                {'event': 'fifo-replacement'},
                {'event': 'rejected-before-consumption'},
            ])


if __name__ == '__main__':
    unittest.main()
