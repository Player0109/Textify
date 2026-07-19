#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 OUTPUT_PATH" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GGML_DIR="$ROOT_DIR/Vendor/whisper.cpp/ggml"
METAL_SOURCE="$GGML_DIR/src/ggml-metal/ggml-metal.metal"
OUTPUT_PATH="$1"
OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/textify-metallib.XXXXXX")"
AIR_PATH="$TEMP_DIR/ggml-metal.air"
TEMP_LIBRARY_PATH="$TEMP_DIR/default.metallib"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"

/usr/bin/xcrun -sdk macosx metal \
  -c \
  -I "$GGML_DIR/src" \
  -I "$GGML_DIR/src/ggml-metal" \
  "$METAL_SOURCE" \
  -o "$AIR_PATH"

/usr/bin/xcrun -sdk macosx metallib \
  "$AIR_PATH" \
  -o "$TEMP_LIBRARY_PATH"

/usr/bin/install -m 0644 "$TEMP_LIBRARY_PATH" "$OUTPUT_PATH"

if [[ ! -s "$OUTPUT_PATH" ]] || ! /usr/bin/file "$OUTPUT_PATH" | /usr/bin/grep -q "MetalLib executable"; then
  echo "failed to build a valid Metal library at $OUTPUT_PATH" >&2
  exit 1
fi
