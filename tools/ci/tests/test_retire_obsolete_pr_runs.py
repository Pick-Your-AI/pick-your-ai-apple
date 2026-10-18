import contextlib
import copy
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import Mock, patch
import urllib.error
import urllib.parse


SPEC = importlib.util.spec_from_file_location(
    "retire_obsolete_pr_runs", Path(__file__).resolve().parents[1] / "retire_obsolete_pr_runs.py"
)
cleanup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cleanup)
OLD = "a" * 40
NEW = "b" * 40
REPO = {"id": cleanup.REPOSITORY_ID, "full_name": cleanup.REPOSITORY}


def pr(number=7, *, sha=NEW, state="open", branch="candidate/example"):
    return {
        "number": number, "state": state,
        "head": {"sha": sha, "ref": branch, "repo": dict(REPO)},
        "base": {"ref": "main", "repo": dict(REPO)},
    }


def run(number=100, *, sha=OLD, association=True, branch="candidate/example"):
    return {
        "id": number, "event": "pull_request", "status": "queued", "conclusion": None,
        "run_attempt": 1, "path": ".github/workflows/swift-storage.yml",
        "repository": dict(REPO), "head_repository": dict(REPO),
        "head_sha": sha, "head_branch": branch,
        "pull_requests": [pr(sha=sha, branch=branch)] if association else [],
        "cancel_url": "https://untrusted.example/never-follow-this",
    }


class FakeAPI:
    def __init__(self, runs, prs):
        self.runs = copy.deepcopy(runs)
        self.prs = copy.deepcopy(prs)
        self.calls = []
        self.run_preflight = {}
        self.pr_reads = {}
        self.open_reads = None
        self.pages = {}
        self.cancel_result = True

    def request(self, path, *, cancel=False):
        self.calls.append((path, cancel))
        if cancel:
            return self.cancel_result
        parsed = urllib.parse.urlsplit(path)
        query = urllib.parse.parse_qs(parsed.query)
        leaf = parsed.path.removeprefix(cleanup.PREFIX)
        if leaf == "/actions/runs":
            status, page = query["status"][0], int(query["page"][0])
            values = self.pages.get((status, page))
            if values is None:
                values = [r for r in self.runs if r.get("status") == status]
                values = values[(page - 1) * 100:page * 100]
            return {"workflow_runs": copy.deepcopy(values)}
        if leaf.startswith("/actions/runs/"):
            number = int(leaf.rsplit("/", 1)[1])
            return copy.deepcopy(self.run_preflight.get(number, next(r for r in self.runs if r["id"] == number)))
        if leaf == "/pulls":
            if query["state"] == ["open"]:
                if self.open_reads:
                    return copy.deepcopy(self.open_reads.pop(0))
                values = [p for p in self.prs if p["state"] == "open"]
                page = int(query["page"][0])
                return copy.deepcopy(values[(page - 1) * 100:page * 100])
            branch = query["head"][0].split(":", 1)[1]
            return copy.deepcopy([p for p in self.prs if p["head"]["ref"] == branch])
        if leaf.startswith("/pulls/"):
            number = int(leaf.rsplit("/", 1)[1])
            if self.pr_reads.get(number):
                return copy.deepcopy(self.pr_reads[number].pop(0))
            return copy.deepcopy(next(p for p in self.prs if p["number"] == number))
        raise AssertionError(f"Unexpected test API path: {path}")

    @property
    def cancelled(self):
        return [path for path, cancel in self.calls if cancel]


