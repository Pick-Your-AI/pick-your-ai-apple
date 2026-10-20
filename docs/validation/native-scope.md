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
| `macos-core` | `PlannerCore`, `PlannerUI`, `PlannerData`, `PlannerCatalog`, `PlannerTransfer` |
| `macos-storage` | `PlannerData` |
| `macos-transfer` | `PlannerTransfer`, `PlannerData`, `PlannerCore`, `PlannerCatalog` |
| `macos-catalog-cache` | `PlannerCatalog` |
| `native-ui` | `PlannerUI`, `PlannerData`, `PlannerCore`, `PlannerCatalog`, `PlannerTransfer` |

These are entire package trees, including sources, tests, fixtures, resources,
tools and metadata. Transfer's durable boundary test imports PlannerData, and
its synthetic fixture admission tests import Core and Catalog. Its library target
links Core and Catalog; its test target additionally links Data. PlannerUI depends
on PlannerData, PlannerCore, PlannerCatalog and PlannerTransfer.
The Core and UI jobs both execute EvidenceHarness, which explicitly links
PlannerUI and PlannerCore and therefore includes all five package trees.
The UI job's App build also links PlannerUI and its complete dependency closure.
The Core package itself and Catalog declare no sibling package dependencies. A future
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

The seventh input refresh carried accepted main
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

The eighth input refresh carried accepted main
`c23050050c9ce46f35aee73e2f80b7b638cba159`. This batches the separately accepted
dependency/SDK receipt corrections, optimized crash-driver guards, placement
conformance, typed evaluation identity and WAL/schema admission changes. Their
actual source, test and input-reader changes were inspected; this input refresh
does not repeat their underlying acceptance decisions or relabel their native
receipts as execution of this composition.

All seven dependency pins and all five job closures remain unchanged. Three
complete package trees change. Core's typed `EvaluationReport` admission derives
the existing input identity within that package; its tests read Core's declared
fixture bundle. Data's existing CSQLite bridge disables checkpoint-on-close before
schema admission; its new WAL and hot-journal tests use synthetic files within the
existing package test target. The complete Data tree remains in the same Storage,
Transfer-test and UI closures. Transfer's placement generator, 98-vector fixture,
four Swift methods and appended reference checks read only its own declared
resources and fixtures. No new sibling package, app input or external resource is
introduced. Catalog and UI package trees stay exact.

The surrounding map now contains 62 leaves: four additions and ten updated
entries against the seventh refresh. The additions are the two accepted immutable
Transfer-license fixtures, their test module and the seven-method crash-driver
fixture. Updated pins cover the dependency workflow/guard/rehearsal and existing
tests, its conservatively pinned explanatory guide, SDK receipt helper/tests,
and the composed storage workflow and crash driver. The SDK helper preserves its
separate pin/product inputs and invalidates stale receipts before new verification.
The dependency workflow's mandatory final guard still requires the original action
and complete snapshot outcomes; this refresh does not install or execute its
reviewed installer artifact or re-audit its license.

The storage workflow preserves the accepted seven portable driver controls,
interrupted-migration and restoration guards, and 31 required simulator cases.
Its sole selector difference from accepted main remains the original literal
`APPLE_CI_JOB` entry. The other four package workflow bodies, selector algorithm,
32-method fixture, documentation allowlist and native context names are unchanged.
The separate aggregate SDK lane still has no package-job identity and therefore
retains native for every non-document change. No new scheduling exemption is
introduced; this audit change allocates all six native jobs.

The completed source-stage receipt at prepared
`c417639382a427ba449588168cbb83f30f149f3d`, tree
`2f3cd050e5d2c7158ff189b51fb2278145481c4f`, belongs to the seventh refresh and
its normally signed child `930cf4c5a920f4af043ec3aaf51b9f78f4fa96f8`.
Those nine portable and six native results remain precisely scoped there. They
do not execute this later package/input composition, its 31-case Data suite or
new placement and typed-identity cases. That audit requires its own
independent input review and applicable hosted gates before final main delivery.

The ninth input refresh carries accepted main
`cd098e8e19f5e4a1d90112379bc8ca089d81ec93`. Accepted #275 adds the canonical
pricebook test fixture, its synthetic admission suite and a dated fixture inventory.
Its Transfer test target explicitly adds local Core and Catalog products alongside
Data. The tests use those existing decoders/cache APIs and their own declared
fixture bundle. They add no external service, app data or unpinned resource reader.

Transfer's dependency closure therefore expands to all four complete Transfer,
Data, Core and Catalog package trees. The other four job closures remain unchanged.
Only the Transfer package-manifest pin and its complete package-tree pin change
from the eighth refresh; the other six dependency pins and four package trees are
preserved. The surrounding map has 63 leaves: the new fixture-inventory document
is conservatively pinned, and the selector and its two added regression methods
receive new pins. The other 60 surrounding entries stay unchanged. No documentation
exemption, workflow command, native context, comparison bound or fallback changes.

