# Textify

Textify is a native macOS menu bar dictation app for quickly turning spoken
English into typed text.

## Requirements

- macOS 14 Sonoma or later.
- Apple Silicon Mac. V1.1 is arm64 only; Intel Macs are not supported.
- Microphone permission for recording while you hold the dictation trigger.
- Accessibility permission for text insertion.
- Input Monitoring permission for the global Right Command trigger.

Textify V1.1 is distributed as a direct GitHub Release DMG. It is not available
through the Mac App Store.

V1.1 user installs require both the GitHub Release DMG and the signed model
manifest/model assets to be published. Until those release assets are live,
local builds are development builds.

## Installation

1. Download the latest `Textify-*-arm64.dmg` from GitHub Releases.
2. Open the DMG and drag Textify to Applications.
3. Launch Textify from Applications and complete onboarding.
4. Install the curated `ggml-small.en-q5_1` model when onboarding asks for it.

Sparkle automatic updates are deferred in V1.1. To update Textify, download the
next GitHub Release DMG manually and replace the installed app.

## Dictation

Hold Right Command to dictate. Textify records while the key is held, transcribes
locally with whisper.cpp, then inserts the final text into the active text field
when possible.

Textify V1.1 supports one curated English model download:
`ggml-small.en-q5_1`. It does not support arbitrary model loading,
multi-language model selection, per-app profiles, or transcript history.

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

Run the menu bar app:

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