class SelectionTests(unittest.TestCase):
    def execute(self, api, *, apply=True):
        messages = []
        result = cleanup.retire(api, apply=apply, emit=messages.append)
        return result, messages

    def test_only_superseded_first_attempt_is_cancelled(self):
        old, current = run(), run(101, sha=NEW)
        api = FakeAPI([old, current], [pr()])
        count, messages = self.execute(api)
        self.assertEqual(count, 1)
        self.assertEqual(api.cancelled, [f"{cleanup.PREFIX}/actions/runs/100/cancel"])
        self.assertIn("superseded PR head", messages[0])
        self.assertFalse(any("untrusted.example" in path for path, _ in api.calls))

    def test_compact_github_run_association_needs_no_full_pr_fields(self):
        candidate = run()
        association = candidate["pull_requests"][0]
        del association["state"]
        del association["base"]["repo"]["full_name"]
        del association["head"]["repo"]["full_name"]
        api = FakeAPI([candidate], [pr()])
        self.assertEqual(self.execute(api)[0], 1)

    def test_closed_pr_with_missing_association_requires_exact_unique_match(self):
        api = FakeAPI([run(association=False)], [pr(sha=OLD, state="closed")])
        count, messages = self.execute(api)
        self.assertEqual(count, 1)
        self.assertIn("closed PR", messages[0])
        for values in (
            [pr(sha=NEW, state="closed")],
            [pr(sha=OLD, state="open")],
            [pr(sha=OLD, state="closed"), pr(8, sha=OLD, state="closed")],
            [],
        ):
            with self.subTest(prs=values):
                api = FakeAPI([run(association=False)], values)
                self.assertEqual(self.execute(api)[0], 0)
                self.assertFalse(api.cancelled)

    def test_current_head_on_another_pr_or_fork_is_preserved(self):
        for foreign in (False, True):
            live = pr(8, sha=OLD, branch="other/candidate")
            if foreign:
                live["head"]["repo"] = {"id": 123, "full_name": "someone/fork"}
            api = FakeAPI([run()], [pr(state="closed"), live])
            self.assertEqual(self.execute(api)[0], 0)
            self.assertFalse(api.cancelled)

    def test_push_main_manual_rerun_and_unknown_run_metadata_are_preserved(self):
        variants = (
            {"event": "push"}, {"event": "workflow_dispatch"}, {"event": "pull_request_target"},
            {"head_branch": "main"}, {"run_attempt": 2}, {"run_attempt": True},
            {"head_repository": {"id": 123}}, {"repository": {"id": 123}},
            {"repository": {"id": cleanup.REPOSITORY_ID, "full_name": "other/repo"}},
            {"path": ".github/workflows/unknown.yml"}, {"path": []},
            {"status": "completed"}, {"status": []}, {"conclusion": "success"},
            {"id": True}, {"head_sha": "bad"}, {"head_branch": ""},
            {"pull_requests": None}, {"pull_requests": [None]},
            {"pull_requests": [pr(), pr(8)]},
        )
        for changed in variants:
            with self.subTest(changed=changed):
                candidate = run()
                candidate.update(changed)
                api = FakeAPI([candidate], [pr(state="closed")])
                self.assertEqual(self.execute(api)[0], 0)
                self.assertFalse(api.cancelled)

    def test_reopened_or_reverted_pr_at_final_read_is_preserved(self):
        for original in (pr(sha=OLD, state="closed"), pr(sha=NEW)):
            api = FakeAPI([run()], [original])
            api.pr_reads[7] = [original, pr(sha=OLD)]
            self.assertEqual(self.execute(api)[0], 0)
            self.assertFalse(api.cancelled)

    def test_open_head_list_is_refreshed_for_each_cancellation(self):
        api = FakeAPI([run()], [pr(state="closed")])
        api.open_reads = [[], [pr(8, sha=OLD, branch="new/current")]]
        self.assertEqual(self.execute(api)[0], 0)
        self.assertFalse(api.cancelled)

    def test_completed_rerun_or_changed_run_at_preflight_is_preserved(self):
        for changed in (
            {"status": "completed", "conclusion": "success"}, {"run_attempt": 2},
            {"head_sha": NEW}, {"head_branch": "another/branch"},
            {"path": ".github/workflows/swift-core.yml"}, {"pull_requests": [pr(8)]},
            {"pull_requests": [pr(), pr(8)]},
        ):
            with self.subTest(changed=changed):
                api = FakeAPI([run()], [pr(state="closed")])
                latest = run()
                latest.update(changed)
                api.run_preflight[100] = latest
                self.assertEqual(self.execute(api)[0], 0)
                self.assertFalse(api.cancelled)

    def test_foreign_or_mismatched_pr_cannot_authorize_cancellation(self):
        for changed in ("head_repo", "base_repo", "number", "branch", "sha"):
            with self.subTest(changed=changed):
                value = pr(state="closed")
                if changed.endswith("repo"):
                    value[changed.split("_")[0]]["repo"] = {"id": 123}
                elif changed == "number":
                    value["number"] = True
                else:
                    value["head"]["ref" if changed == "branch" else "sha"] = "different"
                api = FakeAPI([run()], [pr(state="closed")])
                api.pr_reads[7] = [value]
                self.assertEqual(self.execute(api)[0], 0)
                self.assertFalse(api.cancelled)

    def test_all_run_pages_are_read_before_first_mutation(self):
        api = FakeAPI([run()], [pr(state="closed")])
        api.pages[("queued", 1)] = [dict(run(i + 1000), event="push") for i in range(100)]
        api.pages[("queued", 2)] = [run()]
        self.assertEqual(self.execute(api)[0], 1)
        mutation = next(i for i, (_, cancel) in enumerate(api.calls) if cancel)
        listing = [i for i, (path, _) in enumerate(api.calls) if "/actions/runs?" in path]
        self.assertTrue(all(i < mutation for i in listing))
        self.assertTrue(any("status=queued&per_page=100&page=2" in path for path, _ in api.calls))

    def test_incomplete_run_or_open_pr_pagination_stops_before_mutation(self):
        api = FakeAPI([run()], [pr(state="closed")])
        api.pages[("queued", 1)] = [run(i + 1000) for i in range(100)]
        with patch.object(cleanup, "MAX_PAGES", 1), self.assertRaises(cleanup.SafetyError):
            self.execute(api)
        self.assertFalse(api.cancelled)
        api = FakeAPI([run()], [pr(state="closed")])
        api.open_reads = [[pr(i + 100, sha=NEW) for i in range(100)]]
        with patch.object(cleanup, "MAX_PAGES", 1), self.assertRaises(cleanup.SafetyError):
            self.execute(api)
        self.assertFalse(api.cancelled)

    def test_malformed_open_pr_listing_stops_before_mutation(self):
        api = FakeAPI([run()], [pr(state="closed")])
        api.open_reads = [[{"head": {"sha": "unreadable"}}]]
        with self.assertRaises(cleanup.SafetyError):
            self.execute(api)
        self.assertFalse(api.cancelled)

    def test_cancellation_count_is_bounded(self):
        api = FakeAPI([run(i) for i in range(100, 103)], [pr(state="closed")])
        with patch.object(cleanup, "MAX_CANCELLATIONS", 2):
            self.assertEqual(self.execute(api)[0], 2)
        self.assertEqual(len(api.cancelled), 2)

    def test_preview_and_conflict_never_escalate_or_retry(self):
        api = FakeAPI([run()], [pr(state="closed")])
        count, messages = self.execute(api, apply=False)
        self.assertEqual(count, 0)
        self.assertFalse(api.cancelled)
        self.assertIn("Would request", messages[0])
        api.cancel_result = False
        count, messages = self.execute(api)
        self.assertEqual(count, 0)
        self.assertEqual(len(api.cancelled), 1)
        self.assertIn("without retry", messages[0])


