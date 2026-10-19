# Vector-helper checks under Python optimization

This is an additive supplement to [Apple #342](https://github.com/Pick-Your-AI/pick-your-ai-apple/pull/342),
supporting the bounded CI and conformance work in [#30](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/30)
and [#37](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/37).

## Remaining helper failure

The #342 source at `b0db87aa958e133be061ab9902514972f4015a36` makes all mandatory
verifier gates and four standalone freshness checks independent of Python
assertions. It also buffers all six success summaries until every phase passes.
Those behaviors and the complete existing verifier are retained here.

The imported vector generators still contain sixteen internal assertions.
Python [omits assertions under optimization](https://docs.python.org/3/reference/simple_stmts.html#the-assert-statement),
so an unsupported mutation operation can be interpreted as a supported `set`.
This is a test-input helper defect; it is not evidence of a new Swift decoder or
frozen-wire acceptance defect.

The sixteen existing helper conditions now raise `ValueError` through a shared
`contract_checks.require` function. The predicates remain exact: five catalog,
three cost, four placement, three quality and one resource-estimate check.
They cover mutation operations, catalog sample types and kind inventory,
unique generated names and placement disposition consistency. Generation and
the four existing `SystemExit` freshness-command tails are preserved.

The #342 verifier, hash lock, source pins, fixtures, reference-environment guide
and workflow remain byte-identical. All failure paths retain the verifier's
all-or-none success output; an earlier phase cannot print a partial receipt.

## Supplemental tests and execution

The existing `test_verify_contract.py` entrypoint imports a separate
`reference_helper_checks.py` TestCase. Its original ten methods remain unchanged;
the same configured CI discovery command now runs fourteen methods:

```sh
"$transfer_validation_dir/bin/python" -m unittest discover -s Packages/PlannerTransfer/Tools/tests -p 'test_verify_contract.py' -v
```

Use the fresh, hash-locked virtual environment documented in
[the reference environment guide](../../Packages/PlannerTransfer/Tools/reference-environment.md).
The existing workflow command is unchanged.

The four added methods run 42 extra child processes: three unchanged-input
controls count all 2,807 real validator calls in ordinary, `-O` and
`PYTHONOPTIMIZE=1` modes; 21 cases reject unsupported helper operations in those
three modes; and 18 environment-mode cases exercise the existing hash, required
format, canonical-result, generated-corpus and standalone freshness gates.
Each process uses a disposable copy and a 30-second timeout. The observer calls
the real pinned validator, inverting only the designated negative result.
Every verifier failure must produce no `Verified` summary.

An independent 2026-10-19 probe of the exact #342 helper blobs rejected all seven
unsupported operations in ordinary Python, but incorrectly accepted all seven
with `-O` and all seven with `PYTHONOPTIMIZE=1`. These fourteen observed false
acceptances are the causal baseline for the helper correction.

The combined configured command passed all fourteen methods, with no failures,
errors or skips, in 69.309 seconds on Python 3.12.14 using the existing verified
nine-package lock environment. Each unchanged-input control checked 12 source
hashes and all six corpora: 129 Build, 1,635 Catalog, 202 Quality, 520 Cost,
223 Resource and 98 Placement cases. Source comparison verified all sixteen
predicate ASTs, every standalone-command tail, the complete original ten-method
test body and the preserved verifier/workflow/guide.

These are local Python results. Actual hosted source-composition, Swift/macOS/iOS,
device, migration and release acceptance require their own evidence. Neither
broader issue is closed by this supplement.
