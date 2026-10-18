# Runtime configuration policy (#27)

The Swift domain boundary selects preview, staging or production explicitly.
Preview accepts synthetic responses and has no live endpoint. Staging/production
require an absolute HTTPS endpoint without userinfo, query, fragment, invalid port
or repaired input, and reject responses from every other data environment. A
missing endpoint is an error with no fallback. Diagnostics carry build identity,
contract version 1.0.0 and environment; errors do not echo rejected URLs or bodies.

The seven RuntimeConfiguration tests exercise all environment combinations,
missing configuration, malformed/credential-bearing URLs, overflowing ports,
parser repair, IPv6 and escaped paths, and unsupported contract versions. The
independent review found URL parser repair and port-overflow gaps; regression
vectors now reject those inputs. Test endpoints use example.invalid and make no
network requests.

## Explicit bundle configuration and launch guard

`RuntimeConfiguration.fromBundleInfo` reads the actual built Info.plist, with no
process-environment or launch-argument override. Eight additional native tests
cover absent/unrecognized environment labels, cross-environment bundle identity,
missing live endpoints, the preview endpoint prohibition, malformed/credential
values, bounded version diagnostics and the exact contract version.

| Xcode configuration | Environment | Development bundle identifier | Endpoint checked into this repository |
| --- | --- | --- | --- |
| Debug | preview | `invalid.pickyourai.localpreview` | None; preview forbids one |
| Staging | staging | `invalid.pickyourai.staging` | None; launch must fail visibly |
| Release | production | `invalid.pickyourai.production` | None; launch must fail visibly |

The explicit [Info.plist](../../App/Configuration/Planner-Info.plist) expands
settings from the three adjacent `.xcconfig` files. An explicit plist is needed:
[Apple documents](https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list)
that arbitrary user-defined `INFOPLIST_KEY_` settings do not create custom keys.
The bundle identifier must agree with the declared environment. These `invalid`
identifiers are development configuration, not registered App Store identities.
No deployed endpoint has been selected. Endpoints are nonsecret base URLs;
authentication credentials must not be supplied through these settings.

`ApplicationConfigurationView` validates before constructing either local
library. Missing live endpoints show a fixed actionable error; other invalid
configuration shows fixed error text without rejected values. Successful local
configuration exposes its environment, bounded numeric build identity and
contract version. It does not establish a service connection.

The actual [configuration UI test](../../App/PlannerAppUITests/ConfigurationLaunchTests.swift)
cold-launches Staging and Release without overrides, checks the missing-endpoint
screen and absence of the preview library, backgrounds/foregrounds the app, and
repeats the check after process relaunch. The strict runner reads the built plist
and verifies that the run's newly owned app container has no `LocalDrafts`
startup directory. It requires the exact selected XCTest count, zero failures or
skips, correct bundle/environment/contract metadata and owned-simulator cleanup
on both pinned destinations. A green test summary alone cannot satisfy that gate.

Native execution of this added bundle/launch scope remains **unverified** until
the exact candidate's successful hosted log and artifact are linked by receiving
review. The portable runner's synthetic subprocess tests validate its checks;
they are not app execution. See the [runtime journey record](runtime-journeys.md)
for the evidence and remaining criteria.

This remains a local configuration policy, not a service protocol or endpoint.
Transport must authenticate the service and derive response identity from
validated metadata; caller-supplied labels alone prove nothing. Actual endpoint,
credential storage and transport integration remain unimplemented. Fixture-only
network-response rejection, physical-device and complete #27 acceptance remain
open. The [research consumer handoff](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/74b8e6801e9b60a4c476b9ac64ae4114270ab2fd/docs/CONSUMER_HANDOFF.md)
confirms that the relative OpenAPI server `/v1` supplies no deployed host or service
acceptance. Its newer proposal references do not change the frozen contract.
