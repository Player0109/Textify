#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/Corpus/open-asr-english-nightly-v1.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/open-asr-english-nightly-v1"
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
while IFS=$'\t' read -r subset_id config split; do
  while IFS= read -r offset; do
    destination="$TEMP_DIR/$subset_id-page-$offset.json"
    /usr/bin/printf '%s\0%s\0%s\0%s\0' \
      "$config" "$split" "$offset" "$destination" >> "$metadata_queue"
  done < <(
    /usr/bin/jq -r \
      --arg subset_id "$subset_id" \
      '[.items[] | select(.subsetID == $subset_id) | ((.row / 100 | floor) * 100)]
        | unique[]' \
      "$CORPUS"
  )
done < <(
  /usr/bin/jq -r '.subsets[] | [.id, .config, .split] | @tsv' "$CORPUS"
)

/usr/bin/xargs -0 -n 4 -P 2 /bin/bash -c '
  set -euo pipefail
  config="$1"
  split="$2"
  offset="$3"
  destination="$4"
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
    --data-urlencode "dataset=hf-audio/open-asr-leaderboard" \
    --data-urlencode "config=$config" \
    --data-urlencode "split=$split" \
    --data-urlencode "offset=$offset" \
    --data-urlencode "length=100" \
    --output "$destination" \
    "https://datasets-server.huggingface.co/rows"
' _ < "$metadata_queue"

metadata="$TEMP_DIR/metadata.jsonl"
while IFS=$'\t' read -r subset_id config split; do
  /usr/bin/jq -c \
    --arg subset_id "$subset_id" \
    --arg config "$config" \
    --arg split "$split" \
    '.rows[] + {subsetID: $subset_id, config: $config, split: $split}' \
    "$TEMP_DIR/$subset_id-page-"*.json >> "$metadata"
done < <(
  /usr/bin/jq -r '.subsets[] | [.id, .config, .split] | @tsv' "$CORPUS"
)

download_queue="$TEMP_DIR/download-queue"
mkdir -p "$DATA_DIR"
while IFS=$'\t' read -r item_id subset_id config split row audio_path reference \
  duration_ms expected_size expected_sha; do
  row_json="$(mktemp "$TEMP_DIR/row.XXXXXX")"
  /usr/bin/jq -c \
    --arg subset_id "$subset_id" \
    --argjson row "$row" \
    'select(.subsetID == $subset_id and .row_idx == $row)' \
    "$metadata" > "$row_json"
  if [[ ! -s "$row_json" ]]; then
    echo "Pinned Open ASR row is missing for $item_id." >&2
    exit 1
  fi

  /usr/bin/jq -e \
    --argjson row "$row" \
    --arg revision "$DATASET_REVISION" \
    --arg config "$config" \
    --arg split "$split" \
    --arg reference "$reference" \
    --argjson duration_ms "$duration_ms" \
    '.row_idx == $row
      and .row.text == $reference
      and ((.row.audio_length_s * 1000 | floor) >= ($duration_ms - 2))
      and ((.row.audio_length_s * 1000 | floor) <= ($duration_ms + 2))
      and (.row.audio[0].src
        | contains("/--/" + $revision + "/--/" + $config + "/" + $split + "/" + ($row | tostring) + "/audio/"))' \
    "$row_json" >/dev/null || {
      echo "Pinned Open ASR metadata changed for $item_id." >&2
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
         $item.reference, $item.durationMs, $item.sizeBytes, $item.sha256]
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

echo "Verified Open ASR English nightly corpus at $DATA_DIR"
