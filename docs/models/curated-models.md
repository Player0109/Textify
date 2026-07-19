# Textify Curated Models

The signed catalog shipped with the current app contains nine curated
production choices: Whisper small.en; Whisper Large V3 Turbo q5_0; Parakeet
TDT 0.6B V3, V2, and TDT-CTC 110M; Parakeet Japanese; and the Paraformer
Chinese specialist; ReazonSpeech K2 V2 Japanese; and SenseVoiceSmall for
English, Mandarin, Cantonese, Japanese, and Korean. The catalog and signature
are bundled; model weights remain external and are downloaded only after the
user chooses a model.

The GitHub Pages catalog may temporarily lag an app release. Textify verifies
the bundled and remote catalogs independently and selects the whole catalog
with the newer signed `generatedAt` timestamp. A model is visible only after
its exact artifacts, checksums, provenance, licenses, runtime, accelerator,
capabilities, support tier, finalization/accuracy guidance, requirements, and
minimum app version are in that selected catalog.

## Balanced - Whisper small.en q5_1

- Model id: `ggml-small.en-q5_1`
- Display name: `Balanced - Whisper small.en q5_1`
- File: `ggml-small.en-q5_1.bin`
- Language: English only
- Source: `ggerganov/whisper.cpp`
- Source file: `ggml-small.en-q5_1.bin`
- Textify asset URL shape: `https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.bin`

The manifest `sha256` value must be computed from the exact uploaded Textify
GitHub Release asset bytes, not from an upstream URL, local placeholder, or a
file before final upload verification.

```bash
shasum -a 256 ggml-small.en-q5_1.bin
```

Release manifests must not ship with placeholder checksums, placeholder sizes,
or non-Textify download URLs. If the model bytes change, publish a new immutable
release asset URL and sign a new manifest for those bytes.

## Supported runtime families

### Whisper.cpp / Metal GPU

The signed catalog can publish Whisper GGML variants across tiny, base, small,
medium, large, quantized, distilled, English-only, and multilingual tiers. Each
entry remains a separate curated artifact with its own measured quality,
release-to-final latency, memory use, language capability, and license record.

Users may also import a local Whisper-compatible GGML/GGUF file. Textify checks
that it is a regular file, enforces size limits, recognizes the container
header, hashes and copies it into managed storage, and requires the native
Whisper runtime to load and warm it before activation. Textify labels the
license as user-provided and does not claim that an imported file is safe or
properly licensed.

Whisper Large V3 Turbo q5_0 is published as the English/Hindi Specialist under
catalog id `whisper-large-v3-turbo-q5_0`. Its single 574,041,195-byte artifact
comes directly from `ggerganov/whisper.cpp` at commit
`5359861c739e955e79d9a303bcbc70fb988958b1`; SHA-256 is
`394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`.
Both the OpenAI model and whisper.cpp conversion/runtime layers are MIT.

On the fixed English OpenSLR sample it measured 4.29% corpus WER, 367 ms median
finalization, and 415 ms p95/max. On the fixed Hindi FLEURS `hi_in` sample it
measured 22.05% WER and 20.47% CER, with 536.5 ms median and 734 ms p95/max.
Peak RSS was about 700 MB. The one Hindi clip over the 700 ms Recommended-tier
target and the narrow two-language evidence keep it Specialist. Textify exposes
only English, Hindi, and automatic selection for this entry until additional
languages pass the same gate.

### FluidAudio Parakeet / Core ML Neural Engine

The native runtime supports these catalog variants through pinned FluidAudio
`0.15.5`:

- Parakeet TDT 0.6B V2 (English)
- Parakeet TDT 0.6B V3 (25 European languages)
- Parakeet TDT-CTC 110M
- Parakeet TDT Japanese

Textify requires macOS 14.4 or newer for a Parakeet catalog entry because it
uses `MLComputePlan` to prove that the compiled encoder actually prefers the
Apple Neural Engine. Merely requesting `.cpuAndNeuralEngine` is not accepted as
accelerator evidence.

