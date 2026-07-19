# Multi-Model Benchmark Report — 2026-07-19

This report compares the curated English model choices across Textify's two
shipping runtime families on the same Apple M4 Max, macOS 26.5.1 host. Every
candidate received identical 16 kHz mono audio and ran fully offline after its
model assets were present. Results are reproducible from
`Benchmarks/RealtimeASR`.

## Fixed OpenSLR subset

The primary comparison uses ten speakers and 210 reference words from the
fixed OpenSLR 31 subset in accelerated mode.

| Runtime | Corpus WER | Final median | Final p95/max | Target |
| --- | ---: | ---: | ---: | --- |
| Whisper small.en q5_1 / Metal | 3.33% | 141.5 ms | 208 ms | Pass |
| Whisper Large V3 Turbo q5_0 / Metal | 4.29% | 367 ms | 415 ms | Specialist |
| Parakeet TDT 0.6B V3 int8 / Core ML ANE | 2.38% | 66 ms | 87 ms | Pass |
| Parakeet TDT 0.6B V2 int8 / Core ML ANE | **0.95%** | 64 ms | 74 ms | Pass |
| Parakeet TDT-CTC 110M / Core ML ANE | 2.38% | **38.5 ms** | **51 ms** | Pass |

On this corpus and machine, V2 produced the fewest word errors, while 110M was
the fastest and matched V3's corpus WER. Every choice remained comfortably
below the 700 ms release-to-final target. These narrow results justify the
Accurate and Fast picker tiers but do not imply that either English-only model
replaces multilingual V3.

## Synthetic smoke corpus

The three generated samples cover a short phrase, technical vocabulary, and a
paragraph. They are useful for regression checks but are not an accuracy gate.

| Runtime | Aggregate WER | Final latency range |
| --- | ---: | ---: |
| Whisper small.en q5_1 / Metal | 5.45% | 123–191 ms |
| Parakeet TDT 0.6B V3 int8 / Core ML ANE | 9.09% | 71–87 ms |

Parakeet was faster on all three samples. Whisper made no errors on the
paragraph while Parakeet made two, which is why Textify keeps Whisper as a
first-class backend and fallback instead of replacing it.

## Cold-start and memory interpretation

The first Parakeet run after Core ML compilation took 12.7 seconds to load and
peaked at 529 MB RSS. The comparable first Whisper run took 8.7 seconds and
peaked at 329 MB. Subsequent process runs benefited from Core ML's compiled
model cache, so those load and memory numbers must not be presented as clean
machine measurements.

Interactive dictation uses a resident, pre-warmed session, making
release-to-final latency the relevant user-facing number. The fixed-corpus
result plus a clean isolated signed-catalog install support Parakeet V3's
Recommended promotion. Broader multilingual, noisy-audio, accent, energy, and
oldest-supported-Apple-Silicon coverage remain ongoing release QA rather than
claims implied by this narrow benchmark.

## Promotion decision

Parakeet TDT V3 remains the Recommended multilingual choice and is not a
universal replacement for Whisper. V2 is promoted as the Accurate English
tier, and TDT-CTC 110M as the Fast English tier. The signed catalog keeps all
four English choices because language coverage, quality, download size,
memory, and cold preparation differ. Other implemented variants and additional
open-source families remain unpromoted until they pass the same artifact,
license, quality, latency, memory, fallback, and clean-build gates.

Whisper Turbo, all four promoted Parakeet variants, Paraformer, ReazonSpeech,
and SenseVoiceSmall passed a clean signed-catalog test. The exact Turbo file,
79 Parakeet files, 17 Paraformer files, four ReazonSpeech files, and two
SenseVoice files were downloaded into isolated
managed storage, size/SHA-256 verified, atomically installed, loaded with
network fallback disabled, checked for the required Metal, Neural Engine, or
declared CPU route, and used to transcribe language-matched fixtures. The test
fetched and verified 103 Hugging Face catalog files in 1,300.342 seconds
without failure. Two small commit-pinned upstream fixtures separately exercised
SenseVoice's Korean and Cantonese automatic-language paths.

## ReazonSpeech K2 V2 Japanese promotion

The official Apache-2.0 four-file int8 ONNX export from
`reazon-research/reazonspeech-k2-v2` is pinned at commit
`291488c8151be24d7da4bf7af26e533fad96e407` and totals 160,372,200 bytes.
Textify runs it through exact arm64 sherpa-onnx 1.13.2 and ONNX Runtime 1.24.4
libraries. The recognizer stays resident; interactive measurements exclude
cold model loading and report completed-recording release to final output.

