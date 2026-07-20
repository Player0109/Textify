# Parakeet RNNT 1.1B Catalog Benchmark - 2026-07-20

This report records Textify's promotion evidence for the exact Parakeet RNNT
1.1B model requested from the supplied Artificial Analysis comparison. It does
not generalize the English measurements to other languages.

## Immutable inputs

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `config.json` | 37,318 | `1d84911a9139a9f56a43cfc8d46400e125bcade8a39508d604492fe291c8f40b` |
| `model.safetensors` | 4,282,246,596 | `d2c370b3728c4c3b318d814574e87da144a9484ce6b3c4457a6ed5889bb007e1` |
| `tokenizer.model` | 259,162 | `8f279c3951a1c280a99a108d07b429bd98c03c94ecd0270748bd7affca9c0817` |
| `tokenizer.vocab` | 11,383 | `dc8f48909c2d3a0374f45b7478226d26a7de16bbc5334448a8e989f4538384d1` |
| `vocab.txt` | 5,301 | `27277f2a7176399c7acc178e394cec5e6a575657db9aae9e9e609cb004e9f350` |

The 4,282,559,760-byte directory came from
`mlx-community/parakeet-rnnt-1.1b` revision
`7f399a0d3442123deae9194e71f5c984b2879efa`. The model is CC-BY-4.0.
Textify used MLX Audio Swift revision
`d302a5c6080d2bb97bae38c7418f82abb76013b6` and MLX Swift 0.31.3 revision
`61b9e011e09a62b489f6bd647958f1555bdf2896`, both under MIT.

The required 3,135,962-byte `mlx.metallib` was compiled from the nine generated
entry points in that pinned MLX Swift checkout, targets macOS 14.0, and has
SHA-256 `cffe8fbfa9cfb794f1d920ff187016f823a555f7814cede99026699a936b92c7`.

## Method

- Host: Apple M4 Max, arm64, macOS 26.5.1 build 25F80.
- Runtime: Textify's release-built local MLX Audio adapter with the MLX Metal
  backend required and verified after load.
- Corpus: the ten fixed `dev-clean-2` utterances in `Corpus/openslr31.json`,
  totaling 210 reference words under CC BY 4.0.
- Feed: accelerated, explicit English, whole-recording transcription.
- Timing: release-to-final is recorded independently for each utterance. With
  ten samples, p95 uses the nearest-rank value and is therefore the maximum.
- Accuracy: aggregate WER is total edit errors divided by total reference words.

## Results

| Word errors / words | Aggregate WER | Release-to-final median | p95 | Median RTF | Peak resident memory |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 4 / 210 | 1.90% | 128.5 ms | 241 ms | 0.0182 | 4,456,595,456 bytes |

Per-clip release-to-final values, in corpus order, were 85, 86, 82, 73, 192,
143, 175, 208, 114, and 241 ms. Warm process model loads measured 235-243 ms;
the benchmark's first shader-packaging smoke recorded a 899 ms load and 1.724 s
warmup before caches were populated, so those distributions are not treated as
a clean cold-start comparison.

## Packaging and install evidence

MLX Swift's command-line SwiftPM path does not compile Metal shaders. A build
without the MLX library failed before inference; substituting Whisper's
`default.metallib` loaded a library but failed on the missing
`layer_normfloat32` kernel. Textify now ships a distinct, hash-verified
`mlx.metallib` colocated with the executable and release verification checks
the kernel name to prevent regression.

A fresh install-shaped directory was populated with the five exact files,
every SHA-256 was rechecked, and the native runtime produced
`a man said to the universe sir i exist` at 0 WER while reporting the required
MLX Metal backend.

## Catalog decision

The exact artifact is promoted as Experimental. It meets Textify's local-only,
immutable-artifact, Metal-routing, English quality, and latency gates. Its 4.28
GB download and 4.46 GB peak process footprint are substantially larger than
the existing choices, so the picker requires at least 16 GB unified memory and
advertises only English until more fixed-corpus evidence exists.
