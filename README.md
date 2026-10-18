# Pick Your AI — Apple/iOS

The Apple/iOS planning client for discovering, configuring, checking, costing, comparing and sharing AI stacks. The mobile device is not automatically the inference target.

This repository contains a [Swift client core](Packages/PlannerCore/README.md), delivery proposals and a [frozen-v1 contract preparation harness](tools/conformance/README.md). No application UI, backend or release is included. Swift package tests, iOS SDK compilation, simulator execution and physical-device acceptance are separate evidence stages.

Review the [foundation decision proposals](docs/decisions/README.md), [guest journey proposal](docs/proposals/issue-20-journey-map.md), and [acceptance/ownership intake](docs/proposals/issue-25-acceptance-intake.md) before dependent implementation. These records preserve unresolved receiving decisions; publishing them does not close the delivery issues.

- [Delivery Project 5](https://github.com/orgs/Pick-Your-AI/projects/5) and program [Pick-Your-AI/pick-your-ai-apple#1](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/1).
- Repository and framework decision: [Pick-Your-AI/pick-your-ai-apple#22](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/22). Repository creation is partial progress; framework, module layout and other architecture decisions remain open.
- Shared-service decision: [Pick-Your-AI/pick-your-ai-apple#23](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/23); reuse canonical services rather than create a competing backend.
- [Repository scope](docs/REPOSITORY_SCOPE.md), [contributing](CONTRIBUTING.md), [agent instructions](AGENTS.md), [MIT license](LICENSE).

## Maintainer execution guidance

Use the [platform program prompt](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/d0a1f8b05b90e7e7087fb2f06890265ab5d42606/prompts/mobile/APPLE.md), [shared rules](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/d0a1f8b05b90e7e7087fb2f06890265ab5d42606/prompts/mobile/SHARED.md), [launch instructions](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/d0a1f8b05b90e7e7087fb2f06890265ab5d42606/prompts/mobile/README.md), and [issue/acceptance/handoff index](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/d0a1f8b05b90e7e7087fb2f06890265ab5d42606/prompts/mobile/INDEX.md). These immutable links reference the [proposed migration revision](https://github.com/Pick-Your-AI/pick-your-ai-research/pull/111), open for independent review and not merged. The original research PR 108 is merged; this newer revision reconciles transferred issue identities.

Planning issues now live in `Pick-Your-AI/pick-your-ai-apple`. Refresh live assignees, native parents, prerequisites, Project fields, active work and linked PRs before execution. Do not create duplicate tracking or controllers. Repository creation does not launch a campaign or satisfy a delivery acceptance criterion.

The issue migration preserves the original history and native relationships. Existing Android acceptance-record locations remain in the website repository pending an explicit placement-record change; Apple filenames remain subject to its ADR.
# Delivery status

The [per-issue acceptance ledger](docs/delivery/README.md) tracks all 129 open
issues without treating partial implementation or package CI as full acceptance.
