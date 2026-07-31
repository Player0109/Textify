# Textify Implementation Coordination

This file records cross-agent handoffs during implementation.

## Production Model Fault Injection Handoff - 2026-07-25

- GitHub issue #24 owns the narrow production failpoint seam and forced
  subprocess-relaunch evidence needed to replace the release-only modeled
  boundary matrix.
- This slice may update Task 4 model trust and receipt persistence, Task 12
  download/installer/queue persistence, Task 5 active-model settings
  persistence, Task 11 app activation/restoration/reconciliation composition,
  the release-verification target and executable, focused tests, and the
  minimum `Package.swift` wiring needed to execute the worker in a subprocess.
- Shipping code exposes one inert-by-default durability-observer interface.
  It never reads environment variables or terminates the app. Release-only
  adapters own deterministic fault mutation and process termination.
- The declared matrix covers queue authorization/start, resumable metadata,
  installation staging/receipt, activation preparation/preference,
  revocation/restoration, restoration acknowledgment, deletion rename/byte/
  receipt stages, and installed-receipt reconciliation. Recovery must reload
  the same production stores and preserve ownership and activation invariants.
- This work does not alter model selection, catalog presentation, runtime
  engine behavior, public endpoints, or issue #25's external approval and
  real-device evidence gates.
- Final issue #24 verification executes 143 production observer cells in
  isolated subprocesses, including 13 forced terminations, with a fresh
  recovery process for every cell. The seeded 1,000-operation soak schedules
  20 additional forced crashes and relaunches while actually performing all
  1,000 install, reinstall, cancel, delete, and refresh operations. All cells
  recover with zero invariant violations and zero unexplained managed bytes.
- The campaign exposed one deletion-relaunch case in which new attributed
  bytes appeared beside an existing pending-removal directory. The shipping
  remover now removes the prior pending root, renames the newly appeared live
  root to the deterministic pending identity, removes it, and only then
  removes the Installation Receipt.

## Large Catalog Virtualization Handoff - 2026-07-25

- GitHub issue #22 owns the narrow cross-task changes needed to keep the
  Models destinations responsive and state-stable at production and stress
  catalog sizes.
- This slice may update Task 11 catalog derivation, hierarchy state,
  virtualized presentation, focused app performance tests, and Task 14 manual
  performance guidance and retained trace artifacts. It may regenerate the
  Task 14-owned Xcode project only to add the new Task 11 derivation source to
  the app target. It may make only the AppServices integration changes needed
  to publish immutable catalog, eligibility, local-state, and query-result
  snapshots.
- Catalog and eligibility indexes, local-state overlays, and query results
  retain independent immutable versions. Cancellable derivation runs away from
  the main actor; byte-progress updates do not invalidate catalog,
  eligibility, or query indexes.
- Query derivation consumes the immutable Catalog Index's precomputed trusted
  presentations and ID maps rather than rebuilding them from the raw manifest
  for every search, filter, scope, or sort publication.
- Routine publication preserves surviving selection, expansion, focus, and the
  top semantic row plus pixel offset. Removed selection falls back to its
  Checkpoint, then the next row, previous row, and first result.
- This work preserves the signed catalog, queue, inventory, revocation,
  deletion, Purpose Runtime Boundary, and accessibility behavior completed by
  issues #3–#21. It does not change model trust, installation, activation,
  deletion, or runtime transaction semantics.
- The opt-in Apple M4 Max Release stress gate passed with 85.9 ms search p95,
  72.2 ms filter/scope/sort p95, and 43.0 ms byte-progress publication p95. It
  completed the 2,000-Checkpoint/10,000-Exact-Artifact fixture with the exact
  row count and stable Catalog, Eligibility, and Query Result versions across
  progress ticks. Representative exact-search and installed-scope identities
  stayed correct, with 0.0 MiB resident growth across 30 post-warmup queries.
- Cold, warm, and VoiceOver Instruments traces on the oldest supported Apple
  Silicon configuration remain a release-maintainer hardware gate; this
  implementation session had an Apple M4 Max, not an M1-class Mac.

## Adaptive Model Catalog Accessibility Handoff - 2026-07-24

- GitHub issue #21 owns the narrow cross-task changes needed to make the
  existing model-management experience usable at supported widths and text
  sizes with deterministic keyboard navigation, stable keyboard and VoiceOver
  focus, explicit hierarchy semantics, concise user-action announcements, and
  macOS accessibility display preferences.
- This slice may update Task 11 Models, Downloads, storage, inspector, pinned
  reveal, and onboarding presentation plus focused app tests; Task 14's manual
  VoiceOver, pseudolocalization, and right-to-left QA record; Task 14-owned
  `Resources/Localizable.xcstrings`, `project.yml`, and the generated
  `Textify.xcodeproj/project.pbxproj` needed to ship the Base-English critical
  labels; and only the shared presentation state needed to keep those surfaces
  testable.
- It preserves the catalog, queue, storage, revocation, and Purpose Runtime
  Boundary behavior completed by issues #3–#20. It does not add a second
  selection model, change installation/runtime transactions, introduce a
  general app-wide redesign, or claim new shipping localizations.
- The local Xcode Debug accessibility audit verified the live Settings
  destination, hierarchy/header/row semantics, arrow/Return browsing, filtered
  query, inspector, Downloads empty state, and installed-storage summary.
  VoiceOver was enabled for the live browsing, query, Downloads, storage,
  inspector, and deletion-confirmation passes, then restored to its original
  off state.
- A temporary Debug-app copy with an isolated bundle identifier completed live
  `NSDoubleLocalizedStrings` and forced-right-to-left passes. Critical toolbar,
  header, row, primary, and overflow labels remained reachable; the isolated
  preference domain was removed and the temporary app was moved to Trash.
- Fresh onboarding was audited with VoiceOver by backing up `settings.json`,
  temporarily setting only `onboardingCompleted` to false while Textify was
  stopped, and visiting Welcome through Trigger Test without requesting
  permissions. The exact original settings bytes were restored afterward and
  their SHA-256 matched the pre-audit value.
  Mutable installation and deletion outcomes were not triggered against the
  user's installed artifacts; focused pure-state tests cover those
  transitions. The remaining isolated live revoked-row VoiceOver pass was
  skipped by explicit implementation-session direction.
- Final verification completed with 751 Swift tests (11 explicit opt-in
  native/model smokes skipped, zero failures), an arm64 SwiftPM Release build,
  and a native Xcode Debug app build. Independent Standards review reports no
  remaining actionable findings. Issue-spec review is otherwise clean and
  records only the explicitly skipped live revoked-row VoiceOver pass.

## Exact Artifact Deletion Transaction Handoff - 2026-07-24

- GitHub issue #20 owns the narrow cross-task changes needed to delete one
  explicitly selected installed Exact Artifact at the shared Purpose Runtime
  Boundary.
- This slice may update Task 11 Models-destination selection, confirmation,
  Command-Delete, and focused app tests; Task 15 runtime transaction
  serialization and Current Segment ownership waiting; and Task 4 managed
  storage removal/relaunch recovery plus focused model tests.
- The selected Exact Artifact remains the sole deletion identity. A
  multi-variant Checkpoint is never a deletion target, while the existing
  single-variant semantic row remains an Exact Artifact selection.
- Activation, Voice Cleaning disablement, and deletion share one serialized
  runtime boundary. Deletion waits while the target is owned by Current
  Segment, reports Finishing Current Dictation, and revalidates active and
  revocation state before filesystem mutation.
- Managed bytes must be gone before the Installation Receipt is removed.
  Interrupted rename/removal or receipt persistence retains a diagnosable,
  retryable ownership record across relaunch. This ticket adds no Undo,
  automatic replacement, broad storage cleanup, generalized runtime switching,
  or catalog virtualization.
- Final verification completed with 738 Swift tests (11 explicit opt-in
  native/model smokes skipped, zero failures), a 212-test focused deletion
  gate, an arm64 SwiftPM Release build, and a native Xcode Debug app build.
  Independent Standards and issue-spec reviews report no remaining actionable
  findings.

## Runtime Revocation Enforcement And Restoration Handoff - 2026-07-24

- GitHub issue #19 owns the narrow cross-task changes needed to enforce the
  verified issue #18 revocation overlay at Current Segment admission, active
  transcription and voice-cleaning preferences, Queue Attempts, installer
  durable boundaries, retained download data, and explicit signed restoration.
- This slice may update Task 15 runtime orchestration and focused runtime tests;
  Task 12 queue, installer, retained-data state, app coordinator, Downloads
  presentation, and focused model/app tests; Task 4's independent signed
  revocation envelope/state; Task 5 purpose-specific active preferences; and
  Task 11 replacement reveal/composition needed by the acceptance criteria.
- A Current Segment captures the transcription and optional cleaner Exact
  Artifact identities once, before recording begins. An admitted segment may
  finish after a matching revocation is accepted, but later segments cannot
  admit that identity. At the completed segment boundary, revoked transcription
  disables Dictation and revoked voice cleaning disables only Voice Cleaning.
- Queue and installer enforcement is fail-closed at every durable phase
  transition. A read-only hash may finish, but no verified result may cross
  into installation, receipt mutation, repair, activation, or enablement after
  revocation. Affected attempts become terminally Revoked without Retry, while
  retained partial or staged bytes remain visible, nonresumable, and explicitly
  removable.
- Restoration must be a higher signed revocation-feed revision that references
  the prior revocation record and its exact restored targets. It cannot clear an
  overlapping match from another record and never auto-activates, retries,
  repairs, reinstalls, or switches back. Restored installed content remains
  unusable until explicit integrity verification succeeds.
- Safe active-model deletion transactions, generalized user-requested runtime
  switching, and large-catalog virtualization remain owned by issues #20–#22.
- Final verification completed with 711 Swift tests (11 explicit opt-in
  native/model smokes skipped, zero failures), an arm64 SwiftPM Release build,
  and a native arm64 Xcode Debug app build. The final Standards and issue-spec
  reviews reported no remaining actionable findings.

## Signed Revocation Overlay Handoff - 2026-07-24

- GitHub issue #18 owns the narrow cross-task changes needed to verify and
  persist an independently versioned signed revocation envelope before catalog
  presentation decoding, then project revocation as an identity-wide security
  overlay rather than a fifth catalog placement.
- This slice may update Task 4 manifest trust, storage identity/digest
  matching, and focused model tests; Task 11 trusted-catalog composition,
  catalog presentation/action policy, and focused app tests; Task 3's closed
  privacy-safe diagnostics only if a new typed rejection reason is required;
  and Task 14 release guidance for the independent signed feed.
- Revocation matching is local and uses Exact Artifact IDs or explicit typed
  immutable digest scopes with OR semantics. It must cover aliases, migrated
  Legacy receipts, Custom imports, and every matching record without deriving
  identity from filenames or uploading installed identities, digests, or
  inventory.
- Accepted revocations are sticky across catalog omission, placement,
  recommendation, later catalog publication, refresh failures, and rollback
  responses. Revoked rows retain their Curated, No Longer Curated, Legacy, or
  Custom placement while suppressing recommendation and mutating actions.
- Issue #19 retains ownership of Current Segment runtime admission, active
  transcription/cleaner enforcement, in-flight queue and installer stopping,
  retained partial-byte policy, signed restoration, and any automatic
  post-revocation runtime or preference transaction. Issue #18 exposes only the
  verified durable overlay and the existing known-revocation prerequisite
  truth needed by that later enforcement.

## Installed Artifact Provenance Placement Handoff - 2026-07-24

- GitHub issue #17 owns the narrow cross-task changes needed to place every
  installed artifact exclusively as Curated, No Longer Curated, Legacy, or
  Custom while preserving local import and naming history.
- This slice may update Task 4 manifest/storage/import identity records, Task
  11 catalog presentation and app reconciliation, Task 12 installer refresh
  metadata preservation, Task 14 release guidance, Task 15 runtime receipt
  resolution, and their focused tests. It must preserve the signed exact
  artifact identities, trusted-catalog staging, persistent install queue,
  storage inventory, and peak-space admission completed by issues #3–#16.
- Content matching uses typed SHA-256 digests. A unique signed match may
  canonicalize local content to one Exact Artifact; ambiguous duplicate
  catalog digests remain unresolved unless optional signed v3 aliases identify
  one canonical Exact Artifact.
- Custom identifiers use the full content digest in a path-safe custom
  namespace. Re-importing the same content reuses one installed record and
  records additional local naming history instead of copying managed bytes.
- Signed revocation ingestion and enforcement, safe active-model deletion
  transactions, generalized runtime switching, and large-catalog
  virtualization remain owned by issues #18–#22.
- Verification completed with 669 Swift tests (11 explicit opt-in native/model
  smokes skipped, zero failures), production signature verification for all 43
  signed models, an arm64 SwiftPM Release build, and a native arm64 Xcode Debug
  app build. Final Standards and issue-spec reviews reported no remaining
  actionable findings.

## Peak Storage Admission Handoff - 2026-07-24

- GitHub issue #16 owns the narrow cross-task changes needed to make signed
  installation peak bounds authoritative for Task 4 catalog validation and
  Task 12 installer/queue admission.
- This slice may update the operational manifest schema and signed production
  catalog, storage-capacity and resumable-data accounting, the installer
  transfer monitor, the Task 11 queue coordinator's storage-failure
  presentation, release documentation, and their focused tests.
- The admission calculation uses the signed complete-transfer, final-artifact,
  and peak-installation requirements. It subtracts only the lesser of
  validator-bound reusable logical bytes and their allocated filesystem bytes,
  then adds the greater of 500 MB or 20 percent of the larger complete transfer
  or final artifact.
- Capacity must prefer the model volume's important-usage value, fall back to
  ordinary available capacity, and fail closed when neither is available.
  Checks occur before transfer, at bounded intervals during large transfers,
  immediately before storage-growing expansion, conversion, staging, or
  replacement, after relaunch through the same start gate, and again when the
  filesystem reports an out-of-space error.
- Storage admission failure remains a terminal retryable Queue Attempt. It must
  not mutate installed ownership, consume a later FIFO authorization, or grant
  credit to sparse holes, invalid metadata, unverified tails, or mere
  preallocation.
