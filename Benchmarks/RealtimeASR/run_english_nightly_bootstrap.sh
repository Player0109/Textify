#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 ENGINE [engine options...]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$SCRIPT_DIR/Corpus/english-nightly-bootstrap-v1.index.json"
ENGINE="$1"
shift

cd "$SCRIPT_DIR"
/usr/bin/swift build -c release --product TextifyEvaluationTool
TOOL="$SCRIPT_DIR/.build/release/TextifyEvaluationTool"
"$TOOL" validate-index "$INDEX"

while IFS=$'\t' read -r manifest component_id max_audio_seconds; do
  "$SCRIPT_DIR/run_evaluation_suite.sh" \
    "$SCRIPT_DIR/Corpus/$manifest" \
    "$SCRIPT_DIR/.benchmark-data/$component_id" \
    "$ENGINE" \
    accelerated \
    "$max_audio_seconds" \
    "$@"
done < <(
  /usr/bin/jq -r \
    '.components[] | [.manifest, .id, .maxAudioSeconds] | @tsv' \
    "$INDEX"
)

echo "Completed English nightly bootstrap for $ENGINE"
