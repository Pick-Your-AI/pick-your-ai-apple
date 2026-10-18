#!/usr/bin/env python3
"""Skip native allocation only after proving an exact documentation-only delta."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
from dataclasses import asdict, dataclass


SHA = re.compile(r"[0-9a-f]{40}\Z")
REGULAR_OR_ABSENT = {b"100644", b"000000"}
MAX_COMPARISON_BYTES = 4 * 1024 * 1024
# Audited documentation, not package resources, fixtures or normative validator
# inputs. Unknown Markdown still allocates native; additions require review.
DOCUMENTATION_PATHS = {
    "AGENTS.md", "CONTRIBUTING.md", "README.md",
    "App/README.md", "App/UI_JOURNEY.md",
    "Packages/PlannerCore/README.md", "Packages/PlannerData/README.md",
    "Packages/PlannerTransfer/README.md", "Packages/PlannerCatalog/README.md",
    "tools/conformance/README.md",
    "docs/REPOSITORY_SCOPE.md",
    "docs/acceptance/README.md",
    "docs/acceptance/issue-33-draft-snapshot-boundary.md",
    "docs/acceptance/issue-86-durable-storage.md",
    "docs/proposals/issue-25-acceptance-intake.md",
    "docs/proposals/issue-20-journey-map.md",
    "docs/decisions/research-inputs-20261018.md",
    "docs/decisions/issue-22-platform.md", "docs/decisions/issue-23-services.md",
    "docs/decisions/README.md", "docs/decisions/issue-24-accounts.md",
    "docs/decisions/issue-21-scope.md", "docs/decisions/foundation-disposition.md",
    "docs/validation/toolchain-pin.md", "docs/validation/source-use-policy.md",
    "docs/validation/ci-concurrency.md", "docs/validation/pricebook-boundary.md",
    "docs/validation/issue-98-data-threats.md", "docs/validation/obsolete-pr-checks.md",
    "docs/validation/runtime-configuration.md", "docs/validation/native-scope.md",
    "docs/security/local-draft-threat-model.md",
}


@dataclass(frozen=True)
class Scope:
    native_required: bool
    reason: str
    changed_files: int = 0


def git(repo: Path, *arguments: str) -> bytes:
    return subprocess.run(
        ["git", "--no-pager", *arguments], cwd=repo, check=True,
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=30,
    ).stdout


def documentation(path: bytes) -> bool:
    """An extension alone never exempts a fixture or validator input."""
    return path.decode("utf-8", errors="strict") in DOCUMENTATION_PATHS


def choose(repo: Path, *, event: str, head: str, base: str = "", before: str = "") -> Scope:
    """Every unknown/error path retains native execution, never a guessed skip."""
    if not SHA.fullmatch(head) or head == "0" * 40:
        return Scope(True, "Unknown checkout identity")
    if event not in {"pull_request", "push"}:
        return Scope(True, "Event requires native execution")
    previous = base if event == "pull_request" else before
    if not SHA.fullmatch(previous) or previous == "0" * 40:
        return Scope(True, "Unknown comparison identity")
    try:
        if git(repo, "rev-parse", "HEAD").decode().strip() != head:
            return Scope(True, "Checkout differs from event identity")
        if event == "pull_request":
            parents = git(repo, "show", "-s", "--format=%P", head).decode().strip().split()
            if len(parents) != 2 or parents[0] != previous:
                return Scope(True, "PR checkout is not the expected base/head test merge")
        else:
            git(repo, "merge-base", "--is-ancestor", previous, head)

        # A native source symlink could consume a Markdown target indirectly.
        # Keep the native gate if any symlink/submodule exists in the exact tree.
        tree = git(repo, "ls-tree", "-r", "-z", head)
        if len(tree) > MAX_COMPARISON_BYTES:
            return Scope(True, "Tree exceeds the conservative inspection bound")
        if any(entry.startswith((b"120000 ", b"160000 ")) for entry in tree.split(b"\0")):
            return Scope(True, "Tree contains a symlink or submodule")

        raw = git(repo, "diff", "--raw", "-z", "--no-abbrev", "--no-renames",
                  "--no-ext-diff", "--no-textconv", previous, head, "--")
        if not raw or len(raw) > MAX_COMPARISON_BYTES or not raw.endswith(b"\0"):
            return Scope(True, "Empty, oversized or incomplete comparison")
        entries = raw[:-1].split(b"\0")
        if len(entries) % 2:
            return Scope(True, "Unrecognized comparison format")
        count = len(entries) // 2
        for index in range(0, len(entries), 2):
            fields = entries[index].split()
            if len(fields) != 5 or not fields[0].startswith(b":"):
                return Scope(True, "Unrecognized change metadata", count)
            old_mode, new_mode = fields[0][1:], fields[1]
            if (old_mode not in REGULAR_OR_ABSENT or new_mode not in REGULAR_OR_ABSENT
                    or fields[4] not in {b"A", b"M", b"D"}
                    or not documentation(entries[index + 1])):
                return Scope(True, "Change includes source, configuration, data or non-regular documentation", count)
        return Scope(False, "Complete exact comparison contains only regular documentation", count)
    except (OSError, subprocess.SubprocessError, UnicodeError, ValueError):
        return Scope(True, "Exact Git comparison could not be established")


def main() -> None:
    result = choose(
        Path.cwd(), event=os.environ.get("APPLE_CI_EVENT", ""),
        head=os.environ.get("APPLE_CI_HEAD", ""),
        base=os.environ.get("APPLE_CI_BASE", ""),
        before=os.environ.get("APPLE_CI_BEFORE", ""),
    )
    print(json.dumps(asdict(result), sort_keys=True))
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a", encoding="utf-8") as stream:
            stream.write(f"native_required={str(result.native_required).lower()}\n")


if __name__ == "__main__":
    main()
