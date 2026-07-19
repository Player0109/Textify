#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLUID_CACHE="${1:-$HOME/Library/Application Support/FluidAudio/Models}"
if [[ "$FLUID_CACHE" != /* ]]; then
  FLUID_CACHE="$(pwd)/$FLUID_CACHE"
fi
DATA_DIR="$SCRIPT_DIR/.benchmark-data/jsut-basic5000-sample"
CORPUS="$SCRIPT_DIR/Corpus/jsut-basic5000-sample.json"
RESULT_DIR="$SCRIPT_DIR/results/jsut-basic5000/parakeet-tdt-ja"

cd "$SCRIPT_DIR"
./prepare_jsut_sample.sh
/usr/bin/swift build -c release
mkdir -p "$RESULT_DIR"

while IFS=$'\t' read -r item_id audio_path reference; do
  .build/release/TextifyRealtimeBenchmark \
    --engine parakeet-tdt-ja \
    --audio "$DATA_DIR/$audio_path" \
    --reference "$reference" \
    --fluid-cache "$FLUID_CACHE" \
    --feed-mode accelerated \
    --output "$RESULT_DIR/$item_id.json"
done < <(/usr/bin/jq -r '.items[] | [.id, .audio, .reference] | @tsv' "$CORPUS")

echo "Japanese sample results written to $RESULT_DIR"
