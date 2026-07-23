#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/Corpus/musan-no-speech-nightly-v1.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/musan-no-speech-nightly-v1"
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

metadata_queue="$TEMP_DIR/metadata-queue"
offset=0
while (( offset < 930 )); do
  destination="$TEMP_DIR/page-$offset.json"
  /usr/bin/printf '%s\0%s\0' "$offset" "$destination" >> "$metadata_queue"
  offset=$((offset + 100))
done

/usr/bin/xargs -0 -n 2 -P 1 /bin/bash -c '
  set -euo pipefail
  offset="$1"
  destination="$2"
  /usr/bin/curl \
    --http1.1 \
    --retry 12 \
    --retry-all-errors \
    --retry-delay 0 \
    --retry-max-time 300 \
    --fail \
    --silent \
    --show-error \
    --location \
    --get \
    --data-urlencode "dataset=corypaik/musan" \
    --data-urlencode "config=noise" \
    --data-urlencode "split=train" \
    --data-urlencode "offset=$offset" \
    --data-urlencode "length=100" \
    --output "$destination" \
    "https://datasets-server.huggingface.co/rows"
' _ < "$metadata_queue"

metadata="$TEMP_DIR/metadata.jsonl"
/usr/bin/jq -c '.rows[]' "$TEMP_DIR/page-"*.json > "$metadata"
if [[ "$(/usr/bin/wc -l < "$metadata" | /usr/bin/tr -d ' ')" != "930" ]]; then
  echo "Expected 930 pinned MUSAN noise metadata rows." >&2
  exit 1
fi

download_queue="$TEMP_DIR/download-queue"
mkdir -p "$DATA_DIR"
while IFS=$'\t' read -r item_id subset_id config split row audio_path duration_ms \
  expected_size expected_sha; do
  row_json="$(mktemp "$TEMP_DIR/row.XXXXXX")"
  /usr/bin/jq -c --argjson row "$row" 'select(.row_idx == $row)' "$metadata" > "$row_json"
  expected_source="${subset_id#musan-}"

  /usr/bin/jq -e \
    --argjson row "$row" \
    --arg revision "$DATASET_REVISION" \
    --arg config "$config" \
    --arg split "$split" \
    --arg source "$expected_source" \
    '.row_idx == $row
      and .row.label == 2
      and .row.source == $source
      and (.row.audio[0].src
        | contains("/--/" + $revision + "/--/" + $config + "/" + $split + "/" + ($row | tostring) + "/audio/"))' \
    "$row_json" >/dev/null || {
      echo "Pinned MUSAN metadata changed for $item_id." >&2
      exit 1
    }

  destination="$DATA_DIR/$audio_path"
  mkdir -p "$(dirname "$destination")"
  audio_url="$(/usr/bin/jq -er '.row.audio[0].src' "$row_json")"
  /usr/bin/printf '%s\0%s\0%s\0%s\0%s\0' \
    "$audio_url" "$destination" "$duration_ms" "$expected_size" "$expected_sha" \
    >> "$download_queue"
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

/usr/bin/xargs -0 -n 5 -P 8 /bin/bash -c '
  set -euo pipefail
  url="$1"
  destination="$2"
  expected_duration_ms="$3"
  expected_size="$4"
  expected_sha="$5"

  verify_file() {
    local path="$1"
    local actual_duration_ms
    local actual_size
    local actual_sha
    actual_duration_ms="$(/usr/bin/afinfo "$path" | /usr/bin/awk '\''
      /estimated duration/ { printf "%d", ($3 * 1000) + 0.5; found = 1 }
      END { if (!found) exit 1 }
    '\'')"
    actual_size="$(/usr/bin/stat -f '\''%z'\'' "$path")"
    actual_sha="$(/usr/bin/shasum -a 256 "$path" | /usr/bin/awk '\''{print $1}'\'')"
    [[ "$actual_duration_ms" == "$expected_duration_ms" \
      && "$actual_size" == "$expected_size" \
      && "$actual_sha" == "$expected_sha" ]]
  }

  if [[ -f "$destination" ]] && verify_file "$destination"; then
    exit 0
  fi

  staged="$destination.download.$$"
  cleanup() { /usr/bin/find "$staged" -delete 2>/dev/null || true; }
  trap cleanup EXIT
  /usr/bin/curl \
    --http1.1 \
    --retry 12 \
    --retry-all-errors \
    --retry-delay 0 \
    --retry-max-time 600 \
    --fail \
    --silent \
    --show-error \
    --location \
    --output "$staged" \
    "$url"
  if ! verify_file "$staged"; then
    echo "Audio verification failed for $destination." >&2
    exit 1
  fi
  /bin/mv "$staged" "$destination"
' _ < "$download_queue"

echo "Verified MUSAN nightly no-speech corpus at $DATA_DIR"
