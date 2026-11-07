# Apple/iOS contributor instructions

Read [CONTRIBUTING.md](CONTRIBUTING.md), [repository scope](docs/REPOSITORY_SCOPE.md), and the canonical [shared mobile rules](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/d0a1f8b05b90e7e7087fb2f06890265ab5d42606/prompts/mobile/SHARED.md) with the [platform prompt](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/d0a1f8b05b90e7e7087fb2f06890265ab5d42606/prompts/mobile/APPLE.md) before work. Keep shared execution rules canonical rather than maintaining a second prompt set here.

- Use live GitHub assignees as ownership authority. Research ownership does not assign mobile implementation. Preserve native relationships and Project vocabulary; distinguish Needs owner, Needs input, Awaiting decision and an evidenced Blocked state. Do not mark Ready without ownership, scope and prerequisites.
- Refresh the existing issue, acceptance record, linked PRs and active work. Coordinate with existing work. The maintainer-authorized issue migration is recorded in the canonical prompt index. Do not relocate issues again or create duplicate implementations without an explicit mandate.
- Follow the [accepted Apple platform ADR](docs/decisions/issue-22-platform.md) and [current repository scope](docs/REPOSITORY_SCOPE.md) for dependent implementation. The #22 architecture decision is accepted; preserve its module boundaries and resolve the applicable shared-service inputs through [Pick-Your-AI/pick-your-ai-apple#23](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/23). Reuse canonical service outputs rather than defining a competing backend.
- Preserve acceptance paths and shared contract/evidence authorities in the scope record. Do not fabricate evidence, owners, dates, estimates or commitments.
- Address applicable lifecycle and state restoration; durable storage and migrations; offline synchronization; entitlements and permissions; universal links; accessibility; simulator and physical-device testing; signing/provisioning, TestFlight and App Store delivery. Verify current platform and store requirements from primary sources during implementation/release.
- Separate local builds, simulator/emulator results, physical-device evidence, store submission, approval, authorized release, installed production verification and operational readiness. Report missing evidence explicitly.
- Follow signed commits, PR review and existing repository gates. Never commit credentials, signing keys, customer data, raw evidence downloads or model weights.
- Never shut down or terminate the shared WSL VM. Diagnose individual sessions/services without affecting other workloads.

The pinned Apple and shared prompt contents were accepted unchanged through [research PR #111](https://github.com/Pick-Your-AI/pick-your-ai-research/pull/111), merged on 2026-10-18 as `da3c6045f84260506bd326bb24ddfa8a7e6a23e8`. The immutable links preserve that guidance; current accepted decisions and live issue state remain authoritative for execution.

## Decisions and escalation

For unresolved decisions, follow [CONTRIBUTING.md#routing-decisions](CONTRIBUTING.md#routing-decisions)
and the [canonical escalation guide](https://github.com/Pick-Your-AI/.github/blob/main/docs/governance/ESCALATION.md).
Refresh private routing evidence before choosing a recipient. Report unresolved
roles and failed or stale lookups explicitly; do not infer accepted ownership from
membership or access. Preserve the existing assignee, local gates and private-reporting
boundaries. The [organization governance PR #23](https://github.com/Pick-Your-AI/.github/pull/23) is merged. Refresh the live policy and private routing evidence; these instructions do not enable automatic routing, permission changes or recurring jobs.
