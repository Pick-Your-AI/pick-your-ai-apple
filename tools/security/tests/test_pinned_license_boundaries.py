"""Keep the two reviewed installer proofs independent when both are available."""

from __future__ import annotations

import copy
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "check_dependency_review.py"
SPEC = importlib.util.spec_from_file_location("installer_boundary_review", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
REVIEW = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = REVIEW
SPEC.loader.exec_module(REVIEW)
FIXTURES = Path(__file__).with_name("fixtures")
TYPING = json.loads((FIXTURES / "typing-extensions-license-classification.json").read_text())
TRANSFER = json.loads((FIXTURES / "pinned-transfer-license-conflict.json").read_text())
TYPING_LOCK = REVIEW.TYPING_LOCK_PATH.read_bytes()
TRANSFER_LOCK = (FIXTURES / "pinned-transfer-requirements.fixture").read_bytes()
ARTIFACT = b"INERT SHARED ARTIFACT: no package code or real wheel receipt\n"
TOKEN = "SYNTHETIC-BOUNDARY-TOKEN-NOT-FOR-ARTIFACT-HOST"


class Response(io.BytesIO):
    status = 200


class Transport:
    def __init__(self):
        self.requests = []

    def open(self, request, *, timeout):
        self.requests.append((request, timeout))
        return Response(ARTIFACT)


class PinnedInstallerBoundaryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.typing_path = root / "conformance-lock.txt"
        self.transfer_path = root / "transfer-lock.txt"
        self.reset_locks()

    def reset_locks(self):
        self.typing_path.write_bytes(TYPING_LOCK)
        self.transfer_path.write_bytes(TRANSFER_LOCK)

    def execute(self, changes, classified):
        transport = Transport()
        env = {
            "DEPENDENCY_CHANGES": json.dumps(changes),
            "INVALID_LICENSE_CHANGES": json.dumps(classified),
            "DEPENDENCY_REVIEW_OUTCOME": "failure",
            "DEPENDENCY_SNAPSHOT_OUTCOME": "success",
            "ALLOWED_DEPENDENCY_LICENSES": "MIT, PSF-2.0",
            "DEPENDENCY_REVIEW_TOKEN": TOKEN,
            "GITHUB_REPOSITORY": "Pick-Your-AI/pick-your-ai-apple",
            "GITHUB_EVENT_NAME": "pull_request",
        }
        output, diagnostic = io.StringIO(), io.StringIO()
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(REVIEW, "TYPING_LOCK_PATH", self.typing_path),
            patch.object(REVIEW, "TRANSFER_LOCK_PATH", self.transfer_path),
            patch.object(REVIEW, "TYPING_WHEEL_BYTES", len(ARTIFACT)),
            patch.object(REVIEW, "TRANSFER_WHEEL_BYTES", len(ARTIFACT)),
            patch.object(REVIEW, "TYPING_WHEEL_SHA256", hashlib.sha256(ARTIFACT).hexdigest()),
            patch.object(REVIEW, "TRANSFER_WHEEL_SHA256", hashlib.sha256(ARTIFACT).hexdigest()),
            patch.object(REVIEW, "build_opener", return_value=transport),
            redirect_stdout(output), redirect_stderr(diagnostic),
        ):
            status = REVIEW.main()
        self.assertNotIn(TOKEN, output.getvalue() + diagnostic.getvalue())
        report = json.loads(output.getvalue()) if output.getvalue() else None
        return status, report, transport

    def cases(self):
        return [
            (TYPING["dependency_changes"], TYPING["invalid_license_changes"],
             self.typing_path, self.transfer_path, "apple-pinned-dependency-license", 7),
            (TRANSFER["changes"], TRANSFER["invalid_licenses"],
             self.transfer_path, self.typing_path, "apple-pinned-transfer-license", 11),
        ]

    def test_each_captured_case_uses_only_its_own_installer_proof(self):
        for changes, classified, _, other_path, agent, count in self.cases():
            with self.subTest(manifest=classified["forbidden"][0]["manifest"]):
                self.reset_locks()
                other_path.unlink()
                status, report, transport = self.execute(changes, classified)
                self.assertEqual(status, 0)
                self.assertTrue(report["accepted"])
                self.assertEqual(report["added_dependencies"], count)
                self.assertEqual(report["pinned_license_resolutions"], 1)
                self.assertEqual(report["disallowed_licenses"], 0)
                self.assertEqual(len(transport.requests), 1)
                request, timeout = transport.requests[0]
                self.assertEqual(request.get_header("User-agent"), agent)
                self.assertIsNone(request.get_header("Authorization"))
                self.assertIsNone(request.get_header("Cookie"))
                self.assertGreater(timeout, 0)
                self.assertLessEqual(timeout, 10)

    def test_missing_swapped_or_changed_matching_lock_cannot_borrow_other_proof(self):
        for changes, classified, matching_path, other_path, _, _ in self.cases():
            for variant in ("missing", "swapped", "changed"):
                with self.subTest(manifest=classified["forbidden"][0]["manifest"], variant=variant):
                    self.reset_locks()
                    if variant == "missing":
                        matching_path.unlink()
                    elif variant == "swapped":
                        matching_path.write_bytes(other_path.read_bytes())
                    else:
                        original = matching_path.read_bytes()
                        matching_path.write_bytes(bytes([original[0] ^ 1]) + original[1:])
                    status, report, transport = self.execute(changes, classified)
                    self.assertEqual(status, 1)
                    self.assertIsNone(report)
                    self.assertEqual(transport.requests, [])

    def test_two_manifest_rows_never_become_a_combined_or_partial_recovery(self):
        typing = TYPING["invalid_license_changes"]["forbidden"][0]
        transfer = TRANSFER["invalid_licenses"]["forbidden"][0]
        for rows in ([typing, transfer], [transfer, typing]):
            for forbidden in (rows, [typing], [transfer]):
                with self.subTest(raw_order=rows[0]["manifest"], forbidden=len(forbidden)):
                    classified = {"forbidden": forbidden, "unlicensed": [], "unresolved": []}
                    status, report, transport = self.execute(rows, classified)
                    self.assertEqual(status, 1)
                    self.assertFalse(report["accepted"])
                    self.assertEqual(report["disallowed_licenses"], len(forbidden))
                    self.assertEqual(report["pinned_license_resolutions"], 0)
                    self.assertEqual(transport.requests, [])

    def test_an_unreviewed_manifest_is_rejected_with_both_valid_locks_present(self):
        for source in (TYPING["invalid_license_changes"], TRANSFER["invalid_licenses"]):
            row = copy.deepcopy(source["forbidden"][0])
            row["manifest"] = "tools/unreviewed/requirements-lock.txt"
            classified = {"forbidden": [row], "unlicensed": [], "unresolved": []}
            status, report, transport = self.execute([row], classified)
            self.assertEqual(status, 1)
            self.assertFalse(report["accepted"])
            self.assertEqual(report["pinned_license_resolutions"], 0)
            self.assertEqual(transport.requests, [])


if __name__ == "__main__":
    unittest.main()
