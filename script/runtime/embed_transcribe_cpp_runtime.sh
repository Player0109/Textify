#!/usr/bin/env bash
set -euo pipefail

DESTINATION_DIRECTORY="${1:?Usage: embed_transcribe_cpp_runtime.sh destination-directory [signing-identity]}"
SIGNING_IDENTITY="${2:--}"
ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_LIBRARY="$ROOT_DIRECTORY/Vendor/transcribe.cpp/v0.1.3/lib/libtextify-transcribe.0.1.3.dylib"
EXPORTED_SYMBOLS="$ROOT_DIRECTORY/Vendor/transcribe.cpp/v0.1.3/EXPORTED_SYMBOLS"
DESTINATION_LIBRARY="$DESTINATION_DIRECTORY/libtextify-transcribe.0.1.3.dylib"

verify_source() {
  printf '%s  %s\n' \
    '543b2d9be14e1f3d834534d9f230e9828184466c653bb940787fdd517e5f7855' \
    "$SOURCE_LIBRARY" \
    | shasum -a 256 -c - >/dev/null
  [[ "$(lipo -archs "$SOURCE_LIBRARY")" == "arm64" ]]
  [[ "$(otool -D "$SOURCE_LIBRARY" | tail -1)" == '@rpath/libtextify-transcribe.0.1.3.dylib' ]]
  otool -l "$SOURCE_LIBRARY" \
    | awk '/LC_BUILD_VERSION/{show=1} show && /minos/{print $2; exit}' \
    | grep -Fxq '14.0'
  nm -gjU "$SOURCE_LIBRARY" | sort -u | cmp "$EXPORTED_SYMBOLS" -
  ! nm -gjU "$SOURCE_LIBRARY" | grep -Eq '^_ggml_'
}

sign_library() {
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$DESTINATION_LIBRARY" >/dev/null
  else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
      "$DESTINATION_LIBRARY" >/dev/null
  fi
}

verify_source
mkdir -p "$DESTINATION_DIRECTORY"
install -m 755 "$SOURCE_LIBRARY" "$DESTINATION_LIBRARY"
sign_library
codesign --verify --strict "$DESTINATION_LIBRARY"