Before this refresh, the changed manifest already conservatively allocates every
native job. Refreshing that manifest pin while retaining the former two-tree
Transfer closure would incorrectly permit a Core or Catalog change to skip its
Transfer test job. A real-Git regression reproduced both wrong skips against the
unchanged selector using that incomplete refreshed record. The expanded closed
footprint rejects that legacy record. The complete 25 job/package matrix and
added/deleted Core and Catalog resource cases also retain the intended selective
behavior with a correct record. These 34 Python regression methods are scheduling
evidence; they do not compile or execute the new Swift admission tests.

This selector and audit correction allocates all six native jobs and requires its
own exact-source gates. The reviewed eighth-refresh tree
`88239a9a583512ba5b77fdf58bd95e9c5575292e`, its 32-method local run and the older
signed `930cf4c5` native receipts remain at their original identities. None is
reported as execution of this new dependency closure or receiving composition.

A drift is a safe allocation decision, not a request to refresh hashes blindly.
Before updating the record, independently inspect the changed native code and
tests, all package manifests, resource readers, app project/scheme, workflows and
transitive inputs. Preserve or conservatively expand the dependency matrix if
inputs changed. Derive the new object identities from the reviewed Git tree and
verify the complete surrounding set independently. The audit file is not itself
a package or allowlisted document: its update, like a selector or workflow change,
allocates every native job and must pass its own review and applicable gates.

### Rendering dependency correction without a pin refresh

Source inspection at accepted main
`a3365dac377263aa2595f5d210c0918f1e29b5ab` found three missing job/package
relationships. The Core workflow's actual iPhone/iPad rendering command and the
UI workflow's macOS rendering command both use the checked-in
[`EvidenceHarness` project](../../tools/evidence-rendering/EvidenceHarness.xcodeproj/project.pbxproj).
Its local package products are PlannerUI and PlannerCore; the
[`PlannerUI` manifest](../../Packages/PlannerUI/Package.swift) additionally links
PlannerData. The Core scope therefore needs UI and Data as well as Core, and
the UI scope needs Core as well as UI and Data. These inputs are required by
existing commands, even when the primary package's own test command is unchanged.

The current audit's older manifest, surrounding-input and package pins already
retain native allocation on current source. No skipped real workflow is claimed.
The unsafe case is a future refresh that updates object hashes but retains the
old incomplete job matrix. A new real-Git regression, run against the unchanged
selector at `a3365dac`, reproduced all three false skips: UI and Data changes
skipped `macos-core`, and a Core change skipped `native-ui`.

The correction conservatively expands those two required closures. The audit
adds the same historical Core, Data and UI tree objects already pinned in its
other job entries. Its source revision `cd098e8e`, all existing object pins,
dependency entries and surrounding-input entries remain unchanged. **This is
not a pin refresh and does not authorize new skips for current source.** A later
refresh still needs the complete independent input review described above.

The two new methods cover rejection of all three legacy closures and six added
or deleted dependency-resource cases. The independent 25-combination matrix and
existing Transfer-resource expectations now include the rendering dependencies;
unrelated Catalog and Storage cases still verify legitimate selective allocation.
These are Python tests in disposable Git repositories, with no Swift, Xcode,
simulator or app execution. The corrected complete suite passed all 36 methods
with zero failures, errors or skips in 8.627 seconds on Linux CPython 3.12.14.
The original single-method reproduction reported three assertion failures in
0.273 seconds; the later pass does not relabel that failure. Workflow bodies,
action pins, contexts, runtime
assertions, timeouts, permissions, concurrency and current runs are unchanged.
The correction itself requires all applicable hosted/native gates and independent
review before ordinary delivery. Whole #30 remains open.

## Preserved checks and evidence

All existing native job names, steps, commands, assertions, action pins, permissions,
timeouts, evidence retention and concurrency remain intact. Contract preparation
continues on the same events, including documentation changes. The scope jobs have
distinct names and emit their observed decision; a skipped native job is **not**
reported as an executed Swift test, SDK build or device journey. No required-check
setting or repository protection is changed. Future branch-protection setup must
include meaningful preparation/scope checks and retain the native job names.

The [36 real-Git regressions](../../tools/ci/tests/test_native_scope.py) cover exact
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
selector's current 36-method suite shares the same corrected setup across its original
and audited-package classes; no assertion or cleanup error is suppressed.

This change schedules future runs. It neither cancels existing main/current-head
runs nor changes [obsolete-run maintenance](obsolete-pr-checks.md). #30's broader
negative native checks, secret isolation, required-check enforcement, device and
release acceptance remain separate, and no complete issue closure is claimed.
