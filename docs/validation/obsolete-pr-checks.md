# Retire obsolete PR checks

This [Apple #30](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/30)
maintenance slice complements [#189's concurrency policy](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/189).
Older ungrouped runs and checks on a closed PR can otherwise keep waiting for macOS
capacity. Cancellation is never evidence that a build or acceptance gate passed.

The [workflow](../../.github/workflows/obsolete-pr-checks.yml) runs its safety tests
on relevant PR changes with read-only permissions. The mutation job runs only in
this repository on `main`: after maintenance-file changes, after the existing Python
contract workflow completes, or through manual workflow dispatch on `main`.
There is no additional timed automation. For `workflow_run`, GitHub uses the default
branch revision; the job explicitly checks out `github.sha`, never the triggering
PR's head, artifacts or cache. See GitHub's [event and untrusted-code guidance](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run).

Only the mutation job requests `contents: read`, `pull-requests: read` and
`actions: write`. The script receives the standard, ephemeral `github.token` through
the cancellation step's environment. The pinned checkout action also uses the
standard token and does not persist credentials. No personal token,
release secret, login, repository setting or branch-protection change is needed.
GitHub documents [Actions write permission for ordinary cancellation](https://docs.github.com/en/rest/actions/workflow-runs#cancel-a-workflow-run)
and [unspecified permissions being disabled](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions).

## Selection and preservation

The [script](../../tools/ci/retire_obsolete_pr_runs.py) only considers queued or
running, first-attempt `pull_request` runs from the six existing validation workflow
paths, with the exact Apple repository ID on both sides. It excludes main-branch,
push, manual, rerun, completed, foreign, unknown and ambiguous runs.

A run must resolve to one matching PR. When GitHub omits closed PR associations,
the fallback requires the same repository, branch and exact SHA to match exactly one
closed PR. A branch name alone never authorizes cancellation. Any SHA currently
used by any open PR is preserved, including an open fork or a different PR.

Immediately before each request, the script refreshes all open PR heads, the exact
run and the matching PR. Cancellation requires a still-closed PR or a still-newer
open PR head. A reopened PR, reverted head, completed run or new run attempt is
preserved. GitHub's cancellation endpoint has no atomic expected-PR-head condition;
a state change after the final read remains an API race. A `409` is logged without
retry or escalation. The script never force-cancels and never deletes logs/artifacts.

Enumeration finishes before mutations change result ordering. Pagination, response
size, request count, per-request time, total time and cancellation count are bounded.
Each pass requests at most 50 cancellations. Incomplete or malformed authoritative
listings stop safely; uncertain individual associations are preserved. Requests stay
on the fixed GitHub API repository path and redirects are rejected. Errors never
print tokens, response bodies, PR titles or branch names.

## Validation and evidence boundary

Run the dependency-free regression suite:

```sh
python3 -m unittest discover -s tools/ci/tests -v
git diff --check
```

The suite uses fake metadata and transport responses; it exercises preservation,
live-state changes, closed-PR fallback, pagination/budgets, redirect refusal and
ordinary cancellation without any real token or mutation. Running the script
without `--apply` is a read-only preview using the same metadata checks.

An accepted `202` is a cancellation request, not a completed cancellation receipt.
The workflow logs exact numeric run and PR identities and the selection reason;
check those runs' later conclusions for hosted behavior. Local tests do not prove
actual queue cancellation, untrusted native negative gates, release-secret isolation,
required-check protection or full #30 acceptance. Those remain separately evidenced.
