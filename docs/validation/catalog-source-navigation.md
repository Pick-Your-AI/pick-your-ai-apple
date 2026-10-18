# Explicit catalog source navigation (#61, partial)

This slice extends the existing typed detail consumer with a visible **Review
source link** action for each source record. The source URI remains bounded
verbatim text. Review can explain a missing URI, reject a destination, show an
explicit confirmation, report a failed system handoff, or record that the system
accepted the request. It does not fetch or inspect source content.

The app's fictional preview approves **no source hosts**. A source record, its
declared verification status, its notes and a user tap cannot add a host to the
policy. Positive destinations in tests use only the reserved
`docs.example.com` specimen. No production provider, source-use permission,
evidence grade or navigation host approval is adopted by this work.

## Destination boundary

`CatalogSourceLinkPolicy` accepts a navigation candidate only when all of these
local checks pass:

- The complete input fits the configured UTF-8 byte limit. The default and
  absolute maximum are 4,096 bytes; a configuration can only lower that limit.
- Raw input uses printable ASCII without spaces, controls, formatting characters
  or backslashes. Every percent escape has exactly two hexadecimal digits.
- The scheme is HTTPS. The raw authority is exactly a configured ASCII DNS host,
  optionally followed by the literal port `:443`.
- DNS labels are nonempty, at most 63 bytes each, and use ASCII letters, digits
  and internal hyphens. The entire name is at most 253 bytes, has multiple labels
  and starts its final label with a letter. Single-label and numeric IP targets,
  wildcards, userinfo, encoded hosts, trailing dots and alternate ports are not
  accepted.
- Foundation's strict URL initializer succeeds without repairing the input.
  The complete URL string must remain byte-for-byte identical, and the parsed
  scheme, host, port and lack of userinfo must agree with the checked authority.

Configured ASCII host names compare without case sensitivity. A host match is
exact; approving a name does not approve its subdomains or suffix lookalikes.
The decision is a local navigation candidate, not a verdict that a site or its
content is safe, current, licensed or authoritative. Encoded path/query/fragment
data remain the original URI. Neither this policy nor the system handoff confines
later redirects or an associated app.

