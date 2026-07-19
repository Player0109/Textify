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
- `qwen3-asr-0.6b`, `omnilingual-asr-300m-ctc-int8`, and
  `dolphin-small-ctc-multi-lang-int8`: exact-artifact evaluation-only paths;
  their measured support decisions are recorded in the benchmark report.

Model downloads are cached outside the repository under
`~/Library/Caches/io.github.Player0109.Textify/RealtimeBenchmark/Models`.
Generated audio, builds, and JSON run results are ignored by Git.

## Run

```bash
cd Benchmarks/RealtimeASR
./prepare_synthetic_corpus.sh
./prepare_public_corpus.sh
./prepare_aishell1_sample.sh
./prepare_jsut_sample.sh
./prepare_whisper_metal.sh

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
