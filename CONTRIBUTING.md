# Contributing

Start from the existing fully qualified planning issue linked in the README. Read its acceptance criteria and decision-record path, reconcile prerequisites, confirm the live assignee and receiving reviewer, and inspect overlapping PRs. Do not infer implementation assignment from repository creation or research ownership.

Use a scoped branch, signed commits and a pull request. Obtain independent receiving review and satisfy repository rules before merge. Include the canonical issue, changed behavior or guidance, evidence, limitations and required handoffs. Do not close a work package solely because a PR merged; reconcile every acceptance criterion with receiving review and evidence.

## Access, branches and reviews

Early contributors push branches named `contrib/<your-login>/<topic>` to this repository; other contributors work from a fork. Every pull request into `main` needs one approval from someone other than its author, and only maintainers merge. The [organization contributing rules](https://github.com/Pick-Your-AI/.github/blob/main/CONTRIBUTING.md) define roles, credentials and enforcement.

The organization's team model assigns Triage to the `Mobile Devices` parent team and Write to the `Apple/iOS` child team. Triage permits issue and pull-request triage but does not itself grant push access. `Mobile Lead Maintainers` receives team-granted Admin access; organization owners retain their repository administration rights, and a person's effective access can also include other grants. Early Contributors use their Write access only for their `contrib/<your-login>/<topic>` branches. Team membership changes go through the Lead Maintainers under the organization access policy.

For documentation, run `git diff --check`, check relative Markdown links, and manually review scope and canonical references. Changes to the contract preparation harness must also run the [pinned reference/vector/mutation checks and harness tests](tools/conformance/README.md). These Python checks do not validate an Apple application. Swift core changes must run `swift test --package-path Packages/PlannerCore` and the macOS/iOS SDK workflow; consult the [core validation limits](Packages/PlannerCore/README.md). Storage changes must run the [draft regression and actual process-exit replay](Packages/PlannerData/README.md#reproduce) plus the hosted storage workflow. App framework, lifecycle, device and release checks remain separate; never claim full application validation from package or preparation checks.

Keep local build, simulator/emulator, physical device, store and production results distinct. Only perform release, provisioning, spending or outreach when the authority actually granted permits it. Read the organization [code of conduct](https://github.com/Pick-Your-AI/.github/blob/main/CODE_OF_CONDUCT.md).
