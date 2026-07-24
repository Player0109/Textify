# Changelog

## Unreleased

- Added optional MossFormer2 SE FP32, FP16, and 8-bit voice cleaning on MLX
  Metal before every ASR backend, with independent model selection, in-memory
  16/48 kHz conversion, FP16 auto-enable after install, and raw-audio fallback.
- Added a signed multi-model catalog, resumable atomic multi-file installs,
  switching, deletion, rollback, and verified custom Whisper GGML/GGUF import.
- Added engine-aware offline transcription with Whisper/Metal, native
  FluidAudio Parakeet and Paraformer/Core ML Neural Engine backends, and a
  pinned sherpa-onnx/ONNX Runtime CPU backend.
- Added accelerator verification that fails closed on silent GPU/ANE fallback,
  model-specific recording limits, reproducible WER/CER benchmarks, and
  support-tier guidance in the model picker.
- Added a bundled signed nine-model catalog with immutable commit-pinned
  Hugging Face downloads, per-file size/SHA-256 verification, signed catalog
  anti-downgrade selection, and Keychain-backed manifest signing.
- Added signed model-revocation enforcement across current dictation segments,
  active selections, persistent install queues, retained partial data, and
  exact restoration records that require fresh integrity verification.
- Added exact-artifact deletion with shared runtime-boundary serialization,
  current-dictation draining, purpose-aware confirmation, and retryable
  filesystem recovery that removes receipts only after managed bytes.
- Added adaptive model-management layouts, deterministic keyboard browsing,
  explicit catalog hierarchy/table semantics, stable accessibility focus,
  queryable download progress, and concise lifecycle announcements.
- Added accessibility-display preference support and Base-English string
  catalog coverage with pseudolocalization and right-to-left stress checks for
  critical model-management labels.
- Added Fast Parakeet TDT-CTC 110M and Accurate Parakeet V2 English choices,
  both using the existing offline Core ML/Neural Engine runtime.
- Added Parakeet Japanese as a Specialist choice after a fixed public-corpus
  CER/latency benchmark and clean signed-catalog validation.
- Added compact ReazonSpeech K2 V2 as a Fast Japanese choice after CPU/Core ML,
  fixed-corpus, silence, long-utterance, and staged-app runtime validation.
- Added SenseVoiceSmall as an Accurate five-language choice after automatic
  English, Mandarin, Cantonese, Japanese, and Korean validation; its fixed
  Japanese sample is Textify's most accurate promoted Japanese result.
- Evaluated Qwen3-ASR 0.6B, Omnilingual ASR 300M, and Dolphin Small through the
  reusable sherpa-onnx boundary and explicitly deferred them on measured
  latency, memory, or accuracy rather than exposing unqualified model choices.
- Added Whisper Large V3 Turbo q5_0 as an English/Hindi Specialist after fixed
  English and Hindi corpus benchmarks and Metal GPU validation.
- Added exact MLX and GGUF Metal choices for Parakeet TDT V2, Parakeet TDT V3,
  and Nemotron 3.5 ASR, with immutable hashes, measured picker guidance, and
  explicit F16 substitution where the GGUF sources do not publish BF16.
- Kept the interaction as full recording followed by one near-instant final
  result; live partial transcription and cloud ASR remain excluded.

## V1.1 - 2026-07-03

- Added the production menu bar dictation path for macOS 14+ Apple Silicon Macs.
- Added Right Command hold-to-dictate with local whisper.cpp transcription.
- Added onboarding for the single curated `ggml-small.en-q5_1` model download.
- Added release privacy, acknowledgments, third-party notices, and manual QA
  documentation.
- Deferred Sparkle automatic updates. V1.1 updates are manual GitHub Release DMG
  installs.

The original V1.1 release did not support Intel Macs, Mac App Store
distribution, transcript history, multi-language model selection, arbitrary
model loading, or per-app profiles. The Unreleased work above supersedes only
the model-selection boundary.
