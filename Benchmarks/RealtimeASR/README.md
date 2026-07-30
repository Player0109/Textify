# Textify Realtime ASR Benchmark

This standalone Swift package compares candidate transcription engines without
linking them into the shipping Textify application.

The benchmark feeds identical 16 kHz mono audio to each engine and records:

- model load and warmup time, separately from interactive latency;
- time to first useful partial and changed-partial cadence;
- trigger-release-to-final latency, including streaming backlog;
- inference time, real-time factor, CPU time, and peak process RSS;
- normalized word and character error rates when a reference transcript is
  supplied.

The current candidates are:

- `apple-dictation-analyzer`: Apple's progressive short-dictation module in
  `SpeechAnalyzer`, representing the lower-latency legacy on-device model path;
- `apple-speech-analyzer`: Apple's on-device `SpeechAnalyzer` and
  `SpeechTranscriber` with volatile fast results (macOS 26 or newer);
- `whisper`: Textify's existing Metal-enabled `WhisperRuntime` baseline;
- `parakeet-eou-160`: FluidAudio 0.15.5 with the latency-first Parakeet
  EOU 120M model using 160 ms chunks on Core ML CPU + Neural Engine;
- `parakeet-unified-320`: FluidAudio 0.15.5 with the int8 Parakeet Unified
  `[70,2,2]` streaming encoder on Core ML CPU + Neural Engine.
- `parakeet-tdt-v2`, `parakeet-tdt-v3`, `parakeet-tdt-ctc-110m`, and
  `parakeet-tdt-ja`: the exact batch Parakeet runtime used by Textify for very
  fast final output after trigger release. Each keeps the loaded Core ML
  session resident and reports cold load, warmup, and release-to-final timing
  separately.
- `paraformer-large-zh-int8`: Textify's Mandarin Chinese Specialist candidate,
  using the released FluidAudio non-autoregressive Core ML path. The benchmark
  reports CER and verifies Neural Engine planning for encoder and decoder.
- `reazonspeech-k2-v2` and `sensevoice-small-int8`: the two promoted
  sherpa-onnx CPU paths. SenseVoice supports automatic English, Mandarin,
  Cantonese, Japanese, and Korean recognition.
- `qwen3-asr-0.6b` and `dolphin-small-ctc-multi-lang-int8`: exact-artifact
  evaluation-only paths;
  their measured support decisions are recorded in the benchmark report.
- `mlx-parakeet-rnnt-1.1b`, `mlx-cohere-transcribe-03-2026`, and
  `mlx-whisper-large-v3-turbo`: exact local MLX Audio model-directory routes
  that require Textify's pinned MLX Metal library beside the benchmark
  executable.
- `mlx-qwen3-asr-0.6b-8bit` and `mlx-qwen3-asr-1.7b-8bit`: exact
  MLX Community Qwen3-ASR directories through native MLX Audio Swift with
  automatic language detection.
- `canary-qwen-2.5b`: the exact English Canary-Qwen route through Textify's
  isolated transcribe.cpp Metal runtime.
- `transcribe-qwen3-asr-0.6b` and `transcribe-qwen3-asr-1.7b`: Qwen3-ASR GGUF
  routes through the same isolated transcribe.cpp Metal runtime; the selected
  BF16, Q8_0, or Q5_K_M file is supplied with `--transcribe-model`.
- `mlx-parakeet-tdt-0.6b-v2`, `mlx-parakeet-tdt-0.6b-v3`, and
  `mlx-nemotron-3.5-asr-streaming-0.6b`: exact MLX Community directories
  through MLX Audio Swift Metal.
- `transcribe-parakeet-tdt-0.6b-v2`,
  `transcribe-parakeet-tdt-0.6b-v3`, and
  `transcribe-nemotron-3.5-asr-streaming-0.6b`: exact F16, Q8_0, or Q5_K_M
  Handy GGUF files through transcribe.cpp Metal.
- `litert-gemma-4-12b`: the exact Gemma 4 12B `.litertlm` artifact through the
  official pinned LiteRT-LM Swift package with GPU text and audio backends.

Model downloads are cached outside the repository under
`~/Library/Caches/io.github.Player0109.Textify/RealtimeBenchmark/Models`.
Generated audio, builds, and JSON run results are ignored by Git.

