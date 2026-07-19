#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_MODEL="${1:-}"
RESULT_LABEL="${2:-}"

if [[ -z "$WHISPER_MODEL" || ! -f "$WHISPER_MODEL" ]]; then
  echo "Usage: $0 /path/to/whisper-model.bin [result-label]" >&2
  exit 2
fi
if [[ "$WHISPER_MODEL" != /* ]]; then
  WHISPER_MODEL="$(pwd)/$WHISPER_MODEL"
fi
if [[ -z "$RESULT_LABEL" ]]; then
  RESULT_LABEL="$(basename "$WHISPER_MODEL")"
  RESULT_LABEL="${RESULT_LABEL%.*}"
fi
if [[ ! "$RESULT_LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Result label may contain only letters, digits, dots, underscores, and hyphens." >&2
  exit 2
fi

DATA_DIR="$SCRIPT_DIR/.benchmark-data/jsut-basic5000-sample"
CORPUS="$SCRIPT_DIR/Corpus/jsut-basic5000-sample.json"
RESULT_DIR="$SCRIPT_DIR/results/jsut-basic5000/$RESULT_LABEL"

cd "$SCRIPT_DIR"
./prepare_jsut_sample.sh
/usr/bin/swift build -c release
./prepare_whisper_metal.sh
mkdir -p "$RESULT_DIR"

while IFS=$'\t' read -r item_id audio_path reference; do
  .build/release/TextifyRealtimeBenchmark \
    --engine whisper \
    --audio "$DATA_DIR/$audio_path" \
    --reference "$reference" \
    --whisper-model "$WHISPER_MODEL" \
    --language ja \
    --feed-mode accelerated \
    --output "$RESULT_DIR/$item_id.json"
done < <(/usr/bin/jq -r '.items[] | [.id, .audio, .reference] | @tsv' "$CORPUS")

echo "Japanese Whisper sample results written to $RESULT_DIR"
