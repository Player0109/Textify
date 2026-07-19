# sherpa-onnx runtime provenance

Textify vendors the two arm64 dynamic libraries needed by its version-pinned
`sherpa-onnx` C boundary. They come from the official v1.13.2
`sherpa-onnx-v1.13.2-osx-arm64-shared-no-tts.tar.bz2` release asset.

- Upstream: https://github.com/k2-fsa/sherpa-onnx
- Release: https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.13.2
- Git commit: `13d0ae6c539d2809d32f5eaa3ef1db0c459d0b24`
- Runtime-reported Git SHA: `13d0ae6c`
- Release archive SHA-256: `d880aaa79d36b784168a0398b278813d57ba8e135f468894b8f134b664e2e225`
- Architecture: arm64
- License: Apache-2.0

Exact selected files:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `lib/libsherpa-onnx-c-api.dylib` | 2,903,944 | `b9dce3ad05294742b57627d86e7815be497a2f426e954476cdc31fea22197318` |
| `lib/libonnxruntime.1.24.4.dylib` | 26,291,088 | `3b76ed91e19443f04b79d53bf415d5fe66dd81211e3b7787ba48009e49e2d04d` |
| `include/sherpa-onnx/c-api/c-api.h` | 160,309 | `437b1279047877167d8fadc74a60d47f3df514d703fdac1c1b6851da9bc2fdb4` |

The ONNX Runtime library is the official Core ML-enabled build shipped inside
that sherpa-onnx release and reports ONNX Runtime 1.24.4. ONNX Runtime is MIT
licensed. Textify loads these libraries only from its signed app bundle, checks
the sherpa-onnx version and Git SHA before creating a recognizer, and currently
selects the measured-fastest CPU provider for ReazonSpeech.

The staged application copies the two libraries to `Contents/Frameworks` and
signs them with the same identity as the application. Model weights remain
external signed-catalog downloads.
