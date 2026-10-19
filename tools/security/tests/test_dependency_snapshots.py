"""Controlled HTTP metadata/identity regressions; no GitHub request is made."""

from __future__ import annotations

import base64
from contextlib import redirect_stderr, redirect_stdout
from email.message import Message
from http.client import BadStatusLine, IncompleteRead, LineTooLong
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.request import Request


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("dependency_snapshots", SCRIPTS / "check_dependency_snapshots.py")
assert SPEC is not None and SPEC.loader is not None
SNAPSHOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SNAPSHOT)

BASE, HEAD = "a" * 40, "b" * 40


def dependency(**overrides: object) -> dict[str, object]:
    return {
        "change_type": "added", "manifest": "synthetic/requirements.txt", "ecosystem": "pip",
        "name": "synthetic-review-fixture", "version": "1.0.1",
        "package_url": "pkg:pypi/synthetic-review-fixture@1.0.1", "license": "MIT",
        "source_repository_url": None, "scope": "development", "vulnerabilities": [],
        **overrides,
    }


def event() -> dict[str, object]:
    return {
        "repository": {"full_name": SNAPSHOT.REPOSITORY},
        "pull_request": {
            "base": {"sha": BASE, "repo": {"full_name": SNAPSHOT.REPOSITORY}},
            "head": {"sha": HEAD},
        },
    }


class Pages:
    def __init__(self, pages):
        self.pages = iter(pages)
        self.urls = []

    def __call__(self, url):
        self.urls.append(url)
        headers, rows = next(self.pages)
        return headers, json.dumps(rows).encode("utf-8")