## Run

The first English evaluation-suite manifest is
`Corpus/open-asr-english-pr-v1.json`. It pins 24 Open ASR Leaderboard rows at a
full dataset commit: LibriSpeech clean/other, Common Voice, AMI, GigaSpeech,
and VoxPopuli, with one clip from each of the 1-3, 3-10, 10-20, and 20-29
second buckets. This is a pull-request/public-comparability anchor, not the
eventual private release gate.

Prepare and verify its audio with:

```bash
./prepare_open_asr_english_pr.sh
```

Run any supported engine across the compatible duration lane by passing its
normal engine-specific options after the first five arguments. For example:

```bash
./run_evaluation_suite.sh \
  Corpus/open-asr-english-pr-v1.json \
  .benchmark-data/open-asr-english-pr-v1 \
  whisper accelerated 29 \
  --whisper-model /path/to/model.bin
```

The runner validates the manifest before use and writes one JSON result per
clip plus `summary.json` under `results/open-asr-english-pr-v1/`. The summary
reports per-subset, manifest-slice, micro, and corpus-macro WER/CER; no-speech false-positive
rate and hallucinated word/character counts when applicable; p50/p90/p95 model
load, warmup, release-to-final latency, and RTF; peak RSS; and any missing item
IDs. Speech WER/CER fields are omitted for a suite with no speech references.
Setting the maximum to `10` selects only the twelve 1-3 and 3-10 second clips;
`29` selects all 24. Model load and warmup remain recorded separately by the
existing engine adapters. Catalog-capable Whisper, FluidAudio Parakeet,
sherpa-onnx, MLX Audio, and transcribe.cpp engines use resident batch sessions:
the model is loaded and warmed once, every clip is transcribed through that
session, and `batch-session.json` records the single load and warmup
explicitly.

The complementary negative-control manifest is
`Corpus/musan-no-speech-pr-v1.json`. It pins eight public-domain MUSAN noise
clips from the `free-sound` and `sound-bible` sources, balanced across the same
four duration buckets. Prepare and run it with:

```bash
./prepare_musan_no_speech_pr.sh
./run_evaluation_suite.sh \
  Corpus/musan-no-speech-pr-v1.json \
  .benchmark-data/musan-no-speech-pr-v1 \
  whisper accelerated 29 \
  --whisper-model /path/to/model.bin
```

Set `TEXTIFY_BENCHMARK_LABEL` when comparing multiple artifacts exposed by the
same engine name so their result directories cannot overwrite each other:

```bash
TEXTIFY_BENCHMARK_LABEL=qwen3-0.6b-q5-k-m \
  ./run_evaluation_suite.sh MANIFEST DATA_DIR ENGINE accelerated 29 \
  --transcribe-runtime /path/to/runtime \
  --transcribe-model /path/to/model.gguf
```

The first runnable nightly bootstrap is
`Corpus/english-nightly-bootstrap-v1.index.json`. The index pins the exact
component-manifest hashes before any audio or model work begins. It currently
contains 1,060 items: 360 Open ASR quality clips, 240 speaker-balanced EdAcc
clips, 152 BERSt stress clips, 108 VoiceCodeBench workplace-dictation clips,
and 200 MUSAN no-speech controls. The 860 speech items and all 200 negative
controls are runnable; the remaining planned 160 speech items require the
Common Voice Spontaneous Speech archive described below.

The Open ASR nightly component pins 60 clips from each of LibriSpeech clean,
LibriSpeech other, Common Voice, AMI, GigaSpeech, and VoxPopuli. Its selector
uses the 100-row pages around the four reviewed PR anchors for each corpus,
selects up to 15 clips from each 1-29 second duration bucket, and fills corpus-
specific shortages deterministically. Every corpus retains all four buckets.

The BERSt component uses schema v2 and selects four distinct speakers for each
of 19 phone positions in both shout and no-shout conditions. Its fixed selector
seed, row IDs, speaker IDs, slice metadata, byte sizes, and SHA-256 values are
stored in `Corpus/berst-english-nightly-v1.json`.

