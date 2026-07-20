# Parakeet TDT And Nemotron MLX/GGUF Benchmark - 2026-07-20

## Decision

Textify publishes twelve Experimental choices: one MLX directory and F16,
Q8_0, and Q5_K_M GGUF files for each of Parakeet TDT 0.6B V2, Parakeet TDT
0.6B V3, and Nemotron 3.5 ASR 0.6B. The Handy GGUF repositories do not publish
BF16 files, so the requested BF16 choices use the exact available F16 files
and are labeled F16 throughout the product.

The app reuses its pinned native
`mlx-audio-swift`/MLX Metal runtime for MLX directories and isolated
`transcribe.cpp` 0.1.3 Metal runtime for GGUF files. The Python `mlx-lm`,
`mlx-vlm`, and `mlx-audio` packages and the examples repository are not app
dependencies. Nemotron is used as whole-recording batch ASR; Textify does not
claim or expose upstream streaming partials.

## Immutable sources

| Family | Source | Revision | Selected bytes |
| --- | --- | --- | ---: |
| Parakeet V2 MLX F32 | `mlx-community/parakeet-tdt-0.6b-v2` | `8ae155301e23d820d82aa60d24817c900e69e487` | 2,471,862,935 |
| Parakeet V3 MLX F32 | `mlx-community/parakeet-tdt-0.6b-v3` | `ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15` | 2,509,041,541 |
| Nemotron MLX BF16 | `mlx-community/nemotron-3.5-asr-streaming-0.6b` | `e550040c0478027ed679b2b6b0d055502c103663` | 1,276,703,116 |
| Parakeet V2 GGUF | `handy-computer/parakeet-tdt-0.6b-v2-gguf` | `07cee0616125a08ef619729bb47f40ef747e4bc4` | 1,237,334,592 / 729,574,912 / 539,012,608 |
| Parakeet V3 GGUF | `handy-computer/parakeet-tdt-0.6b-v3-gguf` | `85ac09ea12fc4b1112fa76810059364bc6adc9de` | 1,255,869,856 / 739,508,576 / 548,946,272 |
| Nemotron GGUF | `handy-computer/nemotron-3.5-asr-streaming-0.6b-gguf` | `6d44e540bc31b0de1dbe174a3cea87f53a7f22fb` | 1,277,750,240 / 751,094,240 / 559,647,200 |

Every selected leaf was downloaded from its immutable revision and independently
matched against the byte size and SHA-256 recorded in `models/manifest.json`.
The MLX directories contain only the exact runtime files required by the pinned
local-directory loaders.

Parakeet V2 and V3 retain the upstream CC-BY-4.0 model terms. The exact pinned
Nemotron MLX conversion card declares the NVIDIA Open Model License, while the
exact pinned Handy GGUF card declares OpenMDW-1.1. Textify records the license
attached to each exact source instead of silently normalizing that discrepancy.
The MLX Audio Swift, MLX Swift, and transcribe.cpp runtime layers are MIT.

## Method

- Host: Apple M4 Max, arm64, Metal required and verified by each runtime.
- Corpus: fixed ten-utterance Mini LibriSpeech dev-clean-2 subset in
  `Benchmarks/RealtimeASR/Corpus/openslr31.json`.
- Reference: 210 English words total.
- Measurement: a fresh process per utterance, local model load, short warm-up,
  then full-buffer transcription. Release-to-final is measured around the
  final inference call; no partial transcript is produced.
- Runtime pins: `mlx-audio-swift`
  `d302a5c6080d2bb97bae38c7418f82abb76013b6`, MLX Swift 0.31.3
  (`61b9e011e09a62b489f6bd647958f1555bdf2896`), and transcribe.cpp
  `5a5a49664a8ea1f0e5b3be1dfc544730d1b62561`.

## Results

| Route | WER | Median final | P95 final | Peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Parakeet V2 MLX F32 | 0.48% | 80 ms | 192 ms | 2.64 GB |
| Parakeet V2 GGUF F16 | 0.48% | 74 ms | 159 ms | 1.51 GB |
| Parakeet V2 GGUF Q8_0 | 0.48% | 107 ms | 208 ms | 1.00 GB |
| Parakeet V2 GGUF Q5_K_M | 0.48% | 107 ms | 216 ms | 0.81 GB |
| Parakeet V3 MLX F32 | 2.38% | 67 ms | 291 ms | 2.68 GB |
| Parakeet V3 GGUF F16 | 2.38% | 99 ms | 143 ms | 1.60 GB |
| Parakeet V3 GGUF Q8_0 | 2.38% | 75 ms | 98 ms | 1.07 GB |
| Parakeet V3 GGUF Q5_K_M | 2.38% | 98 ms | 134 ms | 0.88 GB |
| Nemotron MLX BF16 | 3.33% | 137 ms | 413 ms | 1.44 GB |
| Nemotron GGUF F16 | 3.33% | 129 ms | 220 ms | 1.65 GB |
| Nemotron GGUF Q8_0 | 3.33% | 123 ms | 230 ms | 1.11 GB |
| Nemotron GGUF Q5_K_M | 2.86% | 130 ms | 306 ms | 0.92 GB |

These numbers qualify the exact English artifacts and native Metal paths. V3
and Nemotron remain Experimental because their broader automatic-language
claims still need Textify-owned per-language corpus evidence.
