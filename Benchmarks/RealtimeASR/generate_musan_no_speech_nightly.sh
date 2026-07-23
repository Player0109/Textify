#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/Corpus/musan-no-speech-nightly-v1.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/musan-no-speech-nightly-v1"
TEMP_DIR="$(mktemp -d)"

DATASET_ID="corypaik/musan"
DATASET_REVISION="76f9882cfa4475efe11508ac9aa32722f84ca5b7"
VIEWER_BASE_URL="https://datasets-server.huggingface.co"
SELECTION_SEED="textify-musan-no-speech-nightly-v1"
METADATA_CACHE_DIR="$DATA_DIR/.metadata"

cleanup() {
  /usr/bin/find "$TEMP_DIR" -type f -delete 2>/dev/null || true
  /usr/bin/find "$TEMP_DIR" -depth -type d -empty -delete 2>/dev/null || true
}
trap cleanup EXIT

metadata_queue="$TEMP_DIR/metadata-queue"
mkdir -p "$METADATA_CACHE_DIR"
offset=0
while (( offset < 930 )); do
  destination="$METADATA_CACHE_DIR/page-$offset.json"
  if [[ ! -s "$destination" ]]; then
    /usr/bin/printf '%s\0%s\0' "$offset" "$destination" >> "$metadata_queue"
  fi
  offset=$((offset + 100))
done

if [[ -s "$metadata_queue" ]]; then
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
fi

metadata="$TEMP_DIR/metadata.json"
/usr/bin/jq -s \
  --arg revision "$DATASET_REVISION" \
  '[.[] | .rows[]
    | select(.row.label == 2)
    | select(.row.source == "free-sound" or .row.source == "sound-bible")
    | select(. as $entry
        | $entry.row.audio[0].src
        | contains("/--/" + $revision + "/--/noise/train/" + ($entry.row_idx | tostring) + "/audio/"))]
    | unique_by(.row_idx)' \
  "$METADATA_CACHE_DIR/page-"*.json > "$metadata"
/usr/bin/jq -e \
  'length == 930
    and ([.[] | select(.row.source == "free-sound")] | length == 843)
    and ([.[] | select(.row.source == "sound-bible")] | length == 87)' \
  "$metadata" >/dev/null || {
    echo "Pinned MUSAN noise metadata changed." >&2
    exit 1
  }

mkdir -p "$TEMP_DIR/audio"
candidates="$TEMP_DIR/candidates.json"
free_sound_salt="$(
  /usr/bin/printf '%s' "$SELECTION_SEED:free-sound" \
    | /usr/bin/cksum \
    | /usr/bin/awk '{print $1}'
)"
sound_bible_salt="$(
  /usr/bin/printf '%s' "$SELECTION_SEED:sound-bible" \
    | /usr/bin/cksum \
    | /usr/bin/awk '{print $1}'
)"
/usr/bin/jq \
  --argjson free_sound_salt "$free_sound_salt" \
  --argjson sound_bible_salt "$sound_bible_salt" \
  'map(. + {
    rank: (((.row_idx * 1103515245)
      + (if .row.source == "free-sound" then $free_sound_salt else $sound_bible_salt end))
      % 2147483647)
  })
  | sort_by(.rank) as $all
  | (([$all[] | select(.row.source == "free-sound")][0:300])
    + ([$all[] | select(.row.source == "sound-bible")]))' \
  "$metadata" > "$candidates"

download_queue="$TEMP_DIR/download-queue"
/usr/bin/jq -j \
  --arg temp_dir "$TEMP_DIR" \
  '.[]
    | .row.audio[0].src, "\u0000",
      ($temp_dir + "/audio/" + (.row_idx | tostring) + ".wav"), "\u0000"' \
  "$candidates" > "$download_queue"

/usr/bin/xargs -0 -n 2 -P 8 /bin/bash -c '
  set -euo pipefail
  url="$1"
  destination="$2"
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
    --output "$destination" \
    "$url"
' _ < "$download_queue"

compatible="$TEMP_DIR/compatible.jsonl"
while IFS= read -r entry; do
  row="$(/usr/bin/jq -er '.row_idx' <<< "$entry")"
  audio="$TEMP_DIR/audio/$row.wav"
  duration_ms="$(/usr/bin/afinfo "$audio" | /usr/bin/awk '
    /estimated duration/ { printf "%d", ($3 * 1000) + 0.5; found = 1 }
    END { if (!found) exit 1 }
  ')"
  if (( duration_ms < 1000 || duration_ms > 29000 )); then
    continue
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
  /usr/bin/jq -c \
    --argjson duration_ms "$duration_ms" \
    --arg duration_bucket "$duration_bucket" \
    --arg staged_audio "$audio" \
    '. + {
      durationMs: $duration_ms,
      durationBucket: $duration_bucket,
      stagedAudio: $staged_audio
    }' <<< "$entry" >> "$compatible"
done < <(/usr/bin/jq -c '.[]' "$candidates")