Parakeet V3 is promoted as `parakeet-tdt-0.6b-v3` in the Recommended tier. The
catalog selects 21 int8 runtime leaves totaling 483,105,645 bytes from
`FluidInference/parakeet-tdt-0.6b-v3-coreml` at commit
`aed02740059203c4a87495924f685de3722ae9ce`. It intentionally excludes duplicate
and source variants from that repository. The model weights are CC-BY-4.0;
FluidAudio runtime/conversion code is Apache-2.0.

Every file uses an exact commit-pinned Hugging Face URL, safe relative path,
byte size, and SHA-256. The installer stages and verifies every leaf before
atomically replacing the installed model directory. FluidAudio network access
is disabled in the app runtime; missing or corrupt artifacts fail closed.

Parakeet TDT-CTC 110M is published as the English-only Fast tier. Its 16
runtime leaves total 227,466,209 bytes and come from
`FluidInference/parakeet-tdt-ctc-110m-coreml` at commit
`9bc92ead6e8f17eca92a869fd578ae76842b82ba`. The fused preprocessor contains
the encoder, so Textify verifies that component—not a nonexistent standalone
encoder—for Neural Engine-preferred operations. A native smoke run produced an
exact transcript in 68 ms after warm load on the M4 Max test host.

Parakeet V2 is published as the English-only Accurate tier. Its 21 int8 runtime
leaves total 464,413,247 bytes and come from
`FluidInference/parakeet-tdt-0.6b-v2-coreml` at commit
`ee09c569f73759e6d44c9bd16766f477b2b36d39`. A native smoke run produced an
exact transcript in 75 ms; its first executable-specific Core ML preparation
took about 70 seconds on the M4 Max test host, which is disclosed in the model
picker.

Both entries inherit the upstream CC-BY-4.0 model terms and the pinned
Apache-2.0 FluidAudio runtime. On the fixed 210-word OpenSLR subset, 110M
measured 2.38% corpus WER with 38.5 ms median and 51 ms p95/max finalization;
V2 measured 0.95% WER with 64 ms median and 74 ms p95/max. Both also passed the
clean signed-catalog download, atomic install, offline load, ANE verification,
and fixture-transcription gate.

Parakeet Japanese is published as the Japanese-only Specialist tier under the
FluidAudio-compatible catalog id `parakeet-ja`. Its 21 int8 runtime leaves total
619,065,246 bytes and come from `FluidInference/parakeet-0.6b-ja-coreml` at
commit `2952296ff1da4a6d6a7aec545e226367db80c612`. The original and derived model
weights are CC-BY-4.0, and the pinned FluidAudio runtime is Apache-2.0.

On Textify's fixed ten-utterance JSUT sample it measured 13.11% corpus CER,
60.5 ms median finalization, and 406 ms p95/max on the M4 Max test host. Peak
RSS was about 694 MB. The first executable-specific Core ML preparation took
37.4 seconds; warm process loads were 281–739 ms. Its signed picker guidance
discloses the Japanese-only coverage, 619 MB download, accuracy result, and
first-preparation cost.

### FluidAudio Paraformer / Core ML Neural Engine

The runtime publishes `paraformer-large-zh-int8` as a Mandarin Chinese
Specialist. It uses the released FluidAudio 0.15.5
non-autoregressive pipeline: CPU feature extraction, Core ML
encoder/CIF/decoder stages, and host-side integrate-and-fire. Textify verifies
that both the int8 encoder and decoder have Neural Engine-preferred operations
before accepting the model.

The catalog selects 17 int8 runtime leaves totaling 222,136,057 bytes from
`FluidInference/paraformer-large-zh-coreml` at commit
`5dd557bd06342a3cd07ceccb909d8a45e48b053a`. The upstream/derived model and
FluidAudio layers are recorded as Apache-2.0.

The fixed ten-utterance AISHELL-1 sample measured 5.38% corpus CER, 66 ms median
release-to-final latency, and 75 ms maximum/p95 on the Apple M4 Max test host.
Warm process loads were 348–391 ms. The first executable-specific Core ML AOT
preparation took about 146 seconds in the benchmark process, so this model must
remain Specialist rather than Recommended/Fast and its picker requirements
warns that first preparation can take several minutes. A clean isolated install
downloaded all 17 exact files, loaded the resulting managed directory, proved
ANE-preferred operations, and transcribed a public Mandarin fixture.

