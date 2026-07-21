# Acknowledgments

Textify uses whisper.cpp and FluidAudio for local speech transcription.
whisper.cpp is developed by the ggml-org community under the MIT License.
FluidAudio is developed by the FluidInference community under Apache-2.0 and
provides the released Core ML runtimes used for optional Parakeet and
Paraformer models.
Textify also uses sherpa-onnx, ONNX Runtime, and transcribe.cpp for eligible
offline speech-model formats. The FunAudioLLM team released Fun-ASR MLT-Nano;
Textify evaluates and exposes only the language routes that meet its own local
quality and performance gates.
Textify uses MLX and the pinned MLX Audio Swift runtime for eligible Apple
Silicon speech models, including the separately downloaded NVIDIA Parakeet RNNT
1.1B, Parakeet TDT V2/V3, Nemotron 3.5 ASR, Cohere Transcribe 03-2026, and MLX
Community Whisper Large V3 Turbo and Qwen3-ASR conversions. Parakeet TDT,
Nemotron, and Qwen3-ASR GGUF conversions are provided by handy-computer and run
through the pinned transcribe.cpp Metal runtime. Runtime model loading is
restricted to Textify-managed local
directories; network-backed package loading APIs are not used.

Optional MossFormer2 SE MLX speech-enhancement conversions are provided by
starkdmi and run through the same pinned local MLX Audio Swift and MLX Swift
stack before transcription. The FP32, FP16, and 8-bit weights are separate
downloads and are licensed under Apache-2.0.

Whisper was developed and released by OpenAI. The English, multilingual, and
Japanese Parakeet models were released by NVIDIA. Paraformer-large Chinese and
SenseVoiceSmall come from the FunASR/ModelScope ecosystem; Textify retains the
SenseVoice name and attribution as required by its model license.
Textify does not bundle model binaries. Every curated download must use an
immutable Textify release asset or an exact commit-pinned approved upstream
artifact and be exposed through the signed model manifest with exact source,
checksum, license, and provenance records. The currently published catalog may
contain fewer entries than the app runtime can support.

Third-party notices are in `THIRD_PARTY_NOTICES.md`. Copied runtime license
texts are in `THIRD_PARTY_LICENSES/`.
