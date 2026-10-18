#!/usr/bin/env python3
"""Bind dependency-review output to a complete, read-only exact-commit API diff."""

from __future__ import annotations

import base64
import binascii
import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlsplit
from urllib.request import build_opener, HTTPRedirectHandler, Request

from check_dependency_review import InvalidReview, parse_json, parse_output, SCOPES


REPOSITORY = "Pick-Your-AI/pick-your-ai-apple"
API_ORIGIN = "https://api.github.com"
WARNINGS_HEADER = "x-github-dependency-graph-snapshot-warnings"
MAXIMUM_BYTES = 1024 * 1024
MAXIMUM_PAGES = 20
MAXIMUM_SECONDS = 60
PER_PAGE = 100


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise InvalidReview("GitHub comparison redirects are not accepted")


def event_range(event: object) -> tuple[str, str]:
    try:
        if event["repository"]["full_name"] != REPOSITORY:
            raise InvalidReview("Unexpected dependency-review repository")
        pull = event["pull_request"]
        if pull["base"]["repo"]["full_name"] != REPOSITORY:
            raise InvalidReview("Unexpected pull-request base repository")
        base, head = pull["base"]["sha"], pull["head"]["sha"]
        if not all(isinstance(sha, str) and re.fullmatch(r"[0-9a-f]{40}", sha) for sha in (base, head)):
            raise InvalidReview("Dependency comparison requires exact commit identities")
        return base, head
    except (KeyError, TypeError) as error:
        raise InvalidReview("Pull-request comparison identity is incomplete") from error


def comparison_url(base: str, head: str, page: int) -> str:
    return f"{API_ORIGIN}/repos/{REPOSITORY}/dependency-graph/compare/{base}...{head}?per_page={PER_PAGE}&page={page}"


def has_next_page(link: str | None, expected_url: str) -> bool:
    if link is None:
        return False
    if not isinstance(link, str) or len(link) > 16_384:
        raise InvalidReview("Invalid dependency comparison pagination")
    next_urls = []
    for part in link.split(","):
        match = re.fullmatch(r'\s*<([^>]+)>;\s*rel="([a-z]+)"\s*', part)
        if match is None:
            raise InvalidReview("Unrecognized dependency comparison pagination")
        if match[2] == "next":
            next_urls.append(match[1])
    if not next_urls:
        return False
    if len(next_urls) != 1:
        raise InvalidReview("Ambiguous dependency comparison pagination")
    actual, expected = urlsplit(next_urls[0]), urlsplit(expected_url)
    if (
        actual.scheme != expected.scheme or actual.netloc != expected.netloc
        or actual.path != expected.path or actual.fragment
        or parse_qs(actual.query, strict_parsing=True, keep_blank_values=True) != parse_qs(expected.query, keep_blank_values=True)
    ):
        raise InvalidReview("Dependency pagination changed origin or commit identity")
    return True


def require_no_snapshot_warnings(value: str | None) -> None:
    if value is None:
        return
    if not isinstance(value, str) or len(value) > 16_384:
        raise InvalidReview("Snapshot warning metadata is invalid")
    try:
        warnings = base64.b64decode(value, validate=True).decode("utf-8")
    except (binascii.Error, UnicodeError, ValueError) as error:
        raise InvalidReview("Snapshot warning metadata cannot be decoded") from error
    if warnings.strip():
        raise InvalidReview("Dependency snapshots remain incomplete for these commits")


