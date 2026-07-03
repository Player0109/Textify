# Third Party Notices

Textify V1 does not bundle model artifacts.

## whisper.cpp

Textify vendors a pinned source subset of whisper.cpp for local native
transcription.

- Upstream repository: https://github.com/ggml-org/whisper.cpp
- Upstream tag: v1.7.6
- Upstream commit: a8d002cfd879315632a579e73f0148d06959de36
- License: MIT
- Local license copy: `Vendor/whisper.cpp/LICENSE`
- Vendor provenance: `Vendor/whisper.cpp/UPSTREAM.md`

The vendored subset is built through SwiftPM targets only. Model binaries remain
external curated downloads and are not included in this repository snapshot.
