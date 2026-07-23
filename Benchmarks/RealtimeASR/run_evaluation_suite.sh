#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 5 ]]; then
  echo "Usage: $0 MANIFEST DATA_DIR ENGINE MODE MAX_AUDIO_SECONDS [engine options...]" >&2
  exit 2
fi

CALLER_DIR="$PWD"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$1"
DATA_DIR="$2"
ENGINE="$3"
MODE="$4"
MAX_AUDIO_SECONDS="$5"
shift 5

if [[ "$MANIFEST" != /* ]]; then
  MANIFEST="$CALLER_DIR/$MANIFEST"
fi
if [[ "$DATA_DIR" != /* ]]; then
  DATA_DIR="$CALLER_DIR/$DATA_DIR"
fi
if [[ "$MODE" != "accelerated" && "$MODE" != "realtime" ]]; then
  echo "MODE must be accelerated or realtime." >&2
  exit 2
fi
if ! [[ "$MAX_AUDIO_SECONDS" =~ ^[0-9]+$ ]] \
  || (( MAX_AUDIO_SECONDS < 1 || MAX_AUDIO_SECONDS > 60 )); then
  echo "MAX_AUDIO_SECONDS must be between 1 and 60." >&2
  exit 2
fi

cd "$SCRIPT_DIR"
/usr/bin/swift build -c release --product TextifyEvaluationTool
/usr/bin/swift build -c release --product TextifyRealtimeBenchmark

TOOL="$SCRIPT_DIR/.build/release/TextifyEvaluationTool"
BINARY="$SCRIPT_DIR/.build/release/TextifyRealtimeBenchmark"
"$TOOL" validate "$MANIFEST"

case "$ENGINE" in
  whisper)
    "$SCRIPT_DIR/prepare_whisper_metal.sh"
    ;;
  mlx-*)
    "$SCRIPT_DIR/prepare_mlx_metal.sh"
    ;;
esac

SUITE_ID="$(/usr/bin/jq -r '.id' "$MANIFEST")"
RESULT_LABEL="${TEXTIFY_BENCHMARK_LABEL:-$ENGINE}"
if ! [[ "$RESULT_LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "TEXTIFY_BENCHMARK_LABEL may contain only letters, numbers, dot, underscore, and hyphen." >&2
  exit 2
fi
if [[ -n "${TEXTIFY_BENCHMARK_OUTPUT_ROOT:-}" ]]; then
  OUTPUT_ROOT="$TEXTIFY_BENCHMARK_OUTPUT_ROOT"
  if [[ "$OUTPUT_ROOT" != /* ]]; then
    OUTPUT_ROOT="$CALLER_DIR/$OUTPUT_ROOT"
  fi
  RESULT_DIR="$OUTPUT_ROOT/$SUITE_ID"
else
  RESULT_DIR="$SCRIPT_DIR/results/$SUITE_ID/$MODE/$RESULT_LABEL/max-${MAX_AUDIO_SECONDS}s"
fi
mkdir -p "$RESULT_DIR"

item_count=0
if [[ "$ENGINE" != "apple-dictation-analyzer" \
   && "$ENGINE" != "apple-speech-analyzer" \
   && "$ENGINE" != "parakeet-eou-160" \
   && "$ENGINE" != "parakeet-unified-320" \
   && "$ENGINE" != "paraformer-large-zh-int8" \
   && "$ENGINE" != "litert-gemma-4-12b" ]]; then
  batch_jobs="$(mktemp)"
  cleanup() {
    /bin/rm -f "$batch_jobs"
  }
  trap cleanup EXIT
  "$TOOL" compatible-items "$MANIFEST" --max-audio-seconds "$MAX_AUDIO_SECONDS" \
    | /usr/bin/jq --arg data_dir "$DATA_DIR" \
      '{schemaVersion: 1, items: map({
        id,
        audio: ($data_dir + "/" + .audio),
        reference
      })}' > "$batch_jobs"
  item_count="$(/usr/bin/jq -r '.items | length' "$batch_jobs")"
  if (( item_count == 0 )); then
    echo "No corpus items are compatible with MAX_AUDIO_SECONDS=$MAX_AUDIO_SECONDS." >&2
    exit 1
  fi
  "$BINARY" \
    --engine "$ENGINE" \
    --batch-jobs "$batch_jobs" \
    --batch-output-dir "$RESULT_DIR" \
    --feed-mode "$MODE" \
    "$@"
else
  while IFS=$'\t' read -r item_id audio_path reference; do
    audio="$DATA_DIR/$audio_path"
    if [[ ! -f "$audio" ]]; then
      echo "Missing corpus audio: $audio" >&2
      exit 1
    fi

    "$BINARY" \
      --engine "$ENGINE" \
      --audio "$audio" \
      --reference "$reference" \
      --feed-mode "$MODE" \
      --output "$RESULT_DIR/$item_id.json" \
      "$@"
    item_count=$((item_count + 1))
  done < <(
    "$TOOL" compatible-items "$MANIFEST" --max-audio-seconds "$MAX_AUDIO_SECONDS" \
      | /usr/bin/jq -r '.[] | [.id, .audio, .reference] | @tsv'
  )
fi

if (( item_count == 0 )); then
  echo "No corpus items are compatible with MAX_AUDIO_SECONDS=$MAX_AUDIO_SECONDS." >&2
  exit 1
fi

"$TOOL" summarize "$MANIFEST" "$RESULT_DIR" \
  --max-audio-seconds "$MAX_AUDIO_SECONDS" \
  > "$RESULT_DIR/summary.json"

echo "Wrote $item_count results and summary to $RESULT_DIR"
