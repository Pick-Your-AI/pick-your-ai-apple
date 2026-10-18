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
