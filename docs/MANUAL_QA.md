# Textify V1.1 Manual QA

Run these checks before publishing a V1.1 GitHub Release. Any unchecked item is
release-blocking.

## Release-Blocking Checks

- [ ] 1. Fresh install from stapled DMG on macOS 14+ Apple Silicon.
- [ ] 2. Gatekeeper opens app without override.
- [ ] 3. Dock icon appears by default; closing the main window leaves Textify
  running, and clicking the Dock icon reopens the same window.
- [ ] 4. Menu bar icon appears and Open Textify reopens the same main window.
- [ ] 5. Onboarding installs and verifies `ggml-small.en-q5_1`.
- [ ] 6. Microphone permission flow works.
- [ ] 7. Accessibility permission flow works.
- [ ] 8. Right Command trigger test passes with Accessibility granted.
- [ ] 9. Dictation into TextEdit works.
- [ ] 10. Dictation into Notes or browser text field works.
- [ ] 11. Secure password field blocks insertion.
- [ ] 12. Cancelling during processing does not insert late text.
- [ ] 13. Clipboard is restored after paste when marker remains.
- [ ] 14. Clipboard is not overwritten if changed during paste.
- [ ] 15. Diagnostics export contains no transcript or clipboard content.
- [ ] 16. Launch at Login works if enabled.
- [ ] 17. Sparkle UI/framework is absent.
- [ ] 18. App binary is arm64 only.
- [ ] 19. DMG notarization/stapling validation passes.
- [ ] 20. An app added under Privacy -> Excluded Apps shows the disabled
  overlay while the trigger is held and starts no microphone capture.
- [ ] 21. Switching to another app during processing silently prevents
  insertion into the new frontmost app.
- [ ] 22. Holding dictation to the 60-second cap automatically stops capture
  and proceeds without waiting for trigger release.
- [ ] 23. Each curated fallback trigger can be selected, updates the trigger
  instructions immediately, and passes the trigger test after relaunch.
- [ ] 24. Interrupting a model install preserves only a validated resumable
  partial; Retry sends a byte-range request, resumes without corrupting the
  artifact, and reaches Ready only after model warm-up.
- [ ] 25. The model picker clearly shows tier, languages, download size,
  accelerator, expected finalization, accuracy tradeoff, requirements, and
  license for every signed catalog entry.
- [ ] 26. Install and activate a signed multi-file Parakeet V3 entry on a clean
  machine; diagnostics report `fluid_audio_parakeet` and
  `coreml_neural_engine`, and a real dictation completes with no network access.
- [ ] 27. If Paraformer is published, its first preparation warning is visible;
  after preparation, Mandarin dictation succeeds and diagnostics report
  `fluid_audio_paraformer` and `coreml_neural_engine`.
- [ ] 28. Switching among Whisper, Parakeet, and any published Specialist model
  unloads the previous backend, warms the new one, and never inserts a result
  from an old in-flight session.
- [ ] 29. A failed model switch restores the previously active working model
  and leaves it protected from inactive deletion. Deleting the selected active
  Exact Artifact names the purpose consequence and requires an explicit
  Disable Dictation or Disable Voice Cleaning confirmation.
- [ ] 30. Accelerator verification fails closed when Metal or Neural Engine
  execution is unavailable; Textify never silently accepts a CPU fallback.
- [ ] 31. Install MossFormer2 SE FP16; it becomes the active voice cleaner
  without changing the active transcription model, and noisy dictation is
  cleaned before ASR.
- [ ] 32. Switch among FP32, FP16, and 8-bit cleaners, then disable cleaning;
  each selection persists across relaunch and the ASR selection stays intact.
- [ ] 33. Force the selected cleaner to fail loading or processing; Textify
  shows Raw Audio Fallback, completes dictation with the original audio, and
  diagnostics contain no audio or transcript content.
- [ ] 34. Accept a signed revocation during a dictation with Voice Cleaning;
  the admitted segment finishes with its captured identities, then Dictation
  and/or Voice Cleaning disables before another segment can begin.
- [ ] 35. Accept a signed revocation while affected installs are active and
  queued; every affected attempt becomes Revoked without Retry, unaffected FIFO
  work continues, and retained bytes remain visible until Remove Data.
- [ ] 36. Accept an exact higher-revision signed restoration; the old selection
  does not reactivate, Use/Enable remains unavailable until Verify Integrity
  succeeds, and the verification acknowledgment survives relaunch.
