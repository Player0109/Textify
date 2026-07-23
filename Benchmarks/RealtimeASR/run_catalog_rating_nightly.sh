#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 MODEL_CONFIG_JSON OUTPUT_DIRECTORY" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="$1"
OUTPUT_DIRECTORY="$2"

if [[ ! -f "$CONFIG" ]]; then
  echo "Nightly model configuration does not exist: $CONFIG" >&2
  exit 1
fi
if [[ "$OUTPUT_DIRECTORY" != /* ]]; then
  OUTPUT_DIRECTORY="$PWD/$OUTPUT_DIRECTORY"
fi

if [[ "$(/usr/sbin/sysctl -n machdep.cpu.brand_string)" != "Apple M4 Max" ]]; then
  echo "Catalog ratings require the Apple M4 Max reference host." >&2
  exit 1
fi
if ! git -C "$REPO_ROOT" rev-parse --verify HEAD >/dev/null 2>&1 \
  || [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=normal)" ]]; then
  echo "Nightly catalog ratings require a clean checkout at a Git commit." >&2
  exit 1
fi

config_keys="$(/usr/bin/jq -r 'keys | sort | join(",")' "$CONFIG")"
if [[ "$config_keys" != "models,schemaVersion" ]] \
  || [[ "$(/usr/bin/jq -r '.schemaVersion' "$CONFIG")" != "1" ]] \
  || [[ "$(/usr/bin/jq -r '.models | length' "$CONFIG")" -lt 1 ]]; then
  echo "Nightly model configuration must contain schemaVersion 1 and at least one model." >&2
  exit 1
fi
if ! /usr/bin/jq -e '
  all(.models[];
    ((keys - ["id", "artifactDirectory", "engine", "engineOptions", "baseline", "catalogManifest"]) | length) == 0
      and has("id")
      and has("artifactDirectory")
      and has("engine")
      and has("engineOptions")
      and (.id | type == "string")
      and (.artifactDirectory | type == "string" and startswith("/"))
      and (.engine | type == "string")
      and (.engineOptions | type == "array" and all(.[]; type == "string"))
      and ((has("baseline") | not) or (.baseline | type == "string" and startswith("/")))
      and ((has("catalogManifest") | not) or (.catalogManifest | type == "string" and startswith("/")))
  )
' "$CONFIG" >/dev/null; then
  echo "Nightly model entries have missing, unknown, or invalid fields." >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIRECTORY/candidates" "$OUTPUT_DIRECTORY/regressions"

"$SCRIPT_DIR/prepare_open_asr_english_nightly.sh"
"$SCRIPT_DIR/prepare_edacc_english_nightly.sh"
"$SCRIPT_DIR/prepare_berst_english_nightly.sh"
"$SCRIPT_DIR/prepare_musan_no_speech_nightly.sh"

nightly_id="$(date -u +%Y%m%dT%H%M%SZ)"
measured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
model_count="$(/usr/bin/jq -r '.models | length' "$CONFIG")"

for ((model_index = 0; model_index < model_count; model_index += 1)); do
  model_id="$(/usr/bin/jq -r --argjson index "$model_index" '.models[$index].id' "$CONFIG")"
  artifact_directory="$(/usr/bin/jq -r --argjson index "$model_index" '.models[$index].artifactDirectory' "$CONFIG")"
  engine="$(/usr/bin/jq -r --argjson index "$model_index" '.models[$index].engine' "$CONFIG")"
  baseline="$(/usr/bin/jq -r --argjson index "$model_index" '.models[$index].baseline // empty' "$CONFIG")"
  catalog_manifest="$(/usr/bin/jq -r --argjson index "$model_index" '.models[$index].catalogManifest // empty' "$CONFIG")"
  if ! [[ "$model_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Unsafe nightly model id: $model_id" >&2
    exit 1
  fi

  engine_options=()
  while IFS= read -r option; do
    engine_options+=("$option")
  done < <(
    /usr/bin/jq -r --argjson index "$model_index" '.models[$index].engineOptions[]' "$CONFIG"
  )

  run_ids=()
  for run_number in 1 2 3; do
    run_id="$nightly_id-$model_id-r$run_number"
    run_ids+=("$run_id")
    TEXTIFY_CATALOG_MODEL_MANIFEST="$catalog_manifest" \
      "$SCRIPT_DIR/run_english_catalog_rating.sh" \
      "$run_id" \
      "$model_id" \
      "$artifact_directory" \
      "$engine" \
      "${engine_options[@]}"
  done

  candidate="$OUTPUT_DIRECTORY/candidates/$model_id.json"
  "$SCRIPT_DIR/generate_english_catalog_rating.sh" \
    "$model_id" \
    "$measured_at" \
    "${run_ids[0]}" \
    "${run_ids[1]}" \
    "${run_ids[2]}" \
    "$candidate"

  if [[ -n "$baseline" ]]; then
    "$SCRIPT_DIR/compare_catalog_ratings.sh" \
      "$baseline" \
      "$candidate" \
      "$OUTPUT_DIRECTORY/regressions/$model_id.json"
  fi
done

/usr/bin/jq -n \
  --arg nightly_id "$nightly_id" \
  --arg measured_at "$measured_at" \
  --arg config "$CONFIG" \
  --argjson model_count "$model_count" \
  '{
    schemaVersion: 1,
    nightlyID: $nightly_id,
    measuredAt: $measured_at,
    modelConfig: $config,
    modelCount: $model_count,
    productionManifestEdited: false,
    productionManifestSigned: false
  }' > "$OUTPUT_DIRECTORY/nightly.json"

echo "$OUTPUT_DIRECTORY"
