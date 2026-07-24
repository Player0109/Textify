# Textify Implementation Coordination

This file records cross-agent handoffs during implementation.

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
