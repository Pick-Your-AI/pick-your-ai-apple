#!/usr/bin/env python3
"""Allocate native unless complete Git inputs prove an audited job is unchanged."""

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
MAX_AUDIT_BYTES = 64 * 1024
AUDIT_PATH = "tools/ci/native-inputs.json"
PACKAGE_ROOTS = frozenset(f"Packages/Planner{name}" for name in
                          ("Core", "Data", "Transfer", "Catalog", "UI"))
# Include all commands in each job, not just the primary package's imports.
# Core and UI jobs run EvidenceHarness, which links UI, Core and transitive
# Data/Transfer/Catalog. Transfer links Core and Catalog; its tests also link Data.
JOB_INPUTS = {
    "macos-core": {"Packages/PlannerCore", "Packages/PlannerUI", "Packages/PlannerData",
                   "Packages/PlannerTransfer", "Packages/PlannerCatalog"},
    "macos-storage": {"Packages/PlannerData"},
    "macos-transfer": {"Packages/PlannerTransfer", "Packages/PlannerData",
                       "Packages/PlannerCore", "Packages/PlannerCatalog"},
    "macos-catalog-cache": {"Packages/PlannerCatalog"},
    "native-ui": {"Packages/PlannerUI", "Packages/PlannerData", "Packages/PlannerCore",
                  "Packages/PlannerTransfer", "Packages/PlannerCatalog"},
}
DEPENDENCIES = {f"{root}/Package.swift" for root in PACKAGE_ROOTS} | {
    "App/Planner.xcodeproj/project.pbxproj",
    "App/Planner.xcodeproj/xcshareddata/xcschemes/Planner.xcscheme",
}
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
    "docs/validation/issue-113-policy.md", "docs/validation/submission-sdk.md",
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


def package_path(path: str) -> bool:
    return any(path.startswith(root + "/") for root in PACKAGE_ROOTS)


def read_tree(repo: Path, revision: str) -> dict[str, list[str]]:
    raw = git(repo, "ls-tree", "-r", "-t", "-z", revision)
    if not raw or len(raw) > MAX_COMPARISON_BYTES or not raw.endswith(b"\0"):
        raise ValueError("Incomplete or oversized tree")
    result = {}
    kinds = {"040000": "tree", "100644": "blob", "100755": "blob"}
    for entry in raw[:-1].split(b"\0"):
        metadata, name = entry.split(b"\t", 1)
        path = name.decode("utf-8", errors="strict")
        fields = metadata.decode("ascii").split()
        if (len(fields) != 3 or kinds.get(fields[0]) != fields[1]
                or not SHA.fullmatch(fields[2]) or path in result
                or not path or any(ord(c) < 32 or ord(c) > 126 for c in path)
                or any(part in {"", ".", ".."} for part in path.split("/"))):
            # In particular, symlinks/submodules cannot introduce indirect inputs.
            raise ValueError("Unrecognized tree entry")
        result[path] = fields
    return result


def repository_inputs(tree: dict[str, list[str]]) -> dict[str, list[str]]:
    """Pin all non-document leaves outside packages, including absent new paths.

    This deliberately includes more than known workflow/helper inputs. A later
    root configuration or attributes file must not silently change the audit's
    assumptions during an otherwise package-only comparison.
    """
    return {path: entry for path, entry in tree.items()
            if entry[1] != "tree" and not package_path(path)
            and path not in DOCUMENTATION_PATHS and path != AUDIT_PATH}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate audit field")
        result[key] = value
    return result


