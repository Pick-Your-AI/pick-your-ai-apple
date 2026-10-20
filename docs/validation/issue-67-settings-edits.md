# Settings and objective edit preparation

This is bounded PlannerTransfer preparation for [Apple #67](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/67). It creates a validated, uncommitted proposal from an already valid Build. The active [#391 editor receiver](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/391) and [#64 handoff](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/64#issuecomment-6280451575) retain incomplete raw-input editing, UI, autosave, filters and native acceptance. No issue criterion is completed by this preparation alone.

## Source and field authority

The preparation starts from accepted `e742379f9a474e632a998f1586515f4cb1280b18`. The only authored paths are:

- [BuildSettingsEdit.swift](../../Packages/PlannerTransfer/Sources/PlannerTransfer/BuildSettingsEdit.swift)
- [BuildSettingsEditTests.swift](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/BuildSettingsEditTests.swift)
- This receiving record.

No frozen schema, fixture, parser, workflow, storage implementation, existing editor or evaluator changes. [#32](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/32)'s accepted contract boundary remains the source of wire admission. This API uses the bundled frozen `selection.schema.json`, `build.schema.json` and `common.schema.json` through the existing `FrozenValidator` and bounded `JSONParser`; it introduces no successor wire fields or competing ruleset.

`BuildEditableField.settings(for:)` supplies descriptors for the existing 29 `CatalogKind` cases. It reads each exact `settings_<kind>` definition. The frozen deployment-mode settings object has no fields. `BuildEditableField.objectives()` supplies the nine objective descriptors. The descriptor constructor is not public: consumers select a field supplied by the contract instead of supplying an arbitrary path, schema or required-field override.

Descriptors retain the original type, enum, minimum, exclusive minimum, maximum, pattern, required status and array restrictions present in the schema. Objective currency and decimal-money display metadata resolve only the exact bundled common definitions; validation still receives the original field schema and reference. Values retain their original units, including tokens, milliseconds, hours and percentages named by the fields. This layer supplies no unit conversion, inferred unit, catalog-specific limit or default.

## Proposal and receiving contract

The caller selects either one exact selection ID's settings or Build objectives. Each requested operation is an explicit `set` with a `BuildEditValue`, or `remove`. The value initializer first checks the actual UTF-8 JSON bytes with the existing bounded parser. Missing, null, zero, false, empty text and empty arrays remain distinct inputs; a property's schema decides which are admitted.

The proposal performs these steps in order:

1. Check the graph's exact ID and revision against the Build locks, and reject duplicate selection identities rather than picking an arbitrary record.
2. Resolve the target and require every descriptor's kind/objective scope to match it. Reject an empty change list or repeated field name, including a set/remove pair for the same field.
3. Validate every supplied value against its original frozen field schema. Required fields cannot be removed. No partial proposal escapes when a later change fails.
4. Reject a semantic no-op. Numeric representations such as `0.4` and `0.40` are equal under the existing JSON model; decimal-money strings retain their exact spelling.
5. Create the next Build revision with the caller's validated timestamp and lifecycle `draft`. Revalidate the complete encoded Build through the original parser/schema boundary, including the final byte and number bounds.
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

## Actual execution and review

The actual local execution used **Swift 6.1.2 on x86_64 Linux** and the unchanged two-file source tree `0e90eeaf0cf6460ea4436b48935df292c089a2a7`. All **336** source entries were pinned before execution and verified unchanged afterward. This guide is a later documentation-only addition and does not relabel the executed tree.

| Actual original | Result and exact identity |
| --- | --- |
| Focused `swift test --package-path Packages/PlannerTransfer --filter BuildSettingsEditTests` with explicit owned scratch/cache/config paths, one compiler job and the existing read-only SQLite toolchain | **24 passed, 0 failures/skips**, 10.495 seconds XCTest time; 51.330 seconds including clean compilation. UTC 2026-10-20 05:58:35.929769–05:59:27.259698. Original 13,920 bytes, SHA-256 `e19936f3edf6d4bc649306ec26e3404ed354716dd3cf1398dd605ae2e1787adb`. |
| Direct invocation of that same newly compiled `PlannerTransferPackageTests.xctest` binary, with its compiled discovery and all inputs retained | **238 distinct compiled methods: 226 passed, 12 explicit pre-existing CryptoKit-unavailable skips, 0 failures**; all 24 new methods passed. Complete root duration 40.545 seconds. UTC 2026-10-20 06:00:45.213482–06:01:25.811999. Original 70,267 bytes, SHA-256 `71f882b4c6d9466fda5f57b289c76b84798bcfb9bcd1464c03bd25655a58df55`. |

The compiled binary is 14,088,480 bytes, SHA-256 `c426d283c3e9293291402f77faed48b7112edd4f5dc92fc4ce43d56523c5bde9`. The source declares 244 methods; the other six are enclosed by the existing Darwin-only guard and were not compiled or executed on Linux. The 12 explicit skips are the existing five RulesetCacheValidator and seven SyntheticFixtureAdmission methods that require CryptoKit. They are not passes. The original source, generated discovery and every case start/outcome exactly match, with one complete successful root and no omitted, duplicate or failed compiled case. The original XCTest display clock is retained; the UTC intervals above come from the outer execution recorder.

The complete binary was invoked directly to avoid repeating the previously observed SwiftPM full-suite collection stall in the separate #66 run. That historical failure and its source remain separate; no new full-collection failure is asserted for #67. No source correction, failed product test or retry occurred in these two #67 executions.

The original-log qualification record is 92,929 bytes, SHA-256 `2500fc1d0364590073e4d34caaf06b8a33da8be21f43f3f34b412dac36701f89`; it retains the exact commands/environment overrides, all source hashes, compiler/discovery/binary identities, full named outcomes and skip list. Independent source/receipt review and the ordinary signed/receiving route are still pending at this local documentation checkpoint.

The focused suite contains 24 named methods. Its cases cover all 29 descriptor domains and required objective fields; complete value preservation; numeric and enum boundaries; all 12 credential-reference fields; conservative URI handling; absent/null/zero and explicit removal; duplicate/scope/identity/graph failures; unchanged input; caller-supplied graph contexts; complete output bounds; and old estimate identity rejection. The integration methods exercise actual temporary SQLite save/reopen/history, abandoned and rejected proposals, a competing writer's compare-and-save conflict, and explicit analysis-store retirement/late-response denial.

These are synthetic local consumer tests. They do not establish SwiftUI form behavior, accessibility, device execution, interrupted-process persistence, service authority or native editor integration. The existing durable-store crash and native journey gates keep their own source and execution identities. No new native workflow is dispatched by this local preparation.

## Literal receiving status

| Literal #67 criterion | Current result and remaining receiving boundary |
| --- | --- |
| Invalid edits do not corrupt saved builds or reuse stale evidence. | Partial package preparation. The uncommitted API and meaningful SQLite/analysis consumer tests address this boundary; native ownership, form integration, durable-save outcome handling and current-result presentation still require their actual receiving implementation and execution. |
| Enter out-of-range settings and attempt raw credentials; reject unsafe values, preserve the last valid revision and invalidate affected analysis after valid edits. | Partial package preparation. Frozen field checks, credential-reference negatives, unchanged saved bytes and explicit post-save analysis retirement are covered by the focused cases. The supported native journey, including real controls and interrupted persistence, remains unverified here. |
| The typed settings validation and invalidation tests is linked with criterion results, exact versions, limitations and receiving-review disposition. | This record provides the exact source, tests and original execution and preserves the literal criteria. Independent review, normal signed delivery and the later integrated native evidence remain required before any final criterion disposition. |

The selected #64 output remains a receiving prerequisite for integrated settings behavior. No blanket closure of upstream scope is added. All three whole-issue criteria remain open; source review, local execution, signed delivery and product acceptance are separate records.
