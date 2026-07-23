# English Catalog Rating V2 Results

Status: promoted into the signed repository production manifest, 2026-07-23

This report applies `english-catalog-rating-v2` to the complete raw evidence
previously collected with the checksum-pinned `english-catalog-rating-v1`
suite. No inference was rerun: v2 changes only how the existing quality score
maps to its user-facing level and label.

The 31 reviewed records were promoted byte-for-byte into manifest v2 and
signed with the trusted
`textify-model-manifest-2026-huggingface` maintainer key.

## Rating rule

Quality level and label now derive only from the rounded weighted quality
score:

| Score | Quality |
| ---: | --- |
| 90–100 | Highest (5/5) |
| 75–89 | High (4/5) |
| 60–74 | Balanced (3/5) |
| 40–59 | Basic (2/5) |
| 0–39 | Limited (1/5) |

The no-speech false-positive rate remains part of the signed evidence and
nightly regression checks, but it does not cap the quality level.

## Evidence envelope

- Catalog entries: 38
- Rated English transcription models: 31
- Unrated English transcription models: 1
- Language- or purpose-inapplicable models: 6
- Reused complete runs: 93 (three per rated model)
- Reused scored case executions: 86,676 (93 runs x 932 fixed cases)
- Quality levels changed from v1: 20
- V2 policy SHA-256:
  `0da0e0b04e7167ac298eee6dca2190f8522ec95c7f9ace0bdb168c798638988a`
- Policy ID: `english-catalog-rating-v2`
- Suite ID: `english-catalog-rating-v1`
- Suite-index SHA-256:
  `77637f85b4e3fde7b15f5481804e231d720c0337d11153dc5867dee2587ddde8`
- Source revision:
  `5a6be4dc5fed6bf1e7e83801425ae9d7cba761a3`
- Reference host: Apple M4 Max, arm64, macOS Version 26.5.2 (Build 25F84)

All 31 v2 candidates retain the same component WERs, quality scores,
no-speech rates, speed evidence, artifact fingerprints, suite hash, source
revision, host, and raw runs as their audited v1 source candidates.

## Results

