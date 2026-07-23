#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/Corpus/berst-english-nightly-v1.json"
DATASET_ID="Rosie-Lab/BERSt"
DATASET_REVISION="fed35c477427cff44206464b7f85e68d1fc99062"
VIEWER_BASE_URL="https://datasets-server.huggingface.co"
CONFIG="default"
SPLIT="test"
SELECTION_SEED="textify-berst-english-nightly-v1"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  /usr/bin/find "$TEMP_DIR" -type f -delete 2>/dev/null || true
  /bin/rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

fetch_rows() {
  local offset="$1"
  local length="$2"
  local destination="$3"
  echo "Fetching BERSt rows $offset-$((offset + length - 1))"
  /usr/bin/curl \
    --http1.1 \
    --retry 5 \
    --retry-all-errors \
    --retry-delay 2 \
    --fail \
    --silent \
    --show-error \
    --location \
    --get \
    --data-urlencode "dataset=$DATASET_ID" \
    --data-urlencode "config=$CONFIG" \
    --data-urlencode "split=$SPLIT" \
    --data-urlencode "offset=$offset" \
    --data-urlencode "length=$length" \
    --output "$destination" \
    "$VIEWER_BASE_URL/rows"
}

metadata="$TEMP_DIR/metadata.jsonl"
offset=0
while (( offset <= 500 )); do
  page="$TEMP_DIR/page-$offset.json"
  fetch_rows "$offset" 50 "$page"
  /usr/bin/jq -c '.rows[]' "$page" >> "$metadata"
  offset=$((offset + 50))
done

row_count="$(/usr/bin/wc -l < "$metadata" | /usr/bin/tr -d ' ')"
if [[ "$row_count" != "532" ]]; then
  echo "Expected 532 BERSt test rows, received $row_count." >&2
  exit 1
fi

candidates="$TEMP_DIR/candidates.tsv"
while IFS=$'\t' read -r cell row speaker; do
  rank="$(
    /usr/bin/printf '%s' "$SELECTION_SEED:$row" \
      | /usr/bin/shasum -a 256 \
      | /usr/bin/awk '{print $1}'
  )"
  /usr/bin/printf '%s\t%s\t%s\t%s\n' "$cell" "$rank" "$row" "$speaker" \
    >> "$candidates"
done < <(
  /usr/bin/jq -r \
    'select(.row.shout_level == "shout" or .row.shout_level == "no-shout")
      | [([.row.phone_position, .row.shout_level] | @json | @base64),
         .row_idx, .row.user_id]
      | @tsv' \
    "$metadata"
)

selected="$TEMP_DIR/selected.txt"
/usr/bin/sort -t $'\t' -k1,1 -k2,2 "$candidates" \
  | /usr/bin/awk -F $'\t' '
      {
        speaker_key = $1 SUBSEP $4
        if (cell_count[$1] < 4 && !seen_speaker[speaker_key]) {
          print $3
          cell_count[$1]++
          seen_speaker[speaker_key] = 1
        }
      }
    ' \
  | /usr/bin/sort -n > "$selected"

selected_count="$(/usr/bin/wc -l < "$selected" | /usr/bin/tr -d ' ')"
if [[ "$selected_count" != "152" ]]; then
  echo "Expected 152 stratified BERSt rows, selected $selected_count." >&2
  exit 1
fi

