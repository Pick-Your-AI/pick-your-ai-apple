# Recorded-version detail navigation (#61, partial)

This isolated candidate adds explicit inspection of another recorded version of
the same identifier and kind. Its source base is canonical receiving commit
`a113480a595ceb89727a7718fd6ee4d92ecc239a`, tree
`298a4970f756f6f4850159d85a60f0f4658016f7`. That existing 110-case native attempt
and its PR branch remain unchanged. The separately reviewed product-control
checkpoint `0351e6b8cefc8b671607909384b060d770179c9e` remains available to the
canonical owner; this slice does not incorporate or execute it.

## Exact source and bounded meaning

Frozen v1 has identifiers, versions and kinds. It declares no variant-family,
predecessor, successor or latest-version relationship. This consumer lists only
the exact same identifier and kind inside the selected catalog release. Version
strings retain their source meaning and use literal text order. A name, date or
numeric suffix does not establish a recommendation, freshness or availability.

The bundled adapter uses the same qualified bytes as the browser and details,
retaining SHA-256
`2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8`.
Its unchanged fixture has one version per kind. A successful listing displays
one recorded version and explicitly states that no other version of that
identifier and kind is recorded in this catalog. Unsupported capability, failed
reads and invalid listings remain unavailable; none becomes that successful state.

The projection requires the full original row, all catalog identity fields, the
exact loaded detail hash and the selected record. Repeated ID/version identities
are ambiguous even across kinds. A complete matching listing over 100 records is
rejected, never truncated and presented as complete. The receiving model also
rejects changed hashes, absent selected records, duplicates, other catalogs or
kinds, forged titles and invalid row bounds. Matching names do not create a
relationship. This internal Swift projection changes no wire schema.

The helper used by synthetic tests does not establish source qualification or
publication rights. The actual bundled adapter still performs its existing
exact-byte admission before invoking the helper. It does not reinstall the
catalog index or invalidate a previously issued page cursor.

## Navigation and lifecycle

The detail view creates a separate version model and starts its request only
after exact details are loaded. Retry uses the same row and hash. Request
identity, cancellation and terminal dismissal reject late results and errors.
An unexpected detail-pin change invalidates the listing; it cannot silently
authorize another catalog behind unchanged labels.

An ordinary Button displays each other version and name through the existing
bounded literal renderer. The model rechecks the complete listed row. The
containing browser also requires the originating detail to remain selected and
the catalog release to remain current before changing only its inspected sheet
item. A failed context check exposes an unavailable state. Successful explicit
navigation retires the old detail and version models, including source-review
callbacks. The replacement uses its complete `CatalogDetailsIdentity` and loads
its own exact version. The browser continues to own search, sort, kind filters
and page state.

Apple's primary [sheet item documentation](https://developer.apple.com/documentation/SwiftUI/View/sheet%28item%3AonDismiss%3Acontent%3A%29)
describes replacing presented content when its item changes. Its
[StateObject documentation](https://developer.apple.com/documentation/swiftui/stateobject)
explains model reinitialization when view identity changes. Both were read on
2026-10-18. Those mechanisms support this source design; they are not device
execution of the new navigation.

Neither controller receives a notes store, imported-build store or selection
writer. Inspection never selects or replaces a component in a build. Notes
retain their separate EditorPayload, and imported snapshots retain the existing
immutable workflow. A typed builder add/replace flow remains separate work.

## Verification and limits

Nine new Swift methods cover actual bundled qualification across all 29 kinds
and cursor preservation; hash/anchor rejection; opaque version ordering and
explicit receiving-detail loads; ambiguity and complete 100/101 boundaries;
exact listed-row selection; malformed source responses; unavailable capability
and failure/retry; cancellation-ignoring completions after dismissal; and a
changed detail pin during a suspended request. Multiple-version inputs are
synthetic and pass through the unchanged CatalogSnapshot/CatalogItem boundaries.
The new Swift methods are authored and remain unexecuted here.

Portable verification executed all ten Swift-evidence guard test methods with
no failures. A separate read-only Python 3.12.14 / jsonschema 4.26.0 check verified
all nine frozen source hashes and admitted seven bounded synthetic catalog
specimens against the unchanged canonical schemas: the original 29 kinds, six
recorded entries, same-kind and cross-kind duplicate identities, 100 and 101
matching versions, and an absent selected version. All seven are structurally
valid. The authored Swift tests separately require the client to reject ambiguous,
over-limit or absent-anchor projections. These Python-encoded specimens do not
execute the Swift encoder, decoder, model or UI, and their serialized hashes are
not presented as the exact Swift specimen hashes.

A source-derived 119-case synthetic log passed the actual guard command. Each
of eight required-class substitutions and the prior 110-case inventory padded
with nine unrelated cases was rejected. These ten command trials test false
acceptance in the execution gate; none is a Swift test result.

The new `catalog-recorded-versions-ui` profile requires exactly **119 distinct
passing XCTest cases**, including **70 mandatory identities across eight
classes**. It retains all 110 previous cases and adds all nine new identities.
Historical profiles, the strict complete-run parser, both worker/history loops,
both full native journeys and all accepted SDK/protection lanes remain intact.
Transfer remains **57 distinct cases / 21 required identities**, with unchanged
source and pins. No previous receipt executes these nine new methods.

The full catalog journey adds visible checks for the bundled one-version count,
explicit no-other-version label and absence of alternate-version buttons. All
existing exact labels, source review, hash, specifications, provenance, filters,
pagination and relaunch assertions remain. The new native checks are unexecuted.
Positive multiple-version sheet replacement, failure recovery and assistive
technology also require actual native evidence; model tests do not supply it.

## Literal criterion disposition

| Criterion from #61 | Candidate contribution | Remaining evidence and scope |
| --- | --- | --- |
| Every material claim has inspectable evidence or an explicit gap. | Exact recorded versions retain item/catalog pins and open the existing full typed detail consumer; related-product and latest-version gaps remain explicit. | Current-source Swift/native execution, accepted evidence/source-use intake and UX/catalog receiving review. |
| Open a stale or contradictory specification and an unsafe source URL; expose the evidence limitation and allow only validated external navigation. | Existing conditions, evidence gaps, exact-host policy and one-use source review remain; explicit version navigation retires the old review model. | Complete source-review/version journeys, approved-host/source-use intake, installed positive handoff and accessibility evidence. |
| The component detail provenance and safe-link tests is linked with criterion results, exact versions, limitations and receiving-review disposition. | This record identifies the source base, bounded interface, new tests, exact profiles and limits. | Independently reviewed published candidate and actual current-source gates before receiving delivery. |

No whole #61, prerequisite, simulator, physical-device, store or production
acceptance is claimed. Every prior failed native input remains failed. The
active canonical attempt must finish under its own exact source identity.