- [ ] 37. Select one installed Exact Artifact and verify its row Delete action
  and Command-Delete show the same Exact Artifact, Checkpoint, measured local
  size, and active consequence. Delete stays unavailable while size
  measurement is pending. Cancel makes no change; selecting a multi-variant
  Checkpoint offers no deletion.
- [ ] 38. Start deleting the Exact Artifact owned by Current Segment. Settings
  shows Finishing Current Dictation, the admitted segment completes, and no new
  segment starts before deletion finishes. Inject rename, permission, and
  partial-removal failures; no success is shown, the Installation Receipt and
  remaining managed bytes stay attributable, and Retry after relaunch
  completes deletion.
- [ ] 39. Make preference persistence fail while switching models and while
  confirming Disable Purpose and Delete. The previous active identity remains
  selected after switch failure; deletion stops before filesystem mutation,
  and relaunch never restores an active identity whose bytes were removed.
- [ ] 40. Run the staged HTTPS catalog endpoint smoke and retain evidence that
  binds the exact catalog revision/signer, revocation revision/signer, and
  candidate app build identity. Confirm the smoke does not fetch model bytes.
- [ ] 41. On a copy of populated v3 Application Support, rehearse application
  withdrawal with the designated rollback bridge. Revoked active content stays
  blocked, active identities do not change, and Installation Receipts, Queue
  Attempts, placements, and all attributed bytes remain owned afterward.

## Supporting Commands

```bash
git diff --check
bash script/release/validate_release.sh
swift test --filter ModelCatalogPublicationTests
```

Use `docs/RELEASING.md` for the archive, model publishing, signing,
notarization, stapling, and GitHub Release flow.

## Local Integration Notes - 2026-07-03

Automated checks run on `master`:

- PASS: `swift test` completed 247 tests with 0 failures.
- PASS: `swift build -c release --arch arm64`.
- PASS: `bash script/release/validate_release.sh`.
- PASS: `./script/build_and_run.sh --verify` launched the staged `.app`; the
  launched `Textify` process was stopped after verification.

Manual checks not run in this integration gate:

- Release-blocking checklist items 1-2 and 19 require a Developer ID signed,
  notarized, stapled DMG from a maintainer machine.
- Release-blocking checklist item 5 requires the published model asset,
  license/provenance sidecars, signed manifest, and manifest signature. The
  GitHub Pages manifest endpoints returned 404 during integration.
- Release-blocking checklist items 6-16 require interactive macOS permissions,
  target apps, real dictation, secure-field checks, cancellation checks,
  clipboard checks, diagnostics export, and Launch at Login verification.

## Pre-Production Readiness - 2026-07-18

Automated checks against the current working tree:

- PASS: `bash script/release/validate_release.sh` completed 259 tests with 0
  failures, built the arm64 Release executable, linted the release plist, and
  passed the release string and architecture policies.
- PASS: `./script/build_and_run.sh --verify` launched the staged app; the
  launched `Textify` process was stopped after verification.
- PASS: clean native Xcode Debug build, native app launch, and ad-hoc Release archive. The archived
  app passes strict code-signature verification, reports version `1.1.0` build
  `1`, is an `LSUIElement`, and contains only arm64 code.
- PASS: the archived binary links neither Sparkle nor Core ML.
- PASS: the live manifest and detached signature match the tracked files, the
  signature validates with the embedded production public key, and a complete
  download of `ggml-small.en-q5_1.bin` matches the manifest SHA-256.
- PASS: release, model, build, and Xcode-project generation shell scripts pass
  syntax validation.

The build is ready to enter pre-production testing. These checks intentionally
remain unchecked until performed by a tester or release maintainer:

- Items 3-16 require interactive macOS UI, permission, real-model onboarding,
  dictation, secure-field, cancellation, clipboard, diagnostics, and Launch at
  Login testing.
- Items 17-18 have automated evidence above but remain part of the manual
  release checklist.
- Items 1-2 and 19 require a Developer ID signed, notarized, stapled DMG. This
  machine has no Developer ID signing identity, so those checks must run on the
  credentialed maintainer machine before publishing.

## Computer Use Session - 2026-07-18

Interactive checks used the final native Xcode Debug app at
`dist/FinalDerivedData/Build/Products/Debug/Textify.app`. The checklist remains
unchecked because the session used an ad-hoc Debug build rather than the final
signed and stapled release artifact.

- BLOCKED (items 1, 2, and 19): no Developer ID signed, notarized, stapled DMG
  was available on this machine.
- SUPERSEDED (former item 3), PASS (items 17 and 18): the tested build used the
  former menu-bar-only default, is an `LSUIElement`, contains no Sparkle
  framework or linked Sparkle library, and is arm64 only.
