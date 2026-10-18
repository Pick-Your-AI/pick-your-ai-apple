# Typed component detail consumer (#61, partial)

The Demo catalog's detail sheet now presents an exact component's typed
specifications, license declarations, recorded conditions and provenance. It
uses the normal bundled source and existing catalog selection. Opening, retrying,
paging through sources and dismissing details are read-only operations that do
not select a build component or write a draft. The preview remains explicitly
fictional, with unknown compatibility and pricing.

## Typed source and exact identity

`CatalogItemDetails` projects one immutable, schema-validated `CatalogItem` into
the specification fields declared for its exact frozen-v1 kind, the three license
declarations, and every retained provenance record. The complete original item
remains attached to the result. There is no unchecked item constructor, version
substitution, source fetch, draft writer or evidence intake in this boundary.

The field definitions come from the same unchanged bundled catalog-item schema
used by `CatalogItem.decode`. All 29 kinds therefore expose their optional fields
as well as their supplied fields. Names remain the canonical schema identifiers;
the consumer does not invent a display-label registry or a new wire contract.
Fields use deterministic name order. Numeric values retain the decoder's exact
bounded `Decimal` representation and are not narrowed to floating point or
converted between units. Array order is preserved. Unknown units or comparable
conditions are not inferred from neighboring values.

Missing, the literal `unknown`, empty text, empty collections, collections with
unknown or empty entries, and supplied values have distinct states. Supplied
false and zero retain their values. "Supplied" means a recorded declaration,
not a checked source, compatible selection, applicable license or measured fact.
The original value remains available beside its state; classification never
rewrites the source to a sentinel or silently omits an unknown field.

Provenance keeps each source URI, check date, original verification status and
optional notes in source order. Conflicting notes and recorded dates remain
available in the detail sheet. No time-based expiry, contradiction resolution,
retrieval receipt or independent corroboration is fabricated. In particular, a
raw `verified` declaration does not become a checked or independently verified
display grade. The existing accepted `PlannerCore.EvidencePresentation` policy
continues to own those presentation decisions when actual intake receipts exist.

License fields remain declarations with explicit missing states. Billing class,
provider references, namespaced extensions and a description do not acquire a
pricebook rate, serving offering, source-use permission or license applicability
verdict. The complete original extensions are retained on the immutable item but
are not promoted into specification rows.

`BundledCatalogPreviewSource` qualifies and caches the unchanged synthetic
catalog bytes before providing pages or details. Its expected SHA-256 remains
`2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8`.
Detail lookup requires the exact catalog schema, ID, revision and capture date,
exact item ID and version, and matching kind and title. It rejects a forged or
unavailable identity instead of substituting another version. Detail reads do
not reinstall the search index or invalidate an issued page cursor.

The receiving model checks the returned row and catalog pin before publication.
Failed reads retain the selected identity and offer an explicit retry. Request
identity and terminal dismissal guards exclude a completion that arrives after
the sheet closes, including a source that ignores cancellation. Sheet identity
includes the complete row and catalog release; the browser's saved filters and
pagination remain owned by the existing browser model.

## Native presentation and source limitations

The detail form stacks canonical field names, their types, state labels and
recorded values. Each missing optional field remains visible. Per-field headings
and wrapping text preserve the relationship between a label and its value. The
loaded summary reports specification and provenance counts, and the source
section shows the exact catalog identity and SHA-256.

The provenance section starts with an explicit inspection gap and shows eight
records at a time. Show more source records reveals the next eight in original
order without changing the item pin or dropping records from the source value.
Each record shows its original status and check date, its URI or an explicit
missing-URL label, and its notes or an explicit absence/empty state. No raw
`verified` status becomes an independently verified claim.

URI syntax validation at catalog decode is distinct from external navigation.
Even a schema-valid unsafe scheme remains data. The view uses verbatim text,
escapes hidden control and formatting characters, and limits each rendered value
to 2,048 UTF-8 bytes at complete Unicode-scalar boundaries. A visible truncation
notice distinguishes shortened display from the retained source value. Literal
backslashes remain distinguishable from escaped control characters. JSON field
values preserve exact decimals, arrays, false and zero without Markdown parsing.
The view exposes no Link, web view or URL-opening action. A reviewed safe-link
policy, confirmation/rejection behavior and real navigation tests remain a
separate acceptance gate; source URLs are currently inspectable text only.

