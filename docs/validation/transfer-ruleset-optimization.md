# Transfer reference checks with the Ruleset corpus

This receiving correction combines the optimization safeguards in
[#342](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/342), source
`7e983474a3a87e87b6b0a28c5a71b723100d9643`, with the frozen Ruleset boundary in
[#359](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/359), source
`aad18439144b72cd9a799b6ea8467263fddb14c8`.
It preserves the earlier [Graph correction](transfer-graph-optimization.md)
and its original execution record.

## Failure and correction

Ruleset adds an eighth reference corpus and two source pins. Its two verifier
assertions and two generator assertions would disappear under Python optimization.
The receiving conflict must retain both the existing explicit Graph checks and
the new Ruleset phase. All eight success summaries now wait for the final Ruleset
case to succeed.

The Ruleset freshness and canonical-result predicates use the verifier's existing
explicit guard. The generator uses the existing shared guard for unique vector
names and standalone freshness. The predicates themselves are unchanged. All
sixteen pinned schema/fixture hashes, all eight corpora, Swift implementation and
Swift tests remain exact; no dependency or workflow changes are part of this
receiving correction.

## Actual portable reproduction and verification

On 2026-10-19, the original Ruleset generator was executed from a disposable copy
of `aad18439`. Appending one newline to the copied corpus caused a normal-mode
failure with the stale-vector diagnostic. The same input incorrectly exited zero
and printed a success receipt under `-O`. Both commands preserved the altered file.

The combined regression source then retained the four original Ruleset assertions
while extending the existing coverage. Three selected methods produced six failed
subcases in 10.496 seconds:

- Both optimized modes called the real canonical validator only 2,957 times,
  omitting all 321 Ruleset cases from the expected 3,278 calls.
- The standalone stale Ruleset corpus incorrectly succeeded under `-O`.
- Duplicate generated names incorrectly succeeded under `-O` and
  `PYTHONOPTIMIZE=1`; normal mode rejected them without the required diagnostic.

After the four guard conversions, the full configured discovery passed all
**18 methods in 142.298 seconds**, with no failures, errors or skips. The unchanged
hash-locked requirements were installed into a fresh private environment using
Python **3.12.14** and jsonschema **4.26.0**; `pip check` passed.

The original sixteen methods remain. Their source-pin, freshness, canonical-result,
real-validator attendance, standalone-command and late-failure recovery checks now
include Ruleset. Two new methods cover duplicate generated names and missing
Ruleset schema, fixture or corpus inputs. The real subprocesses use normal Python,
`-O` and `PYTHONOPTIMIZE=1`; a failed verifier must emit no success summary.

The standalone corrected verifier also passed separately in all three modes,
emitting the same eight summaries after checking **16 hashes and 3,278 cases**:
129 Build, 1,635 Catalog, 202 Quality, 520 Cost, 223 Resource, 98 Placement,
150 Graph and 321 Ruleset. No frozen input was regenerated.

Original focused-failure log SHA-256:
`dc89b4dc845d275973c48af49bf1f7040320a9fc6f491a3b859238fc7b5dab95`.
Complete corrected-suite log SHA-256:
`a7dc4a90b67085b8a178562e5de1f1c9b2fe4778264639875264d76f8ee03fbd`.
Each corrected standalone-verifier log SHA-256:
`603ee45e47caaa7a5d520cc64f97124bc1c93849eee95db03e9559088d8a8a54`.

These executions belong to the local combined Python source, before this note
and later accepted-main carry. They do not execute Swift, macOS, an iOS simulator
or a service, and do not qualify a later commit merely because its Python inputs
are unchanged. Independent source review, actual configured hosted checks and
ordinary main delivery retain their gates. Broader #30, #32, #37 and #103 acceptance
is unchanged.
