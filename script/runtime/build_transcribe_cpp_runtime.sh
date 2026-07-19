#!/usr/bin/env bash
set -euo pipefail

ROOT_DIRECTORY="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_DIRECTORY="${1:-}"
DESTINATION_DIRECTORY="${2:-$ROOT_DIRECTORY/Vendor/transcribe.cpp/v0.1.3/lib}"
UPSTREAM_COMMIT="5a5a49664a8ea1f0e5b3be1dfc544730d1b62561"
PATCH_FILE="$ROOT_DIRECTORY/Vendor/transcribe.cpp/v0.1.3/patches/0001-funasr-publisher-language-names.patch"
EXPORTED_SYMBOLS="$ROOT_DIRECTORY/Vendor/transcribe.cpp/v0.1.3/EXPORTED_SYMBOLS"
OUTPUT_NAME="libtextify-transcribe.0.1.3.dylib"
TEMP_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIRECTORY"' EXIT

if [[ -z "$SOURCE_DIRECTORY" || ! -d "$SOURCE_DIRECTORY/.git" ]]; then
  echo "Usage: $0 /path/to/transcribe.cpp [destination-directory]" >&2
  exit 2
fi
if [[ "$(git -C "$SOURCE_DIRECTORY" rev-parse HEAD)" != "$UPSTREAM_COMMIT" ]]; then
  echo "transcribe.cpp must be at $UPSTREAM_COMMIT" >&2
  exit 1
fi

git clone --quiet --shared --no-checkout "$SOURCE_DIRECTORY" "$TEMP_DIRECTORY/source"
git -C "$TEMP_DIRECTORY/source" checkout --quiet --detach "$UPSTREAM_COMMIT"
/usr/bin/patch --quiet -d "$TEMP_DIRECTORY/source" -p1 < "$PATCH_FILE"

cmake -S "$TEMP_DIRECTORY/source" -B "$TEMP_DIRECTORY/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_C_FLAGS="-ffile-prefix-map=$TEMP_DIRECTORY/source=." \
  -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$TEMP_DIRECTORY/source=." \
  -DGGML_CCACHE=OFF \
  -DGGML_NATIVE=OFF \
  -DTRANSCRIBE_BUILD_SHARED=OFF \
  -DTRANSCRIBE_BUILD_EXAMPLES=OFF \
  -DTRANSCRIBE_BUILD_TESTS=OFF \
  -DTRANSCRIBE_BUILD_TOOLS=OFF \
  -DTRANSCRIBE_METAL=ON \
  -DTRANSCRIBE_USE_OPENMP=OFF
cmake --build "$TEMP_DIRECTORY/build" --parallel 8

nm -gjU "$TEMP_DIRECTORY/build/src/libtranscribe.a" \
  | /usr/bin/awk '/^_transcribe_/' \
  | sort -u > "$TEMP_DIRECTORY/actual-exports"
cmp "$EXPORTED_SYMBOLS" "$TEMP_DIRECTORY/actual-exports"

xcrun clang++ \
  -dynamiclib \
  -arch arm64 \
  -mmacosx-version-min=14.0 \
  -O3 \
  -Wl,-dead_strip \
  -Wl,-install_name,@rpath/$OUTPUT_NAME \
  -Wl,-compatibility_version,0.1.0 \
  -Wl,-current_version,0.1.3 \
  -Wl,-exported_symbols_list,$EXPORTED_SYMBOLS \
  -Wl,-force_load,"$TEMP_DIRECTORY/build/src/libtranscribe.a" \
  -Wl,-force_load,"$TEMP_DIRECTORY/build/ggml/src/libggml.a" \
  -Wl,-force_load,"$TEMP_DIRECTORY/build/ggml/src/libggml-base.a" \
  -Wl,-force_load,"$TEMP_DIRECTORY/build/ggml/src/libggml-cpu.a" \
  -Wl,-force_load,"$TEMP_DIRECTORY/build/ggml/src/ggml-metal/libggml-metal.a" \
  -framework Accelerate \
  -framework Foundation \
  -framework Metal \
  -framework MetalKit \
  -lz \
  -o "$TEMP_DIRECTORY/$OUTPUT_NAME"

[[ "$(lipo -archs "$TEMP_DIRECTORY/$OUTPUT_NAME")" == "arm64" ]]
otool -l "$TEMP_DIRECTORY/$OUTPUT_NAME" \
  | /usr/bin/awk '/LC_BUILD_VERSION/{show=1} show && /minos/{print $2; exit}' \
  | grep -Fxq '14.0'
[[ "$(otool -D "$TEMP_DIRECTORY/$OUTPUT_NAME" | tail -1)" == "@rpath/$OUTPUT_NAME" ]]

mkdir -p "$DESTINATION_DIRECTORY"
install -m 755 "$TEMP_DIRECTORY/$OUTPUT_NAME" "$DESTINATION_DIRECTORY/$OUTPUT_NAME"
echo "Built $DESTINATION_DIRECTORY/$OUTPUT_NAME"
/usr/bin/stat -f 'sizeBytes=%z' "$DESTINATION_DIRECTORY/$OUTPUT_NAME"
/usr/bin/shasum -a 256 "$DESTINATION_DIRECTORY/$OUTPUT_NAME"
