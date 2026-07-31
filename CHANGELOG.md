# Changelog

## [1.1.0 Unsigned Preview 1] - 2026-07-31

- Published the current Apple Silicon app in an explicitly labeled, unsigned
  and unnotarized GitHub pre-release DMG.
- Kept the app locally ad-hoc signed for Apple Silicon execution and documented
  the expected one-time Gatekeeper approval.
- Reserved `v1.1.0` for the later Developer ID signed, notarized production
  release.

## 1.1.0 - Unreleased

Planned first public app release.

- Added native Dock and menu-bar dictation for macOS 14 or later on Apple
  Silicon, with Right Command hold-to-dictate and local final-text insertion.
- Added guided Microphone and Accessibility permission setup, model onboarding,
  Launch at Login, diagnostics export, excluded apps, vocabulary, and
  replacement pairs.
- Added persistent System Default or exact-device microphone selection,
  visibility-scoped live input metering, and fail-closed handling when a saved
  microphone is unavailable.
- Added a bundled signed 42-entry model catalog: 39 transcription choices and
  three independently selectable MossFormer2 SE voice-cleaning choices.
- Added resumable, atomic multi-file model installs; switching; exact-artifact
  deletion; rollback-safe receipts; and verified custom Whisper GGML/GGUF
  import.
- Added offline transcription through whisper.cpp/Metal, FluidAudio/Core ML,
  MLX Audio/Metal, transcribe.cpp/Metal, and sherpa-onnx/ONNX Runtime.
- Added immutable Textify Release and commit-pinned Hugging Face downloads with
  signed byte-size, SHA-256, license, and provenance verification before
  activation.
- Added accelerator verification that fails closed on silent GPU or Neural
  Engine fallback, model-specific recording limits, reproducible WER/CER
  benchmarks, and explicit support-tier guidance.
- Added signed model-revocation enforcement across active dictation, installed
  selections, persistent queues, retained partial data, and restoration
  records.
- Added multilingual automatic and explicit-language routing for eligible
  models, while failing closed when a selected language is unsupported.
- Added adaptive, keyboard-accessible model management with persistent catalog
  navigation, queryable progress, benchmark details, and lifecycle
  announcements.
- Added explicit Family, Checkpoint, and Exact Artifact semantics, exact-only
  destructive keyboard routing, working source and bundled-license actions,
  and stronger accessibility appearance adaptations in the checkpoint catalog.
- Added floating recording-icon position and scale controls with visible-screen
  clamping.
- Added optional MossFormer2 SE FP32, FP16, and 8-bit in-memory voice cleaning
  before every ASR backend, with FP16 auto-enable and raw-audio fallback.
- Added Fast and Accurate English and Japanese choices, a Chinese Specialist,
  multilingual SenseVoice, and Experimental Qwen3-ASR, Parakeet, Nemotron,
  Cohere, Canary-Qwen, Granite Speech, Voxtral, and MOSS Transcribe-Diarize
  routes.
- Retired the evaluated Omnilingual ASR route from the shipped catalog and
  added crash-safe cleanup for previously managed copies.
- Kept all transcription and optional voice cleaning local. Textify has no
  accounts, analytics, cloud ASR, transcript history, or bundled model weights.
- Deferred automatic updates. Textify 1.1 updates are manual, notarized GitHub
  Release DMG installs.

[1.1.0]: https://github.com/Player0109/Textify/releases/tag/v1.1.0
[1.1.0 Unsigned Preview 1]: https://github.com/Player0109/Textify/releases/tag/v1.1.0-unsigned-preview.1
