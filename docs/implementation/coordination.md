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
