# New imported-build, catalog and T6 receiving preparation

## Route-captured child disappearance correction

Date: 2026-10-19. This bounded correction starts from actual published #391 source
`545e8dfc2ae2c1bad7db53c428636cb20ffc567b`, tree
`95167b7520bcdd19ec780fa673531750478a320e`. Production/test checkpoint
`0eefbda58e14a376304fee9e0280374d529664a1`, tree
`657c1fb8d40263c086b488b1e5844979fa011262`, is an isolated local child of that
exact source. It is not a native execution or a published receiving revision.
The complete earlier source, review and observation record remains below; its
source-time inventory statements retain those historical identities.

The actual [review 5575287272](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391#pullrequestreview-5575287272)
identified a source-control-flow counterexample. The real child destination shared
one T6 model and called its unbound disappearance handler. After Back withdrew
route A and the same retained Build reopened as route B, a delayed child callback
from A could cancel B's completed content or pending work when no Files request
was active. The earlier Back-binding ABA case created a fresh importer, so it
did not cover that no-Files path. The separate Apple receiving read confirmed the
chain in [6273900420](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391#issuecomment-6273900420).
Neither finding observes SwiftUI delivering that callback order or claims an
executed Swift regression/native failure.

The library body now captures one immutable route value for both the actual Back
binding and its destination. The destination supplies the model's
`t6DisappearanceHandler(for:)` factory to `T6ReviewView`; the saved callback checks
its captured opaque route, active library, selected row and full snapshot before
calling the existing T6 disappearance method. A stale or absent route returns
without mutating the current model. Both the factory and stored callback retain
explicit MainActor isolation. The existing standalone `init(model:)` keeps the
model's ordinary disappearance behavior; the route-aware initializer is internal.

The existing Files check and explicit route-withdrawal cancellation remain intact.
A current child with no owned Files request cancels ordinary review work/content;
a current owned importer/exporter retains its exact terminal callback. Back, tab,
selection and library-owner withdrawal still retire those requests explicitly.
The new internal preparation argument reuses `T6ArtifactPreparation` and its
Sendable closure for deterministic pending-work cases. The public initializer
still selects the live preparation and starts with no Build; it grants no caller
the ability to substitute a preselected T6 model.

Six new real-store Swift method declarations use the same production callback
factory as the destination. They specify stale same-Build completed-content and
pending-work preservation without Files, current completed-content cancellation,
current pending-work cancellation with late success/failure and fresh retry,
both importer kinds, and all three exporter terminal outcomes. The latter cases
also deliver the old callback after Files has finished so Files protection cannot
mask the no-Files defect. Each checks retained row bytes. All eight earlier
navigation method bodies and every other existing Swift test remain unchanged.
These are required behavioral assertions, not locally executed Swift results.

The current source inventory is **198 UI / 651 total package declarations**:
146 Core, 34 Data, 181 Transfer, 92 Catalog and 198 UI. All six App journeys,
their 24 runner controls, workflows, SDK/toolchain guards, historical audit pins,
timeouts and the complete T6 evaluator/report preparation sources remain exact
to `545e8dfc`. The mandatory UI profile adds all six exact class/method pairs;
every receipt-parser function remains byte/AST-identical. An additional portable
control rejects a modeled old 192-case receipt padded to the new count.

At 18:18:57 UTC, before attendance registration, the same 15 Python controls
reported two failures: the new identities were absent and the required source
count was still 192. After registration, Python 3.12.14 ran all **15 controls** at
18:19:17–18:19:18 UTC: **15 passed in 0.411 seconds**, no failures/errors/skips.
The original red log is 4,237 bytes, SHA-256
`04926a613e0ff89cfa4f44da1742f0377614352f66827f712390b5c01f78f9bf`;
the original green log is 2,950 bytes, SHA-256
`f575a2e99dae6c9c0f1469518121ff7f6e836fd6741329ec6916d8a80eb2fd13`.
These executions qualify portable receipt controls and source attendance only.
No local Swift compiler, pinned Xcode compilation, simulator, Files UI or native
journey is claimed. The queued `545e8dfc` jobs keep their exact original scope;
the corrected receiving source still requires its own configured native evidence.

## Current regular-file admission carry

Date: 2026-10-19. After the fixed `761e8952` composition below was prepared,
accepted #398 delivered signed `bd289eb074c055bdf9ed1d74d1ab6fe729c778b9`,
tree `4970c9db4bfd6552b26dc4208836301e95786812`, sole `761e8952` parent.
Its four-file change directly affects the selected SDK/pin input boundary. The
current source receives that bounded correction while retaining the complete
earlier composition and original 46-method observation as history below.

`read_bounded` now opens with nonblocking POSIX admission and checks the actual
opened descriptor for a regular file before reading. Rejected descriptors close;
regular-file symlinks and the existing maximum-plus-one budgets remain supported.
The independent accepted-source review
[5574875791](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/398#pullrequestreview-5574875791)
retains its original FIFO timeout and corrected-result scopes. The in-session
Apple receiving review separately read the complete four-file carry and the
unchanged enclosing toolchain/receipt boundary. Three new methods exercise real
FIFO pin/metadata rejection, safe receipt/environment handling and regular-file
symlink recovery; three stream-mock targets adapt to the new opener without
changing their byte-budget assertions. Every other earlier method body remains.
The accepted App guide removes changing discovery counts from its historical
simulator row. Its [current handoff](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391#issuecomment-6272616352)
asks the receiving table to use `Xcode-pin, smoke-runner and SDK guards`; that wording
is preserved. The source inventories remain **11 pin / 32 smoke / 38 SDK** at this
exact preparation.

Native Git composition of that accepted source with the reviewed T6 preparation
is exact local `640e60a47db942356925fcb34cea82c30c10a587`, tree
`205a5d8d8e0b1419e23972472a6fde3db6a2ce7a`, with no merge conflict.
On that immutable local source, Python 3.12.14 ran all **49 SDK/pin methods** at
16:58:49–16:58:57 UTC: **38 SDK plus 11 pin**, 8.436 seconds, zero
failures/errors/skips. All 385 tracked source entries were hashed before and after;
their bytes and modes remained unchanged. The 10,309-byte original log hashes to
`245f59aa2d258a329850b441b1ba79cd6e0135be826a1910d73e0128ea302255`.
The complete exact source-defined method attendance and original footer were
checked without another run. Its case-alias control observed the distinct-directory
branch on this Linux filesystem; no case-insensitive host observation is implied.

This later source changes no T6, native runner, workflow, reference input, deadline
or accepted scope-audit binding. Its final documentation-only inventory/history
amendment changes no executable or test byte. The earlier 46-method run remains
at `ee1fb1f1`; the separate T6 14/24 observations remain at their original source.
No actual Xcode, Swift, simulator, Files-save or new hosted result is inferred
from either portable observation. The final published receiving revision still
requires all configured native gates and original-result qualification.

## Accepted-main composition and original portable observation

Date: 2026-10-19. This current preparation combines the independently reviewed
T6 follow-up `eed67f92ed6ad86f95418c992078c00218c4390f`, tree
`96820578948b3fd56a0999b006a27f73529d32e4`, with accepted main
`761e89526c7afcab1830c66a15b4f865889fe567`, tree
`5073585e50c7ad0474706ef456d88741f7e51c2e`. It remains a normal descendant
of published #391 source `9e7cc629`; neither a new donor lane nor a change to the
historical #198 ref is created. The local source/tree and actual hosted receiving
revision must retain separate identities when published and qualified.

The original fixed #391 source was independently reviewed in
[5574336544](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391#pullrequestreview-5574336544)
and [5574484483](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391#pullrequestreview-5574484483).
Those reviews retain their fixed `9e7cc629` / `101b3cfd` scope. The in-session
Apple engineering reviewer separately read the complete T6 successor production,
receiver tests, journeys, mandatory inventories and documentation, verified all
six exact non-App donor blobs, and reproduced its complete 383-leaf tree. All
165 previous UI method bodies and the original journey bodies/helper remain
exact; the added cases and their portable observations are specified below.
That review performed no Swift, native or portable suite rerun.

### Exact accepted inputs and joins

The previously prepared signed #391 receiver
`ee1fb1f1802984e5732f251f79972865e1d805c0`, tree
`8003193e273b0713ce9c041b79c1960e3fb0645b`, has ordered parents
`269ff82dc50a24a5f44d6c2caee0c066abe20d78` and `9e7cc629`.
The complete 24-path `0e289d81` to `269ff82d` source carry was read and its
382-leaf composition independently reconstructed. It receives these bounded inputs:

- #380 limits actual Xcode/SDK pin reads to 4,096 bytes and Info.plist reads to
  1 MiB, rejecting before decoding or allocating an unbounded input. Existing
  protected input/receipt functions remain exact, as do every earlier SDK/pin
  test body. Four SDK and two pin methods extend the current source inventory.
- #369 retains the original synthetic support-intake record and its remaining
  private receiving/operational limits; this consumer adds no operational receipt.
- #373 rejects ambiguous or invalid acceptance-row identities before constructing
  its lookup, preserves the historical inventory, and adds both normal and
  optimized checks without treating pull requests as issue rows.
- #285 was actually delivered at signed `b35414a8b665bd4f8ea910860edea77537b89028`.
  Its catalog-envelope implementation/test/schema/manifest paths already equal the
  selected source. The ninth reference phase and earlier original observations
  retain their own scope; no new native result follows from byte preservation.
- #389 and signed `72b44ae1d37a594ed18be41441c8353799c48052` correct only the
  historical rendering and SDK/pin rows in the App guide. Those literal historical
  rows remain intact; the current inventory above them is separately 10 pin,
  32 smoke and 36 SDK methods.

The later accepted `aaae0b19` contribution guide adds the proposed team model and
effective-grant distinction. This source carry changes no access or repository
rule. Accepted #393 at `761e8952` correctly identifies Core as a Transfer library
dependency and Data/Catalog as test dependencies. The one shared paragraph keeps
that clarification and this integration's actual five-package Core/native-UI
closure, CostHarness and App journey inputs. Every selector, historical audit pin
and method remains unchanged. The only other manual joins update the current
App inventory and this dated source-intake record.

### Original portable execution on the earlier literal receiver

On exact `ee1fb1f1` / `8003193e`, Python 3.12.14 executed
`python -m unittest -v test_submission_sdk test_toolchain` from
`App/scripts/tests` at 16:22:34–16:22:42 UTC. All **46 methods** passed:
**36 SDK plus 10 pin**, 7.985 seconds, zero failures/errors/skips. Every tracked
source byte was independently hashed before and after and remained unchanged.
The original 9,701-byte log has SHA-256
`97b55d38daaae1e13f5ffc9fc87ec70f8627931ca1a52552103d76586c02ef7e`.

An initial output-only parser expected each success on one line and undercounted
four cases whose expected CLI diagnostics preceded `ok`. The original run had
already returned exit 0 and `Ran 46 tests` / `OK`. A corrected output-only reader
verified every exact method block, terminal result and footer; no suite rerun
replaced the original. This result is not execution of the later T6 composition,
Swift typechecking, either Release product or a simulator application.

Current source requires **645 Swift declarations** across the five packages,
including **192 UI**, and **six real App journeys per pinned destination**.
The exact T6/runner/attendance inputs remain the reviewed successor; the SDK/pin
production and guard inputs remain exact to the literal portable observation.
All configured checks must qualify their actual new receiving source. Neither
old queued work nor an earlier component result is relabelled as its execution.

## T6 report and route lifecycle follow-up

Date: 2026-10-19. This is a focused successor to the published, fixed #391 source
`9e7cc6296dda07addc65c03b76287b5800ead59f`, tree
`101b3cfd8474916202bee331534c7b75b99e4ff7`, whose sole parent is accepted
`0e289d81428068a0a3196cde064fda536c71691b`. The fixed preparation and all
its original source/native limits remain in the complete historical record below.
This follow-up does not modify historical #198, the donor branch or the separately
owned later-main carry. Source checkpoint `2707ca331de9969ce88ccd10cb6345edba7441f0`
is a local immutable commit, not a published or executed receiving revision.

### Exact successor input and scope

The actual [T6 handoff 6269003189](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198#issuecomment-6269003189)
selects immutable donor `394ff3ba1547b0ae59d18afa374879801808eaac`, sole
`a8c601d8c1cc1bd17f2a57f8a6489448c72611b9` parent, tree
`91fca44586e70252d758cc87c547faf56e013b47`. All seven complete changed
files were read and independently hashed against the actual remote source.
The six non-App paths are copied byte-for-byte: T6 model/view/report, both full
model/report test files and the complete donor T6 guide. The three original
Build/Quality/Manifest fixture bytes and artifact preparation remain unchanged.
The App journey retains the entire prior receiver helper and both original bodies,
appends the exact third donor body, and adds one separately identified receiver
journey. No original assertion or method is replaced.

The new UTF-8 report is a bounded human-readable disclosure projection of the
exact reviewed proposed plan. It is not an executable plan, private-pair format,
shared-schema change, rights receipt or approval/deployment action. It preserves
reported counts and declarations, withholds the stated private fields and reference
addresses, requires review of the exact preview and uses the actual system Files
terminal result. The donor's conditional disappearance policy preserves a pending
owned importer/exporter, including the interval before its terminal callback.
This was a source integration requirement, not an observed native Files failure.

### Concrete receiver lifetime changes

The former unbound navigation link supplied no explicit route-withdrawal signal.
The App now binds its actual selected tab and notifies
`ImportedBuildLibraryNavigation` synchronously before changing that selection.
The navigation owner attaches weakly to the actual retained library model; replacing
that model withdraws the old route. Reattaching the same active model and an owned
Files presentation do not masquerade as tab withdrawal. Standalone library callers
may omit this optional App owner; their actual T6 navigation binding still owns
Back cancellation, and a separate host withdrawal must use the explicit owner.

Each T6 opening captures a fresh opaque route, local record ID and complete immutable
BuildSnapshot. SwiftUI uses the same captured Boolean binding tested by the receiver
cases. Its false setter cancels only that exact route. A late old setter cannot
cancel a fresh route for the same Build. The destination modifier is outside the
Form's lazy content, within the existing NavigationStack. No new compatibility
producer or default result is introduced; an ordinary first review/retry explicitly
shows absent evidence.

An actual Back action, tab change or library-owner replacement calls `cancel()`.
A changed selected row or complete snapshot withdraws the route before adoption;
a local label-only revision retains it. Selected deletion and the explicit
**Close selected build** action call `clear()` and retire the route. Close performs
no storage deletion. Failed opens or conflicted deletes keep the prior selected
route, while a committed deletion of another row leaves its request intact. Files
callbacks still need their original donor token; after withdrawal, stale success,
failure and cancellation cannot publish a notice or borrow a new same-Build route.
Retained inputs recover only through a newly selected route and explicit retry.

The eight new real-store Swift methods cover: active selection and one route;
Back with each importer plus late callbacks and recovery; tab withdrawal of an
owned exporter versus same-tab reappearance; same-Build route ABA; local label
versus changed-lock identity; other/selected deletion; close without data deletion;
and failed storage actions versus actual library-owner replacement. These are
source declarations using the production binding/owner, not a Python simulation
or an executed native result. The six previous store-binding methods remain exact.

### Current inventories and bounded local observations

On this exact fixed #391 base, the required package inventories become 146 Core,
34 Data, 181 Transfer, 92 Catalog and **192 UI**: **645 Swift declarations**.
The UI increment is 19 exact successor model/report methods (22 plus 16 donor
methods in total, preserving all 19 earlier model methods), plus eight receiver
methods. Every one of the original 165 UI method identities and bodies remains.
The existing receiver now requires all 192 exact class/method pairs; every parser,
summary, duplicate, failure and skipped-case rejection function is unchanged.

The App requires **six actual journeys per pinned destination**: the two original
Notes/Catalog cases plus four T6 cases. Its original helper, original two T6 bodies
and donor third body retain their source identities. The new fourth T6 body uses
normal tab controls and requires route withdrawal before fresh retained-input
recovery. The workflow changes only its descriptive four-to-six step label; it
continues invoking the same `--suite all` command. No runtime, SDK, timeout, simulator
ownership, retry, result or cleanup policy changes. Historical scope audit bindings
and source revision remain untouched, so this source does not refresh skip authority.

Actual portable observations on 2026-10-19 are separate from Swift execution:

| Observation | Exact local result and interpretation |
| --- | --- |
| Before attendance registration, 16:29 UTC | The 14-method model receiver run fails one source-inventory check with all 27 added identities missing. The 24-method journey runner run fails three inventory/older-receipt assertions. Both complete failed logs remain retained. |
| After registration, 16:30 UTC | All 14 model-receipt controls pass (0.388 s), and all 24 journey-runner controls pass (0.059 s), with no failures/errors/skips. They exercise receipt parsing, exact source inventories, same-count substitutions and earlier receipt rejection; they do not run Swift or an Apple UI. |

No local Swift toolchain is installed. The 192 Swift UI methods, four T6 journeys,
actual native compilation, complete current package/source inventory, system Files
save/readback/failure recovery and all existing receiving gates still need their
literal native observations. The donor's original 22 canonical input controls and
all older component/SDK/rendering results retain their own original source/date/
configuration and are not relabelled as execution of this successor.

The separate current-main contribution owns its SDK/pin/profile additions and
accepted documentation. A later composed source must combine those exact current
inputs with this follow-up, retain every old method and receipt, and qualify the
actual resulting native source. The fixed-base totals above do not assert the
inventory or execution of an as-yet-uncomposed later main.

## Retained fixed #391 preparation

The complete earlier source record follows. Its selected-donor, reserved-export,
618-method and four-journey descriptions are historical to the fixed source above;
the explicitly dated follow-up selects the later report source and new requirements.


Date: 2026-10-19. This record describes the new isolated source preparation selected
in [coordination 6268490006](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198#issuecomment-6268490006).
It is an integration contribution to the existing Apple work, not an acceptance
record that closes its component issues.

## Selection and source authority

The selected base is signed main
`888cb7e71017b57a881659bb11074250aa236778`, tree
`7ea95fb4d3ec06e746148e0fc834effd7aca525b`. Its accepted #378 documentation row
and every unrelated main entry are preserved. This preparation composes accessible
immutable donors and identifies its new joins explicitly. It does not recover or
claim the absent historical `a505310b` / `89000e74` checkpoint.

The earlier separately inspected receiving base was signed main
`a3365dac377263aa2595f5d210c0918f1e29b5ab`, tree
`8e6e74af34d95670d66a0b4b237cd81d6dc2e193`. Its three intervening accepted
commits add the exact already-selected #363 quality-guidance files, #350
dependency participants and a scoped website-placement sentence. All twelve
changed paths are preserved. Eight copy accepted bytes, three guidance entries
already match, and the root README joins only the disjoint final sentence with
the existing selected links. No native observation is relabelled to this carry.

The next inspected receiving base was signed main
`63d6c4e33baf0c50de1f2b57090fa31291a6b502`, tree
`58505268716b3712104d939167e0f54e8c97e0d0`. Its five later commits receive
the #366 maintenance record, #368 evidence-date presentation, #362 native
package-path preflight, #364 eight-phase optimized reference checks and #317
smoke source. Of their 35 changed paths, sixteen already match this preparation,
thirteen copy accepted bytes, and six retain the previously reviewed integration
with exact source inverses. The smoke runner and all 32 controls are byte-identical
to accepted main. The three reference-file differences add only the already
reviewed ninth catalog-envelope phase and its inventory/uniqueness checks.
The date extension retains the original canonical Gregorian day and all prior
evidence identities; its seven Core methods and fifth native rendering method
are included in the current requirements. Native package lookup now rejects an
invalid input before clearing earlier mutation outputs. The accepted runbook and
all earlier source/result limits remain intact. This carry has no new native result.
The canonical #285 continuation `fa0d88e27f3783217fad7a45f441e407b388f90c`
separately supplies its exact operator-guide correction: nine corpora, seventeen
pins and 3,355 cases. That documentation input is a current source proposal,
not an accepted-main or additional execution claim. Its complete bytes are
preserved; no new reference implementation is taken from that continuation.

The final fixed receiving base is signed main
`0e289d81428068a0a3196cde064fda536c71691b`, tree
`53541f531c58eaf031bde08f1cfa7433cc7e5a72`. It preserves the later #103 criterion-2
receiving row and full dependency record, with credential rotation still unexecuted.
It also receives #384's conservative EvidenceHarness scope correction. The combined
UI manifest additionally depends on Catalog and Transfer, so the Core/native-UI
job closures now include those two package trees. Four additive historical audit
entries preserve all existing values and grant no new skips. The
[bounded scope extension](native-scope.md#imported-build-integration-dependency-extension)
retains the four-case original rejection regression, the corrected 38-method
portable observation and unchanged native workflows/deadlines. No earlier source,
review or native result is relabelled to this final composition.

Historical #198 had authored head `f4a35dadbe733e20d35e78f60c622c8c649ae3e2`
and signed staging delivery `2206ea74b25b7b5c0406563d237e4e7fe332ed21`.
Those are separate identities; that staging event was not main delivery of this
larger source. The new preparation changes neither the old #198 ref nor any
component owner's branch. A current-main receiving event still needs its own
review and exact configured qualification.

| Selected immutable input | Contribution retained at its actual scope |
| --- | --- |
| `986ac82a13edd7bc6541082c1a62c59eba57a6c3` | Accessible imported-build, catalog/editor, comparison and journey composition; current stronger boundary files take precedence where explicitly compared. |
| `37d2374869290bf75bd6ea8b31d463c7aa619b60` (#285) | Complete catalog-envelope and optimized nine-phase reference boundary, 17 pins, original source/provenance history and current generic validator/generator behavior. |
| `55f288df2d573d335dade463bf9b03acebe3a889` (#317) | Selected Intel simulator/toolchain continuation, 32-method owned-smoke runner and split 20-minute rendering/simulator jobs with original histories. The separate arm64 offer is not selected. |
| `e74520d1e16adbdc5c84f082025ce33c0fa5a9e4` | Reviewed package/app privacy inventory and separate unsigned Release product observations. |
| `bf0d68c837ef17f346ed7bdfe1db3d958417b7f1` | Graph/reference optimization source and its original attribution. |
| `7cba2cd2cb156e965f262dcbb1deed03d3ff49a5`, `67ac94ff5972e13884848d26c57dc48419621992` | Retained Cost context/presentation and the three-method rendering harness; wide revision and evidence-availability distinctions remain explicit. |
| `ba42fec4bffe1440994c80e02161ecc755d5bed5` | Exact entered editor text and retained failure/undo/autosave behavior. |
| `7579d66115f7fe039352de228b937797fdb38450` | Existing Notes journey's bounded Files-picker cancellation and positive durable-control assertions. |
| `c2d146e80ea6af20397aa55a482660c8e1108a2e` | Original #102 adversarial register and structured historical evidence. The new Markdown prefix identifies its source-time scope; its JSON is unchanged. |
| `692aea580cf17b624425cf739c1f581c3448c201` | Current submission-SDK protected-path receiver and all 32 original guard methods; older 17-method SDK receipts remain historical. |
| `a8c601d8c1cc1bd17f2a57f8a6489448c72611b9` | Selected retained T6 view/model/preparation, 19 model tests, three exact fixtures, two native journey bodies and original interface record. |
| `1e506e7aa22cd89689ced91484443085ed6b225f` (#363) | Three original quality-guidance paths, including 13 methods, consumed as the T6 dependency. |
| `cb8c1b491eccb05590e3478d266a01bf4c4218e4` (#372) | Ten original frozen Manifest/proposed-pair paths, 16 methods, separate 133-case corpus and seven verifier controls. |

The original T6 contributor's two additional private export files remain reserved
and unselected. This preparation introduces no private plan exporter. The selected
`BuildComparisonView` and `ComparisonFieldText` compare two immutable Build
configurations. They do not absorb #365's separately owned catalog component
comparison. The shared catalog-details source was directly compared and remains
the same admitted details boundary; no component-comparison implementation is
silently promoted.

## Actual receiving changes

The selected source joins the existing local Notes library, read-only imported
Build library and fictional Demo catalog in the real app. Exact decimal/text,
bounded import/export, catalog provenance, prepared-fork transactions and retained
comparison cancellation keep their existing module authority. Ordinary imported
Builds have no current compatibility or qualified cost producer. Missing evidence
continues to display unavailable or unknown; it cannot become a pass or zero.

`ImportedBuildLibraryModel` now owns one `T6ReviewModel`. Its published immutable
snapshot forwards complete equality on the same MainActor turn. A different Build,
changed locks under the same ID/revision, a fresh fork or selected deletion retires
old T6 content, input and picker authority. Renaming only local row metadata keeps
the same retained Build. Deleting another row or failing an open keeps the prior
selected review. The six new real-store methods specify each of those boundaries.

The selected record exposes a normal **T6 review** navigation link. The existing
T6 receiver owns explicit quality/manifest selection, bounded off-main preparation,
opaque requests, cancellation/retry, immutable inputs and current report binding.
The app does not invent a compatibility report. An ordinary user may inspect the
retained T6 declarations while compatibility remains unavailable. A reported
quality failure, absent record, pending approval and proposed status remain distinct.
Private references are displayed as inert original values, not fetched or exported.

The two donor native tests are now in the real app's existing UI-test target. Their
test bodies and all assertions remain unchanged. The shared entry helper changes
only its adaptive navigation query, bounded exact-Form scrolling and hittability
check. The older catalog journey had already documented that iPad presents the
tab navigation as ordinary Buttons; no new native failure is claimed from this
source assessment. The app's imported-build Form receives a stable identifier,
and record buttons retain their exact title with revision/evidence as accessibility
value. Actual current native evidence is still required.

The synthetic test host is explicitly Debug-only. Exactly one recognized
`--t6-journey-fixture` value chooses one of two scenarios. Every such launch creates
a new temporary library. The three embedded byte strings are exactly the donor
Build, Quality and Manifest fixtures; the new unit control compares every byte.
The fixture row is visibly labelled synthetic and preserves its original Build
identity. Only that selected row can receive the test-host report through the
existing AnalysisStore and exact T6 receiver. Ordinary app paths do not seed a
record or create that report, and Release compilation excludes the helper and its
fixture bytes. This supplies synthetic UI inputs, not compatibility execution,
measurement authentication, quality approval or deployment authority.

## Shared-file preservation

The five existing Transfer boundary paths retain their selected #285 bytes:
`FrozenValidator.swift`, `catalog_snapshot_vectors.py`,
`dependency_graph_vectors.py`, `verify_contract.py` and `source-manifest.json`.
`DEPENDENCY_GRAPH.md` now retains accepted #350's explicit participant-adapter
scope. Its source and five tests, seventeen Core tests, the Core guide and local
Transfer-to-Core dependency are carried exactly from accepted main. Core remains
independent. This planning helper is not called by the new T6 path and grants no
report-fragment reuse: same-ID/revision lock changes and every full-snapshot change
still retire the complete T6 result and picker authority.
The three original editor dependency entries retain their selected donor bytes:
the UI package manifest, `DraftLibraryModel.swift` and its complete test file.
The delayed-open guard and all 25 source methods remain intact.

The bounded shared-path resolution retains these rules:

| Shared path | Receiving decision |
| --- | --- |
| `native-ui.yml` | Keep the complete selected rendering job and smoke implementation, exact toolchain pins, conservative selection and original 20-minute native limits. Add required Cost and per-device journey jobs, exact UI method attendance, and a result-only aggregate that includes every selected job. |
| `swift-core.yml` | Preserve the complete existing Evidence loop, package/guard/mutation steps and artifact paths. Append the donor's complete Cost loop and its artifact path without interleaving either loop. |
| `swift-storage.yml` | Preserve current storage steps and deadline; require the three prepared-fork cases and complete 34-method inventory on each existing pinned simulator. |
| `swift-transfer.yml` | Preserve the isolated locked environment, 19 generic controls and nine-phase verifier; append standalone Manifest controls/corpus and require all 181 exact Swift methods. |
| `submission-sdk.yml` | Retain all current protected-path guards, five packages and two unsigned Release products. Require exact expanded Transfer/UI attendance and retain separate SDK/privacy product receipts. |
| `App/README.md`, Transfer `README.md` | Combine scope descriptions and retain original dated evidence. A current-source prefix distinguishes new inventory and wiring from earlier observations; duplicate merge paragraphs are removed once. |
| Acceptance index | Preserve complete accepted-main bytes, including the #378 row and bounded #103 criterion-2 receipt. |
| Native scope selector, audit, tests and guide | Carry the accepted #384 correction and add the four Catalog/Transfer relationships required by this integration's actual UI dependencies. Retain every old audit value and native deadline; reject the older incomplete closure without refreshing skip authority. |

The complete source proof accompanying the immutable candidate records every leaf,
mode, chosen input and new authored change. It must show no removed main path and
preserve the accepted #378 row. A calculated tree is not a published Git object,
and a published source is not an executed receiving checkout.

## Required current validation and interpretation

The five package inventories are 146 Core, 34 Data, 181 Transfer, 92 Catalog and
165 UI methods: 618 source declarations. They require actual native execution;
the sum alone cannot qualify a run. The exact Transfer/UI receivers require every
class/method identity once, with complete successful summaries and zero skips,
duplicates or replacement methods. Their portable adversarial controls reject an
older or padded receipt.

The native workflow retains all five current Evidence methods and both fresh smoke
families, and adds the three Cost methods plus all four App journeys on each pinned
iPhone/iPad destination. Each native job keeps its 20-minute limit. The journey
runner retains the 900-second test command, 120-second destination wait, original
new-UUID ownership, single attempts and mandatory cleanup. `native-ui` is an
always-run result-only check with explicit scope/rendering/simulator/cost/journeys
dependencies. Only successful scope plus all required successes, or successful
audited false scope plus all skipped, can pass. Its portable control executes all
4,096 declared status tuples and permits exactly those two combinations.

Core still executes its Debug/Release, two simulator, strict Evidence-rendering,
intentional-failure and mutation gates, with the additional Cost cases. Storage
retains actual process-exit replay and both simulator recovery suites. Submission
SDK retains its separate Xcode 26.3 / SDK 26.2 requirements, fresh caches, five
package runs and both unsigned Release products. Dependency/preparation/catalog
and all applicable conservative scope checks remain required.

Transfer keeps the 17-pin generic boundary and nine-phase 3,355-case reference
inventory, including the catalog-envelope phase and its explicit success checks.
Manifest has its own unchanged three-pin input descriptor, 133 reference cases
and seven controls in that same locked environment. It is a separately governed
entry, not an inferred generic phase or new generic schema pin. Frozen contracts,
all original corpus files and source-policy declarations retain their authorities.

Actual observations remain separately inspectable. The #285 Transfer original at
`c4fa2ba3c700a9655a0ed7d8f676d09682cc7cfd` is qualified in
[6269005714](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/285#issuecomment-6269005714):
141 Swift methods, 19 generic controls and 3,355 reference cases. The #317
`8235a9e04d3cb2b4ac452a7583b0ef9ae350c778` original has its own
[complete smoke/rendering receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/317#issuecomment-6267590880).
Neither result executes the expanded source here. Every older failure, cancelled
job, partial observation and existing source receipt retains its original identity.

### Actual portable observations at the fixed earlier preparation

The immutable local tree `defc54e32d5840688fc4035a92c586980f226087` retains
its original 888-base preparation and actual 2026-10-19 portable observations.
The exhaustive gate control passed all 4,096 shell tuples; the App script suite
passed 116 methods, the exact Swift-receipt controls 14 and Cost receipt controls
seven. In a fresh hash-locked Python 3.12.14 / jsonschema 4.26.0 environment,
19 generic controls passed, the nine canonical phases verified 3,355 cases and
17 pins, and seven Manifest controls plus 133 separate vectors passed. The
reference sequence ended at 14:40:07 UTC. Original logs, exact hashes and source
maps accompany the source review. These are portable executions; neither the six
new Swift method declarations nor any App/native suite ran locally. The later
a336 carry and its expanded 181-method receipt profile retain their own validation
identity. Unchanged input equality can preserve an earlier observation's relevance
without claiming that the expanded native source executed.

## Receiving and completion

The next source checkpoint must contain the exact joined files, full donor/main
preservation map, source inventories and actual portable results for independent
review. A new isolated draft PR may then run the configured native jobs on its
literal source/receiving checkout. Normal reviewed signed delivery, fresh current
main preservation and original-output qualification remain separate steps. A
staging signature alone cannot close an absorbed predecessor.

This local composition supplies no service deployment, real catalog publication,
live compatibility/cost producer, remote share authority, private-plan export,
Universal Links or physical-device result. The #102 seven pending cases remain
pending in their historical register. #365 and the T6 owner's reserved export
pair remain separately owned. Current component acceptance records and all broader
issue criteria, release/installed requirements and source-use decisions remain
their own receiving work. No issue, Project field or predecessor is closed by this
document or by static source inventory.
