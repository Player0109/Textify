# Third Party Notices

Textify does not bundle speech model artifacts. Curated models are downloaded
from immutable Textify release assets or exact commit-pinned upstream files and
verified against the signed model catalog before installation. User-imported
Whisper models remain local and their licenses are not verified by Textify.

## whisper.cpp

Textify vendors a pinned source subset of whisper.cpp for local native
transcription.

- Upstream repository: https://github.com/ggml-org/whisper.cpp
- Upstream tag: v1.7.6
- Upstream commit: a8d002cfd879315632a579e73f0148d06959de36
- License: MIT
- Copied license text: `THIRD_PARTY_LICENSES/whisper.cpp.txt`
- Vendored license source: `Vendor/whisper.cpp/LICENSE`
- Vendor provenance: `Vendor/whisper.cpp/UPSTREAM.md`

The vendored subset is built through SwiftPM targets only. Model binaries remain
external curated downloads and are not included in this repository snapshot.

## OpenAI Whisper models

Whisper model assets are optional external downloads and are not included in
the application bundle or this repository snapshot.

- Whisper small.en q5_1: mirrored as an immutable Textify release asset
- Whisper Large V3 Turbo q5_0: exact commit-pinned GGML artifact from
  https://huggingface.co/ggerganov/whisper.cpp
- Original models: https://huggingface.co/openai
- Model and conversion license: MIT
- Every artifact revision, byte size, and checksum is pinned by the signed
  Textify model catalog

## FluidAudio

Textify pins FluidAudio `0.15.5` for Core ML speech-model loading and Parakeet
and Paraformer inference on Apple Silicon.

- Upstream repository: https://github.com/FluidInference/FluidAudio
- Pinned version: 0.15.5
- Pinned revision: 19600a485baa4998812e4654b70d2bab8f2c9949
- License: Apache-2.0
- Copied license text: `THIRD_PARTY_LICENSES/FluidAudio.txt`

## NVIDIA Parakeet models

Parakeet model assets are optional external downloads and are not included in
the application bundle or this repository snapshot.

- Parakeet TDT 0.6B V3: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- Parakeet TDT 0.6B V2: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2
- Parakeet TDT-CTC 110M: https://huggingface.co/nvidia/parakeet-tdt_ctc-110m
- Parakeet TDT-CTC 0.6B Japanese: https://huggingface.co/nvidia/parakeet-tdt_ctc-0.6b-ja
- Core ML conversions: https://huggingface.co/FluidInference
- Model license: CC-BY-4.0 for all four catalog entries
- Every runtime artifact revision and file checksum is pinned by the signed
  Textify model catalog

## Paraformer-large Chinese model

Paraformer model assets are optional external downloads and are not included
in the application bundle or this repository snapshot.

- Original model: https://modelscope.cn/models/iic/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-pytorch
- Core ML conversion: https://huggingface.co/FluidInference/paraformer-large-zh-coreml
- Upstream model license: Apache-2.0
- Runtime artifact revision pinned by the signed Textify model catalog

## sherpa-onnx and ONNX Runtime

Textify bundles the arm64 C runtime from sherpa-onnx `1.13.2` and its matching
ONNX Runtime `1.24.4` dependency to run eligible ONNX speech models fully
offline.

- sherpa-onnx repository: https://github.com/k2-fsa/sherpa-onnx
- sherpa-onnx commit: `13d0ae6c539d2809d32f5eaa3ef1db0c459d0b24`
- sherpa-onnx license: Apache-2.0
- ONNX Runtime repository: https://github.com/microsoft/onnxruntime
- ONNX Runtime version: `1.24.4`
- ONNX Runtime license: MIT
- Copied license texts: `THIRD_PARTY_LICENSES/sherpa-onnx.txt` and
  `THIRD_PARTY_LICENSES/ONNX_Runtime.txt`
- Exact release-asset and selected-file hashes:
  `Vendor/sherpa-onnx/v1.13.2/UPSTREAM.md`

Both libraries are copied to `Contents/Frameworks` and signed with the
application. Textify verifies the sherpa-onnx runtime version before loading a
model.

## transcribe.cpp

Textify bundles a pinned arm64 build of transcribe.cpp `0.1.3` for eligible
GGUF speech models. It is loaded locally and isolated from Textify's embedded
whisper.cpp symbols.

- Upstream repository: https://github.com/handy-computer/transcribe.cpp
- Upstream commit: `5a5a49664a8ea1f0e5b3be1dfc544730d1b62561`
- Vendored ggml commit: `707321c4cf6d21cb4bc831aa8b687dbf01a521ce`
- License: MIT
- Copied license text: `THIRD_PARTY_LICENSES/transcribe.cpp.txt`
- Local language-prompt compatibility patch and exact build provenance:
  `Vendor/transcribe.cpp/v0.1.3/UPSTREAM.md`

The runtime is built for arm64 macOS 14 with Metal and Accelerate. Textify
requires an actual Metal model backend and rejects CPU fallback for catalog
entries using this engine.

## Fun-ASR MLT-Nano model

Fun-ASR MLT-Nano model assets are optional external downloads and are not
included in the application bundle or this repository snapshot.

- Original model: https://huggingface.co/FunAudioLLM/Fun-ASR-MLT-Nano-2512
- Original model revision: `3dd802bfb8a05dadc440c9d9fc84ecfc1e15c0ff`
- GGUF conversion: https://huggingface.co/handy-computer/Fun-ASR-MLT-Nano-2512-gguf
- GGUF revision: `0b8f9c7bc545a219658aeb1dd4eeaa55d1cf89f3`
- Original model license: Apache-2.0
- Textify candidate artifact: Q8_0, with exact bytes pinned by the signed model
  catalog when promoted

Textify does not claim the checkpoint's full published language list. Only
language routes that pass Textify's own Apple Silicon quality, latency, and
robustness gates may appear in the catalog.

## ReazonSpeech K2 V2 model

ReazonSpeech model assets are optional external downloads and are not included
in the application bundle or this repository snapshot.

- Model: https://huggingface.co/reazon-research/reazonspeech-k2-v2
- Exact ONNX revision: `291488c8151be24d7da4bf7af26e533fad96e407`
- Model license: Apache-2.0
- Every runtime artifact byte size and checksum is pinned by the signed Textify
  model catalog

## SenseVoiceSmall model

SenseVoiceSmall model assets are optional external downloads and are not
included in the application bundle or this repository snapshot.

- Original model: https://huggingface.co/FunAudioLLM/SenseVoiceSmall
- Int8 ONNX conversion: https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17
- Exact ONNX revision: `2365baeacb507f821a0c8120fcee3d484dba7a07`
- Model license: FunASR Model Open Source License Agreement 1.1
- Required attribution: FunASR and SenseVoice; the SenseVoiceSmall model name
  is retained in Textify's catalog and user interface
- Copied model license text:
  `THIRD_PARTY_LICENSES/FunASR_Model_License_1.1.txt`
- Every runtime artifact byte size and checksum is pinned by the signed Textify
  model catalog
