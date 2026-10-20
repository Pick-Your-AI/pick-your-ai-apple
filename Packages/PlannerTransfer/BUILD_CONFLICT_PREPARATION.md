# Local conflict preparation (#90)

This is an isolated preparation slice for
[Apple #90](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/90),
reserved in [comment 6284315221](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/90#issuecomment-6284315221).
Its output is a private, deterministic comparison of two supplied immutable Build
snapshots and an explicit local keep proposal. The helper has no persistence,
service, account, queue, or UI authority.

## Inputs and preservation

`BuildConflictPair` accepts values already admitted by
`BuildTransfer.snapshot(fromDraftJSON:)`. Both must have the exact same UTF-8 build
identity and exact owner reference. This conservative local restriction does not
authenticate the owner or incoming source. A different owner is unsupported by
this preparation profile, rather than silently displayed in another owner's
review. The existing frozen contract, bounded parser, resources and validators
are unchanged.

Both snapshots remain available in full. Private fields, locks, ordered arrays,
optional absence, explicit nulls and exact supported numbers are retained. These
are the validated values, not a claim to preserve the original input's whitespace
or numeric spelling. `BuildSnapshot.encoded()` retains its existing serialization
and reopening limits. Private values and differences must not be logged or passed
to a sharing API without the existing separate projection and review.

The comparison recurses through objects in UTF-8 key order. Paths escape `~` and
`/`; canonically equivalent Unicode spellings remain distinct. Arrays are exposed
as complete ordered before/after values, without guessed element correspondence.
Nothing is classified as a safe merge or an authoritative winner. Different edits
at the same revision are allowed, as are differing revisions; a larger revision
number never automatically selects the incoming value.

## Explicit local decision

`BuildConflictSession` owns one immutable pair. `beginReview()` issues an opaque
token and retires any previous token. `cancelReview()` retires only the token;
both snapshots remain in the session. `prepare` requires all of:

- The current token issued by that exact session.
- An explicit `keepLocal` or `keepIncoming` choice, with no default choice.
- The caller's current local editing-context UUID.
- Freshly read local and incoming snapshots that exactly match the reviewed pair.

The caller must rotate the context UUID whenever the active editor, account or
authority changes, including away-and-back transitions. The UUID is local
freshness information, not authentication. A stale value or context retires the
active token; supplying the old value later cannot revive it. An old or foreign
token cannot consume a newer valid review. The actor serializes concurrent
preparation, so one token can produce at most one proposal.

A successful `BuildConflictProposal` retains **both** originals and the explicit
choice. Its `selected` value is the chosen unchanged snapshot. Preparation does
not increment revision/timestamps, create a fork, merge fields, commit a draft,
enqueue a write or acknowledge a remote update. If a subsequent caller-owned
durable write fails, both originals are still available and another attempt
requires a new explicit review. This is in-memory retention, not crash recovery.

The future durable caller must preserve both revisions until its own atomic
commit and acknowledgment succeed, reject stale current state at that boundary,
and reconcile the existing #89 queue/service output. #425's dispatcher and #84's
fork-lineage work remain separate. This helper introduces no replacement for
their contracts or ownership.

## Source tests and actual execution boundary

`BuildConflictPreparationTests` contains fifteen focused local methods covering
same-revision divergent edits, complete private-value preservation, missing/null
and array-order differences, escaped paths, exact Unicode identity, mismatched
build/owner refusal, both explicit choices, uninferred revision ordering,
one-use preparation/retry, cancellation, newer/foreign review rejection, changed
local/incoming values, context invalidation and concurrent one-use preparation.

The command for this cohort is:

```sh
swift test --package-path Packages/PlannerTransfer --filter BuildConflictPreparationTests
```

The focused cohort passed locally on 2026-10-20 with Swift 6.1.2 on
`x86_64-unknown-linux-gnu`, with warnings treated as errors: all fifteen named
XCTest methods passed once, with zero failures. The original test footer reports
1.19 seconds; the build reports 29.36 seconds. The executed source was staged tree
`903016f720f67cb20bfe44990ccfd2c5cd0fcdaa` over accepted
`e742379f9a474e632a998f1586515f4cb1280b18`; all 337 source files were identical
before and after execution. The later change to this record does not alter
production or test inputs.

The first attempt stopped before any test ran: the compiler reported signal 4
while emitting unchanged `PlannerData`, alongside a missing `sqlite3.pc` notice.
Its original output is retained. One unchanged-source continuation supplied the
verified SQLite package directory with `--pkg-config-path` and used `--jobs 1`;
that continuation produced the passing result above. This does not establish the
cause of the earlier compiler failure. The successful original console has
SHA-256 `51deaaa9a03add337561074ce5cd5664808c2e35b16325180aa1b088f37be253`.

The complete five-path source received independent in-session technical review
for this local preparation scope. This is not a separate-account approval or
Apple persistence/service and privacy receiving acceptance. No local synthetic
method constitutes the issue's required two-client service interruption
demonstration, UI/VoiceOver acceptance, installed-device evidence, or a completed
durable-resolution result.

## Literal criterion disposition

| Live #90 criterion | Preparation contribution and remaining acceptance |
| --- | --- |
| Conflict handling has no silent last-writer data loss. | Both supplied immutable values remain in the pair and every proposal, and selection requires an explicit keep choice. Current work is a local helper; durable/service behavior and receiving acceptance remain unverified. |
| Edit the same revision on two clients, then fail midway through conflict resolution; preserve both versions until an explicit keep/fork/merge decision succeeds. | Same-revision divergent local fixtures, cancellation/stale decisions and a fresh retry are represented in source tests. No two-client run, process crash, durable write interruption, fork or merge-policy implementation is claimed. |
| The conflict diff and interrupted-resolution tests is linked with criterion results, exact versions, limitations and receiving-review disposition. | This package record identifies the tested source, actual local results and limits. Immutable delivery identity and Apple persistence/service plus privacy receiving decisions remain to be recorded. |

All three issue criteria remain open. The preparation depends only on accepted
local interfaces and supplied fixtures; integration acceptance retains #89's
named output requirement. No account, release or real-service scope decision is
made here.