The EdAcc component pins four compatible clips from each of the official test
split's 60 speakers. Its manifest retains accent, raw-accent, gender, and first-
language slices and covers all six duration buckets through 60 seconds.

The VoiceCodeBench component includes all 108 official test recordings whose
decoded duration is at most 60 seconds. They provide 93 minutes of long-form,
human-recorded workplace dictation across 55 speakers and seven domains. The
benchmark uses each item's acoustic transcript for reproducible WER/CER and
retains domain, scenario, difficulty, accent, sex, age, and entity-count slices.
VoiceCodeBench's upstream CTEM and TSR depend on an OpenAI verifier making
semantic entity-presence decisions, so Textify does not report those scores as
offline deterministic metrics.

The MUSAN nightly component supplies 200 public-domain noise controls: 150 from
free-sound and 50 from sound-bible. Both sources retain every 1-29 second
duration bucket. No-speech output is reported as a raw non-empty-transcript
false-positive rate plus hallucinated word and character counts.

The planned final speech component is 160 English clips from Mozilla Common
Voice Spontaneous Speech. Mozilla distributes that archive through Mozilla Data
Collective account-gated downloads rather than the public Hub endpoints used by
the runnable components. It is intentionally not represented by placeholders;
the nightly index will only include it after a licensed archive is provided and
its selected audio is checksum-pinned.

Prepare and run every bootstrap component with:

```bash
./prepare_english_nightly_bootstrap.sh
TEXTIFY_BENCHMARK_LABEL=whisper-small-en-q5_1 \
  ./run_english_nightly_bootstrap.sh whisper \
  --whisper-model /path/to/model.bin
```

Regenerating any nightly selection is an explicit provenance operation, not
part of an ordinary nightly run. If it changes manifest bytes, the pinned hash
in the bootstrap index must be reviewed and updated:

```bash
./generate_open_asr_english_nightly.sh
./generate_berst_english_nightly.sh
./generate_edacc_english_nightly.sh
./generate_voice_code_bench_english_nightly.sh
./generate_musan_no_speech_nightly.sh
```

## Catalog quality and speed ratings

`Corpus/english-catalog-rating-v1.index.json` is the universal English model
comparison profile. It contains 932 pinned cases that every current English
catalog runtime can accept within 29 seconds: 360 Open ASR cases, 220 compatible
EdAcc cases, 152 BERSt stress cases, and 200 MUSAN no-speech controls. The
longer VoiceCodeBench component remains supplemental evidence and never changes
the universal catalog rating.

`Corpus/english-catalog-rating-v2.policy.json` is the current scoring policy
over that unchanged v1 suite. It freezes absolute score anchors, component
weights, the Apple M4 Max reference host, the three-run stability gate, and the
five user-facing levels. Ratings use production-filtered application text
while retaining the raw transcript in each result. Quality is the rounded
weighted score from the median component WERs over three runs; its level and
label map directly from that score. The no-speech false-positive rate remains
signed evidence and a regression signal but does not modify the quality level.
Speed pools all speech cases per run, excludes load and warmup, and is left
`Unrated` when repeated-run p95 spread exceeds 15 percent.

`english-catalog-rating-v1.policy.json` remains immutable historical policy
evidence. Its no-speech caps are reproducible, but new candidates use v2.

Verify the exact installed artifact and collect one immutable run with:

```bash
./run_english_catalog_rating.sh \
  20260722-whisper-small-r1 \
  ggml-small.en-q5_1 \
  "$HOME/Library/Application Support/Textify/Models/installed/ggml-small.en-q5_1" \
  whisper \
  --whisper-model "$HOME/Library/Application Support/Textify/Models/installed/ggml-small.en-q5_1/ggml-small.en-q5_1.bin"
```

Repeat with new run IDs twice, then generate an unsigned candidate:

```bash
./generate_english_catalog_rating.sh \
  ggml-small.en-q5_1 \
  2026-07-22T00:00:00Z \
  20260722-whisper-small-r1 \
  20260722-whisper-small-r2 \
  20260722-whisper-small-r3 \
  /tmp/ggml-small.en-q5_1.rating.json
```

