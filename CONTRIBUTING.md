# Contributing

Current team and Project names: [organization naming register](https://github.com/Pick-Your-AI/.github/blob/ce8c876f6331b4f427d7fc8c2deff4776d003cf5/docs/NAMING.md).

Start from the existing fully qualified planning issue linked in the README. Read its acceptance criteria and decision-record path, reconcile prerequisites, confirm the live assignee and receiving reviewer, and inspect overlapping PRs. Do not infer implementation assignment from repository creation or research ownership.

Use a scoped branch, signed commits and a pull request. Obtain independent receiving review and satisfy repository rules before merge. Include the canonical issue, changed behavior or guidance, evidence, limitations and required handoffs. Do not close a work package solely because a PR merged; reconcile every acceptance criterion with receiving review and evidence.

## Access, branches and reviews

Early contributors push branches named `contrib/<your-login>/<topic>` to this repository; other contributors work from a fork. Every pull request into `main` needs one approval from someone other than its author, and only maintainers merge. The [organization contributing rules](https://github.com/Pick-Your-AI/.github/blob/main/CONTRIBUTING.md) define roles, credentials and enforcement.

The organization's team model assigns Triage to the `Mobile Apps` parent team and Write to the `Apple/iOS` child team. Triage permits issue and pull-request triage but does not itself grant push access. `Lead Maintainers - Mobile Apps` receives team-granted Admin access; organization owners retain their repository administration rights, and a person's effective access can also include other grants. Additional team grants observed for this repository include `Lead Maintainers - Apple/iOS` (Admin), `Review Leads` (Write) and `Organization Maintainers` (Triage). This is descriptive, not a complete authorization record: check the repository's Settings → Collaborators and teams and effective access before routing or approving work. Early Contributors use their Write access only for their `contrib/<your-login>/<topic>` branches. Team membership and settings are managed by organization owners and designated GitHub team maintainers under the [accepted delegation record](https://github.com/Pick-Your-AI/.github/issues/18); repository Admin access and operational ownership are separate.

For documentation, run `git diff --check`, check relative Markdown links, and manually review scope and canonical references. Changes to the contract preparation harness must also run the [pinned reference/vector/mutation checks and harness tests](tools/conformance/README.md). These Python checks do not validate an Apple application. Swift core changes must run `swift test --package-path Packages/PlannerCore` and the macOS/iOS SDK workflow; consult the [core validation limits](Packages/PlannerCore/README.md). Storage changes must run the [draft regression and actual process-exit replay](Packages/PlannerData/README.md#reproduce) plus the hosted storage workflow. App framework, lifecycle, device and release checks remain separate; never claim full application validation from package or preparation checks.

Keep local build, simulator/emulator, physical device, store and production results distinct. Only perform release, provisioning, spending or outreach when the authority actually granted permits it. Read the organization [code of conduct](https://github.com/Pick-Your-AI/.github/blob/main/CODE_OF_CONDUCT.md).

## Routing decisions

For an unresolved decision, first read the existing issue, its assignees, relevant
decision record and related pull requests. Preserve accepted ownership and local
review, evidence, security and release requirements. Routing identifies a contact;
it does not grant access, appoint an owner, authorize publication or waive a gate.

Use the canonical [escalation guide](https://github.com/Pick-Your-AI/.github/blob/main/docs/governance/ESCALATION.md) and
[versioned routing policy](https://github.com/Pick-Your-AI/.github/blob/main/governance/escalation-policy.json). The [organization governance PR #23](https://github.com/Pick-Your-AI/.github/pull/23) merged on 2026-10-30. The escalation guide and routing policy intentionally follow live `main`; the organization naming register above is pinned to the accepted `ce8c876f` revision for reproducible team-name guidance. Refresh live routing evidence and access before making a decision. Do not claim the central tooling is installed or active.

The order is repository team → repository maintainer → repository lead maintainer
→ applicable parent teams → CompleteDotTech. Record a disposition at each level,
including unresolved, vacant, pending-acceptance or inaccessible roles; membership,
team-management status and repository permissions do not establish accepted
operational ownership. Keep owner placeholders for the final fallback. Do not
silently skip an unresolved role or treat a proposed mapping as accepted.

An operator with read access must refresh the private snapshot before resolving:

```sh
python /path/to/org-checkout/governance/router.py refresh --policy /path/to/org-checkout/governance/escalation-policy.json --snapshot /private/path/routing-snapshot.json --status /private/path/routing-status.json
python /path/to/org-checkout/governance/router.py resolve --policy /path/to/org-checkout/governance/escalation-policy.json --snapshot /private/path/routing-snapshot.json --repo Pick-Your-AI/pick-your-ai-apple --max-age-seconds 86400 --status /private/path/routing-status.json
```

Here `86400` is an **operator-selected example**, not an approved default. Select
an appropriate explicit maximum age; a proposed policy value does not supply one.
Check that refresh succeeded. If refresh fails, stop recipient selection and
report the failure; the last successful snapshot is retained for diagnosis, not
as a current route. Report stale or incomplete coverage explicitly. Keep snapshots,
raw API responses, rosters and private
identities outside public Git and public issues. Share only the necessary public
team destination and a sanitized decision summary.

When escalation is needed, include the decision needed, current responsible role,
prior disposition and proposed next recipient. Reuse information already in the
issue or PR; routine contributions need no full escalation history. Send nothing
and change no assignment automatically. Follow [Security and private information](SUPPORT.md#security-and-private-information):
no private destination is verified for this preview. This routing guidance adds
no private reporting destination.
