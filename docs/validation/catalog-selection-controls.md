# Catalog selection controls and native detail labels

This correction follows two completed, failed native runs. It changes the catalog
view's hit areas and selection control, and corrects the journey's detail-label
queries. Filter storage, exact catalog and component pins, source-review policy,
the Notes journey and all package/runner gates remain unchanged. The corrected
source requires independent review and a new complete native run before acceptance.

## Actual executed inputs

The raw job checkout logs and immutable Git commit records agree on these inputs:

| Feature candidate | Actual native checkout | Tree | Ordered checkout parents |
| --- | --- | --- | --- |
| `c8fa65c79b7f02a39f5a03e85a69a81d4d4d2694` | `85eb9f485c919384211aee6696e2b1117c3cd933` | `99ab352371ff44028ad15851b01e33df66ca7022` | `f4fdbcba214bac4be641eefc5079b7ed1a3f3d54`, then `c8fa65c79b7f02a39f5a03e85a69a81d4d4d2694` |
| `3bdb956ab5640a055913621d9b96eec5cf329489` | `435e9f0fac80ca4041265fc8bed7250af02f17ab` | `c8f0aefc8a91d0c7d1f82e7098677ac745185f96` | `c8fa65c79b7f02a39f5a03e85a69a81d4d4d2694`, then `3bdb956ab5640a055913621d9b96eec5cf329489` |

Both jobs used Xcode 16.4 / 16F6, Apple Swift 6.1.2 and the pinned iOS 18.5
runtime, build 22F77. An independent comparison of the actual model logs against
every class-qualified source declaration found exact equality: **87 cases** at
the first source and **101 cases** at the second. All passed; neither result has
missing, duplicate, failed or skipped model cases. The real logs also pass their
strict profiles, requiring respectively 38 identities across five classes and
52 across seven. Thus all six source-policy and eight source-review model tests
actually executed at `435e9f0`; they are no longer only authored tests. These
results do not execute later repairs or the prepared current-main quality union.

| Native job | Model execution | iPhone catalog / Notes | iPad catalog / Notes |
| --- | --- | --- | --- |
| [39128932354 / 117680054390](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39128932354/job/117680054390) | 87 passed, 32.147 seconds | Failed, 151.693 seconds / passed, 215.533 seconds | Failed, 88.758 seconds / passed, 245.354 seconds |
| [39131677846 / 117688000198](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39131677846/job/117688000198) | 101 passed, 27.415 seconds | Failed, 117.924 seconds / passed, 206.562 seconds | Failed, 104.269 seconds / passed, 222.077 seconds |

Every destination summary contains exactly two executed tests: one pass, one
failure, zero skips and zero expected failures. The successful Notes cases retain
the complete autosave, durable revision, relaunch, invalid-amendment, discard,
deletion and independent-control assertions. Both owned-simulator deletions in
each run returned zero. These Notes passes do not qualify the failed catalog gate.

The first run created iPhone `FB5DB4DD-FAEA-4DB1-9322-048D5088B866` and iPad
`64CD1ECB-A165-40CF-8694-1D2766D0BF81`; the second created iPhone
`711DFAD2-8EE9-4515-9907-3614A4F37A41` and iPad
`74E1DC90-8DB9-4CCC-9EBE-F4A7F2BB7C37`. Each result bundle names its exact owned
UDID and the required iPhone SE (3rd generation) or iPad (10th generation) model.

The complete downloaded artifacts were size-, SHA-256- and CRC-verified:

| Artifact | Bytes / ZIP entries | SHA-256 |
| --- | --- | --- |
| [12139555896](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39128932354/artifacts/12139555896) | 187,223,227 / 2,108 | `d720d4900d985530ff2ce0f4383aed1fa0b621886f81289de1844f0fc87c0834` |
| [12139202436](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39131677846/artifacts/12139202436) | 203,714,466 / 2,236 | `66139acc73e2407cfdd8f7e54ef84194dc1bd81ab7ea32a3430607e287bde1f1` |

## Distinct observed failures

### Detail values use complete native labels

Both iPhone runs passed filter selection, the exact one-result count, process
relaunch and restored selection, then opened the detail and verified its loaded
summary. Their subsequent bare `cat.accelerator.fixture` query failed. The actual
app-side accessibility snapshots expose these `LabeledContent` elements:

