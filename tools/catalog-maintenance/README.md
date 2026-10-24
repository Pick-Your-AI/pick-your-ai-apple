# Synthetic catalog maintenance rehearsal (#121)

This separate executable consumes the existing PlannerCore evidence policy,
PlannerData SQLite store, PlannerTransfer contracts and PlannerCatalog cache.
It does not publish data or change the app, cache selector, evidence policy,
frozen contracts, saved-build serializer, or any existing runner.

## Inputs and observations

`fixture-manifest.json` pins five closed fictional inputs and the 14 frozen
schemas plus component registry used for their preflight. Release A saves a valid draft with exact A
catalog/pricebook locks. Release B changes the compute version and illustrative
rate from `0.80` to `0.95`. These values are not vendor prices or entitlements.
The original examples and pinned schemas are unchanged.

The driver invokes a new executable process for seed, maintenance, reopening,
and an adversarial exact-target check. Every successful phase emits the actual
SQLite records, historical bytes, identities and evidence states. It verifies
that the original and unrelated draft remain unchanged; correction/retraction
domain events reduce current display grade and require rechecking while
retaining the original status. The frozen Event v1 wire contract does not
define these notices, so this uses its existing internal domain API with an
explicit synthetic trigger, without claiming an implemented feed protocol.

On a supported Apple host, `native` additionally exercises the actual cache:
A publication, failure and cancellation during B's second artifact download,
successful B replacement, old A lookup, reopening, and production-mode denial.
The exact closed byte allowlist is only a fixture adapter. It is not a general
publisher validator. `portable` never emulates CryptoKit or claims cache credit.

## Running and receiving

Use an already provisioned Python environment matching the research repository's
`requirements-research.txt` (`jsonschema==4.25.1` for this checkpoint), including
its URI/date format dependencies. No dependency is installed by this tool.

```sh
swift build --package-path tools/catalog-maintenance --scratch-path /tmp/maintenance-build --jobs 2
python3 tools/catalog-maintenance/run.py --contracts /absolute/contracts/v1 \
  --executable /tmp/maintenance-build/debug/MaintenanceDrill \
  --mode native --output /tmp/new-maintenance-receipt
python3 -m unittest discover -s tools/catalog-maintenance -p 'test_*.py' -v
```

The output directory must be new and outside the checkout. Original stdout,
stderr, commands, process outcomes, executable/source/input hashes and qualified
observations are retained there. The host unit tests challenge receipt false
positives with synthetic specimens; they are not Swift or native execution.
The dedicated `catalog-maintenance.yml` workflow uses normal pull-request and
main-push events, macOS 15, Xcode 16.4/build 16F6 with Swift 6, and Python 3.12.10.
It checks out immutable research commit `9db556b7fca485c8eb4396f9ee2ceeacdc119d79`
for the canonical schemas, registry and seven pinned validation dependencies.
It builds this executable with two jobs and explicitly runs all six original
portable receipt tests, three native receipt tests, seven JSON-identity
receipt tests and nine producer-JSON tests before the four real native processes. Native specimens test
receipt rejection, not native execution.
The native controls include missing/duplicate cache pins, mixed releases,
rewritten retained bytes, missing failure/cancellation/production-denial controls,
and false currentness or synthetic status. Duplicate same-kind pins must not be
collapsed into a seemingly complete pair. JSON receipt comparisons distinguish
Booleans from numbers while preserving integral numeric equivalence.

Producer stdout rejects duplicate decoded object members at every depth and the
nonstandard constants `NaN`, `Infinity` and `-Infinity` before qualifying a phase.
Escaped spellings of the same name and repeated equal values are duplicates;
the same name in separate objects and distinct Unicode names remain valid.
The original output budget, source and process checks still precede parsing.
Within that budget, raw stdout/stderr and command hashes remain retained on
rejection, later phases do not run, and full qualification stays false. The new
failure reasons contain no member names or values. The nine entry-point tests
mock fixture preflight and all producer responses; neither specimen mode is a
Swift or native run. Existing valid-number/Boolean comparisons are unchanged;
valid JSON exponent overflow is outside this correction's scope.

The workflow always uploads the actual checkout/toolchain records, source and
canonical-input archives, copied executable, build/dependency/test logs and any
original phase outputs and final receipt. A failure before the driver may have
no phase receipt; that remains a failed or unexecuted gate. The native process
must pass all four phases before `full_rehearsal_qualified` can be true. Existing
PlannerCatalog package tests alone do not execute this standalone rehearsal.
Preparing this workflow does not dispatch it or establish a native result.

## Criterion disposition and limits

| #121 criterion | This rehearsal's concrete contribution | Still required for full acceptance |
| --- | --- | --- |
| Traceable data changes reach clients without corrupting historical builds | Exact synthetic A/B pins; actual reopenable store and, when executed on Apple, cached-pair observations | Qualified canonical publisher/client delivery and source-specific maintenance policy |
| Correct/retract, refresh an older client, preserve saved evidence and show warnings | Internal domain-event replay; exact retained bytes/versions/status, recheck state, actual failure/cancellation cache controls in native mode | Installed older-client and rendered-warning observations; real source-rights/maintenance receipt |
| Link rehearsal with criteria, versions, limitations and receiving disposition | This criterion map and machine-readable original receipt with exact inputs/source/executable | Independent current-source review and linked actual result; no automatic issue closure |

The original tool checkpoint `15aea93a` on main `78aa0de9` retains its actual
failed fourth process: the known #348 byte-distinct evidence-target defect.
Its successful seed/maintain/reopen observations are scoped portable persistence
and domain replay; the original overall receipt stays failed. The permanent
`exact-target` phase uses U+00E9 versus U+0065 U+0301 and requires the wrong byte
identity to remain unaffected. Do not normalize or remove that control.

The reviewed #348 correction reached accepted main as signed
`5c4da0e83482286536d4c49667b6f12aeac36144` (tree `c0408668`). This tool now receives
that exact prerequisite through ordinary history, with all existing main files
preserved. Receiving it does not turn the historical failure into a pass: new
results must bind the actual receiving source and executable. The later
`b10710cc` tool checkpoint on `5c4da0e8` has a separately retained portable
four-process pass; its `full_rehearsal_qualified` remains false because the native
cache phases were not executed. At that checkpoint, the separately owned #351
offline selector was not imported.

The current receiving source preserves accepted main `7dd9f7d1ad1a6590021b52bd303d16ffba697f47`,
including #349 network recovery tests (`d29fd608`), #351 offline release selection
(`9fea5270`), and #354 historical quality comparison (`7dd9f7d`). These additive
package contributions leave the rehearsal's existing call paths unchanged; it
does not instantiate the new selector or compare quality records. The prior
portable receipt remains bound to `b10710cc` and its original executable. The
updated source needs its own configured native result; no later package or
rehearsal execution is inferred from this receiving change. These tools make no
physical-device, accessibility-participant,
human-inspection, real independent measurement, or canonical-feed claim.