- HISTORICAL (item 4): the app ran as a menu-bar utility, but inspection of the
  opened status-item menu required a physical click and the handoff was ended
  before it was completed. The tester subsequently reported that the menu is
  dismissed when clicking away, motivating a persistent main-window follow-up.
- PASS (item 5): fresh onboarding displayed the curated
  `ggml-small.en-q5_1` model, verified the installed asset as Ready, and showed
  a complete 190.1 MB installation state.
- PASS (item 6): onboarding requested Microphone permission and refreshed to
  Granted after the tester approved the macOS prompt.
- BLOCKED (item 7): System Settings showed Textify enabled for Accessibility,
  but the ad-hoc Debug process continued to report Denied. Multiple local
  ad-hoc Textify builds had different code requirements and macOS collapsed
  them into one TCC entry, so this needs a stably signed installed build.
- PARTIAL (item 8): the onboarding and Settings trigger tests both detected a
  tester-operated Right Command press and release, including recording start.
  The complete criterion remains blocked by the Accessibility grant mismatch.
- BLOCKED (items 9-14): real cross-app insertion, secure-field behavior,
  processing cancellation, and clipboard restoration/non-overwrite could not
  be exercised safely while the tested process lacked Accessibility trust.
- PASS (item 15): exporting from Advanced Settings created
  `/private/tmp/Textify-Diagnostics-CUA.json`; it contained an empty `files`
  array and no transcript or clipboard content. Cancelling the save panel also
  produced the expected cancellation state.
- PARTIAL (item 16): the Launch at Login control correctly explained that the
  Debug app must be moved to Applications. Actual login-item behavior remains
  blocked until testing an installed release build.

Additional UI evidence:

- PASS: Welcome, Model, Microphone, Accessibility, Trigger Test, and Completion
  onboarding screens rendered coherently and navigated successfully.
- PASS: General, Dictation, Models, Privacy, and Advanced Settings rendered and
  reported consistent model, microphone, and Accessibility states.
- PASS: About Textify reported version `1.1.0 (1)` and the Apache-2.0 notice.
- PASS: original Textify preferences were restored byte-for-byte after the
  session, and the tested Textify process was stopped.

## Hybrid Main Window Computer Use Session - 2026-07-18

Interactive checks used the native Xcode Debug app at
`dist/HybridDerivedData/Build/Products/Debug/Textify.app` after the hybrid Dock
and main-window change.

- PASS: final `bash script/release/validate_release.sh` completed 266 tests with
  0 failures, built the arm64 Release executable, and passed plist, release
  string, and architecture validation. The native Xcode Debug build succeeded.
- PASS (item 3): launching with a legacy `showInDock: false` preference showed
  one main window titled Textify and presented Keep Textify in the Dock as on.
- PASS (item 3): closing the main window left the exact Textify process running
  with no visible window. Opening the already-running bundle through Finder and
  LaunchServices invoked the same app-reopen delegate used by a Dock click and
  restored the retained main window. Computer Use could not address the global
  Dock process directly, so the literal icon click is additionally covered by
  the delegate-policy test.
- PASS with source and automated support (item 4): Open Textify… was present in
  the standard Textify app menu and focused the existing main window. The
  menu-bar-extra action uses the same title and presenter; the global status
  item itself was not addressable through Computer Use.
- PASS: the Dock opt-out switched off and persisted only
  `keepTextifyInDock: false`; switching it back on worked. Automated tests also
  prove a legacy file is atomically rewritten once and a new opt-out survives
  later loads.
- PASS: General, Dictation, Models, Privacy, and Advanced panes remained
  navigable in the retained main window.
- PASS: explicit Quit Textify terminated the process, while closing the window
  did not.
- PASS: the original Textify preferences were restored byte-for-byte and the
  tested process was stopped after the session.

## Production Hardening Verification - 2026-07-19

- PASS: `bash script/release/validate_release.sh` completed 302 tests with zero
  failures, regenerated a stable Xcode project, built the arm64 Release binary,
  and passed plist, icon, category, entitlement, architecture, release-string,
  and shell-syntax policies.
- PASS: the tracked production manifest and detached signature verify with the
  production public key and the exact pinned legacy-manifest migration policy.
- PASS: the live GitHub Pages manifest and signature are byte-for-byte
  identical to the tracked files and verify with the production key. The live
  190,098,681-byte model asset streams to the signed SHA-256
  `bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30`;
  its published MIT license and provenance sidecars are present, and the
  provenance size, hash, source revision, source filename, and mirror metadata
  match the signed manifest.
