"""Exact hosted classification and controlled artifact/outcome failure cases.

Transport tests use inert synthetic bytes with a matching test-only digest.
The real immutable wheel is separately downloaded and hashed by the live gate;
no wheel, package code or raw hosted log is committed as a test fixture.
"""

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
SPEC = importlib.util.spec_from_file_location("python_dependency_review", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
REVIEW = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = REVIEW
SPEC.loader.exec_module(REVIEW)
FIXTURES = Path(__file__).with_name("fixtures")
OBSERVED = json.loads((FIXTURES / "typing-extensions-license-classification.json").read_text())
LOCK = REVIEW.TYPING_LOCK_PATH.read_bytes()
SYNTHETIC_ARTIFACT = b"inert synthetic artifact for bounded transport tests; no package code\n"
PRIVATE_MARKER = "SYNTHETIC-PRIVATE-MARKER-DO-NOT-ECHO"


class Response(io.BytesIO):
    def __init__(self, body, status=200):
        super().__init__(body)
        self.status = status


class Transport:
    def __init__(self, body=SYNTHETIC_ARTIFACT, *, status=200, error=None):
        self.body, self.status, self.error = body, status, error
        self.requests = []

    def open(self, request, *, timeout):
        self.requests.append((request, timeout))
        if self.error is not None:
            raise self.error
        return Response(self.body, self.status)


def execute(changes=None, classified=None, *, transport=None, policy="MIT, PSF-2.0", extra_env=None):
    transport = transport if transport is not None else Transport()
    env = {
        "DEPENDENCY_CHANGES": json.dumps(OBSERVED["dependency_changes"] if changes is None else changes),
        "INVALID_LICENSE_CHANGES": json.dumps(OBSERVED["invalid_license_changes"] if classified is None else classified),
        "DEPENDENCY_REVIEW_OUTCOME": "failure",
        "DEPENDENCY_SNAPSHOT_OUTCOME": "success",
        "ALLOWED_DEPENDENCY_LICENSES": policy,
        "DEPENDENCY_REVIEW_TOKEN": PRIVATE_MARKER,
        "GITHUB_REPOSITORY": "Pick-Your-AI/pick-your-ai-apple",
        "GITHUB_EVENT_NAME": "pull_request",
        **(extra_env or {}),
    }
    env = {key: value for key, value in env.items() if value is not None}
    out, err = io.StringIO(), io.StringIO()
    with (
        patch.dict(os.environ, env, clear=True),
        patch.object(REVIEW, "build_opener", return_value=transport),
        patch.object(REVIEW, "TYPING_WHEEL_BYTES", len(SYNTHETIC_ARTIFACT)),
        patch.object(REVIEW, "TYPING_WHEEL_SHA256", hashlib.sha256(SYNTHETIC_ARTIFACT).hexdigest()),
        redirect_stdout(out), redirect_stderr(err),
    ):
        status = REVIEW.main()
    return status, json.loads(out.getvalue()) if out.getvalue() else None, err.getvalue(), transport


class PinnedPythonLicenseTests(unittest.TestCase):
    def assert_rejected_without_lookup(self, *args, **kwargs):
        status, report, diagnostic, transport = execute(*args, **kwargs)
        self.assertEqual(status, 1)
        if report is not None:
            self.assertFalse(report["accepted"])
            self.assertEqual(report["pinned_license_resolutions"], 0)
        self.assertEqual(transport.requests, [])
        self.assertNotIn(PRIVATE_MARKER, diagnostic)

    def test_proof_identity_matches_reviewed_lock_and_primary_provenance(self):
        source = OBSERVED["source_evidence"]
        self.assertEqual(REVIEW.TYPING_MANIFEST, source["lock_path"])
        self.assertEqual(len(LOCK), REVIEW.TYPING_LOCK_BYTES)
        self.assertEqual(hashlib.sha256(LOCK).hexdigest(), REVIEW.TYPING_LOCK_SHA256)
        self.assertEqual(REVIEW.TYPING_LOCK_SHA256, source["lock_sha256"])
        self.assertEqual(REVIEW.TYPING_WHEEL_URL, source["wheel"]["url"])
        self.assertEqual(REVIEW.TYPING_WHEEL_BYTES, source["wheel"]["bytes"])
        self.assertEqual(REVIEW.TYPING_WHEEL_SHA256, source["wheel"]["sha256"])
        provenance = json.loads(REVIEW.TYPING_LOCK_PATH.with_name("requirements-provenance.json").read_text())
        package = next(p for p in provenance["packages"] if p["name"] == "typing-extensions")
        self.assertEqual(package["license_expression"], "PSF-2.0")
        self.assertEqual(package["wheels"], [source["wheel"]])

    def test_observed_forbidden_row_recovers_only_after_exact_proof(self):
        result = REVIEW.evaluate(OBSERVED["dependency_changes"], OBSERVED["invalid_license_changes"])
        self.assertFalse(result.accepted)
        self.assertEqual(result.disallowed_licenses, 1)
        status, report, diagnostic, transport = execute()
        self.assertEqual(status, 0, diagnostic)
        self.assertTrue(report["accepted"])
        self.assertEqual(report["added_dependencies"], 7)
        self.assertEqual(report["disallowed_licenses"], 0)
        self.assertEqual(report["pinned_license_resolutions"], 1)
        self.assertEqual(diagnostic, "")
        self.assertEqual(len(transport.requests), 1)
        request, timeout = transport.requests[0]
        self.assertEqual(request.full_url, OBSERVED["source_evidence"]["wheel"]["url"])
        self.assertEqual(request.get_method(), "GET")
        self.assertIsNone(request.get_header("Authorization"))
        self.assertIsNone(request.get_header("Cookie"))
        self.assertNotIn(PRIVATE_MARKER, str(request.header_items()))
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 10)

    def test_normal_success_remains_independent_of_the_exception(self):
        rows = copy.deepcopy(OBSERVED["dependency_changes"])
        rows[-1]["license"] = "PSF-2.0"
        clean = {"forbidden": [], "unlicensed": [], "unresolved": []}
        for changes in (rows, []):
            with self.subTest(changes=len(changes)):
                status, report, diagnostic, transport = execute(
                    changes, clean, extra_env={"DEPENDENCY_REVIEW_OUTCOME": "success"}
                )
                self.assertEqual(status, 0, diagnostic)
                self.assertTrue(report["accepted"])
                self.assertEqual(report["pinned_license_resolutions"], 0)
                self.assertEqual(transport.requests, [])

    def test_failed_upstream_with_clean_or_empty_output_is_not_success(self):
        clean = {"forbidden": [], "unlicensed": [], "unresolved": []}
        for rows in ([], OBSERVED["dependency_changes"]):
            with self.subTest(rows=len(rows)):
                self.assert_rejected_without_lookup(rows, clean)
        self.assert_rejected_without_lookup(extra_env={"DEPENDENCY_REVIEW_OUTCOME": "success"})

    def test_all_missing_or_incomplete_outcomes_fail_before_lookup(self):
        for value in (None, "", "cancelled", "skipped", "neutral", "SUCCESS"):
            for field in ("DEPENDENCY_REVIEW_OUTCOME", "DEPENDENCY_SNAPSHOT_OUTCOME"):
                with self.subTest(field=field, value=value):
                    self.assert_rejected_without_lookup(extra_env={field: value})
        self.assert_rejected_without_lookup(extra_env={"DEPENDENCY_SNAPSHOT_OUTCOME": "failure"})

    def test_policy_and_repository_authority_are_required(self):
        for policy in ("", "MIT, Python-2.0", "PSF-2.0 OR GPL-3.0-only", "psf-2.0"):
            with self.subTest(policy=policy):
                self.assert_rejected_without_lookup(policy=policy)
        for field, value in (
            ("GITHUB_REPOSITORY", "other/repository"),
            ("GITHUB_EVENT_NAME", "pull_request_target"),
            ("GITHUB_EVENT_NAME", "push"),
            ("GITHUB_REPOSITORY", None),
        ):
            with self.subTest(field=field, value=value):
                self.assert_rejected_without_lookup(extra_env={field: value})

    def test_other_versions_licenses_manifests_and_scopes_cannot_borrow_proof(self):
        mutations = {
            "change_type": "removed", "manifest": "other/requirements-lock.txt",
            "ecosystem": "npm", "name": "typing_extensions", "version": "4.17.0",
            "package_url": "pkg:pypi/typing-extensions@4.17.0",
            "license": "GPL-1.0-or-later", "source_repository_url": "https://github.com/python/typing_extensions",
            "scope": "development", "extra": PRIVATE_MARKER,
        }
        for field, value in mutations.items():
            with self.subTest(field=field):
                rows = copy.deepcopy(OBSERVED["dependency_changes"])
                rows[-1][field] = value
                classified = {"forbidden": [copy.deepcopy(rows[-1])], "unlicensed": [], "unresolved": []}
                self.assert_rejected_without_lookup(rows, classified)

    def test_missing_duplicate_and_conflicting_rows_cannot_borrow_proof(self):
        rows = OBSERVED["dependency_changes"]
        self.assert_rejected_without_lookup(rows[:-1])
        self.assert_rejected_without_lookup(rows + [copy.deepcopy(rows[-1])])
        conflicting = copy.deepcopy(rows[-1])
        conflicting["manifest"] = "another/requirements.txt"
        self.assert_rejected_without_lookup(rows + [conflicting])
        classified = copy.deepcopy(OBSERVED["invalid_license_changes"])
        classified["forbidden"].append(copy.deepcopy(rows[-1]))
        self.assert_rejected_without_lookup(classified=classified)
        mismatched = copy.deepcopy(rows)
        mismatched[-1]["license"] = "PSF-2.0"
        self.assert_rejected_without_lookup(mismatched)

    def test_other_invalid_categories_and_vulnerabilities_keep_rejection(self):
        for category in ("forbidden", "unlicensed", "unresolved"):
            classified = copy.deepcopy(OBSERVED["invalid_license_changes"])
            classified[category].append(copy.deepcopy(OBSERVED["dependency_changes"][0]))
            with self.subTest(category=category):
                self.assert_rejected_without_lookup(classified=classified)
        for index in (0, 6):
            rows = copy.deepcopy(OBSERVED["dependency_changes"])
            rows[index]["vulnerabilities"] = [{"severity": "low", "message": PRIVATE_MARKER}]
            self.assert_rejected_without_lookup(rows)
        action = json.loads((FIXTURES / "pinned-action-license-gap.json").read_text())
        self.assert_rejected_without_lookup(action["dependency_changes"], action["invalid_license_changes"])

    def test_changed_or_nonregular_installer_fails_before_lookup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "lock.txt"
            with patch.object(REVIEW, "TYPING_LOCK_PATH", path):
                self.assert_rejected_without_lookup()
                for data in (LOCK + b"\n", b"x" + LOCK[1:], b""):
                    path.write_bytes(data)
                    self.assert_rejected_without_lookup()
                path.unlink()
                path.mkdir()
                self.assert_rejected_without_lookup()
                path.rmdir()
                target = root / "target.txt"
                target.write_bytes(LOCK)
                path.symlink_to(target)
                self.assert_rejected_without_lookup()
                path.unlink()
                os.link(target, path)
                self.assert_rejected_without_lookup()
                path.unlink()
                os.mkfifo(path)
                self.assert_rejected_without_lookup()
                path.unlink()
                path.write_bytes(LOCK)
                status, report, diagnostic, _ = execute()
                self.assertEqual(status, 0, diagnostic)
                self.assertTrue(report["accepted"])
                self.assertEqual(target.read_bytes(), LOCK)

    def test_artifact_truncation_expansion_and_changed_bytes_fail_closed(self):
        for body in (SYNTHETIC_ARTIFACT[:-1], SYNTHETIC_ARTIFACT + b"x", b"x" + SYNTHETIC_ARTIFACT[1:]):
            with self.subTest(size=len(body)):
                status, report, diagnostic, transport = execute(transport=Transport(body))
                self.assertEqual(status, 1)
                self.assertIsNone(report)
                self.assertEqual(len(transport.requests), 1)
                self.assertNotIn(PRIVATE_MARKER, diagnostic)

    def test_transport_errors_status_and_redirect_never_supply_proof(self):
        for transport in (
            Transport(status=206), Transport(status=403),
            Transport(error=URLError(PRIVATE_MARKER)), Transport(error=OSError(PRIVATE_MARKER)),
        ):
            status, report, diagnostic, _ = execute(transport=transport)
            self.assertEqual(status, 1)
            self.assertIsNone(report)
            self.assertNotIn(PRIVATE_MARKER, diagnostic)
        handler = REVIEW.PinnedLicenseNoRedirects()
        request = Request(REVIEW.TYPING_WHEEL_URL)
        with self.assertRaises(REVIEW.InvalidReview):
            handler.redirect_request(request, None, 302, "redirect", {}, "https://untrusted.invalid/" + PRIVATE_MARKER)
        with patch.object(REVIEW.os, "open", side_effect=PermissionError(PRIVATE_MARKER)):
            self.assert_rejected_without_lookup()

    def test_expired_stream_and_completion_deadlines_fail_closed(self):
        for times in ([0, 11], [0, 0, 11], [0, 0, 0, 11]):
            with self.subTest(times=times), patch.object(REVIEW.time, "monotonic", side_effect=times):
                status, report, diagnostic, _ = execute()
                self.assertEqual(status, 1)
                self.assertIsNone(report)
                self.assertNotIn(PRIVATE_MARKER, diagnostic)


if __name__ == "__main__":
    unittest.main()
