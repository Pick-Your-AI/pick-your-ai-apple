# Bounded submission-check inputs

## Scope

This record supplies a bounded tooling correction for [issue #110](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/110).
It concerns the [Xcode pin reader](../../App/scripts/toolchain.py) and the
[submission SDK checker](../../App/scripts/submission_sdk.py). The separate
[unsigned SDK compatibility record](submission-sdk.md) defines the checker's
existing purpose and release limitations.

The inspected baseline is `63df6b24b7bee4272bdcc8e75ad679202089110b`, tree
`7a4e6dff0e1f18d35b82b9d3958abcf6e3b6eded`. The correction keeps the same accepted
sizes and diagnostics:

| Input | Maximum accepted bytes | Oversized-input diagnostic |
| --- | ---: | --- |
| Xcode JSON pin | 4,096 | `pin file exceeds 4096 bytes` |
| Submission SDK JSON pin | 4,096 | `SDK pin exceeds 4096 bytes` |
| Built-product `Info.plist` | 1,048,576 | `built Info.plist exceeds the inspection bound` |

Each caller previously allocated the entire file through `Path.read_bytes()`
before checking its bound. The shared `read_bounded` helper now requests only
the permitted bytes plus one overflow-detection byte from one binary stream,
closes the stream, and applies the existing size diagnostic before parsing.
It does not rely on a preceding path-size observation that could become stale.
This bounds the returned input buffer; it is not a claim about total parser or
process memory use.

Exact Xcode and SDK pins, platform/deployment checks, supported metadata fields,
error wrapping, output-path protection and receipt publication remain intact.
A failed recheck still removes the earlier ordinary success receipt before
input loading; a subsequent valid inspection publishes a fresh receipt. The
helper does not select a different toolchain or SDK.

## Original failure and corrected results

The original and corrected CLI experiments ran on Linux with CPython 3.12.14.
Each child had `RLIMIT_AS = 67,108,864` bytes, `RLIMIT_CORE = 0`, and a ten-second
timeout. The inputs were owned synthetic regular files. The large input was a
96 MiB sparse file of zero bytes, created by truncating an empty file; its
logical size was 100,663,296 bytes and its allocated blocks remained below
1 MiB. No application binary or native command was executed.

For each of the three input paths, the same `submission_sdk.py inspect` command
performed five calls: valid input; input of exactly the limit plus one byte;
valid recovery; the 96 MiB sparse input; and valid recovery again. The other two
inputs remained valid. Every rejection checked empty standard output and the
absence of the preceding success receipt. All oversized files were restored to
their exact initial fixture bytes.

| Evidence | Original outcome | Corrected outcome |
| --- | --- | --- |
| Three 96 MiB inputs under the 64 MiB child limit | Three uncaught `MemoryError` failures, exit 1, before the size diagnostic | Three controlled size rejections, exit 2; no `MemoryError` |
| Twelve valid, limit-plus-one and recovery controls | All twelve passed | All twelve retained the same exit, output, error and receipt behavior |
| Six added portable regressions | Three read-budget failures and three passing boundary/recovery controls | All six passed |
| Complete two helper test modules | The original 25 methods were retained without modification | All 31 methods passed, zero failures, errors or skips |

The corrected four-file executable/test tree was
`3cfb2208c91d80f955a188a66bbe79bef8016336`. The 15-call corrected CLI protocol
completed at `2026-10-19T13:12:08.780624+00:00`. The note added afterward does not
change any executed Python bytes. The receiving packet retains the original
failures as well as the corrected results; no original result was relabeled.

The twelve-control comparison retains exact outputs and receipt contents.
Only the known, different temporary probe-directory prefixes are normalized
when comparing path-bearing error messages. The three sparse-input failures
remain separate comparisons with their original stderr and exit codes.

## Reproduction and source identities

Run the directly affected portable helper gates from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s App/scripts/tests -p 'test_toolchain.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s App/scripts/tests -p 'test_submission_sdk.py' -v
```

The [toolchain cases](../../App/scripts/tests/test_toolchain.py) cover the Xcode
pin boundary. The [SDK cases](../../App/scripts/tests/test_submission_sdk.py)
cover the SDK pin and product metadata boundaries. A budgeted in-memory stream
rejects any unbounded request or cumulative read beyond the permitted input
plus one byte. These three probes fail against the original readers. Separate
real-file controls accept valid JSON or XML padded with whitespace to the exact
limit, reject one extra byte, and accept restored valid bytes. The product case
uses the actual CLI on both platform paths and verifies receipt removal and
recovery without retaining unrelated app metadata.

To reproduce the resource-limited protocol separately on Linux, use the
synthetic pin/product fields from `SubmissionSDKTests`, an ordinary output file
outside the protected input paths, and the five-call sequence above. Invoke the
actual `inspect --sdk iphoneos --app <fixture-app> --output <receipt>` operation
with explicit `--toolchain-pin` and `--sdk-pin` arguments. Apply both resource
limits in the child before execution, retain stdout/stderr and exit status for
each call, and restore the changed input before its recovery call. This is a
local allocation/recovery experiment, not native SDK or release validation.

| Corrected source | SHA-256 |
| --- | --- |
| `App/scripts/toolchain.py` | `76eec723268f5deadea562a2c0ace5fd09deef08eff16afb5eecfb8830406fbb` |
| `App/scripts/submission_sdk.py` | `9deb3855fdc6a9aa28371ce5b63b95711c5f9444116ae839b289e75da8420dec` |

The original submission pin files remain byte-identical: SDK pin SHA-256
`df76e57d95d6f9b97a1c5a714eb2007807b8c08302ee92150f136be05fbd13a6`
and Xcode pin SHA-256
`6c456bdd80b2f3d768f9f8a0f8fa724a7998edf0d3094874c1c8dfb5a25e6542`.

| Retained local evidence | SHA-256 |
| --- | --- |
| Original 15-call baseline JSON | `8b9ec41f66dd4596164a4631bda25c7b95b017604e4fec547fdbdfeef0b080c1` |
| New-regression pre-correction log | `9192a279bd6bb5f6131e5b2c68c125d751ee9fe6a8f20100c67df4bc394aa3dc` |
| Corrected 31-method helper log | `3085ad5d639b7d97195cb83be8c3e0ab15d0fa64171ef3341ae824de85a69e56` |
| Corrected 15-call recovery JSON | `c4e734c781c48432a06bd47843bff692060b1da5e597538e8ad7088370caffb7` |
| Original/corrected control comparison JSON | `41e1de680e022db4c55fdc36c36ede98bae7914bad958a9675e63aece25e3a96` |

## Acceptance and receiving boundary

| Literal issue #110 criterion | Contribution and remaining evidence |
| --- | --- |
| Release binary passes the selected security and configuration checks. | This tooling correction does not supply a release binary or its required security acceptance. |
| Inspect the signed release binary for debug endpoints, excess entitlements, vulnerable packages and bundled secrets; retest remediations on the same candidate identity. | The portable input readers now reject oversized files before unbounded allocation. Signed-product endpoint, entitlement, dependency, secret and remediation inspection remains separate. |
| The release-binary security/configuration qualification is linked with criterion results, exact versions, limitations and receiving-review disposition. | This note records the bounded local result. It does not represent the complete release qualification or complete this criterion. |

Record independent source/receiving review and the configured checks against
their actual published source and prepared merge. Those later runs remain
separate from this Linux execution. No workflow, native-scope policy, platform
minimum, entitlement, signing setting, release requirement or issue checkbox is
changed here. No physical-device, signed-archive, TestFlight, App Store,
production-service or broader security acceptance is inferred.