- PASS: a fresh native Xcode Release archive succeeded. Its ad-hoc signature
  passes strict verification, uses hardened runtime, and contains the
  `com.apple.security.device.audio-input` entitlement without App Sandbox. The
  app is version `1.1.0` build `1`, targets macOS 14+, contains only arm64 code,
  and links neither Sparkle nor Core ML.
- PASS: `./script/build_and_run.sh --verify` launched the fresh staged app. A
  Computer Use inspection of that exact `dist/Textify.app` confirmed the four
  curated trigger choices, model-install controls, and complete Excluded Apps
  surface. The app was stopped afterward; no permission prompt was accepted
  and no model download was started.
- BLOCKED: this machine reports zero valid code-signing identities, and
  `TEXTIFY_DEVELOPMENT_TEAM`, `TEXTIFY_SIGNING_IDENTITY`, and
  `TEXTIFY_NOTARY_PROFILE` are all absent. Therefore no Developer ID export,
  notarized/stapled DMG, or Gatekeeper result can be certified here.

All current release-blocking checkboxes remain unchecked. They must be completed
against the final Developer ID signed and stapled artifact; this local evidence
does not substitute for the release-maintainer QA pass.

## Multi-Model Release Verification - 2026-07-19

- PASS: the final `bash script/release/validate_release.sh` run completed 362
  tests with zero failures (six opt-in hardware/network integration tests
  skipped by the default suite), built the arm64 production package, and passed
  the release plist, catalog-signature, and architecture checks.
- PASS: separate opt-in integrations transcribed fixture audio through all four
  offline runtime families: two Whisper variants on Metal, four Parakeet
  variants on Core ML/ANE, Paraformer on Core ML/ANE, and ReazonSpeech and
  SenseVoiceSmall through the declared sherpa-onnx CPU route. The signed-catalog
  test downloaded and verified all 103 Hugging Face catalog files into isolated
  storage. Runtime/provider validation fails closed instead of silently
  accepting a different route.
- PASS: the reproducible fixed English corpus measured 141.5 ms median final
  latency for Whisper small.en, 367 ms for Whisper Turbo, 66 ms for Parakeet
  V3, 64 ms for V2, and 38.5 ms for 110M. Corresponding WER was 3.33%, 4.29%,
  2.38%, 0.95%, and 2.38%. Turbo's fixed Hindi sample measured 536.5 ms median
  and 20.47% CER. Paraformer's fixed Mandarin sample remained at 66 ms median
  and 5.38% CER on this Apple M4 Max.
- PASS: ReazonSpeech's fixed Japanese sample measured 86 ms median, 413 ms
  p95/max, and 14.61% CER. Its 29-second stress fixture finalized in 954 ms,
  and its silence fixture was rejected by the signed confidence threshold.
- PASS: SenseVoiceSmall measured 10.86% Japanese CER at 138.5 ms median,
  3.81% English WER at 222.5 ms median, and 6.15% Mandarin CER at 128 ms
  median. Automatic Japanese, Mandarin, English, Korean, and Cantonese fixtures
  finalized in 91–159 ms, and the measured digital-silence hallucination is
  marked as no speech by the production runtime.
- PASS: a fresh `script/build_and_run.sh --stage-full-release` produced the
  exact app at `dist/Textify.app`. It contains a valid root
  `Contents/Resources/default.metallib`, contains only arm64 code, and passes
  strict ad-hoc code-signature verification.
- PASS: a SenseVoice smoke loaded the signed dylibs directly from the staged
  app's `Contents/Frameworks`, automatically selected Japanese, produced the
  zero-CER reference sentence, and finalized in 91 ms after a 26 ms warmup.
- PASS: the staged 48 MB arm64 app contains the exact tracked nine-model
  manifest/signature pair and passes strict ad-hoc signature verification. Its
  picker catalog contains Whisper small.en, Specialist Whisper Turbo for
  English/Hindi, Recommended Parakeet V3, Fast Parakeet 110M, Accurate Parakeet
  V2, Specialist Parakeet Japanese, Specialist Paraformer Chinese, and Fast
  ReazonSpeech Japanese, and Accurate SenseVoiceSmall Multilingual. Its two
  arm64 native runtime libraries are separately signed under
  `Contents/Frameworks`, and strict deep verification passes.
- BLOCKED: final `verify_release_artifact.sh`, Developer ID signing,
  notarization/stapling, Gatekeeper verification, and clean-machine manual QA
  require the maintainer's team/signing/notary credentials. The ad-hoc staged
  app is for local testing only.

## Immutable Hugging Face Catalog Verification - 2026-07-19

This verification includes the then-current nine-model catalog.