def load_audit(repo: Path, tree: dict[str, list[str]]) -> dict:
    entry = tree.get(AUDIT_PATH)
    if entry is None or entry[:2] != ["100644", "blob"]:
        raise ValueError("Missing regular audit")
    size = int(git(repo, "cat-file", "-s", entry[2]))
    if not 0 < size <= MAX_AUDIT_BYTES:
        raise ValueError("Audit exceeds inspection bound")
    raw = git(repo, "cat-file", "blob", entry[2])
    if len(raw) != size:
        raise ValueError("Incomplete audit")
    audit = json.loads(raw, object_pairs_hook=unique_object)
    keys = {"version", "source_revision", "dependencies", "repository_inputs", "jobs"}
    if (not isinstance(audit, dict) or set(audit) != keys
            or type(audit["version"]) is not int or audit["version"] != 1
            or not isinstance(audit["source_revision"], str)
            or not SHA.fullmatch(audit["source_revision"])
            or audit["source_revision"] == "0" * 40
            or not isinstance(audit["dependencies"], dict)
            or set(audit["dependencies"]) != DEPENDENCIES
            or not isinstance(audit["repository_inputs"], dict)
            or not isinstance(audit["jobs"], dict) or set(audit["jobs"]) != set(JOB_INPUTS)):
        raise ValueError("Unrecognized audit structure")
    maps = [(audit["dependencies"], "blob"), (audit["repository_inputs"], "blob")]
    for job, paths in JOB_INPUTS.items():
        if not isinstance(audit["jobs"][job], dict) or set(audit["jobs"][job]) != paths:
            raise ValueError("Incomplete job footprint")
        maps.append((audit["jobs"][job], "tree"))
    for entries, kind in maps:
        for value in entries.values():
            modes = {"040000"} if kind == "tree" else {"100644", "100755"}
            if (not isinstance(value, list) or len(value) != 3
                    or not all(isinstance(field, str) for field in value)
                    or value[0] not in modes or value[1] != kind
                    or not SHA.fullmatch(value[2]) or value[2] == "0" * 40):
                raise ValueError("Unrecognized audit object")
    return audit


def package_scope(repo: Path, previous: str, tree: dict[str, list[str]], job: str, count: int) -> Scope:
    if job not in JOB_INPUTS:
        return Scope(True, "No audited native job identity", count)
    audit = load_audit(repo, tree)
    old_tree = read_tree(repo, previous)
    git(repo, "merge-base", "--is-ancestor", audit["source_revision"], previous)
    for endpoint in (old_tree, tree):
        if (endpoint.get(AUDIT_PATH) != tree[AUDIT_PATH]
                or repository_inputs(endpoint) != audit["repository_inputs"]
                or any(endpoint.get(path) != value for path, value in audit["dependencies"].items())):
            return Scope(True, "Repository inputs or dependency audit changed", count)
    for endpoint in (old_tree, tree):
        if any(endpoint.get(path) != value for path, value in audit["jobs"][job].items()):
            return Scope(True, "Audited native job inputs changed", count)
    return Scope(False, "Complete package comparison preserves all audited inputs for " + job, count)


def choose(repo: Path, *, event: str, head: str, base: str = "", before: str = "", job: str = "") -> Scope:
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

        raw = git(repo, "diff", "--raw", "-z", "--no-abbrev", "--no-renames",
                  "--no-ext-diff", "--no-textconv", previous, head, "--")
        if not raw or len(raw) > MAX_COMPARISON_BYTES or not raw.endswith(b"\0"):
            return Scope(True, "Empty, oversized or incomplete comparison")
        entries = raw[:-1].split(b"\0")
        if len(entries) % 2:
            return Scope(True, "Unrecognized comparison format")
        count = len(entries) // 2
        only_documentation = True
        for index in range(0, len(entries), 2):
            fields = entries[index].split()
            if len(fields) != 5 or not fields[0].startswith(b":"):
                return Scope(True, "Unrecognized change metadata", count)
            old_mode, new_mode = fields[0][1:], fields[1]
            if (old_mode not in REGULAR_OR_ABSENT or new_mode not in REGULAR_OR_ABSENT
                    or fields[4] not in {b"A", b"M", b"D"}
                    or any(not SHA.fullmatch(value.decode("ascii")) for value in fields[2:4])):
                return Scope(True, "Change includes unsupported modes or metadata", count)
            path = entries[index + 1].decode("utf-8", errors="strict")
            if path not in DOCUMENTATION_PATHS:
                only_documentation = False
                if not package_path(path):
                    return Scope(True, "Change includes inputs outside audited packages", count)
        tree = read_tree(repo, head)
        if only_documentation:
            return Scope(False, "Complete exact comparison contains only regular documentation", count)
        return package_scope(repo, previous, tree, job, count)
    except (OSError, subprocess.SubprocessError, UnicodeError, ValueError, RecursionError):
        return Scope(True, "Exact Git comparison could not be established")


def main() -> None:
    result = choose(
        Path.cwd(), event=os.environ.get("APPLE_CI_EVENT", ""),
        head=os.environ.get("APPLE_CI_HEAD", ""),
        base=os.environ.get("APPLE_CI_BASE", ""),
        before=os.environ.get("APPLE_CI_BEFORE", ""),
        job=os.environ.get("APPLE_CI_JOB", ""),
    )
    print(json.dumps(asdict(result), sort_keys=True))
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a", encoding="utf-8") as stream:
            stream.write(f"native_required={str(result.native_required).lower()}\n")


if __name__ == "__main__":
    main()
