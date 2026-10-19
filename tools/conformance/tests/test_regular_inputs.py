"""Reject special files without waiting for a FIFO writer or reopening admitted inputs."""
import errno
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('regular_input_reference', HERE / 'run.py')
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)

# This child performs an actual pathname replacement on either side of open().
# Its parent imposes the deadline and subprocess.run kills/reaps it on timeout.
OPEN_REPLACEMENT_PROBE = r'''
import errno
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
spec = importlib.util.spec_from_file_location('probe_reference', sys.argv[1])
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)
target, moment, operation = Path(sys.argv[2]), sys.argv[3], sys.argv[4]
original = target.read_bytes()
original_open = os.open
opened, flags_seen, replacements = [], [], []

def replace():
    target.unlink()
    os.mkfifo(target, 0o600)
    replacements.append(target.stat().st_ino)

def intercepted_open(path, flags, *args, **kwargs):
    if Path(path) != target:
        return original_open(path, flags, *args, **kwargs)
    if moment == 'before':
        replace()
    descriptor = original_open(path, flags, *args, **kwargs)
    opened.append(descriptor)
    flags_seen.append(flags)
    if moment == 'after':
        replace()
    return descriptor

reference.os.open = intercepted_open
record = {}
try:
    if operation == 'digest':
        record['digest'] = reference.digest(target)
    else:
        # A one-entry trusted-manifest fixture isolates the copy admission boundary.
        manifest = {'files': [{'path': target.name,
                               'sha256': hashlib.sha256(original).hexdigest()}]}
        snapshot = target.parent / 'snapshot'
        reference.copy_verified_source(target.parent, snapshot, manifest)
        record['copied_bytes_hex'] = (snapshot / target.name).read_bytes().hex()
except Exception as error:
    record.update(exception=type(error).__name__, message=str(error))
finally:
    reference.os.open = original_open
closed = []
for descriptor in opened:
    try:
        os.fstat(descriptor)
    except OSError as error:
        closed.append(error.errno == errno.EBADF)
    else:
        closed.append(False)
record.update(replacements=replacements, opened=len(opened), descriptors_closed=closed,
              nonblocking_flags=[bool(flags & os.O_NONBLOCK) for flags in flags_seen],
              final_fifo=stat.S_ISFIFO(target.stat().st_mode))
print(json.dumps(record))
'''


class RegularInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.environ['CONTRACT_ROOT']).resolve()
        reference.verify_source(cls.root)

    def invoke_cli(self, root, output, timeout=120):
        try:
            return subprocess.run(
                [sys.executable, str(HERE / 'run.py'), '--contract-root', str(root),
                 '--output', str(output)], capture_output=True, text=True, timeout=timeout,
                env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
        except subprocess.TimeoutExpired:
            self.fail(f'Conformance CLI did not finish within {timeout} seconds; '
                      'only its direct child was killed and reaped')

    def test_cli_rejects_fifo_inputs_removes_receipt_and_recovers(self):
        for relative in ('IMPORT_MANIFEST.json', 'examples/build.json'):
            with self.subTest(input=relative), tempfile.TemporaryDirectory() as directory:
                root, output = Path(directory) / 'v1', Path(directory) / 'receipt.json'
                shutil.copytree(self.root, root)
                baseline = self.invoke_cli(root, output)
                self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
                receipt = output.read_bytes()
                target = root / relative
                original = target.read_bytes()
                target.unlink()
                os.mkfifo(target, 0o600)
                before = target.stat()
                try:
                    rejected = self.invoke_cli(root, output, timeout=3)
                    self.assertEqual(rejected.returncode, 1, rejected.stdout + rejected.stderr)
                    self.assertIn('must be a regular file', rejected.stderr)
                    self.assertEqual(rejected.stdout, '')
                    self.assertFalse(output.exists(), 'Special-file rejection retained a success receipt')
                    after = target.stat()
                    self.assertEqual((after.st_ino, after.st_mode), (before.st_ino, before.st_mode))
                finally:
                    target.unlink()
                    target.write_bytes(original)
                recovered = self.invoke_cli(root, output)
                self.assertEqual(recovered.returncode, 0, recovered.stdout + recovered.stderr)
                self.assertEqual(output.read_bytes(), receipt)
                reference.verify_source(root)

    def test_regular_bytes_and_contained_input_aliases_still_verify_and_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'v1'
            shutil.copytree(self.root, root)
            original_manifest = reference.verify_source(root)
            for relative in ('IMPORT_MANIFEST.json', 'examples/build.json'):
                target = root / relative
                saved = root / (target.name + '.ordinary-input')
                target.rename(saved)
                target.symlink_to(saved)
            alias = Path(directory) / 'root-alias'
            alias.symlink_to(root, target_is_directory=True)
            self.assertEqual(reference.verify_source(alias), original_manifest)
            snapshot = Path(directory) / 'snapshot'
            reference.copy_verified_source(alias, snapshot, original_manifest)
            for entry in original_manifest['files']:
                self.assertEqual(reference.digest(snapshot / entry['path']), entry['sha256'])
            hardlink = Path(directory) / 'input-hardlink'
            hardlink.hardlink_to(root / 'build.json.ordinary-input')
            self.assertEqual(reference.digest(hardlink),
                             reference.digest(root / 'examples/build.json'))

    def test_directory_and_character_device_reject_without_input_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / 'folder'
            folder.mkdir()
            (folder / 'keep').write_bytes(b'preserved\n')
            inputs = (folder, Path(os.devnull))
            self.assertTrue(stat.S_ISCHR(inputs[1].stat().st_mode))
            for path in inputs:
                with self.subTest(input=str(path)):
                    before = path.stat()
                    with self.assertRaisesRegex(ValueError, 'must be a regular file'):
                        reference.digest(path)
                    after = path.stat()
                    self.assertEqual((after.st_dev, after.st_ino, after.st_mode),
                                     (before.st_dev, before.st_ino, before.st_mode))
            self.assertEqual((folder / 'keep').read_bytes(), b'preserved\n')

    def replacement_probe(self, moment, operation):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'input'
            original = b'exact admitted bytes\x00\xff\n'
            target.write_bytes(original)
            try:
                completed = subprocess.run(
                    [sys.executable, '-c', OPEN_REPLACEMENT_PROBE,
                     str(HERE / 'run.py'), str(target), moment, operation],
                    capture_output=True, text=True, timeout=3,
                    env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
            except subprocess.TimeoutExpired:
                self.fail('Replacing the input with a FIFO blocked the reader; '
                          'only its direct child was killed and reaped')
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            record = json.loads(completed.stdout)
            self.assertEqual(len(record['replacements']), 1, record)
            self.assertEqual(record['opened'], 1, record)
            self.assertEqual(record['descriptors_closed'], [True], record)
            self.assertEqual(record['nonblocking_flags'], [True], record)
            self.assertTrue(record['final_fifo'], record)
            if moment == 'before':
                self.assertEqual(record.get('exception'), 'ValueError', record)
                self.assertIn('must be a regular file', record['message'])
                self.assertNotIn('digest', record)
                self.assertNotIn('copied_bytes_hex', record)
            else:
                self.assertNotIn('exception', record)
                if operation == 'digest':
                    self.assertEqual(record['digest'], hashlib.sha256(original).hexdigest())
                else:
                    self.assertEqual(record['copied_bytes_hex'], original.hex())

    def test_fifo_replacement_before_open_rejects_for_hash_and_copy(self):
        for operation in ('digest', 'copy'):
            with self.subTest(operation=operation):
                self.replacement_probe('before', operation)

    def test_replacement_after_open_keeps_admitted_bytes_for_hash_and_copy(self):
        for operation in ('digest', 'copy'):
            with self.subTest(operation=operation):
                self.replacement_probe('after', operation)


if __name__ == '__main__':
    unittest.main()