The generator rebuilds summaries from the pinned manifests and raw result
files. It rejects a changed artifact fingerprint, suite hash, model/backend,
runtime version, license, compute route, feed mode, host, Git revision,
resident-session counts, or incomplete production-filtered run. It never edits
or signs `models/manifest.json`. Rating collection requires a clean Git
checkout; the resulting source revision is carried into the candidate and the
signed manifest-v2 evidence.

Nightly automation is configured by a runner-local JSON file with
`schemaVersion`, a non-empty `models` array, and for each model its
catalog `id`, installed `artifactDirectory`, benchmark `engine`,
paired `engineOptions`, and an optional reviewed `baseline` candidate. A model
not yet in production may also name an absolute `catalogManifest` path to its
unsigned candidate catalog; the runner uses that file only to verify the exact
declared artifact bytes and never signs or publishes it.
Set the repository variable `TEXTIFY_CATALOG_RATING_CONFIG` to that
absolute file path on the self-hosted `textify-m4-max` runner.

```json
{
  "schemaVersion": 1,
  "models": [
    {
      "id": "ggml-small.en-q5_1",
      "artifactDirectory": "/Users/runner/TextifyModels/ggml-small.en-q5_1",
      "engine": "whisper",
      "engineOptions": [
        "--whisper-model",
        "/Users/runner/TextifyModels/ggml-small.en-q5_1/ggml-small.en-q5_1.bin"
      ],
      "baseline": "/Users/runner/TextifyBaselines/ggml-small.en-q5_1.json"
    }
  ]
}
```

The scheduled workflow creates three fresh runs per configured model, unsigned
candidate JSON, and regression reports. A report fails on a user-visible level
drop, an excessive score or component-WER regression, a no-speech increase, a
speed regression, or a newly unstable speed cohort. The workflow has read-only repository permissions
and contains no signing or publishing step. A maintainer must separately review
a candidate, insert it into a manifest-v2 model entry, and sign that exact
manifest.