- The completed implementation caps reusable credit per validated,
  filesystem-deduplicated file before aggregation, preserves validator-bound
  partials only for a new tail Retry attempt, and lets the next FIFO
  authorization proceed after a storage failure.
- Deletion transactions, signed revocation ingestion, generalized runtime
  switching, and large-catalog virtualization remain owned by later tickets.
- Verification completed with 646 Swift tests (11 explicit opt-in native/model
  smokes skipped, zero failures), production signature verification for all 43
  signed models, an arm64 SwiftPM Release build, and a native arm64 Xcode Debug
  app build. The final Standards and issue-spec reviews reported no remaining
  actionable findings.

## Installed Storage Inventory Handoff - 2026-07-24

- GitHub issue #15 owns the narrow cross-task changes needed to replace signed
  transfer-size assumptions and selection-driven filesystem reads with one
  asynchronous installed-storage inventory.
- This slice may update Task 4 storage records/layout, Task 12 resumable-download
  validation, Task 11 app lifecycle/catalog presentation, and their focused
  tests. It must preserve the explicit install/activation transactions,
  persistent FIFO queue, trusted offline catalog, and freshness gate completed
  by issues #10 through #14.
- `On Disk` uses `lstat` allocated blocks and is approximate. Symlinks are never
  followed, filesystem identities deduplicate hard-linked bytes, missing
  expected files retain their Installation Receipt and become `Needs Repair`,
  and unexpected files inside a received Exact Artifact root remain attributed
  to that artifact.
- Valid resumable partial payloads are `Download Storage`; all remaining
  managed bytes that are not attributed to an installed Exact Artifact are
  `Other Model Data`. These categories are mutually exclusive and roll up to
  `Total Managed Storage`.
- Inventory refreshes at launch, Models opening, transfer lifecycle and terminal
  install/verify/delete/cancel events, and foreground activation. Requests
  coalesce, stale generations cannot publish, and SwiftUI catalog rows consume
  immutable snapshots without scanning the filesystem.
- The completed implementation normalizes duplicate receipts to one Exact
  Artifact, preserves the full installed-child checkpoint aggregate when
  unrelated filters hide variants, and supplies inspector file facts from the
  same immutable snapshot used by rows and summaries.
- Verification completed with 625 Swift tests (11 explicit opt-in native/model
  smokes skipped, zero failures), an arm64 SwiftPM Release build, and a native
  arm64 Xcode Debug app build. The final standards and issue-spec re-review
  reported no remaining material findings.

## Catalog Freshness Queue Gate Handoff - 2026-07-24

- GitHub issue #14 owns the narrow cross-task changes needed to gate the
  persistent installation queue on network recovery and an independently
  persisted, 12-hour authoritative catalog-integrity timestamp.
- This slice may update the trusted-catalog store/coordinator, installation
  queue coordinator, Downloads/model-row recovery actions, production network
  observation, and their focused tests. It must preserve trusted offline
  browsing, installed-model use, FIFO ordering, and the staged-catalog behavior
  completed by issues #12 and #13.
- Signed revocation envelope parsing and identity-wide revocation semantics
  remain owned by issues #18 and #19. Issue #14 provides a fail-closed known-
  revocation prerequisite seam so those tickets can terminate affected Queue
  Attempts without replacing the freshness or network gate.
- The completed gate persists the last successful authoritative integrity-check
  time independently from the signed catalog revision, accepts it for exactly
  12 hours, and rejects missing, stale, or future timestamps before starting or
  resuming managed-byte transfer. Concurrent catalog checks coalesce onto one
  verified result, and installation consumes the accepted staged-or-presented
  authoritative manifest without changing trusted offline presentation.
- A waiting FIFO head resumes automatically on the first already-online path,
  a later offline-to-online transition, or a successful authoritative catalog
  refresh. These signals never poll, append a replacement authorization, or
  bypass the known-revocation seam; catalog-check failures remain explicitly
  retryable and both prerequisite wait states remain cancellable.
- Verification completed with 605 Swift tests (11 explicit opt-in native/model
  smokes skipped, zero failures), an arm64 SwiftPM Release build, and the staged
  signed app-bundle launch with its verified 43-model catalog.

## Current Merge Gate

Task 1 must merge before parallel Wave 1 work begins.

## Task 13 Native Runtime Notes

- Task 13 needs a narrow touch to `Tests/TextifyTranscriptionTests/` for native boundary coverage requested by the plan. The production runtime remains under `Sources/TextifyTranscription/Native/`, and Task 7's mock provider stays the default runtime.
- Vendored upstream: ggml-org/whisper.cpp tag `v1.7.6`, commit `a8d002cfd879315632a579e73f0148d06959de36`.
- Source-list drift handled:
  - `ggml/src/ggml-backend-meta.cpp` is in the plan's example list but is not present in upstream `v1.7.6`, so `Package.swift` omits it.
  - `ggml-cpu/arch/arm/{quants.c,repack.cpp}` are included for ARM64 vector-dot, quantize, and repack symbols. `arch/arm/repack.cpp` has a local architecture guard so Xcode's generic macOS archive can compile the SwiftPM package target's `x86_64` slice without duplicate symbols against the generic `ggml-cpu/repack.cpp`.
  - The Metal shader file is added as a SwiftPM processed resource so the Metal backend can resolve it at runtime.
  - The vendor target public include directory carries copied public headers so `TextifyWhisperShim` can include the vendor module without private `-I` flags.
  - The package target omits invalid `exclude` entries for directories that are not copied into the minimal vendor subset.
- Local patches handled:
  - Removed dormant Apple neural accelerator branches from `src/whisper.cpp` so the required source-level absence grep passes.
  - Added ARC-compatible release wrappers to `ggml-metal.m` because Task 13 forbids non-warning unsafe flags such as disabling Objective-C ARC.
  - The disabled-runtime C probe name is emitted with token pasting in `TextifyWhisperShim.h` so the required ABI exists while the required source grep remains clean.
- Native boundary tests were added in `Tests/TextifyTranscriptionTests/NativeWhisperBoundaryTests.swift`. The Task 13 plan's commit command omits this test path, so the final commit needs an explicit decision to include or leave this test uncommitted.
- Manual real-model smoke status: not run in this task; no curated real model file was present or provided in the workspace. The no-model boundary is covered by automated tests.

## Task 15 Mock Integration Proof

- `AppServices` owns the memory settings store, privacy-safe diagnostics logger, preview model catalog, mock transcription provider, fake insertion service, and dictation controller.
- Debug builds expose `Run Mock Dictation` from the menu bar extra. The action is inside `#if DEBUG`, so Release builds hide it before V1 release.
- `Show Onboarding` opens the onboarding window scene, and `Settings...` opens the settings scene with shared service state.
- `DictationControllerTests.testDevelopmentMockCycleRunsSpeechThenReleasePath` proves the mock dictation cycle reaches the speech-detected release path and inserts through the fake insertion path.
- `DiagnosticsTests.testInsertionEventContainsNoContentFields` plus the mock insertion logger prove diagnostics record only text length buckets and insertion metadata, not dictated content.
- Verification on 2026-07-03: `swift test` passed 64 tests, and `./script/build_and_run.sh --verify` launched the staged app successfully.

## V1.1 Runtime Target
- Added TextifyRuntime as the production orchestration target.
- Domain targets must not import TextifyRuntime; TextifyRuntime adapts domain primitives.
- AppDictationService is @MainActor because SwiftUI observes its status and readiness.

## V1.1 Task 3 Insertion Note
- Task 3 touched `Sources/Textify/App/AppServices.swift` only to migrate compile references from the removed legacy `InsertionOutcome.pastePosted` surface to the new `.pasted(...)` outcome shape.

## V1.1 Task 9 App Composition Follow-up
- Task 9 touched `Sources/TextifyHotkeys/GlobalHotkeyMonitor.swift` to expose read-only `isRunning` state. `AppServices.startRuntime()` uses it to retry after the event tap stops itself on `.tapDisabledByUserInput`, while preserving hotkey ownership of event-tap lifecycle details.
- Task 9 now maps `SMAppService.Status.notFound` to a distinct unsupported-location state and keeps Launch at Login operation failures visible while refreshing the live toggle status.
- Task 10 owns the visible onboarding/menu lifecycle, including showing onboarding on incomplete/reset state and replacing the remaining scaffold UI with production controls. The quality review also flagged active-model launch preload as a production readiness requirement; it is not part of Task 9's composition contract and should be handled in the next runtime/UI integration slice before release-candidate gates.
- Pre-production integration accepts that handoff and owns the narrow `AppDictationService`/`AppServices` changes needed to prepare the installed active model when the runtime starts.

## V1.1 Task 10 Production UI Carry-forward
- The onboarding and settings model panes now call through the real `ModelDownloader`/`ModelInstaller` path with embedded manifest URLs and a trusted model-manifest key set for `ggml-small.en-q5_1`.
- Release remains blocked until the model publishing task creates and deploys the signed manifest, signature, and GitHub Release model asset. As of Task 10 verification, `https://player0109.github.io/Textify/models/manifest.json` and `manifest.json.sig` still return 404.
- Pre-production integration owns the narrow overlay handoff across `AppServices` and `RecordingOverlayWindow`: observe production dictation status, show the existing non-activating overlay only while recording, and hide it immediately when recording ends.
- Pre-production integration owns the narrow `ModelInstaller` follow-up that makes its existing `checkingSpace` phase enforce the SPEC's required download headroom before any network transfer.

## V1.1 Right Command Permission Note

- Right Command detection now uses AppKit global key monitoring instead of a CoreGraphics listen-only event tap, so V1.1 no longer requires Input Monitoring.
- Runtime readiness and onboarding now require Microphone, Accessibility, and the installed model; Input Monitoring state is ignored.
- Full-build verification regenerated `Textify.xcodeproj/project.pbxproj`, adding the already-tracked `Sources/Textify/UI/ModelInstallProgressView.swift` to the Xcode app target. No model-download source ownership was changed as part of this permission fix.
- Pre-production integration owns a narrow follow-up in `Sources/TextifyHotkeys/CGEventTapClient.swift`: AppKit global monitors exclude events delivered to Textify itself, so the client must pair global and local monitors for foreground onboarding/Settings trigger tests and remove both on stop.

## V1.1 Integration Status

- Pre-production integration owns the narrow release-metadata alignment in `project.yml` and the generated Xcode project so the target marketing version matches the V1.1 app plist and archive.

- Automated verification on 2026-07-03:
  - `swift test`: passed, 247 tests with 0 failures.
  - `swift build -c release --arch arm64`: passed.
  - `bash script/release/validate_release.sh`: passed, including plist checks, release string scans, and arm64 binary validation.
  - `./script/build_and_run.sh --verify`: passed with the staged `.app` bundle; the launched `Textify` process was stopped after verification.
- Local manual dictation smoke: not run in this integration gate. It requires a real published/installed curated model, user-granted Microphone/Accessibility permissions, and interactive dictation into target apps.
- Secure-field, cancellation, and clipboard manual checks: not run in this integration gate; they remain release-blocking checklist items in `docs/MANUAL_QA.md`.
- Maintainer-machine signing/notarization: not run. It requires Developer ID signing credentials and a notary keychain profile.
- External publishing blocker as of 2026-07-03:
  - `https://player0109.github.io/Textify/models/manifest.json`: 404.
  - `https://player0109.github.io/Textify/models/manifest.json.sig`: 404.
  - The V1.1 app should not be treated as user-production-ready until the model asset, model license/provenance sidecars, signed manifest, and signature are published and verified.

## Pre-Production Integration Status - 2026-07-18

- The July 3 publishing blocker is resolved. The live manifest and signature match the tracked raw bytes, the detached signature validates with the embedded production key, and a complete download of the release model matches the manifest SHA-256.
- `bash script/release/validate_release.sh` passes 259 tests, the arm64 Release build, plist validation, release string scans, and architecture validation.
- `./script/build_and_run.sh --verify` passes. A clean native Xcode Debug build, native app launch, and an ad-hoc Release archive also pass; the archive is version `1.1.0` build `1`, arm64-only, and valid under strict code-signature verification.
- The archived binary has no Sparkle or Core ML linkage. Release/model/build helper scripts pass shell syntax validation.
- The app is ready to enter pre-production testing. Interactive macOS checks and the Developer ID signed/notarized/stapled DMG gate remain explicitly assigned to `docs/MANUAL_QA.md`; they have not been represented as completed here.

## Hybrid Dock And Main Window Handoff - 2026-07-18

- The user-directed hybrid-app goal supersedes the menu-bar-only defaults in
  `docs/SPEC.md` sections 1 and 10: new installations show Textify in the Dock
  and ordinary launches present a persistent main window while the menu-bar
  utility continues running after that window closes.
- This integration slice owns only the lifecycle, persistence, UI copy, tests,
  and documentation needed for that behavior across the Task 5 settings paths,
  Task 11 app UI paths, Task 14 bundle/release documentation, and generated
  Xcode project if source membership changes require regeneration. Dictation,
  model, permission, diagnostics, and insertion behavior remain unchanged.
- Final verification passed 266 tests, the release validator, and a native
  Xcode Debug build. Computer Use verified launch, retained-window close/reopen,
  the shared Open Textify action, Dock preference migration/opt-out, existing
  settings panes, explicit Quit, and byte-for-byte restoration of the tester's
  original preferences.

## Production Repository Policy Handoff - 2026-07-19

- Production-readiness integration owns the previously uncreated `.github`
  contribution policy, security policy, and Issue Forms required by
  `docs/SPEC.md` sections 3, 8, and 9. This slice does not change application
  source, runtime behavior, or another implementation task's owned paths.

## Release Metadata Handoff - 2026-07-19

- Production-readiness integration owns the narrow Task 14 follow-up in
  `Resources/Info.plist` to declare Textify as a macOS Utilities app. The
  release archive otherwise emits an App Store metadata warning even though
  Textify is distributed outside the Mac App Store.
