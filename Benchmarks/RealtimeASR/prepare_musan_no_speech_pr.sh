#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/Corpus/musan-no-speech-pr-v1.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/musan-no-speech-pr-v1"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  /usr/bin/find "$TEMP_DIR" -type f -delete 2>/dev/null || true
  /bin/rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

cd "$SCRIPT_DIR"
/usr/bin/swift build -c release --product TextifyEvaluationTool
TOOL="$SCRIPT_DIR/.build/release/TextifyEvaluationTool"
"$TOOL" validate "$CORPUS"

DATASET_ID="$(/usr/bin/jq -r '.dataset.id' "$CORPUS")"
DATASET_REVISION="$(/usr/bin/jq -r '.dataset.revision' "$CORPUS")"
VIEWER_BASE_URL="$(/usr/bin/jq -r '.dataset.viewerBaseURL' "$CORPUS")"

verify_file() {
  local path="$1"
  local expected_duration_ms="$2"
  local expected_size="$3"
  local expected_sha="$4"
  local actual_duration_ms
  local actual_size
  local actual_sha
  actual_duration_ms="$(/usr/bin/afinfo "$path" | /usr/bin/awk '
    /estimated duration/ { printf "%d", ($3 * 1000) + 0.5; found = 1 }
    END { if (!found) exit 1 }
  ')"
  actual_size="$(/usr/bin/stat -f '%z' "$path")"
  actual_sha="$(/usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}')"
  [[ "$actual_duration_ms" == "$expected_duration_ms" \
    && "$actual_size" == "$expected_size" \
    && "$actual_sha" == "$expected_sha" ]]
}

mkdir -p "$DATA_DIR"

while IFS=$'\t' read -r item_id subset_id config split row audio_path duration_ms expected_size expected_sha; do
  destination="$DATA_DIR/$audio_path"
  mkdir -p "$(dirname "$destination")"
  if [[ -f "$destination" ]] \
    && verify_file "$destination" "$duration_ms" "$expected_size" "$expected_sha"; then
    continue
  fi

  expected_source="${subset_id#musan-}"
  clip_number="${item_id##*-}"
  expected_source_path="noise/$expected_source/noise-$expected_source-$clip_number.wav"
  row_json="$(mktemp "$TEMP_DIR/row.XXXXXX")"
  /usr/bin/curl \
    --http1.1 \
    --retry 4 \
    --retry-all-errors \
    --retry-delay 2 \
    --fail \
    --silent \
    --location \
    --get \
    --data-urlencode "dataset=$DATASET_ID" \
    --data-urlencode "config=$config" \
    --data-urlencode "split=$split" \
    --data-urlencode "offset=$row" \
    --data-urlencode "length=1" \
    --output "$row_json" \
    "$VIEWER_BASE_URL/rows"

  /usr/bin/jq -e \
    --argjson row "$row" \
    --arg revision "$DATASET_REVISION" \
    --arg config "$config" \
    --arg split "$split" \
    --arg source "$expected_source" \
    --arg source_path "$expected_source_path" \
    '.rows[0] as $entry
      | $entry.row_idx == $row
      and $entry.row.label == 2
      and $entry.row.source == $source
      and $entry.row.path == $source_path
      and ($entry.row.audio[0].src
        | contains("/--/" + $revision + "/--/" + $config + "/" + $split + "/" + ($row | tostring) + "/audio/"))' \
    "$row_json" >/dev/null || {
      echo "Dataset metadata changed for $item_id." >&2
      exit 1
    }

  audio_url="$(/usr/bin/jq -er '.rows[0].row.audio[0].src' "$row_json")"
  staged="$(mktemp "$TEMP_DIR/audio.XXXXXX")"
  /usr/bin/curl \
    --http1.1 \
    --retry 4 \
    --retry-all-errors \
    --retry-delay 2 \
    --fail \
    --silent \
    --location \
    --output "$staged" \
    "$audio_url"

  if ! verify_file "$staged" "$duration_ms" "$expected_size" "$expected_sha"; then
    echo "Audio verification failed for $item_id." >&2
    exit 1
  fi
  /bin/mv "$staged" "$destination"
  /bin/sleep 1
done < <(
  /usr/bin/jq -r \
    '.items[] as $item
      | .subsets[]
      | select(.id == $item.subsetID)
      | [$item.id, $item.subsetID, .config, .split, $item.row, $item.audio,
         $item.durationMs, $item.sizeBytes, $item.sha256]
      | @tsv' \
    "$CORPUS"
)

echo "Verified MUSAN no-speech PR corpus at $DATA_DIR"
