# Textify Curated Models

Textify V1.1 publishes one curated production model. The app downloads model
bytes only from Textify-controlled GitHub Release assets and validates those
bytes against the signed model manifest.

## Balanced - Whisper small.en q5_1

- Model id: `ggml-small.en-q5_1`
- Display name: `Balanced - Whisper small.en q5_1`
- File: `ggml-small.en-q5_1.bin`
- Language: English only
- Source: `ggerganov/whisper.cpp`
- Source file: `ggml-small.en-q5_1.bin`
- Textify asset URL shape: `https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.bin`

The manifest `sha256` value must be computed from the exact uploaded Textify
GitHub Release asset bytes, not from an upstream URL, local placeholder, or a
file before final upload verification.

```bash
shasum -a 256 ggml-small.en-q5_1.bin
```

Release manifests must not ship with placeholder checksums, placeholder sizes,
or non-Textify download URLs. If the model bytes change, publish a new immutable
release asset URL and sign a new manifest for those bytes.