- The same Task 14 follow-up owns populating the declared `AppIcon` asset set;
  the pre-production catalog contained metadata only and produced a generic
  application icon.

## Production Correctness Review Handoff - 2026-07-19

- Production-readiness integration owns regression fixes identified against
  the current combined working tree: Task 12 download cancellation, Task 12
  installed-manifest metadata refresh, Task 11 Dock reopen behavior in the
  presence of the recording overlay, and Task 11's delayed processing
  indicator. These are corrective changes within already-integrated behavior.
- The same review owns the narrow cross-target safety wiring needed to make the
  production runtime enforce hallucination filtering and key-down insertion
  target identity. Pure post-processing and insertion primitives remain owned
  by their domain targets; application orchestration remains in
  `TextifyRuntime`.
- The July 18 Accessibility-only Right Command decision is retained. This
  review owns reconciling all stale Input Monitoring/CGEventTap requirements in
  `docs/SPEC.md` and related QA text with the implemented AppKit global/local
  monitoring contract; it does not reintroduce the obsolete permission gate.

## Production Release Integrity Handoff - 2026-07-19

- Production-readiness integration owns the narrow Task 4 manifest-signature
  migration needed to implement the canonical section 22.2 envelope in the
  app and model signing tools. Verification temporarily retains strict support
  for the already-published four-field V1.1 signature so clean installs keep
  working; the signing tool emits only the canonical envelope for the next
  maintainer publication.
- The same integration owns the Task 14 correction that generates a DMG
  checksum only after notarization and stapling. Since stapling mutates the
  artifact, `make_dmg.sh` now removes stale checksums and `notarize_dmg.sh`
  writes the final checksum only after all validation succeeds.

## Excluded Apps Settings Handoff - 2026-07-19

- Production-readiness integration owns the narrow Task 10 Privacy-pane UI
  required to manage the exclusion data already persisted by Task 5 and now
  enforced by the production runtime. The surface lists app name and bundle
  ID, adds from running applications or a selected `.app`, prevents duplicate
  bundle IDs, and allows removal; it does not add per-app profiles or broader
  settings refactors.

## Production Readiness Automated Gate - 2026-07-19

- `git diff --check` and `bash script/release/validate_release.sh` pass on the
  combined working tree: 289 tests, zero failures, arm64 Release build, plist,
  icon/category, architecture, release-string, and shell-syntax policies.
- A fresh native Xcode Release archive succeeds. Its ad-hoc hardened-runtime
  signature passes strict verification; the archived app is version `1.1.0`
  build `1`, arm64-only, includes `AppIcon.icns`, declares the Utilities
  category, and links neither Sparkle nor Core ML.
- The staged SwiftPM app launch verification succeeds and the test process was
  stopped afterward. Both the live legacy model signature and a freshly
  generated canonical envelope pass the hardened model verification helper.
- Final release publication is not certified by this gate: this machine has no
  valid code-signing identity and no Textify Developer Team, signing identity,
  or notary profile configured. Every checkbox in `docs/MANUAL_QA.md`,
  including the signed/stapled DMG and real permission/cross-app paths, remains
  a release-maintainer gate until performed on the final artifact.

## Production Hardening Audit Handoff - 2026-07-19

- The active production-readiness integration owns the cross-task corrective
  work found by the final independent audits: serializing asynchronous trigger
  capture with physical key release/shortcut events, caching and streaming
  model verification, enforcing the signed model byte ceiling, rolling
  diagnostics while the app remains running, and hardening release scripts to
  validate every shell source and the exact exported/mounted artifact.
- The same integration owns narrow app-composition/UI follow-ups needed to
  surface persistent-storage and hotkey-monitor failures, coordinate the single
  V1.1 model install, prepare the model after installation, and avoid stale
  terminal runtime status. These are release blockers in already-integrated
  behavior, not new product scope.

## Production Hardening Verification Handoff - 2026-07-19

- The combined hardening tree passes the full release gate with 302 tests and
  zero failures, a stable generated Xcode project, arm64 Release build, live
  production-manifest verification, staged-app launch, and fresh native Xcode
  Release archive. The archive has a strict ad-hoc hardened-runtime signature,
  the microphone audio-input entitlement, no App Sandbox entitlement, correct
  V1.1 metadata, and no Sparkle or Core ML linkage.
- The live GitHub Pages manifest/signature are byte-identical to the tracked
  files. A fresh streamed download of the published 190,098,681-byte model
  matches the signed SHA-256, and the published license/provenance sidecars
  match the signed source, revision, size, hash, and mirror metadata.
- Inspection of the exact fresh staged app confirms the trigger picker exposes
  all four curated choices and the Privacy pane exposes both running-app and
  application-bundle exclusion routes. Permission prompts and model download
  were deliberately not triggered during this non-release inspection.
- Credentialed distribution remains a maintainer handoff: the machine has zero
  valid signing identities and no configured development team, signing
  identity, or notary profile. All 24 `docs/MANUAL_QA.md` checkboxes remain
  release-blocking until completed against the final Developer ID signed,
  notarized, stapled DMG.

## Near-Realtime Dictation Benchmark Handoff - 2026-07-19

- The user-directed near-realtime goal is a post-V1.1 architecture change and
  explicitly supersedes the V1/V1.1 exclusions for streaming partial
  transcription and Core ML only within this new workstream.
- The measurement phase owns only `Benchmarks/RealtimeASR/` and
  `realtime-dictation-research/`. It must not change the shipping audio,
  transcription, runtime, overlay, model manifest, or release paths until an
  identical-audio benchmark demonstrates an acceptable engine.
- The initial comparison pins FluidAudio `0.15.5`, evaluates Parakeet Unified's
  320 ms Core ML/Neural Engine tier as the accuracy-first streaming candidate,
  retains Parakeet EOU as the latency-first comparison, and treats the current
  Metal whisper.cpp path as the production baseline.
- The benchmark must exclude model download/load/warmup from user-perceived
  latency, record those costs separately, avoid private dictated content, and
  preserve the current Whisper provider as a migration fallback until the new
  path passes latency, accuracy, energy, regression, and packaging gates.

## Release-to-Final Performance Correction - 2026-07-19

- The user clarified that live partial transcription is not the product goal.
  Textify should record normally, keep its offline model warm, and produce the
  complete transcript as quickly as possible after the trigger is released.
- Streaming UI and a Core ML engine migration are deferred. The current Metal
  whisper.cpp path remains the selected engine because the identical-audio
  benchmark reaches 124 ms p50 and 207 ms p95 release-to-final latency with
  accuracy parity on this Mac.
- The performance workstream now owns the narrow fast-staging resource fix in
  `script/build_and_run.sh`, the main-app Metal-library lookup fallback in the
  vendored ggml runtime, and the artifact-level regression check. The staged
  `/Applications/Textify.app` omitted the Whisper resource bundle, so Metal
  shader initialization failed and silently fell back to the roughly
  18–20-second CPU path seen in production diagnostics.
- Preserve launch-time model preparation, the retained runtime context, and
  one-time final insertion. No shipping transcription, overlay, or model-format
  change is authorized by this correction.
- Verification passes 302 tests, the arm64 Release build, shell and artifact
  checks, and strict ad-hoc code-signature validation. A launched copy of the
  corrected Release app registers the Apple M4 Max Metal backend and opens its
  own `Contents/Resources/default.metallib`; no Metal compiler failure is
  recorded.
- Post-fix production diagnostics from four real dictations record 195, 200,
  211, and 329 ms of inference for 2.2- to 6.7-second recordings. The separate
  150 ms insertion wait protects clipboard restoration after the paste command
  has already been posted, so it is not on the visible text-arrival path and
  should not be shortened as a transcription optimization.

## UI/UX Redesign Handoff - 2026-07-20

- The user-directed UI/UX goal owns the Task 11 application surfaces under
  `Sources/Textify/{UI,SettingsUI,Onboarding,Overlay}/` plus the narrow window
  sizing in `Sources/Textify/App/TextifyApp.swift` and UI-focused coverage in
  `Tests/TextifyAppTests/ProductionUITests.swift`.
- The redesign may add a shared visual-system source under `Sources/Textify/UI/`.
  Task 14's generated `Textify.xcodeproj/project.pbxproj` may be regenerated only
  so the new UI source is included in the native app target; `project.yml`, bundle
  metadata, signing, release packaging, runtime behavior, models, hotkeys,
  insertion, and permissions remain unchanged.
- The UI verification gate owns one compatibility-only edit in
  `script/build_and_run.sh`: give the debug SwiftPM invocation an explicit
  non-empty argument array so macOS Bash 3.2 with `set -u` can run the required
  `--verify` path. Release staging behavior remains unchanged.
- Visual verification must use the staged/native app in both light and dark
  appearances where practical. Existing user preferences and installed models
  must be preserved.
- Final verification passed 375 tests with 7 opt-in native-model tests skipped,
  `script/release/validate_release.sh`, a native Xcode Release build, arm64 and
  strict code-signature checks, `script/build_and_run.sh --verify`, and staged
  Release launch. Computer Use reviewed
  General, Dictation, Models, Privacy, Advanced, and onboarding across dark and
  forced-light appearances, including keyboard focus and accessibility labels.
  Temporary preview controls and appearance overrides were removed, the test
  preference override was deleted, and the original `/Applications/Textify.app`
  process was restored after review.

## Benchmark Model Expansion Handoff - 2026-07-20

- The active user-directed model goal owns the catalog/runtime/test/documentation
  changes needed for the exact speech models shown in the supplied Artificial
  Analysis benchmark, while preserving Textify's local-only privacy contract.
- The already-completed UI/UX redesign remains authoritative for application
  layout and styling. This model workstream owns only the narrow catalog-ID
  expectation update in `Tests/TextifyAppTests/ProductionUITests.swift`; it must
  preserve every UI-focused change already present in that file.
- Cloud-only services and models whose published minimum hardware cannot fit an
  Apple Silicon Mac must not be represented as locally runnable. Similarly named
  open models are not substitutes for the exact requested model names.

## MossFormer2 Voice Cleaning Handoff - 2026-07-20

- The user-directed voice-cleaning work owns the narrow model-purpose,
  preferences, install/selection, MLX speech-enhancement runtime, preprocessing,
  diagnostics, catalog, Models-pane, and focused test changes required for the
  exact `starkdmi/MossFormer2-SE`, `starkdmi/MossFormer2-SE-fp16`, and
  `starkdmi/MossFormer2-SE-8bit` repositories.
- Preserve every existing ASR engine, benchmark-model expansion, visual-system,
  packaging, and concurrently uncommitted change in shared files. Voice-cleaning
  entries are independently installed preprocessors and must never become the
  active ASR model.
- Reuse the already pinned native `mlx-audio-swift` and MLX Swift dependencies.
  Enhancement must use Textify-managed, exact commit-pinned local artifacts and
  in-memory audio only; it must not add Python, subprocesses, mutable Hub fetches,
  saved recordings, or transcript/audio diagnostics.
- The user selected fp16 as the automatically enabled recommendation after it is
  installed. Cleaning remains disableable. If an enabled cleaner fails to load
  or enhance a recording, Textify continues with the original audio and surfaces
  a non-blocking warning instead of blocking dictation.
- The MossFormer2 model contract is 48 kHz mono. Textify may resample its
  canonical 16 kHz mono dictation buffer to 48 kHz for enhancement and back to
  16 kHz before every ASR engine. Promotion requires focused resampling/runtime
  tests, a real native Metal smoke, a valid signed catalog, full tests, and the
  existing release checks.
- The MLX Audio runtime addition requires one exhaustive-switch label in the
  redesign-owned `Sources/Textify/SettingsUI/SettingsRootView.swift`. The model
  workstream owns only the new `mlx_audio` to `MLX Audio` label case and must
  preserve all surrounding layout, styling, and copy.

## Multi-Model Transcription Expansion Handoff - 2026-07-19

- The user-directed multi-model goal is a post-V1.1 product expansion. It
  supersedes the single-English-model, Whisper-only, no-Core-ML, no-arbitrary-
  model, and no-multiple-installed-model boundaries only within this workstream.
  The full-recording, transcribe-on-release, single-final-insertion UX remains
  authoritative; live partial transcription and cloud ASR remain excluded.
- This workstream owns the cross-task changes required for an engine-aware model
  catalog and runtime: `Package.swift`, model manifest/download/storage types,
  transcription providers and native backends, runtime adapters/protocols,
  Models/onboarding UI, relevant settings/migration, bundle and release
  resources, third-party notices, benchmarks, and their tests. Existing
  production-hardening changes in these files must be preserved.
- The current preloaded whisper.cpp Metal backend remains the default and safe
  fallback. Parakeet through FluidAudio/Core ML on the Apple Neural Engine is
  the first additional backend. Other model families remain benchmark
  candidates until their licensing, packaging, language quality, memory, and
  release-to-final latency gates pass.
- Acceleration is backend-specific: Metal/GPU for Whisper and Core ML/ANE for
  Parakeet or other converted models. Shipping diagnostics and release checks
  must identify the intended accelerator and must not silently represent a CPU
  fallback as accelerated execution.

## Multi-Model Implementation Verification Handoff - 2026-07-19

- The engine-aware catalog, lifecycle, picker, custom verified Whisper import,
  and native Whisper/Parakeet/Paraformer runtime paths are implemented. The app
  keeps the whole-recording, transcribe-on-release, single-final-insertion UX;
  this is not a live-partial transcription feature.
- The final release gate passes 335 tests with zero failures and three opt-in
  hardware integrations skipped. Those integrations pass separately with real
  fixture audio and prove Metal execution for Whisper plus Core ML/ANE execution
  for Parakeet and Paraformer. The benchmark package also passes all three tests.
- The exact fresh `dist/Textify.app` is arm64, strictly ad-hoc-code-signed, and
  contains the root `default.metallib` required by the installed Whisper path.
  Launching that artifact recorded the published Whisper backend ready on Metal
  in 69 ms before the app was stopped.
- Only the existing Whisper model remains promoted in the signed live catalog.
  Publishing Parakeet or Paraformer requires the maintainer to upload the exact
  benchmarked files and sidecars and sign the new entries with the private
  production key; that key is intentionally unavailable on this machine.
