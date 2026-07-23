# English Catalog Rating v1 Calibration

Status: frozen pre-production calibration evidence, 2026-07-22

The `english-catalog-rating-v1` policy and suite were exercised against two
representative Textify runtime families before publication. Each model used
three complete resident-session runs on the reference host. These results are
calibration candidates only; they were not added to or signed into the
production model manifest.

## Frozen inputs

- Suite index SHA-256:
  `77637f85b4e3fde7b15f5481804e231d720c0337d11153dc5867dee2587ddde8`
- Policy SHA-256:
  `5ded40890932d42817522eb21e004524e86b042505f692fa70054a864e88c3e5`
- Reference host: Apple M4 Max, arm64, macOS Version 26.5.2 (Build 25F84)
- Base source revision: `8e84f1b41800deeac5861a2c1989f3e16599ddb0`
- Profile: 932 fixed English cases, with 732 speech and 200 no-speech
  cases; every input is no longer than 29 seconds
- Execution: accelerated production path, one model load, one warmup, and one
  resident session per component and run

Quality uses fixed weights of 50% Open ASR, 30% Earnings-21/22 (EdAcc), and
20% BERSt. Component WER anchors are 0.05/0.40, 0.12/0.55, and 0.18/0.70
for excellent/unacceptable. The no-speech false-positive rate may cap the
quality level independently of the rounded weighted score.

Speed uses 70% p95 release-to-final latency and 30% p95 real-time factor. Its
excellent/unacceptable anchors are 150/1,200 milliseconds and 0.02/0.25. A
relative p95 spread above 15% makes speed unrated.

## Calibration results

| Model/runtime | Component WER: Open / EdAcc / BERSt | No-speech FPR | Quality | p50 / p95 | p95 RTF | Spread | Speed |
| --- | --- | ---: | --- | ---: | ---: | ---: | --- |
| `ggml-small.en-q5_1` / whisper.cpp | 0.104 / 0.255 / 0.352 | 72.5% | 76, level 1 Limited | 104 / 260 ms | 0.062 | 6.2% | 87, level 4 Fast |
| `parakeet-tdt-0.6b-v3` / FluidAudio | 0.078 / 0.161 / 0.278 | 7.5% | 89, level 3 Balanced | 66 / 119 ms | 0.043 | 8.5% | 97, level 5 Fastest |

The Whisper weighted quality score would ordinarily map to level 4, but its
72.5% no-speech false-positive rate correctly caps it at level 1. The Parakeet
result is capped at level 3 by its 7.5% rate. Both speed cohorts remain within
the 15% stability limit.

The two independently implemented runtime families produce distinct,
plausible quality and speed signals, while the no-speech gate prevents a good
speech-only score from hiding hallucinations. On that evidence, the v1 index,
anchors, weights, caps, labels, and stability threshold are frozen. Any future
semantic change requires a new suite or policy identifier rather than editing
v1 in place.

These calibration runs were collected from the dirty implementation worktree
before the clean-checkout publication gate was added. They are sufficient to
calibrate and freeze the policy, but they are deliberately ineligible for
production publication. After this implementation is committed, any manifest
candidate must be recollected from a clean checkout; the runner now enforces
that condition and carries the exact source revision into the signed evidence.

Run IDs:

- `calibration-small-en-1`, `calibration-small-en-2`,
  `calibration-small-en-3`
- `calibration-parakeet-v3-1`, `calibration-parakeet-v3-2`,
  `calibration-parakeet-v3-3`

The generated candidate JSON files live under the ignored
`Benchmarks/RealtimeASR/.benchmark-results/` directory. Regenerate them from
the immutable raw run directories with `generate_english_catalog_rating.sh`;
do not copy them into production without manual review and a separate signing
step.
