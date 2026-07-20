#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  echo "usage: $0 OUTPUT_PATH [SIGNING_IDENTITY]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_PATH="$ROOT_DIR/Vendor/mlx-swift/0.31.3/mlx.metallib"
OUTPUT_PATH="$1"
SIGNING_IDENTITY="${2:--}"
EXPECTED_SHA256="cffe8fbfa9cfb794f1d920ff187016f823a555f7814cede99026699a936b92c7"

printf '%s  %s\n' "$EXPECTED_SHA256" "$SOURCE_PATH" | shasum -a 256 -c -
mkdir -p "$(dirname "$OUTPUT_PATH")"
/usr/bin/install -m 0644 "$SOURCE_PATH" "$OUTPUT_PATH"

if [[ ! -s "$OUTPUT_PATH" ]] \
  || ! /usr/bin/file "$OUTPUT_PATH" | /usr/bin/grep -q "MetalLib executable"; then
  echo "failed to embed a valid MLX Metal library at $OUTPUT_PATH" >&2
  exit 1
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --sign - --timestamp=none "$OUTPUT_PATH" >/dev/null
else
  /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    "$OUTPUT_PATH" >/dev/null
fi

/usr/bin/codesign --verify --strict "$OUTPUT_PATH"
printf '%s  %s\n' "$EXPECTED_SHA256" "$OUTPUT_PATH" | shasum -a 256 -c - >/dev/null
