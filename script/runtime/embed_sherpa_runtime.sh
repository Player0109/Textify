#!/usr/bin/env bash
set -euo pipefail

DESTINATION_DIRECTORY="${1:?Usage: embed_sherpa_runtime.sh destination-directory [signing-identity]}"
SIGNING_IDENTITY="${2:--}"
ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DIRECTORY="$ROOT_DIRECTORY/Vendor/sherpa-onnx/v1.13.2/lib"
SHERPA_LIBRARY="$SOURCE_DIRECTORY/libsherpa-onnx-c-api.dylib"
ONNX_RUNTIME_LIBRARY="$SOURCE_DIRECTORY/libonnxruntime.1.24.4.dylib"

verify_source() {
  printf '%s  %s\n' \
    'b9dce3ad05294742b57627d86e7815be497a2f426e954476cdc31fea22197318' \
    "$SHERPA_LIBRARY" \
    '872533f130f1839a5bc01788ddb4f75c83a189763441ba1178788ed965449289' \
    "$ONNX_RUNTIME_LIBRARY" \
    | shasum -a 256 -c - >/dev/null
  [[ "$(lipo -archs "$SHERPA_LIBRARY")" == "arm64" ]]
  [[ "$(lipo -archs "$ONNX_RUNTIME_LIBRARY")" == "arm64" ]]
}

sign_library() {
  local library_path="$1"
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$library_path" >/dev/null
  else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$library_path" >/dev/null
  fi
}

verify_source
mkdir -p "$DESTINATION_DIRECTORY"
install -m 755 "$SHERPA_LIBRARY" "$DESTINATION_DIRECTORY/libsherpa-onnx-c-api.dylib"
install -m 755 "$ONNX_RUNTIME_LIBRARY" "$DESTINATION_DIRECTORY/libonnxruntime.1.24.4.dylib"
sign_library "$DESTINATION_DIRECTORY/libonnxruntime.1.24.4.dylib"
sign_library "$DESTINATION_DIRECTORY/libsherpa-onnx-c-api.dylib"

codesign --verify --strict "$DESTINATION_DIRECTORY/libonnxruntime.1.24.4.dylib"
codesign --verify --strict "$DESTINATION_DIRECTORY/libsherpa-onnx-c-api.dylib"
