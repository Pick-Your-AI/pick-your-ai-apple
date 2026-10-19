# Transfer reference checks with the current Graph corpus

This receiving continuation combines the existing [verifier correction #342](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/342),
its reviewed [helper donor #347](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/347),
and accepted main `5c4da0e83482286536d4c49667b6f12aeac36144`.
It addresses the [incoming Graph finding](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/342#issuecomment-6260331611)
within that existing receiving route. It supports #30, #37 and #103 without
closing their remaining implementation and qualification criteria.

## Failure and correction

The original #342 correction covers six corpora and twelve source pins.
Accepted main subsequently added the DependencyGraph schema, fixture and
150-case corpus. Its two verifier assertions and four generator assertions still
disappear when Python runs with optimization. Python's
[assertion semantics](https://docs.python.org/3/reference/simple_stmts.html#the-assert-statement)
therefore also apply to this newly received code.

The composition retains every existing required predicate and buffers all seven
verifier summaries until the final Graph case succeeds. Graph freshness and actual
canonical validity now use the verifier's existing explicit checks. The generator
uses the shared helper check for its two kind inventories, relationship/activation
counts and unique case names. Its standalone freshness command raises an explicit
failure before printing success.

The current-main source manifest, fourteen pinned input hashes, all schema and
fixture bytes, seven generated corpora, Swift implementation and Swift tests are
unchanged. No new wire semantics, dependency version, policy or runtime admission
is introduced. The original #342 CI discovery step and all #347 helper corrections
remain in the receiving tree.

## Actual local reproduction

On 2026-10-19, Python 3.12.14 executed the unchanged accepted Graph generator in
disposable directories under three modes: normal, `-O`, and `PYTHONOPTIMIZE=1`.
The valid corpus succeeded in all three modes. Six independently altered inputs
then produced these results:

| Altered synthetic input | Normal Python | Each optimized mode |
| --- | --- | --- |
| Append a newline to the generated corpus | Rejected | Incorrect success |
| Remove one dependent kind | Rejected | Incorrect success |
| Remove one dependency kind | Rejected | Incorrect success |
| Remove one relationship | Rejected | Incorrect success |
| Remove one activation | Rejected | Incorrect success |
| Replace a relationship with a duplicate | Rejected | Incorrect success |

The five schema-shape probes used the generator's existing `--write` command to
isolate its internal predicates from the separate stale-output check. The baseline
has 21 actual child executions and twelve incorrect optimized successes. No
repository input was altered by those probes.

## Receiving regression results

A fresh temporary environment installed the unchanged hash-locked requirements;
`pip check` passed. The configured discovery command passed all **16 methods**
in **95.870 seconds**, with no failures, errors or skips:

```sh
"$transfer_validation_dir/bin/python" -m unittest discover -s Packages/PlannerTransfer/Tools/tests -p 'test_verify_contract.py' -v
"$transfer_validation_dir/bin/python" Packages/PlannerTransfer/Tools/verify_contract.py
```

The original ten verifier and four helper method identities remain. Their corpus,
source-pin, canonical-result, stale-output, real-validator attendance and complete
receipt checks now include Graph. The existing same-directory late-failure retry
also tests restoring the Graph corpus before successful verification. Two added
methods exercise all five generator-invariant failures and missing Graph schema,
fixture and corpus files in each of the three modes. Every failed verifier run
must produce no success summary; a missing final corpus cannot leave a partial
six-corpus receipt.

The standalone receiving verifier also passed: **14 hashes and 2,957 cases**,
comprising 129 Build, 1,635 Catalog, 202 Quality, 520 Cost, 223 Resource, 98 Placement
and 150 Graph cases. The helper observer counts calls to the actual installed
validator and joins that total to the retained corpora. Frozen data was not
regenerated to make the tests pass.

These are local Python checks of this source composition. They do not execute
Swift, macOS, an iOS simulator, a physical device or a service. Independent
receiving review, the actual configured hosted checks, signed delivery and
default-branch verification retain their own gates. The prior #342/#347 logs
remain evidence of their original six-corpus inputs.
