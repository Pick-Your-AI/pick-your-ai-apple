"""Captured Transfer failure and controlled byte-proof regressions; no wheel executes."""

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
from urllib.error import URLError
from urllib.request import Request


SCRIPT = Path(__file__).resolve().parents[1] / "check_dependency_review.py"
SPEC = importlib.util.spec_from_file_location("transfer_dependency_review", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
REVIEW = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = REVIEW
SPEC.loader.exec_module(REVIEW)
OBSERVED = json.loads((Path(__file__).with_name("fixtures") / "pinned-transfer-license-conflict.json").read_text())
LOCK_FIXTURE = Path(__file__).with_name("fixtures") / "pinned-transfer-requirements.fixture"
LOCK = LOCK_FIXTURE.read_bytes()
# Transport unit tests use controlled bytes and their real digest. The separate
# receiving receipt verifies the original immutable wheel without patching pins.
ARTIFACT = b"CONTROLLED TEST ARTIFACT: not executable package evidence"
TOKEN = "SYNTHETIC-GITHUB-TOKEN-NEVER-SEND-TO-ARTIFACT-HOST"


class Response(io.BytesIO):
    def __init__(self, body, status):
        super().__init__(body)
        self.status = status
        self.requests = []
        self.received = 0

    def read1(self, size):
        self.requests.append(size)
        body = super().read1(size)
        self.received += len(body)
        return body


class Transport:
    def __init__(self, body=ARTIFACT, *, status=200, error=None):
        self.response = Response(body, status)
        self.error = error
        self.requests = []

    def open(self, request, *, timeout):
        self.requests.append((request, timeout))
        if self.error is not None:
            raise self.error
        return self.response


def execute(changes=None, classified=None, *, transport=None, policy="MIT, PSF-2.0", extra_env=None):
    transport = Transport() if transport is None else transport
    env = {
        "DEPENDENCY_CHANGES": json.dumps(OBSERVED["changes"] if changes is None else changes),
        "INVALID_LICENSE_CHANGES": json.dumps(OBSERVED["invalid_licenses"] if classified is None else classified),
        "ALLOWED_DEPENDENCY_LICENSES": policy,
        "DEPENDENCY_REVIEW_TOKEN": TOKEN,
        "DEPENDENCY_REVIEW_OUTCOME": "failure",
        "DEPENDENCY_SNAPSHOT_OUTCOME": "success",
        "GITHUB_REPOSITORY": "Pick-Your-AI/pick-your-ai-apple",
        "GITHUB_EVENT_NAME": "pull_request",
        **(extra_env or {}),
    }
    env = {key: value for key, value in env.items() if value is not None}
    out, err = io.StringIO(), io.StringIO()
    with (
        patch.dict(os.environ, env, clear=True),
        patch.object(REVIEW, "build_opener", return_value=transport),
        patch.object(REVIEW, "TRANSFER_WHEEL_BYTES", len(ARTIFACT)),
        patch.object(REVIEW, "TRANSFER_WHEEL_SHA256", hashlib.sha256(ARTIFACT).hexdigest()),
        redirect_stdout(out), redirect_stderr(err),
    ):
        status = REVIEW.main()
    return status, json.loads(out.getvalue()) if out.getvalue() else None, err.getvalue(), transport


class PinnedTransferLicenseTests(unittest.TestCase):
    def setUp(self):
        # Main does not acquire the held Transfer feature or its active manifest.
        # Only this inert, byte-identical fixture supplies the reviewed installer.
        fixture = patch.object(REVIEW, "TRANSFER_LOCK_PATH", LOCK_FIXTURE)
        fixture.start()
        self.addCleanup(fixture.stop)

    def test_observed_failure_requires_exact_installer_and_verified_artifact(self):
        self.assertEqual(OBSERVED["source"]["job_id"], 117714734437)
        self.assertEqual(len(LOCK), REVIEW.TRANSFER_LOCK_BYTES)
        self.assertEqual(hashlib.sha256(LOCK).hexdigest(), REVIEW.TRANSFER_LOCK_SHA256)
        baseline = REVIEW.evaluate(OBSERVED["changes"], OBSERVED["invalid_licenses"])
        self.assertFalse(baseline.accepted)
        self.assertEqual((baseline.disallowed_licenses, baseline.pinned_license_resolutions), (1, 0))
        status, result, diagnostic, transport = execute()
        self.assertEqual(status, 0, diagnostic)
        self.assertTrue(result["accepted"])
        self.assertEqual((result["added_dependencies"], result["pinned_license_resolutions"]), (11, 1))
        self.assertEqual(result["disallowed_licenses"], 0)
        self.assertEqual(len(transport.requests), 1)
        request, timeout = transport.requests[0]
        self.assertEqual(request.full_url, REVIEW.TRANSFER_WHEEL_URL)
        self.assertIsNone(request.get_header("Authorization"))
        self.assertIsNone(request.get_header("Cookie"))
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 10)
        self.assertNotIn(TOKEN, diagnostic)

    def test_other_manifest_identity_scope_or_classification_cannot_borrow_proof(self):
        mutations = {
            "manifest": "tools/conformance/requirements-lock.txt", "ecosystem": "npm",
            "name": "another-package", "version": "4.16.1", "change_type": "removed",
            "package_url": "pkg:pypi/typing-extensions@4.16.1", "scope": "development",
            "license": "GPL-3.0-only", "source_repository_url": "https://example.invalid/private",
        }
        for key, value in mutations.items():
            with self.subTest(key=key):
                changes = copy.deepcopy(OBSERVED["changes"])
                row = next(row for row in changes if row["name"] == "typing-extensions")
                row[key] = value
                classified = {"forbidden": [copy.deepcopy(row)], "unresolved": [], "unlicensed": []}
                status, result, _, transport = execute(changes, classified)
                self.assertEqual(status, 1)
                self.assertFalse(result["accepted"])
                self.assertEqual(transport.requests, [])

    def test_missing_duplicate_or_conflicting_raw_rows_cannot_borrow_proof(self):
        original = OBSERVED["changes"]
        row = OBSERVED["invalid_licenses"]["forbidden"][0]
        missing = [entry for entry in original if entry != row]
        conflict = copy.deepcopy(row)
        conflict["license"] = "LicenseRef-Unreviewed"
        for changes in (missing, original + [row], original + [conflict]):
            status, result, _, transport = execute(changes)
            self.assertEqual(status, 1)
            self.assertFalse(result["accepted"])
            self.assertEqual(transport.requests, [])

    def test_other_license_categories_and_vulnerabilities_remain_failures(self):
        for category in ("forbidden", "unresolved", "unlicensed"):
            classified = copy.deepcopy(OBSERVED["invalid_licenses"])
            classified[category].append(copy.deepcopy(OBSERVED["changes"][0]))
            status, result, _, transport = execute(classified=classified)
            self.assertEqual(status, 1)
            self.assertFalse(result["accepted"])
            self.assertEqual(transport.requests, [])
        changes = copy.deepcopy(OBSERVED["changes"])
        changes[0]["vulnerabilities"] = [{"severity": "low"}]
        status, result, _, transport = execute(changes)
        self.assertEqual(status, 1)
        self.assertEqual(result["vulnerable_dependencies"], 1)
        self.assertEqual(transport.requests, [])

    def test_original_outcome_and_successful_exact_snapshots_are_mandatory(self):
        for key, values in {
            "DEPENDENCY_REVIEW_OUTCOME": [None, "", "skipped", "cancelled", "neutral", "success"],
            "DEPENDENCY_SNAPSHOT_OUTCOME": [None, "", "failure", "skipped", "cancelled"],
        }.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    status, _, _, transport = execute(extra_env={key: value})
                    self.assertEqual(status, 1)
                    self.assertEqual(transport.requests, [])

    def test_upstream_failure_with_clean_or_empty_output_is_not_recovered(self):
        clean = {"forbidden": [], "unresolved": [], "unlicensed": []}
        for changes in ([], OBSERVED["changes"]):
            status, _, _, transport = execute(changes, clean)
            self.assertEqual(status, 1)
            self.assertEqual(transport.requests, [])
        status, result, _, _ = execute([], clean, extra_env={"DEPENDENCY_REVIEW_OUTCOME": "success"})
        self.assertEqual(status, 0)
        self.assertTrue(result["accepted"])
        self.assertEqual(result["pinned_license_resolutions"], 0)

    def test_no_qualifying_transfer_change_performs_no_lock_or_network_io(self):
        clean = {"forbidden": [], "unresolved": [], "unlicensed": []}
        with patch.object(REVIEW.os, "open", side_effect=AssertionError("unexpected installer IO")) as opened:
            status, result, _, transport = execute(
                [], clean, extra_env={"DEPENDENCY_REVIEW_OUTCOME": "success"}
            )
            self.assertEqual(status, 0)
            self.assertTrue(result["accepted"])
            self.assertEqual(transport.requests, [])
            status, _, _, transport = execute([], clean)
            self.assertEqual(status, 1)
            self.assertEqual(transport.requests, [])
            row = copy.deepcopy(OBSERVED["invalid_licenses"]["forbidden"][0])
            row["manifest"] = "tools/conformance/requirements-lock.txt"
            status, result, _, transport = execute(
                [row], {"forbidden": [row], "unresolved": [], "unlicensed": []}
            )
            self.assertEqual(status, 1)
            self.assertFalse(result["accepted"])
            self.assertEqual(transport.requests, [])
            opened.assert_not_called()

    def test_current_policy_and_project_context_are_required(self):
        for policy in ("", "MIT", "psf-2.0", "PSF-2.0 OR GPL-3.0-only"):
            status, _, _, transport = execute(policy=policy)
            self.assertEqual(status, 1)
            self.assertEqual(transport.requests, [])
        for env in ({"GITHUB_REPOSITORY": "other/repo"}, {"GITHUB_EVENT_NAME": "push"}):
            status, _, diagnostic, transport = execute(extra_env=env)
            self.assertEqual(status, 1)
            self.assertEqual(transport.requests, [])
            self.assertNotIn(TOKEN, diagnostic)

    def test_missing_changed_or_nonregular_installer_rejects_before_network(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            good = root / "good"
            good.write_bytes(LOCK)
            changed = root / "changed"
            changed.write_bytes(bytes([LOCK[0] ^ 1]) + LOCK[1:])
            oversized = root / "oversized"
            oversized.write_bytes(LOCK + b"\n")
            link = root / "link"
            link.symlink_to(good)
            fifo = root / "fifo"
            os.mkfifo(fifo)
            hard = root / "hard"
            os.link(good, hard)
            for path in (root / "missing", root, changed, oversized, link, fifo, hard):
                with self.subTest(path=path.name), patch.object(REVIEW, "TRANSFER_LOCK_PATH", path):
                    status, _, diagnostic, transport = execute()
                    self.assertEqual(status, 1)
                    self.assertEqual(transport.requests, [])
                    self.assertNotIn(str(root), diagnostic)

    def test_changed_truncated_and_excess_artifact_bytes_fail_with_bounded_reads(self):
        for body in (ARTIFACT[:-1], ARTIFACT + b"excess" * 100, bytes([ARTIFACT[0] ^ 1]) + ARTIFACT[1:]):
            transport = Transport(body)
            status, _, diagnostic, _ = execute(transport=transport)
            self.assertEqual(status, 1)
            self.assertNotIn(TOKEN, diagnostic)
            self.assertLessEqual(transport.response.received, len(ARTIFACT) + 1)
            self.assertTrue(all(0 < size <= 16_384 for size in transport.response.requests))

    def test_transport_failure_redirect_and_http_status_cannot_supply_proof(self):
        marker = "PRIVATE-TRANSPORT-DETAIL"
        for transport in (Transport(error=URLError(marker)), Transport(status=403)):
            status, _, diagnostic, _ = execute(transport=transport)
            self.assertEqual(status, 1)
            self.assertNotIn(marker, diagnostic)
            self.assertNotIn(TOKEN, diagnostic)
        with self.assertRaises(REVIEW.InvalidReview):
            REVIEW.PinnedLicenseNoRedirects().redirect_request(
                Request(REVIEW.TRANSFER_WHEEL_URL), None, 302, "redirect", {}, "https://example.invalid/"
            )

    def test_expired_deadline_during_or_after_reading_cannot_supply_proof(self):
        for clock in ([0, 0, 11], [0, 0, 0, 11]):
            with patch.object(REVIEW.time, "monotonic", side_effect=clock):
                status, _, diagnostic, _ = execute()
            self.assertEqual(status, 1)
            self.assertIn("time limit", diagnostic)


if __name__ == "__main__":
    unittest.main()
