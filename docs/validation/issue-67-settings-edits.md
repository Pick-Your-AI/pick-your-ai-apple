# Settings and objective edit preparation

This is bounded PlannerTransfer preparation for [Apple #67](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/67). It creates a validated, uncommitted proposal from an already valid Build. The active [#391 editor receiver](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391) and [#64 handoff](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/64#issuecomment-6280451575) retain incomplete raw-input editing, UI, autosave, filters and native acceptance. No issue criterion is completed by this preparation alone.

## Known gaps stated first

- **Proposal bypass (not fixed here).** `BuildSettingsEdit.prepare` is a static, unauthenticated, pure function. It returns a public, fully schema-valid `proposed: BuildSnapshot` with the revision already advanced. A caller can `proposed.encoded()` and pass it to `DraftStore.save(id:expectedRevision:title:payload:)`, which gates on expected-revision compare-and-swap only and never checks an owner or a confirming session. No owner/session type exists in this PR. The gate is deferred to the [#391](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391) receiving work. Issue criterion 1 therefore remains **unevidenced end to end**. Recommended order: factor one shared owner/session type from merged #429, land #426 on it, then have this PR adopt it.
- **Commits are unsigned.** All seven commits that were on this branch before the changes described in the final section are unsigned (GitHub verification reason `unsigned`). No all-signed claim is made. A signed preparation commit named in earlier PR text is not on this branch and is not its head.
- **Synthetic payload shipped in a product target.** The head adds `.copy("SyntheticInputs")` to `Packages/PlannerTransfer/Package.swift` and a 479-line synthetic dependency-graph JSON read at runtime from `Bundle.module`. That is outside the settings-edit scope; see "Source and field authority". Recommended: split it into its own PR or move the resource to the test target.
- **Force unwraps.** `BuildSettingsEdit.prepare` uses nine force unwraps of schema-required members (the `locks`, `selections`, selection `id`/`kind`/`settings`, `objectives` and `revision` accesses and the `CatalogKind(rawValue:)` conversion). They are safe against the frozen v1 schemas today and are deferred, not changed here. They would become crashes rather than thrown errors under a frozen successor that makes a member optional or adds a kind.

## Source and field authority

The preparation was first written against accepted `e742379f9a474e632a998f1586515f4cb1280b18`; the PR base is now `09667e27f083b7635c62e2b1bb72b34a81959367`, which is also the merge base with main. Recomputed from Git against that base (`git diff --stat origin/main...HEAD` and the diff against the PR base agree), the branch changed exactly **eight paths** (+1491/-1 at head `3e6f4f29`, before the lifecycle commit):

| Path | Purpose |
| --- | --- |
| [BuildSettingsEdit.swift](../../Packages/PlannerTransfer/Sources/PlannerTransfer/BuildSettingsEdit.swift) | Settings/objective proposal API (this PR's subject) |
| [BuildSettingsEditTests.swift](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/BuildSettingsEditTests.swift) | Its tests |
| This receiving record | Evidence record |
| [BuildDependencyGraphInput.swift](../../Packages/PlannerTransfer/Sources/PlannerTransfer/BuildDependencyGraphInput.swift) | **Not part of the settings subject.** Admits a bundled synthetic dependency graph |
| [BuildDependencyGraphInputTests.swift](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/BuildDependencyGraphInputTests.swift) | Its 8 test methods |
| [BUILD_DEPENDENCY_GRAPH_INPUT.md](../../Packages/PlannerTransfer/BUILD_DEPENDENCY_GRAPH_INPUT.md) | Its guide |
| `Packages/PlannerTransfer/Sources/PlannerTransfer/SyntheticInputs/dependency-graph.json` | 479-line synthetic data payload shipped in the product target |
| `Packages/PlannerTransfer/Package.swift` | One-line resource change adding `.copy("SyntheticInputs")` |

The last five rows were added by commits `580c9a84` and `3e6f4f29` and are undeclared scope for a settings-edit PR, now declared. The synthetic payload ships inside the PlannerTransfer product and is read from `Bundle.module` at runtime; `docs/REPOSITORY_SCOPE.md` states synthetic fixtures are not product evidence. The loader pins a SHA-256, bounds size, decodes through `DependencyGraph.decode` and matches the Build's locks, so no correctness defect is claimed, but the recommendation is to split these five paths into their own PR or move the resource to the test target.

No frozen schema, existing fixture, parser, workflow, storage implementation, existing editor or evaluator is edited; `Package.swift` is the only build-configuration change. [#32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32)'s accepted contract boundary remains the source of wire admission. This API uses the bundled frozen `selection.schema.json`, `build.schema.json` and `common.schema.json` through the existing `FrozenValidator` and bounded `JSONParser`; it introduces no successor wire fields or competing ruleset.

`BuildEditableField.settings(for:)` supplies descriptors for the existing 29 `CatalogKind` cases. It reads each exact `settings_<kind>` definition. The frozen deployment-mode settings object has no fields. `BuildEditableField.objectives()` supplies the nine objective descriptors. The descriptor constructor is not public: consumers select a field supplied by the contract instead of supplying an arbitrary path, schema or required-field override.

Descriptors retain the original type, enum, minimum, exclusive minimum, maximum, pattern, required status and array restrictions present in the schema. Objective currency and decimal-money display metadata resolve only the exact bundled common definitions; validation still receives the original field schema and reference. Values retain their original units, including tokens, milliseconds, hours and percentages named by the fields. This layer supplies no unit conversion, inferred unit, catalog-specific limit or default.

## Proposal and receiving contract

The caller selects either one exact selection ID's settings or Build objectives. Each requested operation is an explicit `set` with a `BuildEditValue`, or `remove`. The value initializer first checks the actual UTF-8 JSON bytes with the existing bounded parser. Missing, null, zero, false, empty text and empty arrays remain distinct inputs; a property's schema decides which are admitted.

The proposal performs these steps in order:

1. Check the graph's exact ID and revision against the Build locks, and reject duplicate selection identities rather than picking an arbitrary record.
2. Resolve the target and require every descriptor's kind/objective scope to match it. Reject an empty change list or repeated field name, including a set/remove pair for the same field.
3. Validate every supplied value against its original frozen field schema. Required fields cannot be removed. No partial proposal escapes when a later change fails.
4. Reject a semantic no-op. Numeric representations such as `0.4` and `0.40` are equal under the existing JSON model; decimal-money strings retain their exact spelling.
5. Require the original Build's lifecycle to be `draft`, `validated` or `ready`; a `deployed` or `archived` Build throws `lifecycleNotEditable` (fork it through the ordinary import/fork path instead; this mirrors the optional-tier transition in #426). Create the next Build revision with the caller's validated timestamp and lifecycle `draft`. A `validated` or `ready` Build is therefore demoted: `lifecycleBefore`, `lifecycleAfter` and `lifecycleChanges` expose it and `changedFieldNames` ends with `"lifecycle"` when it changes. Revalidate the complete encoded Build through the original parser/schema boundary, including the final byte and number bounds.
6. Return the original snapshot, complete proposed snapshot and direct graph participation preview. No durable write, evaluator request, current-owner decision or analysis-store change occurs here.

All unrelated settings, selection order and identity, enabled flags, roles, catalog pins, locks, directed links, owner and namespaced private fields remain exact JSON values. The proposal is local data, not a sharing projection. Existing explicit export policy still applies.

The native consumer must verify its current store/draft/selection-session ownership before using a proposal. It must save through the existing expected-revision compare-and-save operation and handle conflict, failure or uncertain completion without automatically overwriting or retrying against a newer draft. A proposal may be abandoned with no storage effect. The package deliberately does not duplicate the editor owner's draft or session state machine.

After a successful durable revision change, the consumer must select the new exact Build identity in its analysis store and retire **all** prior-revision results from current presentation. Previously saved results can remain explicitly historical. Pending callbacks from an earlier revision must remain rejected even if transport ignores cancellation. A failed or abandoned proposal must not be relabeled as a committed revision. These receiving actions are tested through the existing `DraftStore` and `AnalysisStore`, but are not wired into the native app by this contribution.

## Validation and invalidation boundaries

| Input or result | Meaning retained by this preparation |
| --- | --- |
| Number, integer, range and enum | Original frozen admission; no clamping, coercion or precision expansion. The existing bounded decimal subset can reject a number even where the broader schema would admit it. |
| Credential-reference fields | Require the original `secret://` reference shape. Raw fictional credentials, empty references, disallowed characters and trailing newline reject with payload-free errors. This is not an authentication or secret-availability check. |
| URI field | Uses the existing conservative URI validator. A schema-valid URI is not contacted, authorized or vouched for. |
| Free text | Retains the field's actual constraints. A region or other free-text field is not a general secret detector; the package does not invent that guarantee. |
| Decimal money | Remains the exact decimal string with its original fraction limit; currency remains an explicit three-uppercase-letter code. No conversion, price or affordability verdict is inferred. |
| Optional absence versus null | Removal deletes an optional property. Explicit null must independently satisfy its schema and is not silently converted to absence or zero. |
| Selection settings | Seeds direct graph participation with the selected kind and retains all identities, including disabled selections. It does not infer transitive evaluation or compatibility. |
| Before/after environment | The caller explicitly supplies resolved mode and production values. Unknown stays unknown; lifecycle, setting text or running on Apple does not infer either value. |
| Graph activity | Active, inactive and unknown remain distinct. An inactive/inactive edge can be absent from the direct preview; this is not permission to reuse an old-revision result. |
| Objectives | The frozen graph has no field-level objective dependency map. The proposal therefore requires full recheck rather than inventing unaffected result classes. |
| Coupled settings | Per-field validity is not semantic compatibility. Relationships such as split totals, min/max replica ordering, model capability and resource sufficiency retain their governed evaluator. |

The direct participant plan is descriptive. It supplies no `pass`, `fail`, `unknown` finding or evaluator-level `skipped` verdict. All old-revision analysis retirement remains mandatory independently of the preview's affected set.

## Evidence, labelled by tree

Every claim below is tied to a named tree. Nothing is transferred from one tree to another. Counts were recomputed from Git (`func test` declarations) or from the CI job logs named here.

| Tree | Commit | What it contains | Evidence that belongs to it |
| --- | --- | --- | --- |
| `0e90eeaf0cf6460ea4436b48935df292c089a2a7` | local only, not on this branch | Two-file source (implementation and tests), 336 inputs | Local Swift 6.1.2 Linux run below. Not a tree of this PR. |
| `900c9eedd8234a141a22b69524795e303edaa30f` | `d2d103fc` | Settings feature (3 paths) on the accepted base | Run set `39477723...`: Contract preparation, Dependency review, Synthetic catalog maintenance rehearsal and Unsigned submission SDK compatibility succeeded; Native local drafts **failed** and the other native workflows were **cancelled**. No complete passing set exists for this tree. |
| `91df22bce832b5a854577975c997299becfbdf0d` | `580c9a84` | Adds the graph-input paths | Run set `39491292...`: Swift build transfer and Unsigned submission SDK compatibility **failed**; four native workflows **cancelled**. No complete passing set. |
| `8fa9958cedc36eef29c1efb92a9f5ea0fdd47150` | `3e6f4f29` | Adds the test separation for admitted graph revisions; eight changed paths in total | Run set `39497751...`: all 17 checks passed, none cancelled. Details below. |
| Tree of the commits after `3e6f4f29` | see the PR comment | Adds lifecycle admission, its tests and this record revision | CI for that tree is recorded in the PR comment after it finishes; a record cannot name its own tree. |

### Tree `8fa9958c` (head `3e6f4f29`): method counts and CI

Declared test methods (`func test` count): `BuildSettingsEditTests.swift` **24**, `BuildDependencyGraphInputTests.swift` **8**.

CI log evidence for this tree:

- `macos-transfer` job 118887218129 (run 39497751919), `swift test --package-path Packages/PlannerTransfer`: suite `BuildSettingsEditTests` executed 24 tests, 0 failures; suite `BuildDependencyGraphInputTests` executed 8 tests, 0 failures; `PlannerTransferPackageTests.xctest` executed **301** tests, 0 failures. All 32 named methods of the two suites reported `passed`; none failed or skipped. The pull-request workflow checks out a merge of head into the PR base; because the base is this branch's merge base, that merge tree is expected to equal the head tree (inferred, not read back).
- `submission-sdk` job 118887246869 (run 39497752166) is a separate job on the same head; its log also contains a 301-test Transfer run.
- `gh pr checks` reported 17 of 17 jobs passing, including `macos-core` (36m24s of its 40 minute budget), `native-simulator` (14m15s) and `native-evidence-rendering` (13m16s).
- The eight graph-input methods were never executed by the local Linux runs. Their only execution evidence is the CI job above.

Declared methods of `BuildDependencyGraphInputTests`: production bundle matches the independent frozen fixture and qualification; foreign graph id unavailable without fallback; different graph revisions unavailable without narrowing; schema-valid tamper at the same identity rejected; equivalent JSON spelling cannot replace pinned original bytes; oversized and truncated inputs cannot produce a graph; admitted bytes and graph immutable after caller mutation; admitted graph feeds the uncommitted settings boundary.

### Retained historical local execution (tree `0e90eeaf`, not this PR's tree)

The earlier local run used **Swift 6.1.2 on x86_64 Linux** and the unchanged two-file source tree `0e90eeaf0cf6460ea4436b48935df292c089a2a7` (336 inputs verified unchanged). It qualifies neither `900c9eed` nor `8fa9958c`; its original qualification file is not published here.

| Actual original | Result |
| --- | --- |
| Focused `swift test --filter BuildSettingsEditTests` | 24 passed, 0 failures or skips; 10.495 s XCTest time |
| Same compiled `PlannerTransferPackageTests.xctest` run directly | 238 compiled methods: 226 passed, 12 explicit CryptoKit-unavailable skips, 0 failures. Skips are not passes. |

The head test file declares the same 24 settings methods. Whether its bytes equal the locally executed ones is not asserted here.

### Coverage and limits

The 24 settings methods cover all 29 descriptor domains and required objective fields; value preservation; numeric and enum boundaries; all 12 credential-reference fields; conservative URI handling; absent/null/zero and explicit removal; duplicate/scope/identity/graph failures; unchanged input; caller-supplied graph contexts; output bounds; and old estimate identity rejection. Integration methods exercise temporary SQLite save/reopen/history, abandoned and rejected proposals, a competing writer's compare-and-save conflict, and explicit analysis-store retirement.

These are synthetic local consumer tests. Compare-and-save is not an interrupted-persistence result: no crash or kill test is exercised by this PR (`DraftCrashProbe` and `PendingWriteCrashProbe` exist in the repository but are not used here). They do not establish SwiftUI form behavior, accessibility, device execution, service authority or native editor integration. No claim is made that independent human review, a non-author approval or signed delivery has occurred.

## Literal receiving status

| Literal #67 criterion | Current result and remaining receiving boundary |
| --- | --- |
| Invalid edits do not corrupt saved builds or reuse stale evidence. | **Partial, unevidenced end to end.** With the proposal bypass above, saved-build protection is not demonstrated. Package-level rejection and consumer tests below the native layer are real. The uncommitted API and meaningful SQLite/analysis consumer tests address this boundary; native ownership, form integration, durable-save outcome handling and current-result presentation still require their actual receiving implementation and execution. |
| Enter out-of-range settings and attempt raw credentials; reject unsafe values, preserve the last valid revision and invalidate affected analysis after valid edits. | **Partial.** Rejection and preservation are evidenced at package level; invalidation is only the full-recheck flag and the direct-participation preview, and retirement is the consumer's. Frozen field checks, credential-reference negatives, unchanged saved bytes and explicit post-save analysis retirement are covered by the focused cases. The supported native journey, including real controls and interrupted persistence, remains unverified here. |
| The typed settings validation and invalidation tests is linked with criterion results, exact versions, limitations and receiving-review disposition. | **Fail for this tree until reviewed.** This record now recomputes paths, counts and CI per tree, but independent review and later integrated native evidence have not occurred. The supported empty-draft to restoration journey, including optional-tier removal and interrupted persistence, is **not started** in this PR (it belongs to #391). This row's original text follows: it provides the exact source, tests and original execution and preserves the literal criteria. Independent review, normal signed delivery and the later integrated native evidence remain required before any final criterion disposition. |

The selected #64 output remains a receiving prerequisite for integrated settings behavior. No blanket closure of upstream scope is added. All three whole-issue criteria remain open; source review, local execution, signed delivery and product acceptance are separate records.

## Changes after head `3e6f4f29`

New work on this branch (the earlier unsigned history is not rewritten):

- Lifecycle admission in `BuildSettingsEdit.swift`: typed `lifecycleNotEditable` for `deployed` and `archived`; `draft`, `validated` and `ready` are demoted to `draft`; `lifecycleBefore`, `lifecycleAfter`, `lifecycleChanges` added; `"lifecycle"` appended to `changedFieldNames` when it changes. Previously a setting edit silently reset any lifecycle to `draft` and the change was absent from `changedFieldNames`.
- One new test method, `testDeployedAndArchivedBuildsAreRefusedAndEditableLifecyclesAreDemotedVisibly`, covers all five schema lifecycle values; the existing `ready` preservation test is updated for the extra `"lifecycle"` name. The settings suite therefore declares 25 methods after this change.
- No other semantic Swift change. The proposal bypass, the synthetic payload and the force unwraps are unchanged and open. The CI result for these commits is reported in the PR comment, not here.