- PASS: `bash script/release/validate_release.sh` completed 362 tests with zero
  failures and six explicit opt-in hardware/network skips, then built the
  arm64 Release executable and passed catalog, plist, entitlement,
  architecture, release-string, and shell-syntax policies.
- PASS: the tracked signed catalog contains Whisper small.en, Whisper Turbo,
  Parakeet V3, Fast Parakeet 110M, Accurate Parakeet V2, Parakeet Japanese,
  the Paraformer Chinese Specialist, Fast ReazonSpeech Japanese, and Accurate
  SenseVoiceSmall Multilingual. Its
  detached signature verifies with key ID
  `textify-model-manifest-2026-huggingface`, and every one of the 103 selected
  Hugging Face leaves uses an exact lowercase 40-character commit, byte size,
  and SHA-256.
- PASS: an isolated clean-install integration downloaded the Whisper Turbo
  artifact, all 79 Parakeet leaves, all 17 Paraformer leaves, and all four
  ReazonSpeech leaves and both SenseVoiceSmall leaves from their final public
  Hugging Face URLs. It installed every model atomically, loaded it from
  Textify-managed storage, proved the
  intended Metal, ANE, or declared CPU route, and transcribed public English,
  Hindi, Japanese, and Mandarin fixtures. The test completed in 1,300.342
  seconds with zero failures; SenseVoice automatic selection also transcribed
  pinned English, Mandarin, Japanese, Korean, and Cantonese fixtures. Fresh
  downloads and cold Core ML preparation dominated the duration.
- PASS: a fresh Xcode Release build staged the exact app at `dist/Textify.app`.
  The 48 MB arm64 app contains no model weights, contains a valid Whisper
  `default.metallib`, contains the two pinned arm64 sherpa/ONNX Runtime
  libraries, and contains a byte-identical signed catalog pair under
  `Contents/Resources/ModelCatalog/`. Strict deep ad-hoc signature verification
  passes. The copied FunASR model license and SenseVoice attribution are also
  present in `Contents/Resources`.
- PASS: catalog selection tests prove that the bundled baseline survives remote
  failure and cannot be replaced by an older valid remote catalog. Sources are
  selected wholesale; entries are never merged.
- REMAINS MANUAL: checklist items 26-30 must still be performed interactively
  against the final Developer ID signed, notarized, stapled artifact. The local
  clean-install/runtime proof does not certify Gatekeeper, user permissions,
  model switching UI, or cross-app insertion on that final artifact.
- BLOCKED: Developer ID signing, notarization, stapling, Gatekeeper assessment,
  and final manual dictation through every promoted catalog entry still require
  the credentialed release-maintainer machine.

## Benchmark Model Expansion Verification - 2026-07-20

- PASS: the exact Whisper Large V2 and V3 q5_0 downloads matched their signed
  byte sizes and SHA-256 values before inference.
- PASS: both artifacts transcribed all ten fixed OpenSLR utterances through the
  release-built whisper.cpp Metal path. V2 measured 3.33% aggregate WER and
  551 ms median/746 ms p95 release-to-final; V3 measured 3.81% aggregate WER
  and 542.5 ms median/728 ms p95.
- PASS: the tracked Ed25519 signature and production catalog policy verify for
  the expanded eleven-model catalog. Its 105 Hugging Face leaves are exact
  commit-pinned URLs with byte sizes and SHA-256 values.
- PASS: `script/release/validate_release.sh` completed 376 tests with zero
  failures and seven explicit native/network skips, built the arm64 Release
  executable, and passed catalog, plist, entitlement, architecture,
  release-string, native-runtime, and shell-syntax policies.

## MLX Whisper Large V3 Turbo Verification - 2026-07-20

- PASS: `bash script/release/validate_release.sh` completed 403 tests with zero
  failures and eight explicit opt-in native/network skips, verified the signed
  15-model catalog, built the arm64 SwiftPM Release executable, and passed the
  native-runtime, bundled-license, and MLX Metal-library checks.
- PASS: the benchmark package's three tests passed. The exact
  `mlx-community/whisper-large-v3-turbo` revision and the exact original-model
  tokenizer assets matched all ten signed byte sizes and SHA-256 values.
- PASS: native inference used MLX Metal and the fully local ten-file directory.
  The first fixed OpenSLR clip transcribed at 0 WER; the complete 210-word
  corpus measured 3.33% aggregate WER, 321.5 ms median, 416 ms p95/max, and
  1,748,041,728 bytes peak resident memory.