| Runtime | Corpus CER | Final median | Final p95/max | Cold load | Peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| ReazonSpeech K2 V2 int8 / CPU | 14.61% | 86 ms | 413 ms | ~1.3 s | 551 MB |
| Parakeet Japanese int8 / Core ML ANE | **13.11%** | **60.5 ms** | **406 ms** | ~37 s first preparation | 694 MB |

The ten JSUT clips contain 267 normalized reference characters; Reazon made 39
character edits. A 29-second stress clip finalized in 954 ms with about 744 MB
peak RSS. The runtime hard-rejects audio longer than its signed 29-second
product limit. Five seconds of digital silence yielded a low-confidence filler
whose mean log probability was below the signed `-1.0` acceptance threshold,
so the production finalizer discards it.

Core ML was tested rather than assumed. On the same 10.72-second JSUT clip it
took 378 ms after a 4.7-second load and used about 1.14 GB RSS. CPU was faster
and used roughly half the memory, so the production catalog explicitly declares
the CPU provider. Reazon is promoted as a compact Fast Japanese alternative:
it trades 1.50 percentage points of CER for a roughly 160 MB download and much
shorter cold preparation than Parakeet Japanese.

The final staged-app smoke used the signed libraries under
`Textify.app/Contents/Frameworks`, produced the exact reference sentence, and
finalized in 503 ms. Reproduce the fixed sample with:

```bash
Benchmarks/RealtimeASR/run_jsut_reazonspeech_sample.sh \
  /path/to/reazonspeech-k2-v2-int8
```

## SenseVoiceSmall multilingual promotion

The general-purpose 2024 SenseVoiceSmall int8 export—not the later
Cantonese-specific fine-tune with a similar repository name—is pinned at
`2365baeacb507f821a0c8120fcee3d484dba7a07`. Its model and token table total
239,549,735 bytes and run through Textify's existing sherpa-onnx boundary.

| Corpus | Error rate | Final median | Final p95/max | Warm load | Peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| JSUT Japanese, 267 chars | **10.86% CER** | 138.5 ms | 311 ms | 312–321 ms | 739 MB |
| OpenSLR English, 210 words | 3.81% WER | 222.5 ms | 390 ms | 313–320 ms | 612 MB |
| AISHELL-1 Mandarin, 130 chars | 6.15% CER | 128 ms | 163 ms | 316–323 ms | 594 MB |

This is Textify's best measured Japanese corpus result, ahead of Parakeet
Japanese at 13.11% CER and ReazonSpeech at 14.61% CER. Automatic language
selection was then checked separately on representative Japanese, Mandarin,
and English fixtures, plus the exact upstream Korean and Cantonese WAV files.
All five produced useful output in the correct language/script; those smoke
finalizations ranged from 91 to 159 ms. Five seconds of digital silence caused
the model to emit a short Mandarin token, so Textify added a production
no-speech backstop for punctuation-only and below -60 dBFS input. The app's
adaptive speech detector and -45 dBFS edge trimmer run before this model-level
backstop.

A 29-second stress recording finalized in 882 ms at about 646 MB RSS. That
maximum-duration result is disclosed and keeps SenseVoice in the Accurate tier,
while normal fixed-corpus finalizations stayed below 390 ms. Core ML did not
help: the longest Japanese fixture took 332 ms after a 2.04-second load versus
311 ms after a 319 ms CPU load. The production entry therefore declares CPU.

The weight license is FunASR Model Open Source License Agreement 1.1, which
allows use, copying, modification, and sharing subject to attribution and model
name retention. An official FunASR/SenseVoice project member confirmed paid
commercial desktop use. The signed entry retains the SenseVoiceSmall name and
points at the immutable license text; the app ships the same text and required
attribution.

The final staged-app smoke loaded the separately signed sherpa-onnx and ONNX
Runtime dylibs from `Textify.app/Contents/Frameworks`, automatically selected
Japanese, produced the zero-CER reference sentence, and finalized in 91 ms
after a 26 ms warmup. This proves the distributable app layout rather than only
the workspace vendor directory.

## Additional sherpa-onnx candidate decisions

Three additional exact int8 candidates were evaluated through the same C/Swift
runtime boundary and remain deliberately absent from the production adapter.