| Model ID | Quality | No-speech FPR | Speed | p50 / p95 |
| --- | ---: | ---: | ---: | ---: |
| `ggml-small.en-q5_1` | 76, High (4/5) | 72.5% | 88, Fast (4/5) | 101 / 249 ms |
| `whisper-large-v2-q5_0` | 81, High (4/5) | 74.0% | 18, Slow (1/5) | 454 / 924 ms |
| `whisper-large-v3-q5_0` | 82, High (4/5) | 33.5% | Unrated (unstable p95) | — |
| `whisper-large-v3-turbo-q5_0` | 82, High (4/5) | 23.5% | 52, Measured (2/5) | 359 / 428 ms |
| `canary-qwen-2.5b-q4-k-m` | Unrated (runtime failure) | — | Unrated | — |
| `parakeet-tdt-0.6b-v3` | 89, High (4/5) | 7.5% | 98, Fastest (5/5) | 60 / 116 ms |
| `parakeet-tdt-ctc-110m` | 79, High (4/5) | 2.0% | 100, Fastest (5/5) | 35 / 68 ms |
| `parakeet-tdt-0.6b-v2` | 89, High (4/5) | 10.5% | 97, Fastest (5/5) | 66 / 105 ms |
| `parakeet-rnnt-1.1b` | 87, High (4/5) | 22.5% | 89, Fast (4/5) | 86 / 285 ms |
| `cohere-transcribe-03-2026-mlx-8bit` | 88, High (4/5) | 73.5% | 89, Fast (4/5) | 85 / 267 ms |
| `whisper-large-v3-turbo-mlx` | 83, High (4/5) | 79.0% | 57, Measured (2/5) | 274 / 491 ms |
| `parakeet-ja` | Not applicable (Japanese) | — | Not applicable | — |
| `paraformer-large-zh-int8` | Not applicable (Chinese) | — | Not applicable | — |
| `reazonspeech-k2-v2-int8` | Not applicable (Japanese) | — | Not applicable | — |
| `sensevoice-small-int8-2024-07-17` | 74, Balanced (3/5) | 23.0% | 64, Balanced (3/5) | 136 / 655 ms |
| `qwen3-asr-0.6b-mlx-8bit` | 80, High (4/5) | 0.0% | 83, Fast (4/5) | 112 / 340 ms |
| `qwen3-asr-1.7b-mlx-8bit` | 85, High (4/5) | 1.5% | 61, Balanced (3/5) | 178 / 614 ms |
| `qwen3-asr-0.6b-bf16` | 89, High (4/5) | 0.5% | 77, Fast (4/5) | 122 / 422 ms |
| `qwen3-asr-0.6b-q8-0` | 89, High (4/5) | 0.5% | 82, Fast (4/5) | 112 / 355 ms |
| `qwen3-asr-0.6b-q5-k-m` | 88, High (4/5) | 0.0% | 84, Fast (4/5) | 100 / 340 ms |
| `qwen3-asr-1.7b-bf16` | 92, Highest (5/5) | 1.0% | 47, Measured (2/5) | 212 / 801 ms |
| `qwen3-asr-1.7b-q8-0` | 92, Highest (5/5) | 1.5% | 66, Balanced (3/5) | 154 / 568 ms |
| `qwen3-asr-1.7b-q5-k-m` | 93, Highest (5/5) | 1.5% | 70, Balanced (3/5) | 142 / 519 ms |
| `parakeet-tdt-0.6b-v2-mlx` | 90, Highest (5/5) | 12.5% | 100, Fastest (5/5) | 29 / 83 ms |
| `parakeet-tdt-0.6b-v3-mlx` | 93, Highest (5/5) | 9.5% | 100, Fastest (5/5) | 30 / 83 ms |
| `nemotron-3.5-asr-streaming-0.6b-mlx` | 70, Balanced (3/5) | 0.5% | 95, Fastest (5/5) | 54 / 222 ms |
| `parakeet-tdt-0.6b-v2-f16` | 90, Highest (5/5) | 11.5% | 100, Fastest (5/5) | 40 / 113 ms |
| `parakeet-tdt-0.6b-v2-q8-0` | 90, Highest (5/5) | 11.5% | 100, Fastest (5/5) | 39 / 115 ms |
| `parakeet-tdt-0.6b-v2-q5-k-m` | 90, Highest (5/5) | 11.0% | 100, Fastest (5/5) | 42 / 120 ms |
| `parakeet-tdt-0.6b-v3-f16` | 93, Highest (5/5) | 11.0% | 100, Fastest (5/5) | 43 / 127 ms |
| `parakeet-tdt-0.6b-v3-q8-0` | 93, Highest (5/5) | 11.0% | 100, Fastest (5/5) | 43 / 128 ms |
| `parakeet-tdt-0.6b-v3-q5-k-m` | 92, Highest (5/5) | 10.5% | 100, Fastest (5/5) | 45 / 134 ms |
| `nemotron-3.5-asr-streaming-0.6b-f16` | 70, Balanced (3/5) | 0.0% | 96, Fastest (5/5) | 58 / 201 ms |
| `nemotron-3.5-asr-streaming-0.6b-q8-0` | 71, Balanced (3/5) | 0.0% | 96, Fastest (5/5) | 57 / 204 ms |
| `nemotron-3.5-asr-streaming-0.6b-q5-k-m` | 70, Balanced (3/5) | 0.0% | 95, Fastest (5/5) | 59 / 205 ms |
| `mossformer2-se-fp32` | Not applicable (voice cleaning) | — | Not applicable | — |
| `mossformer2-se-fp16` | Not applicable (voice cleaning) | — | Not applicable | — |
| `mossformer2-se-int8` | Not applicable (voice cleaning) | — | Not applicable | — |

## Unrated evidence

`canary-qwen-2.5b-q4-k-m` remains Unrated because its two deterministic
attempts failed at the same no-speech control after the decoder reached its
256-token generation cap. The three Japanese/Chinese transcription models are
outside the English suite, and the three MossFormer2 entries perform voice
cleaning rather than transcription.

## Evidence location

The v2 candidates are named `candidate.v2.json`, and the seven explicit
Unrated records are named `unrated.v2.json`, under:

`Benchmarks/RealtimeASR/.benchmark-results/catalog-rating/all-models-20260723/`

The repository production catalog now contains all 31 v2 ratings:

- Manifest SHA-256:
  `ba2cf26665eb096de1be19279014c8f36ff5132305d5881db677805752c388a1`
- Signature SHA-256:
  `6e11f8d477f6c4f6652ae895a82d611210112cdc9124320d32673589a0461e9f`
- Signed content type:
  `application/vnd.textify.model-manifest+json;version=2`

External GitHub Pages publication is a separate release operation and was not
performed by this update.
