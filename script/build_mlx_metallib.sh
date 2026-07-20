#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  echo "usage: $0 OUTPUT_PATH [MLX_SWIFT_CHECKOUT]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="$1"
MLX_SWIFT_CHECKOUT="${2:-$ROOT_DIR/.build/checkouts/mlx-swift}"
EXPECTED_REVISION="61b9e011e09a62b489f6bd647958f1555bdf2896"
METAL_SOURCE_ROOT="$MLX_SWIFT_CHECKOUT/Source/Cmlx/mlx-generated/metal"
OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/textify-mlx-metallib.XXXXXX")"
TEMP_LIBRARY_PATH="$TEMP_DIR/mlx.metallib"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [[ ! -d "$METAL_SOURCE_ROOT" ]]; then
  echo "missing pinned MLX Metal sources: $METAL_SOURCE_ROOT" >&2
  exit 1
fi

ACTUAL_REVISION="$(git -C "$MLX_SWIFT_CHECKOUT" rev-parse HEAD)"
if [[ "$ACTUAL_REVISION" != "$EXPECTED_REVISION" ]]; then
  echo "unexpected mlx-swift revision: $ACTUAL_REVISION" >&2
  exit 1
fi

METAL_SOURCES=(
  arg_reduce.metal
  conv.metal
  gemv.metal
  layer_norm.metal
  random.metal
  rms_norm.metal
  rope.metal
  scaled_dot_product_attention.metal
  steel/attn/kernels/steel_attention.metal
)

ACTUAL_METAL_SOURCES="$(
  find "$METAL_SOURCE_ROOT" -type f -name '*.metal' -print \
    | sed "s|^$METAL_SOURCE_ROOT/||" \
    | sort
)"
EXPECTED_METAL_SOURCES="$(printf '%s\n' "${METAL_SOURCES[@]}" | sort)"
if [[ "$ACTUAL_METAL_SOURCES" != "$EXPECTED_METAL_SOURCES" ]]; then
  echo "mlx-swift Metal entry-point set does not match the pinned build contract" >&2
  diff -u <(printf '%s\n' "$EXPECTED_METAL_SOURCES") <(printf '%s\n' "$ACTUAL_METAL_SOURCES") >&2 || true
  exit 1
fi

for metal_source in "${METAL_SOURCES[@]}"; do
  air_name="${metal_source//\//_}"
  /usr/bin/xcrun -sdk macosx metal \
    -x metal \
    -Wall \
    -Wextra \
    -fno-fast-math \
    -Wno-c++17-extensions \
    -Wno-c++20-extensions \
    -mmacosx-version-min=14.0 \
    -I "$METAL_SOURCE_ROOT" \
    -c "$METAL_SOURCE_ROOT/$metal_source" \
    -o "$TEMP_DIR/$air_name.air"
done

/usr/bin/xcrun -sdk macosx metallib \
  "$TEMP_DIR"/*.air \
  -o "$TEMP_LIBRARY_PATH"

/usr/bin/strings "$TEMP_LIBRARY_PATH" > "$TEMP_DIR/mlx.metallib.strings"

if [[ ! -s "$TEMP_LIBRARY_PATH" ]] \
  || ! /usr/bin/file "$TEMP_LIBRARY_PATH" | /usr/bin/grep -q "MetalLib executable" \
  || ! /usr/bin/grep -Fq "layer_normfloat32" "$TEMP_DIR/mlx.metallib.strings"; then
  echo "failed to build a complete MLX Metal library" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
/usr/bin/install -m 0644 "$TEMP_LIBRARY_PATH" "$OUTPUT_PATH"
