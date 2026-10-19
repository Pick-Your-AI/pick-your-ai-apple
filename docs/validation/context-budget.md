# Opt-in CD11/CD1-0.1 context consumer preparation

This is the isolated Apple [#37](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37)
preparation reserved in [receipt 6259105538](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37#issuecomment-6259105538).
It consumes a reviewed research candidate through an explicit API. It does not
enter the frozen-v1 dispatcher, change a BuildSnapshot, choose an active route,
publish a shared producer, or accept the whole cross-client/migration issue.
The existing archival conformance owner retains its neutral-wire/local-store
work and receiving route.

## Immutable input and selected boundary

The reference is accepted Research commit
[`449a29be1752a3c545709da466c7d53fc18fef73`](https://github.com/Pick-Your-AI/pick-your-ai-research/commit/449a29be1752a3c545709da466c7d53fc18fef73),
tree `6a188a54d269028e5283288d9f6afa1f63ba2163`. Its CD11 binding reader,
CD1 reader, normalized context calculator, two supporting modules, two schemas,
two original fixtures and MIT license are copied without modification into
[`Tools/context_reference`](../../Packages/PlannerTransfer/Tools/context_reference).
The separate [source manifest](../../Packages/PlannerTransfer/Tools/context_reference/source-manifest.json)
records every original Git blob, byte count and SHA-256. These ten files were
compared with the complete native Git Data tree before copying. They are test
oracle inputs, not new frozen-v1 schemas or application resources.

The original answers are 734 bytes with SHA-256
`be4fc13496144cb559fa2a8116da5f81fd5e1395f50fa6c6b1b8999bf6c9b2f1`;
their original 647-byte binding declares that exact digest. The API preserves
both original `Data` values and checks the answer digest before consuming an
answer. Different whitespace or property order requires a new matching binding.
The digest establishes byte identity; it says nothing about source eligibility.

`ContextBudgetRecord.decode(binding:answers:)` reads only the explicitly selected
`cd11-0.1` / `cd1-0.1` profile. It globally validates every answer record, including
unused records, duplicate keys, pointer syntax, parent/child overlap and numeric
admission. It then reads the seven fixed context fields using their reviewed
types. There is no arbitrary caller-supplied schema evaluator or rule dispatcher.
The existing `JSONValue`, frozen schemas, source manifest and six frozen corpora
remain unchanged.

## Preservation and conservative evaluation

Each immutable `ContextBudgetAnswer` keeps its requested field/path, supplied
state, typed value, optional original source and actual source path. `provided`,
`unknown`, `missing`, `withheld` and `not_applicable` remain distinct. A provided
ancestor can supply a member; an absent member stays missing with its original
parent path. A withheld descendant preserves its cause when the requested parent
has no record. Invalid traversal rejects. No answer is rewritten into a default
and no 0.2 assumption metadata is injected.

Object keys and pointer tokens use exact UTF-8 bytes. Pointer splitting also uses
bytes, so a combining mark following `/` cannot hide a parent/child overlap.
Validated route/model/tokenizer versions compare exact UTF-8, rather than Swift's
canonical-equivalence string comparison. The separate active scope must already
be normalized by the caller; all six scope components and each version/digest
must match. The client does not derive this tuple from a build or use a matching
hash as an approval.

| Condition after successful wire admission | Result |
| --- | --- |
| Explicitly disabled selection | `skipped`, `selection_not_enabled` |
| Unresolved activation | `unknown`, `selection_activation_unknown` |
| Missing active scope | `unknown`, `selection_scope_missing` |
| Different normalized scope | `unknown`, `route_scope_mismatch` |
| Unresolved / ineligible evidence input | `unknown`, distinct evidence reason |
| Explicit activation, exact scope and eligible evidence | Run the normalized context screen |

The typed scope constructor rejects malformed active identity even if a caller
intends to disable the selection. `Bool?` parameters expose exactly true, false
or unresolved; numeric and string truthiness have no API representation.

Counts use JSON integer tokens and exact nonnegative decimal-integer arithmetic.
`1.0`, `1e0`, Booleans, numeric strings and negative counts cannot become integers
by normalization. `-0` denotes zero as in the reference. An exact integer such as
`2**80` remains supported, and one additional token still changes the comparison.
Input bounds are positive and ordered. A separate budget cannot also declare a
provided shared vendor window.

The shared predicate checks input plus reserved output against the shared cap;
the separate predicate checks independent input and output caps. For example,
7,000 input and 2,000 output fail an 8,000-token shared cap, but fit separate 8,000
input / 4,000 output caps. Optional input and total-policy constraints are absent
only when explicitly `not_applicable`; unknown, missing or withheld constraints
stay unresolved. A required output cap marked N/A stays unknown. A qualified
failure dominates an independent unresolved check. Lower and upper findings
remain separate, including a straddling `mayNotFit` result.

`ContextTokenCount.effectiveLimit` uses an extension only when the caller supplies
explicit extension evidence, then applies the runtime ceiling. Absent native
context stays absent. It does not resolve extension eligibility or measure
tokens, memory, runtime capacity, latency, quality or physical-device behavior.

## Native representation limits

The private reader admits at most 512 KiB per document, 48 value nesting levels,
16,384 value nodes, 4,096 bytes per number token and 128 JSON Pointer components.
Public normalized counts admit up to 4,096 decimal digits; internal addition
retains the extra carry digit. Excesses report `unsupportedLimit`, rather than a
canonical schema rejection or a rounded value.

Decimal/exponent tokens, including values in unused records, must survive the
CD1 finite binary64 decimal-readback rule. Whole-valued floats must also equal
their actual binary64 integer; a short printed `1e23` cannot conceal rounding.
The implementation normalizes exact decimal text and reconstructs whole-valued
binary64 integers from their bit pattern. Exponents outside ±10,000 or outside
the native `Int` parsing range report `unsupportedNumber`. Count arithmetic does
not use this floating representation.

JSON strings require valid Unicode scalar values. Lone surrogate escapes are an
explicit native unsupported representation (`unsupportedUnicode`), even where
the Python prototype retains them. Invalid UTF-8 and JSON syntax reject. This
selected profile therefore does not claim unrestricted canonical JSON parity.
Two corpus cases explicitly distinguish canonical admission from these native
Unicode/pointer limits. Size, depth, node and number-length boundaries have
separate Swift tests.

The original documents and sources are available through explicit properties.
Automatic record/answer/scope/result descriptions and error codes omit those
untrusted contents. Nothing in this API sanitizes retained bytes for sharing;
they must not be sent to logs, exports or diagnostics by a caller.

## Shared cases and reproduction

[`context_vectors.py`](../../Packages/PlannerTransfer/Tools/context_vectors.py)
checks all ten pins, copies the verified bytes to a private temporary directory,
then verifies the entire completed copy set before importing any reference module.
It does not import through a mutable research checkout or retrieve a network
resource. The original MIT license is retained with those copies.

The portable [copy-boundary regression](../../Packages/PlannerTransfer/Tools/tests/test_context_vectors.py)
alters an earlier module during a later copy write and requires rejection before
the first import. It also requires a fresh valid retry and restoration of the
caller's module/bytecode state. During local preparation, this controlled fault
actually executed the changed module against the earlier per-file-check order.
The correction checks all completed copies after all writes; this synthetic fault
and recovery do not execute Swift or establish native conformance.

The neutral corpus has **137 record cases**, **331 numeric tokens** and **six
effective-limit cases**. The record inventory has 73 canonical-valid rows, of
which 71 are supported by this native profile, and 64 canonical-invalid rows.
The numeric inventory has 196 admitted and 135 rejected tokens. Expectations
come from the exact pinned Python reader/calculator, not the Swift implementation.
Six Swift methods consume the complete corpus, inspect all seven retained answers
and lower/upper checks, compare byte identities, exercise native limits/recovery,
and check that automatic descriptions do not reveal original sources. Explicit
future CD11/CD1 versions reject without migration; closed root/envelope and
required-byte-binding negatives remain part of this same corpus.

Run with the existing fresh Transfer reference environment:

```sh
transfer_validation_dir=$(mktemp -d)
python3 -m venv "$transfer_validation_dir"
"$transfer_validation_dir/bin/python" -m pip --isolated install --require-hashes --only-binary=:all: -r Packages/PlannerTransfer/Tools/requirements.txt
"$transfer_validation_dir/bin/python" -m pip check
"$transfer_validation_dir/bin/python" Packages/PlannerTransfer/Tools/verify_contract.py
"$transfer_validation_dir/bin/python" -m unittest discover -s Packages/PlannerTransfer/Tools/tests -p 'test_context_vectors.py' -v
"$transfer_validation_dir/bin/python" Packages/PlannerTransfer/Tools/context_vectors.py
swift test --package-path Packages/PlannerTransfer
```

`context_vectors.py --write` explicitly regenerates only the new synthetic corpus.
Ordinary invocation must reproduce its bytes exactly. The configured Transfer
workflow runs the portable copy guard and regeneration with the existing fresh interpreter; all dependency
pins, installation arguments, frozen checks and native commands remain intact.
No additional installer, service, package dependency or network permission is
introduced.

Local preparation on 2026-10-19 used Python 3.12.14 and jsonschema 4.25.1 in an
existing read-only environment to execute the pinned reference and generate the
case expectations. The corrected copy guard's one negative/recovery method passed
in 0.074 seconds, and complete regeneration retained the same corpus bytes.
That is distinct from the configured fresh Apple environment
with jsonschema 4.26.0. Swift and Xcode are unavailable in this local workspace;
no Swift compilation, XCTest, simulator or physical-device success is claimed.
The actual prepared-source workflow must qualify the selected native tree and
the real locked reference environment before receiving acceptance.

Primary language references checked on 2026-10-19:
[Swift strings and characters](https://docs.swift.org/latest/documentation/the-swift-programming-language/stringsandcharacters/),
[UTF-8 view](https://developer.apple.com/documentation/swift/string/utf8view), and
[`Double.description`](https://developer.apple.com/documentation/swift/double/description).
The last documents finite-value round trips, not full equality with Python's
decimal-selection behavior. The shared token corpus is the executable obligation
for this profile. The full Swift language page returned a JavaScript shell in
this environment; source/search excerpts do not substitute for native execution.

## Receiving disposition and remaining work

| Literal #37 acceptance criterion | This preparation and observed result | Remaining receiving work |
| --- | --- | --- |
| All clients agree on pinned cross-platform fixtures and migration behavior. | One isolated opt-in context corpus is generated by the exact accepted Research 449 reference. No all-client or migration agreement is claimed. | Preserve the existing archival conformance owner's bundle and migration results; obtain the actual affected-client and central contract disposition. |
| Run identical version-pinned vectors through Swift and available references; a future unshipped client uses the published harness interface and remains explicitly unverified. | The complete reference generation/regeneration executes locally with the versions above. The same retained input bytes and expected results are wired into six Swift methods, including future-version and negative/recovery cases. | Actual source-bound Swift/native execution and the real locked reference environment are pending. Other client implementation and runtime parity retain their own evidence; this does not substitute for the archival receiving bundle. |
| The language-neutral conformance bundle and Apple migration results is linked with criterion results, exact versions, limitations and receiving-review disposition. | This guide links the new context corpus/generator, exact input manifest and selected representation limits. It records preparation only and performs no frozen-record migration. | Link the actual signed source/prepared/main results and independent receiving disposition after they exist; retain and qualify the separately owned Apple migration results before whole-issue acceptance. |

The preparation consumes the accepted draft/snapshot output of Apple #33 and
the accepted frozen placement output of #35. The latter's 98 placement vectors
do not adopt new context policy. Apple #36's rendering output remains on its
separately owned [#335 receiver](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/335).
That named output and the existing #37 archival receiving boundary are retained.

Before any default integration or whole-issue acceptance, obtain independent
Apple/client and central contract technical review of this exact profile, bind
the actual signed source/prepared/main trees and original configured results,
reconcile the named #36 output, and link the receiving disposition from #37.
Preparation does not close #37, change its assignees/Project state, replace the
archived producer, or imply deployed/runtime cross-client parity. The broader
native migration and application journeys retain their own evidence obligations.
