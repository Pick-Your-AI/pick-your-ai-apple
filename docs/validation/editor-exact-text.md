# Exact title and note edits

This is a bounded source correction for [Apple #69](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/69), offered to the existing [#198 editor receiver](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/198). It does not complete the issue or replace that receiver.

## Required behavior and observed gap

The [editor contract](editor-autosave.md) requires acknowledged text to reopen exactly, undo and redo to retain binding changes, and later input to survive suspended opening and restoration. Title and note text are user input, separate from frozen BuildSnapshot data.

The unchanged published editor at `f4a35dadbe733e20d35e78f60c622c8c649ae3e2` has tree `7c1f448977119771104f30daab498d0e81f165b9`. Signed stage `2206ea74b25b7b5c0406563d237e4e7fe332ed21` preserves that same tree. Its synthesized `EditorContents` equality and dirty/per-field comparisons use Swift String equality. Consequently, composed `Caf\u{00E9}` and decomposed `Cafe\u{0301}` compare equal despite differing UTF-8 bytes.

The actual controlled baseline demonstrated that assigning those distinct values can return before recording input. It can leave the editor clean, omit autosave and undo, and reopen the old bytes after Save. During a suspended restore or open, the missed input generation can also permit older content or another selection to replace that input. This conflicts with the existing editor contract; no new normalization policy is introduced.

## Correction

`EditorContents` compares both fields by UTF-8 bytes. The edit guard, dirty state, and restored-content undo decision therefore share the same exact text boundary. Per-field input generations use the same byte comparison. A repeated byte-identical binding remains a no-op.

The correction does not change the debounce interval, actor suspension guards, storage compare-and-swap, revision history, undo limits, payload format, or analysis currency. It adds no text normalization or contract fields. Existing editor source and test files outside the two production files’ comparison changes remain unchanged.

## Focused cases

The new `EditorExactTextTests` uses actual `DraftStore` SQLite persistence and controlled actor suspension/clock release. Every text-preservation assertion compares UTF-8 arrays rather than repeating the faulty String equality.

| Method | Required result |
| --- | --- |
| `testCanonicalTitleEditPersistsExactBytesAndUndoRedoRevisions` | Both spelling directions assign the supplied title, become dirty, save/reopen exactly, and append distinct undo/redo revisions |
| `testCanonicalNotesEditPersistsExactBytesAndUndoRedoRevisions` | The same complete checks apply to notes, while the title is preserved |
| `testCanonicalBindingEditSchedulesTheNormalDebouncedSave` | The ordinary scheduling path creates and acknowledges the changed note revision |
| `testCanonicalEditsDuringRestoreSurviveTheActorSuspension` | Later title and note input survives restoration and can be saved as a subsequent revision |
| `testCanonicalLateEditPreventsAnOlderOpenFromReplacingTheSelection` | Later input keeps the original selection; the other draft remains unchanged |
| `testExactRepeatedInputDoesNotCreateDirtyStateOrUndoOrRevision` | An exact byte copy stays clean with no history or revision added |
| `testOrdinaryAsciiEditRetainsTheExistingSaveAndUndoBehavior` | Ordinary title and note editing retains the existing persistence/undo behavior |

## Actual local evidence

The local validation uses Swift 6.1.2 on Linux and SQLite 3.45.1. It compiles the exact original or corrected model and undo source with the unchanged original SQLite source. A separate inert `Published` wrapper and `ObservableObject` protocol supply only the unavailable publishing declarations. This adapter is a local validation input, not repository product source or an implementation of SwiftUI observation/rendering.

| Original command result | Actual outcome |
| --- | --- |
| Initial compiler setup | Failed before test execution because the SQLite header was not on the include path; retained separately |
| Unchanged source, matching cached SQLite header/runtime supplied | Seven methods: five failed, two controls passed; 65 failed assertions, zero skipped methods |
| Corrected source, identical seven test methods | Seven passed, zero failures or skips |
| Corrected source plus exact prior editor tests | 47 passed, zero failures or skips: 25 `DraftLibraryModelTests`, 13 `EditorAutosaveTests`, two `EditorUndoHistoryTests`, and seven new methods |

The original failed and passing logs and complete before/after source hashes are retained separately. The unchanged-source log hashes to `74bbfcb5c5c3f2b7fa8992c880d6864749c9eafb058445ae4b943adf52706a89`; the focused corrected log to `5ac4d98484e4ded17631c5df2851b09ce4425d76cb51c37e3d2c49a8abc3edf9`; and the 47-method log to `d7760cf090c358c048cc105440de33407cbb1798e8ae444b9044b3dfb7ba2c57`. Each execution leaves its supplied source bytes unchanged. The actual test logs retain their own local clock timestamps; they are not rewritten as native or later receiving executions.

## Receiving and remaining acceptance

The existing receiver must explicitly adopt the two production files, the new test file and this record while preserving its selected current-main, workflow, source and historical evidence inputs. Its resulting native method inventory must include all seven new identities without weakening the existing required identities or profiles. Run the selected native toolchain's ordinary full PlannerUI and app gates; a focused native replay can use:

`swift test --package-path Packages/PlannerUI --filter EditorExactTextTests`

No native SwiftUI, actual app interaction, production-timer duration, OS termination during autosave, full stack-builder journey, physical-device, signing, or release result is claimed by the Linux model harness. The canonical receiver's earlier native results retain their exact original source and are not evidence for this correction. The whole #69 process-kill/recovery and receiving criteria remain open, as do the independently owned prerequisites. This contribution dispatches no native job and changes no canonical branch or issue metadata.
