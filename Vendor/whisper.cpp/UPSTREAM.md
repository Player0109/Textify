# whisper.cpp Upstream Snapshot

Upstream repository: https://github.com/ggml-org/whisper.cpp
Commit SHA: a8d002cfd879315632a579e73f0148d06959de36
Tag: v1.7.6
Date copied: 2026-07-03

Included paths:
- include/
- src/whisper.cpp
- src/whisper-arch.h
- ggml/include/
- selected base, CPU, and Metal sources under ggml/src/

Excluded paths:
- examples/
- bindings/
- models/
- samples/
- tests/
- server examples
- benchmark tools
- OpenVINO sources
- CUDA sources
- Vulkan sources
- SYCL sources
- OpenCL sources
- Apple neural accelerator sources

Local patches:
- Removed dormant Apple neural accelerator branches from src/whisper.cpp so Textify can prove the runtime is absent with source-level checks.
- Kept the v1.7.6 source list scoped to files present in that tag; ggml/src/ggml-backend-meta.cpp is not present upstream at this tag.