items="$TEMP_DIR/items.jsonl"
while IFS= read -r row; do
  entry="$TEMP_DIR/entry-$row.json"
  /usr/bin/jq -c --argjson row "$row" 'select(.row_idx == $row)' "$metadata" > "$entry"
  audio_url="$(/usr/bin/jq -er '.row.audio[0].src' "$entry")"
  staged="$TEMP_DIR/audio-$row.wav"
  echo "Downloading BERSt row $row"
  /usr/bin/curl \
    --http1.1 \
    --retry 5 \
    --retry-all-errors \
    --retry-delay 2 \
    --fail \
    --silent \
    --show-error \
    --location \
    --output "$staged" \
    "$audio_url"

  duration_ms="$(/usr/bin/afinfo "$staged" | /usr/bin/awk '
    /estimated duration/ { printf "%d", ($3 * 1000) + 0.5; found = 1 }
    END { if (!found) exit 1 }
  ')"
  if (( duration_ms < 1000 || duration_ms > 10000 )); then
    echo "BERSt row $row is outside the 1-10 second nightly lane." >&2
    exit 1
  fi
  if (( duration_ms < 3000 )); then
    duration_bucket="1-3"
  else
    duration_bucket="3-10"
  fi
  size_bytes="$(/usr/bin/stat -f '%z' "$staged")"
  sha256="$(/usr/bin/shasum -a 256 "$staged" | /usr/bin/awk '{print $1}')"
  item_id="$(/usr/bin/printf 'berst-test-%06d' "$row")"

  /usr/bin/jq -cn \
    --arg id "$item_id" \
    --argjson row "$row" \
    --arg audio "berst-test/$row.wav" \
    --arg reference "$(/usr/bin/jq -r '.row.script' "$entry")" \
    --argjson duration_ms "$duration_ms" \
    --arg duration_bucket "$duration_bucket" \
    --argjson size_bytes "$size_bytes" \
    --arg sha256 "$sha256" \
    --arg speaker_id "$(/usr/bin/jq -r '.row.user_id' "$entry")" \
    --arg phone_position "$(/usr/bin/jq -r '.row.phone_position' "$entry")" \
    --arg shout_level "$(/usr/bin/jq -r '.row.shout_level' "$entry")" \
    --arg affect "$(/usr/bin/jq -r '.row.affect' "$entry")" \
    --arg first_language "$(/usr/bin/jq -r '.row.first_language' "$entry")" \
    --arg phone_model "$(/usr/bin/jq -r '.row.phone_model' "$entry")" \
    '{
      id: $id,
      subsetID: "berst-test",
      row: $row,
      audio: $audio,
      reference: $reference,
      durationMs: $duration_ms,
      durationBucket: $duration_bucket,
      sizeBytes: $size_bytes,
      sha256: $sha256,
      speakerID: $speaker_id,
      slices: {
        phonePosition: $phone_position,
        shoutLevel: $shout_level,
        affect: $affect,
        firstLanguage: $first_language,
        phoneModel: $phone_model
      }
    }' >> "$items"
done < "$selected"

generated="$TEMP_DIR/berst-english-nightly-v1.json"
/usr/bin/jq -s \
  --arg dataset_id "$DATASET_ID" \
  --arg dataset_revision "$DATASET_REVISION" \
  --arg viewer_base_url "$VIEWER_BASE_URL" \
  --arg selection_seed "$SELECTION_SEED" \
  '{
    schemaVersion: 2,
    id: "berst-english-nightly-v1",
    name: "BERSt English nightly stress evaluation",
    language: "en",
    dataset: {
      id: $dataset_id,
      revision: $dataset_revision,
      viewerBaseURL: $viewer_base_url
    },
    selection: {
      seed: $selection_seed,
      rule: "four distinct speakers per phonePosition x shoutLevel cell; shout and no-shout only"
    },
    durationLanes: [
      {id: "short-10", maxAudioSeconds: 10},
      {id: "universal", maxAudioSeconds: 29},
      {id: "full-60", maxAudioSeconds: 60}
    ],
    requiredDurationBuckets: ["1-3", "3-10"],
    subsets: [
      {
        id: "berst-test",
        config: "default",
        split: "test",
        role: "stress",
        speechOrigin: "human-read",
        license: "CC-BY-4.0",
        sourceURL: "https://huggingface.co/datasets/Rosie-Lab/BERSt"
      }
    ],
    items: .
  }' "$items" > "$generated"

/bin/mv "$generated" "$OUTPUT"
echo "Generated 152-item BERSt nightly manifest at $OUTPUT"
