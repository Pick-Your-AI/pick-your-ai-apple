#!/usr/bin/env python3
"""Request ordinary cancellation only for proven obsolete first-attempt PR runs."""

import argparse
import http.client
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


REPOSITORY = "Pick-Your-AI/pick-your-ai-apple"
REPOSITORY_ID = 1422897390
API_ROOT = "https://api.github.com"
PREFIX = f"/repos/{REPOSITORY}"
WORKFLOWS = frozenset(
    f".github/workflows/{name}.yml"
    for name in (
        "catalog-cache", "contract-preparation", "native-ui",
        "swift-core", "swift-storage", "swift-transfer",
    )
)
ACTIVE = frozenset(("queued", "in_progress"))
MAX_PAGES = 10
MAX_CANCELLATIONS = 50
MAX_RESPONSE_BYTES = 4 * 1024 * 1024
SHA = re.compile(r"[0-9a-f]{40}\Z")


class SafetyError(Exception):
    """Stop without exposing response bodies, credentials or untrusted messages."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class GitHub:
    def __init__(self, token):
        if not isinstance(token, str) or not token or "\r" in token or "\n" in token:
            raise SafetyError("GITHUB_TOKEN is required; never pass it as an argument.")
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())
        self.deadline = time.monotonic() + 180
        self.requests_left = 350

    def request(self, path, *, cancel=False):
        suffix = (
            r"/actions/runs/[1-9][0-9]*/cancel" if cancel
            else r"/(?:actions/runs|pulls)(?:/[1-9][0-9]*)?(?:\?[^#\r\n]*)?"
        )
        if not isinstance(path, str) or not re.fullmatch(re.escape(PREFIX) + suffix, path):
            raise SafetyError("Refused an API operation outside the repository metadata/cancellation scope.")
        if self.requests_left <= 0 or time.monotonic() >= self.deadline:
            raise SafetyError("Reached the bounded API request/time budget; remaining runs are preserved.")
        self.requests_left -= 1
        request = urllib.request.Request(
            API_ROOT + path,
            data=b"" if cancel else None,
            method="POST" if cancel else "GET",
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "X-GitHub-Api-Version": "2026-03-10",
            },
        )
        try:
            with self.opener.open(request, timeout=10) as response:
                if cancel:
                    if response.status != 202:
                        raise SafetyError("Cancellation returned an unexpected status.")
                    return True
                if response.status != 200:
                    raise SafetyError("Metadata returned an unexpected status.")
                body = response.read(MAX_RESPONSE_BYTES + 1)
                if len(body) > MAX_RESPONSE_BYTES:
                    raise SafetyError("Metadata exceeded the response bound.")
                return json.loads(body)
        except urllib.error.HTTPError as error:
            if cancel and error.code == 409:
                return False  # The run may already have finished. Never force-cancel.
            raise SafetyError(f"GitHub returned HTTP {error.code}; remaining runs are preserved.") from None
        except (urllib.error.URLError, TimeoutError, OSError, ValueError, http.client.HTTPException):
            raise SafetyError("GitHub metadata could not be read safely; remaining runs are preserved.") from None


def positive_integer(value):
    return type(value) is int and value > 0


def valid_sha(value):
    return isinstance(value, str) and SHA.fullmatch(value) is not None


def same_repository(value):
    return (
        isinstance(value, dict)
        and type(value.get("id")) is int
        and value["id"] == REPOSITORY_ID
        and value.get("full_name", REPOSITORY) == REPOSITORY
    )


def run_in_scope(run):
    return (
        isinstance(run, dict)
        and positive_integer(run.get("id"))
        and run.get("event") == "pull_request"
        and isinstance(run.get("status"), str)
        and run.get("status") in ACTIVE
        and run.get("conclusion") is None
        and type(run.get("run_attempt")) is int and run["run_attempt"] == 1
        and isinstance(run.get("path"), str) and run["path"] in WORKFLOWS
        and same_repository(run.get("repository"))
        and same_repository(run.get("head_repository"))
        and valid_sha(run.get("head_sha"))
        and isinstance(run.get("head_branch"), str)
        and 0 < len(run["head_branch"]) <= 255
        and run["head_branch"] != "main"
    )


def valid_pr(pr, *, number=None, branch=None):
    if not isinstance(pr, dict) or not positive_integer(pr.get("number")):
        return False
    head, base = pr.get("head"), pr.get("base")
    return (
        isinstance(head, dict) and isinstance(base, dict)
        and same_repository(head.get("repo")) and same_repository(base.get("repo"))
        and valid_sha(head.get("sha"))
        and pr.get("state") in ("open", "closed")
        and (number is None or pr["number"] == number)
        and (branch is None or head.get("ref") == branch)
    )


def list_runs(api):
    runs = {}
    for status in sorted(ACTIVE):
        for page in range(1, MAX_PAGES + 1):
            data = api.request(f"{PREFIX}/actions/runs?event=pull_request&status={status}&per_page=100&page={page}")
            values = data.get("workflow_runs") if isinstance(data, dict) else None
            if not isinstance(values, list) or len(values) > 100:
                raise SafetyError("Invalid run listing; no cancellation has started.")
            for run in values:
                if run_in_scope(run):
                    runs[run["id"]] = run
            if len(values) < 100:
                break
        else:
            raise SafetyError("Run listing reached the pagination bound; no cancellation has started.")
    return [runs[key] for key in sorted(runs)]


def open_heads(api):
    heads = set()
    for page in range(1, MAX_PAGES + 1):
        values = api.request(f"{PREFIX}/pulls?state=open&per_page=100&page={page}")
        if not isinstance(values, list) or len(values) > 100:
            raise SafetyError("Invalid open-PR listing; remaining runs are preserved.")
        for pr in values:
            # Also preserve a matching open fork head; do not infer that its tests are disposable.
            head = pr.get("head") if isinstance(pr, dict) else None
            base = pr.get("base") if isinstance(pr, dict) else None
            if not (
                isinstance(head, dict) and valid_sha(head.get("sha"))
                and isinstance(base, dict) and same_repository(base.get("repo"))
                and pr.get("state") == "open"
            ):
                raise SafetyError("Unrecognized open-PR metadata; remaining runs are preserved.")
            heads.add(head["sha"])
        if len(values) < 100:
            return heads
    raise SafetyError("Open-PR listing reached the pagination bound; remaining runs are preserved.")


def resolve_pr(api, run):
    associations = run.get("pull_requests")
    if not isinstance(associations, list):
        return None
    if len(associations) == 1:
        association = associations[0]
        if not isinstance(association, dict) or not valid_pr({**association, "state": "open"}, branch=run["head_branch"]):
            return None
        number = association["number"]
        pr = api.request(f"{PREFIX}/pulls/{number}")
        return pr if valid_pr(pr, number=number, branch=run["head_branch"]) else None
    if associations:
        return None  # More than one association is deliberately ambiguous.
    # GitHub drops closed PRs from run.pull_requests. A branch name alone is insufficient.
    query = urllib.parse.urlencode({
        "state": "all", "head": f"Pick-Your-AI:{run['head_branch']}", "per_page": 100,
    })
    values = api.request(f"{PREFIX}/pulls?{query}")
    if not isinstance(values, list) or len(values) >= 100:
        return None
    matches = [
        pr for pr in values
        if valid_pr(pr, branch=run["head_branch"]) and pr["head"]["sha"] == run["head_sha"]
    ]
    return matches[0] if len(matches) == 1 and matches[0]["state"] == "closed" else None


def obsolete_reason(run, pr):
    if pr["state"] == "closed":
        return "closed PR"
    if pr["head"]["sha"] != run["head_sha"]:
        return "superseded PR head"
    return None


def retire(api, *, apply=False, emit=print):
    candidates = list_runs(api)  # Finish pagination before mutations can change its ordering.
    protected = open_heads(api)
    accepted = eligible = 0
    for run in candidates:
        if eligible >= MAX_CANCELLATIONS:
            break
        if run["head_sha"] in protected:
            continue
        pr = resolve_pr(api, run)
        if pr is None or obsolete_reason(run, pr) is None:
            continue
        # Refresh all open heads, then the exact run and PR immediately before the POST.
        # The REST API has no atomic PR-head conditional cancellation; do not cache this check.
        protected = open_heads(api)
        if run["head_sha"] in protected:
            continue
        latest = api.request(f"{PREFIX}/actions/runs/{run['id']}")
        if not run_in_scope(latest) or any(
            latest[key] != run[key] for key in ("id", "head_sha", "head_branch", "path", "run_attempt")
        ):
            continue
        associations = latest.get("pull_requests")
        if not isinstance(associations, list) or len(associations) > 1:
            continue
        if associations and not (
            isinstance(associations[0], dict)
            and valid_pr({**associations[0], "state": "open"}, number=pr["number"], branch=run["head_branch"])
        ):
            continue
        current = api.request(f"{PREFIX}/pulls/{pr['number']}")
        if not valid_pr(current, number=pr["number"], branch=run["head_branch"]):
            continue
        reason = obsolete_reason(latest, current)
        if reason is None:
            continue
        eligible += 1
        identity = f"run {run['id']}, PR {pr['number']}, {reason}"
        if not apply:
            emit(f"Would request cancellation: {identity}")
        elif api.request(f"{PREFIX}/actions/runs/{run['id']}/cancel", cancel=True):
            accepted += 1
            emit(f"Cancellation accepted: {identity}")
        else:
            emit(f"Cancellation conflicted; preserved without retry: {identity}")
    emit(f"Inspected {len(candidates)} in-scope runs; eligible {eligible}; cancellation requests accepted {accepted}.")
    return accepted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Request ordinary cancellation from reviewed main-branch workflow code.")
    args = parser.parse_args()
    try:
        if args.apply and not (
            os.environ.get("GITHUB_REPOSITORY") == REPOSITORY
            and os.environ.get("GITHUB_REF") == "refs/heads/main"
            and os.environ.get("GITHUB_EVENT_NAME") in ("push", "workflow_run", "workflow_dispatch")
        ):
            raise SafetyError("Apply is restricted to this repository's main-branch maintenance workflow.")
        retire(GitHub(os.environ.get("GITHUB_TOKEN")), apply=args.apply)
        return 0
    except SafetyError as error:
        print(f"Stopped safely: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
