# Retire obsolete PR checks

This [Apple #30](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/30)
maintenance slice complements [#189's concurrency policy](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/189).
Older ungrouped runs and checks on a closed PR can otherwise keep waiting for macOS
capacity. Cancellation is never evidence that a build or acceptance gate passed.

The [workflow](../../.github/workflows/obsolete-pr-checks.yml) runs its safety tests
on relevant PR changes with read-only permissions. The mutation job runs only in
this repository on `main`: after maintenance-file changes, after the existing Python
contract workflow completes, when a PR targeting `main` closes, or through manual
workflow dispatch on `main`. Closing a superseded PR therefore does not depend on
another contract check finishing before its obsolete queued runs can be considered.

The closure hook is limited to `pull_request_target: closed` with a `main` base.
Its job guard checks the repository, `main` ref, event action, closed payload state
and base branch. The Python entry point repeats those guards before constructing
the API client; action/state/base values are passed only as environment metadata.
Both jobs explicitly check out the immutable `github.sha`; for
this event and `workflow_run`, GitHub supplies default-branch code. Ordinary PR
safety tests still use their merge SHA with read-only permissions. The mutator never
checks out the triggering PR's head or consumes its artifacts, caches, body or code.
The event only schedules a pass: the existing live run/PR/head checks still decide
every cancellation, including preserving a PR that reopened after the event.
See GitHub's [closure event and untrusted-code guidance](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request_target)
and [workflow completion behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run).
There is no additional timed automation. Closing a PR whose base is an integration
branch is covered by the existing completion/push/manual passes, not this narrow hook.

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

GitHub's [workflow-run response](https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2026-03-10)
also documents ref-qualified paths such as `.github/workflows/build.yml@main`.
The allowlist accepts the listed exact local paths either unqualified or followed by
one bounded, syntactically checked ASCII Git ref. It rejects unknown workflow
paths and malformed qualifiers. The qualifier supplies no repository or PR
authority, and the complete original path must remain identical at the final
preflight. Current Apple runs inspected on 2026-10-18 used unqualified paths;
the qualified variant is covered by synthetic cancellation/preservation tests.

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
Workflow guard regressions exercise the actual job expression against allowed
maintenance events and rejected PR, reopened, foreign-repository and non-main cases.
They also protect immutable checkouts, the closed/main event filter, job permissions
and the absence of PR code/artifact/cache inputs. These structural checks do not
simulate GitHub webhook delivery; observe a real post-delivery closure run separately.

An accepted `202` is a cancellation request, not a completed cancellation receipt.
The workflow logs exact numeric run and PR identities and the selection reason;
check those runs' later conclusions for hosted behavior. Local tests do not prove
actual queue cancellation, untrusted native negative gates, release-secret isolation,
required-check protection or full #30 acceptance. Those remain separately evidenced.
