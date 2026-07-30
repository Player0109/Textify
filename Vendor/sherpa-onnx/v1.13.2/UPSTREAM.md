# sherpa-onnx runtime provenance

Textify vendors the two arm64 dynamic libraries needed by its version-pinned
`sherpa-onnx` C boundary. The sherpa-onnx C library and header come from the
official v1.13.2
`sherpa-onnx-v1.13.2-osx-arm64-shared-no-tts.tar.bz2` release asset. The ONNX
Runtime library comes from Microsoft's first-party arm64 1.24.4 release asset,
which sherpa-onnx v1.13.2 also pins for native arm64 shared builds.

- Upstream: https://github.com/k2-fsa/sherpa-onnx
- Release: https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.13.2
- Git commit: `13d0ae6c539d2809d32f5eaa3ef1db0c459d0b24`
- Runtime-reported Git SHA: `13d0ae6c`
- Release archive URL: https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.2/sherpa-onnx-v1.13.2-osx-arm64-shared-no-tts.tar.bz2
- Release archive bytes: `24,006,637`
- Release archive SHA-256: `d880aaa79d36b784168a0398b278813d57ba8e135f468894b8f134b664e2e225`
- Architecture: arm64
- License: Apache-2.0

ONNX Runtime source:

- Upstream: https://github.com/microsoft/onnxruntime
- Release: https://github.com/microsoft/onnxruntime/releases/tag/v1.24.4
- Git commit: `2d924974ef147392ced8409d36bd6d2e7fcc8a74`
- Release archive URL: https://github.com/microsoft/onnxruntime/releases/download/v1.24.4/onnxruntime-osx-arm64-1.24.4.tgz
- Release archive bytes: `30,937,282`
- Release archive SHA-256: `93787795f47e1eee369182e43ed51b9e5da0878ab0346aecf4258979b8bba989`
- Architecture: arm64
- Install name: `@rpath/libonnxruntime.1.24.4.dylib`
- macOS deployment target: `14.0` (SDK `15.5`)
- License: MIT

Exact selected files:

| Source asset | File | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| sherpa-onnx | `lib/libsherpa-onnx-c-api.dylib` | 2,903,944 | `b9dce3ad05294742b57627d86e7815be497a2f426e954476cdc31fea22197318` |
| ONNX Runtime | `lib/libonnxruntime.1.24.4.dylib` | 35,418,600 | `872533f130f1839a5bc01788ddb4f75c83a189763441ba1178788ed965449289` |
| sherpa-onnx | `include/sherpa-onnx/c-api/c-api.h` | 160,309 | `437b1279047877167d8fadc74a60d47f3df514d703fdac1c1b6851da9bc2fdb4` |

The ONNX Runtime library is Microsoft's official Core ML-enabled arm64 build
and reports ONNX Runtime 1.24.4. Its `LICENSE` and `ThirdPartyNotices.txt` bytes
match Textify's pinned copies. Textify loads these libraries only from its
signed app bundle, checks the sherpa-onnx version and Git SHA before creating a
recognizer, and currently selects the measured-fastest CPU provider for
ReazonSpeech.

The staged application copies the two libraries to `Contents/Frameworks` and
signs them with the same identity as the application. Model weights remain
external signed-catalog downloads.
