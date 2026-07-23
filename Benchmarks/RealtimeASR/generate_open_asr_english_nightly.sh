#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PR_CORPUS="$SCRIPT_DIR/Corpus/open-asr-english-pr-v1.json"
OUTPUT="$SCRIPT_DIR/Corpus/open-asr-english-nightly-v1.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/open-asr-english-nightly-v1"
TEMP_DIR="$(mktemp -d)"

DATASET_ID="hf-audio/open-asr-leaderboard"
DATASET_REVISION="b6bdcd0beb34f8975dc659796176d88f43aff502"
VIEWER_BASE_URL="https://datasets-server.huggingface.co"
SELECTION_SEED="textify-open-asr-english-nightly-v1"
WINDOW_LENGTH=100
METADATA_CACHE_DIR="$DATA_DIR/.metadata"

cleanup() {
  /usr/bin/find "$TEMP_DIR" -type f -delete 2>/dev/null || true
  /bin/rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

subset_extension() {
  case "$1" in
    librispeech-clean|librispeech-other|common-voice) echo flac ;;
    ami|gigaspeech|voxpopuli) echo wav ;;
    *) echo "Unknown Open ASR subset: $1" >&2; return 1 ;;
  esac
}

metadata_queue="$TEMP_DIR/metadata-queue"
mkdir -p "$METADATA_CACHE_DIR"
while IFS=$'\t' read -r subset_id config split; do
  while IFS= read -r anchor_row; do
    offset=$((anchor_row / WINDOW_LENGTH * WINDOW_LENGTH))
    destination="$METADATA_CACHE_DIR/$subset_id-anchor-page-$offset.json"
    marker="$TEMP_DIR/$subset_id-anchor-page-$offset.queued"
    if [[ ! -e "$marker" ]]; then
      /usr/bin/touch "$marker"
      if [[ ! -s "$destination" ]]; then
        /usr/bin/printf '%s\0%s\0%s\0%s\0%s\0' \
          "$config" "$split" "$offset" "$WINDOW_LENGTH" "$destination" \
          >> "$metadata_queue"
      fi
    fi
  done < <(
    /usr/bin/jq -r --arg subset_id "$subset_id" \
      '.items[] | select(.subsetID == $subset_id) | .row' \
      "$PR_CORPUS"
  )
done < <(
  /usr/bin/jq -r '.subsets[] | [.id, .config, .split] | @tsv' "$PR_CORPUS"
)

if [[ -s "$metadata_queue" ]]; then
  /usr/bin/xargs -0 -n 5 -P 2 /bin/bash -c '
  set -euo pipefail
  config="$1"
  split="$2"
  offset="$3"
  length="$4"
  destination="$5"
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
    --data-urlencode "length=$length" \
    --output "$destination" \
    "https://datasets-server.huggingface.co/rows"
' _ < "$metadata_queue"
fi

selected_items="$TEMP_DIR/selected.jsonl"
while IFS=$'\t' read -r subset_id config split; do
  candidates="$TEMP_DIR/$subset_id-candidates.json"
  /usr/bin/jq -sc \
    --arg revision "$DATASET_REVISION" \
    --arg config "$config" \
    --arg split "$split" \
    '[.[]
      | .rows[]
      | select(.row.audio_length_s >= 1 and .row.audio_length_s <= 29)
      | select(.row.text | type == "string" and (split(" ") | length >= 2))
      | select(. as $entry
          | $entry.row.audio[0].src
          | contains("/--/" + $revision + "/--/" + $config + "/" + $split + "/" + ($entry.row_idx | tostring) + "/audio/"))]
      | unique_by(.row_idx)' \
    "$METADATA_CACHE_DIR/$subset_id-"*.json > "$candidates"

  salt="$(
    /usr/bin/printf '%s' "$SELECTION_SEED:$subset_id" \
      | /usr/bin/cksum \
      | /usr/bin/awk '{print $1}'
  )"
  selection="$TEMP_DIR/$subset_id-selection.json"
  /usr/bin/jq \
    --arg subset_id "$subset_id" \
    --argjson salt "$salt" \
    'def bucket:
      if . < 3 then "1-3"
      elif . < 10 then "3-10"
      elif . < 20 then "10-20"
      else "20-29"
      end;
    map(. + {
      subsetID: $subset_id,
      durationBucket: (.row.audio_length_s | bucket),
      rank: (((.row_idx * 1103515245) + $salt) % 2147483647)
    })
    | sort_by(.rank) as $all
    | (["1-3", "3-10", "10-20", "20-29"]
        | map(. as $bucket | [$all[] | select(.durationBucket == $bucket)][0:15])
        | add) as $balanced
    | ($balanced | map(.row_idx)) as $selected_rows
    | ($balanced + [
        $all[]
        | select(.row_idx as $row | ($selected_rows | index($row) | not))
      ])[0:60]' \
    "$candidates" > "$selection"

  /usr/bin/jq -e \
    'length == 60
      and ([.[].row_idx] | unique | length == 60)
      and ([.[].durationBucket] | unique | length == 4)' \
    "$selection" >/dev/null || {
      echo "Could not select 60 duration-covered clips for $subset_id." >&2
      exit 1
    }
  /usr/bin/jq -c '.[]' "$selection" >> "$selected_items"
