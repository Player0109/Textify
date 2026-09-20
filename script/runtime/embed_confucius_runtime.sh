#!/usr/bin/env bash
set -euo pipefail
DESTINATION_DIRECTORY="${1:?destination directory required}"
SIGNING_IDENTITY="${2:--}"
ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_LIBRARY="$ROOT_DIRECTORY/Vendor/audio.cpp/9ba8841/lib/libtextify-confucius.dylib"
DESTINATION_LIBRARY="$DESTINATION_DIRECTORY/libtextify-confucius.dylib"
printf '%s  %s\n' '1776894bb69ed08a85aa883c48d799d59381bd4524930a430a25a5aebb4610b1' "$SOURCE_LIBRARY" | shasum -a 256 -c - >/dev/null
[[ "$(lipo -archs "$SOURCE_LIBRARY")" == "arm64" ]]
[[ "$(otool -D "$SOURCE_LIBRARY" | tail -1)" == '@rpath/libtextify-confucius.dylib' ]]
otool -l "$SOURCE_LIBRARY" \
  | awk '/LC_BUILD_VERSION/{show=1} show && /minos/{print $2; exit}' \
  | grep -Fxq '14.0'
! nm -gjU "$SOURCE_LIBRARY" | grep -Eq '^_ggml_'
nm -gjU "$SOURCE_LIBRARY" | sort -u | cmp <(sort -u "$ROOT_DIRECTORY/Vendor/audio.cpp/9ba8841/EXPORTED_SYMBOLS") -
mkdir -p "$DESTINATION_DIRECTORY"
install -m 755 "$SOURCE_LIBRARY" "$DESTINATION_LIBRARY"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$DESTINATION_LIBRARY"
else
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$DESTINATION_LIBRARY"
fi
codesign --verify --strict "$DESTINATION_LIBRARY"