- PASS: `script/build_and_run.sh --stage-full-release` produced the exact app at
  `dist/Textify.app`. Its tracked catalog and signature are byte-identical,
  both Metal libraries are valid, the MLX library matches its pinned SHA-256,
  the app and five explicitly packaged native binaries are arm64, no model
  weights are bundled, and strict deep ad-hoc signature verification passes.
- BLOCKED: Developer ID signing, notarization/stapling, Gatekeeper assessment,
  and final clean-machine interactive dictation still require the credentialed
  release-maintainer workflow. This ad-hoc staged app is for local testing.

## Qwen3-ASR MLX And GGUF Verification - 2026-07-20

- PASS: both nine-file MLX directories and all six requested GGUF files matched
  the final signed catalog's immutable revision, exact byte size, and SHA-256.
- PASS: all eight entries transcribed the complete ten-utterance fixed English
  corpus on the Apple M4 Max through their required Metal backends. MLX 0.6B
  and 1.7B measured 3.20% and 1.83% WER; the GGUF variants measured
  3.33–3.65% WER with 156.5–317.5 ms median finalization.
- PASS: both MLX variants and the 0.6B/1.7B Q5_K_M GGUF routes transcribed all
  ten fixed Hindi fixtures with automatic language detection. The GGUF routes
  measured 11.36%/10.05% and 10.00%/7.00% WER/CER respectively.
- PASS: `swift test` and `script/release/validate_release.sh` each completed
  409 tests with zero failures and eight explicit opt-in native/network skips.
  The standalone benchmark package's three tests also passed.
- PASS: the final detached signature verifies the 23-model catalog with key ID
  `textify-model-manifest-2026-huggingface`; structural tests cover every Qwen
  runtime variant, artifact layout, automatic-language contract, size, hash,
  and measured picker presentation.
- PASS: `script/build_and_run.sh --stage-full-release` produced the arm64 app
  at `dist/Textify.app`. It contains byte-identical catalog/signature files,
  the verified MLX Metal library and transcribe.cpp runtime, no model weights,
  and passes strict deep ad-hoc code-signature verification.
- BLOCKED: Developer ID signing, notarization/stapling, Gatekeeper assessment,
  and final clean-machine interactive model switching require the credentialed
  release-maintainer workflow. This ad-hoc staged app is for local testing.

## Parakeet TDT And Nemotron MLX/GGUF Verification - 2026-07-20

- PASS: the three exact MLX directories and nine exact F16, Q8_0, and Q5_K_M
  GGUF files matched their immutable source revisions, signed byte sizes, and
  SHA-256 hashes. The Handy repositories publish F16 rather than BF16.
- PASS: all twelve choices transcribed the complete fixed ten-utterance,
  210-word English corpus on the Apple M4 Max through their required native
  Metal backends. Aggregate WER ranged from 0.48% to 3.33%, median
  release-to-final latency ranged from 67 to 137 ms, and every p95 remained
  under Textify's 700 ms target.
- PASS: the signed catalog contains 35 models and structural tests cover every
  new runtime variant, language policy, artifact layout, revision, byte size,
  and SHA-256. Nemotron is deliberately presented as batch dictation without a
  live-streaming claim.
- PASS: `swift test` and `script/release/validate_release.sh` each completed
  414 tests with zero failures and eight explicit opt-in native/network skips.
  The standalone benchmark package's three tests also passed.
- PASS: `script/build_and_run.sh --stage-full-release` produced the arm64
  ad-hoc app at `dist/Textify.app`; the staged app contains the verified
  35-model catalog/signature, required MLX and transcribe.cpp Metal runtimes,
  notices, no model weights, and passed the release artifact checks.
- BLOCKED: Developer ID signing, notarization/stapling, Gatekeeper assessment,
  and final clean-machine interactive model switching require the credentialed
  release-maintainer workflow. This ad-hoc staged app is for local testing.

## Adaptive Model Catalog Accessibility Audit - 2026-07-24

Interactive inspection used the native Xcode Debug app at
`dist/DerivedData/Build/Products/Debug/Textify.app`. This is a local
accessibility audit, not release certification of a signed and stapled build.
VoiceOver was temporarily enabled in macOS Accessibility settings, the live
catalog checks below were repeated with it active, and its original off state
was restored after the audit.

- PASS: Settings navigation and the Transcription Models destination expose
  stable labels. The catalog exposes its Model, Quality, Speed, Features,
  State, and Action headers plus Family and Exact Artifact rows with outline
  level and logical row position/count.
- PASS: Arrow Down moved accessibility focus from Whisper small.en to Whisper
  large-v2. Return selected that exact artifact and opened an inspector whose
  identity, operational requirements, benchmark evidence, provenance, license,
  and local-file state were readable in the macOS accessibility tree.