def normalized_changes(rows: list[dict[str, object]], *, raw_api: bool) -> list[str]:
    """Match the pinned action's ChangeSchema projection/defaults, not row order."""
    normalized = []
    for row in rows:
        result = {}
        for field in ("change_type", "manifest", "ecosystem", "name", "version", "package_url"):
            if not isinstance(row.get(field), str):
                raise InvalidReview("Compared dependency metadata is incomplete")
            result[field] = row[field]
        if result["change_type"] not in {"added", "removed"}:
            raise InvalidReview("Unknown compared dependency change type")
        for field in ("license", "source_repository_url"):
            if field not in row or (row[field] is not None and not isinstance(row[field], str)):
                raise InvalidReview("Compared license/source metadata is incomplete")
            result[field] = row[field]
        if "scope" in row:
            if not isinstance(row["scope"], str) or row["scope"] not in SCOPES:
                raise InvalidReview("Compared dependency scope is unsupported")
            result["scope"] = row["scope"]
        vulnerabilities = row.get("vulnerabilities", [] if raw_api else None)
        if not isinstance(vulnerabilities, list):
            raise InvalidReview("Compared vulnerability metadata is incomplete")
        projected = []
        for vulnerability in vulnerabilities:
            if not isinstance(vulnerability, dict):
                raise InvalidReview("Compared vulnerability metadata is invalid")
            detail = {}
            for field in ("advisory_ghsa_id", "advisory_summary", "advisory_url"):
                if not isinstance(vulnerability.get(field), str):
                    raise InvalidReview("Compared vulnerability identity is incomplete")
                detail[field] = vulnerability[field]
            severity = vulnerability.get("severity", "low" if raw_api else None)
            if not isinstance(severity, str) or severity not in {"low", "moderate", "high", "critical"}:
                raise InvalidReview("Compared vulnerability severity is invalid")
            detail["severity"] = severity
            projected.append(detail)
        result["vulnerabilities"] = sorted(projected, key=lambda value: json.dumps(value, sort_keys=True))
        normalized.append(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return sorted(normalized)


def verify_comparison(base: str, head: str, reviewed: list[dict[str, object]], fetch_page) -> int:
    observed = []
    total_bytes = 0
    for page in range(1, MAXIMUM_PAGES + 1):
        headers, body = fetch_page(comparison_url(base, head, page))
        total_bytes += len(body)
        if total_bytes > MAXIMUM_BYTES:
            raise InvalidReview("Dependency comparison exceeds the supported byte limit")
        require_no_snapshot_warnings(headers.get(WARNINGS_HEADER))
        rows = parse_output(body.decode("utf-8"))
        if len(rows) > PER_PAGE:
            raise InvalidReview("Dependency comparison page exceeds the requested limit")
        observed.extend(rows)
        if not has_next_page(headers.get("link"), comparison_url(base, head, page + 1)):
            if normalized_changes(observed, raw_api=True) != normalized_changes(reviewed, raw_api=False):
                raise InvalidReview("Dependency-review output differs from the complete exact-commit comparison")
            return len(observed)
    raise InvalidReview("Dependency comparison exceeds the supported page limit")


def main() -> int:
    try:
        if os.environ.get("GITHUB_EVENT_NAME") != "pull_request" or os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
            raise InvalidReview("Only this repository's pull-request review is supported")
        token = os.environ.get("DEPENDENCY_REVIEW_TOKEN")
        if not token or not token.isascii() or any(ord(char) < 33 or ord(char) > 126 for char in token):
            raise InvalidReview("Read-only dependency-review token is unavailable")
        with Path(os.environ["GITHUB_EVENT_PATH"]).open("rb") as stream:
            event = parse_json(stream.read(MAXIMUM_BYTES + 1).decode("utf-8"))
        base, head = event_range(event)
        reviewed = parse_output(os.environ.get("DEPENDENCY_CHANGES"))
        deadline = time.monotonic() + MAXIMUM_SECONDS
        opener = build_opener(NoRedirects())

        def fetch_page(url: str):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise InvalidReview("Dependency comparison exceeded its time limit")
            request = Request(url, method="GET", headers={
                "Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "apple-dependency-review",
            })
            with opener.open(request, timeout=min(10, remaining)) as response:
                if response.status != 200:
                    raise InvalidReview("Dependency comparison did not succeed")
                warnings = response.headers.get_all(WARNINGS_HEADER, [])
                if len(warnings) > 1:
                    raise InvalidReview("Ambiguous snapshot warning metadata")
                headers = {}
                if warnings:
                    headers[WARNINGS_HEADER] = warnings[0]
                links = response.headers.get_all("link", [])
                if links:
                    headers["link"] = ",".join(links)
                chunks = []
                received = 0
                while received <= MAXIMUM_BYTES:
                    if time.monotonic() >= deadline:
                        raise InvalidReview("Dependency comparison exceeded its time limit")
                    chunk = response.read1(min(65_536, MAXIMUM_BYTES + 1 - received))
                    if not chunk:
                        break
                    chunks.append(chunk)
                    received += len(chunk)
                if time.monotonic() >= deadline:
                    raise InvalidReview("Dependency comparison exceeded its time limit")
                return headers, b"".join(chunks)

        count = verify_comparison(base, head, reviewed, fetch_page)
        print(json.dumps({"snapshot_warnings": False, "matched_dependencies": count, "base": base, "head": head}, sort_keys=True))
        return 0
    except InvalidReview as error:
        print(f"Dependency snapshot verification failed: {error}", file=sys.stderr)
        return 1
    except (OSError, HTTPError, URLError, UnicodeError, KeyError, ValueError):
        # Do not echo HTTP bodies, token values, raw dependency metadata or paths.
        print("Dependency snapshot verification failed; no complete matching review is established.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
