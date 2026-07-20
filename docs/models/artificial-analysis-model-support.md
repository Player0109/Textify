# Artificial Analysis Model Support

Snapshot date: 2026-07-20

This matrix tracks the exact model names in the supplied Artificial Analysis
benchmark. Textify remains strictly local and offline: dictated audio may not be
sent to a hosted transcription API. A similarly named open checkpoint does not
count as support for a service-only model.

| Requested model | Local Textify status | Evidence and next gate |
| --- | --- | --- |
| Voxtral Small | Blocked pending runtime correctness | Mistral publishes the exact Apache-2.0 24B checkpoint, and a 15.72 GB Q4_K_M GGUF plus Small-specific projector can run through `llama.cpp`/`libmtmd` on Metal. However, the current llama.cpp path has a confirmed open Mini/Small correctness defect with materially higher WER than vLLM. Textify will not expose the model until the audio pooling/preprocessing fixes are merged or pinned and pass the fixed corpus. [Official model](https://huggingface.co/mistralai/Voxtral-Small-24B-2507) [Runtime defect](https://github.com/ggml-org/llama.cpp/issues/25496) |
| Inkling (256K) | Unavailable under local-only policy | `thinkingmachines/Inkling:peft:262144` is a hosted Tinker configuration, not a separate local checkpoint. The public base model requires about 2 TB for BF16 or 600 GB for its publisher-supported NVFP4 path, beyond currently documented Mac capacity. [Official model card](https://thinkingmachines.ai/model-card/inkling/) |
| Voxtral Mini Transcribe 2 | Unavailable under local-only policy | The exact `voxtral-mini-2602` model is Premier/API-only. Mistral has not published downloadable weights for this exact model; Voxtral Mini and Voxtral Realtime are different checkpoints. [Exact model card](https://docs.mistral.ai/models/model-cards/voxtral-mini-transcribe-26-02) |
| Whisper Large V2 | Supported, Experimental | Exact q5_0 GGML bytes are pinned in the signed catalog and routed through Textify's resident whisper.cpp Metal runtime. The catalog currently advertises English only. [Official conversion repository](https://huggingface.co/ggerganov/whisper.cpp) |
| Whisper Large V3 | Supported, Experimental | Exact q5_0 GGML bytes are pinned in the signed catalog and routed through Textify's resident whisper.cpp Metal runtime. The catalog currently advertises English only. [Official conversion repository](https://huggingface.co/ggerganov/whisper.cpp) |
| Canary-Qwen 2.5B | Supported, Accurate | The exact 1.74 GB Q4_K_M artifact is pinned in the signed catalog and routed through transcribe.cpp's exact `canary_qwen` architecture on Metal. The fixed 210-word sample measured 0.95% WER, 255.5 ms median/373 ms p95 finalization, and 3.16 GB peak process memory; Textify advertises English only with a 40-second cap. [Official model](https://huggingface.co/nvidia/canary-qwen-2.5b) [Benchmark record](benchmark-report-2026-07-20-canary-qwen.md) |
| Cohere Transcribe | Supported, Experimental | The exact four-file, 2.42 GB Apache-2.0 8-bit MLX conversion is pinned in the signed catalog and routed through Textify's resident MLX Metal engine. The fixed 210-word sample measured 2.86% WER, 121.5 ms median/304 ms p95 finalization, and 2.52 GB peak process memory; Textify advertises explicit English with a 30-second cap. [Official model](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026) [Benchmark record](benchmark-report-2026-07-20-cohere-transcribe.md) |
| Whisper Large V3 Turbo | Supported, Specialist + Experimental MLX alternative | Exact q5_0 GGML bytes remain the smaller English/Hindi Specialist. The exact MLX Community safetensors checkpoint is also pinned as a separate English-only Experimental choice with local tokenizer assets: 3.33% WER, 321.5 ms median/416 ms p95 finalization, and 1.75 GB peak process memory on the fixed sample. [MLX source](https://huggingface.co/mlx-community/whisper-large-v3-turbo) [Benchmark record](benchmark-report-2026-07-20-mlx-whisper-turbo.md) |
| Parakeet RNNT 1.1B | Supported, Experimental | The exact five-file, 4.28 GB MLX conversion is pinned in the signed catalog and routed through Textify's resident MLX Metal engine. The fixed 210-word sample measured 1.90% WER, 128.5 ms median/241 ms p95 finalization, and 4.46 GB peak process memory; Textify advertises English only and requires at least 16 GB unified memory. [Official model](https://huggingface.co/nvidia/parakeet-rnnt-1.1b) [Benchmark record](benchmark-report-2026-07-20-parakeet-rnnt.md) |
| Qwen3 ASR Flash | Exact Flash service unavailable; open Qwen3-ASR alternatives supported | The exact `qwen3-asr-flash` name is a metered DashScope/Qwen Cloud service with no released weights and cannot be relabeled. Textify separately publishes the open Qwen3-ASR 0.6B and 1.7B checkpoints as eight Experimental MLX/GGUF choices with automatic language detection and measured Metal performance. [Official service documentation](https://www.alibabacloud.com/help/en/model-studio/non-realtime-speech-recognition-user-guide) [Local benchmark record](benchmark-report-2026-07-20-qwen3-asr.md) |
| Parakeet TDT 0.6B V2 | Supported, Accurate | The exact model already ships through a signed 21-file Core ML catalog entry and FluidAudio's Neural Engine-verified runtime. [Catalog documentation](curated-models.md) |
| Gemma 4 12B | Implementation candidate | Google publishes exact Apache-2.0 weights and a public immutable 6.55 GB LiteRT-LM audio artifact. LiteRT-LM 0.14 has a native Swift/macOS route with Metal model and audio backends, but Textify still needs the pinned engine, WAV bridge, deterministic transcript-only prompting, 30-second cap, roughly 8 GB memory gate, native QA, and signed packaging. [Official model](https://huggingface.co/google/gemma-4-12B-it) [Pinned LiteRT artifact](https://huggingface.co/litert-community/gemma-4-12B-it-litert-lm/tree/c65da4643badfd9ae0748b5df0145d8fddaef47e) |

## Promotion rules

A candidate becomes Supported only after all of the following are true:

- the exact immutable artifact and every runtime file have recorded size,
  SHA-256, license, and provenance;
- a native Apple Silicon path runs without network access after installation;
- the intended Metal, Core ML/Neural Engine, or other local accelerator is
  measured rather than inferred;
- fixed-corpus accuracy, release-to-final latency, cold load, peak unified
  memory, silence behavior, maximum recording length, switching, and unload
  behavior pass;
- the signed catalog, clean installer, runtime routing, picker, tests, notices,
  and release artifact all agree on the exact identity and limitations.

Service-only and hardware-infeasible entries remain documented as unavailable;
they must not appear as installable choices unless their exact local artifacts
and runtimes later satisfy the same gate.
