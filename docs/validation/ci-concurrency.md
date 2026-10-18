# Cancel superseded PR checks without losing main evidence

Scope: the workflow scheduling slice of [Apple #30](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/30).

Each existing CI workflow uses its workflow name, event type and pull request number
as a concurrency group. A newer run of that workflow for the same PR cancels the
older queued or running revision. Other PRs and other workflows keep their own
checks. All build, native test, contract, artifact and read-only permission steps
remain in place; a cancelled old revision is not a passing merge gate for a new head.

Push events use the unique workflow run ID instead of the branch name. This preserves
every main integration run, including pending post-merge evidence. Merely setting
`cancel-in-progress: false` for main would still allow a shared group's pending run
to be replaced; unique main groups avoid that loss. See GitHub's
[workflow concurrency reference](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency).

The policy applies when GitHub schedules a run using the updated workflow. It does
not retroactively cancel older runs created without a concurrency group, and it does
not cancel checks on a superseded but separate PR. Those require a specific reviewed
cancellation through a capability with Actions write permission.

Local review verifies that all six YAML documents remain valid and their existing
trigger, permissions and job definitions are unchanged. Hosted scheduling/cancellation
behavior requires an actual PR update receipt; it is not established by YAML parsing.
This scheduling change does not complete #30's untrusted-PR, release-secret or
required-check protection acceptance.
