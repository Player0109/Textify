#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/Corpus/open-asr-english-pr-v1.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/open-asr-english-pr-v1"
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
  local expected_size="$2"
  local expected_sha="$3"
  local actual_size
  local actual_sha
  actual_size="$(/usr/bin/stat -f '%z' "$path")"
  actual_sha="$(/usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}')"
  [[ "$actual_size" == "$expected_size" && "$actual_sha" == "$expected_sha" ]]
}

mkdir -p "$DATA_DIR"

while IFS=$'\t' read -r item_id config split row audio_path reference duration_ms expected_size expected_sha; do
  destination="$DATA_DIR/$audio_path"
  mkdir -p "$(dirname "$destination")"
  if [[ -f "$destination" ]] && verify_file "$destination" "$expected_size" "$expected_sha"; then
    continue
  fi

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
    --arg reference "$reference" \
    --arg revision "$DATASET_REVISION" \
    --arg config "$config" \
    --arg split "$split" \
    --argjson duration_ms "$duration_ms" \
    '.rows[0] as $entry
      | $entry.row_idx == $row
      and $entry.row.text == $reference
      and (($entry.row.audio_length_s * 1000 | floor) == $duration_ms)
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

  if ! verify_file "$staged" "$expected_size" "$expected_sha"; then
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
      | [$item.id, .config, .split, $item.row, $item.audio, $item.reference,
         $item.durationMs, $item.sizeBytes, $item.sha256]
      | @tsv' \
    "$CORPUS"
)

echo "Verified Open ASR English PR corpus at $DATA_DIR"