The released preprocessor accepts no more than 480,000 samples at 16 kHz (30
seconds). Textify hard-rejects a larger buffer before FluidAudio can truncate
it, and production Paraformer catalog entries are capped at 29 seconds. The
recorder uses the selected model's declared limit and automatically finishes
there instead of recording an unsupported utterance.

### ReazonSpeech / sherpa-onnx CPU

The catalog publishes `reazonspeech-k2-v2-int8` as the compact Fast Japanese
choice. Its official four-file int8 Zipformer transducer export totals
160,372,200 bytes and is pinned to `reazon-research/reazonspeech-k2-v2` commit
`291488c8151be24d7da4bf7af26e533fad96e407`. The model and sherpa-onnx are
Apache-2.0; ONNX Runtime is MIT.

Textify embeds only the exact arm64 sherpa-onnx 1.13.2 C runtime and ONNX
Runtime 1.24.4 libraries, not model weights. It verifies their source hashes,
architecture, nested signatures, and sherpa release version/commit before use.
The loaded recognizer remains resident and creates a fresh stream for each
completed recording.

On the fixed ten-utterance JSUT sample it measured 14.61% corpus CER, 86 ms
median release-to-final latency, and 413 ms p95/max. Cold model load was about
1.3 seconds and peak RSS about 551 MB. A 29-second stress recording finalized
in 954 ms. A five-second silence fixture produced a low-confidence token that
Textify's signed average-log-probability threshold discards.

The CPU provider is intentional. On the same 10.72-second fixture, the Core ML
provider took 378 ms after a 4.7-second load and used about 1.14 GB RSS; CPU was
faster and used roughly half the memory. Reazon is slightly less accurate than
the 13.11% CER Parakeet Japanese entry, but its download is about one quarter
the size and its cold preparation is dramatically shorter. Those distinct
tradeoffs justify keeping both Japanese choices.

### SenseVoiceSmall / sherpa-onnx CPU

The catalog publishes `sensevoice-small-int8-2024-07-17` as the Accurate
five-language choice. The 239,233,841-byte int8 ONNX model and 315,894-byte
token table are pinned to
`csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` commit
`2365baeacb507f821a0c8120fcee3d484dba7a07`. The runtime uses automatic
language identification for English, Mandarin, Cantonese, Japanese, and Korean
and also permits an explicit language selection.

On fixed public samples, SenseVoiceSmall measured 10.86% Japanese CER with
138.5 ms median and 311 ms p95/max finalization, 3.81% English WER with about
223 ms median and 390 ms p95/max, and 6.15% Mandarin CER with 128 ms median and
163 ms p95/max. Automatic selection produced the expected script and content
on the Korean and Cantonese upstream fixtures in 139 ms and 159 ms. Cold model
load was about 0.32 seconds, and the largest fixed-corpus process reached about
739 MB RSS. A 29-second stress recording finalized in 882 ms, so the model is
Accurate rather than Recommended despite its excellent ordinary-dictation
latency.

The CPU provider is again measured rather than assumed. On the longest JSUT
fixture it finalized in 311 ms after a 319 ms CPU load; Core ML took 332 ms
after a 2.04-second load and offered no memory or latency advantage. Textify
therefore publishes the CPU route. SenseVoice can hallucinate a short token on
digital silence, so the runtime marks punctuation-only or below -60 dBFS input as
no speech; normal app recordings have already passed the stricter adaptive
speech detector and -45 dBFS edge trimmer.

SenseVoiceSmall weights use the custom FunASR Model Open Source License
Agreement 1.1. The license permits use, copying, modification, and sharing with
source/author attribution and retention of the model name. An official project
member separately confirmed commercial paid-desktop use. Textify retains the
SenseVoiceSmall name in the picker, includes FunASR/SenseVoice attribution, and
ships a copy of the model license text.

## Evaluated but deferred families

