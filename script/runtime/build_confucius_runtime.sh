#!/usr/bin/env bash
set -euo pipefail
SOURCE_DIRECTORY="${1:?path to audio.cpp checkout required}"
ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESTINATION_DIRECTORY="${2:-$ROOT_DIRECTORY/Vendor/audio.cpp/9ba8841/lib}"
UPSTREAM_COMMIT=9ba884179826c3b33dd305185b5f94c79175a03d
[[ "$(git -C "$SOURCE_DIRECTORY" rev-parse HEAD)" == "$UPSTREAM_COMMIT" ]]
TEMP_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIRECTORY"' EXIT
git clone --quiet --shared --no-checkout "$SOURCE_DIRECTORY" "$TEMP_DIRECTORY/source"
git -C "$TEMP_DIRECTORY/source" checkout --quiet --detach "$UPSTREAM_COMMIT"
cmake -S "$TEMP_DIRECTORY/source" -B "$TEMP_DIRECTORY/build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DAUDIOCPP_MODEL_SET=custom -DAUDIOCPP_MODELS=confucius4_r2t2 \
  -DAUDIOCPP_BUILD_C_API=ON -DAUDIOCPP_BUILD_NATIVE_MODEL_MANAGER=OFF \
  -DAUDIOCPP_BUILD_SERVER_FRONTENDS=OFF -DENGINE_ENABLE_METAL=ON \
  -DENGINE_ENABLE_OPENMP=OFF -DENGINE_ENABLE_NATIVE_CPU=OFF
cmake --build "$TEMP_DIRECTORY/build" --parallel 8 --target audiocpp
mkdir -p "$DESTINATION_DIRECTORY"
OUTPUT_LIBRARY="$DESTINATION_DIRECTORY/libtextify-confucius.dylib"
cp "$TEMP_DIRECTORY/build/bin/libaudiocpp.0.1.0.dylib" "$OUTPUT_LIBRARY"
install_name_tool -id '@rpath/libtextify-confucius.dylib' "$OUTPUT_LIBRARY"
codesign --force --sign - --timestamp=none "$OUTPUT_LIBRARY"
shasum -a 256 "$OUTPUT_LIBRARY"
