#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 4 ]]; then
  echo "Usage: $0 RUN_ID MODEL_ID ARTIFACT_DIRECTORY ENGINE [engine options...]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$SCRIPT_DIR/Corpus/english-catalog-rating-v1.index.json"
MODEL_MANIFEST="${TEXTIFY_CATALOG_MODEL_MANIFEST:-$SCRIPT_DIR/../../models/manifest.json}"
RUN_ID="$1"
MODEL_ID="$2"
ARTIFACT_DIRECTORY="$3"
ENGINE="$4"
shift 4

if ! [[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "RUN_ID may contain only letters, numbers, dot, underscore, and hyphen." >&2
  exit 2
fi
if ! [[ "$MODEL_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "MODEL_ID may contain only letters, numbers, dot, underscore, and hyphen." >&2
  exit 2
fi
if ! git -C "$SCRIPT_DIR" rev-parse --verify HEAD >/dev/null 2>&1 \
  || [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain --untracked-files=normal)" ]]; then
  echo "Catalog rating runs require a clean checkout at a Git commit." >&2
  exit 1
fi

RUN_ROOT="$SCRIPT_DIR/.benchmark-results/catalog-rating/$RUN_ID"
if [[ -e "$RUN_ROOT" ]]; then
  echo "Rating run already exists; choose a new RUN_ID: $RUN_ROOT" >&2
  exit 1
fi

artifact_fingerprint="$("$SCRIPT_DIR/verify_catalog_model_artifact.sh" \
  "$MODEL_MANIFEST" \
  "$MODEL_ID" \
  "$ARTIFACT_DIRECTORY")"
mkdir -p "$RUN_ROOT"

cd "$SCRIPT_DIR"
/usr/bin/swift build -c release --product TextifyEvaluationTool
TOOL="$SCRIPT_DIR/.build/release/TextifyEvaluationTool"
"$TOOL" validate-index "$INDEX"

while IFS=$'\t' read -r manifest component_id max_audio_seconds; do
  TEXTIFY_BENCHMARK_MODEL_ID="$MODEL_ID" \
  TEXTIFY_BENCHMARK_LABEL="$MODEL_ID" \
  TEXTIFY_BENCHMARK_OUTPUT_ROOT="$RUN_ROOT" \
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

index_sha256="$(/usr/bin/shasum -a 256 "$INDEX" | /usr/bin/awk '{print $1}')"
git_commit="$(git -C "$SCRIPT_DIR" rev-parse HEAD)"
created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
resident_engine="$(/usr/bin/jq -r '.engine' "$RUN_ROOT/open-asr-english-nightly-v1/batch-session.json")"
/usr/bin/jq -n \
  --arg run_id "$RUN_ID" \
  --arg model_id "$MODEL_ID" \
  --arg engine "$resident_engine" \
  --arg artifact_fingerprint "$artifact_fingerprint" \
  --arg created_at "$created_at" \
  --arg git_commit "$git_commit" \
  --arg index_sha256 "$index_sha256" \
  '{
    schemaVersion: 1,
    runID: $run_id,
    modelID: $model_id,
    engine: $engine,
    artifactFingerprint: $artifact_fingerprint,
    createdAt: $created_at,
    gitCommit: $git_commit,
    suiteIndexSHA256: $index_sha256
  }' > "$RUN_ROOT/run.json"

echo "$RUN_ROOT"
