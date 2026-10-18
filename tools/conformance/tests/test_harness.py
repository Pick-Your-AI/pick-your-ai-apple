"""Harness regressions; use --contract-root's same frozen checkout via environment."""
import copy
from contextlib import contextmanager, redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

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

    def invoke_main(self, root, output):
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(sys, 'argv', [str(HERE / 'run.py'), '--contract-root', str(root),
                                        '--output', str(output)]), \
                redirect_stdout(stdout), redirect_stderr(stderr):
            try:
                runner.main()
                status = 0
            except SystemExit as error:
                status = error.code
        return status, stdout.getvalue(), stderr.getvalue()

    def test_cli_failed_source_removes_success_receipt_and_recovers(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            output = directory / 'receipt.json'
            invalid = directory / 'invalid-contract'
            invalid.mkdir()
            (invalid / 'IMPORT_MANIFEST.json').write_text('{}\n')

            def invoke(root):
                return subprocess.run([sys.executable, str(HERE / 'run.py'), '--contract-root',
                                       str(root), '--output', str(output)],
                                      capture_output=True, text=True, timeout=120,
                                      env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})

            baseline = invoke(self.root)
            self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
            original = output.read_bytes()
            receipt = json.loads(original)
            self.assertEqual(receipt['canonical_reference'], 'passed')
            self.assertTrue(all(check['passed'] for check in
                                receipt['schema_results'] + receipt['domain_results']))
            self.assertTrue(all(mutation['detected'] for mutation in receipt['mutations']))

            failed = invoke(invalid)
            self.assertEqual(failed.returncode, 1, failed.stdout + failed.stderr)
            self.assertIn('Frozen import manifest differs', failed.stderr)
            self.assertEqual(failed.stdout, '')
            stale_receipt_remained = output.exists()

            recovery = invoke(self.root)
            self.assertEqual(recovery.returncode, 0, recovery.stdout + recovery.stderr)
            self.assertEqual(output.read_bytes(), original)
            runner.verify_source(self.root)
            self.assertFalse(stale_receipt_remained,
                             'The exit-1 source rejection retained a prior success receipt')

    def test_output_cannot_replace_canonical_or_tool_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            source, tool = directory / 'contracts', directory / 'tools'
            source.mkdir()
            tool.mkdir()
            source_file, tool_file = source / 'input.json', tool / 'contract-lock.json'
            source_file.write_bytes(b'frozen source\n')
            tool_file.write_bytes(b'runner source\n')
            source_alias, tool_alias = directory / 'source-alias', directory / 'tool-alias'
            source_alias.symlink_to(source, target_is_directory=True)
            tool_alias.symlink_to(tool, target_is_directory=True)
            for output in (source, tool, source_file, tool_file,
                           source_alias / source_file.name, tool_alias / tool_file.name):
                with self.subTest(output=output), patch.object(runner, 'HERE', tool), \
                        patch.object(runner, 'run') as execute:
                    status, stdout, stderr = self.invoke_main(source, output)
                    self.assertEqual(status, 1, stderr)
                    self.assertIn('Output must be outside', stderr)
                    self.assertEqual(stdout, '')
                    execute.assert_not_called()
                    self.assertEqual(source_file.read_bytes(), b'frozen source\n')
                    self.assertEqual(tool_file.read_bytes(), b'runner source\n')
                    self.assertTrue(source_alias.is_symlink())
                    self.assertTrue(tool_alias.is_symlink())

    def test_output_rejects_links_and_wrong_types_without_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            source = directory / 'contracts'
            source.mkdir()
            original = source / 'input.json'
            original.write_bytes(b'frozen source\n')
            folder = directory / 'folder'
            folder.mkdir()
            (folder / 'keep').write_bytes(b'keep\n')
            symbolic, dangling = directory / 'symbolic', directory / 'dangling'
            symbolic.symlink_to(original)
            dangling.symlink_to(directory / 'absent')
            directory_link = directory / 'directory-link'
            directory_link.symlink_to(folder, target_is_directory=True)
            hardlink = directory / 'hardlink'
            hardlink.hardlink_to(original)
            outputs = [symbolic, dangling, directory_link, hardlink, folder]
            if hasattr(os, 'mkfifo'):
                fifo = directory / 'fifo'
                os.mkfifo(fifo)
                outputs.append(fifo)
            for output in outputs:
                before = output.lstat()
                with self.subTest(output=output), patch.object(runner, 'run') as execute:
                    status, stdout, stderr = self.invoke_main(source, output)
                    self.assertEqual(status, 1, stderr)
                    self.assertIn('Output must be an unshared regular file', stderr)
                    self.assertEqual(stdout, '')
                    execute.assert_not_called()
                    after = output.lstat()
                    self.assertEqual((after.st_ino, after.st_mode, after.st_nlink),
                                     (before.st_ino, before.st_mode, before.st_nlink))
                    self.assertEqual(original.read_bytes(), b'frozen source\n')
                    self.assertEqual((folder / 'keep').read_bytes(), b'keep\n')

    def test_output_requires_an_existing_directory_parent(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            ordinary_file = directory / 'ordinary-file'
            ordinary_file.write_bytes(b'keep\n')
            for parent in (directory / 'missing', ordinary_file):
                with self.subTest(parent=parent), patch.object(runner, 'run') as execute:
                    status, stdout, stderr = self.invoke_main(self.root, parent / 'receipt.json')
                    self.assertEqual(status, 1, stderr)
                    self.assertIn('Conformance failed:', stderr)
                    self.assertEqual(stdout, '')
                    execute.assert_not_called()
            self.assertFalse((directory / 'missing').exists())
            self.assertEqual(ordinary_file.read_bytes(), b'keep\n')

    def test_output_accepts_a_separate_directory_with_a_similar_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            source, destination = directory / 'contracts', directory / 'contracts-receipts'
            source.mkdir()
            destination.mkdir()
            alias = directory / 'receipts-alias'
            alias.symlink_to(destination, target_is_directory=True)
            result = dict(schema_results=[], domain_results=[])
            with patch.object(runner, 'run', return_value=result) as execute:
                status, stdout, stderr = self.invoke_main(source, alias / 'receipt.json')
            self.assertEqual(status, 0, stderr)
            self.assertTrue(stdout.startswith('PASS '))
            self.assertEqual(json.loads((destination / 'receipt.json').read_text()), result)
            self.assertTrue(alias.is_symlink())
            execute.assert_called_once_with(source)

    def test_dependency_failure_invalidates_an_accepted_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'receipt.json'
            output.write_text('{"canonical_reference": "passed"}\n')
            with patch.object(runner, 'versions', side_effect=ValueError('deliberate dependency mismatch')):
                status, stdout, stderr = self.invoke_main(self.root, output)
            self.assertEqual(status, 1, stderr)
            self.assertIn('deliberate dependency mismatch', stderr)
            self.assertEqual(stdout, '')
            self.assertFalse(output.exists())

    def test_publication_failures_leave_no_partial_or_stale_receipt(self):
        original_temporary_file = runner.tempfile.NamedTemporaryFile
        partial_writes = []

        @contextmanager
        def failing_write(*args, **kwargs):
            with original_temporary_file(*args, **kwargs) as stream:
                write = stream.write

                def write_then_fail(contents):
                    partial_writes.append(write(contents[:13]))
                    raise OSError('deliberate write failure')

                with patch.object(stream, 'write', side_effect=write_then_fail):
                    yield stream

        failures = (
            ('serialization', patch.object(runner.json, 'dumps',
                                           side_effect=ValueError('deliberate serialization failure'))),
            ('write', patch.object(runner.tempfile, 'NamedTemporaryFile', side_effect=failing_write)),
            ('replace', patch.object(runner.Path, 'replace',
                                     side_effect=OSError('deliberate replace failure'))),
        )
        for phase, failure in failures:
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                output, unrelated = directory / 'receipt.json', directory / 'keep'
                output.write_text('{"canonical_reference": "passed"}\n')
                unrelated.write_bytes(b'keep\n')
                with patch.object(runner, 'run', return_value=dict(schema_results=[], domain_results=[])), failure:
                    status, stdout, stderr = self.invoke_main(self.root, output)
                self.assertEqual(status, 1, stderr)
                self.assertIn(f'deliberate {phase} failure', stderr)
                self.assertEqual(stdout, '')
                self.assertFalse(output.exists())
                self.assertEqual(list(directory.iterdir()), [unrelated])
                self.assertEqual(unrelated.read_bytes(), b'keep\n')
        self.assertEqual(partial_writes, [13])


if __name__ == '__main__':
    unittest.main()
