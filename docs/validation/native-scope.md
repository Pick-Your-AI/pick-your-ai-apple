# Native allocation from audited Git inputs

This is a bounded scheduling contribution to [Apple #30](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/30).
The existing [contributor gates](../../CONTRIBUTING.md) assign documentation changes
whitespace, links and scope/reference review. Rebuilding unrelated Swift packages
for each receipt or isolated package change consumes native capacity needed by
actual app changes. The selector preserves the documentation rule and adds a
conservative, explicitly pinned proof for unchanged package jobs.

## Exact scope decision

The native/package workflows still trigger on the same pull-request events
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

Each of the five package scope steps supplies its native job's literal `APPLE_CI_JOB` name.
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

The first refresh updated that audit to accepted main
`13e67df89309289b42fd9302c5908041739d9d11`. The intervening accepted work adds
the frozen quality reader and resources, strict Core raw-JSON admission and its
raw-vector replay, bounded Catalog loading, and the stricter XCTest evidence
qualifier. Their complete source/test changes and input readers were inspected;
the five package manifests and app project/scheme remain byte-identical, so the
dependency matrix is unchanged. Core, Transfer and Catalog receive new complete
package-tree pins; Data and UI retain their existing pins.

That surrounding audit contained 38 leaves. It includes the added raw-vector
helper, its contract-preparation workflow step, the accepted mutation qualifier
and tests, and the foreground-maintenance fixture correction below. All other
surrounding pins are unchanged. The selector algorithm, documentation allowlist
and five literal job-name workflow additions are unchanged. This explicit refresh
does not treat earlier native executions as evidence for the newer tree; all
native jobs are allocated for the audit change itself.

The second refresh carried accepted main
`074ae4bffec6066d3fe6e6a5fe47ab429dde54ed`: #268 reconciles the accepted #32
record in two documents, and #257 adds the separately reviewed dependency-policy
workflow, its bounded helpers, controlled regressions and evidence documents.
The new workflow invokes only its own security helpers; the five native workflows,
app sources and conformance input selection are unchanged. The accepted Transfer
README correction updates that package's complete tree pin; the other four package
trees and all seven dependency pins remain identical to the first refresh.

The accepted conformance runner also invalidates an earlier success receipt
before validation and publishes new output atomically. Its new path, link and
failure regressions preserve the frozen input selection and native commands.
That complete surrounding set contained 51 leaves: the earlier 38 paths, with
new exact runner/harness blobs, plus all 13 accepted dependency-policy leaves,
including its documents and fixtures. None received a documentation exemption.
The selector, fixture tests, allowlist, job closures and five native workflow
bodies remained unchanged at that refresh. The
completed native executions at source `a650f4039c067a178d725c6c9238b6c660ac6a97`
retain their exact test-merge `c4cb02f3f3ce97cc6b9ac1463122735f43c91802` and tree
`34f35205789e36b5fd57413199f6d45d29597742`; the later input refresh allocated
all five jobs and required its own current-source checks.

The third refresh carried accepted main
`d0537ace2cb0a14cdbb5f316a79e972e427ae63c`. Accepted #279 adds the separate
[submission SDK workflow](submission-sdk.md), its verifier and rejection tests,
and exact Xcode/SDK pins. It also records the generated native app metadata and
updates the app project's generated orientations and explicit header-search
setting. The project dependency pin therefore changes, while all five package
manifests, complete package roots, shared scheme and dependency closures remain
unchanged. Accepted #283 reconciles two historical toolchain receipt documents;
those documents add no executable input.

The new aggregate `submission-sdk` scope step deliberately supplies no
`APPLE_CI_JOB`. It retains the conservative documentation-only decision: every
non-document change runs its five package suites and app builds under the
separately pinned toolchain. No package-specific skip rule is added for that lane.
The accepted policy/SDK guides join the documentation allowlist only as
explanatory material; the verifier reads the JSON pins and built product
metadata, not those guides.

That surrounding audit contains 56 leaves. Its five additions are the
submission workflow, verifier, verifier tests and two JSON pins. Six existing
entries change: the app project, native UI workflow, selector, scope regressions,
obsolete-run helper and its regressions. These retain the accepted metadata
capture, two documentation exemptions and exact submission-workflow retirement
support; no other scheduling algorithm or job dependency changes. This input
refresh itself allocates all six native jobs. Completed observations at source
`9b5a10b5097292a1544b29c088c430d66f771eb1`, prepared merge
`46ad9e8704599307564440bbd299fb79066727a1` and tree
`84bb94356310b671b8d009cdac695ff03be2e78e` retain that earlier scope, and do not
constitute execution of this later combined tree.

A fourth input refresh was reviewed against accepted main
`51952c75f2280d57891491903e495fb822b83bfd`. Accepted #276 adds the frozen
ResourceEstimate structural reader, its schema and example, deterministic raw
vectors and native/reference tests inside `PlannerTransfer`. The shared validator,
source manifest, reference runner and package README retain the accepted resource
entry points. The complete reader and test inputs were inspected: native resources
come from that package's declared bundles, and the reference generator and runner
read its own pinned schemas and fixtures. No sibling package, app or surrounding
repository input is introduced. Only Transfer's complete package-tree pin changes;
all seven dependency pins, the five job closures, four other package trees and
56 surrounding leaves remain identical to the third refresh. The accepted #289
service-decision handoff changes three explanatory documents without adding an
executable input or modifying a native gate.

That resource refresh requires all six native jobs. Executions at source
`c069a02da98c56c3a019292e51821fcd909df66b`, prepared merge
`22016874005cdf3a54594ba3d44cbf8732700972` and tree
`e4b67127d22b4d4939aa590867135a7c22a21fe2` retain that earlier source scope;
they do not execute that resource/input refresh.

A fifth input refresh was reviewed against accepted main
`bcf4c771641e62b30812e67bff86cf6b221c92cb`. Accepted #284 declares Catalog's
privacy manifest as a processed SwiftPM resource and adds a test that reads the
built package bundle through `Bundle.module`. The complete manifest, package
declaration, test and explanatory documents were inspected for input selection.
The resource and generated bundle access stay within `PlannerCatalog`; no sibling
package or new app input is introduced. Catalog's package-manifest dependency pin
and complete package-tree pin change. The other six dependency pins, four package
trees and all five job closures remain unchanged from the resource refresh.

The surrounding audit now contains 57 leaves. Its sole addition is the accepted
`docs/validation/issue-101-privacy.md` blob; the previous 56 entries are unchanged.
This new document receives no documentation exemption. The selector, its 32-test
fixture and the five package workflow bodies remain unchanged. This bounded input
review does not requalify the accepted privacy inventory or establish app-bundle,
network, release or store evidence. The audit update allocates all six native jobs
and requires fresh checks for this combined tree; the earlier `c069a02d` execution
identities above do not execute this later resource and privacy input refresh.

The sixth input refresh additionally carried accepted main
`9c744450d689690f66ab6a28aa146a1318917464`. Accepted #298 rejects a corrupt
restoration source newer than the current draft head, before either head or
history writes, while preserving normal save, rename and duplicate behavior.
Its full restore/write/transaction/decode context and focused regression were
inspected. This changes only the complete `PlannerData` tree within the existing
storage, Transfer-test and UI closures; all seven dependency pins, four other
package trees and the five dependency relationships remain unchanged.

The accepted storage workflow requires the new named restoration regression and
26 successful simulator cases while retaining its interrupted-migration gate.
The selector's original literal `APPLE_CI_JOB` entry remains its only change
against that accepted workflow. The complete surrounding set still has 57 leaves;
only this composed storage-workflow pin changes from the fifth refresh. No other
selector, fixture, documentation allowance, native job identity or command changes
in this input update. Every native job remains required for the audit update
itself. Earlier 2f78 resource/privacy Python checks and c069/e4 native receipts
retain their original trees and do not execute this new restoration composition.

The current record carries accepted main
`71db949333d94958d7d7909a1dd16c51c2421e2e`, which adds only the reviewed hosted
dependency-drill record and its explanatory guide. Both complete documentation
changes were inspected for input interaction. They retain their historical
workflow, package, failure/recovery and remaining-acceptance identities; this
input refresh does not re-audit those hosted receipts or grant broader dependency,
credential, device or release acceptance.

All seven dependency pins, five complete package trees and five job closures
remain unchanged from the restoration refresh. The surrounding set now contains
58 leaves: the new `dependency-review-hosted-drill.json` is added and the existing
`dependency-review.md` pin is updated. Both are conservatively pinned rather than
given a documentation exemption. The selector, its 32-method fixture and all five
native workflows remain unchanged. This audit update still requires all six
native jobs; earlier source, Python and native receipts retain their original
trees and do not execute this documentation/input composition.

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

That 15-method lifetime receipt belongs to the linked editor checkpoint. The
selector's 32-method suite shares the same corrected setup across its original
and audited-package classes; no assertion or cleanup error is suppressed.

This change schedules future runs. It neither cancels existing main/current-head
runs nor changes [obsolete-run maintenance](obsolete-pr-checks.md). #30's broader
negative native checks, secret isolation, required-check enforcement, device and
release acceptance remain separate, and no complete issue closure is claimed.