class DependencySnapshotTests(unittest.TestCase):
    def test_uses_event_base_and_head_commits_and_rejects_other_repository_or_bad_sha(self) -> None:
        self.assertEqual(SNAPSHOT.event_range(event()), (BASE, HEAD))
        for modified in (None, {}, {"repository": {"full_name": "other/repo"}}):
            with self.assertRaises(SNAPSHOT.InvalidReview):
                SNAPSHOT.event_range(modified)
        for field in ("base", "head"):
            for sha in ("main", "a" * 39, "A" * 40, "../outside", None):
                changed = event()
                changed["pull_request"][field]["sha"] = sha
                with self.assertRaises(SNAPSHOT.InvalidReview):
                    SNAPSHOT.event_range(changed)
        changed = event()
        changed["pull_request"]["base"]["repo"]["full_name"] = "other/repo"
        with self.assertRaises(SNAPSHOT.InvalidReview):
            SNAPSHOT.event_range(changed)

    def test_explicit_empty_and_complete_nonempty_comparisons_match(self) -> None:
        for rows in ([], [dependency()]):
            fetch = Pages([({}, rows)])
            self.assertEqual(SNAPSHOT.verify_comparison(BASE, HEAD, rows, fetch), len(rows))
            self.assertEqual(fetch.urls, [SNAPSHOT.comparison_url(BASE, HEAD, 1)])

    def test_later_snapshot_cannot_make_an_earlier_partial_action_result_pass(self) -> None:
        for reviewed, observed in (([], [dependency()]), ([dependency()], [])):
            with self.assertRaises(SNAPSHOT.InvalidReview):
                SNAPSHOT.verify_comparison(BASE, HEAD, reviewed, Pages([({}, observed)]))

    def test_changed_advisory_license_scope_or_identity_requires_fresh_review(self) -> None:
        vulnerability = {"severity": "critical", "advisory_ghsa_id": "synthetic-advisory",
                         "advisory_summary": "synthetic", "advisory_url": "https://example.invalid/advisory"}
        for change in ({"license": None}, {"scope": "runtime"}, {"version": "1.0.2"},
                       {"vulnerabilities": [vulnerability]}):
            with self.subTest(change=change):
                with self.assertRaises(SNAPSHOT.InvalidReview):
                    SNAPSHOT.verify_comparison(BASE, HEAD, [dependency()], Pages([({}, [dependency(**change)])]))

    def test_pending_or_invalid_warning_metadata_fails_and_empty_warning_passes(self) -> None:
        SNAPSHOT.require_no_snapshot_warnings(None)
        SNAPSHOT.require_no_snapshot_warnings("")
        SNAPSHOT.require_no_snapshot_warnings(base64.b64encode(b"  ").decode())
        for header in ("not base64!", base64.b64encode(b"pending").decode(), base64.b64encode(b"\xff").decode()):
            with self.subTest(header=header):
                with self.assertRaises(SNAPSHOT.InvalidReview):
                    SNAPSHOT.require_no_snapshot_warnings(header)

    def test_every_page_warning_is_checked_and_rows_can_reorder(self) -> None:
        a, b = dependency(), dependency(name="synthetic-second")
        next_link = f'<{SNAPSHOT.comparison_url(BASE, HEAD, 2)}>; rel="next"'
        fetch = Pages([({"link": next_link}, [a]), ({}, [b])])
        self.assertEqual(SNAPSHOT.verify_comparison(BASE, HEAD, [b, a], fetch), 2)
        warning = base64.b64encode(b"still pending on second page").decode()
        with self.assertRaises(SNAPSHOT.InvalidReview):
            SNAPSHOT.verify_comparison(BASE, HEAD, [a, b], Pages([
                ({"link": next_link}, [a]), ({SNAPSHOT.WARNINGS_HEADER: warning}, [b]),
            ]))

    def test_pagination_cannot_change_host_ref_page_or_add_a_fragment(self) -> None:
        url = SNAPSHOT.comparison_url(BASE, HEAD, 2)
        unsafe = [url.replace("api.github.com", "example.invalid"), url.replace(HEAD, "c" * 40),
                  url.replace("page=2", "page=1"), url + "#fragment", url + "&extra=value", url + "&extra="]
        for target in unsafe:
            with self.subTest(target=target):
                fetch = Pages([({"link": f'<{target}>; rel="next"'}, [])])
                with self.assertRaises(SNAPSHOT.InvalidReview):
                    SNAPSHOT.verify_comparison(BASE, HEAD, [], fetch)
                self.assertEqual(len(fetch.urls), 1)
        for header in ("broken pagination", f'<{url}>; rel="next", <{url}>; rel="next"'):
            with self.assertRaises(SNAPSHOT.InvalidReview):
                SNAPSHOT.has_next_page(header, url)

    def test_pagination_and_byte_bounds_fail_without_accepting_a_partial_diff(self) -> None:
        pages = [({"link": f'<{SNAPSHOT.comparison_url(BASE, HEAD, n + 1)}>; rel="next"'}, [])
                 for n in range(1, SNAPSHOT.MAXIMUM_PAGES + 1)]
        with self.assertRaises(SNAPSHOT.InvalidReview):
            SNAPSHOT.verify_comparison(BASE, HEAD, [], Pages(pages))
        with self.assertRaises(SNAPSHOT.InvalidReview):
            SNAPSHOT.verify_comparison(BASE, HEAD, [], lambda _: ({}, b" " * (SNAPSHOT.MAXIMUM_BYTES + 1)))
        with self.assertRaises(SNAPSHOT.InvalidReview):
            SNAPSHOT.verify_comparison(BASE, HEAD, [], Pages([({}, [dependency()] * 101)]))

    def test_normalization_matches_pinned_defaults_without_hiding_missing_action_data(self) -> None:
        raw = dependency()
        del raw["scope"]
        del raw["vulnerabilities"]
        reviewed = {**raw, "vulnerabilities": []}
        self.assertEqual(SNAPSHOT.verify_comparison(BASE, HEAD, [reviewed], Pages([({}, [raw])])), 1)
        with self.assertRaises(SNAPSHOT.InvalidReview):
            SNAPSHOT.normalized_changes([raw], raw_api=False)
        for key in ("name", "package_url", "license", "source_repository_url"):
            missing = dependency()
            del missing[key]
            with self.assertRaises(SNAPSHOT.InvalidReview):
                SNAPSHOT.normalized_changes([missing], raw_api=True)

    def test_redirect_never_forwards_token_and_cli_failure_does_not_echo_values(self) -> None:
        marker = "PRIVATE-SYNTHETIC-TOKEN-DO-NOT-ECHO"
        request = Request(SNAPSHOT.comparison_url(BASE, HEAD, 1), headers={"Authorization": marker})
        with self.assertRaises(SNAPSHOT.InvalidReview) as caught:
            SNAPSHOT.NoRedirects().redirect_request(request, None, 302, "redirect", {}, "https://example.invalid/")
        self.assertNotIn(marker, str(caught.exception))
        out, err = io.StringIO(), io.StringIO()
        with patch.dict(os.environ, {"GITHUB_EVENT_NAME": "push", "DEPENDENCY_REVIEW_TOKEN": marker}, clear=True):
            with redirect_stdout(out), redirect_stderr(err):
                self.assertEqual(SNAPSHOT.main(), 1)
        self.assertNotIn(marker, out.getvalue() + err.getvalue())
        self.assertEqual(out.getvalue(), "")

    def test_http_protocol_failures_during_open_or_read_do_not_echo_values(self) -> None:
        marker = "PRIVATE-SYNTHETIC-HTTP-DETAIL"
        token = "PRIVATE-SYNTHETIC-TOKEN-DO-NOT-ECHO"
        with tempfile.TemporaryDirectory() as temporary:
            event_path = Path(temporary) / "event.json"
            event_path.write_text(json.dumps(event()), encoding="utf-8")
            env = {
                "GITHUB_EVENT_NAME": "pull_request", "GITHUB_REPOSITORY": SNAPSHOT.REPOSITORY,
                "GITHUB_EVENT_PATH": str(event_path), "DEPENDENCY_REVIEW_TOKEN": token,
                "DEPENDENCY_CHANGES": json.dumps([dependency()]),
            }
            for phase in ("open", "read"):
                for error in (BadStatusLine(marker), LineTooLong(marker), IncompleteRead(marker.encode())):
                    with self.subTest(phase=phase, error=type(error).__name__):
                        response = io.BytesIO(json.dumps([dependency()]).encode())
                        response.status, response.headers = 200, Message()
                        response.read1 = Mock(side_effect=error)
                        opener = Mock()
                        opener.open.side_effect = error if phase == "open" else None
                        opener.open.return_value = response
                        out, err = io.StringIO(), io.StringIO()
                        with (
                            patch.dict(os.environ, env, clear=True),
                            patch.object(SNAPSHOT, "build_opener", return_value=opener),
                            redirect_stdout(out), redirect_stderr(err),
                        ):
                            self.assertEqual(SNAPSHOT.main(), 1)
                        self.assertEqual(opener.open.call_count, 1)
                        self.assertEqual(response.read1.call_count, int(phase == "read"))
                        self.assertEqual(out.getvalue(), "")
                        self.assertEqual(
                            err.getvalue(),
                            "Dependency snapshot verification failed; no complete matching review is established.\n",
                        )
                        self.assertNotIn(marker, err.getvalue())
                        self.assertNotIn(token, err.getvalue())


if __name__ == "__main__":
    unittest.main()
