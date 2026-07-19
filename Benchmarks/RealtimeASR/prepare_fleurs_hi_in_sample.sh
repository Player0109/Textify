#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/Corpus/fleurs-hi-in-sample.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/fleurs-hi-in-sample"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

DATASET_ID="$(/usr/bin/jq -r '.dataset.id' "$CORPUS")"
DATASET_REVISION="$(/usr/bin/jq -r '.dataset.revision' "$CORPUS")"
CONFIG="$(/usr/bin/jq -r '.dataset.config' "$CORPUS")"
SPLIT="$(/usr/bin/jq -r '.dataset.split' "$CORPUS")"
ROW_COUNT="$(/usr/bin/jq '[.items[].row] | max + 1' "$CORPUS")"
ROWS_URL="https://datasets-server.huggingface.co/rows?dataset=$DATASET_ID&config=$CONFIG&split=$SPLIT&offset=0&length=$ROW_COUNT"

mkdir -p "$DATA_DIR"
/usr/bin/curl -fsSL "$ROWS_URL" -o "$TEMP_DIR/rows.json"

/usr/bin/jq -e \
  --arg revision "$DATASET_REVISION" \
  --arg config "$CONFIG" \
  --arg split "$SPLIT" \
  'all(.rows[]; .row.audio[0].src | contains("/--/" + $revision + "/--/" + $config + "/" + $split + "/"))' \
  "$TEMP_DIR/rows.json" >/dev/null

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

while IFS=$'\t' read -r row_index audio_path expected_size expected_sha; do
  destination="$DATA_DIR/$audio_path"
  if [[ -f "$destination" ]] && verify_file "$destination" "$expected_size" "$expected_sha"; then
    continue
  fi

  audio_url="$(/usr/bin/jq -r --argjson row "$row_index" \
    '.rows[] | select(.row_idx == $row) | .row.audio[0].src' "$TEMP_DIR/rows.json")"
  [[ -n "$audio_url" && "$audio_url" != "null" ]]

  staged="$TEMP_DIR/$audio_path"
  /usr/bin/curl -fsSL "$audio_url" -o "$staged"
  verify_file "$staged" "$expected_size" "$expected_sha"
  /bin/mv "$staged" "$destination"
done < <(/usr/bin/jq -r '.items[] | [.row, .audio, .sizeBytes, .sha256] | @tsv' "$CORPUS")

echo "Verified Hindi FLEURS sample at $DATA_DIR"
