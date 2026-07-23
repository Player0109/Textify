# English Catalog Rating v1 Results

Status: complete catalog-wide candidate run, 2026-07-23

Historical v1 scoring record. The direct-score v2 rescore is recorded in
`catalog-rating-results-v2-2026-07-23.md`.

This report records the first complete application of
`english-catalog-rating-v1` to the signed Textify model catalog. It is
benchmark evidence, not production manifest metadata. Promotion still
requires manual review and a separate manifest signing step.

## Run envelope

- Catalog entries: 38
- Rated English transcription models: 31
- Unrated English transcription models: 1
- Language- or purpose-inapplicable models: 6
- Complete scored runs: 93 (three per rated model)
- Scored case executions: 86,676 (93 runs x 932 fixed cases)
- Per run: 732 speech cases and 200 no-speech controls
- Suite index SHA-256:
  `77637f85b4e3fde7b15f5481804e231d720c0337d11153dc5867dee2587ddde8`
- Policy ID and suite ID: `english-catalog-rating-v1`
- Source revision: `5a6be4dc5fed6bf1e7e83801425ae9d7cba761a3`
- Reference host: Apple M4 Max, arm64, macOS Version 26.5.2 (Build 25F84)

Every rated candidate passed the final evidence audit: schema version 1,
three matching raw runs, the frozen suite hash, the common source revision,
the expected artifact fingerprint, and complete 360/220/152/200 component
counts in each run.

## Results

Quality labels include the no-speech safety cap. Speed is based on p50/p95
release-to-final latency and p95 real-time factor. A speed cohort is Unrated
when its relative p95 spread exceeds the frozen 15% stability limit.

