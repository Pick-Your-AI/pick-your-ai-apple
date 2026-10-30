# Pick Your AI — Apple/iOS

The Apple/iOS planning client for discovering, configuring, checking, costing, comparing and sharing AI stacks. The mobile device is not automatically the inference target.

This repository contains an [unsigned SwiftUI iPhone/iPad app](App/README.md) for local draft notes and revision history, a [Swift client core](Packages/PlannerCore/README.md), [transactional local storage](Packages/PlannerData/README.md), [frozen-v1 transfer and configuration comparison](Packages/PlannerTransfer/README.md), a [public preview catalog cache](Packages/PlannerCatalog/README.md), and a [contract preparation harness](tools/conformance/README.md). The app's current local editing slice does not establish service integration or a production release. Swift package tests, iOS SDK compilation, simulator execution and physical-device acceptance are separate evidence stages.

Review the [current foundation disposition](docs/decisions/foundation-disposition.md), [guest journey map](docs/proposals/issue-20-journey-map.md), and [acceptance/ownership intake](docs/proposals/issue-25-acceptance-intake.md) before dependent implementation. The [criterion-by-criterion acceptance map](docs/acceptance/README.md) tracks implemented slices and remaining executable work. Decision-artifact acceptance and downstream application, device, service and release acceptance retain their own criteria.

- [Delivery Project 5](https://github.com/orgs/Pick-Your-AI/projects/5) and program [Pick-Your-AI/pick-your-ai-apple#1](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/1).
- Repository and framework decision: [the accepted #22 ADR](docs/decisions/issue-22-platform.md) selects SwiftUI/native adapters, Swift 6, iPhone/adaptive iPad on iOS/iPadOS 17, and local SQLite persistence. The [exact independent receiving receipt](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/22#issuecomment-6244062120) closes the architecture decision; downstream implementation and qualification continue under their existing issues.
- Shared-service decision: [Pick-Your-AI/pick-your-ai-apple#23](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/23); reuse canonical services rather than create a competing backend.
- [Repository scope](docs/REPOSITORY_SCOPE.md), [contributing](CONTRIBUTING.md), [agent instructions](AGENTS.md), [MIT license](LICENSE).

## Maintainer execution guidance

Use the [platform program prompt](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/d0a1f8b05b90e7e7087fb2f06890265ab5d42606/prompts/mobile/APPLE.md), [shared rules](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/d0a1f8b05b90e7e7087fb2f06890265ab5d42606/prompts/mobile/SHARED.md), [launch instructions](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/d0a1f8b05b90e7e7087fb2f06890265ab5d42606/prompts/mobile/README.md), and [issue/acceptance/handoff index](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/d0a1f8b05b90e7e7087fb2f06890265ab5d42606/prompts/mobile/INDEX.md). The migration guidance was published through [research PR #111](https://github.com/Pick-Your-AI/pick-your-ai-research/pull/111), merged on 2026-10-18 as `da3c6045f84260506bd326bb24ddfa8a7e6a23e8`. The pinned Apple and shared prompt contents are unchanged at that merge; these links preserve their immutable source revision.

Planning issues now live in `Pick-Your-AI/pick-your-ai-apple`. Refresh live assignees, native parents, prerequisites, Project fields, active work and linked PRs before execution. Do not create duplicate tracking or controllers. Repository creation does not launch a campaign or satisfy a delivery acceptance criterion.

The issue migration preserves the original history and native relationships. Android acceptance records follow the scoped placement ADRs in its [repository scope record](https://github.com/Pick-Your-AI/pick-your-ai-android/blob/146413ff168583f4c2b0df87ab41d36e57f8ea85/docs/REPOSITORY_SCOPE.md); each ADR changes only its named records, while all other record locations retain their current authority. Preserve Apple's accepted ADR and issue-linked artifact paths.

## Contributor routing

For a blocked decision, use [the repository routing procedure](CONTRIBUTING.md#routing-decisions).
Start with the existing issue and its accepted owner; preserve its scope and evidence requirements.