| Candidate | Fixed-corpus result | Final latency | Peak RSS | Decision |
| --- | --- | ---: | ---: | --- |
| Qwen3-ASR 0.6B | Hindi 12.95% WER / 13.11% CER | 2.22 s median, 3.42 s p95/max | 2.15 GB | Defer: quality is promising, but ordinary finalization and memory are not interactive; 29-second output was incomplete even at 512 tokens. |
| Omnilingual ASR CTC 300M | Hindi 23.18% WER / 31.24% CER | 754 ms median, 1.50 s p95/max | 1.02 GB | Defer: enormous language coverage, but worse Hindi quality than promoted Turbo and outside the latency target. |
| Dolphin Small CTC multilingual | Hindi 33.86% WER / 35.37% CER; Japanese 18.35% CER | 228 ms Hindi median; ~93 ms Japanese median | 814 MB | Defer: fast, but substantially less accurate than existing Hindi and Japanese choices. |

Qwen's exact six files total 987,015,347 bytes at commit
`68818b2313fe77bd06f6a7c5068ff3ef59d02b8a`. Its Core ML provider took
15.45 seconds and about 8.20 GB RSS on the comparison fixture. Omnilingual's
365,438,543 bytes are pinned at
`6abf1ece20cd2308bdb7d13cd78ec1c44fa4c094`; Core ML took 2.92 seconds and
about 12.28 GB. Dolphin's 250,163,616 bytes are pinned at
`c8b6689509acfcd744c04e5e169164f9ac4cae32`. These runs reinforce the product
rule that merely selecting a Core ML execution provider is not evidence of a
useful Apple acceleration path.

## Whisper Large V3 Turbo specialist and Distil comparison

The official GGML `ggml-large-v3-turbo-q5_0.bin` artifact is 574,041,195 bytes
with SHA-256
`394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`.
It loaded through Textify's pinned whisper.cpp v1.7.6 runtime with Metal active.

| Corpus | Error rate | Final median | Final p95/max | Peak RSS |
| --- | ---: | ---: | ---: | ---: |
| OpenSLR English, 210 words | 4.29% WER | 367 ms | 415 ms | 692 MB |
| FLEURS `hi_in`, 440 words/557 chars | 22.05% WER / 20.47% CER | 536.5 ms | 734 ms | 691 MB |

The Hindi fixture is the first ten validation rows of `google/fleurs` pinned at
commit `70bb2e84b976b7e960aa89f1c648e09c59f894dd`. One Hindi utterance took
734 ms, so Turbo is not a Recommended-tier latency pass. It is promoted only
as an English/Hindi Specialist, with the measured latency, quality, download,
and memory costs shown in the picker.

Distil-Whisper Large V3.5 was also run against the same English sample using
the official `distil-whisper/distil-large-v3.5-ggml` artifact at commit
`960ecb5c2ecfba3ebb9ebe485c1032ec266cf436`. It produced the same 4.29% WER,
a 352 ms median, and 387 ms p95/max, but the unquantized file is 1,519,521,155
bytes, peak RSS was about 1.62 GB, and the model is English-only. A 15 ms median
advantage does not justify roughly 2.7x the download and 2.3x the memory, so it
is explicitly deferred rather than added as a redundant picker choice.

## Moonshine V2 Tiny English runtime audit

Released sherpa-onnx v1.13.2 was tested with the exact quantized English model
from `csukuangfj2/sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27` at commit
`d1e6c30921780b8508d04b492dfb3ce8a51605d4`. The encoder, merged decoder, and
tokens total about 44 MB. On CPU, the seven OpenSLR clips at or below 9.02
seconds decoded in 29–110 ms and the first smoke fixture was exact. The three
clips from 11.48 to 13.31 seconds all failed with an ONNX broadcast error and
empty transcripts because this export has an approximately ten-second window.

Core ML was not an optimization for this model. The exact 4.65-second smoke
fixture took 58 ms on CPU with about 177 MB peak RSS; selecting the Core ML
provider took 1.947 seconds with about 331 MB peak RSS after a 4.1-second load.
Moonshine therefore remains deferred until Textify has boundary-aware chunking
with accuracy tests. It must not silently truncate or lower the normal recording
limit merely to add a small picker entry.

## Kotoba-Whisper V2 Japanese comparison

