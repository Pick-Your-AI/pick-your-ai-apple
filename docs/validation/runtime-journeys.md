# App backgrounding, cancellation and configuration validation

## Scope and independent execution gate

This record covers the remaining concrete app-runtime checks named by #26 and
the missing-configuration launch case in #27. It builds on the canonical #198
editor/Files/startup/catalog target. It retains the complete Notes and catalog
journeys, including durable save, undo/redo, discard, deletion, independent controls,
catalog filtering, exact details and source-review behavior.

All added Swift and XCTest behavior is **unverified native execution** until the
exact reviewed candidate passes the normal hosted workflow. Local portable
runner tests use explicitly synthetic subprocess results and establish only the
runner's failure, metadata and owned-cleanup checks. They cannot close an issue
or substitute for a simulator/device result.

| Named behavior | Source and required observation | Current receiving status |
| --- | --- | --- |
| Background/foreground while editing | `LocalDraftLifecycleTests.testBackgroundRecoveryAndCancelledDiscardPreserveOwnDraft`: edit a newly created synthetic draft, press the real Home action, observe an OS background state, activate, and compare full title/notes in the same editor. | Native execution pending |
| Durable recovery after backgrounding | After foreground recovery, await normal save acknowledgement, clean-close, terminate, relaunch and open the same record ID with exact text. | Native execution pending |
| Cancel a dirty discard operation | A standard-menu paste exceeds the real title limit and produces the actual failed autosave. Cancel the discard dialog (or dismiss its regular-width iPad popover), require exact unsaved input to remain, then explicitly discard and reopen the prior committed text. | Native execution pending |
| Invalid application environment | `ConfigurationLaunchTests.testMissingEndpointStopsStartupWithoutPreviewFallback`: build actual Staging and Release configurations without a live endpoint, require a visible fixed error before libraries open, and repeat after foreground and process recovery. | Native execution pending |
| Correct artifact and no hidden fallback | Read each built app's plist and the same invocation's newly owned app container. Require the exact bundle/environment/contract, absent endpoint and no local-store startup directory for rejected configurations. | Native execution pending |

The background test does not wait for Save before Home, but OS scheduling can
allow the normal 750 ms debounce to finish first. It does not claim a forced race
between debounce and lifecycle save. Controlled model tests cover those distinct
ordering cases. Likewise, discard cancellation is a real UI operation, not
evidence of cancelling every asynchronous adapter request.

## Reproducible execution and artifacts

Use the pinned Xcode 16.4 / build 16F6 selection and supported iOS 18.5 runtime
required by the canonical UI runner. It creates a new iPhone SE (3rd generation)
and iPad (10th generation), records their identities and only cleans up those
verified new IDs. The iOS 17 deployment floor and physical devices remain separate
coverage dimensions.

```sh
python3 -m unittest discover -s App/scripts/tests -v
swift test --package-path Packages/PlannerCore
python3 App/scripts/ui-journey.py --evidence-directory .build/native-evidence/ui-journey
python3 App/scripts/ui-journey.py --configuration Staging --evidence-directory .build/native-evidence/configuration-staging
python3 App/scripts/ui-journey.py --configuration Release --evidence-directory .build/native-evidence/configuration-production
```

Each destination must produce the exact expected passed XCTest count: three Debug
journeys (Notes, Catalog and Lifecycle), one Staging configuration journey and one
Release configuration journey.
Zero/partial/skipped/expected-failure summaries, wrong metadata, opened local
storage under rejected configuration, test failures and cleanup failures all
fail the runner. Test selection is fixed by the requested build configuration.
No rerun/retry flag, alternate runtime, launch seed or app-container reset exists.

Debug keeps the native model/build/smoke and all three complete UI journeys in the
existing native job. The canonical 110-case UI model gate and all 61 required
identities remain mandatory; current Transfer qualification separately requires
all 65 cases and 29 identities in the accepted resource/quality union, retaining
the historical 57-case profile for its own source. Staging and Release run in separate mandatory matrix jobs,
each with both destinations and its own 40-minute deadline. Matrix fail-fast is
disabled so a failed configuration does not cancel the other configuration's
evidence. All three jobs share the conservative native-source scope precondition
and require the exact Xcode pin; each checks its configured cache/build paths are
absent before use. No configuration result is allowed to fail without failing
the workflow. The separate Xcode 26.3 / SDK 26.2 submission lane retains its
five-package and unsigned simulator/device checks; it does not substitute for
these pinned Xcode 16.4 / iOS 18.5 development journeys.

`native-local-drafts-evidence`, `native-configuration-Staging-evidence` and
`native-configuration-Release-evidence` retain their toolchain/build logs, exact
commands, result bundles and screenshots, result summaries, safe built-configuration
metadata and owned-cleanup receipts. Uploads run on failure too, and existing
evidence directories cannot be overwritten. Before accepting execution, link
each run/job, exact tested and
delivered source identities, artifact ID/digest, observed failures/recovery and
independent receiving review. Nothing in this record asserts those future results.

## Remaining issue boundaries

- #26 remains open pending actual accepted results for its named runtime checks
  and any supported simulator/device qualification not supplied by those results.
- #27 consumes the [accepted shared-service architecture](../decisions/issue-23-services.md),
  but still needs an approved deployed origin, actual O1 operating acceptance and
  authenticated response provenance. No fixture-only response, credential-storage, device or release
  acceptance is established by a missing-endpoint launch.
- #28's required interrupted edit followed by a second cold build link is not
  implemented or exercised here. Deep-link routing and protection of unsaved
  work across unacknowledged process termination remain open.
- #29's cancellation/stale-revision and main-actor responsiveness requirements
  need their own exact model, adapter and receiving execution evidence. A Cancel
  button and OS Home event cannot establish those broader guarantees.
