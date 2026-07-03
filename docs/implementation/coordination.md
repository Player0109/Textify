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

## V1.1 Task 10 Production UI Carry-forward
- The onboarding and settings model panes now call through the real `ModelDownloader`/`ModelInstaller` path with embedded manifest URLs and a trusted model-manifest key set for `ggml-small.en-q5_1`.
- Release remains blocked until the model publishing task creates and deploys the signed manifest, signature, and GitHub Release model asset. As of Task 10 verification, `https://player0109.github.io/Textify/models/manifest.json` and `manifest.json.sig` still return 404.
