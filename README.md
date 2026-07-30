# Textify

Native, offline dictation for Apple Silicon Macs.

[![CI](https://github.com/Player0109/Textify/actions/workflows/ci.yml/badge.svg)](https://github.com/Player0109/Textify/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Player0109/Textify)](LICENSE)

## What it does

Textify records while you hold the dictation trigger, transcribes the completed
recording locally, and inserts the final text into the focused text field. It
runs as both a Dock app and a menu-bar app, keeps no transcript history, and
does not use cloud speech recognition.

Textify intentionally produces one final transcript after recording rather than
live partial captions. Closing the main window leaves dictation running; reopen
it from the Dock or the menu-bar **Open Textify** action.

## Requirements

- macOS 14 Sonoma or later.
- An Apple Silicon Mac. Textify 1.1 is arm64 only; Intel Macs are unsupported.
- Microphone permission for recording.
- Accessibility permission for the global Right Command trigger and text
  insertion.
- Network access when downloading the app or a model. Dictation itself is
  offline after a model is installed.

Production builds are distributed as notarized GitHub Release DMGs. Textify is
not available through the Mac App Store.

## Installation

The Textify 1.1.0 production app has not been published yet. The existing
`models-v1` GitHub Release contains model assets for Textify's signed catalog,
not an installable app.

When the 1.1.0 app release is available:

1. Download `Textify-1.1.0-arm64.dmg` and its `.sha256` file from the
   [Textify 1.1.0 release](https://github.com/Player0109/Textify/releases/tag/v1.1.0).
2. Optionally verify the download:

   ```bash
   shasum -a 256 -c Textify-1.1.0-arm64.dmg.sha256
   ```

3. Open the DMG and drag Textify to Applications.
4. Launch Textify from Applications.

Automatic updates are deferred in Textify 1.1. To update, download the next
GitHub Release DMG and replace the installed app.

## Getting started

1. Complete the Microphone and Accessibility permission steps in onboarding.
2. Choose and install a transcription model from the bundled signed catalog.
3. Focus a text field, hold Right Command, speak, and release the key.
4. Use Settings to change the model, microphone, language, or recording-overlay
   placement.

Textify stops recording at the active model's declared safe limit. Most
catalog entries allow the app-wide 60-second maximum; some models use a shorter
limit.

## Models

Textify 1.1 ships a signed catalog of 42 choices: 39 transcription models and
three optional MossFormer2 SE voice-cleaning models. The catalog includes
Whisper, Parakeet, Paraformer, ReazonSpeech, SenseVoice, Qwen3-ASR, Nemotron,
Granite Speech, Voxtral, MOSS Transcribe-Diarize, and other eligible local
routes across whisper.cpp, FluidAudio/Core ML, MLX Audio, transcribe.cpp, and
sherpa-onnx.

Textify does not bundle speech model binaries. During onboarding or from
Settings, Textify can download curated model files from immutable Textify
GitHub Release assets or exact commit-pinned public Hugging Face files. Every
file is checked against the signed catalog's byte size and SHA-256 before it
can become active. Custom model import is limited to supported Whisper
GGML/GGUF files and remains local.

Support tiers are curator guidance, not benchmark scores. Some catalog entries
are explicitly Experimental or Unrated. Exact model capabilities, runtime
requirements, sources, revisions, licenses, sizes, checksums, and provenance
are documented in [the curated model guide](docs/models/curated-models.md), the
[third-party notices](THIRD_PARTY_NOTICES.md), and the signed
[model manifest](models/manifest.json).

Model suggestions are accepted through GitHub issues only. Textify does not
accept model binary pull requests or issue attachments.

## Privacy

Audio and dictated text stay on the Mac. Textify does not have accounts,
analytics, crash reporting, transcript history, or an automatic upload path for
dictated content. Clipboard insertion is brief and restored on a best-effort
basis.

See [PRIVACY.md](PRIVACY.md) for the full privacy statement.

## Contributing

Bug reports, feature requests, and model suggestions are welcome through
[GitHub Issues](https://github.com/Player0109/Textify/issues). External pull
requests are not accepted at this time; see
[CONTRIBUTING.md](.github/CONTRIBUTING.md) for the current contribution policy.
Report vulnerabilities privately as described in
[SECURITY.md](.github/SECURITY.md).

Build and test locally:

```bash
swift build
swift test
```

Run the development app:

```bash
./script/build_and_run.sh
```

Verify a staged app bundle:

```bash
./script/build_and_run.sh --verify
```

Release builds require the additional signing, notarization, and evidence gates
in [docs/RELEASING.md](docs/RELEASING.md).

## License

Textify is licensed under the [Apache License 2.0](LICENSE).

## Acknowledgments

Textify builds on open-source speech runtimes and model work from many
communities. See [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md),
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and
[THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES/) for attribution, provenance, and
copied license texts.