The URL parser is intentionally Apple-specific. The accepted Android
[external-navigation boundary](https://github.com/Pick-Your-AI/pick-your-ai-android/blob/93bebf787a091fe4858c1c70fd07cabefe17170f/docs/NAVIGATION_BOUNDARY.md)
provided the exact-host/explicit-consent reference. Android parser behavior is
not treated as Foundation test evidence.

## Exact selection and one-use consent

The detail model retains the immutable selected item and catalog identity.
Review refers to the original provenance index and is available only after that
record has been loaded and revealed in the current eight-record page window.
Showing more records preserves their order, the item/catalog pin and any current
review.

Each review receives a new UUID. Only its current confirmation can produce an
opening request; the same source URI is rechecked against the immutable policy
immediately before that confirmation is consumed. A second use of that UUID
cannot dispatch again. Replacing or closing review retires captured controls.
Closing the detail model also retires review and late callbacks. A recreated
detail for another item version or catalog release cannot adopt an old review.

The confirmation shows the exact host and complete eligible URL, with wrapping,
before the explicit **Open source** action. It is not shortened to the ordinary
2,048-byte field preview. Cancel leaves the pinned item and browsing state
unchanged. The model marks the confirmation consumed before the view calls the
system's `openURL` action. Only the matching current opening can accept its
completion callback.

A failed handoff provides **Review again**, which creates a new confirmation;
there is no automatic retry. A successful callback says only that the system
accepted the request. It does not establish page loading, redirect behavior,
source inspection or claim verification. Link, review, state and opening
diagnostic descriptions omit the URL, host and transient UUID.

All source declarations remain intact, including old dates, contradictory notes,
raw `verified` values and explicit unknown/missing facts. Navigation performs no
draft, selection, catalog, evidence or price write.

## Verification and limits

The isolated source is based on the independently reviewed catalog/editor
candidate `c8fa65c79b7f02a39f5a03e85a69a81d4d4d2694`, tree
`99ab352371ff44028ad15851b01e33df66ca7022`. Its running native checks and the
[retained earlier failures](catalog-editor-receiving.md) are unchanged by this
separate worktree.

Six policy XCTest cases cover exact approved URL preservation; unreviewed and
confusable authorities; unsafe schemes and malformed input; the exact byte
boundary and invalid limits; bounded host configuration; and redacted
diagnostics. They exercise Foundation itself when the native package runs.

Eight asynchronous model cases cover loaded/visible records and exact consent;
empty host approval, missing/unsafe sources; replacement and closure;
handler-failure/review recovery; terminal detail dismissal; ordered pagination;
stale contradictory evidence after a handoff; and a recreated version's refusal
of an old review or callback. These use controlled typed source specimens.
They do not qualify altered fixture bytes as a production release and do not
open a browser.

The existing catalog UI journey adds actual **Review source link** and **Close
source review** interactions for the unchanged bundled missing-URI specimen.
It requires the complete missing-URL explanation, absence of an Open action,
and unchanged declaration/date after dismissal. Every preceding and subsequent
filter, selection, relaunch, exact pin, detail, pagination and empty-state
assertion remains, including the separate contained-native-switch correction.
The exact Notes journey and both pinned destinations remain required.

The new `catalog-source-ui` execution profile requires **101 distinct passing
XCTest cases**, including **52 named class-qualified identities across seven
classes**. It retains every mandatory identity from the separate 87-case
receiving profile and adds all fourteen new source-review cases. The historical
42/68/48/87 profiles remain available only for their own source inventories.
Padded historical output, missing classes, duplicate identities, skips, failures
and incomplete summaries still fail closed. Transfer remains exactly 48 on this
stack. Any later main/worker composition must preserve its added cases and use a
new reviewed complete inventory.

**The fourteen new Swift tests and amended device journey are authored but not
yet executed.** Local Python log specimens validate only the execution guard.
Current-source native compilation, all 101 model cases and both full device
journeys must pass before delivery. The missing-URI native case does not establish
installed rejection, positive browser/associated-app handoff, VoiceOver traversal
or physical-device behavior for other destinations. Those evidence scopes remain
open alongside approved host/source-use intake and the other #61 criteria.

## Accepted-main receiving preparation

This separate, unpublished receiving composition combines accepted main
`074ae4bffec6066d3fe6e6a5fe47ab429dde54ed` with the reviewed source-navigation
candidate `3bdb956ab5640a055913621d9b96eec5cf329489`. Their common ancestor is
`f636afb24b8ecc1324a361aa2a7d2caa3a2481d7`. The original #240/#273 candidates,
their running jobs and canonical #198 branch are unchanged.

The ordinary merge exposed four Transfer overlaps. Each resolution retains both
accepted behaviors; no schema, source fixture or evaluator rule is rewritten.

| Overlap | Receiving resolution |
| --- | --- |
| `FrozenValidator.swift` | Keep the complete quality-record and catalog-snapshot validation entry points, each selecting its own unchanged frozen schema. |
| `source-manifest.json` | Keep all nine exact source hashes, including both quality resources and the catalog-snapshot schema. |
| `Tools/verify_contract.py` | Run both the 202-case quality loop and the 77-case snapshot loop after the existing build/item checks. |
| Transfer `README.md` | Retain both API/scope sections and every historical receiving qualification. |

The complete 200-leaf comparison preserves every other input byte except the
explicit Transfer execution-profile update and this receiving record. All app,
UI model, source-navigation policy, device-journey and UI workflow blobs remain
exactly those of the reviewed source candidate. Main's newer Core, Catalog,
quality-record, dependency and conformance-harness changes are retained.

| Package | Accepted main declarations | Source candidate declarations | Receiving declarations |
| --- | ---: | ---: | ---: |
| PlannerUI | 23 | 101 | 101 |
| PlannerTransfer | 45 | 48 | 57 |
| PlannerCore | 85 | 67 | 85 |
| PlannerData | 25 | 28 | 28 |
| PlannerCatalog | 44 | 36 | 44 |

These are distinct class-qualified source inventories, **not executed Swift
results**. The new `catalog-quality-transfer` gate requires 57 passing cases,
including the prior twelve required identities and all nine quality-record
regressions: 21 required identities across four classes. The native UI gate
remains 101/52/seven. Every historical profile, the strict parser, both history
guards and the complete device journeys remain intact. Another accepted-main or
worker addition requires a newly reviewed complete inventory.

Local preparation verified all nine bundled hashes, 129 build/selection cases,
1,635 item cases across 29 kinds, 202 quality cases and 77 snapshot cases with
the existing Python 3.12.14/jsonschema 4.26.0 environment and format checks.
The separately pinned Python/jsonschema 4.25.1 contract harness verified its
manifest and every covered byte before passing 137 schema vectors, six domain
checks, three detected mutations and all 24 harness regressions with zero skips.
The reusable research checkout supplies the exact locked contract bytes; its
current Git revision is not represented as the historical contract revision.
All 59 CI helper tests, including ten execution-guard methods, and all 26 app
runner tests passed. Fourteen real CLI trials also passed their expected
outcomes: complete 57/101-case synthetic logs are accepted, each of the
eleven required class substitutions is rejected, and padded old 48-case output
cannot replace the nine quality cases. Those logs are parser specimens only.

**No Swift, simulator or device execution has occurred for this receiving
composition.** Its combined 57 Transfer and 101 UI results, other package gates,
both full native journeys and independent receiving review remain required.
Historical runs of either parent cannot qualify this new source combination.

## Primary API references

Apple's [strict URL initializer](https://developer.apple.com/documentation/foundation/url/init(string:encodinginvalidcharacters:))
and [URL parsing documentation](https://developer.apple.com/documentation/foundation/url/init(string:))
describe disabling automatic IDNA and percent-encoding repair.
[OpenURLAction completion](https://developer.apple.com/documentation/swiftui/openurlaction/callasfunction(_:completion:))
reports whether the system can open a URL, possibly before it finishes opening.
The [environment action](https://developer.apple.com/documentation/swiftui/openurlaction)
can hand a universal link to an associated app or a browser. These primary
references were checked on 2026-10-18; no network retrieval occurs in this feature.
