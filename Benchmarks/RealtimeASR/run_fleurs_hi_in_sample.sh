#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_MODEL="${1:-}"
CORPUS="$SCRIPT_DIR/Corpus/fleurs-hi-in-sample.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/fleurs-hi-in-sample"
RESULT_DIR="$SCRIPT_DIR/results/fleurs-hi-in/whisper"

if [[ ! -f "$WHISPER_MODEL" ]]; then
  echo "Usage: $0 /path/to/multilingual-whisper-model.bin" >&2
  exit 2
fi
if [[ "$WHISPER_MODEL" != /* ]]; then
  WHISPER_MODEL="$(pwd)/$WHISPER_MODEL"
fi

cd "$SCRIPT_DIR"
./prepare_fleurs_hi_in_sample.sh
/usr/bin/swift build -c release
./prepare_whisper_metal.sh
mkdir -p "$RESULT_DIR"

while IFS=$'\t' read -r item_id audio_path reference; do
  .build/release/TextifyRealtimeBenchmark \
    --engine whisper \
    --audio "$DATA_DIR/$audio_path" \
    --reference "$reference" \
    --whisper-model "$WHISPER_MODEL" \
    --language hi \
    --feed-mode accelerated \
    --output "$RESULT_DIR/$item_id.json"
done < <(/usr/bin/jq -r '.items[] | [.id, .audio, .reference] | @tsv' "$CORPUS")

echo "Hindi FLEURS results written to $RESULT_DIR"
