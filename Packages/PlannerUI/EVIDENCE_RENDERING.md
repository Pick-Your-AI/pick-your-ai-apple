# Evidence state mapping and decoder/UI vectors

Canonical work package: [Apple #36](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/36), IOS-03.05.
The [accepted #32 boundary](../PlannerTransfer/README.md#32-receiving-conformance-record)
supplies its prerequisite. This record covers the Apple evidence components and
their reproducible decoder/rendering inputs. Actual source ingestion, evaluator
production and the broader report screen's request-selection integration retain
their own work packages.

## Selected behavior

`EvaluationReportView` accepts the existing immutable, validated
`EvaluationReport`. It displays the producer's result, readiness, counts, finding
outcome, severity, message and evidence. It does not evaluate a rule, resolve a
conflict, fill a missing observation or grant an evidence grade. Build revision
and catalog snapshot remain visible so the reported identity is retained. A
caller must use the current response selected by its existing generation and
identity boundary; this component introduces no request or storage path.

The [bounded #72 explanation extension](../../docs/validation/issue-72-finding-explanations.md)
also displays the reported ruleset ID/version and each participant selection ID
in its supplied order. Nonblank remediation remains verbatim and is labeled as
reported. Omitted, empty or whitespace-only remediation receives an explicit
unavailable-action explanation. Empty participant lists remain explicit; the
view does not invent an affected setting, navigation target or safe correction.

`EvidenceValuePresence` and `EvidenceCollectionPresence` classify presence only.
`ClaimEvidenceView` separately renders the already accepted `EvidencePresentation`
mapping. A report's `pass` or `valid` value cannot construct a source-inspection
or independent-support receipt. The two public views add no wire fields, local
compatibility policy or catalog relabeling.

| Retained input | Apple display and interpretation |
| --- | --- |
| Optional evidence collection omitted | Evidence was not provided; support is unknown. |
| Evidence collection explicitly empty | The list is empty; support is unknown. This remains distinct from omission. |
| `observed` or `expected` omitted | Not provided (unanswered). The client does not fill zero, `false`, a comparison result or a passing outcome. |
| Explicit JSON `null` | Explicit null; retained through decoding and encoding. |
| Exact string `"unknown"` | Literal string `"unknown"`; it supplies no pass or independent verification. |
| `false`, `0`, empty string, `"pass"`, `"null"`, `"not_applicable"`, arrays or objects | Supplied JSON data, with strings quoted and controls escaped. Presence alone does not establish completeness, applicability or support. Nested fields are not silently interpreted as rule results. |
| Outcome `pass`, `fail`, `unknown` or `skipped` | Displayed as **Reported rule outcome**, independently of the separately labeled `error`, `warning` or `info` severity. |
| Skipped with a supplied not-applicable reason | Both the reported `skipped` outcome and the exact reason remain visible. A skipped rule with no established applicability remains a different input. Frozen v1 has no extra not-applicable outcome added here. |
| Conflicting evidence | Every entry and source version remains in order, including repeated paths. The reported outcome and resolution message are retained. The client neither chooses a winner nor converts every contradiction to unknown. |
| Reported `valid` / `ready` / `pass` alongside missing evidence | The labels explicitly identify producer-reported values, while the missing-evidence notice remains visible. The client does not generate a new pass from absence. |
| Empty findings | No findings were supplied; this does not establish a pass. Supplied summary counts remain reported values and are not recomputed locally. |

The report text uses SwiftUI's verbatim text initializer. Evidence JSON strings
and paths are quoted, so literal words and escaped controls remain data rather
than becoming an absent-value label or Markdown. The view preserves all entries;
it does not deduplicate evidence by path or findings by rule ID. No verification
badge is inferred from a URL, array length, response success or a non-null value.

## Canonical evidence and conflict inputs

The client consumes the accepted [Research #127 mapping](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/92111483b8d52b1b05152391b2d73e9f59ca2fba/research/T0-configuration/catalog-data-sources.md)
and its [explicit #41 receiving receipt](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/41#issuecomment-6242626857).
The existing [Apple handoff](../../docs/decisions/research-inputs-20261018.md)
retains the original acceptance and limits. The fresh #41 read also found its
[delivered CD-9 synthetic resolver](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/41#issuecomment-6249113591);
that candidate does not change this frozen report encoding or approve actual
location facts.

| Existing claim inputs | Rendered grade / retained state |
| --- | --- |
| Historical `verified` without actual source inspection | Unverified; original recorded `verified` remains separately visible. A support reference alone cannot replace inspection. |
| Inspected claim without accepted independent support | Source checked, except that distinct user-supplied or estimated provenance remains labeled as such. |
| Inspected claim plus accepted independent support | Independently verified. The ingestion caller remains responsible for resolving and obtaining acceptance of the actual receipts. |
| Unavailable source | Unavailable, even if earlier support is retained. |
| Selected-tuple correction or retraction | Recheck required and Unverified; an unrelated newer-release event cannot clear that state. |
| Version-pinned facts | Retained version and snapshot; no invented expiry. |
| Current-state facts | Exact capture date and retained snapshot; no guessed time-to-live. |
| New release / new snapshot | Distinct notices; neither silently replaces the retained tuple. |

The #58 date extension adds a localized **Capture date (Gregorian)** label to
`ClaimEvidenceView` through the existing `EvidenceCaptureDate` API and SwiftUI's
locale. The original **Current-state facts as of** line retains its exact ISO
date. Formatting uses the validated proleptic Gregorian day, independent of
caller time zones and alternate-calendar preferences. It changes no grade,
receipt, retained identity, expiry or correction/recheck rule. If Foundation
cannot format the date exactly, the original recorded date remains available.
The [date contract, primary references and focused test obligations](../../tools/evidence-rendering/README.md#captured-date-presentation-under-58)
keep current date work separate from the historical #36 results below.

The separate #58 explanatory-copy extension uses the `PlannerUI` resource bundle
for the claim card's static labels and closed grade/review messages. English,
German and Arabic are explicit presentation examples; other languages fall back
to English. Resource selection follows this view's current locale on each render.
The original status, component/version/snapshot, raw capture date, source,
retrieval method and both receipt types remain verbatim, including values that
look like translation keys or Markdown. The existing Core mapping alone chooses
the grade and review requirement. This adds no source inspection, acceptance,
expiry rule or action. [Copy and native coverage](../../tools/evidence-rendering/README.md#claim-card-explanatory-copy-under-58)
remain separate from whole-app language/market acceptance and #75's current
analysis/response integration.

The original copy-source macOS screenshot at
`c6d7d313d723b924bb675a13c4f25208f8d55452` / prepared
`f142c713bf667e25a69422384e38b348842f7452` exposed a visual defect in the
Arabic card: neutral punctuation in values such as `method:%@` and
`receipt:**literal**` could reorder beside the RTL label. The six original
automated methods passed; their logical accessibility strings did not prove
visual identifier order. The original artifact remains
[artifact 12192650675 from run 39258577523](https://github.com/Pick-Your-AI/pick-your-ai-apple/actions/runs/39258577523/artifacts/12192650675).
Its five selected PNG payloads and metadata were decoded without a new rendering
run, and the Arabic image was independently inspected.

The correction isolates each displayed value with Unicode FSI/PDI. Labels retain
the view's language and layout, while each value takes its own first-strong
direction. The production accessibility label uses those same real label/value
inputs without presentation controls; stored values, dates, grades, receipts and
the test host remain unchanged. No expected fixture text is injected into the
production view. The mechanism follows
[Unicode UAX #9 revision 52, sections 2.4–2.5](https://www.unicode.org/reports/tr9/tr9-52.html#Explicit_Directional_Isolates)
(read on 2026-10-19). This uses the existing SwiftUI text/accessibility APIs rather
than a newer-platform writing-direction API.

The unchanged 14-scenario sixth method already includes the observed
punctuation-heavy Arabic case, exact logical values, locale changes, recheck and
English recovery, with all five selected viewport attachments. The correction
requires new actual source-bound native results and inspection of the new Arabic
PNG beside the original; the old successful run does not qualify the corrected
pixels. Accessibility-string equality remains a logical-content check. Neither
that equality nor these scoped screenshots establish a complete VoiceOver,
physical-device or arbitrary mixed-script text-safety qualification.

The two conflict fixtures deliberately preserve different centrally supplied
dispositions. One contains numeric disagreement with a producer-reported
conservative failure; the other contains equally ranked opposite yes/no claims
with an unknown result and a reproducible-test request. They exercise transport
and presentation of the accepted distinction, not a new Apple conflict resolver
or evidence about a real engine. Real source display and reuse continue to require
their existing per-source decisions; these tests ingest only synthetic values.

## Exact inputs and coverage

The generator verifies the frozen manifest, copies only covered files to a
disposable directory, and verifies the copied bytes again before validation. This
also rejects a source change during copying. It runs the existing canonical
JSON Schema consumer and emits identical UTF-8 payload strings into both package
resources. The `--check` gate rejects any drift in either resource.

| Input | Identity |
| --- | --- |
| Contract and canonical source | v1 `1.0.0`, Research `7acbefbf4e4e700231e88be272bc89e3a73dde15` |
| Frozen import manifest SHA-256 | `ef6d5801eec10f3169e2bf84653e7026b33088e305a987991ec52faadcd7f554` |
| Evaluation-report schema SHA-256 | `78935ec78848de7655bd972851aa0357c4426f6870fc028ba81739c85040359b` |
| Original evaluation fixture SHA-256 | `039626962ef0f2c4f706614d775ad47eda1d148c58f736c98ad169fc153221f3` |
| Shared evidence resource | 54,476 bytes in each package; SHA-256 `12e4ce069d9bdf3055d5eb1400a33b3643a2860403d111ac95dd92bd09a81b72` |
| Reference environment | Python 3.12.14, exact [conformance requirements](../../tools/conformance/requirements.txt), including `jsonschema==4.25.1`; all installed versions are embedded in the bundle |
| Swift source | The delivering PR pins the complete source tree; `EvaluationReport` and `EvidencePresentation` remain unchanged from signed main `074ae4bffec6066d3fe6e6a5fe47ab429dde54ed` |

The current 41 vectors contain 32 accepted and nine rejected payloads. The original
37 case objects, payload strings and expectations remain unchanged; four #72 cases
are appended after them:

- All 12 outcome/severity combinations include absent, explicit-null and literal-unknown observed and expected values.
- Four cases cover absent/empty collections, reported pass without support, and empty findings.
- Two conflict cases preserve conservative failure and unresolved opposite claims.
- Two skipped cases distinguish a supplied not-applicable reason from unestablished applicability.
- Eight scalar/structured-data cases retain false, zero, empty string, literal status words, nested unknown and escaped controls.
- Nine rejections cover versions `0.9.0`, `1.0.1` and `2.0.0`, missing outcome/severity/message, unsupported finding/evidence verification fields, and a null collection.
- Four explanation cases retain exact ruleset and ordered participant identities, supplied verbatim remediation, omitted/empty/whitespace-only remediation, and an empty participant list.

The Core tests pass the exact payload bytes through `EvaluationReport.decode`,
verify the full semantic JSON round trip, check every presence/outcome/severity
expectation, and retain the prior report across every rejection before decoding
the valid report again. An unsupported version remains rejected; no unadopted
migration is performed. Existing UTF-8, byte, depth, node, numeric and timestamp
limits remain those of the accepted public decoder.

## Native rendering qualification

The [isolated native test host](../../tools/evidence-rendering/README.md) runs the
real public SwiftUI views in a separate application. `EvidenceRenderingTests`
uses public `XCUIApplication` queries against that foreground app, without
inserting expected strings into app accessibility labels. It requires actual
launch/readiness, the exact selected fixture and sequence, and native static-text
elements. Empty or missing output fails. Bounded scrolling materializes lazy
content and keeps later observed text in the negative outcome/grade assertions.

The first four methods now render all 32 valid shared cases, test independent outcome/severity
labels, exercise compact and wide widths at an accessibility text size, and cover
the claim grades and retained-identity change events. A horizontal viewport
exposes the requested wide report on a compact screen. This checks native
accessibility text; it is not evidence of physical-device layout, visual contrast,
localization or a complete VoiceOver journey.

The existing native UI job runs the original package model tests and the separate
host's six macOS UI tests. The existing Core workflow runs the same six selected
UI tests on its already inventoried iPhone and iPad. At this source baseline the pin is Xcode 16.4/16F6 and iOS
18.5; each delivering run must retain its actual selected toolchain and destination
identities. The new log gate reuses the strict XCTest parser with explicit module
`PlannerEvidenceUITests`, keeping `PlannerCoreTests` as its unchanged default.
It requires all six exact methods, unique starts and passes, exactly one complete
matching `All tests` or `Selected tests` session and zero failures or skips. Its
synthetic adversarial logs qualify the parser only; the older `PlannerUITests`
module cannot qualify this host.
The date/copy and failed-host records below retain their original source and
37-vector counts. The #72 extension changes only the six total/valid count
literals in the shared host and tests; all six method identities, remaining
method bodies and earlier 37 cases stay intact. Its new native execution is a
separate receiving requirement, recorded in the linked #72 guide.

The fifth method adds ten date/locale cases on one retained view identity,
including Arabic text, calendar and time-zone overrides, the Gregorian switch,
year limits and recovery with a required recheck. The four original native
method bodies and all 37 frozen vectors remain unchanged. Their prior results
do not establish execution of this additional method; the delivering date PR
must retain its own actual configured native results.
The sixth method adds 14 same-view copy scenarios: English/German/Arabic,
Arabic right-to-left layout, unsupported-language English fallback, literal
identifiers/receipts and return to English with the recheck still required.
They use accessibility-sized text and retain named PNG attachments from the final
visible viewport for five selected scenarios. These are scoped screenshots,
not full scroll-content captures or an app-wide visual matrix. The first four
method bodies remain exact; the fifth retains all ten date cases and assertions,
with translated German/Arabic explanatory-label expectations and additional
negative-label checks. All five old method identities remain required. A prior
five-method receipt cannot qualify the six-method extension. Local source and
synthetic receipt checks do not establish Swift compilation or native rendering;
the new configured results and attachment review remain pending.
Independent review reproduced a false acceptance of bare class/method names in
the initial qualifier. The corrected UI call requires an explicit module prefix;
the regression rejects those same bare names while Core's existing default
continues to accept its historical Linux spelling. This was a synthetic parser
failure and recovery, distinct from the later observed native failures below.

The original direct-host package implementation at source `7d9724b1` / prepared
`29579d01` / tree `0c7c83e0` did then fail both actual native runs with entirely
empty accessibility trees. All four rendering methods failed with 238 assertions
on each platform, while the existing Core runs and 23 editor-model methods had
passed. Both complete original failed logs and their exact identities remain in
the [host correction record](../../tools/evidence-rendering/README.md#actual-failed-predecessor-and-current-qualification).
The production views, Core tests and both 37-case resources are unchanged by the
test-host correction. Fresh native execution of that correction remains required.

## Reproduce and receiving disposition

From the repository root with the checked-in Python requirements installed and
`CONTRACT_ROOT` pointing to the pinned Research `contracts/v1` directory:

```sh
python tools/conformance/evidence_vectors.py --contract-root "$CONTRACT_ROOT" --check
CONTRACT_ROOT="$CONTRACT_ROOT" python -m unittest discover -s tools/conformance/tests -v
swift test --package-path Packages/PlannerCore
swift test --package-path Packages/PlannerUI
xcodebuild test -project tools/evidence-rendering/EvidenceHarness.xcodeproj \
  -scheme EvidenceHarness -destination 'platform=macOS' \
  -only-testing:PlannerEvidenceUITests/EvidenceRenderingTests \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

The final 37-vector candidate was run on the signed `074ae4bf` base with Swift
6.1.2 on Linux and the exact Python requirements above. All 89 Core cases passed,
including the four new presence/round-trip/rejection/conflict methods; all 30
conformance harness methods passed. The full strict XCTest parser independently
qualified the 89 unique starts/passes and zero failures. The original reference
runner also passed 137 schema vectors, six domain checks and three detected
semantic mutations, and the existing 45-vector report export remained exact.

| Local final-candidate receipt | Identity |
| --- | --- |
| `evidence-core-final37.log` | 23,969 bytes, SHA-256 `155d234da4ccd434e31c5dd43890ac834301361a8503942dae7ecf1a2b7f2fcd` |
| `evidence-harness-module-required.log` | 5,122 bytes, SHA-256 `376f686bf8676211548a089fd92fd698dddfeeccfc1cf0f5fa999a8e79f1a113`; 30 methods in 25.416 seconds after the explicit-module correction |

Earlier 35/36-vector checkpoints keep their own logs and do not supply these
final counts. The original native view attempts failed as recorded above;
corrected-host execution is **pending actual native qualification**. Swift syntax
parsing and the Python/reference results do not qualify AppKit, UIKit or SwiftUI
behavior. The delivering PR must pin actual native runs,
their full source composition and the final independent receiving disposition.

| Literal #36 criterion | Evidence and receiving result |
| --- | --- |
| UI and decoder never turn missing evidence or a literal unknown string into pass. | Presence projection, full Core round trips and public views preserve the distinction; final native rendering and independent receiving disposition are required. |
| Render absent facts, contradictory evidence, a literal unknown value and skipped rules; never collapse them to pass or confuse outcome with severity. | The same 37 decoder/UI vectors and four native methods cover the required states; execution at the actual delivering Apple checkout remains required. |
| The evidence state mapping and decoder/UI vectors is linked with criterion results, exact versions, limitations and receiving-review disposition. | This record, the exact resources and delivering PR/review receipts provide the link. The issue remains open until all three criteria are reconciled with the actual native results and normal signed-main delivery. |

Review roles remain contract governance and affected client reviewers, exercised
under the maintainer's delegated project authority. Do not infer other-client
runtime parity, service acceptance, source-use grants or release acceptance from
this bounded output. Those are separate outcomes, not extra #36 closure gates.
