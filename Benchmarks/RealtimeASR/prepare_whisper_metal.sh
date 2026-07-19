#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GGML_DIR="$SCRIPT_DIR/../../Vendor/whisper.cpp/ggml"
OUTPUT_DIR="$SCRIPT_DIR/.build/release"
AIR_FILE="$OUTPUT_DIR/ggml-metal.air"

mkdir -p "$OUTPUT_DIR"

/usr/bin/xcrun -sdk macosx metal \
  -c \
  -I "$GGML_DIR/src" \
  -I "$GGML_DIR/src/ggml-metal" \
  "$GGML_DIR/src/ggml-metal/ggml-metal.metal" \
  -o "$AIR_FILE"

/usr/bin/xcrun -sdk macosx metallib \
  "$AIR_FILE" \
  -o "$OUTPUT_DIR/default.metallib"

echo "Whisper Metal library written to $OUTPUT_DIR/default.metallib"
