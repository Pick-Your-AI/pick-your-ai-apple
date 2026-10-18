#!/usr/bin/env python3
"""Check GitHub dependency-review output, including unresolved license metadata.

The pinned GitHub action performs advisory lookup and SPDX license-expression
evaluation. This guard does not replace that service or infer an absent result.
It rejects missing/malformed output, all reported vulnerabilities (including
development and unknown scope), and all three upstream invalid-license categories.
Only aggregate counts are printed.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import asdict, dataclass


MAXIMUM_OUTPUT_BYTES = 1024 * 1024
SCOPES = frozenset({"runtime", "development", "unknown"})
LICENSE_CATEGORIES = frozenset({"forbidden", "unresolved", "unlicensed"})


class InvalidReview(ValueError):
    """Review evidence cannot be interpreted safely; messages contain no payload."""


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


@dataclass(frozen=True)
class ReviewResult:
    added_dependencies: int
    removed_dependencies: int
    vulnerable_dependencies: int
    unresolved_licenses: int
    unlicensed_dependencies: int
    disallowed_licenses: int

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
        result = evaluate(
            parse_output(os.environ.get("DEPENDENCY_CHANGES")),
            parse_license_output(os.environ.get("INVALID_LICENSE_CHANGES")),
        )
    except (InvalidReview, UnicodeError) as error:
        print(f"Dependency review could not be verified: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"accepted": result.accepted, **asdict(result)}, sort_keys=True))
    return 0 if result.accepted else 1


if __name__ == "__main__":
    raise SystemExit(main())