- PASS: Right expanded Whisper large-v3-turbo from a two-variant collapsed
  Checkpoint into two outline-level-3 Exact Artifacts and updated the logical
  count from 35 to 37; Left restored the collapsed state and count. End reached
  row 35 of 35 and Home returned to the first Family heading.
- PASS: entering `Canary` in Search models reduced the logical catalog from 35
  rows to one Family and one Exact Artifact while preserving a deterministic
  selection and inspector while VoiceOver was active. Installed scope exposed
  a readable five-field storage summary and the selected artifact's measured
  on-disk state.
- PASS: Downloads presented a coherent empty-state layout. Its explicit
  `No Downloads` label, explanatory value, and stable identifier were added
  after the initial tree inspection found that SwiftUI's visual
  `ContentUnavailableView` did not expose those children reliably.
- PASS with automated state fixtures: terminal completion, failure,
  cancellation, deletion, activation, and revocation announcements are
  concise and emitted once; incremental progress stays queryable without
  announcing each tick; selection removal moves to the nearest surviving row;
  pinned reveal, disclosure, page/home/end navigation, off-screen selection,
  and Command-Delete share deterministic pure-state tests.
- PASS with automated presentation checks: accessibility text sizes force
  labeled compact fields; Reduce Motion, Reduce Transparency, Increase
  Contrast, and Differentiate Without Color produce the intended presentation
  decisions. The Base-English string catalog retains primary, overflow,
  Downloads, verification, and destructive-action labels.
- PASS with live localization stress: a temporary copy of the same Debug app,
  using an isolated bundle identifier, ran once with
  `NSDoubleLocalizedStrings` and once with forced right-to-left direction. The
  doubled catalog kept Search, scope, Filters, Downloads, More actions, row
  actions, and six individually exposed headers reachable. The RTL pass
  mirrored the sidebar, toolbar, catalog columns, rows, and action order
  without clipping critical controls. The isolated preferences were deleted
  and the temporary app was moved to Trash after the audit.
- PASS: selecting an installed artifact exposed Delete while VoiceOver was
  active. Its confirmation named Canary-Qwen 2.5B's Exact Artifact,
  Checkpoint, and measured 1.74 GB local size; the audit cancelled it and
  preserved the selected row and installed data.
- PASS: fresh onboarding was audited with VoiceOver after backing up
  `settings.json` and temporarily changing only `onboardingCompleted`.
  Welcome, model selection/verification, Microphone, Accessibility, and
  trigger-test steps exposed their progress, status, explanatory copy, and
  actions without requesting permissions or starting a trigger test. The app
  was stopped and the original settings file restored byte-for-byte; its
  SHA-256 returned to
  `1206b08cbfcf53c33d7f610e1fb1f5aa9d9c3189d71b3942f3184b90d57bf265`.
- SKIPPED by explicit implementation-session direction: the remaining live
  revoked-row VoiceOver pass. No installation was started, no installed
  artifact was revoked, and no deletion was accepted, so the existing
  installed models and user data were not modified. Their semantics and
  focus/announcement transitions are covered by the focused automated fixtures
  above.

## Large Catalog Performance Verification - 2026-07-25

The Models destinations now derive four independently versioned immutable
layers away from the main actor: Catalog Index, Eligibility Index, Local-State
Overlay, and Query Result. Release builds retain `ModelCatalog` signposts for
catalog indexing, eligibility, local overlay projection, query derivation,
publication, and lazy row visibility/recycling.

Automated release stress is opt-in so the ordinary suite does not allocate the
10,000-artifact fixture:

```bash
TEXTIFY_RUN_CATALOG_STRESS=1 \
  swift test -c release \
  --filter ModelCatalogDerivationTests.testReleaseStressCatalogBudgets
```

- PASS: a 500-Checkpoint/2,000-Exact-Artifact fixture enforces search and
  filter/scope/sort p95 under 250 ms, with a submitted warm search under
  100 ms. The Apple M4 Max Release run measured 85.9 ms search p95 and 72.2 ms
  filter/scope/sort p95.
- PASS: an approximately 2,000-Checkpoint/10,000-Exact-Artifact fixture
  derives without a crash, hang, incorrect row count, or query-index rebuild
  across repeated byte-progress mutations. Exact search and installed-scope
  identities remain correct, and 30 repeated queries after warmup measured
  0.0 MiB resident-memory growth.
