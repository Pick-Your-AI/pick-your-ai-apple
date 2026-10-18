# Source-use gate: implementation evidence and remaining acceptance

This is bounded engineering evidence for [Apple #38](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/38)
and [Apple #40](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/40), refreshed with full live bodies/comments on
2026-10-18. It is not a production source-use matrix or an accepted production-promotion record.

## Consumed authority

- [Research #60 rights table](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/92111483b8d52b1b05152391b2d73e9f59ca2fba/research/market/rights-validation.md): terms checked 2026-10-16; source/use decisions and conditions remain separate from approval to ingest or publish.
- [Research #60 model-metadata receiving receipt](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/60#issuecomment-6242698806): accepted with constraints; compilation rights do not cover upstream measurements, weights or cards; no collection authorization inferred.
- [Research #41 accepted T4 receipt](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/41#issuecomment-6242626857): sources without a row default to no automated retrieval, commercial display or redistribution.

No real-source permissions or legal grants are encoded. The implementation consumes an exact decision supplied by trusted intake. It cannot resolve terms, judge legal scope, authenticate a reviewer, or establish that an approval reference exists. A syntactically nonempty reference is not proof of approval. Intake must supply authentic, current, complete decisions and revocations and compute the claim fingerprint from the actual source-derived value. The field-level scope and operation must represent the actual usage, including relevant upstream rights.

## Behavior and tests

`SourceUseRequest` binds source ID, claim ID, source version, snapshot ID, lowercase SHA-256 claim fingerprint, operation, scope and material kind. Operations are Apple display, offline cache, export and automated retrieval; none implies another. A row binds record reference, immutable 40-character revision, row identity, terms reference and checked date. No TTL is invented.

Production authorization requires one matching permitted rights decision, an explicit conditions-satisfied receipt, and one matching accepted production-promotion receipt tied to the exact rights row. Missing, unknown, denied, revoked, incomplete and conflicting inputs deny. Revocation wins over an allowed/accepted duplicate regardless of order. Changed rows need a new exact promotion. A successful result returns the request, dated row and both receipt references for traceability.

Known frozen synthetic catalog identifiers and the exact `2026.10-demo` component version are excluded even when a caller labels them production and supplies apparently accepted receipts. These exact identifiers come from the unchanged frozen `contracts/v1/examples/catalog.json`; no reserved namespace or wildcard is invented. This also contributes a bounded negative case for [Apple #31](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/31), without implementing the complete synthetic/offline app experience.

Synthetic requests return a distinct `syntheticOnly` result, never production authorization. This assumes intake truthfully labels material: calling real source content synthetic cannot grant rights. The production path must handle only `authorized`; the library does not activate data or fetch it. Conditions include notices, attribution, estimate labels and product-scope restrictions; their actual satisfaction remains a receiving-review responsibility.

`SourceUsePolicyTests` covers eleven tests: exact receipt/audit trace; public URL without rights and research without promotion; all identity/scope dimensions; display/cache/export/retrieval separation; unknown/denied/revoked rights; unmet conditions and pending/rejected/revoked promotions; changed dated rows and recovery; conflict/revocation order; synthetic isolation and known-fixture relabel rejection; malformed identities, digests and Gregorian dates. Every scenario is synthetic.

Reproduce with the selected Swift toolchain:

```sh
swift test --package-path Packages/PlannerCore
```

## Criterion disposition

| Issue criterion | Implemented evidence | Remaining acceptance |
| --- | --- | --- |
| #38 Every displayed production field has an applicable source-use decision | Exact field/claim request and fail-closed receipt gate | No real field inventory, production display path or approved real snapshot is integrated |
| #38 Trace display, offline cache and export uses to exact dated rights rows; exclude unknown/revoked even with public URL | Operation-specific matching, row audit, unknown/revoked/public-URL negative tests | Apply to every actual data surface, durable cache and export; verify notices and accepted real source scope |
| #38 Apple source-use matrix linked to #41/#60 with criterion results and receiving disposition | Canonical inputs and engineering tests linked here | Actual source-use matrix and source-rights/evidence/publication plus Apple consumer acceptance remain pending |
| #40 Research merge alone cannot activate production data | Rights decision without a separate exact promotion denies | Activation pipeline integration and real recorded approvals remain pending |
| #40 Merged proposal without promotion must not activate until precise source claims/use rights approved | Exact claim, version, hash, scope, operation and dated row must match separate production approval | No real proposal is promoted; no approval authority is asserted by these test fixtures |
| #40 Acceptance record for Apple production-promotion data slice | Engineering evidence and limitations recorded here | Receiving review, actual promotion acceptance record and supported launch-slice evidence remain pending |

The required integrated replay of an approved real snapshot, malformed/retracted snapshot and unavailable historical release is **unverified**. Atomic activation, preservation of the last valid state, revocation propagation to historical/shared views, durable cache handling and receipt authenticity are not implemented by this synchronous policy. Linux tests establish portable domain behavior only; native build, simulator execution, physical-device behavior and production acceptance remain separate. Neither issue should close from this slice alone.
