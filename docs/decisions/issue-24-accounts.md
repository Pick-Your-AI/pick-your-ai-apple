# #24: Accounts, analytics and commerce decision matrix

Status: proposed; product/release and applicable privacy/security receiving review pending. [Intake](README.md), [scope](issue-21-scope.md), [service requirements](issue-23-services.md).

Recommend guest-first planning with durable local drafts, explicit export/import and local fork. Do not require registration for core local use. No account creation, advertising/tracking SDK, optional product analytics, payments or subscriptions in the first proposed baseline. Public guest sharing still needs server authorization and privacy controls; guest does not mean anonymous to the server or unrestricted writes.

| Alternative / capability | Baseline disposition | Activation obligations and failure/recovery case |
| --- | --- | --- |
| Guest-only local planning | Selected proposal; disclose local retention/loss limits and export options | Test termination, storage failure, local deletion and restore; no promised cross-device sync |
| Guest remote share | Core target, gated by canonical service readiness | Scope write authority, minimize data and preview payload; revoke/expire share; lost acknowledgment cannot duplicate or falsely report success |
| Account-enabled continuity | Conditional and disabled | Explicit product need, identity provider and account data inventory; authentication/revocation, cache isolation, queued-write logout and in-app deletion with associated-data handling before activation |
| Third-party/social sign-in | Disabled | Assess current App Review 4.8 applicability and equivalent login obligations/exceptions for actual identity scope; no automatic claim that every login requires Sign in with Apple |
| Optional usage analytics | Disabled, no SDK installed | Separate purpose, data/retention, disclosure and consent determination; denial/revocation preserves core journey and stops future optional collection; qualify deletion as applicable |
| Tracking / advertising | Excluded from proposed baseline | Separate scope and privacy decision including ATT where actual cross-app/site tracking applies; do not confuse all analytics with tracking |
| Operational diagnostics | Only minimum necessary redacted diagnostics proposed | Inventory actual logs, network metadata and retention; exclude private build content and tokens; explain any data collection in disclosures |
| Digital plans/subscriptions | Conditional and disabled under #125 | Review StoreKit/IAP and actual storefront/program obligations, entitlement authority, restore/refund/revocation and failure recovery before enabling |
| External purchases or links | Disabled | Separate actual product category, storefront and eligibility assessment; no blanket worldwide external-payment exception |
| Additional markets | Conditional under #129 | Market-specific data, support, policy and device qualification; do not inherit approval from another market |

Policy input checked 2026-10-18: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), particularly 3.1 (payments), 4.8 (login), 5.1 (privacy/data and account deletion). Applicability depends on actual behavior, storefront and current terms. This is a decision input, not store approval or legal compliance certification. Recheck against the submitted binary in #113. Guest scope does not eliminate privacy policy, SDK inventory, privacy manifest or disclosure review.

Required desk walkthrough: compare guest local save with an optional signed-in save; guest save must remain available if sign-in is declined. Decline optional analytics without losing core function. Attempt to buy in an unsupported storefront: no purchase UI/route is enabled. If scope later activates these branches, execute session expiry, revocation, deletion with pending writes, consent withdrawal, payment interruption and restore/refund cases against real services. All runtime cases are unexecuted now; no entitlement or identity service is fabricated.

| #24 criterion | Prepared evidence | Remaining acceptance |
| --- | --- | --- |
| Account/revenue decision explicitly selects applicable obligations | Guest baseline and conditional obligation matrix | Product/release approval of exclusions; actual privacy/security applicability review |
| Evaluate guest/account, consent and regional monetization separately without default activation | Matrix, explicit disabled capabilities and decline/unsupported-storefront walkthrough | Exact-version receiving disposition; actual tests only when activated |
| Linked matrix with results, versions, limitations and receiving review | This record, frozen input version and policy check date | Publishing commit/PR, issue link and receiving receipt; no runtime/store evidence claimed |