| Model ID | Quality | No-speech FPR | Speed | p50 / p95 |
| --- | ---: | ---: | ---: | ---: |
| `ggml-small.en-q5_1` | 76, Limited (1/5) | 72.5% | 88, Fast (4/5) | 101 / 249 ms |
| `whisper-large-v2-q5_0` | 81, Limited (1/5) | 74.0% | 18, Slow (1/5) | 454 / 924 ms |
| `whisper-large-v3-q5_0` | 82, Limited (1/5) | 33.5% | Unrated (unstable p95) | — |
| `whisper-large-v3-turbo-q5_0` | 82, Basic (2/5) | 23.5% | 52, Measured (2/5) | 359 / 428 ms |
| `canary-qwen-2.5b-q4-k-m` | Unrated (runtime failure) | — | Unrated | — |
| `parakeet-tdt-0.6b-v3` | 89, Balanced (3/5) | 7.5% | 98, Fastest (5/5) | 60 / 116 ms |
| `parakeet-tdt-ctc-110m` | 79, High (4/5) | 2.0% | 100, Fastest (5/5) | 35 / 68 ms |
| `parakeet-tdt-0.6b-v2` | 89, Basic (2/5) | 10.5% | 97, Fastest (5/5) | 66 / 105 ms |
| `parakeet-rnnt-1.1b` | 87, Basic (2/5) | 22.5% | 89, Fast (4/5) | 86 / 285 ms |
| `cohere-transcribe-03-2026-mlx-8bit` | 88, Limited (1/5) | 73.5% | 89, Fast (4/5) | 85 / 267 ms |
| `whisper-large-v3-turbo-mlx` | 83, Limited (1/5) | 79.0% | 57, Measured (2/5) | 274 / 491 ms |
| `parakeet-ja` | Not applicable (Japanese) | — | Not applicable | — |
| `paraformer-large-zh-int8` | Not applicable (Chinese) | — | Not applicable | — |
| `reazonspeech-k2-v2-int8` | Not applicable (Japanese) | — | Not applicable | — |
| `sensevoice-small-int8-2024-07-17` | 74, Basic (2/5) | 23.0% | 64, Balanced (3/5) | 136 / 655 ms |
| `qwen3-asr-0.6b-mlx-8bit` | 80, High (4/5) | 0.0% | 83, Fast (4/5) | 112 / 340 ms |
| `qwen3-asr-1.7b-mlx-8bit` | 85, High (4/5) | 1.5% | 61, Balanced (3/5) | 178 / 614 ms |
| `qwen3-asr-0.6b-bf16` | 89, High (4/5) | 0.5% | 77, Fast (4/5) | 122 / 422 ms |
| `qwen3-asr-0.6b-q8-0` | 89, High (4/5) | 0.5% | 82, Fast (4/5) | 112 / 355 ms |
| `qwen3-asr-0.6b-q5-k-m` | 88, High (4/5) | 0.0% | 84, Fast (4/5) | 100 / 340 ms |
| `qwen3-asr-1.7b-bf16` | 92, Highest (5/5) | 1.0% | 47, Measured (2/5) | 212 / 801 ms |
| `qwen3-asr-1.7b-q8-0` | 92, High (4/5) | 1.5% | 66, Balanced (3/5) | 154 / 568 ms |
| `qwen3-asr-1.7b-q5-k-m` | 93, High (4/5) | 1.5% | 70, Balanced (3/5) | 142 / 519 ms |
| `parakeet-tdt-0.6b-v2-mlx` | 90, Basic (2/5) | 12.5% | 100, Fastest (5/5) | 29 / 83 ms |
| `parakeet-tdt-0.6b-v3-mlx` | 93, Balanced (3/5) | 9.5% | 100, Fastest (5/5) | 30 / 83 ms |
| `nemotron-3.5-asr-streaming-0.6b-mlx` | 70, Balanced (3/5) | 0.5% | 95, Fastest (5/5) | 54 / 222 ms |
| `parakeet-tdt-0.6b-v2-f16` | 90, Basic (2/5) | 11.5% | 100, Fastest (5/5) | 40 / 113 ms |
| `parakeet-tdt-0.6b-v2-q8-0` | 90, Basic (2/5) | 11.5% | 100, Fastest (5/5) | 39 / 115 ms |
| `parakeet-tdt-0.6b-v2-q5-k-m` | 90, Basic (2/5) | 11.0% | 100, Fastest (5/5) | 42 / 120 ms |
| `parakeet-tdt-0.6b-v3-f16` | 93, Basic (2/5) | 11.0% | 100, Fastest (5/5) | 43 / 127 ms |
| `parakeet-tdt-0.6b-v3-q8-0` | 93, Basic (2/5) | 11.0% | 100, Fastest (5/5) | 43 / 128 ms |
| `parakeet-tdt-0.6b-v3-q5-k-m` | 92, Basic (2/5) | 10.5% | 100, Fastest (5/5) | 45 / 134 ms |
| `nemotron-3.5-asr-streaming-0.6b-f16` | 70, Balanced (3/5) | 0.0% | 96, Fastest (5/5) | 58 / 201 ms |
| `nemotron-3.5-asr-streaming-0.6b-q8-0` | 71, Balanced (3/5) | 0.0% | 96, Fastest (5/5) | 57 / 204 ms |
| `nemotron-3.5-asr-streaming-0.6b-q5-k-m` | 70, Balanced (3/5) | 0.0% | 95, Fastest (5/5) | 59 / 205 ms |
| `mossformer2-se-fp32` | Not applicable (voice cleaning) | — | Not applicable | — |
| `mossformer2-se-fp16` | Not applicable (voice cleaning) | — | Not applicable | — |
| `mossformer2-se-int8` | Not applicable (voice cleaning) | — | Not applicable | — |

## Unrated evidence

`canary-qwen-2.5b-q4-k-m` was attempted twice. Both attempts completed all
732 speech cases and failed at the same no-speech input after 26 controls.
The decoder reached its 256-token generation cap before end-of-stream. No
score was synthesized from an incomplete run.

The three Japanese/Chinese transcription models are outside an English
rating policy. The three MossFormer2 entries perform voice cleaning rather
than transcription. Explicit `unrated.json` records account for all seven
cases.

## Evidence location

The candidates, raw runs, explicit Unrated records, runner log, and progress
ledger are under the ignored local directory:

`Benchmarks/RealtimeASR/.benchmark-results/catalog-rating/all-models-20260723/`

The production `models/manifest.json` and its signature were not changed by
this run.