- PASS: 10,000-artifact byte-progress publication enforces p95 under 100 ms
  while Catalog Index, Eligibility Index, and Query Result versions remain
  unchanged. The same Release run measured 43.0 ms progress-publication p95.
- PASS with focused state fixtures: collapsed Checkpoints construct no child
  hierarchy rows; routine publication retains surviving selection, expansion,
  focus, and semantic scroll anchor state; removed Exact Artifact selection
  falls back to its surviving Checkpoint before next, previous, or first row.

Before release certification, capture cold, warm, and VoiceOver Instruments
traces on the oldest supported Apple Silicon configuration. Use the
`ModelCatalog` points of interest to verify that `row-visible` remains bounded
to the viewport plus accessibility overscan, `row-recycled` follows scripted
scrolling, no unexplained main-thread stall exceeds 100 ms, and fewer than one
percent of frames exceed two display frames. Store the resulting trace bundle
with the release evidence; do not commit machine-specific `.trace` data.

- BLOCKED for this implementation session: the available Apple M4 Max is not
  the oldest supported Apple Silicon configuration, so the required M1 cold,
  warm, and VoiceOver trace capture remains a release-maintainer hardware gate.

## Catalog Publication And Rollback Verification - 2026-07-25

- PASS: the focused publication tests bind catalog revision/hash/signer,
  revocation revision/hash/signer, candidate-app bundle identity and executable
  digest, and accepted sticky revocation/restoration evidence. The production
  verifier accepts only the same embedded trust table as the app. Tests reject
  lower revisions, corrections at an unchanged revision, mutable revocation
  records, and restorations that do not repeat an exact prior target.
- PASS: the v3 rollback rehearsal loads persisted Installation Receipts and
  Queue Attempts plus settings, trusted catalog, and sticky revocation archives
  from a real temporary Application Support layout. Receipt, queue, and active
  identity inputs are frozen pre-bridge fixtures. The bridge strictly verifies
  a candidate app, matches its derived identity to publication evidence,
  retains artifact/storage/attempt identities and Curated placement, and proves
  a revoked active artifact remains blocked. Evidence retains state and
  owned-file SHA-256 values plus byte count; exact state and model bytes are
  unchanged after rehearsal.
- PASS: `bash script/release/validate_release.sh` completed 766 tests with 12
  expected opt-in skips and zero failures, verified the tracked signed
  43-model v3 catalog, built the arm64 Release executable, and passed release
  metadata, native dependency, and shell-syntax checks.
- PARTIAL live endpoint evidence: anonymous HTTPS fetched the current public
  catalog and detached signature without fetching model bytes. The signature
  names `textify-model-manifest-2026-huggingface`, but the public body is the
  older schema-v2 revision `2026-07-23T12:30:59Z`; the new publication gate
  correctly rejects it because it lacks v3 installation bounds.
- BLOCKED external publication gate: the public `revocations.json` and
  `revocations.json.sig` endpoints currently return HTTP 404. A credentialed
  maintainer must publish the reviewed signed revocation baseline and staged
  v3 catalog, then run
  `script/models/smoke_model_catalog_endpoint.sh` and retain its evidence
  before checking release item 40.

## Final Release Evidence Sign-Off

- [ ] Retain the release commit, signed build hashes, catalog/revocation
  revisions, and signer identities.
- [ ] Attach schema, property, transition, malformed-input, migration, fault
  campaign, and seeded soak results.
- [ ] Attach semantic UI evidence for hierarchy, selection, comparison,
  actions, scopes, query, pinned reveal, inspector, Downloads, onboarding,
  trust states, revocation, and deletion.
- [ ] Attach genuine manual VoiceOver, Full Keyboard Access, supported text
  scaling, Reduce Motion, Increase Contrast, and Reduce Transparency results.
- [ ] Attach 30 or more warm measurements and three cold launches from a real
  oldest-supported M1-class device and a later supported device.
- [ ] Exercise every signed catalog Compute Route on at least one real
  supported device and attach the result.
- [ ] Attach security review, publication report, diagnostics review,
  packaging validation, and rollback rehearsal.
- [ ] Record zero open Critical/High defects and no Medium defect in a
  trust-critical domain; attach a product-and-engineering waiver and safe
  workaround for any other Medium defect.
- [ ] Record independent review of trust, migration, revocation, and
  destructive filesystem behavior.
- [ ] Record two distinct human approvals.
- [ ] Run `script/release/assemble_release_evidence.sh` and retain the validated
  bundle beside its attachments.

The current implementation session cannot check the real-device, manual
accessibility, credentialed publication, independent human review, or two-human
approval boxes. The evidence validator intentionally rejects placeholders for
those release gates.
