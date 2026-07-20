# Textify

Textify is a native macOS Dock and menu-bar dictation app for quickly turning
speech into typed text with offline, hardware-accelerated models.

## Requirements

- macOS 14 Sonoma or later.
- Apple Silicon Mac. V1.1 is arm64 only; Intel Macs are not supported.
- Microphone permission for recording while you hold the dictation trigger.
- Accessibility permission for text insertion and the global Right Command trigger.

Textify V1.1 is distributed as a direct GitHub Release DMG. It is not available
through the Mac App Store.

V1.1 user installs require the GitHub Release DMG and network access for the
model selected during setup. The app carries a signed catalog but no model
weights.

## Installation

1. Download the latest `Textify-*-arm64.dmg` from GitHub Releases.
2. Open the DMG and drag Textify to Applications.
3. Launch Textify from Applications and complete onboarding.
4. Install a model from the signed catalog when onboarding asks for it.

Textify keeps a main window in the Dock for setup and settings, while its
menu-bar icon remains available for quick access. Closing the main window keeps
dictation running; reopen it from the Dock or the menu-bar Open Textify action.

Sparkle automatic updates are deferred in V1.1. To update Textify, download the
next GitHub Release DMG manually and replace the installed app.

## Dictation

Hold Right Command to dictate. Textify records while the key is held, transcribes
the completed recording locally, then inserts the final text into the active
text field when possible. It intentionally does not show live partial captions;
the optimization target is near-instant final text after release.

The runtime supports six offline engine families on Apple Silicon:

- Whisper GGML/GGUF through whisper.cpp and Metal, including verified custom
  model import;
- NVIDIA Parakeet through FluidAudio, Core ML, and Apple Neural Engine;
- Parakeet RNNT/TDT, Nemotron 3.5 ASR, Cohere Transcribe, Whisper Turbo, and
  Qwen3-ASR through MLX Audio Swift and Metal;
- Canary-Qwen, Parakeet TDT, Nemotron 3.5 ASR, and Qwen3-ASR GGUF through the
  isolated transcribe.cpp Metal runtime;
- Paraformer-large Chinese through FluidAudio, Core ML, and Apple Neural
  Engine; and
- ReazonSpeech K2 V2 and SenseVoiceSmall through pinned sherpa-onnx and ONNX
  Runtime libraries on the Apple Silicon CPU.

The shipped signed catalog offers 35 choices: Whisper small.en;
Experimental Whisper Large V2 and V3; Whisper Large V3 Turbo for measured
English/Hindi use plus a separate Experimental MLX Turbo choice for English;
Accurate Canary-Qwen 2.5B for English; four Core ML Parakeet variants plus
Experimental Parakeet RNNT 1.1B and Cohere Transcribe; the Paraformer Chinese
specialist; compact Fast ReazonSpeech Japanese; and Accurate SenseVoiceSmall
with automatic English, Mandarin, Cantonese, Japanese, and Korean selection;
plus Experimental Qwen3-ASR 0.6B and 1.7B choices in MLX 8-bit and GGUF BF16,
Q8_0, and Q5_K_M formats; and Experimental Parakeet TDT V2, Parakeet TDT V3,
and Nemotron 3.5 ASR in native MLX plus GGUF F16, Q8_0, and Q5_K_M formats.
V3 and Nemotron use automatic language detection. Nemotron remains a
whole-recording batch route in Textify and does not expose live partials.
Whisper small.en downloads from an immutable Textify release asset; the other
Whisper, Core ML, MLX, Canary-Qwen, ReazonSpeech, and SenseVoice model files
download from exact commit-pinned public Hugging Face files. Every file is
checked against its signed byte size and SHA-256 before it can become active.
Textify does not keep transcript history or use proprietary/cloud ASR.

Recording length follows the active model's declared capability. Most Whisper
and Parakeet entries allow the app-wide 60-second maximum. Paraformer,
ReazonSpeech, and SenseVoice use shorter safe windows, and Textify stops
recording at each model-specific limit.

## Privacy

Textify processes audio locally and does not keep transcript history or retain
raw audio after dictation. Clipboard use is limited to snapshot, paste, and
restore during insertion. See `PRIVACY.md` for the full V1.1 privacy statement.

## Development

Build and test:

```bash
swift build
swift test
```

Run the hybrid Dock and menu-bar app:

```bash
./script/build_and_run.sh
```

Verify the app bundle launches:

```bash
./script/build_and_run.sh --verify
```

## License

Textify is licensed under the Apache License 2.0. See `LICENSE`.

Third-party acknowledgments and notices are in `ACKNOWLEDGMENTS.md`,
`THIRD_PARTY_NOTICES.md`, and `THIRD_PARTY_LICENSES/`.