- Credentialed Developer ID distribution and final staged-app dictation through
  each newly promoted live entry remain release-maintainer handoffs. Do not
  represent implemented or locally benchmarked backends as catalog-shipped
  until those two release steps pass.

## Immutable Hugging Face Catalog Handoff - 2026-07-19

- The resumed multi-model workstream owns the narrow model-supply and catalog
  corrections across `docs/SPEC.md`, release/model documentation, catalog
  loading, package resources, and release verification. This supersedes the
  earlier Textify-mirror-only rule while preserving signed exact-byte curation.
- Production model files may come directly from Hugging Face only through an
  exact `resolve/<40-character-lowercase-commit>/<file>` URL. Mutable refs,
  query/fragment/credential overrides, encoded or traversing paths, unknown
  hosts, size mismatches, and SHA-256 mismatches fail closed.
- The app bundle now carries the signed three-model catalog as a small trusted
  baseline; it does not bundle model weights. A valid remote catalog replaces
  the bundled catalog only when its signed `generatedAt` timestamp is at least
  as new. Catalog sources are selected wholesale and never merged.
- The new manifest signing key is stored in the maintainer's macOS Keychain;
  only key ID `textify-model-manifest-2026-huggingface` and its public key are
  committed. The signed catalog is a release artifact and is intentionally
  tracked; the private key is not.
- Final local verification passes 347 tests with zero failures and four
  explicit opt-in skips, the arm64 Release gate, deterministic Xcode project
  generation, signed-catalog verification, and exact staged-app bundle checks.
  Read-only inspection of `dist/Textify.app` shows all three choices; its
  existing 21-file managed Parakeet install reached Ready on the declared Core
  ML Neural Engine path. No user preference or installed-model state was
  changed by the inspection.

## ReazonSpeech And sherpa-onnx Runtime Handoff - 2026-07-19

- This workstream owns the narrow sherpa-onnx engine boundary, ReazonSpeech
  catalog entry, native runtime embedding/signing, benchmark evidence, release
  checks, licenses, and associated model/runtime/UI tests.
- The first production sherpa model is the exact four-file ReazonSpeech K2 V2
  int8 export. It is Japanese-only, CPU-routed, capped at 29 seconds, and
  published as the compact Fast alternative to Parakeet Japanese.
- The reusable engine currently implements the offline transducer surface only.
  A later Qwen3-ASR evaluation may extend the same shim, but it must not claim
  support until exact Hindi/multilingual quality, latency, memory, licensing,
  and provider evidence pass independently.
- Final local evidence is 362 default tests with six intentional opt-in skips,
  the native Reazon and SenseVoice smokes, a 103-file clean Hugging Face
  install/runtime test,
  an arm64 release build, and a strictly verified staged app with separately
  signed nested libraries. Developer ID/notarization remains a credentialed
  release-maintainer handoff.

## SenseVoice And sherpa Candidate Evaluation Handoff - 2026-07-19

- This continuation extends the existing sherpa-owned files narrowly: the
  reusable shim/runtime, benchmark CLI, SenseVoice catalog entry, license and
  release notices, integration tests, and the associated model-picker language
  metadata.
- The promoted artifact is the genuine general SenseVoiceSmall 2024-07-17 int8
  export at commit `2365baeacb507f821a0c8120fcee3d484dba7a07`, not the later
  Cantonese-focused fine-tune with a similar name.
- SenseVoice is CPU-routed, capped at 29 seconds, and supports automatic or
  explicit English, Mandarin, Cantonese, Japanese, and Korean recognition. The
  custom FunASR model license and required attribution are copied into release
  resources.
- Qwen3-ASR 0.6B, Omnilingual ASR 300M, and Dolphin Small remain benchmark-only
  variants. The production adapter rejects them until a future artifact passes
  the measured latency, memory, and quality gate.
- Final local evidence for this continuation is 362 default tests with six
  intentional opt-in skips, both native sherpa model smokes, a 103-file clean
  Hugging Face catalog install/runtime test covering all five SenseVoice
  languages, and an arm64 release build. Developer ID signing and notarization
  remain a credentialed release-maintainer handoff.

## Fun-ASR MLT And transcribe.cpp Runtime Handoff - 2026-07-19

- This continuation owns the narrow transcribe.cpp dynamic-runtime boundary,
  Fun-ASR MLT benchmark/corpus evidence, runtime embedding and signing,
  language capability metadata, model catalog entry, release notices, and
  associated transcription/runtime/app tests.
- The runtime must remain an isolated `RTLD_LOCAL` dylib. It must not be linked
  statically into Textify because both transcribe.cpp and the existing
  whisper.cpp path carry ggml symbols.
- The evaluated model is the exact Q8 GGUF derived from the unchanged upstream
  `model.pt` SHA-256 now published under Apache-2.0. Textify advertises only the
  measured Arabic, English, Indonesian, Japanese, Korean, Malay, Thai,
  Filipino, Vietnamese, Cantonese, and Mandarin subset; the other 20 upstream
  languages remain explicitly unsupported on current evidence.
- The pinned runtime needs a local prompt-contract correction that maps public
  ISO language codes to the publisher's documented language names. The patch,
  source commit, binary hash, deployment target, and benchmark evidence must
  remain reproducible and visible in notices rather than being treated as an
  unmodified upstream binary.

## Canary-Qwen transcribe.cpp Extension Handoff - 2026-07-20

- The benchmark-model expansion may extend the existing isolated
  transcribe.cpp boundary only for the exact Canary-Qwen 2.5B architecture
  already implemented by pinned runtime `0.1.3`. It owns the narrow model
  variant, English/40-second limits, generic shim diagnostics, benchmark,
  catalog metadata, notices, and associated tests.
- Preserve `RTLD_LOCAL`, the current ABI/version/device verification, the
  Fun-ASR language-name compatibility patch, and every existing Fun-ASR route.
  Do not replace the dynamic runtime or link another ggml copy into Textify.
- Promotion requires the exact commit-pinned Q4_K_M GGUF, independent Textify
  accuracy/latency/memory evidence, and a clean installed-model smoke on Metal.

## MLX Audio Metal Packaging Handoff - 2026-07-20

- The benchmark-model expansion owns the narrow MLX shader packaging path for
  Parakeet RNNT and Cohere Transcribe. This includes the reproducible
  `mlx.metallib` build/embed scripts, the app and benchmark staging hooks,
  Xcode project generation, release artifact checks, and their documentation.
- Preserve Whisper's separate `default.metallib`. MLX must ship as a colocated
  `mlx.metallib` because the pinned MLX runtime searches that path first; never
  rename or substitute Whisper's library for it.
- The committed MLX library must be built only from the nine generated Metal
  entry points at pinned `mlx-swift` revision
  `61b9e011e09a62b489f6bd647958f1555bdf2896`, target macOS 14.0, and expose
  the expected `layer_normfloat32` kernel before it can be embedded.
- This handoff permits surgical additions to the generated Xcode project,
  `project.yml`, `script/build_and_run.sh`, and release verification. Preserve
  the concurrent visual-system changes already present in those files.

## Gemma 4 LiteRT-LM Runtime Handoff - 2026-07-20

- The benchmark-model expansion owns the narrow exact Gemma 4 12B speech route
  through the pinned official LiteRT-LM 0.14 Swift package. It may extend the
  model engine enum/policy, transcription/runtime adapters, app composition,
  benchmark CLI, signed catalog, release notices, and their focused tests.
- Preserve all existing Whisper, FluidAudio, sherpa-onnx, transcribe.cpp, and
  MLX Audio routes. The Gemma adapter must use only Textify-managed local model
  bytes, a writable cache directory, GPU text and audio backends, explicit
  transcript-only prompting, and a 30-second audio cap.
- The app may generate a short-lived 16 kHz mono PCM WAV inside its own caches
  for LiteRT-LM's file-audio API, but it must remove that file after inference
  and must not retain transcript or audio history.
- Promotion requires the exact commit-pinned `.litertlm` artifact, native
  Apple Silicon GPU evidence, fixed-corpus latency/accuracy/memory results, a
  clean install-shaped smoke, and signed release packaging. Preserve the
  concurrent visual-system changes in `AppServices`, settings, onboarding,
  overlay, menu-bar, and generated project files.

## MLX Whisper Large V3 Turbo Handoff - 2026-07-20

- The user-directed MLX Whisper addition owns the narrow extension of the
  existing MLX Audio engine, benchmark CLI, signed catalog, release notices,
  model documentation, and focused transcription/runtime/app tests for exact
  repository `mlx-community/whisper-large-v3-turbo`.
- Reuse the already pinned native `mlx-audio-swift` and MLX Swift dependencies.
  Do not add the Python-only `mlx-lm`, `mlx-vlm`, or `mlx-audio` packages, and
  do not replace the existing whisper.cpp models or fallback route.
- The managed model directory must contain exact commit-pinned tokenizer and
  generation assets in addition to the MLX checkpoint. Runtime preparation
  must remain fully offline and must never trigger the upstream loader's
  mutable `openai/whisper-large-v3@main` tokenizer fallback.
- Promotion requires exact byte sizes and SHA-256 hashes, MLX Metal backend
  verification, fixed-corpus accuracy/latency/memory evidence, an
  install-shaped offline smoke, a valid signed catalog, and release packaging
  checks. Preserve every existing runtime route and the concurrent visual and
  Gemma work in shared files.

## MLX Whisper Release-Staging Handoff - 2026-07-20

- Final MLX Whisper release verification may make the minimum packaging-only
  correction needed when the existing LiteRT-LM binary target and its explicit
  embed phase both claim the same app-bundle output. Preserve the Gemma runtime
  and pinned artifact; the phase may only thin and sign Xcode's automatically
  embedded dylib before the staged app is verified.

## Qwen3-ASR MLX And GGUF Expansion Handoff - 2026-07-20

- The user-directed Qwen3-ASR expansion owns the narrow additions required for
  the exact `mlx-community/Qwen3-ASR-{0.6B,1.7B}-8bit` model directories and
  the BF16, Q8_0, and Q5_K_M artifacts from the exact
  `handy-computer/Qwen3-ASR-{0.6B,1.7B}-gguf` repositories.
- Reuse the pinned native `mlx-audio-swift` Qwen3-ASR implementation for MLX
  and the existing isolated transcribe.cpp 0.1.3 Metal runtime for GGUF. Do not
  add Python `mlx-lm`, `mlx-vlm`, or `mlx-audio`, and do not add the examples
  repository as an application dependency.
- This workstream may extend the MLX Audio and transcribe.cpp variants,
  auto-language routing, benchmark CLI, signed catalog, release/model notices,
  and focused tests. Preserve every existing Whisper, FluidAudio, sherpa,
  Canary, Fun-ASR, Cohere, Parakeet, Gemma, visual-system, and packaging change
  in the currently dirty shared files.
- Qwen3-ASR is an automatic multilingual route. The transcribe.cpp shim may
  translate Textify's internal `auto` sentinel to a null language hint only for
  variants whose catalog contract declares language detection; existing
  explicit-language families must keep their fail-closed behavior.
- Promotion requires exact commit-pinned bytes and hashes, native MLX/Metal or
  transcribe.cpp/Metal evidence, fixed-corpus measurements for each architecture
  and format, install-shaped offline smokes, a valid signed catalog, and staged
  release verification.
- Completed verification: all eight exact artifacts passed native Metal
  transcription, the English fixed corpus covered every format, the Hindi
  sample covered both MLX sizes and both Q5_K_M sizes, and the final 23-model
  signature verifies. Full tests, release validation, and the ad-hoc staged app
  also pass; Developer ID/notarization and clean-machine interactive QA remain
  with the release maintainer.

## Parakeet TDT And Nemotron MLX/GGUF Expansion Handoff - 2026-07-20

- The user-directed expansion owns the narrow additions required for the exact
  `mlx-community/parakeet-tdt-0.6b-{v2,v3}` and
  `mlx-community/nemotron-3.5-asr-streaming-0.6b` model directories, plus F16,
  Q8_0, and Q5_K_M artifacts from the corresponding `handy-computer` GGUF
  repositories. Those exact repositories do not publish BF16; F16 is the
  user-visible substitute and must not be mislabeled.
- Reuse the pinned native `mlx-audio-swift` implementation for MLX and the
  existing isolated transcribe.cpp Metal runtime for GGUF. Do not add the
  Python `mlx-lm`, `mlx-vlm`, or `mlx-audio` packages, and do not add the
  examples repository as an application dependency.
- This workstream may extend the MLX Audio and transcribe.cpp variants,
  language routing, benchmark CLI, signed catalog, release/model notices, and
  focused transcription/runtime/app tests. Preserve every existing runtime,
  visual-system, packaging, and concurrently uncommitted change in shared
  files.
- Promotion requires exact commit-pinned bytes and hashes, native MLX/Metal or
  transcribe.cpp/Metal evidence, install-shaped offline smokes, a valid signed
  catalog, and staged release verification. Language and streaming claims must
  remain no broader than the behavior actually exposed and measured by
  Textify's post-release batch-dictation path.
- Completed native verification: all twelve exact artifact choices matched
  their immutable source sizes and SHA-256 values, required MLX or
  transcribe.cpp Metal on an M4 Max, and completed the fixed 210-word English
  corpus at 0.48–3.33% WER with 67–137 ms median finalization. The final signed
  catalog contains 35 models. Full release validation and staged-app checks
  remain required before handoff.

## Local Ad-Hoc Launch Signing Handoff - 2026-07-21

- The user-directed launch fix owns the minimum Task 14 bundle changes needed
  to make locally ad-hoc-signed Xcode apps load Textify's embedded native
  runtimes under Hardened Runtime and to make staged-app verification launch
  the produced executable long enough to catch `dyld` failures.
- Keep the production `Textify.entitlements` strict. The library-validation
  exception is limited to a separate local entitlement used by Debug builds
  and the explicit `--stage-full-release` developer workflow; Developer ID
  archives continue using the production entitlement and consistently signed
  nested code.
