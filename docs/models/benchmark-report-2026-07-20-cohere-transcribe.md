# Cohere Transcribe 03-2026 Catalog Benchmark - 2026-07-20

This report records Textify's promotion evidence for the exact Cohere
Transcribe model requested from the supplied Artificial Analysis comparison.
It does not generalize the English measurements to other languages.

## Immutable inputs

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `config.json` | 4,336 | `206113921b2b75ad43461e9d2d4cd361405be9acaf29aa3ec1ed751c16347bb6` |
| `model.safetensors` | 2,418,031,831 | `bd1edbe982f47d22e64ba5723a4204b43ca93ea703b18946160d44ec26c83ab9` |
| `tokenizer.model` | 492,827 | `6d21e6a83b2d0d3e1241a7817e4bef8eb63bcb7cfe4a2675af9a35ff3bbf0e14` |
| `tokenizer_config.json` | 48,141 | `0dfeb3eeba07bccaa1b4bf78f3135ad3059acf8d18f681675832b285ac0035b0` |

The 2,418,577,135-byte directory came from
`beshkenadze/cohere-transcribe-03-2026-mlx-8bit` revision
`d1f843476f84846e6fe7aa58a6033f17882f0ec9`. The official model and conversion
are Apache-2.0. Textify used MLX Audio Swift revision
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
- Feed: accelerated, explicit English, greedy whole-recording transcription.
- Timing: release-to-final is recorded independently for each utterance. With
  ten samples, p95 uses the nearest-rank value and is therefore the maximum.
- Accuracy: aggregate WER is total edit errors divided by total reference words;
  punctuation and capitalization are normalized by the shared scorer.

## Results

| Word errors / words | Aggregate WER | Release-to-final median | p95 | Median RTF | Peak resident memory |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 6 / 210 | 2.86% | 121.5 ms | 304 ms | 0.0179 | 2,522,726,400 bytes |

Per-clip release-to-final values, in corpus order, were 81, 89, 83, 82, 137,
140, 281, 210, 106, and 304 ms. Warm process model loads measured 192-204 ms
with a 196.5 ms median; warmups measured 71-93 ms with a 71.5 ms median. The
first shader-preparation smoke recorded a 228 ms load and 1.090 s warmup before
caches were populated, so that warmup is disclosed separately.

## Runtime and install evidence

Textify's adapter requires the exact four-file model directory, an actual MLX
Metal backend, explicit English, and 16 kHz mono audio. It rejects automatic
language detection, non-English selection, CPU fallback, and audio beyond 30
seconds. Digital and near-digital silence returns no speech without invoking
the model.

All four downloaded files matched their immutable catalog sizes and SHA-256
values. The native runtime loaded those exact files with Textify's packaged,
signed `mlx.metallib` and produced
`A man said to the universe, Sir, I exist.` at 0 WER on the first fixed clip.
The signed-catalog integration covers atomic installation and the same local
runtime route behind its network-heavy opt-in gate.

## Catalog decision

The exact artifact is promoted as Experimental. It meets Textify's local-only,
immutable-artifact, Metal-routing, English accuracy, and interactive latency
gates. Its 2.42 GB download, 2.53 GB peak process footprint, English-only
coverage, new conversion, and 30-second recording cap are disclosed directly
in the picker.
