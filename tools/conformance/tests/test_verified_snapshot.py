"""Bind copied execution and exports to the exact pinned source bytes."""
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('snapshot_reference', HERE / 'run.py')
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)
spec = importlib.util.spec_from_file_location('snapshot_exporter', HERE / 'export_swift_vectors.py')
exporter = importlib.util.module_from_spec(spec)
with patch.dict(sys.modules, {'run': reference}):
    spec.loader.exec_module(exporter)


class VerifiedSnapshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.environ['CONTRACT_ROOT']).resolve()
        reference.verify_source(cls.root)

    def invoke_main(self, root, output):
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(sys, 'argv', [str(HERE / 'run.py'), '--contract-root', str(root),
                                        '--output', str(output)]), \
                redirect_stdout(stdout), redirect_stderr(stderr):
            try:
                reference.main()
                status = 0
            except SystemExit as error:
                status = error.code
        return status, stdout.getvalue(), stderr.getvalue()

    def test_manifest_hash_and_parse_use_the_same_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'v1'
            shutil.copytree(self.root, root)
            manifest_path = root / 'IMPORT_MANIFEST.json'
            source = root / 'examples/build.json'
            manifest_bytes, source_bytes = manifest_path.read_bytes(), source.read_bytes()
            replacement = source_bytes + b' '
            altered_manifest = json.loads(manifest_bytes)
            next(entry for entry in altered_manifest['files']
                 if entry['path'] == 'examples/build.json')['sha256'] = hashlib.sha256(replacement).hexdigest()
            original_read = Path.read_bytes
            changed = []

            def replace_after_read(path):
                value = original_read(path)
                if path == manifest_path and not changed:
                    changed.append(True)
                    manifest_path.write_text(json.dumps(altered_manifest))
                    source.write_bytes(replacement)
                return value

            try:
                with patch.object(Path, 'read_bytes', replace_after_read):
                    with self.assertRaisesRegex(ValueError, 'hash mismatch: examples/build.json'):
                        reference.verify_source(root)
                self.assertEqual(changed, [True])
            finally:
                manifest_path.write_bytes(manifest_bytes)
                source.write_bytes(source_bytes)
            reference.verify_source(root)

    def test_reference_handoff_rejects_changed_bytes_before_consumption_and_recovers(self):
        original_versions = reference.versions
        for relative in ('examples/build.json', 'schemas/build.schema.json', 'reference/evaluate.py'):
            with self.subTest(source=relative), tempfile.TemporaryDirectory() as directory:
                root, output = Path(directory) / 'v1', Path(directory) / 'receipt.json'
                shutil.copytree(self.root, root)
                status, _, stderr = self.invoke_main(root, output)
                self.assertEqual(status, 0, stderr)
                receipt = output.read_bytes()
                source = root / relative
                original = source.read_bytes()
                changed = []

                def change_after_verification():
                    result = original_versions()
                    changed.append(True)
                    source.write_bytes(original + b'\n ')
                    return result

                try:
                    with patch.object(reference, 'versions', side_effect=change_after_verification), \
                            patch.object(reference, 'vectors', wraps=reference.vectors) as consume:
                        status, stdout, stderr = self.invoke_main(root, output)
                    self.assertEqual(changed, [True])
                    self.assertEqual(status, 1, stderr)
                    self.assertIn('Frozen import hash mismatch: ' + relative, stderr)
                    self.assertEqual(stdout, '')
                    self.assertFalse(output.exists())
                    consume.assert_not_called()
                finally:
                    source.write_bytes(original)
                status, _, stderr = self.invoke_main(root, output)
                self.assertEqual(status, 0, stderr)
                self.assertEqual(output.read_bytes(), receipt)
                reference.verify_source(root)

    def test_reference_handoff_rechecks_source_path_containment(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'v1'
            shutil.copytree(self.root, root)
            source = root / 'reference/evaluate.py'
            original = source.read_bytes()
            outside = Path(directory) / 'outside-reference.py'
            outside.write_bytes(original)
            original_versions = reference.versions

            def redirect_after_verification():
                result = original_versions()
                source.unlink()
                source.symlink_to(outside)
                return result

            try:
                with patch.object(reference, 'versions', side_effect=redirect_after_verification), \
                        patch.object(reference, 'vectors', wraps=reference.vectors) as consume:
                    with self.assertRaisesRegex(ValueError, 'hash mismatch: reference/evaluate.py'):
                        reference.run(root)
                consume.assert_not_called()
                self.assertTrue(source.is_symlink())
                self.assertEqual(outside.read_bytes(), original)
            finally:
                source.unlink()
                source.write_bytes(original)
            reference.verify_source(root)
            self.assertEqual(reference.run(root)['canonical_reference'], 'passed')

    def test_export_handoff_rejects_changed_bytes_before_consumption_and_recovers(self):
        original_versions = reference.versions
        for relative in ('examples/evaluation-report.json', 'schemas/evaluation-report.schema.json'):
            with self.subTest(source=relative), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / 'v1'
                shutil.copytree(self.root, root)
                baseline = exporter.bundle(root)
                source = root / relative
                original = source.read_bytes()
                changed = []

                def change_after_verification():
                    result = original_versions()
                    changed.append(True)
                    source.write_bytes(original + b'\n ')
                    return result

                try:
                    with patch.object(reference, 'versions', side_effect=change_after_verification), \
                            patch.object(exporter, 'verified_bundle', wraps=exporter.verified_bundle) as consume:
                        with self.assertRaisesRegex(ValueError, 'hash mismatch: ' + relative):
                            exporter.bundle(root)
                    self.assertEqual(changed, [True])
                    consume.assert_not_called()
                finally:
                    source.write_bytes(original)
                self.assertEqual(exporter.bundle(root), baseline)
                reference.verify_source(root)


if __name__ == '__main__':
    unittest.main()