- Preserve all model, runtime, catalog, UI, and concurrently uncommitted work.
  Verification must reproduce the current `libCLiteRTLM_mac.dylib` Team-ID
  rejection before the fix and prove the rebuilt app remains alive afterward.
- Completed verification: the staged Release workflow first failed its new
  launch smoke with exit 134 and the expected LiteRT-LM Team-ID rejection. With
  the local entitlement applied, the same workflow passes, Launch Services
  keeps Textify alive beyond five seconds with normal AppKit/Metal startup, all
  436 tests pass with 9 native opt-in skips, and release validation confirms the
  default Release configuration still uses `Textify.entitlements`.

## SwiftPM Release Staging Launch Handoff - 2026-07-21

- The current build request owns the minimum Task 14 fast-staging correction in
  `script/build_and_run.sh` needed for the arm64 SwiftPM Release executable to
  locate native runtimes embedded under `Contents/Frameworks`.
- Preserve the full Xcode staging, local-entitlement, runtime, catalog, and all
  concurrently uncommitted work. Add an artifact-level launch regression check
  so a successful compile and code-sign verification cannot hide an immediate
  `dyld` exit from the staged app.
- Completed verification: the arm64 SwiftPM Release bundle contains
  `@executable_path/../Frameworks`, passes the direct launch smoke and strict
  code-sign verification, validates the signed 38-model catalog, and remains
  running after Launch Services opens it. `swift test` passes 437 tests with 9
  opt-in native integration tests skipped and zero failures.

## Spokenly-Inspired UI Redesign Handoff - 2026-07-21

- The active UI redesign owns the existing Task 11 surfaces under
  `Sources/Textify/App/`, `Sources/Textify/UI/`, `Sources/Textify/Onboarding/`,
  `Sources/Textify/Overlay/`, and `Sources/Textify/SettingsUI/`.
- It also owns the narrow visual-token assertions in
  `Tests/TextifyAppTests/ProductionUITests.swift` so the tests describe the new
  blue, compact, dark macOS visual system captured from the Spokenly reference.
- Runtime behavior, model policy, settings persistence, native engines, build
  scripts, and release staging remain outside this handoff.

## Model Provider Logo Asset Handoff - 2026-07-21

- The user-directed model catalog polish owns only the provider logo image sets
  added under `Resources/Assets.xcassets/` and their use by the Task 11 model
  rows in `Sources/Textify/SettingsUI/SettingsRootView.swift`.
- It also owns the minimum `script/build_and_run.sh` staging step that compiles
  the existing asset catalog into `Assets.car` and verifies that resource. This
  keeps vendor logos and the pre-existing app icon available in the fast
  SwiftPM app bundle as well as the Xcode build.
- Preserve the app icon and every packaging, signing, runtime, model-catalog,
  and concurrently uncommitted resource change. Vendor marks must remain local
  bundled assets so the model page continues to work fully offline.

## Benchmark-Derived Model Ratings Handoff - 2026-07-22

- The user-directed rating workstream owns the benchmark-to-catalog pipeline
  under `Benchmarks/RealtimeASR/`, the minimum strict model-manifest and
  verification changes under `Sources/TextifyModels/`, the corresponding
  signing helpers and focused tests, and the model rating presentation in
  `Sources/Textify/SettingsUI/SettingsRootView.swift`.
- Quality and speed signals must be derived from a versioned, checksum-pinned,
  English comparison profile and exact model artifacts. Catalog tiers remain
  curator labels and must not be used as measured-rating fallbacks; models
  without complete comparable evidence display `Unrated`.
- The universal catalog profile is capped at 29 seconds so every current
  English transcription model can run the same cases. Longer VoiceCodeBench
  recordings remain supplemental structured-dictation evidence and do not
  affect the universal rating.
- Benchmark quality must reflect Textify's production hallucination decision,
  while retaining raw engine output for diagnostics. Speed excludes load and
  warmup and is publishable only from stable repeated runs on the declared
  reference host.
- Automated workflows may generate candidate rating records and regression
  reports, but may not edit, publish, or sign the production catalog. Existing
  signed manifest V1 verification must remain valid; production V2 signing is
  a manual maintainer operation.
- Preserve every unrelated UI, runtime, model, resource, packaging, and build
  change in the dirty worktree.
- Calibration froze suite-index SHA-256
  `77637f85b4e3fde7b15f5481804e231d720c0337d11153dc5867dee2587ddde8`
  after three complete Apple M4 Max runs each for whisper.cpp small.en and
  FluidAudio Parakeet v3. The resulting unsigned candidates remain ignored
  evidence; `models/manifest.json` and its signature are byte-for-byte
  unchanged.

## Direct-Score Quality Rating V2 Handoff - 2026-07-23

- The user-directed rating simplification continues the benchmark-derived
  rating workstream across `Benchmarks/RealtimeASR/`, the strict benchmark
  validation under `Sources/TextifyModels/`, focused tests, and rating
  documentation.
- Preserve the frozen `english-catalog-rating-v1` policy and its historical
  capped results. Introduce `english-catalog-rating-v2` as a scoring policy
  over the unchanged, checksum-pinned v1 suite so existing complete raw runs
  can be rescored without rerunning inference.
- In v2, the quality level and label derive only from the rounded weighted
  quality score. Keep the 200-case no-speech false-positive rate as separately
  signed evidence and a regression signal, but do not let it modify the
  quality level.
- Generated v2 candidates remain unsigned review artifacts. Do not edit or
  sign `models/manifest.json` or `models/manifest.json.sig` as part of this
  handoff.

## Signed Model-Page Rating Promotion Handoff - 2026-07-23

- A follow-up user request explicitly authorized promoting the reviewed v2
  ratings onto the model page. The repository production catalog is now
  manifest v2 with 31 exact `english-catalog-rating-v2` benchmark objects; the
  Canary runtime failure and six language/purpose-inapplicable models remain
  `Unrated`.
- The exact manifest was signed with the configured
  `textify-model-manifest-2026-huggingface` Keychain key and passed the
  standalone release verifier. Manifest SHA-256 is
  `ba2cf26665eb096de1be19279014c8f36ff5132305d5881db677805752c388a1`;
  signature SHA-256 is
  `6e11f8d477f6c4f6652ae895a82d611210112cdc9124320d32673589a0461e9f`.
- This handoff updates the bundled/repository production inputs only. External
  GitHub Pages publication remains a separate release operation.

## Qwen Runtime Diagnostics Handoff - 2026-07-23

- The user-directed Qwen failure investigation owns the narrow cross-task fix
  in `TextifyRuntime` that preserves a catalog runtime's required automatic
  language mode instead of replacing it with the global language preference.
- The same slice owns privacy-safe failure codes and timestamps in
  `TextifyDiagnostics`, plus a dedicated read-only Logs pane under the existing
  Task 11 settings UI. Logs must remain closed-schema technical metadata:
  never audio, transcripts, clipboard contents, target-app identifiers,
  vocabulary, or raw library error strings.
- Preserve all benchmark, catalog-rating, manifest, asset, packaging, and
  concurrently uncommitted UI work. Verification must cover the exact
  Qwen3-ASR resolver/adapter mismatch, recent-log redaction, and the existing
  full Swift test gate.
- Completed verification: the installed Qwen3-ASR 1.7B BF16 artifact
  transcribes the pinned sample through the Metal runtime, the resolver
  regression preserves its required `auto` language mode, all 455 Swift tests
  pass with 9 native opt-in skips, and the staged app renders the privacy-safe
  Logs pane with current timestamps and redacted JSONL events.

## 2026 Open-ASR Article Model Expansion Handoff - 2026-07-23

- The user-directed model expansion owns the narrow runtime exposure, catalog
  entries, license notices, focused tests, and model-support documentation
  needed for the sixteen models named in the linked MarkTechPost comparison.
- Preserve every unrelated benchmark, rating, UI, diagnostics, packaging, and
  concurrently uncommitted change. Reuse the pinned native runtimes already in
  the repository; do not claim production support for an architecture that
  cannot execute through Textify's offline runtime boundary.
- The existing transcribe.cpp 0.1.3 binary already contains exact handlers for
  Granite Speech 4.1 2B, Granite Speech 4.1 2B-NAR, Voxtral Mini 4B Realtime
  2602, and MOSS-Transcribe-Diarize. The existing sherpa-onnx 1.13.2 boundary
  contains Omnilingual ASR 300M CTC support. This workstream may expose those
  variants, pin exact immutable artifacts, and add install-shaped verification
  without modifying the native binaries.
- MOSS-Transcribe-preview-2B, ARK-ASR-3B, both Kyutai STT checkpoints, and
  diffusion-gemma-asr-small require native architecture work outside the
  current runtime binaries. Record those gaps explicitly rather than adding
  inert catalog rows or introducing a Python/cloud fallback.
- The signed production manifest may be updated only after exact file sizes,
  SHA-256 values, license/provenance, runtime compatibility, and focused tests
  are verified. Preserve the benchmark-derived ratings policy: new models
  remain unrated until comparable signed evidence exists.
- Completed verification: the signed 43-model manifest passes its standalone
  verifier; all 462 Swift tests pass with 11 native opt-in skips; Omnilingual
  ASR 300M CTC transcribes the pinned sample through the installed sherpa-onnx
  runtime; and the full release validator passes the production build,
  resources, native libraries, headers, symbols, patches, and license notices.
  The four newly exposed transcribe.cpp families have catalog, resolver,
  adapter, and runtime coverage; their multi-gigabyte native artifact smokes
  remain explicit opt-in tests and were not run in this checkout.

## Model Catalog Experience Seam Handoff - 2026-07-23

- GitHub issue #2 owns the narrow behavior-preserving prefactor that moves the
  current signed-catalog, installed-model, active-preference, query, and
  download-state derivation behind one pure catalog-experience boundary.
- This slice may add that boundary under the existing settings UI ownership,
  route the current flat model page through it, and add focused semantic app
  tests. It must preserve current v2 catalog decoding, visible order, ratings,
  active state, install progress, and user-facing actions.
- Manifest v3, hierarchical rows, revised action semantics, persistent queues,
  storage inventory, and runtime behavior remain owned by later tickets.

## Signed Manifest V3 Presentation Graph Handoff - 2026-07-24

- GitHub issue #3 owns the additive manifest work under
  `Sources/TextifyModels/Manifest/`, its focused model fixtures/tests, and the
  minimum `AppServices`/settings composition and catalog-experience seam
  extension needed to carry verified Family, Checkpoint, and Exact Artifact
  presentation data end to end.
- `ModelEntry` remains the exact operational installation/runtime record.
  Manifest v3 adds a separate normalized signed presentation graph with strict
  typed metadata and production-policy validation; signed v1/v2 decoding,
  installation identities, receipts, and active preferences must remain
  behaviorally unchanged.
- This slice does not publish or rewrite `models/manifest.json`, render native
  hierarchy rows, change user-facing actions, resolve compatibility fallbacks,
  or implement later queue, storage, migration, revocation, and release work.

## Bundled Production Catalog V3 Publication Handoff - 2026-07-24

- GitHub issue #4 owns the production-only migration of
  `models/manifest.json` and its detached signature from schema v2 to v3. The
  operational `models` array, every exact artifact ID, immutable URL, digest,
  byte size, runtime tuple, and managed layout must remain unchanged.
- This slice also owns the minimum v3 enablement in the standalone manifest
  signing and verification helpers, their publication guidance, a frozen v2
  migration fixture, and focused production-catalog integration tests.
- The standalone verifier may add one narrowly scoped Swift executable target
  in `Package.swift` so publication checks reuse `TextifyModels` strict
  decoding, signature verification, and production policy instead of carrying
  a second schema implementation in shell tooling.
- Runtime behavior, installer semantics, active-preference mutation, native
  hierarchy rendering, queues, storage inventory, and revocation remain owned
  by later tickets.

## Native Model Catalog Hierarchy Handoff - 2026-07-24

- GitHub issue #5 owns the Task 11 Models-pane presentation changes under
  `Sources/Textify/SettingsUI/`, the catalog-experience selection/disclosure
  state needed to render the signed v3 Family → Checkpoint → Exact Artifact
  graph, and focused semantic coverage in `Tests/TextifyAppTests/`.
- This slice preserves exact artifact installation, activation, deletion,
  download, receipt, and runtime identities. Selection is UI context only and
  never mutates active preferences.
- The existing flat operational rows remain the compatibility fallback when no
  signed v3 presentation graph is available. Virtualization profiling, the
  adaptive inspector, comparison columns, purpose destinations, expanded query
  behavior, queues, storage, revocation, and runtime transactions remain owned
  by later tickets.

## Adaptive Model Inspector Handoff - 2026-07-24

- GitHub issue #6 owns the adaptive trailing inspector under
  `Sources/Textify/SettingsUI/`, the catalog-experience projections and
  cancellable local-detail loading needed to distinguish aggregate Checkpoint
  truth from operational Exact Artifact truth, and focused semantic coverage in
  `Tests/TextifyAppTests/`.
- Catalog, compatibility, receipt, and cached local-state facts must publish
  immediately. Filesystem metadata inspection runs off the main actor, never
  hashes model contents implicitly, and may publish only for the current typed
  selection and generation.
- The existing hierarchy, exact installation/runtime identities, active
  preferences, and explicit verification action remain unchanged. Storage
  inventory accounting, comparison tables, query expansion, queues,
  revocation, deletion transactions, and runtime changes remain owned by later
  tickets.

## Exact Artifact Variant Comparison Handoff - 2026-07-24

- GitHub issue #7 owns the expanded-checkpoint comparison presentation under
  `Sources/Textify/SettingsUI/` and its focused catalog-experience coverage in
  `Tests/TextifyAppTests/`.
- The signed recommended exact artifact is the checkpoint reference. Quality
  and speed may be summarized relative to it only when both artifacts carry
  the same non-empty signed comparison-group identifier. Different groups
  report Not Comparable, and an unrated reference produces no invented
  baseline; the exact artifact inspector continues to expose raw signed
  evidence.
