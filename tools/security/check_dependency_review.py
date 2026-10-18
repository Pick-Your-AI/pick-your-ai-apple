#!/usr/bin/env python3
"""Check GitHub dependency-review output, including unresolved license metadata.

The pinned GitHub action performs advisory lookup and SPDX license-expression
evaluation. This guard rejects missing/malformed output and reported problems.
An observed Action license gap and one exact Transfer installer classification
can be resolved only through their reviewed immutable source bytes. Other unknown,
conflicting or disallowed results still fail. Only aggregate counts are printed.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import time
from dataclasses import asdict, dataclass, replace
from urllib.error import URLError
from urllib.request import build_opener, HTTPRedirectHandler, Request


MAXIMUM_OUTPUT_BYTES = 1024 * 1024
SCOPES = frozenset({"runtime", "development", "unknown"})
LICENSE_CATEGORIES = frozenset({"forbidden", "unresolved", "unlicensed"})
PINNED_ACTION_COMMIT = "907a6e9569212033966bc0b69d32473b046dd66b"
PINNED_LICENSE_BLOB = "cdfebd4e4322284fde560f21808182055976d9bf"
PINNED_LICENSE_SHA256 = "399ebcd5cf53d2ba8f32e8d7c7aa77a64b959734f662c533f30b0e75d76012a1"
PINNED_LICENSE_BYTES = 1095
PINNED_LICENSE_URL = (
    "https://api.github.com/repos/actions/dependency-review-action/contents/LICENSE"
    f"?ref={PINNED_ACTION_COMMIT}"
)
MAXIMUM_LICENSE_RESPONSE_BYTES = 65_536
MAXIMUM_LICENSE_SECONDS = 10
TRANSFER_MANIFEST = "Packages/PlannerTransfer/Tools/requirements.txt"
TRANSFER_LOCK_PATH = Path(__file__).resolve().parents[2] / TRANSFER_MANIFEST
TRANSFER_LOCK_BYTES = 1969
TRANSFER_LOCK_SHA256 = "49d2158183e44a47f0f66fd7ce6cb146ca52281015cfcd2e9dd2670724eb0344"
TRANSFER_OBSERVED_LICENSE = (
    "Python-2.0 AND GPL-1.0-or-later AND Python-2.0 AND BSD-3-Clause "
    "AND Python-2.0 AND BSD-3-Clause AND 0BSD"
)
TRANSFER_WHEEL_URL = (
    "https://files.pythonhosted.org/packages/49/d3/"
    "b8441a820a491ddfc024b0b0cf0393375b75ea13866d9c66727e54c2fc80/"
    "typing_extensions-4.16.0-py3-none-any.whl"
)
TRANSFER_WHEEL_BYTES = 45_571
TRANSFER_WHEEL_SHA256 = "481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8"


class InvalidReview(ValueError):
    """Review evidence cannot be interpreted safely; messages contain no payload."""


class PinnedLicenseNoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise InvalidReview("Pinned license redirects are not accepted")


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidReview("Review JSON contains a duplicate object key")
        result[key] = value
    return result


def _invalid_constant(_: str) -> object:
    raise InvalidReview("Review JSON contains a non-JSON number")


def parse_json(text: str | None) -> object:
    if text is None or not text.strip():
        raise InvalidReview("Required dependency-review output is missing")
    if len(text.encode("utf-8")) > MAXIMUM_OUTPUT_BYTES:
        raise InvalidReview("Dependency-review output exceeds the supported byte limit")
    try:
        value = json.loads(
            text, object_pairs_hook=_unique_object, parse_constant=_invalid_constant
        )
    except (ValueError, RecursionError) as error:
        raise InvalidReview("Dependency-review output is not unambiguous JSON") from error
    return value


def parse_output(text: str | None) -> list[dict[str, object]]:
    value = parse_json(text)
    if not isinstance(value, list) or any(not isinstance(row, dict) for row in value):
        raise InvalidReview("Dependency-review output must be an array of objects")
    return value


def parse_license_output(text: str | None) -> dict[str, list[dict[str, object]]]:
    value = parse_json(text)
    if not isinstance(value, dict) or set(value) != LICENSE_CATEGORIES:
        raise InvalidReview("License review must contain all three pinned categories")
    for rows in value.values():
        if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
            raise InvalidReview("Each license-review category must be an array of objects")
    return value


def has_exact_pinned_license_gap(changes, invalid_licenses) -> bool:
    """Only the single complete row observed in run 39113412122, attempt 2."""
    expected = {
        "change_type": "added", "manifest": ".github/workflows/dependency-review.yml",
        "ecosystem": "actions", "name": "actions/dependency-review-action",
        "version": PINNED_ACTION_COMMIT,
        "package_url": f"pkg:githubactions/actions/dependency-review-action@{PINNED_ACTION_COMMIT}",
        "license": None, "source_repository_url": None, "scope": "runtime",
        "vulnerabilities": [],
    }
    return (
        invalid_licenses["unlicensed"] == [expected]
        and changes.count(expected) == 1
        and all(row == expected for row in changes if row.get("package_url") == expected["package_url"])
    )


def verify_pinned_license_response(body: bytes) -> None:
    if len(body) > MAXIMUM_LICENSE_RESPONSE_BYTES:
        raise InvalidReview("Pinned license response exceeds the byte limit")
    value = parse_json(body.decode("utf-8"))
    if (
        not isinstance(value, dict) or value.get("type") != "file"
        or value.get("path") != "LICENSE" or value.get("sha") != PINNED_LICENSE_BLOB
        or value.get("encoding") != "base64" or type(value.get("size")) is not int
        or value["size"] != PINNED_LICENSE_BYTES or not isinstance(value.get("content"), str)
    ):
        raise InvalidReview("Pinned license metadata does not match reviewed source")
    try:
        raw = base64.b64decode(value["content"].replace("\n", ""), validate=True)
    except (ValueError, binascii.Error) as error:
        raise InvalidReview("Pinned license content cannot be decoded") from error
    if len(raw) != PINNED_LICENSE_BYTES or hashlib.sha256(raw).hexdigest() != PINNED_LICENSE_SHA256:
        raise InvalidReview("Pinned license bytes differ from the reviewed MIT file")


def verify_pinned_license() -> None:
    if (
        os.environ.get("GITHUB_EVENT_NAME") != "pull_request"
        or os.environ.get("GITHUB_REPOSITORY") != "Pick-Your-AI/pick-your-ai-apple"
    ):
        raise InvalidReview("Pinned license lookup requires this repository's pull-request review")
    token = os.environ.get("DEPENDENCY_REVIEW_TOKEN")
    if not token or len(token) > 4096 or not token.isascii() or any(ord(c) < 33 or ord(c) > 126 for c in token):
        raise InvalidReview("Read-only pinned-license token is unavailable")
    request = Request(PINNED_LICENSE_URL, method="GET", headers={
        "Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "apple-pinned-dependency-license",
    })
    deadline = time.monotonic() + MAXIMUM_LICENSE_SECONDS
    opener = build_opener(PinnedLicenseNoRedirects())
    with opener.open(request, timeout=MAXIMUM_LICENSE_SECONDS) as response:
        if response.status != 200:
            raise InvalidReview("Pinned license lookup did not succeed")
        chunks, received = [], 0
        while received <= MAXIMUM_LICENSE_RESPONSE_BYTES:
            if time.monotonic() >= deadline:
                raise InvalidReview("Pinned license lookup exceeded its time limit")
            chunk = response.read1(min(16_384, MAXIMUM_LICENSE_RESPONSE_BYTES + 1 - received))
            if not chunk:
                break
            chunks.append(chunk)
            received += len(chunk)
        if time.monotonic() >= deadline:
            raise InvalidReview("Pinned license lookup exceeded its time limit")
    verify_pinned_license_response(b"".join(chunks))


def has_exact_transfer_license_conflict(changes, invalid_licenses) -> bool:
    """The complete single classification observed in job 117714734437."""
    expected = {
        "change_type": "added", "manifest": TRANSFER_MANIFEST,
        "ecosystem": "pip", "name": "typing-extensions", "version": "4.16.0",
        "package_url": "pkg:pypi/typing-extensions@4.16.0",
        "license": TRANSFER_OBSERVED_LICENSE, "source_repository_url": None,
        "scope": "runtime", "vulnerabilities": [],
    }
    return (
        invalid_licenses == {"forbidden": [expected], "unresolved": [], "unlicensed": []}
        and changes.count(expected) == 1
        and all(row == expected for row in changes if row.get("package_url") == expected["package_url"])
    )


def verify_transfer_license_artifact() -> None:
    """Bind the exact installer to reviewed wheel bytes; never execute the wheel."""
    if (
        os.environ.get("GITHUB_EVENT_NAME") != "pull_request"
        or os.environ.get("GITHUB_REPOSITORY") != "Pick-Your-AI/pick-your-ai-apple"
    ):
        raise InvalidReview("Transfer artifact proof requires this repository's pull-request review")
    flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
    with os.fdopen(os.open(TRANSFER_LOCK_PATH, flags), "rb") as lock:
        metadata = os.fstat(lock.fileno())
        if (
            not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1
            or metadata.st_size != TRANSFER_LOCK_BYTES
        ):
            raise InvalidReview("Transfer installer is not the reviewed regular file")
        raw = lock.read(TRANSFER_LOCK_BYTES + 1)
    if len(raw) != TRANSFER_LOCK_BYTES or hashlib.sha256(raw).hexdigest() != TRANSFER_LOCK_SHA256:
        raise InvalidReview("Transfer installer differs from the reviewed hash-locked bytes")
    request = Request(TRANSFER_WHEEL_URL, method="GET", headers={
        "User-Agent": "apple-pinned-transfer-license", "Accept": "application/octet-stream",
    })
    deadline = time.monotonic() + MAXIMUM_LICENSE_SECONDS
    opener = build_opener(PinnedLicenseNoRedirects())
    with opener.open(request, timeout=MAXIMUM_LICENSE_SECONDS) as response:
        if response.status != 200:
            raise InvalidReview("Transfer artifact lookup did not succeed")
        chunks, received = [], 0
        while received <= TRANSFER_WHEEL_BYTES:
            if time.monotonic() >= deadline:
                raise InvalidReview("Transfer artifact lookup exceeded its time limit")
            chunk = response.read1(min(16_384, TRANSFER_WHEEL_BYTES + 1 - received))
            if not chunk:
                break
            chunks.append(chunk)
            received += len(chunk)
        if time.monotonic() >= deadline:
            raise InvalidReview("Transfer artifact lookup exceeded its time limit")
    raw = b"".join(chunks)
    if len(raw) != TRANSFER_WHEEL_BYTES or hashlib.sha256(raw).hexdigest() != TRANSFER_WHEEL_SHA256:
        raise InvalidReview("Transfer artifact differs from the reviewed PSF-2.0 wheel")


@dataclass(frozen=True)
class ReviewResult:
    added_dependencies: int
    removed_dependencies: int
    vulnerable_dependencies: int
    unresolved_licenses: int
    unlicensed_dependencies: int
    disallowed_licenses: int
    pinned_license_resolutions: int = 0

    @property
    def accepted(self) -> bool:
        return not (
            self.vulnerable_dependencies
            or self.unresolved_licenses
            or self.unlicensed_dependencies
            or self.disallowed_licenses
        )


def evaluate(
    changes: list[dict[str, object]], invalid_licenses: dict[str, list[dict[str, object]]]
) -> ReviewResult:
    added = removed = vulnerable = 0
    for row in changes:
        if not isinstance(row.get("change_type"), str) or row["change_type"] not in {"added", "removed"}:
            raise InvalidReview("Unrecognized dependency change type")
        if any(
            not isinstance(row.get(field), str) or not row[field].strip()
            for field in ("manifest", "ecosystem", "name", "version")
        ):
            raise InvalidReview("Dependency identity is incomplete")
        if row["change_type"] == "removed":
            # Removing an unsafe or unidentified dependency is a recovery action.
            removed += 1
            continue
        # The pinned upstream schema permits absent scope; its all-scope filter
        # treats that legacy API representation as runtime. Explicit null is not
        # a supported scope and is never silently coerced.
        if "scope" in row and (not isinstance(row["scope"], str) or row["scope"] not in SCOPES):
            raise InvalidReview("Dependency scope is missing or unsupported")
        vulnerabilities = row.get("vulnerabilities")
        if not isinstance(vulnerabilities, list):
            raise InvalidReview("Dependency vulnerability evidence is missing")
        added += 1
        vulnerable += bool(vulnerabilities)
    # The official action owns SPDX expression classification and can resolve a
    # raw null license through GitHub's repository-license API. Its result is an
    # object of three arrays, not one array, and the raw dependency list need not
    # receive that resolved license. No reported category can be discarded.
    return ReviewResult(
        added, removed, vulnerable,
        len(invalid_licenses["unresolved"]), len(invalid_licenses["unlicensed"]),
        len(invalid_licenses["forbidden"]),
    )


def main() -> int:
    try:
        changes = parse_output(os.environ.get("DEPENDENCY_CHANGES"))
        invalid_licenses = parse_license_output(os.environ.get("INVALID_LICENSE_CHANGES"))
        outcome = os.environ.get("DEPENDENCY_REVIEW_OUTCOME")
        if outcome not in {"success", "failure"}:
            raise InvalidReview("Upstream dependency-review outcome is missing or unsupported")
        if os.environ.get("DEPENDENCY_SNAPSHOT_OUTCOME") != "success":
            raise InvalidReview("Exact dependency snapshots did not complete successfully")
        result = evaluate(changes, invalid_licenses)
        allowed = {part.strip() for part in os.environ.get("ALLOWED_DEPENDENCY_LICENSES", "").split(",")}
        if (
            outcome == "success" and not result.vulnerable_dependencies and not result.unresolved_licenses
            and not result.disallowed_licenses and "MIT" in allowed
            and has_exact_pinned_license_gap(changes, invalid_licenses)
        ):
            # This is exact source evidence for an existing allowed license,
            # not an upstream package exemption (which ignores Action versions).
            verify_pinned_license()
            result = replace(result, unlicensed_dependencies=0, pinned_license_resolutions=1)
        transfer_resolution = False
        if (
            outcome == "failure" and not result.vulnerable_dependencies
            and "PSF-2.0" in allowed
            and has_exact_transfer_license_conflict(changes, invalid_licenses)
        ):
            verify_transfer_license_artifact()
            result = replace(result, disallowed_licenses=0, pinned_license_resolutions=1)
            transfer_resolution = True
        if outcome == "failure" and result.accepted and not transfer_resolution:
            raise InvalidReview("Upstream review failure has no exact verified recovery")
    except (InvalidReview, UnicodeError) as error:
        print(f"Dependency review could not be verified: {error}", file=sys.stderr)
        return 1
    except (OSError, URLError):
        print("Pinned dependency license could not be verified; no recovery is accepted.", file=sys.stderr)
        return 1
    print(json.dumps({"accepted": result.accepted, **asdict(result)}, sort_keys=True))
    return 0 if result.accepted else 1


if __name__ == "__main__":
    raise SystemExit(main())
