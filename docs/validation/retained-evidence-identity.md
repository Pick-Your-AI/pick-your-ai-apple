# Exact targets for retained-evidence correction events

This bounded correction contributes to [Apple #42](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/42).
The freshness UI, historical-release retrieval, canonical event transport and
rights-aware real-data replay remain with their existing delivery work.

## Behavior

The public `RetainedEvidenceIdentity` initializer accepts nonblank component,
version and catalog-snapshot identities. A correction or retraction must target
that exact retained tuple. Synthesized Swift equality treats canonically
equivalent Unicode spellings as equal, so a byte-distinct target can incorrectly
mark unrelated retained evidence for recheck and remove its current display grade.

The tuple now compares the original UTF-8 bytes of all three fields. Inputs remain
unchanged. An event for a different tuple leaves the current review state and
display grade unchanged; an exact target still requires recheck. Existing review
priority, capture-date behavior, evidence grading and retained history are unchanged.
This is a correction to the generic public projection; it establishes no bypass
through an ASCII-constrained frozen-v1 adapter or an installed application.

## Regression coverage and execution boundary

Two new methods exercise both Unicode directions independently in each tuple
field through actual `EvidencePresentation.receiving` calls. They cover correction
and retraction from both the original and an already-notified review state,
byte-identical reconstructed targets, and retention of a required recheck through
later unrelated events and availability notices. The assertions also preserve
the original identity bytes, status, source and support receipts, and freshness.

Source preparation uses the unchanged target blobs from accepted main
`d64dba942a4eeab3950daf0ee3ceffb883166974`. No Swift toolchain is available in this
local review environment, so no local XCTest execution is claimed. Required
configured native jobs must establish execution at the actual published or
prepared tree; prior package results do not execute these two new methods.

```sh
swift test --jobs 1 --package-path Packages/PlannerCore --filter EvidencePresentationTests
swift test --jobs 1 --package-path Packages/PlannerCore
swift test --jobs 1 --package-path Packages/PlannerCore -c release
```

Independent source review, current-main preservation, applicable native gates,
ordinary signed delivery and actual post-main qualification remain required.
The complete #42 criteria and its UI, real-data, device and release acceptance
remain open.
