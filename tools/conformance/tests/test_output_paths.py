"""Exercise output preflight only against newly owned synthetic directory trees."""
from contextlib import redirect_stderr, redirect_stdout
import errno
import importlib.util
import io
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
spec = importlib.util.spec_from_file_location('output_path_reference', HERE / 'run.py')
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


class OutputPathTests(unittest.TestCase):
    def fixture(self, directory):
        tools = directory / 'Tools'
        tools.mkdir()
        for name in ('run.py', 'contract-lock.json', 'requirements.txt'):
            shutil.copyfile(HERE / name, tools / name)
        source = directory / 'Source'
        source.mkdir()
        (source / 'IMPORT_MANIFEST.json').write_bytes(b'{}\n')
        return tools, source

    def invoke_cli(self, tools, root, output):
        return subprocess.run(
            [sys.executable, str(tools / 'run.py'), '--contract-root', str(root),
             '--output', str(output)], capture_output=True, text=True, timeout=10,
            env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})

    def assert_preserved(self, path, before, contents):
        self.assertTrue(path.exists(), f'Preflight removed synthetic input/output {path.name}')
        after = path.lstat()
        self.assertEqual((after.st_dev, after.st_ino, after.st_mode, after.st_nlink),
                         (before.st_dev, before.st_ino, before.st_mode, before.st_nlink))
        self.assertEqual(path.read_bytes(), contents)

    def test_cli_preserves_regular_input_prefixes_before_root_normalization(self):
        for variant in ('root-is-file', 'direct-child', 'direct-dotdot', 'alias-child',
                        'relative-alias-dotdot', 'nested-alias-dotdot'):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                tools, source = self.fixture(directory)
                prefix = directory / 'input-prefix'
                contents = b'Unshared synthetic input prefix; preserve bytes and inode.\n'
                prefix.write_bytes(contents)
                aliases = []
                if variant == 'root-is-file':
                    selected = prefix
                elif variant == 'direct-child':
                    selected = prefix / 'nested'
                elif variant == 'direct-dotdot':
                    selected = prefix / '..' / source.name
                else:
                    alias = directory / 'selected-alias'
                    target = (prefix / 'nested' if variant == 'alias-child' else
                              Path(prefix.name) / 'nested' / '..' / '..' / source.name)
                    alias.symlink_to(target, target_is_directory=True)
                    aliases.append((alias, os.readlink(alias), alias.lstat()))
                    selected = alias
                    if variant == 'nested-alias-dotdot':
                        outer = directory / 'outer-alias'
                        outer.symlink_to(alias.name, target_is_directory=True)
                        aliases.append((outer, os.readlink(outer), outer.lstat()))
                        selected = outer
                before = prefix.lstat()
                rejected = self.invoke_cli(tools, selected, prefix)
                self.assertEqual(rejected.returncode, 1, rejected.stdout + rejected.stderr)
                self.assertEqual(rejected.stdout, '')
                self.assertIn('Conformance failed:', rejected.stderr)
                self.assert_preserved(prefix, before, contents)
                for alias, target, initial in aliases:
                    self.assertTrue(alias.is_symlink())
                    self.assertEqual(os.readlink(alias), target)
                    self.assertEqual(alias.lstat().st_ino, initial.st_ino)
                self.assertEqual((source / 'IMPORT_MANIFEST.json').read_bytes(), b'{}\n')

    def test_cli_preserves_receipts_for_invalid_destination_prefixes(self):
        for variant in ('direct-file', 'alias-file', 'direct-missing', 'alias-missing'):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                tools, source = self.fixture(directory)
                destination = directory / 'destination'
                destination.mkdir()
                receipt = destination / 'receipt.json'
                contents = b'{"synthetic_prior_receipt":true}\n'
                receipt.write_bytes(contents)
                before = receipt.lstat()
                prefix = directory / 'invalid-prefix'
                if variant.endswith('file'):
                    prefix.write_bytes(b'Preserve this synthetic prefix.\n')
                    prefix_before = prefix.lstat()
                selected_parent = prefix / '..' / destination.name
                if variant.startswith('alias'):
                    alias = directory / 'destination-alias'
                    alias.symlink_to(Path(prefix.name) / '..' / destination.name,
                                     target_is_directory=True)
                    selected_parent = alias
                rejected = self.invoke_cli(tools, source, selected_parent / receipt.name)
                self.assertEqual(rejected.returncode, 1, rejected.stdout + rejected.stderr)
                self.assertEqual(rejected.stdout, '')
                self.assertIn('Conformance failed:', rejected.stderr)
                self.assert_preserved(receipt, before, contents)
                if variant.endswith('file'):
                    self.assert_preserved(prefix, prefix_before, b'Preserve this synthetic prefix.\n')
                else:
                    self.assertFalse(prefix.exists())
                if variant.startswith('alias'):
                    self.assertTrue(alias.is_symlink())

    def test_cli_valid_directory_aliases_still_invalidate_content_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            tools, source = self.fixture(directory)
            child = source / 'ordinary-child'
            child.mkdir()
            alias = directory / 'source-alias'
            alias.symlink_to(child / '..', target_is_directory=True)
            destination = directory / 'destination'
            destination.mkdir()
            destination_alias = directory / 'destination-alias'
            destination_alias.symlink_to(destination, target_is_directory=True)
            output = destination / 'receipt.json'
            output.write_bytes(b'{"synthetic_prior_receipt":true}\n')
            rejected = self.invoke_cli(tools, alias, destination_alias / output.name)
            self.assertEqual(rejected.returncode, 1, rejected.stdout + rejected.stderr)
            self.assertEqual(rejected.stdout, '')
            self.assertIn('Frozen import manifest differs', rejected.stderr)
            self.assertFalse(output.exists(), 'Accepted content failure retained a stale receipt')
            self.assertTrue(alias.is_symlink())
            self.assertTrue(destination_alias.is_symlink())
            self.assertTrue(child.is_dir())
            self.assertEqual((source / 'IMPORT_MANIFEST.json').read_bytes(), b'{}\n')

    def test_cli_case_variants_follow_observed_directory_identity(self):
        for protected in ('Source', 'Tools'):
            with self.subTest(protected=protected), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                tools, source = self.fixture(directory)
                actual = directory / protected
                variant = directory / protected.lower()
                aliases = variant.exists() and os.path.samestat(actual.stat(), variant.stat())
                if not aliases:
                    variant.mkdir()
                output = variant / 'synthetic-receipt.json'
                contents = b'Preserve this only when the directory is protected.\n'
                output.write_bytes(contents)
                before = output.lstat()
                rejected = self.invoke_cli(tools, source, output)
                self.assertEqual(rejected.returncode, 1, rejected.stdout + rejected.stderr)
                self.assertEqual(rejected.stdout, '')
                if aliases:
                    self.assertIn('Output must be outside', rejected.stderr)
                    self.assert_preserved(output, before, contents)
                else:
                    self.assertIn('Frozen import manifest differs', rejected.stderr)
                    self.assertFalse(output.exists())
                print(f'Output path {protected}: observed ' +
                      ('same-directory case alias' if aliases else 'distinct case directories'))

    def test_directory_lookup_errors_preserve_receipts_before_execution(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            tools, source = self.fixture(directory)
            output = directory / 'receipt.json'
            contents = b'{"synthetic_prior_receipt":true}\n'
            original_stat = Path.stat
            for target in (source, directory):
                for code in (errno.EACCES, errno.EIO):
                    with self.subTest(target=target.name, error=code):
                        output.write_bytes(contents)
                        before = output.lstat()
                        def checked_stat(path, *args, **kwargs):
                            if path == target:
                                raise OSError(code, 'Synthetic directory lookup failure')
                            return original_stat(path, *args, **kwargs)
                        stdout, stderr = io.StringIO(), io.StringIO()
                        with patch.object(Path, 'stat', checked_stat), \
                                patch.object(reference, 'HERE', tools), \
                                patch.object(reference, 'run', return_value=dict(
                                    schema_results=[], domain_results=[])) as execute, \
                                patch.object(sys, 'argv', ['run.py', '--contract-root', str(source),
                                                          '--output', str(output)]), \
                                redirect_stdout(stdout), redirect_stderr(stderr):
                            with self.assertRaises(SystemExit) as stopped:
                                reference.main()
                        self.assertEqual(stopped.exception.code, 1)
                        self.assertEqual(stdout.getvalue(), '')
                        self.assertIn('Synthetic directory lookup failure', stderr.getvalue())
                        execute.assert_not_called()
                        self.assert_preserved(output, before, contents)


if __name__ == '__main__':
    unittest.main()
