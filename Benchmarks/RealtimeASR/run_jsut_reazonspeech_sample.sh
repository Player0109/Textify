#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL_DIRECTORY="${1:-}"
SHERPA_RUNTIME_DIRECTORY="${2:-$SCRIPT_DIR/../../Vendor/sherpa-onnx/v1.13.2/lib}"

if [[ -z "$MODEL_DIRECTORY" || ! -d "$MODEL_DIRECTORY" ]]; then
  echo "Usage: $0 /path/to/reazonspeech-k2-v2-int8 [sherpa-runtime-directory]" >&2
  exit 2
fi
if [[ "$MODEL_DIRECTORY" != /* ]]; then
  MODEL_DIRECTORY="$(pwd)/$MODEL_DIRECTORY"
fi
if [[ "$SHERPA_RUNTIME_DIRECTORY" != /* ]]; then
  SHERPA_RUNTIME_DIRECTORY="$(pwd)/$SHERPA_RUNTIME_DIRECTORY"
fi
if [[ ! -d "$SHERPA_RUNTIME_DIRECTORY" ]]; then
  echo "sherpa-onnx runtime directory does not exist: $SHERPA_RUNTIME_DIRECTORY" >&2
  exit 2
fi

DATA_DIR="$SCRIPT_DIR/.benchmark-data/jsut-basic5000-sample"
CORPUS="$SCRIPT_DIR/Corpus/jsut-basic5000-sample.json"
RESULT_DIR="$SCRIPT_DIR/results/jsut-basic5000/reazonspeech-k2-v2-int8"

cd "$SCRIPT_DIR"
./prepare_jsut_sample.sh
/usr/bin/swift build -c release
mkdir -p "$RESULT_DIR"

while IFS=$'\t' read -r item_id audio_path reference; do
  .build/release/TextifyRealtimeBenchmark \
    --engine reazonspeech-k2-v2 \
    --audio "$DATA_DIR/$audio_path" \
    --reference "$reference" \
    --sherpa-runtime "$SHERPA_RUNTIME_DIRECTORY" \
    --sherpa-model "$MODEL_DIRECTORY" \
    --feed-mode accelerated \
    --output "$RESULT_DIR/$item_id.json"
done < <(/usr/bin/jq -r '.items[] | [.id, .audio, .reference] | @tsv' "$CORPUS")

echo "ReazonSpeech Japanese sample results written to $RESULT_DIR"