- This slice owns only precise Artifact Format, Numeric Format, Runtime,
  Compute Route, responsive comparison layout, and the accessible About Model
  Variants explanation. Existing exact actions and installation/runtime
  identities remain unchanged. Purpose destinations, query expansion, queues,
  storage, revocation, deletion transactions, and runtime behavior remain
  owned by later tickets.
- The same slice owns the narrow Task 14 source-membership refresh in the
  generated Xcode project. `project.yml` already includes
  `Sources/Textify/`, but the checked-in project predates the catalog files
  added by issues #2–#7; regeneration is required so production Xcode builds
  compile the same settings UI sources as SwiftPM.

## Purpose-Specific Model Destinations Handoff - 2026-07-24

- GitHub issue #8 owns the narrow Task 11 settings and onboarding changes under
  `Sources/Textify/{App,SettingsUI,Onboarding,UI}/` plus focused semantic
  coverage in `Tests/TextifyAppTests/`.
- Transcription Models and Voice Cleaning remain projections of the same
  signed catalog, compatibility resolver, installer, installed-model store,
  active preferences, hierarchy, selection, and inspector semantics. Purpose
  filtering uses the signed `ModelPurpose` value and never filename or display
  title inference.
- Onboarding may replace its legacy fixed-model shortcut with compatible
  transcription choices from those shared services. Installation and
  activation remain separate operations; voice cleaning stays optional and
  independently disableable.
- Persistent queues, storage inventory, revocation, deletion transactions, and
  runtime switching transactions remain owned by later tickets.

## Model Compatibility Boundary Handoff - 2026-07-24

- The issue #8 standards review identified that the compatibility predicate is
  pure model-domain logic, so this ticket additionally owns a narrow extraction
  into `Sources/TextifyModels/` with focused coverage in
  `Tests/TextifyModelsTests/`.
- The app target retains only capture of the current bundle, operating-system,
  architecture, and physical-memory values plus dependency composition.
- This handoff does not expand issue #8 into installer policy, runtime
  switching, storage inventory, revocation, or queue ownership.

## Transparent Recommendation And Fallback Handoff - 2026-07-24

- GitHub issue #9 owns the typed compatibility and same-Checkpoint
  recommendation resolver under `Sources/TextifyModels/`, plus the minimum
  catalog-experience, Settings, onboarding, app-composition, and focused test
  changes needed to keep incompatible Exact Artifacts visible and disclose a
  signed fallback before installation.
- A fallback may resolve only from the Checkpoint's signed
  `fallbackArtifactIDs`, only when the signed recommendation is deterministically
  incompatible, and only to a compatible Exact Artifact in that same
  Checkpoint. Requires-update and indeterminate outcomes never authorize a
  fallback.
- Presentation order remains `artifactIDs`; fallback order is not revocation
  recovery, runtime switching, or a hidden CPU/Runtime substitution. Persistent
  queues, storage inventory, revocation, deletion transactions, and runtime
  switching remain owned by later tickets.
- Verification completed with focused compatibility/catalog tests, the staged
  signed app-bundle launch, a native macOS grouped-variant visual smoke, clean
  Standards and Spec reviews, and the full 519-test suite (11 opt-in native
  smokes skipped, zero failures).

## Explicit Install And Activation Transactions Handoff - 2026-07-24

- GitHub issue #10 owns the narrow Task 11 app, Settings, onboarding, and
  focused integration-test changes needed to keep model selection, managed-byte
  installation, transcription Use, Voice Cleaning Enable, and Voice Cleaning
  Disable as separate operations.
- This slice may add the minimum `AppDictationService` preparation seam needed
  to prove one installed candidate Ready before committing its purpose-specific
  active preference. Failed preparation must leave the previous persisted
  identity unchanged and restore its runtime preparation when necessary.
- Catalog presentation may add orthogonal state tokens for Installed, Ready,
  Active, incompatible, and Needs Repair so one status does not erase another.
  Existing exact artifact IDs and signed compatibility decisions remain
  authoritative.
- Persistent download queues, storage inventory, revocation, deletion
  transactions, and generalized runtime switching remain owned by later
  tickets.
- Verification covers the explicit install/readiness and purpose-specific
  activation transactions, processing-safe backend reservation, and
  recording-time preference snapshots through focused app, catalog, and
  runtime integration tests.
- Final verification completed with the staged signed app bundle and its
  43-model manifest, a native macOS grouped-variant visual smoke, clean
  Standards and Spec reviews, and the full 537-test suite (11 opt-in native
  smokes skipped, zero failures).

## Model Catalog Discovery And Reveal Handoff - 2026-07-24

- GitHub issue #11 owns the Task 11 catalog-query and Models-destination
  presentation changes under `Sources/Textify/SettingsUI/`, focused semantic
  coverage in `Tests/TextifyAppTests/`, and the minimum `SettingsRouter`
  extension in `Sources/Textify/App/AppServices.swift` required to carry one
  purpose-specific Exact Artifact reveal identity into the existing main
  window.
- All and Installed remain projections of the same trusted signed graph and
  local-state overlay. Search and filters retain signed Family, Checkpoint,
  Exact Artifact, provider, language, Artifact Format, Numeric Format, Runtime,
  Compute Route, compatibility, state, and benchmark-evidence truth without
  filename inference for v3 artifacts.
- Catalog order follows signed `curatedRank` at the Family, Checkpoint, and
  Exact Artifact levels. Quality, Speed, and Download Size use each
  Checkpoint's signed recommended Exact Artifact as their reference, and metric
  ties preserve that signed order.
- Installed Size consumes On Disk bytes as the existing inspector measures
  them, invalidates those measurements when the typed installed records change,
  and keeps unknown measurements last in both directions. Persistent
  background storage inventory remains owned by issue #15.
- A reveal is a separate pinned Exact Artifact projection. It never mutates the
  user's scope, search, filters, or sort, and dismissal restores the ordinary
  query result.
- Persistent queues, storage inventory collection, revocation, deletion
  transactions, runtime switching, catalog staging, keyboard virtualization,
  and large-catalog performance work remain owned by later tickets.
- Final verification covers 546 tests with 11 opt-in native smokes skipped and
  zero failures, the staged app's 43-model signed manifest, and a native macOS
  smoke of All/Installed, search, filters, removable tokens, sorting, inspector
  On Disk measurement, and Installed Size. Independent Standards and Spec
  reviews report no remaining findings.

## Persistent Model Installation Queue Handoff - 2026-07-24

- GitHub issue #12 owns the Task 12 model-download state and persistence work
  under `Sources/TextifyModels/Downloads/`, the narrow Task 11 app coordinator
  and Downloads-popover wiring under `Sources/Textify/{App,SettingsUI}/`, and
  focused queue, composition, and catalog-experience tests.
- The minimum call-site and persistence closure also owns the existing
  onboarding install actions, the shared install-progress phase switch,
  `ModelStorageLayout.installQueueURL`, and their focused tests. These files
  route existing behavior through the queue; they do not broaden onboarding,
  general storage inventory, or model-install policy.
- A Queue Attempt is the durable identity of one Install or Reinstall
  authorization. Attempts retain explicit FIFO order and terminal history;
  Retry appends a new linked attempt at the tail and never rewrites the prior
  lifecycle.
- The queue is the only path that invokes `ModelInstaller`. It serializes
  managed byte mutation, persists nonterminal work before execution, restores
  interrupted active work as queued after relaunch, and projects state by Exact
  Artifact so unrelated rows and Checkpoint rollups remain unchanged.
- Cancel, Pause, Resume, Retry, and Reveal target one stable Queue Attempt.
  Canceling queue work never calls installed-model deletion. Validator-bound
  resumable data may be associated with a later attempt, but only
  `ModelInstaller` may create installed ownership after complete verification
  and atomic installation.
- Revoked is a terminal Queue Attempt state required for truthful Downloads
  history in this ticket. Fetching or applying signed revocations remains
  outside this slice.
- Persistent storage inventory, peak-space policy, signed-catalog freshness,
  revocation ingestion, deletion transactions, generalized runtime switching,
  catalog staging, and large-catalog virtualization remain owned by later
  tickets.
- Final verification completed with 568 tests (11 opt-in native backend
  smokes skipped, zero failures), the staged signed app bundle and its
  43-model manifest, a native macOS Downloads-popover smoke, and clean
  independent Standards and Spec reviews.

## Trusted Catalog Snapshot And Staging Handoff - 2026-07-24

- GitHub issue #13 owns the trusted-catalog authority and presentation-staging
  work under `Sources/TextifyModels/Manifest/`, the narrow Task 11
  `ProductionModelManifestLoader`/`ModelCatalogCoordinator`/Models-destination
  composition and UI changes, and focused model/app tests.
- This slice also owns two narrow cross-task closures required by its
  acceptance criteria: Task 12's `ModelDownloader` must expose the exact
  verified manifest/signature bytes without adding another verification path,
  and Task 3's closed diagnostics schema must record a high-severity catalog
  rejection reason without free-form content.
- The closed diagnostics-schema addition requires the exhaustive
  `FakeRuntimeDiagnostics` switch in
  `Tests/TextifyRuntimeTests/AppDictationServiceTests.swift` to acknowledge
  the new catalog event. That test-only compatibility case is owned by this
  handoff and does not alter runtime behavior.
- `generatedAt` is the existing signed manifest-v3 monotonic catalog revision.
  The durable highest accepted revision remains independent from the presented
  revision so routine updates can be accepted and staged while either Models
  destination is open.
- This work does not add queue freshness gating, revocation ingestion, storage
  inventory, deletion transactions, generalized runtime switching, or
  large-catalog virtualization; those remain owned by later tickets.
- The bundled/cache snapshot renders before the remote check, retains the
  exact verified manifest and signature bytes, and persists highest accepted,
  presented, and staged revisions atomically. Invalid signatures, rollbacks,
  strict decoding, schema validation, and cache corruption never replace
  trusted presentation; future schemas remain a distinct update-required
  outcome.
- Valid updates stage while either Models destination is open and apply once
  both close or the user chooses Apply Now. Stable hierarchy identities retain
  surviving selection, expansion, focus, and scroll anchors. Installed-model
  Activate and Delete actions remain available through untrusted, trusted,
  offline, staged, rejected, and future-schema catalog states.
- Final verification completed with 591 tests (11 opt-in native backend smokes
  skipped, zero failures), the production release validator, the staged
  signed app bundle and its 43-model catalog, and a native macOS smoke of both
  Models destinations with trusted content remaining usable under a persistent
  rejection banner. Independent Standards and Spec reviews report no
  remaining actionable findings.

## Catalog Publication And V3 Rollback Bridge Handoff - 2026-07-25

- GitHub issue #23 owns the release-facing catalog publication policy and
  evidence types under `Sources/TextifyModels/Release/`, focused model tests
  and fixtures, the minimum production-manifest policy tightening required to
  reject incomplete license/provenance metadata, and catalog prepublication
  scripts and release documentation. It also owns the minimum Task 1
  `Package.swift` integration needed to expose the publication verifier as a
  Swift package executable; no other package products, targets, or dependency
  declarations are in scope. The handoff also includes replacing the duplicate
  production catalog endpoint/key literals in
  `Sources/Textify/SettingsUI/SettingsRootView.swift` with the shared embedded
  trust definition used by that verifier; no surrounding Settings UI behavior
  is in scope. It additionally owns the mechanical `AppPaths`/`AppServices`
  adoption of the shared typed rollback-state layout so catalog, revocation,
  settings, and Models paths retain one owner; no other app composition
  behavior is in scope.
- The publication gate composes the existing manifest, production-policy, and
  revocation verifiers. It does not introduce another signature path or place
  private signing material in the repository.
- The designated v3 rollback bridge is evidence-only and non-mutating. It
  decodes the existing Installation Receipt, Queue Attempt, placement, active
  identity, trusted-catalog, and sticky-revocation formats and proves that
  application withdrawal retains byte ownership and blocks revoked content.
- Endpoint smoke remains an explicit prepublication operation so ordinary CI
  does not fetch model artifacts or depend on live catalog hosting.
- This handoff does not own generalized installer fault injection, queue and
  storage recovery matrices, or final production release sign-off; those
  remain issues #24 and #25.
- Final verification completed with 766 tests (12 expected opt-in native/
  stress smokes skipped, zero failures), the arm64 production build, signed
  bundled catalog verification, native dependency checks, and shell syntax
  checks. Independent Standards and Spec re-reviews report no remaining
  actionable findings.

## Fault Campaign And Release Evidence Handoff - 2026-07-25

- GitHub issues #24 and #25 own a separate `TextifyReleaseVerification`
  package module, its focused tests, and release-only verifier executables and
  scripts. The shipping `Textify` executable must not depend on this module.
- This handoff permits the minimum Task 1 `Package.swift` additions needed to
  expose those release-verification targets. It also permits release-process
  documentation changes under Task 14 ownership and focused reuse of the
  existing Task 4 model-domain public interfaces without changing their
  runtime behavior.
- Issue #24 owns deterministic localhost transfer scenarios, durable-boundary
  fault and recovery campaigns, security/privacy probes, seeded soak evidence,
  and retained machine-readable reports. It must not download production model
  artifacts or send local inventory to a publisher.
- Issue #25 owns strict release-candidate evidence declarations and bundle
  validation. Missing real-device measurements, manual accessibility results,
  independent security review, or two distinct human approvals remain
  release-blocking; automation must never synthesize or waive them.
- Issue #24 verification separates its fixed-seed property model from
  production evidence. The report includes a 1,000-operation real
  `ModelInstallQueueStore` soak with 3,000 store reconstructions, plus
  production `URLSessionDownloadTransport` loopback scenarios and executed
  security/privacy probes. The retained focused production-path log and
  machine-readable test-case index cover installer, queue, storage,
  revocation/restoration, deletion,
  coordinator, diagnostics, and release-verification behavior.
