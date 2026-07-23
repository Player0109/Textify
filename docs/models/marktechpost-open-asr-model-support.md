# MarkTechPost 2026 open-ASR model support

Status: native runtime audit, 2026-07-23

Source comparison:
[Best Open Speech Recognition (ASR) Models in 2026](https://www.marktechpost.com/2026/07/23/best-open-speech-recognition-asr-models-in-2026-wer-languages-latency-and-license-compared/)

Textify counts a model as supported only when the signed catalog names exact
immutable artifacts and the app has an offline native execution path for those
artifacts. A model name, disabled row, Python subprocess, or cloud fallback does
not count.

## Coverage

| Article model | Textify status | Offline route |
| --- | --- | --- |
| MOSS-Transcribe-preview-2B | Native port required | No compatible architecture in the pinned runtimes |
| ARK-ASR-3B | Native port required | CrispASR has a C++ implementation, but Textify's pinned transcribe.cpp ABI does not |
| Granite Speech 4.1 2B | Supported | transcribe.cpp 0.1.3, Q5_K_M GGUF, Metal |
| Cohere Transcribe | Supported | MLX Audio Swift, 8-bit MLX, Metal |
| Canary-Qwen-2.5B | Supported | transcribe.cpp 0.1.3, Q4_K_M GGUF, Metal |
| Qwen3-ASR-1.7B | Supported | MLX Audio Swift and transcribe.cpp Metal choices |
| Parakeet TDT 0.6B v3 | Supported | FluidAudio/Core ML, MLX Audio, and transcribe.cpp choices |
| Kyutai STT 2.6B | Native port required | Kyutai publishes MLX weights, but Textify has no delayed-streams Swift runtime boundary |
| Whisper large-v3 | Supported | whisper.cpp Q5_0, Metal |
| Voxtral Mini 4B Realtime 2602 | Supported | transcribe.cpp 0.1.3, Q4_K_M GGUF, Metal |
| Granite Speech 4.1 2B-NAR | Supported | transcribe.cpp 0.1.3, Q5_K_M GGUF, Metal |
| Qwen3-ASR-0.6B | Supported | MLX Audio Swift and transcribe.cpp Metal choices |
| Kyutai STT 1B en_fr | Native port required | Kyutai publishes an Apple MLX checkpoint, but Textify has no delayed-streams Swift runtime boundary |
| Omnilingual ASR | Supported | sherpa-onnx 1.13.2, 300M CTC INT8 ONNX, CPU |
| MOSS-Transcribe-Diarize 0.9B | Supported | transcribe.cpp 0.1.3, Q5_K_M GGUF, Metal |
| diffusion-gemma-asr-small | Native port required | The adapter requires Whisper-small plus the separately licensed 26B DiffusionGemma backbone; no compatible Textify runtime exists |

Eleven of the sixteen exact article models now have working Textify routes.
The five remaining entries are deliberately absent from the production catalog
so users cannot download a model that the app cannot execute.

## Newly exposed artifacts

| Model | Immutable source revision | Artifact |
| --- | --- | --- |
| Granite Speech 4.1 2B | `58e7710fd7039ded5a185668eef5f71ca5d9d919` | `granite-speech-4.1-2b-Q5_K_M.gguf` |
| Granite Speech 4.1 2B-NAR | `ca53e8273416eb7e888f19bcebbcb9b6ab3edc17` | `granite-speech-4.1-2b-nar-Q5_K_M.gguf` |
| Voxtral Mini 4B Realtime 2602 | `b3e1c979e3775cbd0a49a65878a0ec7f06789ed7` | `Voxtral-Mini-4B-Realtime-2602-Q4_K_M.gguf` |
| MOSS-Transcribe-Diarize 0.9B | `6fdfa33aed776bbb0ac11a1a9835634fe6d75dd7` | `MOSS-Transcribe-Diarize-Q5_K_M.gguf` |
| Omnilingual ASR 300M | `6abf1ece20cd2308bdb7d13cd78ec1c44fa4c094` | `model.int8.onnx` and `tokens.txt` |

Every file URL in `models/manifest.json` is commit-pinned and includes its
exact byte count and SHA-256. These models remain `Unrated` until they complete
Textify's checksum-pinned catalog benchmark policy.

## Remaining native work

Each remaining model needs a separate implementation slice:

1. MOSS preview and ARK need a production C/C++ or Swift ABI, reproducible
   conversion, Metal proof, and fixed-corpus parity against their publisher
   implementations.
2. The two Kyutai checkpoints can share one delayed-streams runtime, but it must
   load Textify-managed local artifacts and return a final result without
   network access.
3. DiffusionGemma ASR needs an on-device DiffusionGemma decoder implementation,
   Whisper-small encoder integration, adapter loading, Gemma license handling,
   and a memory/device eligibility policy for the 26B backbone.

Only after those gates pass should their exact artifacts be added to the signed
catalog.
