"""Verify conformance export rejects drift instead of silently re-blessing it."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class SwiftVectorTests(unittest.TestCase):
    def test_export_check_rejects_vector_and_source_fixture_drift(self):
        root = Path(os.environ['CONTRACT_ROOT']).resolve()
        exporter = Path(__file__).resolve().parents[1] / 'export_swift_vectors.py'
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'evaluation-vectors.json'
            fixture = output.parent / 'evaluation-report.json'
            shutil.copyfile(root / 'examples/evaluation-report.json', fixture)
            command = [sys.executable, str(exporter), '--contract-root', str(root), '--output', str(output)]
            def invoke(*arguments):
                return subprocess.run(command + list(arguments), capture_output=True, text=True)
            self.assertEqual(invoke().returncode, 0)
            original = output.read_bytes()
            self.assertEqual(invoke('--check').returncode, 0)
            output.write_bytes(original.replace(b'"valid": true', b'"valid": false', 1))
            result = invoke('--check')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('bundle differs', result.stderr)
            output.write_bytes(original)
            fixture.write_bytes(fixture.read_bytes() + b' ')
            result = invoke('--check')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('fixture differs', result.stderr)
            shutil.copyfile(root / 'examples/evaluation-report.json', fixture)
            self.assertEqual(invoke('--check').returncode, 0)


if __name__ == '__main__':
    unittest.main()