- `Identifier, cat.accelerator.fixture`
- `Version, 2026.10-demo`
- `Compatibility, Unknown`
- `Price estimate, Unknown`
- `Catalog, catalog.fixture.1`

The receiving source adopts the complete independently reviewed, Form-scoped
exact-one locator loop from canonical checkpoint
[`f59a67258fbe285bd1dad2d659f35989a3b0c4f1`](https://github.com/Pick-Your-AI/pick-your-ai-apple/commit/f59a67258fbe285bd1dad2d659f35989a3b0c4f1),
including its factual App and receiving documentation. That handoff leaves the
production controls unchanged; the two product corrections below remain separate.
The journey queries those complete labels and retains every exact expected
value. It checks compatibility and price separately. The existing source hash,
typed specifications, optional-field gap, declaration/date, missing URL, source
review, pagination and empty-result assertions remain required. The previous
failed runs did not reach those later assertions. No production detail value or
label is changed to satisfy the test.

### Kind selection has one visible button and explicit state

At `85eb9f0`, the iPad query found exactly one native Switch contained in the
identified row. Its actual synthesized tap was at `(644.5, 400)`, inside that
51-by-31-point control; the immediate post-tap query still reported `0`, failing
the required `1` assertion. The same contained-switch source passed selection
and restoration on iPhone, and later also on iPad at `435e9f0`. This is qualified
as an inconsistent control interaction, not proof that every switch tap fails.

The component-kind sheet now presents one standard Button per kind, with the same
stable `catalogKind-<kind>` identifier and visible kind name. A trailing checkmark
shows selection; the button exposes its explicit Selected/Not selected value and
the selected accessibility trait. Its full row has a rectangular hit shape and a
minimum 44-point height. Activation calls the existing `setKind` operation using
the inverse of the current inclusion state; no model, preference or pin changes
are introduced.

The journey requires exactly one Accelerator button with that label, the initial
unselected trait/value and minimum height, then uses an ordinary native tap.
Both selected trait and value must change, the same combined one-result filter
must appear, and both selected signals must survive process relaunch. The
containment assertions specific to the removed nested Switch are replaced by
these actual button/state assertions. No coordinate tap or extended timeout is
added; complete current-source execution remains required.

### The component row includes its displayed empty space

At `435e9f0`, iPad passed selection and restoration, then its normal component-row
tap failed to open any details sheet. The retained tap is `(410, 613.75)`, the
center of the row's accessible Button frame `(16, 581.5, 788, 64.5)`. Its visible
labels occupy only the left side, ending at x=216 and x=224. The final complete
hierarchy remains the filtered catalog with one result; it contains no detail
loading, unavailable or ready view. No detail-presentation warning is recorded
during that tap.

The source's plain Button expanded its label layout to the full row width without
specifying that empty region as hit-test content. The correction applies
`contentShape(Rectangle())` inside that expanded label. This makes the intended
row hit shape explicit while preserving the same button, captured row identity
and detail presentation. The test keeps its normal `tap(candidate)` and unchanged
ten-second ready assertion. The next native result must establish the correction;
the retained touch geometry supports it but does not constitute a passing run.

## Required verification

The correction preserves all 101 UI-model declarations, the complete 48-case
transfer inventory, both original journey identities, every strict result guard,
the existing device/runtime pins and owned-simulator cleanup. The separately
prepared main union still needs the reviewed 57-case quality-transfer profile;
its historical source checkpoint is not changed or represented as executed here.
No local Swift or native execution is available in this editing environment.

Both complete journeys must pass on both pinned destinations at the exact
published source before native acceptance. The missing-URL Review/Close controls
were not reached in these failed runs; positive external handoff, physical-device
and VoiceOver validation retain their separate evidence requirements. No issue
criterion is closed solely by these source corrections or package passes.

Primary Apple references checked 2026-10-18:
[content shapes define hit testing](https://developer.apple.com/documentation/swiftui/view/contentshape(_:eofill:)),
[the selected accessibility trait](https://developer.apple.com/documentation/swiftui/accessibilitytraits/isselected),
and [adding accessibility traits](https://developer.apple.com/documentation/swiftui/view/accessibilityaddtraits(_:)).