class TransportTests(unittest.TestCase):
    def client(self):
        client = cleanup.GitHub("synthetic-test-token")
        client.opener = Mock()
        return client

    def response(self, *, status=200, body=b"{}"):
        response = Mock(status=status)
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.read.return_value = body
        return response

    def test_fixed_endpoint_and_ordinary_post(self):
        client = self.client()
        client.opener.open.return_value = self.response(status=202)
        self.assertTrue(client.request(f"{cleanup.PREFIX}/actions/runs/123/cancel", cancel=True))
        request = client.opener.open.call_args.args[0]
        self.assertEqual(request.full_url, f"https://api.github.com{cleanup.PREFIX}/actions/runs/123/cancel")
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(client.opener.open.call_args.kwargs, {"timeout": 10})
        self.assertIsNone(cleanup.NoRedirect().redirect_request(None, None, 302, "", {}, "https://other.example"))

    def test_other_repository_force_cancel_and_path_traversal_are_refused(self):
        client = self.client()
        for path, cancel in (
            ("https://other.example/cancel", True),
            ("/repos/other/repo/actions/runs/123/cancel", True),
            (f"{cleanup.PREFIX}/actions/runs/123/force-cancel", True),
            (f"{cleanup.PREFIX}/../other/actions/runs/123", False),
            (f"{cleanup.PREFIX}/actions/runs/123/logs", False),
            (f"{cleanup.PREFIX}/actions/runs/123/artifacts", False),
        ):
            with self.subTest(path=path), self.assertRaises(cleanup.SafetyError):
                client.request(path, cancel=cancel)
        client.opener.open.assert_not_called()

    def test_http_conflict_returns_without_force_cancellation(self):
        client = self.client()
        client.opener.open.side_effect = urllib.error.HTTPError("synthetic", 409, "conflict", {}, None)
        self.assertFalse(client.request(f"{cleanup.PREFIX}/actions/runs/123/cancel", cancel=True))
        self.assertEqual(client.opener.open.call_count, 1)

    def test_redirect_permission_and_network_errors_do_not_expose_details(self):
        for error in (
            urllib.error.HTTPError("synthetic", 302, "synthetic-test-token", {}, io.BytesIO(b"private response")),
            urllib.error.HTTPError("synthetic", 403, "synthetic-test-token", {}, io.BytesIO(b"private response")),
            urllib.error.URLError("synthetic-test-token"),
        ):
            with self.subTest(kind=type(error).__name__):
                client = self.client()
                client.opener.open.side_effect = error
                with self.assertRaises(cleanup.SafetyError) as raised:
                    client.request(f"{cleanup.PREFIX}/pulls/7")
                self.assertNotIn("synthetic-test-token", str(raised.exception))
                self.assertNotIn("private response", str(raised.exception))
                self.assertEqual(client.opener.open.call_count, 1)

    def test_response_size_json_and_request_time_budgets_fail_closed(self):
        client = self.client()
        client.opener.open.return_value = self.response(body=b"x" * 9)
        with patch.object(cleanup, "MAX_RESPONSE_BYTES", 8), self.assertRaises(cleanup.SafetyError):
            client.request(f"{cleanup.PREFIX}/pulls/7")
        client.opener.open.return_value = self.response(body=b"not json")
        with self.assertRaises(cleanup.SafetyError):
            client.request(f"{cleanup.PREFIX}/pulls/7")
        for key, value in (("requests_left", 0), ("deadline", 0)):
            client = self.client()
            setattr(client, key, value)
            with self.assertRaises(cleanup.SafetyError):
                client.request(f"{cleanup.PREFIX}/pulls/7")
            client.opener.open.assert_not_called()

    def test_apply_refuses_wrong_repository_branch_or_pr_event_before_network(self):
        valid = {
            "GITHUB_REPOSITORY": cleanup.REPOSITORY,
            "GITHUB_REF": "refs/heads/main", "GITHUB_EVENT_NAME": "push",
        }
        for key, value in (
            ("GITHUB_REPOSITORY", "other/repo"), ("GITHUB_REF", "refs/heads/candidate"),
            ("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_EVENT_NAME", "pull_request_target"),
        ):
            env = dict(valid)
            env[key] = value
            with self.subTest(key=key, value=value), patch.dict(cleanup.os.environ, env, clear=True), \
                 patch.object(cleanup.sys, "argv", ["retire", "--apply"]), \
                 patch.object(cleanup, "GitHub") as client, contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(cleanup.main(), 1)
                client.assert_not_called()


if __name__ == "__main__":
    unittest.main()
