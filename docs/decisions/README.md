# Apple foundation decision proposals

For the current criterion-level assessment after merged Swift implementation and successful macOS CI, read [foundation disposition](foundation-disposition.md). It separates authorized engineering decisions from actual external inputs. The proposal-1 intake and validation statements below are historical; they do not describe the current CI capability.

The [#21 scope receiving update](issue-21-scope.md) now consumes the accepted #20
journey map at `fd58e522`, whose actual [receiving receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/20#issuecomment-6244060433)
is preserved in the foundation disposition. All 110 candidate classifications
remain unchanged, with an explicit journey trace and missing-field boundaries.
The three literal criteria have separate results: scope content is prepared for
independent product/release receiving review, while the first exact qualified
real-data tuple remains absent. This updates the earlier proposal's #20 status
without turning desk research or synthetic implementation into release evidence.

The [#23 consumer delta](issue-23-services.md) received complete Apple
product/release engineering decision acceptance on 2026-10-19 through the
[actual delegated receiving decision](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/23#issuecomment-6265740527).
It adopts the canonical service decision delivered through Android #347 at signed
`4c753bd6`, its frozen routes, engineering responsibilities and cross-client
handoff. Actual origins, deployed versions, operating/custody commitments and
O1–O6 implementation/activation evidence remain separate. The existing #288/#289
source delivery and reviews retain their historical scope; no service, device or
release execution is supplied by accepting this architecture decision.

Revision: proposal-1, prepared 2026-10-18 UTC against Apple main `bbf013616b67693f887b32849c55aa39a6e5b1e1`. These are concrete engineering recommendations for receiving review, not accepted product decisions, implementation evidence or release approval. They do not alter live issue criteria or assign people.

- [#21 release scope](issue-21-scope.md)
- [#22 platform and module ADR](issue-22-platform.md)
- [#23 shared-service integration delta](issue-23-services.md)
- [#24 accounts, analytics and commerce](issue-24-accounts.md)
- [Refreshed research inputs and available native CI](research-inputs-20261018.md)

The [#20 journey proposal](../proposals/issue-20-journey-map.md) reuses [revision 70b92e9](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/70b92e91045570b8699c4c814058778da68478cd/docs/proposals/issue-20-journey-map.md), correcting its unsupported reference to a missing source manifest. Its desk research is not participant validation. #20 receiving acceptance remains pending. Live #21–24 were refreshed on 2026-10-18: all lacked assignees and comments. Product/release receiving reviewer identity and disposition remain pending; technical review alone does not fill this role. Research PR #111 remains OPEN/unmerged at refresh. Shared/platform/epic-01 prompts were read as proposed guidance alongside AGENTS.md, CONTRIBUTING.md and repository scope.

Source baseline: research `7acbefbf4e4e700231e88be272bc89e3a73dde15`, website `dc66a9e269917ab7241c7d08fd0e7f2a2f039872`. Frozen contract version is 1.0.0. Its [adoption limits](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/ADOPTION.md) distinguish illustrative rules and synthetic fixtures from approved facts. Available schemas, fixtures and research can support preparation and conformance work now; missing production qualification does not invalidate those inputs.

Proposed record placement: retain these decision files, and use Apple `docs/delivery/work-packages/NN.md` for subsequent criterion evidence after #22 receiving acceptance. Existing Android acceptance paths in the website remain unchanged. No relocation is performed by this proposal.

Validation: documentation whitespace/link checks and criterion mapping only. Linux environment has no `xcodebuild`. No app build, simulator, physical-device, integration, signing, TestFlight or production test was executed. Exact delivered commit and independent review receipt must be attached by the publishing PR; no receipt is invented here. All four issues stay open until their exact criteria and receiving review are satisfied.
