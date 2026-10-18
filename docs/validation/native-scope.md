# Native allocation for documentation changes

This is a bounded scheduling contribution to [Apple #30](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/30).
The existing [contributor gates](../../CONTRIBUTING.md) assign documentation changes
whitespace, links and scope/reference review. Rebuilding unchanged Swift inputs for
each acceptance receipt consumes native capacity needed by actual app changes.

## Exact scope decision

The five native/package workflows still trigger on the same pull-request events
and main pushes. A read-only Ubuntu job runs the scope regressions and
[`native_scope.py`](../../tools/ci/native_scope.py) before allocating macOS:

| Input | Native allocation |
| --- | --- |
| A nonempty complete comparison contains only allowlisted regular documentation files | Skip the native job; report the explicit documentation decision |
| Swift, project, workflow, script, schema, data, fixture or unknown Markdown change | Run the existing native job |
| Source renamed to a documentation filename, executable documentation, any symlink/submodule in the head tree | Run native |
| Empty comparison, unsupported event, unavailable/mismatched identity, divergent push, malformed/oversized data or Git failure | Run native |
| Preflight job fails or does not produce the explicit `false` result | Run native; the failed preflight remains visible |
| Workflow cancellation | Respect cancellation; do not restart a cancelled run |

The checkout must equal the event's exact commit. For a PR it must be a two-parent
test merge whose first parent equals the event's base SHA; comparison uses that
base and test-merge tree. For a main push, the event's `before` SHA must be an
ancestor of the checkout. Full history is fetched with persisted credentials disabled.
No branch name or supplied filename is interpolated into a shell command.

The explicit allowlist was audited against the repository's Markdown inventory,
Swift package resource declarations, Xcode project, native scripts and validator
input readers. Its entries are explanatory instructions, decisions, receipts and
READMEs, not schema/vector resources or executable validator inputs. The already
reviewed incoming `App/UI_JOURNEY.md` and this guide are also included. Unknown
Markdown, including files under `docs`, remains a native input until reviewed and
explicitly added. If an allowed document becomes an executable or native test input,
remove its exemption in the same change.

Git's complete NUL-delimited raw comparison retains file modes, deletions and paths
containing newlines; rename detection and external/text conversion drivers are off.
The selector uses a four-MiB conservative inspection bound and 30-second Git-command
timeouts. Exceeding a bound allocates native instead of trusting partial evidence.
GitHub's [event path filters](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#git-diff-comparisons)
currently inspect at most 3,000 changed files; this selector does not use that trigger
filter or a paginated API file list to decide that native inputs are unchanged.

## Preserved checks and evidence

All existing native job names, steps, commands, assertions, action pins, permissions,
timeouts, evidence retention and concurrency remain intact. Contract preparation
continues on the same events, including documentation changes. The scope jobs have
distinct names and emit their observed decision; a skipped native job is **not**
reported as an executed Swift test, SDK build or device journey. No required-check
setting or repository protection is changed. Future branch-protection setup must
include meaningful preparation/scope checks and retain the native job names.

The [15 real-Git regressions](../../tools/ci/tests/test_native_scope.py) cover exact
PR test merges and main comparisons, a 3,006-file mixed change, source deletion and
rename, unknown Markdown/fixtures, executable files, indirect symlink/submodule
inputs, newline paths, invalid identities, divergent history, empty changes and the
actual CLI output. They run locally and on each scope preflight. These Python tests
do not compile Swift or prove simulator execution.

### Disposable Git fixture lifetime

The fixture sets repository-local `maintenance.autoDetach=false` before its first
commit. Automatic maintenance still runs when Git decides it is needed, but the
invoking command waits for it to finish before the temporary repository is removed.
This follows Git's documented [maintenance lifetime setting](https://git-scm.com/docs/git-maintenance)
and does not change the checked-out project's configuration or the scope selector.

The motivating [scope job 117666335194](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39124385062/job/117666335194)
at editor source `8e76d0ee3db9659df4b7c96bef0eb0c70909ea52` ran all 15 methods
using Git 2.55.0. Its submodule case errored during `TemporaryDirectory.cleanup`
with `OSError: [Errno 39] Directory not empty: 'objects'`, after the assertion.
The four sibling scope jobs passed. The original failed receipt is retained;
the conservative fallback still allocates the native job after a scope failure.

A bounded local diagnostic on Git 2.51.1 ran the unchanged submodule method 20
times and the foreground comparison 20 times. Both completed without the hosted
cleanup exception. Git Trace2 nevertheless recorded 60 detached maintenance
children in the first run and 60 foreground maintenance children, with no detach
regions, in the second. This verifies the lifetime mechanism being corrected; it
does not establish the hosted exception's exact interleaving. Cleanup errors are
still fatal, and no retry, assertion removal or native acceptance is implied.

With the repository-local fixture setting, all 15 real-Git regression methods
passed on Git 2.51.1. Their Trace2 receipt contained 34 maintenance children, all
with `--no-detach`, and zero detach regions. Fresh hosted scope results remain
required for delivery.

This change schedules future runs. It neither cancels existing main/current-head
runs nor changes [obsolete-run maintenance](obsolete-pr-checks.md). #30's broader
negative native checks, secret isolation, required-check enforcement, device and
release acceptance remain separate, and no complete issue closure is claimed.