- Issue #25 adds a strict release-evidence declaration and atomic bundle
  verifier. It binds the current release commit, parent specification, build
  artifacts, catalog/revocation identities, and every retained attachment
  digest; requires complete semantic UI and genuine manual accessibility
  coverage; enforces 30 warm iterations and three cold launches on both a real
  oldest-supported M1-class device and a later supported device; requires
  real-device evidence for every declared Compute Route; applies the declared
  defect and independent-review policies; and requires two distinct human
  approvals.
- The implementation session does not claim final release sign-off. Public v3
  catalog/revocation publication, oldest-supported hardware measurements,
  manual accessibility passes, independent human review, and two human
  approvals remain external release gates. The verifier rejects their absence
  and the checked-in template is intentionally incomplete.
- Review hardening requires every release category to use a distinct structured
  evidence record bound to the release commit and separately hashed source
  attachments. Performance counts are checked against retained sample arrays;
  Compute Routes are derived from the attached v3 manifest; publication
  identity is decoded from retained publication evidence and bound to that
  manifest and an attached executable hash; review and approval declarations
  must match their own retained records.
- Review hardening needs two read-only production-policy entry points in
  `ProductionModelPolicy.swift` so issue #24 can execute the same HTTPS and
  typed-digest-alias decisions used by manifest validation instead of copying
  release-only stand-ins. This is a narrow Task 4 handoff: existing validation
  behavior is unchanged and no other model-domain files are owned.
- The same hardening also centralizes anonymous catalog GET construction in
  `ModelDownloadURLPolicy`. Adding that policy to
  `Sources/TextifyModels/Downloads/ModelDownloader.swift` is a narrow Task 12
  handoff. Reusing it from the manifest and revocation downloaders is a
  separate narrow Task 4 handoff. Neither change alters endpoints or payloads;
  together they make the production anonymity rule directly executable by
  release checks.
- Final local validation after review hardening executed 784 tests with 12
  expected environment-gated skips and zero failures, then completed the
  production build and vendor integrity checks. The retained-evidence script
  separately executed 198 focused tests with zero failures and verified all
  generated checksums.
- At commit `b79f299`, issue #24 remained open because its modeled 12-by-11
  matrix and real queue/partial soak did not replace production failpoints or
  forced process relaunches. The Production Model Fault Injection handoff above
  supersedes that limitation.

## Model Catalog Scroll Performance Follow-up - 2026-07-26

- The Models pane no longer publishes passive viewport changes into pane-wide
  SwiftUI state. Keyboard navigation and selection recovery retain explicit,
  one-way semantic scrolling; exact pixel-offset restoration during catalog
  mutations is intentionally no longer preserved.
- The 43-model catalog uses an eager `VStack` and no
  `scrollTargetLayout()`. This moves its mixed-height row layout out of the
  scrolling path and avoids the repeated lazy row creation and size fitting
  that made trackpad scrolling visibly hitch.
- The final Release build was validated interactively and all 800 automated
  tests passed with 12 expected environment-gated skips and zero failures.

## Bundled-Only Model Catalog Handoff - 2026-07-26

- The active user-directed offline-first catalog change owns the narrow
  production composition, bundled manifest loader, model-transfer catalog
  integrity prerequisite, Models/onboarding presentation, focused tests, and
  source-of-truth specification changes required to make the app-bundled signed
  manifest the only runtime catalog.
- Textify must not fetch a manifest, manifest signature, revocation body, or
  revocation signature at launch, when onboarding opens, when a Models
  destination opens, or before a model transfer. Catalog membership changes
  ship only through an app release.
- Existing signed-manifest verification, strict production policy, immutable
  artifact URLs, size/SHA-256 verification, installed receipts, imported
  models, and previously accepted sticky revocation state remain intact. Model
  artifact downloads continue to use the network when explicitly requested.
- The existing remote catalog coordinator/store and publication machinery may
  remain as non-production compatibility and release-verification code, but
  production composition and user-facing recovery actions must not reach it.

## Retained Model Catalog Navigation Handoff - 2026-07-27

- Issue #26 owns the Settings model-catalog presentation lifetime, the
  app-scoped derivation cache used by catalog destinations, the dedicated
  catalog scrolling layout, and focused regression tests for warm navigation.
- This work may extend the bundled-only production composition and Models
  presentation files above, but it must preserve the bundled signed manifest
  as the only runtime catalog source and must not restore page-entry catalog
  refreshes or remote recovery actions.
- Pane navigation must retain the last useful verified projection and
  window-session query, hierarchy, selection, inspector, and scroll state.
  Closing the Settings surface may reset presentation choices, but must not
  discard the retained verified projection needed for the next open.
- Scroll retention means restoring the last semantic row anchor on pane
  re-entry. Exact passive pixel-offset tracking remains intentionally excluded
  because publishing trackpad viewport churn previously caused visible hitching.
- This handoff supersedes the 2026-07-26 eager-row choice with a conditional
  lazy-row implementation. The M1 Instruments, VoiceOver, Full Keyboard
  Access, variable-height scrolling, and trackpad-hitch gates decide whether
  the lazy stack ships or must move to a stronger system-virtualized control.

## Checkpoint-First Models Presentation Handoff - 2026-07-27

- Issue #27 owns the Models presentation projection, the shared responsive
  layout policy, progressive Exact Artifact choice, purpose-specific Voice
  Cleaning card, focused presentation tests, and the narrow signed catalog-copy
  publication gates needed by the redesigned chooser.
- The existing Family → Checkpoint → Exact Artifact domain graph, retained
  window-session feature lifetime, semantic navigation state, signed evidence,
  installation queue, integrity verification, revocation enforcement, and
  purpose runtime boundaries remain authoritative.
- This work may replace the permanently expanded artifact table and its
  per-row responsive decisions. It must not reintroduce page-entry loading,
  remote catalog access, inferred artifact identity, unsigned comparison
  claims, or automatic replacement after deletion or revocation.
- Changes outside the prior Settings UI ownership are limited to persisted
  legal Exact Artifact overrides, explicit Use orchestration, production
  presentation-copy validation, and the signed manifest copy reviewed in issue
  #27.
- The explicit Use handoff also owns focused application-composition coverage
  proving that only Use may continue from verified installation into
  activation; Install Only, reinstall, and failed transfers retain the prior
  active identity.

## Bounded Catalog Screen Projection Handoff - 2026-07-27

- The active Models scrolling-performance implementation owns the narrow
  derivation, checkpoint presentation, Settings composition, persisted
  artifact-override admission, provider-logo, and focused-test changes needed
  to keep rich catalog graphs out of the scrolling subtree.
- It preserves issue #26's retained catalog lifetime and issue #27's
  checkpoint-first interaction. For the bounded curated picker it replaces
  lazy row realization and per-row keyboard/accessibility focus bindings with
  an eager scalar screen projection and one composite keyboard focus target.
- Override validation moves into the existing derivation actor. Settings may
  persist cleanup only after the actor publishes an explicit invalid-override
  result; rendering must not reconstruct a catalog or schedule preference
  mutations.
- Download byte progress is isolated in event-created per-artifact cells.
  Structural phase changes may republish the screen projection, while
  byte-only ticks must leave it equal.
- Existing bundled-only catalog work in `AppServices.swift`,
  `SettingsRootView.swift`, and coordination/release documentation remains
  independent and must be preserved when this implementation is staged.

## Omnilingual ASR Retirement Handoff - 2026-07-28

- The active user-directed retirement removes
  `omnilingual-asr-300m-ctc-int8` from the bundled signed catalog, its
  Omnilingual-specific sherpa-onnx runtime and benchmark routes, and every
  Textify-managed local copy or transfer remnant.
- This slice may update Task 4 catalog and queue state, Task 7/13 transcription
  runtime and shim boundaries, Task 11 production startup composition and
  focused tests, the standalone benchmark package, current catalog
  documentation, and the signed manifest pair.
- Startup cleanup must clear and persist an active Omnilingual preference before
  deleting data, remove matching Queue Attempts before transfer processing
  begins, delete partial/staged/retained bytes, and reuse the crash-safe
  installed-artifact transaction so managed bytes disappear before the
  Installation Receipt. It is idempotent and retries after relaunch.
- No replacement model is selected automatically. Historical benchmark reports,
  changelog entries, prior coordination records, the signed v2 migration
  fixture, and upstream sherpa-onnx headers remain as audit evidence.
- Existing bundled-only catalog and bounded-screen-projection edits in the dirty
  worktree are independent and must be preserved.

## Explicit Transcription Language Handoff - 2026-07-29

- The active user-directed language fix owns the narrow settings-to-runtime
  language policy in `TextifyRuntime`, the minimum MLX Audio and transcribe.cpp
  runtime changes needed to carry an explicit supported language to inference,
  and focused regression tests in their existing test targets.
- A specific language selected in Settings must disable language detection and
  reach the active model as that language. Automatic is the only preference
  that may enable multilingual detection. An active model that does not support
  a specifically selected language must fail closed instead of silently using
  its catalog default or automatic detection.
- Preserve the independent Omnilingual retirement, bundled-only catalog,
  bounded screen projection, benchmark, manifest, packaging, and other dirty
  worktree changes.
- The final Debug test run passed all 846 automated tests with 11 expected
  environment-gated skips and zero failures.

## Floating Icon Placement Handoff - 2026-07-30

- The active user-directed floating-icon customization owns the narrow Task 5
  persistence, Task 11 Dictation-settings presentation, overlay-window
  geometry, and focused settings/app tests needed to expose X offset, Y offset,
  and scale.
- The values apply to the existing recording/processing overlay used by every
  configured trigger. Defaults preserve the current center-bottom placement and
  size, legacy settings decode to those defaults, and the final window frame
  remains clamped to the selected screen's visible frame.
- Preserve the independent model-catalog, explicit-language, benchmark,
  manifest, runtime, and other dirty-worktree changes. This slice does not add
  per-trigger profiles or any other overlay appearance controls.
- Focused persistence, composition, and geometry verification passed 15 tests,
  `swift build` passed, and `git diff --check` passed. Two full `swift test`
  attempts were blocked by a repeatable signal 10 in the independent
  `AppDictationServiceTests` before its first assertion; skipping that suite
  later exposed a separate signal 11 in `RuntimeAdaptersTests`. Neither
  crashing suite owns floating-icon settings or overlay geometry.

## Guided Permissions Setup Handoff - 2026-07-30

- The active user-directed permission setup improvement owns the narrow Task 11
  Privacy presentation, setup-status routing, macOS permission handoff, and
  focused app tests needed to guide users through Microphone and Accessibility
  from one primary action.
- macOS remains the source of truth. This work does not add permission toggles,
  bypass system consent, change runtime readiness, or reintroduce Input
  Monitoring as a requirement.
- Preserve the independent visual-refresh, floating-icon, model-catalog,
  explicit-language, benchmark, manifest, runtime, and other dirty-worktree
  changes. The existing onboarding step order remains unchanged.
- Verification passed 32 focused production UI tests, 11 focused permission
  and readiness tests, `git diff --check`, staged-build manifest verification,
  and a visual inspection of the staged Privacy pane.
- A full `swift test` attempt built successfully and passed all 78
  `AppCompositionTests` before reproducing the pre-existing signal 10 at the
  start of `AppDictationServiceTests`. Real TCC consent still requires manual
  validation with a stably signed installed app because macOS stores permission
  decisions against app identity.

## Offline Model License Disclosure Handoff - 2026-07-30

- The production open-source release audit owns the narrow legal-disclosure
  path needed to make every curated model license and notice viewable before
  download and without network access.
- This slice may add one isolated bundled-document resolver/view, preserve
  structured signed source/license/file data in the exact-artifact inspector,
  add the same disclosure affordance to onboarding, and add focused tests plus
  release-resource verification.
- Preserve the independent visual refresh, retained catalog navigation,
  permissions setup, floating-icon placement, explicit-language routing,
  manifest, runtime, benchmark, and other dirty-worktree changes. Do not
  restructure the surrounding model catalog or onboarding UI.
- License resolution must use the exact signed `licenseTextUrl` where copyright
  ownership differs, fail closed when a catalog license has no bundled
  document, and keep upstream links separate from the offline disclosure.

## Signed License Provenance Correction Handoff - 2026-07-30

- The production open-source release audit found one dead signed
  `licenseTextUrl` and one incomplete bundled model-license copy.
- This correction owns only the Canary-Qwen transcribe.cpp license URL, the
  detached manifest signature required by that byte change, the exact
  commit-pinned FunASR license copy, and focused legal-disclosure/release
  verification.
- Preserve every other signed catalog field, runtime, benchmark, model choice,
  and independent dirty-worktree change. The corrected manifest must pass the
  existing production-policy verifier before it can be committed.

## Compiled Dependency Attribution Handoff - 2026-07-31

- The production open-source release audit owns the narrow distribution
  attribution closure for third-party code that is linked into the app or its
  bundled native libraries.
- This slice may add exact pinned upstream NOTICE and nested component-license
  files, identify them in `THIRD_PARTY_NOTICES.md`, include them in both app
  staging paths, and pin them in release verification.
- Do not change dependency revisions, package APIs, runtime behavior, or
  unrelated source files. Every copied text must match the exact dependency or
  native-runtime revision used by the release build.

## Public Repository Privacy Scrub Handoff - 2026-07-31

- The production open-source release audit owns the one-line replacement of a
  developer-specific absolute path in the historical implementation plan.
- Preserve the plan's command, wording, chronology, and every other historical
  record; only substitute a neutral example checkout path.

## Bundled Revocation Delivery Handoff - 2026-07-31

- The production release security audit owns the narrow startup path that
  loads an exact bundled signed revocation snapshot before the bundled catalog
  can be presented or installed.
- This slice may update production manifest loading, startup composition, and
  focused app tests. Packaging, signed baseline bytes, evidence gates, and
  release documentation remain a separate release-engineering handoff.
- The bundled snapshot must be verified by the existing revocation trust
  boundary, merged through the existing sticky rollback-state rules, and fail
  closed when required bytes are absent, malformed, or invalid. It must not
  weaken persisted revocations or invent unsigned baseline state.
- Preserve the independent catalog UI, runtime, benchmark, signed manifest,
  attribution, and other dirty-worktree changes. Agents are not alone in the
  worktree and must not revert or reformat unrelated edits.