## Verification and delivery status

Six Swift regressions cover all 29 kinds and all five field types, exact field
sets and identities, false/zero/missing/empty distinctions, unknown collections,
contradictory provenance and unsafe URI retention, absent optional declarations,
and separate versions with exact decimal values. Required provenance and update
dates remain required by the unchanged frozen schema.

Eight asynchronous model and rendering regressions exercise the real bundled
source across all 29 kinds, exact lookup rejection, page-cursor preservation,
failure/retry, mismatched result rejection, late completion after dismissal,
17-record provenance pagination, bounded literal rendering and full sheet
identity. Controlled presentation doubles do not establish source-byte integrity;
the test that reads the real bundle qualifies those bytes.

The native workflows also require executed-result evidence with
[`require_swift_test_results.py`](../../tools/ci/require_swift_test_results.py).
For this candidate the transfer suite must contain exactly 42 distinct passing
XCTest cases, including all six named detail projection regressions; the UI model
suite must contain exactly 68, including all eight named detail regressions.
Each log must end its complete XCTest run with one matching successful All tests
summary. Compilation, missing results, duplicate identities, wrong suites,
skips, failures and incompatible result formats fail the gate. Swift's separate
Testing framework footer with zero tests cannot satisfy the XCTest count.

Eight portable guard regressions pass locally, alongside all 46 existing CI
helper tests. The guard was also replayed against the actual retained 36-case
transfer, 60-case browser and 68-case canonical editor model logs: each parses
correctly for its own historical count, and all are rejected as new detail
evidence. The older 68-case run has the same total but lacks every new detail
case, so a matching count alone cannot qualify this feature. This replay tests
the evidence guard and does not execute any of the 14 new Swift tests.

The existing actual catalog UI journey now waits for the visible loaded summary
and reads the accelerator's eight-field count, exact source hash, `vram_gb` value
24, missing `rated_power_w`, original `user_supplied` declaration, check date,
missing URL and fictional qualification. It retains screenshots and the existing
relaunch, filters, continuation and empty-state assertions. The runner still
requires the existing exact journey names and both owned device classes; this
slice does not inject a source, seed a store or weaken a journey assertion.

This work is stacked in an isolated checkout above the active #211 browser
candidate at `aba37bb980f49e0e6772f11bcfaa8023a34d4839`, preserving its independently
reviewed menu, adaptive-navigation and editor-focus corrections. Canonical Python
fixture validation and the portable runner tests can
run on the available Linux host; Swift and Xcode execution are unavailable there.
Swift test execution, both actual UI journeys, exact-head independent review,
normal signed integration and the receiving composition with canonical #198
remain required before delivery. Preserve its concurrent editor, Home/Files
journeys and exact test-count requirements during integration. No unexecuted
test is a passing test. Recalculate and review the complete receiving suite totals
when those distinct cases are integrated; retain their required case identities
alongside these detail guards. Exact published-source results belong in the
delivery PR.

| #61 criterion | Implemented boundary | Remaining evidence |
| --- | --- | --- |
| Every material claim has inspectable evidence or an explicit gap. | Native typed fields, all original provenance, exact item/catalog pins, and explicit missing/unassessed facts. | Executed current-source native journeys, accepted evidence intake and source-use coverage, UX/catalog consumer review. |
| Stale or contradictory specifications and unsafe URLs expose limitations and permit only validated navigation. | Original dates and conflicting notes remain available; invisible controls are escaped and URLs are bounded text; no unchecked navigation exists. | Reviewed safe-link policy, explicit confirmation and rejection UI, actual native negative/recovery and accessibility journeys. |
| Criterion results, versions, limitations and receiving disposition are linked. | This scoped consumer receipt records the source boundaries and meaningful projection, model and UI regressions. | Published exact commit, executed checks, independent receiving review and accepted delivery composition. |

Variant selection/replacement, active builder context, screen-reader traversal,
Dynamic Type, installed devices and production source/service/store acceptance
remain separate. This partial delivery does not close #61 or declare a new
owner, deadline or commitment.
