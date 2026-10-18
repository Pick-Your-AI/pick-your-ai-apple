# Native allocation from audited Git inputs

This is a bounded scheduling contribution to [Apple #30](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/30).
The existing [contributor gates](../../CONTRIBUTING.md) assign documentation changes
whitespace, links and scope/reference review. Rebuilding unrelated Swift packages
for each receipt or isolated package change consumes native capacity needed by
actual app changes. The selector preserves the documentation rule and adds a
conservative, explicitly pinned proof for unchanged package jobs.

## Exact scope decision

The five native/package workflows still trigger on the same pull-request events
and main pushes. A read-only Ubuntu job runs the scope regressions and
[`native_scope.py`](../../tools/ci/native_scope.py) before allocating macOS:

| Input | Native allocation |
| --- | --- |
| A nonempty complete comparison contains only allowlisted regular documentation files | Skip the native job; report the explicit documentation decision |
| A complete regular package-only comparison, optionally mixed with allowlisted documentation, preserves the job's full audited inputs at both endpoints | Skip that job; report the exact job identity and audited-input decision |
| A job's package tree changed, or differs from its reviewed pin at either endpoint | Run that job |
| A dependency manifest, surrounding repository input, audit record, project, workflow, external script or unknown path changed or differs from its pin | Run all native jobs |
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

## Audited package inputs

Each existing scope step supplies its native job's literal `APPLE_CI_JOB` name.
The five existing scope context names retain their historical `documentation scope`
suffix so no required context disappears. An absent or unknown job identity retains
the original behavior: only the documentation rule can skip native allocation.

[`native-inputs.json`](../../tools/ci/native-inputs.json) records complete Git tree
objects for the following dependency closure, including test targets:

| Native job | Complete package trees that must match at both endpoints |
| --- | --- |
| `macos-core` | `PlannerCore` |
| `macos-storage` | `PlannerData` |
| `macos-transfer` | `PlannerTransfer`, `PlannerData` |
| `macos-catalog-cache` | `PlannerCatalog` |
| `native-ui` | `PlannerUI`, `PlannerData` |

These are entire package trees, including sources, tests, fixtures, resources,
tools and metadata. Transfer's durable boundary test imports PlannerData even
though its library target does not. PlannerUI and the app also depend on
PlannerData. Core and Catalog declare no sibling package dependencies. A future
test that reads another package's fixture without changing `Package.swift` still
changes its own package tree, so that job remains allocated until explicitly
reviewed again. Source additions, deletions and renames participate in the same
complete comparison; a filename suffix never hides a test resource.

All five `Package.swift` files and the app's project and shared scheme must also
match their exact audited objects. In addition, the audit pins **every tracked
non-document leaf outside the five package roots**, excluding only the audit
record itself. This includes workflows, the selector and its regressions, app
sources/toolchain/scripts, conformance tools, storage replay and root configuration.
The selector compares the complete set, modes, types and hashes at both endpoints.
An added root attributes/configuration file cannot escape the audit merely because
it was introduced before the current package-only change. A surrounding-input
drift conservatively runs all jobs even when it may affect only one of them.

The record is read from the exact checkout commit's regular Git blob, with a
64-KiB bound, strict field/key/object validation and duplicate-key rejection.
Untracked or modified working-copy JSON cannot replace it. The same record must
exist at both endpoints, and its audited source revision must be an ancestor of
the comparison base. Missing/deleted package roots, malformed pins, unsupported
modes, linked trees, non-ASCII/control paths and failed reads retain native
allocation. No fallback guesses dependencies or accepts a partial file listing.

### Audit maintenance

The initial package/dependency audit uses accepted source
`8ca109963bfca3a707b1af8b80aabcd9dd28fd8a`, including the accepted independent
library/history recovery. Its surrounding-input pins include this selector and
regression update plus the five literal job-name additions. Every native job body,
action pin and command remains identical to that accepted base.

A drift is a safe allocation decision, not a request to refresh hashes blindly.
Before updating the record, independently inspect the changed native code and
tests, all package manifests, resource readers, app project/scheme, workflows and
transitive inputs. Preserve or conservatively expand the dependency matrix if
inputs changed. Derive the new object identities from the reviewed Git tree and
verify the complete surrounding set independently. The audit file is not itself
a package or allowlisted document: its update, like a selector or workflow change,
allocates every native job and must pass its own review and applicable gates.

## Preserved checks and evidence

All existing native job names, steps, commands, assertions, action pins, permissions,
timeouts, evidence retention and concurrency remain intact. Contract preparation
continues on the same events, including documentation changes. The scope jobs have
distinct names and emit their observed decision; a skipped native job is **not**
reported as an executed Swift test, SDK build or device journey. No required-check
setting or repository protection is changed. Future branch-protection setup must
include meaningful preparation/scope checks and retain the native job names.

The [32 real-Git regressions](../../tools/ci/tests/test_native_scope.py) cover exact
PR test merges and main comparisons, a 3,006-file mixed change, source deletion and
rename, unknown Markdown/fixtures, executable files, indirect symlink/submodule
inputs, newline paths, invalid identities, divergent history, empty changes and the
actual CLI output. The package cases exercise all 25 job/package combinations,
transitive test dependencies, new resources, stale reader changes, both comparison
endpoints, all seven dependency pins, prior root/workflow/helper drift, corrupted
and duplicate audit data, input bounds, and committed versus working-copy audit
identity. They run locally and on each scope preflight. These Python tests do not
compile Swift or prove simulator execution.

This change schedules future runs. It neither cancels existing main/current-head
runs nor changes [obsolete-run maintenance](obsolete-pr-checks.md). #30's broader
negative native checks, secret isolation, required-check enforcement, device and
release acceptance remain separate, and no complete issue closure is claimed.
