# transcribe.cpp runtime provenance

- Upstream: `https://github.com/handy-computer/transcribe.cpp`
- Runtime version: `0.1.3`
- Source commit: `5a5a49664a8ea1f0e5b3be1dfc544730d1b62561`
- Vendored ggml commit: `707321c4cf6d21cb4bc831aa8b687dbf01a521ce`
- License: MIT (copied in `THIRD_PARTY_LICENSES/transcribe.cpp.txt`)
- Local patch: `patches/0001-funasr-publisher-language-names.patch`
- Local patch SHA-256: `e4837fc78edc92a861fe8f3e72bbc3bcb1d9269ef3dc38cd2c81022fdf02f26b`
- Build target: arm64 macOS 14.0, Metal + Accelerate, baseline CPU code
  (`GGML_NATIVE=OFF`)
- Public header SHA-256: `2b7c468b2153ebda9110840945fb83652148f787cb4cb0a4d049d1ee7c65bbda`
- Dylib: `lib/libtextify-transcribe.0.1.3.dylib`
- Dylib size: `3,361,104` bytes
- Dylib SHA-256: `543b2d9be14e1f3d834534d9f230e9828184466c653bb940787fdd517e5f7855`
- Mach-O UUID: `53B0792F-9508-3DAE-8AAD-9B8063786156` (required for
  `dlopen` on supported macOS releases and reproduced byte-for-byte across two
  clean builds)
- Export policy: only the public `transcribe_*` C ABI is visible. ggml symbols
  remain private so this dylib can be loaded with `RTLD_LOCAL` beside Textify's
  existing whisper.cpp runtime.

The dylib is built reproducibly with:

```bash
script/runtime/build_transcribe_cpp_runtime.sh /path/to/transcribe.cpp
```

The local patch is required because the upstream Fun-ASR adapter accepts public
ISO language codes but the model's documented prompt contract expects its
publisher language names. Benchmark results record both the upstream commit and
the exact patched source-diff SHA-256.
