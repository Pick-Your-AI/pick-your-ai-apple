# #34: Apple consumer API requirements and reference cases

Status, 2026-10-18: **consumer preparation for canonical review; no approved extension or live adapter acceptance.** This packet addresses [Apple #34](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/34) under the accepted [Apple module scope](../REPOSITORY_SCOPE.md), [service handoff](../decisions/issue-23-services.md) and [guest/account decision](../decisions/issue-24-accounts.md). It preserves the existing [Android #36](https://github.com/Pick-Your-AI/pick-your-ai-android/issues/36) / [Research #40](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/40) contract route and website #15–#18 implementation ownership.

Fresh issue and native-parent intake found no existing #34/#4 discussion claim or #36 proposal; the active Android lane confirmed no unpublished competing proposal. The [bounded Apple preparation claim](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/34#issuecomment-6253928972) assigns this work to the in-session Apple lane. It assigns no human operating role and changes no canonical service branch.

## Exact inputs and authority

- Frozen [OpenAPI 1.0.0](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/api/openapi.yaml), Git revision `7acbefbf4e4e700231e88be272bc89e3a73dde15`: **12,079 bytes**, SHA-256 `6a08d7230c23576889167da6cff48d95093da9dc04d4bfa6ece443ff35089a79`. OpenAPI syntax version is **3.1.0**; its API version is **1.0.0**. These are different fields.
- [Frozen adoption limits](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/ADOPTION.md) and the schema references in that exact API remain canonical. This packet changes none of their bytes or meanings.
- The accepted [Android service baseline](https://github.com/Pick-Your-AI/pick-your-ai-android/blob/4c753bd69f3857d9b15051be86078948e61074ac/docs/SERVICE_BASELINE.md), signed `4c753bd6`, selects the future shared service and operating gates. The [Apple #23 consumer record](../decisions/issue-23-services.md) retains its exact signature/tree, upstream reviews and W1–W9/O1–O6 limits. Neither input supplies an operating endpoint or credential.

The frozen server is relative `/v1`. All fourteen operations inherit `bearerAuth`; none overrides it for anonymous reads. Guest local editing remains available without registration, while future guest remote writes and shares require scoped server authority. This packet does not turn an object ID, imported owner field, shared link or static website into that authority.

## Complete frozen transport inventory

All paths below are relative to the frozen server, not observed URLs. `Error` means the exact `components/schemas/Error` shape; its code strings are not an enumerated status/retry policy.

| Operation | Method and path | Declared request selectors/body | Declared responses |
| --- | --- | --- | --- |
| `listComponentKinds` | GET `/component-kinds` | No operation-specific parameter | 200: inline registry envelope |
| `readCatalogSnapshot` | GET `/catalog/snapshots/{snapshot_id}` | Required string `snapshot_id` | 200: CatalogSnapshot; 404: Error |
| `readDependencyGraph` | GET `/dependencies/{dependency_id}` | Required string `dependency_id` | 200: DependencyGraph; 404: Error |
| `readRuleset` | GET `/rulesets/{ruleset_id}` | Required string path ID and required string query `version` | 200: Ruleset; 404: Error |
| `readPricebook` | GET `/pricebooks/{pricebook_id}` | Required string `pricebook_id` | 200: Pricebook; 404: Error |
| `createBuild` | POST `/builds` | Required `Idempotency-Key`; BuildSnapshot body | 201: BuildSnapshot and declared ETag; 422: Error |
| `readBuild` | GET `/builds/{build_id}` | Required string `build_id` | 200: current BuildSnapshot and ETag; 404: Error |
| `replaceBuildIfRevisionMatches` | PUT `/builds/{build_id}` | Build ID, required `If-Match` and `Idempotency-Key`; BuildSnapshot body | 200: new BuildSnapshot and ETag; 409/422: Error |
| `evaluateBuild` | POST `/builds/{build_id}/evaluate` | Build ID and idempotency; positive integer `build_revision`, optional resource/cost estimate IDs | 200: EvaluationReport; 409/422: Error |
| `publishResourceEstimate` | POST `/builds/{build_id}/resource-estimates` | Build ID and idempotency; ResourceEstimate body | 201: ResourceEstimate; 422: Error |
| `estimateCost` | POST `/builds/{build_id}/estimate-cost` | Build ID and idempotency; positive integer revision/period days and string pricebook ID | 200: CostEstimate; 422: Error |
| `recordQualityEvaluationRun` | POST `/builds/{build_id}/quality-runs` | Build ID and idempotency; QualityEvaluationRun body | 201: QualityEvaluationRun; 422: Error |
| `listCompatibleOptions` | GET `/builds/{build_id}/compatible-options` | Build ID, required string query `kind`, optional string `role` defaulting to `primary` | 200: inline revision/kind/options envelope |
| `proposeDeployment` | POST `/builds/{build_id}/deployment-proposals` | Build ID and idempotency; DeploymentManifest body | 201: DeploymentManifest; 422: Error |

There are **13 paths, 14 operations and seven required idempotency references**. Creation's 201 description says Location is returned, but only ETag appears in its response-header map; that is an explicit documentation/schema reconciliation input. `If-Match` describes a quoted current revision and next-revision body, while its schema is only `type: string`. These observations do not override the descriptive semantic invariant or authorize unquoted revisions.

No collection paging, discovery selection, list/history/fork/delete/share, resource/quality GET, health/readiness or version-negotiation operation is defined by this file. No universal byte limit, timeout, cursor lifetime, retry-after policy, token issuance or unauthenticated response status is declared. Absence is a governance gap, not unlimited admission, proof of endpoint behavior or permission to invent a default.

## Apple requirements for canonical disposition

Each row names a consumer obligation and the exact missing decision. It proposes no route spelling, wire field, status code or token format. New definitions belong in a governed version or an explicitly compatible extension; frozen v1 remains unchanged.

| ID | Required Apple behavior and case | Canonical decision/output requested | Coordination |
| --- | --- | --- | --- |
| R1 Discovery and paging | Discover eligible catalog/graph/rule/pricebook versions; retain exact selected IDs/hashes while paging. Empty, withdrawn and unavailable releases remain distinct. A continuation cannot silently switch the catalog version or filter set | Complete discovery/query schema; stable order and snapshot/cursor binding; maximum page/body limits, cursor expiry and typed restart/rejection. Decide how revoked eligibility affects retained/offline bytes | Android #36 / Research #40; website #15/#18; Apple #45/#87 |
| R2 Build list, pinned history and fork | List only authorized builds; read an explicit immutable revision independently of the current head. Fork creates a distinct identity with deliberate ownership and preserves declared source provenance | Versioned listing/history/fork operations, authority and pagination; head-versus-revision semantics, provenance, retention and conflict behavior. Local import/fork is not evidence of these server operations | Research #40/#42; website #17; Apple #46/#48 |
| R3 Deletion and shares | Explicitly preview the public payload; keep creator powers distinct from link viewing. Deletion/revocation/expiry must prevent stale callbacks, caches or recovery from reactivating authority | Adopted share create/read/revoke/expiry and build-delete contracts; public/private projection, abuse limits, derived-data retention, viewer denial and restoration reconciliation. Resolve whether/how authorized historical records remain readable | Research #40/#42/#60; website #17; Apple #48/#50/#91 |
| R4 Resource, quality and other evidence reads | Read immutable records by adopted identifiers and bind them to build revision, model/runtime/context/concurrency and all artifact pins. Estimated capacity and measured quality remain separate; a different or absent tuple stays unavailable/unknown | Actual GET/discovery contracts, exact tuple and estimator/condition/uncertainty fields, freshness and retraction rules. Existing producer POSTs are not read substitutes. Decide cache eligibility and explicit unsupported representation disposition | Research #40/#41; website #16; Android #79; Apple #36/#49 |
| R5 Guest authority and isolation | Preserve guest local drafts when authorization is absent/expired; cross-object identifiers or an imported owner cannot confer write access. Disable optional account features until their scope activates | Guest issuance/renewal/retirement, object scope, creator/viewer distinction and explicit unauthenticated/unauthorized failure contracts. If accounts later activate, adopt transfer/logout/revocation and cache/queued-write isolation first | Accepted Apple #24 and Android #25; Research #40/#42; website #17; Apple #50 |
| R6 Retry, optimistic writes and uncertain acknowledgment | Retain exact idempotency identity and base revision through retry; never infer that a timed-out write failed. Reconcile head/receipt before showing success or replacing a local draft. Stale `If-Match` follows the defined 409 boundary | Key format/scope/expiry, duplicate-body versus conflicting-body response, durable operation receipt and retention, ETag/Location grammar, commit-unknown recovery and safe retry/rate-limit behavior. No blind retry or invented last-write-wins | Research #40/#42; website #17; Apple #46/#51/#89 |
| R7 Version and transport compatibility | Keep the last compatible authorized draft/cache when API or artifact versions are unsupported. Bind every response to environment, authority, request generation and exact revision; discard superseded responses | Explicit old-client compatibility/rejection, media/schema/API version negotiation, error/redaction/retry taxonomy, maximum decoded body and request/page limits, cancellation behavior, health/readiness and migration/rollback handshake | Android #36/#51; Research #40; Apple #23/#34/#44/#108 |

All seven rows require affected Apple/Android/web review through the canonical contract intake. Website #15–#18 retain their existing implementation obligations; this packet appoints no new backend owner, operator, recovery custodian or reviewer. A real origin, deployed version, operating acceptance and approved contract release remain separate handoffs.

## Concrete reference cases

The following **38 synthetic cases** extract seven inline schemas directly from the pinned OpenAPI. They cover request required fields, integer/Boolean distinctions, extra fields, unknown verdicts, missing error facts and header/registry limits. The payloads have no real user, secret, catalog or evidence content.

`schema_valid` describes only the exact JSON Schema result. Seven cases deliberately document **schema-admitted but semantically unresolved** values: empty estimate/pricebook IDs, revision zero, an unregistered kind, a whitespace idempotency key, non-revision If-Match text and a future registry version. The broader operation description, canonical artifact validation and required version/authority/tuple checks still apply. In particular, K02 is not support for API 99.0.0, H05 does not satisfy the quoted-revision invariant, and O01's literal `unknown` is never a compatibility pass.

These cases do not cover the externally referenced top-level artifact schemas, all HTTP behavior or a Swift transport adapter. Existing [#32 contract conformance](../../Packages/PlannerTransfer/README.md#32-receiving-conformance-record) retains its independent 29-kind/BuildSnapshot artifact scope and native receipts. This intake adds transport-shape observations without claiming another generated-model or app result.

```json
{
  "case_format": "apple-api-intake-1",
  "canonical_revision": "7acbefbf4e4e700231e88be272bc89e3a73dde15",
  "openapi_sha256": "6a08d7230c23576889167da6cff48d95093da9dc04d4bfa6ece443ff35089a79",
  "schema_targets": {
    "evaluate_request": "/paths/~1builds~1{build_id}~1evaluate/post/requestBody/content/application~1json/schema",
    "cost_request": "/paths/~1builds~1{build_id}~1estimate-cost/post/requestBody/content/application~1json/schema",
    "options_response": "/paths/~1builds~1{build_id}~1compatible-options/get/responses/200/content/application~1json/schema",
    "registry_response": "/paths/~1component-kinds/get/responses/200/content/application~1json/schema",
    "error": "/components/schemas/Error",
    "idempotency_key": "/components/parameters/idempotencyKey/schema",
    "if_match": "/components/parameters/ifMatch/schema"
  },
  "cases": [
    {"id":"E01","target":"evaluate_request","payload":{"build_revision":3},"schema_valid":true,"meaning":"valid_shape"},
    {"id":"E02","target":"evaluate_request","payload":{"build_revision":3,"resource_estimate_id":"synthetic-resource-1","cost_estimate_id":"synthetic-cost-1"},"schema_valid":true,"meaning":"valid_shape"},
    {"id":"E03","target":"evaluate_request","payload":{},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"E04","target":"evaluate_request","payload":{"build_revision":0},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"E05","target":"evaluate_request","payload":{"build_revision":true},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"E06","target":"evaluate_request","payload":{"build_revision":1.5},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"E07","target":"evaluate_request","payload":{"build_revision":3,"unpublished_option":true},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"E08","target":"evaluate_request","payload":{"build_revision":3,"resource_estimate_id":null},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"E09","target":"evaluate_request","payload":{"build_revision":3,"resource_estimate_id":""},"schema_valid":true,"meaning":"schema_admits_semantics_unresolved"},
    {"id":"C01","target":"cost_request","payload":{"build_revision":3,"pricebook_id":"synthetic-pricebook-1","period_days":30},"schema_valid":true,"meaning":"valid_shape"},
    {"id":"C02","target":"cost_request","payload":{"build_revision":3,"period_days":30},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"C03","target":"cost_request","payload":{"build_revision":3,"pricebook_id":"synthetic-pricebook-1","period_days":0},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"C04","target":"cost_request","payload":{"build_revision":3,"pricebook_id":"synthetic-pricebook-1","period_days":true},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"C05","target":"cost_request","payload":{"build_revision":3,"pricebook_id":42,"period_days":30},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"C06","target":"cost_request","payload":{"build_revision":3,"pricebook_id":"synthetic-pricebook-1","period_days":30,"assumed_cost":"0"},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"C07","target":"cost_request","payload":{"build_revision":3,"pricebook_id":"","period_days":30},"schema_valid":true,"meaning":"schema_admits_semantics_unresolved"},
    {"id":"O01","target":"options_response","payload":{"build_id":"synthetic-build-1","build_revision":3,"kind":"model","options":[{"catalog_item_id":"synthetic-model-1","catalog_item_version":"1.0.0","verdict":"unknown","rule_ids":[]}]},"schema_valid":true,"meaning":"valid_shape"},
    {"id":"O02","target":"options_response","payload":{"build_id":"synthetic-build-1","build_revision":3,"kind":"model","options":[{"catalog_item_id":"synthetic-model-1","catalog_item_version":"1.0.0","verdict":"compatible","rule_ids":[]}]},"schema_valid":true,"meaning":"valid_shape"},
    {"id":"O03","target":"options_response","payload":{"build_id":"synthetic-build-1","build_revision":3,"kind":"model","options":[{"catalog_item_id":"synthetic-model-1","catalog_item_version":"1.0.0","verdict":"incompatible","rule_ids":[]}]},"schema_valid":true,"meaning":"valid_shape"},
    {"id":"O04","target":"options_response","payload":{"build_id":"synthetic-build-1","build_revision":3,"kind":"model","options":[{"catalog_item_id":"synthetic-model-1","catalog_item_version":"1.0.0","verdict":"pass","rule_ids":[]}]},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"O05","target":"options_response","payload":{"build_id":"synthetic-build-1","build_revision":3,"kind":"model","options":[{"catalog_item_id":"synthetic-model-1","catalog_item_version":"1.0.0","verdict":"unknown"}]},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"O06","target":"options_response","payload":{"build_id":"synthetic-build-1","build_revision":3,"kind":"model","options":[{"catalog_item_id":"synthetic-model-1","catalog_item_version":"1.0.0","verdict":"unknown","rule_ids":[],"assumed_quality":"pass"}]},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"O07","target":"options_response","payload":{"build_id":"synthetic-build-1","build_revision":0,"kind":"model","options":[{"catalog_item_id":"synthetic-model-1","catalog_item_version":"1.0.0","verdict":"unknown","rule_ids":[]}]},"schema_valid":true,"meaning":"schema_admits_semantics_unresolved"},
    {"id":"O08","target":"options_response","payload":{"build_id":"synthetic-build-1","build_revision":3,"kind":"synthetic-unregistered-kind","options":[{"catalog_item_id":"synthetic-model-1","catalog_item_version":"1.0.0","verdict":"unknown","rule_ids":[]}]},"schema_valid":true,"meaning":"schema_admits_semantics_unresolved"},
    {"id":"F01","target":"error","payload":{"code":"synthetic_conflict","message":"Synthetic retained error","correlation_id":"synthetic-request-1"},"schema_valid":true,"meaning":"valid_shape"},
    {"id":"F02","target":"error","payload":{"message":"Synthetic retained error"},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"F03","target":"error","payload":{"code":"synthetic_conflict","message":"Synthetic retained error","correlation_id":42},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"F04","target":"error","payload":{"code":"synthetic_conflict","message":"Synthetic retained error","retry_after_seconds":1},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"F05","target":"error","payload":{"code":"synthetic_conflict","message":null},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"H01","target":"idempotency_key","payload":"synthetic-operation-1","schema_valid":true,"meaning":"valid_shape"},
    {"id":"H02","target":"idempotency_key","payload":"","schema_valid":false,"meaning":"invalid_shape"},
    {"id":"H03","target":"idempotency_key","payload":" ","schema_valid":true,"meaning":"schema_admits_semantics_unresolved"},
    {"id":"H04","target":"if_match","payload":"\"3\"","schema_valid":true,"meaning":"valid_shape"},
    {"id":"H05","target":"if_match","payload":"not-a-revision","schema_valid":true,"meaning":"schema_admits_semantics_unresolved"},
    {"id":"K01","target":"registry_response","payload":{"schema_version":"1.0.0","kinds":{}},"schema_valid":true,"meaning":"valid_shape"},
    {"id":"K02","target":"registry_response","payload":{"schema_version":"99.0.0","kinds":{}},"schema_valid":true,"meaning":"schema_admits_semantics_unresolved"},
    {"id":"K03","target":"registry_response","payload":{"schema_version":"1.0.0"},"schema_valid":false,"meaning":"invalid_shape"},
    {"id":"K04","target":"registry_response","payload":{"schema_version":"1.0.0","kinds":[]},"schema_valid":false,"meaning":"invalid_shape"}
  ]
}
```

## Reproduce the offline reference check

Use Python 3.12 with `jsonschema==4.26.0` and `PyYAML==6.0.3` in an isolated environment. Save the exact pinned OpenAPI bytes to `openapi.yaml`; the verifier rejects a changed file before parsing any schema. It reads this document's only JSON block. No HTTP request, credential, service or canonical source write occurs during this check.

```python
import hashlib
import importlib.metadata
import json
import pathlib
import sys

import yaml
from jsonschema import Draft202012Validator

if importlib.metadata.version('jsonschema') != '4.26.0':
    raise SystemExit('wrong jsonschema version')
if importlib.metadata.version('PyYAML') != '6.0.3':
    raise SystemExit('wrong PyYAML version')
document = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
fixture = json.loads(document.split('```json\n', 1)[1].split('\n```', 1)[0])
raw = pathlib.Path(sys.argv[2]).read_bytes()
if len(raw) != 12079 or hashlib.sha256(raw).hexdigest() != fixture['openapi_sha256']:
    raise SystemExit('frozen OpenAPI bytes changed')
api = yaml.safe_load(raw)
schemas = {}
for name, pointer in fixture['schema_targets'].items():
    value = api
    for part in pointer.split('/')[1:]:
        value = value[part.replace('~1', '/').replace('~0', '~')]
    Draft202012Validator.check_schema(value)
    schemas[name] = Draft202012Validator(value)
seen = set()
for case in fixture['cases']:
    if case['id'] in seen or type(case['schema_valid']) is not bool:
        raise SystemExit('invalid case identity or expectation')
    seen.add(case['id'])
    actual = schemas[case['target']].is_valid(case['payload'])
    if actual != case['schema_valid']:
        raise SystemExit(f"unexpected schema result: {case['id']}")
    print(f"PASS {case['id']} schema_valid={actual}")
print(f"PASS {len(seen)} frozen transport-shape cases")
```

Save that block as a temporary `check_api_intake.py`, then run `python check_api_intake.py docs/proposals/issue-34-api-consumer-intake.md openapi.yaml` from the repository root. Retain the command, exact document/fixture/OpenAPI hashes, interpreter/dependency versions, exit status and every case outcome. Deliberately change one expected result or one source byte and require a nonzero exit; run the unchanged checker under `python -O` as well. These are reference-check controls, not live service failure/recovery.

<!-- apple34-reference-receipt -->
Actual local reference execution, 2026-10-18, used Python **3.12.14**, `jsonschema 4.26.0` and `PyYAML 6.0.3`. All **38 expectations matched** in normal Python and again under `-O`: **17 schema-valid and 21 schema-invalid payloads**, including all seven explicitly unresolved semantic cases. The original 12,079-byte OpenAPI hash, 13 paths, 14 inherited-bearer operations and seven idempotency references were independently checked before replay.

The four deliberate failure controls also behaved as required: changing E01's expected result failed with `unexpected schema result: E01`; changing one source byte failed with `frozen OpenAPI bytes changed` before any case pass. Both controls returned exit 1 in normal and optimized Python. The unchanged runs each returned exit 0. These are six actual local checker invocations; no Swift/native, HTTP or service recovery was executed.

The decoded case fixture, serialized with sorted JSON keys and compact separators, has SHA-256 `70773abfec43a707855f42aad986c2153821063f54b7cee5046745ce7ca9ff5e`. The extracted Python block with one trailing newline has SHA-256 `2066849faad1c5623292030044ee090901bae01d96f3bc00d9c64e7fad8d896a`. The normal and optimized success logs are each **1,084 bytes**, SHA-256 `0ee4bf8b087e06b810db23e481157a53c1c905f1b189ff2dd99ae3a9e7e82082`; each contains all 38 named outcomes and the total. The wrong-expectation logs are each 30 bytes / `1bf0d06b3e5df0442665e0cc685fc6bba61cc4c17fa789c318dc3aa66161a171`; changed-source logs are each 29 bytes / `ef15fc284a6323fcd58fc5b51493244b713096b2c2315a8861d5defe43f42982`.

The retained execution manifest has SHA-256 `1a1560fdcf0e4389c58f749c4f30d64b6622dc258bfc954b1c7bd286515f9192` and records exact invocations, every dependency version, durations, input and output hashes. Its pre-receipt document hash is `903355fdb718440782940e600f59fe16ba177f9426b7f44b39838c5ab09d6aa1`; only this dated receipt and the preparation heading were added afterward, with the extracted fixture/checker bytes unchanged. Independent source and affected-owner review remain separate pending dispositions.

## Required live and affected-client acceptance

| Case | Frozen fact / preparation result | Required receiving observation, still unexecuted |
| --- | --- | --- |
| Missing/retired authority | Every operation inherits bearer security; no unauthenticated status or token lifecycle is defined | Against the approved extension, reject unauthorized writes and cross-object access with its adopted typed response; preserve local editing and ignore responses after authority retirement |
| Unsupported version or unknown representation | K02 demonstrates that the registry's inline string alone does not enforce version compatibility; referenced artifacts have separate canonical validation | A supported old client receives the adopted compatible representation or explicit versioned rejection. No silent pin rewrite, assumed migration or partial promotion; retain the last eligible compatible data |
| Paging limit and stale cursor | No paging contract is present in frozen v1 | Exercise the approved exact limit, overflow and expired/mismatched continuation cases on a pinned collection; preserve selection and prevent mixed-version pages |
| Stale write and uncertain commit | PUT declares 409 and a quoted current If-Match with next-revision body; E03–E08 and C02–C06 test only inline request shapes | Race two authorized writes, verify the exact adopted stale-write response, then drop a post-commit acknowledgment and reconcile the real retained head/receipt before retry or displayed success |
| Wrong resource/quality tuple | Existing POSTs describe production/retention, and schema-valid transport does not prove artifact identity | Request a different model/runtime/context/concurrency tuple and wrong/stale artifact revision; show unavailable/unknown, preserve capacity/quality separation and discard superseded callbacks |
| Outage, cancellation and rollback | Relative `/v1` and the selected hosting topology establish no deployed environment or recovery | Exercise the real adopted endpoint/build during outage, timeout, cancellation, recovery and migration rollback; retain the durable draft and separately prove authority/freshness after restoration |

### Literal #34 disposition

| Issue criterion | This packet supplies | Remaining gate |
| --- | --- | --- |
| Apple adapter conformance passes against the approved API extension. | Exact frozen transport inventory, seven Apple requirements and 38 reference-shape cases | Approved versioned extension, real Swift adapter/reference-consumer conformance and affected-owner receiving approval; criterion pending |
| Review unauthenticated writes, unsupported versions, paging limits and stale-write responses against the approved extension; mocks cannot establish live adapter acceptance. | Explicit four-case mapping above, actual baseline constraints and concrete schema-versus-semantic distinctions | Actual approved-extension observations and failed/recovery receipts, not a mocked endpoint or guessed HTTP status; criterion pending |
| The Apple request/response contract vectors and governance approval link is linked with criterion results, exact versions, limitations and receiving-review disposition. | This exact case packet, pinned provenance, reproducible reference procedure and per-criterion limits | Publish the reviewed packet, submit it to Android #36 / Research #40, attach the actual governance/affected-client disposition and future receiving evidence; criterion pending |

This document is a consumer requirement and synthetic reference artifact. Technical peer review of it does not supply central contract approval, live API conformance, staging deployment, device execution or release acceptance. Existing native issue relationships, assignments, checkboxes and all other acceptance records remain unchanged.
