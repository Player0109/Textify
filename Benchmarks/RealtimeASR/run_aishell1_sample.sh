#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLUID_CACHE="${1:-$HOME/Library/Application Support/FluidAudio/Models}"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/aishell1-sample"
RESULT_DIR="$SCRIPT_DIR/results/aishell1/accelerated/paraformer-large-zh-int8"

cd "$SCRIPT_DIR"
./prepare_aishell1_sample.sh
/usr/bin/swift build -c release
mkdir -p "$RESULT_DIR"

BINARY="$SCRIPT_DIR/.build/release/TextifyRealtimeBenchmark"
while IFS=$'\t' read -r item_id audio_path reference; do
  "$BINARY" \
    --engine paraformer-large-zh-int8 \
    --audio "$DATA_DIR/$audio_path" \
    --reference "$reference" \
    --fluid-cache "$FLUID_CACHE" \
    --feed-mode accelerated \
    --output "$RESULT_DIR/$item_id.json"
done < <(/usr/bin/jq -r '.items[] | [.id, .audio, .reference] | @tsv' Corpus/aishell1-sample.json)

echo "AISHELL-1 results written to $RESULT_DIR"
