# Network client and atomic-cache recovery checks

This is the bounded test contribution for [Apple #106](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/106),
coordinated in [comment6260843518](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/106#issuecomment-6260843518).
It exercises existing package behavior through a real `URLSession` with an intercepted,
synthetic `URLProtocol`. No request contacts a server. Source preparation begins on
accepted `666033a9f6621e3342b190e75725310fa71f8826`.

**The six new Darwin tests have not yet been executed at this preparation checkpoint.**
Their original configured results, exact checkout/tree and independent receiving
disposition must be linked from #106 before this contribution is accepted. No
production defect, original failing native baseline, live service, installed app
journey or complete #106 criterion is claimed here.

## The composition being checked

The [existing client](../../Packages/PlannerCatalog/Sources/PlannerCatalog/PublicArtifactClient.swift)
streams public JSON through Apple `URLSession.AsyncBytes`; the
[existing cache](../../Packages/PlannerCatalog/Sources/PlannerCatalog/CatalogCache.swift)
validates each pin and commits the complete pair atomically. The original transport
suite uses URLSession interception and stream helpers. The original cache/history
and [full-fixture admission tests](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/SyntheticFixtureAdmissionTests.swift)
invoke downloader closures directly. The new
[NetworkArtifactRecoveryTests](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/NetworkArtifactRecoveryTests.swift)
pass the actual client's `fetch` operation into that cache downloader.

The PlannerTransfer test target already depends on PlannerCatalog, PlannerCore and
PlannerData. Only two existing test-fixture declarations become visible within that
test target so the suites share the same strict fixture oracle. All original test
method bodies, production APIs, package dependencies, cache format, frozen resources
and workflow declarations remain unchanged.

Each test owns a fresh synthetic HTTPS origin, intercepted session and temporary
directory. The first refresh downloads and commits a complete known pair. A fault
then occurs during the second artifact of another refresh. The test compares the
entire stored envelope with its prior bytes and reopens both active and exact-pair
historical lookup. An explicit successful retry must retain exact artifact bytes
and pins, advance only the supplied cache date, and keep synthetic/unknown status.
The cache date used by these tests is controlled fixture time, not a wall-clock or
remote freshness claim.

| Test method | Injected condition | Required observations | Native execution at preparation |
| --- | --- | --- | --- |
| `testTimeoutDuringSecondArtifactPreservesStoredPairAndExplicitRetry` | URLProtocol fails the pricebook request with timeout and private error text | Fixed timeout code; complete prior envelope; exactly two refresh attempts before explicit third-attempt recovery | Pending |
| `testThrottledSecondArtifactPreservesStoredPairAndExplicitRetry` | HTTP 429 with a private response message | Fixed status 429; no automatic retry or partial activation; exact-pair recovery | Pending |
| `testDisconnectedSecondArtifactNeverCommitsPartialData` | HTTP 200, a partial-body notification, then connection loss | Fixed transport code; no partial returned pair; unchanged stored envelope and successful explicit retry | Pending |
| `testMalformedSecondArtifactPreservesStoredPairAndExplicitRetry` | Truncated JSON in HTTP 200 | Original digest rejects changed bytes before parsing/activation; exact original pair remains readable | Pending |
| `testValidChangedPricebookBytesCannotReplacePinnedPair` | Schema-shaped price change under the original immutable pin | Existing Pricebook decoder accepts the changed shape, but the original digest rejects substitution; original bytes recover | Pending |
| `testActualRequestCancellationPreservesPairAndNewerDraftRevision` | Suspend the actual second request after a partial-byte notification; perform a newer local save and attempt stale CAS/overlapping refresh; cancel the task | `stopLoading` observed for that exact held request; cancellation returned; no extra transport; prior cache retained; actual newer draft and two-entry history preserved after reopen and retry | Pending |

Every scenario checks actual request order, GET/Accept fields, absence of body,
Authorization and Cookie, and exclusion of the private draft marker from URLs.
Fault descriptions must exclude the supplied private transport text. The draft
control uses the real SQLite-backed `DraftStore`; its incomplete local payload is
not exported or validated as a BuildSnapshot. Both stored-draft analysis status and
cached current checks stay unknown/noncurrent after recovery.

## Exact fixture and cancellation boundaries

The shared helper requires the unchanged complete examples below. Catalog item
records pass the existing `CatalogItem.decode` boundary; pricebook bytes pass the
existing `Pricebook.decode` boundary. Exact-example admission is a test oracle,
not a general catalog-snapshot schema adapter or permission for real-data promotion.
The original build example is used only to create the local starting draft.

| Test resource | SHA-256 |
| --- | --- |
| [build.json](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/Fixtures/build.json) | `26762208769a8cf1012b4f33b1c1608556d275187ce21117d0b9632cdf951864` |
| [catalog.json](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/Fixtures/catalog.json) | `2e9120db823faef3e1e330a7d2e8067b3ab064328e2faed699d15cf41880fbf8` |
| [pricebook.json](../../Packages/PlannerTransfer/Tests/PlannerTransferTests/Fixtures/pricebook.json) | `716a848822fc2b182d226c597f7e50f4b00a0fe01ba5c03879e858ca6f0c9b46` |

The cancellation fixture reports request entry only after sending response and
partial-byte notifications. It does not assert that an external network delivered
those bytes or that the application consumed them. It records the exact protocol
instance's stop callback, prohibits subsequent client notifications, and requires
the canceled operation to finish. Five-second XCTest waits bound the test's
observations; the production client's existing 30/60-second request/resource limits
are not changed. No retry, sleep-based completion guess or late success notification
is substituted for the stop/completion assertions.

Apple's primary documentation for [stopLoading](https://developer.apple.com/documentation/foundation/urlprotocol/stoploading()),
[failure notification](https://developer.apple.com/documentation/foundation/urlprotocolclient/urlprotocol(_:didfailwitherror:))
and [AsyncBytes](https://developer.apple.com/documentation/foundation/urlsession/asyncbytes)
was read on 2026-10-19. The fixture stops notifications after cancellation as those
interfaces require. The actual SDK compilation and execution remain the API-use
verification; the documentation read is not a native test result.

## Reproduction and evidence disposition

On the configured Apple toolchain, run the focused suite from the repository root:

```sh
swift test --package-path Packages/PlannerTransfer --filter NetworkArtifactRecoveryTests
```

Ordinary delivery also retains the full
[Swift transfer workflow](../../.github/workflows/swift-transfer.yml), including
canonical reference checks, all Transfer methods and unsigned iOS compilation,
and the [submission SDK workflow](../../.github/workflows/submission-sdk.yml).
Both original workflow executions must include all six new methods with no failure
or skip, on their actual prepared checkout. Other required repository gates remain
intact. The current workflow pins are Xcode 16.4 for Transfer and Xcode 26.3 for the
submission compatibility run; record their observed Swift/SDK/runtime versions in
the receiving receipt rather than inferring them from these configuration values.

Local preparation used the retained reference environment on CPython 3.12.14 with
the unchanged pinned requirements. `pip check` passed. The actual unchanged verifier
passed 14 source hashes and seven corpora: 129 build, 1,635 catalog (all 29 kinds),
202 quality, 520 cost, 223 resource, 98 placement and 150 dependency-graph cases.
These 2,957 reference cases do not execute the new network tests. The local Swift
executable is unavailable; Darwin-only URLSession/AsyncBytes and CryptoKit behavior
is therefore pending Apple-platform execution, not a Linux pass or counted skip.

Retain each original log, exact source and prepared tree, named method attendance,
test count/failure/skip totals, observed toolchain, and any original failure plus
its correction. Link the resulting PR/receiving evidence from #106. An unpublished
expected result or later source-preservation review cannot replace that execution.

## Remaining issue acceptance

This package composition does not implement the application request coordinator,
visible-revision analysis (#75), conflict UI or shared conflict service (#90),
background scheduling/expiration, real TLS/network conditions, or physical-device
edit/restart and release journeys. The local CAS control proves only the recorded
package interleaving. Draft/UI and existing cache/service contributions retain their
owners. The complete #106 criteria and required quality/affected-consumer receiving
disposition remain open until their literal outputs and evidence are supplied.
