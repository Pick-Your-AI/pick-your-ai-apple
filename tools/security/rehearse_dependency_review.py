#!/usr/bin/env python3
"""Replay harmless review-output fixtures through the actual command-line gate."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import platform
import secrets
import stat
import subprocess
import sys


SCRIPT = Path(__file__).with_name("check_dependency_review.py")


class InvalidOutput(ValueError):
    """A receipt destination is unsafe; messages contain no supplied paths."""


@contextmanager
def prepared_output(path: Path | None):
    if path is None:
        yield None
        return
    if path.name in {"", ".", ".."}:
        raise InvalidOutput("Receipt output must name a file outside the source checkout.")
    # Check the actual supplied traversal before resolving it. Resolving alone
    # can erase an impossible regular-file/.. or missing-directory/.. prefix.
    parent = path.parent.stat()
    resolved_parent = path.parent.resolve(strict=True)
    source_root = Path(__file__).resolve(strict=True).parents[2]
    if resolved_parent.is_relative_to(source_root):
        raise InvalidOutput("Receipt output must be outside the source checkout.")
    resolved = resolved_parent.stat()
    parent_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        opened = os.fstat(parent_fd)
        if not stat.S_ISDIR(opened.st_mode) or any(
            (item.st_dev, item.st_ino) != (opened.st_dev, opened.st_ino)
            for item in (parent, resolved)
        ):
            raise InvalidOutput("Receipt output directory changed during validation.")
        try:
            existing = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            existing = None
        if existing is not None:
            if not stat.S_ISREG(existing.st_mode) or existing.st_nlink != 1:
                raise InvalidOutput("Receipt output must be a regular file with one link.")
            # An admissible prior success must not survive a failed new attempt.
            os.unlink(path.name, dir_fd=parent_fd)
        yield parent_fd, path.name
    finally:
        os.close(parent_fd)


def write_output(destination: tuple[int, str], encoded: str) -> None:
    parent_fd, name = destination
    temporary = ".dependency-review-" + secrets.token_hex(16) + ".tmp"
    descriptor = os.open(
        temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
        0o600, dir_fd=parent_fd,
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(encoded)
        # Both names stay anchored to the validated directory. Replacement
        # neither follows a final symlink nor truncates a hardlinked target.
        os.replace(temporary, name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
    finally:
        try:
            os.unlink(temporary, dir_fd=parent_fd)
        except FileNotFoundError:
            pass


def rehearsal_report() -> dict[str, object]:
    safe = {
        "change_type": "added", "manifest": "synthetic/requirements.txt",
        "ecosystem": "pip", "name": "synthetic-review-fixture", "version": "1.0.1",
        "scope": "development", "license": "MIT", "vulnerabilities": [],
        "package_url": "pkg:pypi/synthetic-review-fixture@1.0.1", "source_repository_url": None,
    }
    vulnerable = {
        **safe, "version": "1.0.0", "vulnerabilities": [{"severity": "critical"}],
    }
    unapproved = {**safe, "license": "LicenseRef-Synthetic-Unapproved"}
    clean_licenses = {"forbidden": [], "unresolved": [], "unlicensed": []}
    unlicensed = {**safe, "license": None}
    cases = [
        ("no-dependency-change", [], clean_licenses, 0),
        ("vulnerable-development-dependency", [vulnerable], clean_licenses, 1),
        ("unapproved-license", [unapproved], {**clean_licenses, "forbidden": [unapproved]}, 1),
        ("unresolved-license", [unlicensed], {**clean_licenses, "unlicensed": [unlicensed]}, 1),
        ("urgent-update-recovery", [{**vulnerable, "change_type": "removed"}, safe], clean_licenses, 0),
        ("patched-version-with-missing-review", [safe], None, 1),
    ]
    results = []
    for name, changes, licenses, expected in cases:
        # The synthetic replay needs no network, repository token or inherited
        # credentials. No package represented in the fixture is installed.
        env = {
            "PYTHONUTF8": "1", "DEPENDENCY_CHANGES": json.dumps(changes),
            "DEPENDENCY_REVIEW_OUTCOME": "failure" if name in {
                "vulnerable-development-dependency", "unapproved-license"
            } else "success",
            "DEPENDENCY_SNAPSHOT_OUTCOME": "success",
        }
        if licenses is not None:
            env["INVALID_LICENSE_CHANGES"] = json.dumps(licenses)
        run = subprocess.run(
            [sys.executable, str(SCRIPT)], env=env, capture_output=True, text=True,
            timeout=10, check=False,
        )
        results.append({
            "case": name, "expected_exit": expected, "actual_exit": run.returncode,
            "passed": run.returncode == expected,
            "report": json.loads(run.stdout) if run.stdout else None,
            "diagnostic": run.stderr.strip() or None,
        })
    report = {
        "schema_version": 1,
        "kind": "synthetic-dependency-review-output-drill",
        "python": platform.python_version(),
        "guard_sha256": hashlib.sha256(SCRIPT.read_bytes()).hexdigest(),
        "limits": [
            "Uses supplied synthetic review output; does not query an advisory database.",
            "Does not install a vulnerable package, change credentials or test a release binary.",
            "SPDX classifications are fixture inputs; hosted action classification remains a separate gate.",
            "Action and snapshot outcomes are explicit synthetic inputs, not hosted check receipts.",
        ],
        "passed": all(result["passed"] for result in results),
        "cases": results,
    }
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path,
        help="Write a receipt outside this checkout, in an existing directory; refuse linked or nonregular files.",
    )
    args = parser.parse_args()
    try:
        with prepared_output(args.output) as destination:
            report = rehearsal_report()
            encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
            if destination is None:
                print(encoded, end="")
            else:
                write_output(destination, encoded)
            return 0 if report["passed"] else 1
    except InvalidOutput as error:
        print(f"Dependency review rehearsal failed: {error}", file=sys.stderr)
    except (OSError, ValueError, subprocess.SubprocessError):
        print("Dependency review rehearsal failed; no current result was produced.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
