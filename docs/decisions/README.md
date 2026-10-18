# Apple foundation decision proposals

Revision: proposal-1, prepared 2026-10-18 UTC against Apple main `bbf013616b67693f887b32849c55aa39a6e5b1e1`. These are concrete engineering recommendations for receiving review, not accepted product decisions, implementation evidence or release approval. They do not alter live issue criteria or assign people.

- [#21 release scope](issue-21-scope.md)
- [#22 platform and module ADR](issue-22-platform.md)
- [#23 shared-service integration delta](issue-23-services.md)
- [#24 accounts, analytics and commerce](issue-24-accounts.md)

The [#20 journey proposal](../proposals/issue-20-journey-map.md) reuses [revision 70b92e9](https://github.com/Pick-Your-AI/pick-your-ai-apple/blob/70b92e91045570b8699c4c814058778da68478cd/docs/proposals/issue-20-journey-map.md), correcting its unsupported reference to a missing source manifest. Its desk research is not participant validation. #20 receiving acceptance remains pending. Live #21–24 were refreshed on 2026-10-18: all lacked assignees and comments. Product/release receiving reviewer identity and disposition remain pending; technical review alone does not fill this role. Research PR #111 remains OPEN/unmerged at refresh. Shared/platform/epic-01 prompts were read as proposed guidance alongside AGENTS.md, CONTRIBUTING.md and repository scope.

Source baseline: research `7acbefbf4e4e700231e88be272bc89e3a73dde15`, website `dc66a9e269917ab7241c7d08fd0e7f2a2f039872`. Frozen contract version is 1.0.0. Its [adoption limits](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/7acbefbf4e4e700231e88be272bc89e3a73dde15/contracts/v1/ADOPTION.md) distinguish illustrative rules and synthetic fixtures from approved facts. Available schemas, fixtures and research can support preparation and conformance work now; missing production qualification does not invalidate those inputs.

Proposed record placement: retain these decision files, and use Apple `docs/delivery/work-packages/NN.md` for subsequent criterion evidence after #22 receiving acceptance. Existing Android acceptance paths in the website remain unchanged. No relocation is performed by this proposal.

Validation: documentation whitespace/link checks and criterion mapping only. Linux environment has no `xcodebuild`. No app build, simulator, physical-device, integration, signing, TestFlight or production test was executed. Exact delivered commit and independent review receipt must be attached by the publishing PR; no receipt is invented here. All four issues stay open until their exact criteria and receiving review are satisfied.
