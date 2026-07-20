#!/usr/bin/env bash
set -euo pipefail

SOURCE_LIBRARY="${1:?Usage: embed_litert_lm_runtime.sh source-library destination-directory [signing-identity]}"
DESTINATION_DIRECTORY="${2:?Usage: embed_litert_lm_runtime.sh source-library destination-directory [signing-identity]}"
SIGNING_IDENTITY="${3:--}"
DESTINATION_LIBRARY="$DESTINATION_DIRECTORY/libCLiteRTLM_mac.dylib"
EXPECTED_SHA256="eddb330164eb9cf911f74320c6a41b368fef43b42d1232874cc658e161b48779"

printf '%s  %s\n' "$EXPECTED_SHA256" "$SOURCE_LIBRARY" | shasum -a 256 -c - >/dev/null
[[ "$(lipo -archs "$SOURCE_LIBRARY")" == *arm64* ]]
[[ "$(otool -D "$SOURCE_LIBRARY" | tail -1)" == '@rpath/libCLiteRTLM_mac.dylib' ]]

mkdir -p "$DESTINATION_DIRECTORY"
lipo "$SOURCE_LIBRARY" -thin arm64 -output "$DESTINATION_LIBRARY"
chmod 755 "$DESTINATION_LIBRARY"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$DESTINATION_LIBRARY" >/dev/null
else
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    "$DESTINATION_LIBRARY" >/dev/null
fi

[[ "$(lipo -archs "$DESTINATION_LIBRARY")" == "arm64" ]]
[[ "$(otool -D "$DESTINATION_LIBRARY" | tail -1)" == '@rpath/libCLiteRTLM_mac.dylib' ]]
codesign --verify --strict "$DESTINATION_LIBRARY"
