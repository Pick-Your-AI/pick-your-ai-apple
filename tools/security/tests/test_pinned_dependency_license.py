"""Retained hosted input and controlled immutable-license transport regressions."""

from __future__ import annotations

import base64
import copy
from contextlib import redirect_stderr, redirect_stdout
import hashlib
from http.client import BadStatusLine, IncompleteRead, LineTooLong
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from urllib.error import URLError
from urllib.request import Request


SCRIPT = Path(__file__).resolve().parents[1] / "check_dependency_review.py"
SPEC = importlib.util.spec_from_file_location("pinned_dependency_review", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
REVIEW = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = REVIEW
SPEC.loader.exec_module(REVIEW)
FIXTURES = Path(__file__).with_name("fixtures")
OBSERVED = json.loads((FIXTURES / "pinned-action-license-gap.json").read_text())
LICENSE = (FIXTURES / "dependency-review-action.LICENSE").read_bytes()
COMMIT = "907a6e9569212033966bc0b69d32473b046dd66b"
URL = f"https://api.github.com/repos/actions/dependency-review-action/contents/LICENSE?ref={COMMIT}"
TOKEN = "SYNTHETIC-READ-ONLY-TOKEN-DO-NOT-ECHO"


def response_document(**overrides: object) -> dict[str, object]:
    return {
        "type": "file", "path": "LICENSE", "name": "LICENSE", "size": len(LICENSE),
        "sha": OBSERVED["upstream_license"]["blob"], "encoding": "base64",
        "content": base64.encodebytes(LICENSE).decode("ascii"), **overrides,
    }


class Response(io.BytesIO):
    status = 200


class Transport:
    def __init__(self, body: bytes | None = None, error: Exception | None = None):
        self.body = body if body is not None else json.dumps(response_document()).encode()
        self.error = error
        self.requests: list[tuple[Request, float]] = []

    def open(self, request: Request, *, timeout: float):
        self.requests.append((request, timeout))
        if self.error is not None:
            raise self.error
        return Response(self.body)


def execute(changes=None, classified=None, *, transport=None, policy="MIT, Apache-2.0", extra_env=None):
    transport = transport if transport is not None else Transport()
    env = {
        "DEPENDENCY_CHANGES": json.dumps(OBSERVED["dependency_changes"] if changes is None else changes),
        "INVALID_LICENSE_CHANGES": json.dumps(OBSERVED["invalid_license_changes"] if classified is None else classified),
        "ALLOWED_DEPENDENCY_LICENSES": policy,
        "DEPENDENCY_REVIEW_TOKEN": TOKEN,
        "GITHUB_REPOSITORY": "Pick-Your-AI/pick-your-ai-apple",
        "GITHUB_EVENT_NAME": "pull_request",
        "DEPENDENCY_REVIEW_OUTCOME": "success",
        "DEPENDENCY_SNAPSHOT_OUTCOME": "success",
        **(extra_env or {}),
    }
    out, err = io.StringIO(), io.StringIO()
    with patch.dict(os.environ, env, clear=True), patch.object(REVIEW, "build_opener", return_value=transport, create=True):
        with redirect_stdout(out), redirect_stderr(err):
            status = REVIEW.main()
    return status, json.loads(out.getvalue()) if out.getvalue() else None, err.getvalue(), transport


class PinnedDependencyLicenseTests(unittest.TestCase):
    def test_observed_license_gap_requires_and_accepts_exact_immutable_proof(self):
        self.assertEqual(hashlib.sha256(LICENSE).hexdigest(), OBSERVED["upstream_license"]["sha256"])
        self.assertEqual(hashlib.sha1(f"blob {len(LICENSE)}\0".encode() + LICENSE).hexdigest(), OBSERVED["upstream_license"]["blob"])
        status, report, diagnostic, transport = execute()
        self.assertEqual(status, 0, diagnostic)
        self.assertTrue(report["accepted"])
        self.assertEqual(report["pinned_license_resolutions"], 1)
        self.assertEqual(report["unlicensed_dependencies"], 0)
        self.assertEqual(report["added_dependencies"], 2)
        self.assertEqual(diagnostic, "")
        self.assertEqual(len(transport.requests), 1)
        request, timeout = transport.requests[0]
        self.assertEqual(request.full_url, URL)
        self.assertEqual(request.get_header("Authorization"), f"Bearer {TOKEN}")
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 10)

    def test_other_identity_license_scope_or_version_is_never_resolved(self):
        mutations = {
            "manifest": ".github/workflows/another.yml", "ecosystem": "npm",
            "name": "other/dependency-review-action", "version": "0" * 40,
            "package_url": f"pkg:githubactions/other/dependency-review-action@{COMMIT}",
            "source_repository_url": "https://github.com/actions/dependency-review-action",
            "license": "GPL-3.0-only", "scope": "development", "change_type": "removed",
        }
        for key, value in mutations.items():
            with self.subTest(key=key):
                changes = copy.deepcopy(OBSERVED["dependency_changes"])
                changes[1][key] = value
                classified = {"unlicensed": [copy.deepcopy(changes[1])], "unresolved": [], "forbidden": []}
                status, report, _, transport = execute(changes, classified)
                self.assertEqual(status, 1)
                self.assertFalse(report["accepted"])
                self.assertEqual(transport.requests, [])

    def test_missing_duplicate_or_inconsistent_raw_change_cannot_borrow_proof(self):
        changes = OBSERVED["dependency_changes"]
        cases = [([], OBSERVED["invalid_license_changes"]),
                 (changes + [copy.deepcopy(changes[1])], OBSERVED["invalid_license_changes"])]
        conflicting = copy.deepcopy(changes)
        conflicting[1]["license"] = "GPL-3.0-only"
        cases.append((conflicting, OBSERVED["invalid_license_changes"]))
        double = copy.deepcopy(OBSERVED["invalid_license_changes"])
        double["unlicensed"].append(copy.deepcopy(double["unlicensed"][0]))
        cases.append((changes, double))
        for raw, classified in cases:
            with self.subTest(raw=raw, classified=classified):
                status, report, _, transport = execute(raw, classified)
                self.assertEqual(status, 1)
                self.assertFalse(report["accepted"])
                self.assertEqual(transport.requests, [])

    def test_other_invalid_categories_and_vulnerabilities_keep_their_rejection(self):
        for category in ("forbidden", "unresolved"):
            classified = copy.deepcopy(OBSERVED["invalid_license_changes"])
            classified[category] = [copy.deepcopy(OBSERVED["dependency_changes"][1])]
            status, report, _, transport = execute(classified=classified)
            self.assertEqual(status, 1)
            self.assertFalse(report["accepted"])
            self.assertEqual(transport.requests, [])
        changes = copy.deepcopy(OBSERVED["dependency_changes"])
        changes[0]["vulnerabilities"] = [{"severity": "low"}]
        status, report, _, transport = execute(changes)
        self.assertEqual(status, 1)
        self.assertEqual(report["vulnerable_dependencies"], 1)
        self.assertEqual(transport.requests, [])

    def test_missing_current_policy_or_project_authority_cannot_resolve_license(self):
        for policy in ("", "Apache-2.0", "MIT OR GPL-3.0-only", "mit"):
            with self.subTest(policy=policy):
                status, report, _, transport = execute(policy=policy)
                self.assertEqual(status, 1)
                self.assertFalse(report["accepted"])
                self.assertEqual(transport.requests, [])
        for env in ({"GITHUB_EVENT_NAME": "push"}, {"GITHUB_REPOSITORY": "other/repo"},
                    {"DEPENDENCY_REVIEW_TOKEN": ""}, {"DEPENDENCY_REVIEW_TOKEN": "bad\nvalue"}):
            status, _, diagnostic, transport = execute(extra_env=env)
            self.assertEqual(status, 1)
            self.assertNotIn(TOKEN, diagnostic)
            self.assertEqual(transport.requests, [])

    def test_license_metadata_bytes_and_unambiguous_json_are_all_required(self):
        documents = [response_document(path="OTHER"), response_document(sha="0" * 40),
                     response_document(type="symlink"), response_document(encoding="utf-8"),
                     response_document(size=True), response_document(size=len(LICENSE) + 1),
                     response_document(content=base64.b64encode(LICENSE + b"changed").decode()),
                     response_document(content="not base64!"), {}, [], None]
        bodies = [json.dumps(doc).encode() for doc in documents]
        bodies.extend([b'{"path":"LICENSE","path":"OTHER"}', b'{"size":NaN}', b" " * 65_537])
        for body in bodies:
            with self.subTest(body=body[:80]):
                status, report, diagnostic, transport = execute(transport=Transport(body))
                self.assertEqual(status, 1)
                self.assertIsNone(report)
                self.assertNotIn(TOKEN, diagnostic)
                self.assertEqual(len(transport.requests), 1)

    def test_transport_failure_or_redirect_never_supplies_license_or_echoes_values(self):
        marker = "PRIVATE-SYNTHETIC-TRANSPORT-DETAIL"
        status, report, diagnostic, _ = execute(transport=Transport(error=URLError(marker)))
        self.assertEqual(status, 1)
        self.assertIsNone(report)
        self.assertNotIn(marker, diagnostic)
        self.assertNotIn(TOKEN, diagnostic)
        request = Request(URL, headers={"Authorization": f"Bearer {TOKEN}"})
        with self.assertRaises(REVIEW.InvalidReview):
            REVIEW.PinnedLicenseNoRedirects().redirect_request(request, None, 302, "redirect", {}, "https://example.invalid/")

    def test_http_protocol_failures_during_open_or_read_do_not_echo_values(self):
        marker = "PRIVATE-SYNTHETIC-HTTP-DETAIL"
        for phase in ("open", "read"):
            for error in (BadStatusLine(marker), LineTooLong(marker), IncompleteRead(marker.encode())):
                with self.subTest(phase=phase, error=type(error).__name__):
                    transport = Transport(error=error if phase == "open" else None)
                    with patch.object(Response, "read1", side_effect=error) as read:
                        status, report, diagnostic, transport = execute(transport=transport)
                    self.assertEqual(status, 1)
                    self.assertIsNone(report)
                    self.assertEqual(len(transport.requests), 1)
                    self.assertEqual(read.call_count, int(phase == "read"))
                    self.assertEqual(
                        diagnostic,
                        "Pinned dependency license could not be verified; no recovery is accepted.\n",
                    )
                    self.assertNotIn(marker, diagnostic)
                    self.assertNotIn(TOKEN, diagnostic)

    def test_unsuccessful_http_or_expired_read_deadline_cannot_supply_proof(self):
        with patch.object(Response, "status", 403):
            status, report, _, transport = execute()
        self.assertEqual(status, 1)
        self.assertIsNone(report)
        self.assertEqual(len(transport.requests), 1)
        with patch.object(REVIEW.time, "monotonic", side_effect=[0, 0, 11]):
            status, report, diagnostic, transport = execute()
        self.assertEqual(status, 1)
        self.assertIsNone(report)
        self.assertIn("time limit", diagnostic)
        self.assertEqual(len(transport.requests), 1)


if __name__ == "__main__":
    unittest.main()
