"""Evidence exports must retain their real schema and byte-provenance failures."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
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
        copyfileobj = shutil.copyfileobj

        def corrupted_snapshot(source, target, *args, **kwargs):
            result = copyfileobj(source, target, *args, **kwargs)
            target.flush()
            copied_path = Path(target.name)
            if copied_path.name == "evaluation-report.json":
                copied_path.write_bytes(copied_path.read_bytes() + b" ")
            return result

        with patch.object(exporter.shutil, "copyfileobj", side_effect=corrupted_snapshot):
            with self.assertRaisesRegex(ValueError, "hash mismatch: examples/evaluation-report.json"):
                exporter.bundle(self.root)
        self.assertEqual(len(exporter.bundle(self.root)["cases"]), 37)


    def test_source_redirect_during_copy_is_rejected_before_consumption_and_recovers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "v1"
            shutil.copytree(self.root, root)
            source = root / "examples/evaluation-report.json"
            original = source.read_bytes()
            outside = Path(directory) / "outside-evaluation-report.json"
            outside.write_bytes(original)
            baseline = exporter.bundle(root)
            original_versions = exporter.reference.versions
            redirected = []

            def redirect_after_verification():
                result = original_versions()
                source.unlink()
                source.symlink_to(outside)
                redirected.append(True)
                return result

            try:
                with patch.object(exporter.reference, "versions", side_effect=redirect_after_verification), \
                        patch.object(exporter, "verified_bundle", wraps=exporter.verified_bundle) as consume:
                    with self.assertRaisesRegex(ValueError, "hash mismatch: examples/evaluation-report.json"):
                        exporter.bundle(root)
                self.assertEqual(redirected, [True])
                consume.assert_not_called()
                self.assertTrue(source.is_symlink())
                self.assertEqual(outside.read_bytes(), original)
            finally:
                source.unlink()
                source.write_bytes(original)
            exporter.reference.verify_source(root)
            self.assertEqual(exporter.bundle(root), baseline)

    def test_manifest_copy_rejects_fifo_replacement_before_consumption_and_recovers(self):
        probe = textwrap.dedent(r'''
            import json, os, stat, sys
            from pathlib import Path
            from unittest.mock import patch
            sys.path.insert(0, sys.argv[1])
            import evidence_vectors as exporter
            root = Path(sys.argv[2])
            manifest = root / "IMPORT_MANIFEST.json"
            original_stat = exporter.shutil._stat
            original_read = exporter.reference.read_regular_bytes
            original_versions = exporter.reference.versions
            verified = False
            replaced = []

            def after_verification():
                global verified
                result = original_versions()
                verified = True
                return result

            def replace(site):
                manifest.unlink()
                os.mkfifo(manifest)
                replaced.append(site)
                print(json.dumps({"event": "fifo-replacement", "site": site}), flush=True)

            def checked_stat(path):
                result = original_stat(path)
                if verified and not replaced and Path(path) == manifest:
                    replace("copyfile-source-stat")
                return result

            def checked_read(path):
                if verified and not replaced and Path(path) == manifest:
                    replace("regular-input-open")
                return original_read(path)

            with patch.object(exporter.reference, "versions", side_effect=after_verification), \
                    patch.object(exporter.shutil, "_stat", side_effect=checked_stat), \
                    patch.object(exporter.reference, "read_regular_bytes", side_effect=checked_read), \
                    patch.object(exporter, "verified_bundle", wraps=exporter.verified_bundle) as consume:
                try:
                    exporter.bundle(root)
                except ValueError as error:
                    if "Conformance input must be a regular file:" not in str(error):
                        raise
                else:
                    raise AssertionError("Replaced manifest was accepted")
                consume.assert_not_called()
            if replaced != ["regular-input-open"]:
                raise AssertionError(replaced)
            if not stat.S_ISFIFO(manifest.stat().st_mode):
                raise AssertionError("FIFO identity changed")
            print(json.dumps({"event": "rejected-before-consumption"}), flush=True)
        ''')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "v1"
            shutil.copytree(self.root, root)
            manifest = root / "IMPORT_MANIFEST.json"
            original = manifest.read_bytes()
            baseline = exporter.bundle(root)
            result = None
            timeout_output = ""
            try:
                try:
                    result = subprocess.run(
                        [sys.executable, "-B", "-u", "-c", probe, str(HERE), str(root)],
                        capture_output=True, text=True, timeout=3)
                except subprocess.TimeoutExpired as error:
                    output = error.stdout or b""
                    timeout_output = output.decode() if isinstance(output, bytes) else output
                self.assertTrue(stat.S_ISFIFO(manifest.stat().st_mode))
            finally:
                manifest.unlink()
                manifest.write_bytes(original)
                self.assertEqual(exporter.bundle(root), baseline)
            self.assertIsNotNone(result, "Manifest copy blocked after replacement: " + timeout_output)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            events = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(events, [
                {"event": "fifo-replacement", "site": "regular-input-open"},
                {"event": "rejected-before-consumption"},
            ])

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
