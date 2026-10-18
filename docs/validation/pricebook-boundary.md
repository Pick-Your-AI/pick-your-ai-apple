# Frozen-v1 pricebook boundary (#32, #37)

Pricebook.decode consumes the immutable 1.0.0 pricebook schema with closed objects,
required fields, explicit kind/meter/price-type/verification enums and exact string
money. Catalog references retain identity/version. Optional source URI remains
absent when absent; a decoded verification value does not establish trust,
applicability or current price. The client performs no pricing calculation.

The byte-identical canonical example is pinned in the fixture README. Eighty-two
identical structural, enum and decimal mutation vectors run in Swift and against
the hash-verified Python schema. CI invokes tools/conformance/pricebook_vectors.py;
Swift tests also cover roundtrip and stricter timestamp/URI cases. Shared helper
extraction retains the existing report-boundary regressions.

Client limits: 4 MiB input, machine Int revisions, strict Gregorian timestamps
without leap seconds, and absolute ASCII source URIs. These unsupported cases
reject rather than round or invent defaults. Python format-plugin parity is not
claimed. This covers Pricebook only, not all 29 catalog kinds, arbitrary historical
migrations, live service pricing, UI or receiving acceptance. The issue's broader
criteria remain open.

## Raw JSON boundary

Both `Pricebook.decode` and `EvaluationReport.decode` require UTF-8 and check raw
object keys before Foundation creates keyed containers. Repeated keys, escaped
spellings of one key, and canonically equivalent Unicode keys reject with a typed
error that contains no source keys or values. Keys in separate objects remain
independent. No input bytes, money spelling, or provenance values are normalized.

The shared Core preflight checks framing and limits traversal to root depth zero
through depth 48 and 131,072 JSON values, counting the root and containers. Object
names do not count as values; each member's value does. The existing 4 MiB bound
is checked before text conversion. This avoids unbounded keyed/evidence container
construction within an otherwise small input. The preflight leaves literal,
number and string-value interpretation to the existing typed decoder. Report
numeric limits, its 32-level evidence limit, Pricebook's machine `Int` range,
and frozen field/type/money checks remain in force. These are client admission
limits and do not extend or replace the frozen schemas.

Twenty [raw-wire vectors](../../Packages/PlannerCore/Tests/PlannerCoreTests/Fixtures/raw-contract-vectors.json)
define literal replacements on the unchanged hash-pinned canonical fixtures.
Swift and `tools/conformance/raw_core_vectors.py` apply the replacements directly
to text; parsing/re-encoding a vector before the boundary would erase the defect.
The Python replay checks the raw-key profile and frozen structural validation.
Native tests separately cover invalid UTF-8/non-UTF8 encodings, Unicode key
equivalence, string punctuation/escapes, exact money and maximum `Int`, malformed
and trailing input, and byte/depth/node bounds. Applicable hosted Core Debug,
Release, iOS SDK and simulator checks remain required for a delivering PR; local
Linux results alone are not Apple platform acceptance.