The official Apache-2.0
`kotoba-tech/kotoba-whisper-v2.0-ggml/ggml-kotoba-whisper-v2.0-q5_0.bin`
artifact was pinned at commit `e3a0cf6a62b95911703cfb97d819292e058f12c3`.
The file is 537,819,875 bytes with SHA-256
`4a3b92192b5d3578ff854a5876213e2e27af0c2d357492c2d14271e82c303658`.
It loaded through Textify's existing whisper.cpp v1.7.6 Metal path and was run
against the same ten JSUT fixtures as Parakeet Japanese.

| Runtime | Corpus CER | Final median | Final p95/max | Peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Kotoba-Whisper V2.0 q5_0 / Metal | 18.73% | 507.5 ms | 700 ms | 633 MB |
| Parakeet Japanese int8 / Core ML ANE | **13.11%** | **60.5 ms** | **406 ms** | 694 MB |

Kotoba's first process load took 24.7 seconds; later loads were 324–743 ms. It
is smaller and used slightly less peak memory than Parakeet, but it was less
accurate and roughly eight times slower at the median. Textify therefore records
it as a tested, compatible, legally eligible model that is not promoted because
it adds no measured user benefit.

Reproduce with:

```bash
Benchmarks/RealtimeASR/run_jsut_whisper_sample.sh \
  /path/to/ggml-kotoba-whisper-v2.0-q5_0.bin \
  kotoba-whisper-v2.0-q5_0
```

## Parakeet Japanese specialist

The released Parakeet Japanese int8 Core ML path was evaluated against ten
fixed utterances from the public `FluidInference/JSUT-basic5000` test subset.
As with Mandarin, Textify reports character error rate rather than unreliable
whitespace-derived Japanese word error rate.

| Runtime | Corpus CER | Final median | Final p95/max | Warm process load |
| --- | ---: | ---: | ---: | ---: |
| Parakeet TDT-CTC 0.6B Japanese int8 / Core ML ANE | 13.11% | 60.5 ms | 406 ms | 281–739 ms |

The ten clips contain 267 normalized reference characters and 35 character
edits. All finalizations stayed below the 700 ms target. Peak RSS was about
694 MB. The first executable-specific Core ML preparation took 37.4 seconds;
later processes loaded in hundreds of milliseconds. The exact 21-file,
619,065,246-byte artifact set is pinned to commit
`2952296ff1da4a6d6a7aec545e226367db80c612` and its encoder compute plan proved
Apple Neural Engine-preferred operations.

Reproduce the sample and results with:

```bash
Benchmarks/RealtimeASR/run_jsut_sample.sh \
  "$HOME/Library/Application Support/FluidAudio/Models"
```

## Paraformer Chinese specialist

The released FluidAudio 0.15.5 Paraformer-large Chinese int8 path was evaluated
against the fixed first ten rows of the public AISHELL-1 test derivative. The
benchmark records character error rate because Mandarin does not have reliable
whitespace-delimited words.

| Runtime | Corpus CER | Final median | Final p95/max | Warm process load |
| --- | ---: | ---: | ---: | ---: |
| Paraformer-large zh int8 / Core ML ANE | 5.38% | 66 ms | 75 ms | 348–391 ms |

The ten clips contain 130 reference characters; seven character edits occurred.
Eight clips were exact. The model truncated four trailing characters on one
clip and made three character edits on another. Peak RSS during the warm
per-process runs was about 68 MB.

The important caveat is first preparation. Core ML performed executable-specific
ANE AOT compilation for about 146 seconds in the first benchmark process. A
subsequent launch of the same executable loaded in roughly 0.35 seconds. Because
Textify keeps the selected model resident, release-to-final behavior is
excellent after preparation, but this cold cost disqualifies Paraformer from
Recommended/Fast. It ships only as a Mandarin Specialist with an explicit
first-preparation warning. Its exact commit-pinned artifacts passed the signed
catalog clean-download, load, ANE-verification, and fixture-transcription
integration; final Developer ID artifact QA remains separate.

Input length is a separate product constraint: the released Core ML
preprocessor accepts at most 30 seconds of 16 kHz audio. Textify therefore caps
signed Paraformer entries at 29 seconds and rejects any buffer beyond the native
30-second window instead of allowing FluidAudio's fixed decoder path to
truncate it.

Reproduce the sample and results with:

```bash
Benchmarks/RealtimeASR/run_aishell1_sample.sh \
  "$HOME/Library/Application Support/FluidAudio/Models"
```

The benchmark's runtime first verifies Neural Engine-preferred operations for
both the int8 encoder and decoder. FluidAudio network access is disabled by the
Textify runtime after the signed artifacts are installed.
