#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-accelerated}"
WHISPER_MODEL="${2:-}"
FLUID_CACHE="${3:-$HOME/Library/Application Support/FluidAudio/Models}"

if [[ "$MODE" != "accelerated" && "$MODE" != "realtime" ]]; then
  echo "Usage: $0 [accelerated|realtime] /path/to/whisper-model.bin" >&2
  exit 2
fi
if [[ ! -f "$WHISPER_MODEL" ]]; then
  echo "A valid Whisper model path is required." >&2
  exit 2
fi

cd "$SCRIPT_DIR"
./prepare_public_corpus.sh
/usr/bin/swift build -c release
./prepare_whisper_metal.sh

BINARY="$SCRIPT_DIR/.build/release/TextifyRealtimeBenchmark"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/openslr31"
RESULT_DIR="$SCRIPT_DIR/results/openslr31/$MODE"

for engine in whisper parakeet-tdt-v2 parakeet-tdt-v3 parakeet-tdt-ctc-110m parakeet-eou-160 parakeet-unified-320 apple-speech-analyzer apple-dictation-analyzer; do
  mkdir -p "$RESULT_DIR/$engine"
  while IFS=$'\t' read -r item_id audio_path reference; do
    arguments=(
      --engine "$engine"
      --audio "$DATA_DIR/$audio_path"
      --reference "$reference"
      --feed-mode "$MODE"
      --output "$RESULT_DIR/$engine/$item_id.json"
    )
    if [[ "$engine" == "whisper" ]]; then
      arguments+=(--whisper-model "$WHISPER_MODEL")
    fi
    if [[ "$engine" == parakeet-tdt-* ]]; then
      arguments+=(--fluid-cache "$FLUID_CACHE")
    fi
    "$BINARY" "${arguments[@]}"
  done < <(/usr/bin/jq -r '.items[] | [.id, .audio, .reference] | @tsv' Corpus/openslr31.json)
done

echo "Corpus results written to $RESULT_DIR"