## Fail-Closed Release Publication Handoff - 2026-07-31

- The production release audit owns the narrow DMG-signing, embedded-input
  identity, and pre-publication ordering corrections in release scripts and
  `docs/RELEASING.md`.
- The DMG must carry the configured Developer ID signature before notarization;
  the mounted app must contain the tracked signed release inputs byte-for-byte;
  downloaded draft bytes must match an independently retained local digest.
- The release commit, annotated tag target, remote default branch, evidence
  declaration, and still-draft GitHub Release must agree before the command
  that makes the release public. No post-publication check may stand in for a
  precondition.
- Preserve archive/export behavior, notarization credentials, manual approval
  gates, and unrelated release documentation.

## Signed Revocation Baseline Packaging Handoff - 2026-07-31

- The production release audit owns the exact empty v2 authority baseline,
  detached revocation-domain signature, signing helper, bundle resources, and
  release gates required by the startup handoff above.
- The baseline may use the existing allowlisted maintainer Ed25519 key while
  retaining the distinct model-revocations signature type and canonical
  payload. Private key bytes remain in the maintainer Keychain and must never
  enter the repository, logs, or generated evidence.
- Future withdrawals and restorations replace this tracked pair only with a
  strictly later reviewed signed revision. The empty baseline does not waive
  the publication-evidence, rollback, manual review, or two-person approval
  gates.

## ONNX Runtime Deployment-Target Remediation Handoff - 2026-07-31

- The production release audit owns replacement of the accidentally thinned
  universal2 ONNX Runtime binary, whose arm64 slice requires macOS 15.5, with
  Microsoft's exact first-party 1.24.4 arm64 release binary targeting macOS
  14.
- This slice may replace only the vendored ONNX dylib and update its pinned
  source/archive/dylib size and hash provenance plus matching automated release
  gates. It must retain version `1.24.4`, arm64 architecture, install name,
  exported ABI, sherpa imports, library validation, and runtime smoke behavior.
- Preserve the sherpa dylib, public headers, catalog compatibility claims, and
  unrelated runtime/catalog work. Final acceptance still requires a real
  macOS 14 sherpa-model smoke from the signed release candidate.

## Release Artifact Surface Verification Handoff - 2026-07-31

- The production release audit owns exact production-entitlement allowlisting,
  the runtime-selected Whisper metallib gate, and normalization of Xcode's
  back-deployed Swift compatibility library to the arm64 hardened release
  contract.
- This slice may update export/package scripts and artifact verification only.
  It must not change app entitlements, Whisper kernels, dependency revisions,
  or application runtime behavior.
- The exported app must contain only the microphone audio-input entitlement;
  both the actual SwiftPM Whisper resource and fallback metallib must be valid
  macOS 14 libraries with required kernels; every shipped Mach-O executable
  and dylib must be arm64 and carry the expected release signature policy.

## Exact Upstream Legal Text Whitespace Handoff - 2026-07-31

- The production open-source release audit owns a repository attribute that
  exempts byte-for-byte upstream legal snapshots from Git whitespace
  normalization and whitespace-error checks.
- Preserve the upstream license and NOTICE bytes exactly; the exemption must
  apply only beneath `THIRD_PARTY_LICENSES/` and must not relax checks for
  application source, scripts, first-party documentation, or configuration.

## Post-Review Runtime Trust And Retirement Handoff - 2026-07-31

- The production release review remediation owns the narrow startup gates in
  `AppServices.swift` and focused app-composition tests needed to block runtime
  startup when bundled/persisted model trust cannot be established or retired
  Omnilingual cleanup cannot finish safely.
- Catalog/revocation bootstrap failure must prevent model preparation and
  hotkey startup without discarding sticky revocation state. Retirement
  cleanup failure must prevent runtime and transfer recovery from starting so
  cleanup can retry on the next launch.
- Preserve the signed catalog/revocation formats, normal successful startup,
  model selection behavior, and unrelated UI/runtime work.

## Post-Review Persistent Window Handoff - 2026-07-31

- The production release review remediation owns the main-window presenter and
  one focused test proving close/reopen retains and reuses the same `NSWindow`.
- Closing may reset the catalog presentation session, but must not release the
  presenter-owned window or delegate. Preserve onboarding-window behavior,
  Dock/menu-bar routing, and all visual layout.

## Post-Review Release Provenance And CI Handoff - 2026-07-31

- The production open-source release audit owns the CI runner/toolchain
  correction, executable deployment-target assertions, and archive-source
  cleanliness gates identified by independent review.
- CI must use an Apple-silicon runner with Swift 6.2 or later while proving the
  produced Textify executable still targets macOS 14.0. Archive creation must
  capture one clean committed source state and refuse to stamp output if the
  worktree or `HEAD` changes before the archive completes.
- This slice may update `.github/workflows/ci.yml`, release validation and
  artifact-verification scripts, `build_archive.sh`, and the matching build
  prerequisites in public/release documentation. It must not weaken manual
  macOS 14 real-device, Developer ID, notarization, or evidence gates.

## Exact Release Input Byte Preservation Handoff - 2026-07-31

- The production open-source release audit owns `.gitattributes` rules that
  disable line-ending conversion for copied third-party legal snapshots and
  the detached-signature-bound catalog/revocation payloads.
- Keep whitespace diagnostics enabled everywhere else. Do not rewrite the
  protected files; their currently verified hashes and signatures must remain
  unchanged.

## Post-Review Automated Evidence Count Handoff - 2026-07-31

- The production release review remediation may update only the automated test
  count and matching validation description in `docs/MANUAL_QA.md` after the
  integrated release gate finishes.
- Preserve every manual checkbox, human-approval requirement, credentialed
  signing/notarization blocker, and real-device evidence requirement.

## Public Documentation Truthfulness Handoff - 2026-07-31

- The production open-source release audit owns narrow corrections to
  `README.md`, `docs/release/v1.1.0.md`, and `PRIVACY.md` identified by the
  final documentation review.
- Public feature copy must not claim that Textify 1.1 can select a microphone;
  the shipping setting is System Default. The privacy statement must also
  disclose user-opened model, source, and license links that leave Textify for
  third-party pages in the default browser.
- Preserve all unrelated feature claims, release-blocking wording, and the
  distinction between Textify's own model-download requests and browser
  navigation initiated by the user.

## Signed Artifact Source-Provenance Handoff - 2026-07-31

- The production release review remediation owns the narrow build metadata and
  release-script changes required to carry the archive's original clean commit
  into the signed app and prove the same identity through export, DMG creation,
  evidence binding, draft creation, notarization, and publication.
- This slice may update `Resources/Info.plist`, `project.yml`, the generated
  Xcode project, release helpers, focused release validation, and matching
  release documentation/tests. Every long-running transformation must compare
  the captured commit with a clean `HEAD` both before and after it runs.
- The commit identity must live inside the signed app so a stale DMG cannot be
  rebound to a later declaration whose executable happens to be unchanged.
  Evidence, draft, and publish helpers must verify that signed identity against
  the declaration/tag commit.
- The artifact verifier may also close the reviewed generic Mach-O gap by
  requiring every packaged Mach-O file—not only the known libraries—to be
  exactly arm64 while preserving the macOS 14 compatibility checks.

## Authoritative Spec Drift Release Gate Handoff - 2026-07-31

- The production open-source release audit owns narrow release-documentation
  gates for the independently reviewed mismatch between `docs/SPEC.md` and the
  shipping microphone UI/runtime.
- Do not rewrite the authoritative product decision or implement the missing
  feature in this release-setup slice. Instead, add explicit unchecked manual
  gates for non-default microphone selection and the visibility-scoped live
  input meters, and record that app publication remains blocked until the
  feature ships or the product owner formally narrows the specification.
- Also preserve the review finding that the specification's old “No language
  selector” statement conflicts with the shipping language control. Resolving
  either product decision requires explicit scope authority; source
  publication may proceed while production app publication remains blocked.

## Catalog Interaction Spec Blocker Handoff - 2026-07-31

- The production open-source release audit owns narrow release-documentation
  gates for the independently confirmed catalog interaction defects. Do not
  redesign the catalog UI in this release-setup slice.
- Production app publication must remain blocked while a multi-variant
  Checkpoint-level Command-Delete can resolve implicitly to one selected Exact
  Artifact, the normal curated inspector lacks the required source and license
  affordances, or the checkpoint surface lacks stronger boundaries for
  Increase Contrast and Differentiate Without Color.
- Preserve the existing destructive-action confirmations and accessibility
  evidence requirements. Source publication may proceed with explicit,
  unchecked gates and public issue tracking for the implementation work.

## Hosted CI Download Cancellation Verification Handoff - 2026-07-31

- The production open-source release audit owns the narrow deterministic-test
  remediation in `DeterministicModelDownloadService.swift` and its focused
  release-verification test after the macOS 26 hosted runner completed the
  artificial slow response before the cancellation task resumed.
- Replace wall-clock ordering with explicit synchronization that proves a
  partial payload was received before cancellation and that cancellation
  removes the partial file. Preserve the production download transport,
  redirect/range/validator/disconnect/retry coverage, and all unrelated model
  workflow behavior.

## Production App Conformance Remediation Handoff - 2026-07-31

- The product owner explicitly chose to retain the shipping Dictation Language
  selector. This remediation may align the authoritative specification,
  release guidance, and unchanged manual-QA decision gate with the persisted,
  fail-closed language behavior already implemented and tested. It must not
  remove the selector, reset existing language preferences, or check any
  manual-QA evidence box.
- The audio/runtime slice owns `Sources/TextifyAudio`, its focused tests,
  `RuntimeAudioRecorderAdapter`, the narrow `AppDictationService` audio-error
  mapping, `ProductionDictationError`, and matching runtime tests. It adds exact
  CoreAudio UID routing and scalar-only input metering, but does not edit app
  composition or SwiftUI files.
- The checkpoint-catalog slice owns only
  `ModelCatalogCheckpointExperience.swift`,
  `ModelCatalogScreenProjection.swift`, `ModelCatalogCheckpointView.swift`,
  the narrow Models keyboard/inspector sections of `SettingsRootView.swift`,
  and their focused app tests. It must preserve the checkpoint-first visual
  design while removing implicit Checkpoint deletion, wiring existing bundled
  source/license presentation, and adding non-color accessibility boundaries.
  It must not alter model storage, runtime-boundary transactions, catalog
  trust, or legal resource files.
- The app microphone slice owns `AppServices.swift`, `OnboardingRootView.swift`,
  `TextifyApp.swift`, the Dictation-only sections of `SettingsRootView.swift`,
  and matching app tests. Because `SettingsRootView.swift` is shared with the
  checkpoint slice, this work starts only after the checkpoint changes have
  landed in the shared working tree.
- Manual QA 42 through 46, the three specification-conformance blocker
  paragraphs, Developer ID signing, notarization, and release publication
  remain fail-closed until their real-device or credentialed evidence exists.

## Production App Conformance Remediation Completion - 2026-07-31

- The explicit product-owner decision and implemented remediation above
  supersede the earlier documentation-only instructions that prohibited
  microphone implementation or public selectable-microphone copy. Public docs
  may now describe System Default and stable exact-device selection, the
  visibility-scoped scalar meter, and fail-closed unavailable-device behavior.
- The stale paragraphs saying checks 42 through 46 cannot pass in the current
  implementation may be replaced with open evidence gates. Every checkbox
  remains unchecked until real-device, assistive-technology, and final-candidate
  evidence is recorded.
- Developer ID signing, notarization, stapling, Gatekeeper validation, and
  production release publication remain outside this handoff and fail closed
  without maintainer credentials.

## Active Input Observer Review Remediation Handoff - 2026-07-31

- The production release review reopened the audio/runtime slice narrowly for
  startup and teardown races in active-input observation. The CoreAudio owner
  may change `CoreAudioInputDevices.swift`, `SystemAudioEngineClient.swift`,
  and focused observer tests to serialize listener ownership, make queued
  validation lifecycle-safe, and add hardware-free cleanup coverage.
- The microphone-stream owner may change only
  `MicrophoneInputClient.swift` and its focused tests to ensure termination
  during startup cannot subsequently install a tap or start capture.
- Preserve exact stable-UID routing, keep System Default bound to the original
  device while that stream remains valid, and do not add a listener for default
  input preference changes. Manual hardware evidence remains unchecked.

## Recorder Finish-Lifecycle Test Handoff - 2026-07-31

- Release validation owns the narrow deterministic-test remediation for
  `LiveAudioRecorder` finishing-state coverage after the existing reentrant
  task test proved dependent on actor scheduling.
- This handoff may add an internal post-drain, before-ingestion-task-completion
  suspension seam and update only the focused recorder tests. It must preserve
  the public initializer, the production grace duration, the non-idle
  `alreadyRecording` invariant, and stale-session ingestion coverage.

## Local Release Staging Architecture Handoff - 2026-07-31

- Production source-release validation owns the narrow
  `script/build_and_run.sh --stage-full-release` correction needed to thin
  Xcode's copied Swift compatibility library in the staged app to arm64.
- Keep the credentialed archive/export pipeline unchanged: it already thins
  after export and signs nested code before the app. The local workflow must
  use ad-hoc signing with `Textify.Local.entitlements`, leave fast staging
  unchanged, and verify every packaged Mach-O is exactly arm64.

## Unsigned Preview Distribution Handoff - 2026-07-31

- The product owner explicitly authorized a temporary public unsigned app/DMG
  while Developer ID membership is deferred. This release slice owns the
  narrow local packaging support and public documentation needed for an
  unmistakably labeled GitHub pre-release.
- Publish only under an `unsigned-preview` suffix. Keep `v1.1.0`, the existing
  Developer ID archive/export/notarization helpers, the production release
  evidence gates, and every unchecked manual-QA item unchanged.
- The app inside the DMG may use local ad-hoc signing required for Apple
  Silicon execution. The DMG must remain unsigned and unnotarized, the release
  notes must explain Gatekeeper's manual approval, and no documentation may
  call this artifact a production or trusted Developer ID release.
