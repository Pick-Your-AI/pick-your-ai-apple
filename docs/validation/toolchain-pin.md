# Actionable Xcode pin validation

Scope: the remaining unavailable-toolchain and clean-cache case for
[Apple #26](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/26).
The accepted local SwiftUI/iOS 17 architecture, checked-in project and local SQLite
package remain the implementation boundary.

[The pin](../../App/toolchain.json) names Xcode 16.4, build 16F6, and its exact
developer directory. [The verifier](../../App/scripts/toolchain.py) uses the
explicit directory to query /usr/bin/xcodebuild with DEVELOPER_DIR, compares the
complete version/build response, and returns a verified environment only on success.
Missing directories, unreadable/malformed pin files, a failed/timed-out probe or a
different version/build produce setup instructions and exit status 2. The CLI never
searches installed versions. Commands after -- receive the verified environment and
their exit status is propagated.

## Reproduction and retained evidence

Run the portable checks:

```sh
python3 -m unittest discover -s App/scripts/tests -p 'test_toolchain.py' -v
```

The unavailable-pin regression executes the production CLI as a real child process
with a temporary pin naming a missing Xcode bundle. It requires exit status 2, exact
installation/version/path instructions, an unchanged pre-existing environment file,
and absence of a downstream command's sentinel. Its captured failure message is
printed into the retained test log. Additional injected probe tests cover a wrong
version, wrong build, extra output, nonzero exit, timeout, inherited directory
override, malformed configuration and command exit-status propagation.

The native workflow first runs those checks, then invokes the same CLI against the
real repository pin. It records pin-tests.txt and pin-selection.txt. It verifies
empty explicit SwiftPM cache/scratch, Xcode package cache and derived-data paths
before dependency resolution/build, retaining empty-caches.txt. Model tests and the
unsigned iOS Simulator app build use those paths. The existing Xcode/macOS/Swift/
runtime logs and iPhone/iPad launch logs remain in native-local-drafts-evidence.

The five current Swift packages have no remote package dependencies: local package
paths are committed together, and CSQLite uses the selected system SDK. Missing
checkout content fails resolution/build; the verifier does not download or substitute
package or Xcode versions. Future external dependencies require explicit version
pins and their own unavailable-pin regression.

## Acceptance disposition

Source and test preparation is complete in the linked PR. Local execution was
unavailable because the session executor was offline. The exact-head hosted
unavailable-pin test, successful pinned recovery, empty-cache build, artifact
identity and independent receiving review must be recorded before full #26 closure.
A parsed script or a mocked version probe is not the hosted clean-build result.
Simulator compilation and launches do not establish signing, physical-device,
TestFlight or App Store acceptance.
