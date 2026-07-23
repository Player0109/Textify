#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 6 ]]; then
  echo "Usage: $0 MODEL_ID MEASURED_AT RUN_ID_1 RUN_ID_2 RUN_ID_3 OUTPUT" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$SCRIPT_DIR/Corpus/english-catalog-rating-v1.index.json"
POLICY="$SCRIPT_DIR/Corpus/english-catalog-rating-v2.policy.json"
MODEL_ID="$1"
MEASURED_AT="$2"
OUTPUT="$6"

if [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$PWD/$OUTPUT"
fi
mkdir -p "$(dirname "$OUTPUT")"

cd "$SCRIPT_DIR"
/usr/bin/swift build -c release --product TextifyEvaluationTool
TOOL="$SCRIPT_DIR/.build/release/TextifyEvaluationTool"
RUN_1="$SCRIPT_DIR/.benchmark-results/catalog-rating/$3"
RUN_2="$SCRIPT_DIR/.benchmark-results/catalog-rating/$4"
RUN_3="$SCRIPT_DIR/.benchmark-results/catalog-rating/$5"
ARTIFACT_FINGERPRINT="$(/usr/bin/jq -r '.artifactFingerprint' "$RUN_1/run.json")"
"$TOOL" rate-index "$INDEX" \
  --policy "$POLICY" \
  --model-id "$MODEL_ID" \
  --artifact-fingerprint "$ARTIFACT_FINGERPRINT" \
  --measured-at "$MEASURED_AT" \
  --run-dir "$RUN_1" \
  --run-dir "$RUN_2" \
  --run-dir "$RUN_3" \
  > "$OUTPUT"

echo "$OUTPUT"
