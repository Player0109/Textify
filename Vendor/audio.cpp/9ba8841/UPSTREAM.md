# Confucius4-R2T2 native runtime

- Upstream: https://github.com/0xShug0/audio.cpp
- Commit: `9ba884179826c3b33dd305185b5f94c79175a03d`
- Copied: 2026-09-20
- ABI: 0.2.0, limited to the exported `audiocpp_*` C surface.
- Build: Apple Silicon, macOS 14 minimum, Release, Metal; only the
  `confucius4_r2t2` model family. No Python, server, model manager, OpenMP,
  external runtime dependencies, or build-time download in the app.
- Metal shader source is embedded (`GGML_METAL_EMBED_LIBRARY=ON`).
- Included: upstream C ABI header and license, exact exported symbol inventory,
  `lib/libtextify-confucius.dylib`.
- Local source patches: none. The dylib install name is changed to
  `@rpath/libtextify-confucius.dylib` and it is ad-hoc signed locally.
- SHA-256: `1776894bb69ed08a85aa883c48d799d59381bd4524930a430a25a5aebb4610b1`.
- Rebuild from a clean checkout of that commit with
  `script/runtime/build_confucius_runtime.sh /path/to/audio.cpp`.
  Audit and update the embedding checksum after rebuilding with a different
  compiler or toolchain.
- The isolated dynamic library avoids collisions with Textify's other ggml
  runtimes. Its only linked libraries are Apple system libraries/frameworks.
- Bundled dependency notices: `THIRD_PARTY_LICENSES/audio.cpp.txt`.
- Model license and derivative notice: `THIRD_PARTY_LICENSES/Confucius4-R2T2.txt`.
