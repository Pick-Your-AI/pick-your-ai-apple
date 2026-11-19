# Apple help, bug reports and evidence corrections

Use the Apple repository to report a reproducible app problem or request review
of an incorrect public fact. The project is a planning client; synthetic examples
do not establish real compatibility, price, capacity or quality.

## Choose a public route

Check [existing Apple reports](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues)
first. The two focused forms are:

| Route | Useful report |
| --- | --- |
| [Apple app bug](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/new?template=apple-bug.yml) | Exact app/source version, iOS/iPadOS version, simulator or physical-device context, invented reproduction steps, expected/observed result and safe recovery status |
| [Apple evidence correction](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/new?template=apple-evidence-correction.yml) | A public reference and version, the disputed value, proposed correction, conditions and missing evidence or source-use permission |

**GitHub issues and attachments are public.** GitHub may require sign-in. Opening
a link does not submit a report. Review the complete form, then use GitHub's
explicit submit action. Retain the resulting issue URL; a visible triage response
is separate evidence that the report was handled.

These fixed routes contain only a template selector. They receive no app-provided
draft, diagnostic payload, attachment or prefilled private content. This guide
adds no in-app uploader or browser command. Older app builds can use the same
public links; a report about an older build does not claim that it contains newer
features or a later fix.

For app problems, preserve the original private data locally and reproduce with a
new synthetic draft and invented values. Record whether saving was acknowledged
and what a retry, cancellation or recovery actually did. Do not delete original
data or repeat a destructive action merely to prepare a report. If the relevant
version or result is unknown, say so.

## Review diagnostic content before sharing

Diagnostics are optional. You can report a problem with no diagnostic attachment.
Use this manual redaction-preview procedure for any content you choose to share:

1. Prepare a small local metadata preview containing only the app/build or public
   source version, OS version and iPhone/iPad family, simulator/physical-device
   context, and a safe visible status. Keep unknown values explicit.
2. Remove private draft text, names, accounts, record IDs, credentials, private
   URLs, filesystem paths, raw files, logs and exception text. Prefer an invented
   reproduction to a screenshot of real data.
3. Read the entire final preview. Inspect every screenshot or other attachment
   locally, including its visible text and metadata. If safe removal is uncertain,
   leave the attachment out.
4. Manually copy only the reviewed content into the form. Re-read the completed
   form and attachments after any edit, then make the explicit submission.

This procedure does not automatically detect secrets or sanitize GitHub's later
free-text inputs. The form's review checkboxes record the reporter's confirmation.
The app collects or uploads nothing through these repository forms. The existing
[threat model](docs/validation/issue-98-data-threats.md) retains the distinct
device, provider, backup, privacy-manifest and service qualification work.

## Triage and response responsibility

The [bounded #122 intake assignment](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/122#issuecomment-6258084402)
records the in-session Apple project agent's implementation and controlled
synthetic-ticket handling through the existing CompleteDotTech project account.
It supplies no named person's continuing duty rota, monitored private inbox,
support hours or response-time guarantee. Ongoing operating responsibility needs
its own explicit acceptance.

For each handled report, record its category, safe reproduction or source check,
exact relevant version, disposition and next step in the issue. Use these routes:

| Finding | Handling |
| --- | --- |
| Apple implementation or presentation defect | Keep the report in this project, link existing work, preserve safe reproduction and qualify the reviewed fix at its actual version |
| Shared evidence or freshness correction | Record the proposed change and coordinate with [Research #41](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/41) before changing shared outputs |
| Recorded-price or pricing-method correction | Preserve units, currency, region, conditions and unknown coverage; coordinate with [Research #39](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/39) |
| Contract or source-use correction | Coordinate with [Research #40](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/40) or [#60](https://github.com/Pick-Your-AI/pick-your-ai-research/issues/60), respectively |
| Duplicate, wrong category or insufficient safe input | Link the existing work or correct the category on the same report; state the missing safe input and next step without copying private material |
| Confidential information or sensitive security detail | Follow the private-information boundary below; do not quote it or forward it through public comments |

Coordination links do not submit cross-repository reports, assign another person
or grant publication authority. Preserve historical pins and distinguish a
requested correction, reviewed evidence, accepted code and published client data.
A synthetic reproduction cannot establish a vendor fact.

Before closing a report as fixed, link the accepted change, exact verification
and remaining limits. A submitted report, source review, package test, simulator
run, installed-device result and operating drill describe different observations.
The [intake record](docs/acceptance/issue-122-support-intake.md) tracks the actual
controlled drill and the remaining whole-issue criteria.

## Security and private information

**No private/security reporting destination or receiving responsibility has been
verified for this Apple preview.** Do not put confidential details, credentials
or sensitive exploit information in the public forms. This is the verified
intake boundary, not a claim that GitHub's private reporting feature is disabled.
No private advisory route or security email address is advertised as working.

If private information is posted accidentally, avoid quoting it in a follow-up.
Use GitHub's editing/removal and help process for the affected public location;
record only a safe description of the handling. Remove or rotate exposed
credentials through their issuer as applicable. Visible deletion does not
guarantee removal from edit history, notifications, caches or other copies, and
local draft deletion cannot remove a GitHub report.

Confidential intake and an incident response requiring a private channel remain
unavailable until a real destination and responsible receiving role are verified.
Apple [#23](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/23) and the
existing canonical shared-service owners retain service activation and ongoing
operations; this public intake creates no new backend.

## Unresolved decisions

Use [the routing procedure](CONTRIBUTING.md#routing-decisions) for a decision that
needs another responsible role. Keep the original issue and accepted owner;
summarize the decision, prior disposition and next recipient without copying private
rosters or raw API data. The [organization governance PR #23](https://github.com/Pick-Your-AI/.github/pull/23) is merged. Central routing still requires a successful private refresh; it does not promise a response time or assign an unaccepted owner.

Keep credentials, account details, personal/customer data and confidential reports
out of public issues. Follow [Security and private information](#security-and-private-information):
no private destination is verified for this preview. This routing guidance adds
no private reporting destination.
