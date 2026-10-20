# Reported finding identity and unavailable corrective action

Related work package: [Apple #72](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/72),
Apple/iOS09.03, “Explain findings and possible fixes”.

This bounded consumer change makes the report's ruleset identity and finding
participants inspectable, preserves supplied remediation, and explains when the
producer supplied no actionable remediation text. It does not complete the
affected-setting navigation or VoiceOver journey required by #72. The issue stays
open for those integrated results and its existing prerequisite/receiving gates.

## Observed gap and selected behavior

At signed main `364f561989dff724be73c509c78786b5f77b7d5d`, the
[report view](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/364f561989dff724be73c509c78786b5f77b7d5d/Packages/PlannerUI/Sources/PlannerUI/EvaluationReportView.swift)
already displayed build/catalog identity, outcome, severity, message and evidence.
It omitted `ruleset_id`, `ruleset_version` and each finding's `selection_ids`.
An omitted remediation displayed no action explanation; an empty string produced
an empty remediation label. This gap was identified by complete source inspection,
not by an executed native UI failure.

The public `EvaluationReportView(report:)` interface and validated immutable
`EvaluationReport` remain unchanged.

| Supplied input | Displayed behavior |
| --- | --- |
| Report ruleset ID and version | Two verbatim labels show the exact reported values. They identify the ruleset that produced this report, without approving that policy. |
| Finding rule ID, message, outcome and severity | Existing exact fields remain visible; the extension does not recompute or reinterpret them. |
| Participant selection IDs | Every ID appears with its position in the supplied order. The ordinal makes an order change observable without resolving an ID to a current setting. |
| Empty participant list | “Reported participant selections: none supplied.” No affected setting or navigation target is invented. |
| Nonblank remediation | “Reported remediation:” followed by the original string. Trimming is used only to classify blank text; the displayed nonblank value itself is not trimmed, normalized or interpreted as Markdown. |
| Omitted, empty or whitespace-only remediation | “No corrective action is described in this finding. Review its evidence before changing a setting.” The view does not infer that the finding is harmless or that any edit is safe. |
| Evidence collection, values, paths and source versions | Existing presence distinctions and exact quoted values remain intact. No source grade, support receipt or compatibility result is inferred from metadata. |

The fallback applies independently of reported outcome. A producer-reported pass
with no action stays a reported pass with no described action. A fail or unknown
with no action stays unresolved; the client does not manufacture a fix.

All content remains read-only. The caller still owns selection of the response
for the exact current build and request generation. This view adds no evaluator,
policy, catalog lookup, request, storage write, automatic substitution or
currentness authority. Participant IDs are reported references, not proof that a
currently displayed setting or catalog entry resolves them.

## Ownership and prerequisite boundary

The [bounded #72 claim](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/72#issuecomment-6279753018)
followed a complete native issue/PR inventory and reads of the repository and
organization contribution rules. It leaves #391's editor/integration route and
#387/#401's currentness, navigation and native-host recovery work with their
existing owners.

Appending consumer cases requires exact count changes in the existing host.
The [independently reviewed shared-file coordination](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/401#issuecomment-6279922933)
covers six numeric literals only: `37 → 41` total/unique counts and `28 → 32`
valid counts in `EvidenceHarnessApp.swift` and `EvidenceRenderingTests.swift`.
The proposed patch was 2,901 bytes, SHA-256
`2ca8f05758122cbba7a5ac16c87786cfe903bb27e823a46c517b532bff018599`.
All six native method identities and their remaining behavior are unchanged.
The Core fixture reader also updates its two total/valid count literals.
Current README counts follow the new corpus; historical execution records keep
their original counts and hashes.

The authored base has six native rendering methods. A later receiver combining
#387 analysis with accepted localization must preserve that separate seven-method
union. These source compositions and their original results are not interchangeable.
PR #416's original jobs also keep their own unchanged 37-case source;
their results cannot qualify the four new #72 cases.

The existing [#56](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/56)
and [#70](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/70)
prerequisite outputs still govern understandable input/conflict labels and
approved policy/fixture parity. This consumer preparation does not assert their
whole-work-package acceptance.

## Exact synthetic consumer inputs

The generator appends four schema-valid cases after every original case. It
preserves all 37 original case objects, exact payload strings and expectations,
including the nine rejections. Bundle lock, original fixture digest, dependencies
and schema identity also remain unchanged.

| Appended case | Deliberate distinction |
| --- | --- |
| `evidence/explanation/reported-action` | Failed synthetic finding; exact ruleset `rules.explanation.reported-action` / `2.3.4-draft.1`; ordered `sel_z_limit`, then `sel_a_model`; supplied action contains literal Markdown-like text. |
| `evidence/explanation/absent-action` | Unknown finding; remediation property omitted; exact version `2.3.4-draft.2` and one unresolved participant ID remain available. |
| `evidence/explanation/empty-action` | Failed finding; remediation is the empty string and participant list is empty; exact version `2.3.4-draft.3` remains visible. |
| `evidence/explanation/whitespace-action` | Unknown finding; remediation retains tab, space, LF, CR and nonbreaking space; the view shows the unavailable-action explanation and preserves both ordered participant IDs and version `2.3.4-draft.4`. |

These are explicitly synthetic producer statements. They establish no approved
remediation, price, quality result, actual device observation or compatibility
policy. The existing native test loop obtains expected text only in the test
process; the real host decodes payloads and never consumes `visibleText`.

Both Core and UI resources contain **41 cases: 32 accepted and nine rejected**.
Their exact shared bytes are **54,476**, SHA-256
`12e4ce069d9bdf3055d5eb1400a33b3643a2860403d111ac95dd92bd09a81b72`.
Core passes every accepted payload through the actual decoder, compares full
semantic JSON round trips, and preserves the prior report across every rejection.
The existing rendering loop will require the added ruleset, ordinal participant
and remediation labels from the actual public view.

| Frozen input | Identity |
| --- | --- |
| Contract / schema version | `1.0.0` |
| Canonical Research import | `7acbefbf4e4e700231e88be272bc89e3a73dde15` |
| Import manifest SHA-256 | `ef6d5801eec10f3169e2bf84653e7026b33088e305a987991ec52faadcd7f554` |
| Evaluation-report schema SHA-256 | `78935ec78848de7655bd972851aa0357c4426f6870fc028ba81739c85040359b` |
| Original report fixture SHA-256 | `039626962ef0f2c4f706614d775ad47eda1d148c58f736c98ad169fc153221f3` |
| Original local execution base / tree | `364f561989dff724be73c509c78786b5f77b7d5d` / `49e31eba0d1d7c8d8ae96a11254ac375df0d6c28` |
| Final authored source base / tree | `2a800687deb0e2c5356b226d309e36cc14f7b087` / `5fbbdc9fa9cb24543760befe00338144dde007ff` |

The local read-only Research cache was at `8af15e63a1b71e4914008f607554aa264c3e0cc5`.
Its frozen import matched the pinned manifest. The existing generator and runner
verify covered source bytes, copy only verified inputs into owned temporary
directories and reverify the copies before consumption. The cache's later Git
revision does not replace the frozen import identity.

## Finite accepted carry before publication

After the product checks and initial independent source review, the private
candidate incorporated two already accepted, valid-signed main commits once:
`364f → 2ef8aa541757adeca090e265fe97d5fde1c14f0b → 2a800687deb0e2c5356b226d309e36cc14f7b087`.
The final authored commit has the sole planned parent `2a800687deb0e2c5356b226d309e36cc14f7b087`.

[#415](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/415) updates current
dependency-graph validation prose. [#408](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/408)
adds owned Swift-child cleanup and its two subprocess controls. Their finite
four-path carry is `Packages/PlannerTransfer/DEPENDENCY_GRAPH.md`,
`tools/conformance/README.md`, `tools/conformance/swift_mutations.py`, and
`tools/conformance/tests/test_swift_mutations.py`. The README composes accepted
cleanup prose with this change's two vector-count substitutions; the other three
accepted files match `2a800687` exactly. All eight reviewed product/test files
remain byte-for-byte identical to their executed versions.

The local 65-method conformance result below belongs to the original 25-control
Swift-mutation harness. The carried base has 27 such controls and the final
conformance source declares 67 methods in total. Those added controls were not
executed by this lane's earlier 65-method run. The actual receiving CI must
qualify its own source; no prior 65/151 result is relabeled as a run of the carry.
The complete finite carry/source-map receipt is 118,338 bytes, SHA-256
`a7616c34d1928bc0b654656e4cda340e4dc0b4813bf2b4f33ae540985d6e53e2`.

## Actual local validation

The 2026-10-19 execution used a fresh Python **3.12.14** environment. Its installer
enforced every reviewed wheel hash in `requirements-lock.txt`; `pip check`
reported no broken requirements. The complete installation original is 1,637
bytes, SHA-256
`613a2aa3f5793b75bc0c8a4d312674c58dc01cdb129c6a48dd858618f431e2c4`.

After fixture generation, all **329 physical source leaves** were captured before
and after the Core and conformance checks and remained identical during execution.
The final documentation and accepted carry are separate from those executed maps. The delivering PR pins the actual
authored commit/tree and every changed blob for independent receiving review.

| Actual check | Result and original identity |
| --- | --- |
| Expanded evidence generation and `--check` | 41/32/9; identical Core/UI bytes; all original 37 cases and bundle metadata exact. Each 84-byte command log has SHA-256 `31589672506911f63d038c4292bbb5ee99de24eaa4049a7a324add5377b0360e`. |
| Complete conformance harness | All **65** exact source-declared methods pass, including both new explanation checks and all six earlier vector guards. No failures or skips; 37.524 seconds. Original 11,728 bytes, SHA-256 `3db62fa2751cd07a3db002641a4c614a01327b36caee5c8ccd13cda38e8b4d20`. |
| Canonical reference runner | 137 schema cases (11 valid / 126 invalid), six domain checks and three detected semantic mutations pass; canonical reference reports passed. Original 109 bytes, SHA-256 `587c2df42995d0cde680761afea2217583aab2c181f43dd8fd59751c4be489e0`. |
| Existing report export | All 45 report vectors remain exact. Original 49 bytes, SHA-256 `26fe70944c69ebba69d384598d37f045fa4bae5d9a827bdc8ab304a4597c006b`. |
| Actual Core XCTest execution | Swift **6.2.4**, Linux `x86_64-unknown-linux-gnu`, Swift 6 language mode, two compiler jobs. All **151** source-declared methods start and pass exactly once, no skips/failures; XCTest 6.522 seconds, command 22.028 seconds. Original 43,947 bytes, SHA-256 `d9349a8edc4cd2347aebb7254152ea34df9a2500a4aa6b84c5f12226348494ac`. |
| Swift syntax parsing | The changed view and both host/test Swift files parse with the same 6.2.4 frontend, exit zero and zero output bytes. This is syntax evidence only. |

The existing strict XCTest parser accepted the complete Core session, and the
qualified results match all 151 exact current-source declarations. The unrelated
Swift Testing footer with zero tests is retained but supplies no XCTest result.
The accepted `364f` base has five more Core declarations than PR #416's original
`bda0570` prepared source, which has 146; those counts remain source-specific.

The Python original preserves both deliberate consumer-byte rejection
diagnostics and the observed distinct-case filesystem branch. The 25 Swift
mutation harness methods use synthetic child transcripts and filesystem fixtures;
their passing results do not claim a fresh Swift semantic-mutation execution.
All local commands above completed successfully on their original source.

The strict local qualification record is 31,537 bytes, SHA-256
`279159911a630a7ea68190de8dab0ac0f03bc7b89953bb4679472d6e24637c1b`.
It records every exact Python/Core outcome and original-log identity, canonical
results and the explicit syntax-only limit. The separate complete conformance
source/execution record is 177,582 bytes, SHA-256
`ec054495dfa277c0274ea4602c5984b6af8a80743def0c67aec8852590ba1cc1`.

## Reproduce and receiving disposition

Use the repository's [fresh hash-locked Python setup](../../tools/conformance/README.md#reproduce)
with `CONTRACT_ROOT` selecting the exact frozen import:

```sh
"$APPLE_CONFORMANCE_PYTHON" tools/conformance/evidence_vectors.py \
  --contract-root "$CONTRACT_ROOT" --check
"$APPLE_CONFORMANCE_PYTHON" -m unittest discover -s tools/conformance/tests -v
"$APPLE_CONFORMANCE_PYTHON" tools/conformance/run.py \
  --contract-root "$CONTRACT_ROOT" --output /path/to/owned/evidence/conformance.json
"$APPLE_CONFORMANCE_PYTHON" tools/conformance/export_swift_vectors.py \
  --contract-root "$CONTRACT_ROOT" \
  --output Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures/evaluation-vectors.json --check
swift test --package-path Packages/PlannerCore
```

Normal configured receiving CI must still build and execute the actual Apple
SDK/package/host paths at its exact checkout. The current six-method rendering
source must execute all 32 valid shared cases on the configured native targets.
The existing [host instructions](../../tools/evidence-rendering/README.md)
supply its actual Xcode commands and receipt gates. No macOS/iOS compilation,
SwiftUI rendering, full VoiceOver journey, simulator observation or device result
is claimed by the Linux decoder run or syntax parsing above. Actual source-bound
native results and independent receiving review remain pending at this document's
prepublication checkpoint; the delivering PR records their later disposition.

| Literal #72 criterion | This change and remaining result |
| --- | --- |
| Every actionable finding explains the cause and a safe next step. | Existing producer message and supplied remediation remain inspectable; absent action is explicit. This does not establish that every real producer finding has an accepted cause or safe correction. |
| Navigate from a failed/unknown finding to the exact participant setting using VoiceOver, keeping rule/evidence versions and a safe corrective action inspectable. | Exact ruleset, rule and participant identities are visible; existing evidence source versions remain intact. Actual setting resolution/navigation, VoiceOver and safe-action acceptance remain required in the owners' integrated route. |
| Link the finding explanation and accessible correction journey with criterion results, exact versions, limitations and receiving disposition. | This record supplies the bounded source/fixture/local-validation link. The integrated accessible journey, actual native records and independent receiving disposition still have to be linked. |

The issue remains open. A merged consumer slice does not close #72, accept its
prerequisites, replace the existing editor/currentness owners or establish the
whole platform's accessibility and release readiness.
