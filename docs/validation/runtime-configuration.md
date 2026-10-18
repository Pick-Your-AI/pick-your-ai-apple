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

This is a local policy, not an invented service protocol or endpoint. Transport
must authenticate the service and derive response identity from validated
metadata; caller-supplied labels alone prove nothing. Bundle identifiers, actual
endpoints, app-visible errors, secret storage and transport integration remain
unimplemented. Therefore #27's production launch criterion and simulator/UI
acceptance remain open. The [research consumer handoff](https://github.com/Pick-Your-AI/pick-your-ai-research/blob/74b8e6801e9b60a4c476b9ac64ae4114270ab2fd/docs/CONSUMER_HANDOFF.md)
confirms that the relative OpenAPI server `/v1` supplies no deployed host or service
acceptance. Its newer proposal references do not change the frozen contract.