The reusable additional engine boundary is sherpa-onnx v1.13.2 at commit
`13d0ae6c539d2809d32f5eaa3ef1db0c459d0b24`, not one custom runtime per model.
Textify now ships production paths for ReazonSpeech and SenseVoiceSmall. Its
broader released C/Swift evaluation surface covers Qwen3-ASR, Dolphin, and
Omnilingual ASR, while sherpa-onnx also exposes Moonshine V2, Cohere Transcribe,
Fun-ASR Nano, and FireRedASR. Each new architecture
still requires a small explicit shim extension plus exact-artifact quality,
latency, memory, license, and accelerator evaluation. A provider option alone
is not accelerator proof.

| Candidate | Decision |
| --- | --- |
| Distil-Whisper Large V3.5 | Deferred on product fit. Its official 1,519,521,155-byte GGML artifact produced the same 4.29% WER as Turbo on the fixed English sample and was only 15 ms faster at the median, while peaking near 1.62 GB RSS and supporting English only. |
| Kotoba-Whisper V2.0 q5_0 | Deferred with no measured advantage. The official 537,819,875-byte Apache-2.0 GGML artifact reached 18.73% CER, 507.5 ms median, 700 ms p95/max, about 633 MB RSS, and a 24.7-second first load on the same JSUT slice. Promoted Parakeet Japanese measured 13.11% CER and 60.5 ms median, so another Japanese-only download would add choice without adding value. |
| Qwen3-ASR 0.6B int8 ONNX | Deferred on interactive cost. The exact 987,015,347-byte Apache-2.0 artifact reached 12.95% Hindi WER and 13.11% CER, better than Whisper Turbo's Hindi result, but took about 2.22 seconds median and 3.42 seconds p95/max with about 2.15 GB RSS. Core ML regressed to 15.45 seconds and 8.20 GB on one clip; a 29-second Japanese stress clip still ended incomplete at the raised 512-token output limit. |
| Cohere Transcribe 2B | Runtime-capable but license-deferred. Sherpa-onnx v1.13.2 has a released adapter, but the approximately 2.1 GB conversion remains slow for this product and its model page contradicts itself by declaring Apache-2.0 metadata and CC-BY-NC-4.0 in the license section. |
| Omnilingual ASR CTC 300M int8 | Deferred on measured quality. The exact 365,438,543-byte Apache-2.0 artifact covers more than 1,600 languages and finalized the fixed Hindi sample in about 754 ms median/1.50 seconds p95, but reached 23.18% WER and 31.24% CER with about 1.02 GB RSS—worse quality than promoted Whisper Turbo on this slice. Core ML took 2.92 seconds and roughly 12.28 GB on one clip. |
| Dolphin Small CTC multilingual int8 | Deferred on quality despite speed. The exact 250,163,616-byte Apache-2.0 artifact finalized at about 228 ms Hindi median and roughly 93 ms Japanese median, but measured 33.86% Hindi WER/35.37% CER and 18.35% Japanese CER. It adds no quality advantage over the promoted Hindi or Japanese choices. |
| Moonshine V2 Tiny English | Deferred pending safe chunking. The exact 44 MB quantized sherpa artifact transcribed ≤9.02-second OpenSLR clips in 29–110 ms on CPU, but returned empty results for every 11.48–13.31-second clip because the exported window is about 10 seconds. Core ML was much worse on a 4.65-second clip: 1.947 seconds versus 58 ms on CPU, with higher memory. Do not cap ordinary dictation or silently lose long audio; add boundary-aware chunking before promotion. |
| Canary 180M/1B | Deferred until a released native Apple-accelerated runtime exists. NVIDIA's official support path targets NVIDIA hardware. |

Detailed measurements and reproducible commands live in
`docs/models/benchmark-report-2026-07-19.md` and `Benchmarks/RealtimeASR`.

## Promotion gate

A model is not added merely because its runtime can load it. Promotion requires:

- exact reproducible artifact provenance and acceptable redistribution terms;
- signed per-file SHA-256 and size metadata;
- representative English, multilingual, short-utterance, punctuation, noisy,
  accented, and long-utterance evaluation where the model claims support;
- release-to-final latency, cold load, warmup, memory, and accelerator evidence;
- clean switching, failure recovery, and previous-model fallback tests; and
- a signed release build that works on a clean machine without developer caches.