selection="$TEMP_DIR/selection.json"
/usr/bin/jq -s \
  'sort_by(.rank) as $all
  | def select_source($source; $target; $caps):
      [$all[] | select(.row.source == $source)] as $source_items
      | (["1-3", "3-10", "10-20", "20-29"]
          | map(. as $bucket
              | [$source_items[] | select(.durationBucket == $bucket)][0:$caps[$bucket]])
          | add) as $balanced
      | ($balanced | map(.row_idx)) as $selected_rows
      | ($balanced + [
          $source_items[]
          | select(.row_idx as $row | ($selected_rows | index($row) | not))
        ])[0:$target];
    (select_source("free-sound"; 150;
      {"1-3": 38, "3-10": 38, "10-20": 37, "20-29": 37}))
    + (select_source("sound-bible"; 50;
      {"1-3": 13, "3-10": 13, "10-20": 12, "20-29": 12}))' \
  "$compatible" > "$selection"
/usr/bin/jq -e \
  'length == 200
    and ([.[].row_idx] | unique | length == 200)
    and ([.[] | select(.row.source == "free-sound")] | length == 150)
    and ([.[] | select(.row.source == "sound-bible")] | length == 50)
    and ([.[] | select(.row.source == "free-sound") | .durationBucket] | unique | length == 4)
    and ([.[] | select(.row.source == "sound-bible") | .durationBucket] | unique | length == 4)' \
  "$selection" >/dev/null || {
    echo "Could not select the 150/50 source-balanced MUSAN nightly controls." >&2
    exit 1
  }

mkdir -p "$DATA_DIR/musan-free-sound" "$DATA_DIR/musan-sound-bible"
items="$TEMP_DIR/items.jsonl"
while IFS= read -r entry; do
  row="$(/usr/bin/jq -er '.row_idx' <<< "$entry")"
  source="$(/usr/bin/jq -er '.row.source' <<< "$entry")"
  subset_id="musan-$source"
  relative_audio="$subset_id/$row.wav"
  destination="$DATA_DIR/$relative_audio"
  /bin/mv "$(/usr/bin/jq -er '.stagedAudio' <<< "$entry")" "$destination"

  /usr/bin/jq -cn \
    --arg id "musan-$source-$(/usr/bin/printf '%04d' "$row")" \
    --arg subset_id "$subset_id" \
    --argjson row "$row" \
    --arg audio "$relative_audio" \
    --argjson duration_ms "$(/usr/bin/jq -er '.durationMs' <<< "$entry")" \
    --arg duration_bucket "$(/usr/bin/jq -er '.durationBucket' <<< "$entry")" \
    --argjson size_bytes "$(/usr/bin/stat -f '%z' "$destination")" \
    --arg sha256 "$(/usr/bin/shasum -a 256 "$destination" | /usr/bin/awk '{print $1}')" \
    '{
      id: $id,
      subsetID: $subset_id,
      row: $row,
      audio: $audio,
      reference: "",
      durationMs: $duration_ms,
      durationBucket: $duration_bucket,
      sizeBytes: $size_bytes,
      sha256: $sha256
    }' >> "$items"
done < <(/usr/bin/jq -c '.[]' "$selection")

generated="$TEMP_DIR/musan-no-speech-nightly-v1.json"
/usr/bin/jq -s \
  --arg dataset_id "$DATASET_ID" \
  --arg dataset_revision "$DATASET_REVISION" \
  --arg viewer_base_url "$VIEWER_BASE_URL" \
  --arg selection_seed "$SELECTION_SEED" \
  'sort_by(.subsetID, .row)
    | {
      schemaVersion: 2,
      id: "musan-no-speech-nightly-v1",
      name: "MUSAN English nightly no-speech controls",
      language: "en",
      dataset: {
        id: $dataset_id,
        revision: $dataset_revision,
        viewerBaseURL: $viewer_base_url
      },
      selection: {
        seed: $selection_seed,
        rule: "150 free-sound and 50 sound-bible public-domain noise clips, decoded duration 1-29 seconds, duration-bucket balanced then deterministic deficit fill"
      },
      durationLanes: [
        {id: "short-10", maxAudioSeconds: 10},
        {id: "universal", maxAudioSeconds: 29},
        {id: "full-60", maxAudioSeconds: 60}
      ],
      requiredDurationBuckets: ["1-3", "3-10", "10-20", "20-29"],
      subsets: [
        {
          id: "musan-free-sound",
          config: "noise",
          split: "train",
          role: "negative-control",
          speechOrigin: "no-speech",
          license: "Public Domain",
          sourceURL: "https://www.openslr.org/17/"
        },
        {
          id: "musan-sound-bible",
          config: "noise",
          split: "train",
          role: "negative-control",
          speechOrigin: "no-speech",
          license: "Public Domain",
          sourceURL: "https://www.openslr.org/17/"
        }
      ],
      items: .
    }' \
  "$items" > "$generated"

/bin/mv "$generated" "$OUTPUT"
/usr/bin/find "$METADATA_CACHE_DIR" -type f -delete
/bin/rmdir "$METADATA_CACHE_DIR"
echo "Generated 200-item MUSAN nightly manifest at $OUTPUT"