done < <(
  /usr/bin/jq -r '.subsets[] | [.id, .config, .split] | @tsv' "$PR_CORPUS"
)

if [[ "$(/usr/bin/wc -l < "$selected_items" | /usr/bin/tr -d ' ')" != "360" ]]; then
  echo "Expected 360 selected Open ASR nightly clips." >&2
  exit 1
fi

mkdir -p "$DATA_DIR"
download_queue="$TEMP_DIR/download-queue"
while IFS=$'\t' read -r subset_id; do
  mkdir -p "$DATA_DIR/$subset_id"
  extension="$(subset_extension "$subset_id")"
  /usr/bin/jq -j \
    --arg subset_id "$subset_id" \
    --arg data_dir "$DATA_DIR" \
    --arg extension "$extension" \
    'select(.subsetID == $subset_id)
      | .row.audio[0].src, "\u0000",
        ($data_dir + "/" + $subset_id + "/" + (.row_idx | tostring) + "." + $extension), "\u0000"' \
    "$selected_items" >> "$download_queue"
done < <(/usr/bin/jq -r '.subsets[] | [.id] | @tsv' "$PR_CORPUS")

/usr/bin/xargs -0 -n 2 -P 8 /bin/bash -c '
  set -euo pipefail
  url="$1"
  destination="$2"
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
  /bin/mv "$staged" "$destination"
' _ < "$download_queue"

items="$TEMP_DIR/items.jsonl"
while IFS= read -r entry; do
  subset_id="$(/usr/bin/jq -er '.subsetID' <<< "$entry")"
  row="$(/usr/bin/jq -er '.row_idx' <<< "$entry")"
  extension="$(subset_extension "$subset_id")"
  relative_audio="$subset_id/$row.$extension"
  audio="$DATA_DIR/$relative_audio"
  metadata_duration_ms="$(/usr/bin/jq -er '.row.audio_length_s * 1000 | floor' <<< "$entry")"
  duration_ms="$(/usr/bin/afinfo "$audio" | /usr/bin/awk '
    /estimated duration/ { printf "%d", ($3 * 1000) + 0.5; found = 1 }
    END { if (!found) exit 1 }
  ')"
  if (( duration_ms < 1000 || duration_ms > 29000 \
    || duration_ms < metadata_duration_ms - 2 || duration_ms > metadata_duration_ms + 2 )); then
    echo "Open ASR duration verification failed for $subset_id row $row." >&2
    exit 1
  fi

  if (( duration_ms < 3000 )); then
    duration_bucket="1-3"
  elif (( duration_ms < 10000 )); then
    duration_bucket="3-10"
  elif (( duration_ms < 20000 )); then
    duration_bucket="10-20"
  else
    duration_bucket="20-29"
  fi

  /usr/bin/jq -cn \
    --arg id "open-asr-$subset_id-$(/usr/bin/printf '%05d' "$row")" \
    --arg subset_id "$subset_id" \
    --argjson row "$row" \
    --arg audio "$relative_audio" \
    --arg reference "$(/usr/bin/jq -r '.row.text' <<< "$entry")" \
    --argjson duration_ms "$duration_ms" \
    --arg duration_bucket "$duration_bucket" \
    --argjson size_bytes "$(/usr/bin/stat -f '%z' "$audio")" \
    --arg sha256 "$(/usr/bin/shasum -a 256 "$audio" | /usr/bin/awk '{print $1}')" \
    '{
      id: $id,
      subsetID: $subset_id,
      row: $row,
      audio: $audio,
      reference: $reference,
      durationMs: $duration_ms,
      durationBucket: $duration_bucket,
      sizeBytes: $size_bytes,
      sha256: $sha256
    }' >> "$items"
done < "$selected_items"

generated="$TEMP_DIR/open-asr-english-nightly-v1.json"
/usr/bin/jq -s \
  --slurpfile pr "$PR_CORPUS" \
  --arg dataset_id "$DATASET_ID" \
  --arg dataset_revision "$DATASET_REVISION" \
  --arg viewer_base_url "$VIEWER_BASE_URL" \
  --arg selection_seed "$SELECTION_SEED" \
  'sort_by(.subsetID, .row)
    | {
      schemaVersion: 2,
      id: "open-asr-english-nightly-v1",
      name: "Open ASR English nightly public quality anchor",
      language: "en",
      dataset: {
        id: $dataset_id,
        revision: $dataset_revision,
        viewerBaseURL: $viewer_base_url
      },
      selection: {
        seed: $selection_seed,
        rule: "60 deterministic clips per corpus from the 100-row pages surrounding its four reviewed PR anchors; up to 15 per 1-3, 3-10, 10-20, and 20-29 second bucket, then seeded deficit fill"
      },
      durationLanes: [
        {id: "short-10", maxAudioSeconds: 10},
        {id: "universal", maxAudioSeconds: 29},
        {id: "full-60", maxAudioSeconds: 60}
      ],
      requiredDurationBuckets: ["1-3", "3-10", "10-20", "20-29"],
      subsets: $pr[0].subsets,
      items: .
    }' \
  "$items" > "$generated"

/bin/mv "$generated" "$OUTPUT"
/usr/bin/find "$METADATA_CACHE_DIR" -type f -delete
/bin/rmdir "$METADATA_CACHE_DIR"
echo "Generated 360-item Open ASR English nightly manifest at $OUTPUT"