```bash
cd Benchmarks/RealtimeASR
./prepare_synthetic_corpus.sh
./prepare_public_corpus.sh
./prepare_open_asr_english_pr.sh
./prepare_open_asr_english_nightly.sh
./prepare_edacc_english_nightly.sh
./prepare_berst_english_nightly.sh
./prepare_voice_code_bench_english_nightly.sh
./prepare_musan_no_speech_pr.sh
./prepare_musan_no_speech_nightly.sh
./prepare_aishell1_sample.sh
./prepare_jsut_sample.sh
./prepare_whisper_metal.sh
./prepare_mlx_metal.sh

swift run -c release TextifyRealtimeBenchmark \
  --engine apple-dictation-analyzer \
  --audio .benchmark-data/synthetic/short.aiff \
  --reference "Textify should show useful words while I am still speaking." \
  --output results/apple-dictation-short.json

swift run -c release TextifyRealtimeBenchmark \
  --engine apple-speech-analyzer \
  --audio .benchmark-data/synthetic/short.aiff \
  --reference "Textify should show useful words while I am still speaking." \
  --output results/apple-speech-short.json

swift run -c release TextifyRealtimeBenchmark \
  --engine whisper \
  --audio .benchmark-data/synthetic/short.aiff \
  --reference "Textify should show useful words while I am still speaking." \
  --whisper-model "$HOME/Library/Application Support/Textify/Models/installed/ggml-small.en-q5_1/ggml-small.en-q5_1.bin" \
  --output results/whisper-short.json

swift run -c release TextifyRealtimeBenchmark \
  --engine parakeet-eou-160 \
  --audio .benchmark-data/synthetic/short.aiff \
  --reference "Textify should show useful words while I am still speaking." \
  --output results/parakeet-eou-short.json

swift run -c release TextifyRealtimeBenchmark \
  --engine parakeet-unified-320 \
  --audio .benchmark-data/synthetic/short.aiff \
  --reference "Textify should show useful words while I am still speaking." \
  --output results/parakeet-unified-short.json

swift run -c release TextifyRealtimeBenchmark \
  --engine parakeet-tdt-v3 \
  --audio .benchmark-data/synthetic/short.aiff \
  --reference "Textify should show useful words while I am still speaking." \
  --fluid-cache "$HOME/Library/Application Support/FluidAudio/Models" \
  --output results/parakeet-tdt-v3-short.json

swift run -c release TextifyRealtimeBenchmark \
  --engine paraformer-large-zh-int8 \
  --audio .benchmark-data/aishell1-sample/0.wav \
  --reference "甚至出现交易几乎停滞的情况" \
  --fluid-cache "$HOME/Library/Application Support/FluidAudio/Models" \
  --feed-mode accelerated \
  --output results/paraformer-aishell1-0.json

swift run -c release TextifyRealtimeBenchmark \
  --engine mlx-parakeet-rnnt-1.1b \
  --audio .benchmark-data/openslr31/LibriSpeech/dev-clean-2/1272/141231/1272-141231-0000.flac \
  --reference "A MAN SAID TO THE UNIVERSE SIR I EXIST" \
  --mlx-model .benchmark-data/parakeet-rnnt-1.1b \
  --feed-mode accelerated \
  --output results/parakeet-rnnt-1.1b-openslr31-0000.json

swift run -c release TextifyRealtimeBenchmark \
  --engine mlx-whisper-large-v3-turbo \
  --audio .benchmark-data/openslr31/LibriSpeech/dev-clean-2/1272/141231/1272-141231-0000.flac \
  --reference "A MAN SAID TO THE UNIVERSE SIR I EXIST" \
  --mlx-model .benchmark-data/mlx-whisper-large-v3-turbo \
  --feed-mode accelerated \
  --output results/mlx-whisper-large-v3-turbo-openslr31-0000.json

swift run -c release TextifyRealtimeBenchmark \
  --engine mlx-qwen3-asr-0.6b-8bit \
  --audio .benchmark-data/openslr31/LibriSpeech/dev-clean-2/1272/141231/1272-141231-0000.flac \
  --reference "A MAN SAID TO THE UNIVERSE SIR I EXIST" \
  --mlx-model /path/to/Qwen3-ASR-0.6B-8bit \
  --feed-mode accelerated \
  --output results/mlx-qwen3-asr-0.6b-8bit-openslr31-0000.json

swift run -c release TextifyRealtimeBenchmark \
  --engine transcribe-qwen3-asr-0.6b \
  --audio .benchmark-data/openslr31/LibriSpeech/dev-clean-2/1272/141231/1272-141231-0000.flac \
  --reference "A MAN SAID TO THE UNIVERSE SIR I EXIST" \
  --transcribe-runtime ../../Vendor/transcribe.cpp/v0.1.3/lib \
  --transcribe-model /path/to/Qwen3-ASR-0.6B-Q5_K_M.gguf \
  --feed-mode accelerated \
  --output results/transcribe-qwen3-asr-0.6b-q5-k-m-openslr31-0000.json

swift run -c release TextifyRealtimeBenchmark \
  --engine litert-gemma-4-12b \
  --audio .benchmark-data/openslr31/LibriSpeech/dev-clean-2/1272/141231/1272-141231-0000.flac \
  --reference "A MAN SAID TO THE UNIVERSE SIR I EXIST" \
  --litert-model .benchmark-data/gemma-4-12b-litert-lm/gemma-4-12B-it.litertlm \
  --litert-cache .benchmark-data/gemma-4-12b-litert-cache \
  --feed-mode accelerated \
  --output results/gemma-4-12b-openslr31-0000.json
```

Use `--feed-mode accelerated` for a throughput-only run. The default
`realtime` mode schedules audio buffers at their original capture cadence so
that first-partial and release-to-final measurements include inference
backpressure.

Run the fixed public subset across every engine with:

```bash
./run_public_corpus.sh accelerated \
  "/path/to/ggml-small.en-q5_1.bin" \
  "$HOME/Library/Application Support/FluidAudio/Models"
```

Run the fixed Mandarin sample with:

```bash
./run_aishell1_sample.sh \
  "$HOME/Library/Application Support/FluidAudio/Models"
```

Run the fixed Japanese sample with:

```bash
./run_jsut_sample.sh \
  "$HOME/Library/Application Support/FluidAudio/Models"
```

Run the same Japanese sample through any Whisper-compatible model with:

```bash
./run_jsut_whisper_sample.sh /path/to/model.bin optional-result-label
```

Run the exact ReazonSpeech K2 V2 int8 ONNX export through Textify's pinned
sherpa-onnx runtime with:

