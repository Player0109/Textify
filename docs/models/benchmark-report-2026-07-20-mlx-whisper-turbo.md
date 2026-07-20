# MLX Whisper Large V3 Turbo Catalog Benchmark - 2026-07-20

This report records Textify's promotion evidence for the exact
`mlx-community/whisper-large-v3-turbo` model requested for the native MLX path.
It does not generalize the English measurements to other languages.

## Immutable inputs

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `config.json` | 268 | `b34fc29e4e11e0a25e812775dd67f4dd16fc2c8eb43d28ae25ff7d660ecb6379` |
| `weights.safetensors` | 1,613,977,612 | `951ed3fc1203e6a62467abb2144a96ce7eafca8fa77e3704fdb8635ff3e7f8a6` |
| `tokenizer.json` | 2,710,337 | `297b13372ac43916285644fb9687add3cc62ee2a1adb60da3dc25cc94c1871fd` |
| `tokenizer_config.json` | 282,843 | `844b642c73a91359722f47b35705f7174686df33d252695d8572cf9ac03a6389` |
| `special_tokens_map.json` | 2,186 | `baea4ea09372eb4fca86b4e4346139fd73cb807d5087e9de0948e971739c3e74` |
| `added_tokens.json` | 34,648 | `3c51f66c4c21f9e126970078f11ae77a78c74aee8df606ee9daba86e467108e0` |
| `vocab.json` | 1,036,558 | `e2aa043ef015641d363d8288e7c241c85e36a5c761fb303598e0710233344387` |
| `merges.txt` | 493,869 | `2df2990a395e35e8dfbc7511e08c12d56018d8d04691e0133e5d63b21e154dc6` |
| `normalizer.json` | 52,666 | `bf1c507dc8724ca9cf9903640dacfb69dae2f00edee4f21ceba106a7392f26dd` |
| `generation_config.json` | 3,772 | `cce11bfe3aaa6ae9e072ea2637caaec8795e68d9b67e655a5af16ee509681a4c` |

The 1,618,594,759-byte directory uses the MLX checkpoint from revision
`a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb`. The eight tokenizer/generation
files come from the original `openai/whisper-large-v3-turbo` revision
`41f01f3fe87f28c78e2fbf8b568835947dd65ed9`. Installing those files in the
managed directory prevents the pinned Swift runtime from using its mutable
network tokenizer fallback. The original checkpoint is MIT licensed.

Textify used MLX Audio Swift revision
`d302a5c6080d2bb97bae38c7418f82abb76013b6` and MLX Swift 0.31.3 revision
`61b9e011e09a62b489f6bd647958f1555bdf2896`, both under MIT. The required
3,135,962-byte `mlx.metallib` targets macOS 14.0 and has SHA-256
`cffe8fbfa9cfb794f1d920ff187016f823a555f7814cede99026699a936b92c7`.

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
| 7 / 210 | 3.33% | 321.5 ms | 416 ms | 0.0458 | 1,748,041,728 bytes |

Per-clip release-to-final values, in corpus order, were 270, 287, 273, 258,
373, 378, 380, 416, 296, and 347 ms. Warm process model loads measured 192-207
ms with a 196 ms median; warmups measured 232-256 ms with a 232 ms median. The
first shader-preparation smoke recorded a 210 ms load and 1.873 s warmup before
caches were populated.

## Runtime and install evidence

Textify's adapter requires the exact ten-file managed directory, an actual MLX
Metal backend, explicit English, 16 kHz mono audio, and a 60-second maximum.
It rejects automatic language detection, non-English selection, CPU fallback,
and incomplete tokenizer directories. Digital and near-digital silence returns
no speech without invoking the model.

The downloaded files matched the signed catalog sizes and SHA-256 values. The
native runtime loaded the exact directory with Textify's packaged
`mlx.metallib` and produced `A man said to the universe, Sir, I exist.` at 0
WER on the first fixed clip. The opt-in signed-catalog integration test covers
atomic installation and the same local runtime route.

## Catalog decision

The exact artifact is promoted as a separate Experimental choice. It meets
Textify's local-only, immutable-artifact, Metal-routing, English accuracy, and
interactive latency gates. Compared with the existing 5-bit whisper.cpp Turbo
entry, it improved the narrow English result from 4.29% to 3.33% WER and the
median from 367 ms to 321.5 ms, but increases the download from 574 MB to 1.62
GB and peak process memory from about 700 MB to 1.75 GB. Both choices remain in
the picker so that tradeoff stays explicit.
