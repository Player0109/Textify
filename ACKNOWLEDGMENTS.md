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