```bash
./run_jsut_reazonspeech_sample.sh /path/to/reazonspeech-k2-v2-int8
```

Run SenseVoiceSmall or another sherpa evaluation path directly with:

```bash
swift run -c release TextifyRealtimeBenchmark \
  --engine sensevoice-small-int8 \
  --audio .benchmark-data/jsut-basic5000-sample/basic5000/wav/BASIC5000_4503.wav \
  --language auto \
  --sherpa-runtime ../../Vendor/sherpa-onnx/v1.13.2/lib \
  --sherpa-model /path/to/sensevoice-small-int8-2024-07-17 \
  --sherpa-provider cpu \
  --sherpa-threads 4 \
  --feed-mode accelerated
```

Run the fixed Hindi FLEURS sample with:

```bash
./run_fleurs_hi_in_sample.sh /path/to/multilingual-whisper-model.bin
```

The Whisper preparation step compiles the same vendored ggml Metal shader into
the benchmark executable directory. Without that artifact, whisper.cpp can
silently fall back to CPU in a command-line SwiftPM build.

The MLX preparation step embeds Textify's hash-verified `mlx.metallib` beside
the release benchmark executable. MLX Swift documents that command-line
SwiftPM cannot compile these shaders; without the distinct library, MLX Audio
fails closed instead of falling back to a different compute path.

Synthetic speech is a reproducible smoke corpus, not the accuracy gate. Engine
selection also uses the ten-speaker fixed subset in `Corpus/openslr31.json` and
later representative manual dictation on the oldest supported Apple Silicon
hardware. The English public corpus comes from OpenSLR Mini LibriSpeech under
CC BY 4.0. The Mandarin sample comes from AISHELL-1 under Apache-2.0 through the
Hugging Face Dataset Viewer. The Japanese sample comes from JSUT basic5000
under the mixed attribution/share-alike terms recorded in its corpus metadata.
The Hindi sample uses rows 0–9 of the FLEURS `hi_in` validation split at commit
`70bb2e84b976b7e960aa89f1c648e09c59f894dd` under CC-BY-4.0. Its preparation
script refreshes Dataset Viewer URLs but requires that exact revision in each
asset path and verifies every WAV byte size and SHA-256. Downloaded data remains
outside source control; corpus metadata and exact audio checksums are tracked.

The Fun-ASR MLT evaluation uses ten fixed FLEURS validation clips for each of
the model's 31 claimed languages at the same dataset commit. Generate and
verify the corpus, then run the exact Q8_0 production candidate through the
pinned patched transcribe.cpp CLI with Metal and the same 4,096-token context
cap as Textify:

```bash
./generate_fleurs_funasr_mlt_sample.sh
./prepare_fleurs_funasr_mlt_sample.sh
./run_funasr_mlt_sample.py \
  --cli /path/to/transcribe.cpp/build/bin/transcribe-cli \
  --model /path/to/Fun-ASR-MLT-Nano-2512-Q8_0.gguf
```

When the Dataset Viewer cannot render a language, generation streams the first
ten audio members from that language's immutable raw `dev.tar.gz` (the source
of the Hub `validation` split). The helper verifies the pinned LFS SHA metadata,
archive size, TSV size and TSV SHA-256, then the corpus records each extracted
WAV's size and SHA-256. This avoids decoding entire single-row-group Parquet
shards merely to select ten clips.

Run the focused promotion stress suite after the full language sweep:

```bash
./prepare_funasr_mlt_stress.sh
./run_funasr_mlt_stress.py \
  --cli /path/to/transcribe.cpp/build/bin/transcribe-cli \
  --model /path/to/Fun-ASR-MLT-Nano-2512-Q8_0.gguf
```

This checks loudness-normalized real FLEURS speech mixed with a fixed white
noise floor in every promoted language, five seconds of digital silence under every language
prompt, ten available system-voice one-word cases, three English accents,
technical terms, punctuation/numerals, English-Mandarin code switching, and a
59.5-second recording. System-voice fixtures are reproducible smoke/stress
inputs rather than accuracy evidence; the FLEURS sweep remains the quality
gate. The result records the host OS because installed `say` voices may change
between macOS releases.
