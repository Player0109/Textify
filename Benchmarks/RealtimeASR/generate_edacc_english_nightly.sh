#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/Corpus/edacc-english-nightly-v1.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/edacc-english-nightly-v1"
DATASET_ID="edinburghcstr/edacc"
DATASET_REVISION="d9ae7bd344f0562b766ec93ee5ce8f2f9568ce66"
VIEWER_BASE_URL="https://datasets-server.huggingface.co"
CONFIG="default"
SPLIT="test"
SELECTION_SEED="textify-edacc-english-nightly-v1"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  /usr/bin/find "$TEMP_DIR" -type f -delete 2>/dev/null || true
  /bin/rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

fetch_speaker_rows() {
  local speaker="$1"
  local destination="$2"
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
    --data-urlencode "dataset=$DATASET_ID" \
    --data-urlencode "config=$CONFIG" \
    --data-urlencode "split=$SPLIT" \
    --data-urlencode "where=\"speaker\" = '$speaker'" \
    --data-urlencode "offset=0" \
    --data-urlencode "length=100" \
    --output "$destination" \
    "$VIEWER_BASE_URL/filter"
}

statistics="$TEMP_DIR/statistics.json"
/usr/bin/curl \
  --retry 12 \
  --retry-all-errors \
  --retry-delay 0 \
  --retry-max-time 300 \
  --fail \
  --silent \
  --show-error \
  --location \
  --get \
  --data-urlencode "dataset=$DATASET_ID" \
  --data-urlencode "config=$CONFIG" \
  --data-urlencode "split=$SPLIT" \
  --output "$statistics" \
  "$VIEWER_BASE_URL/statistics"

speakers="$TEMP_DIR/speakers.txt"
/usr/bin/jq -r \
  '.statistics[]
    | select(.column_name == "speaker")
    | .column_statistics.frequencies
    | keys[]' \
  "$statistics" \
  | /usr/bin/sort > "$speakers"
speaker_count="$(/usr/bin/wc -l < "$speakers" | /usr/bin/tr -d ' ')"
if [[ "$speaker_count" != "60" ]]; then
  echo "Expected 60 EdAcc test speakers, received $speaker_count." >&2
  exit 1
fi

mkdir -p "$DATA_DIR/edacc-test"
items="$TEMP_DIR/items.jsonl"
while IFS= read -r speaker; do
  echo "Selecting EdAcc speaker $speaker"
  page="$TEMP_DIR/$speaker.json"
  fetch_speaker_rows "$speaker" "$page"

  candidates="$TEMP_DIR/$speaker-candidates.tsv"
  while IFS= read -r row; do
    rank="$(
      /usr/bin/printf '%s' "$SELECTION_SEED:$row" \
        | /usr/bin/shasum -a 256 \
        | /usr/bin/awk '{print $1}'
    )"
    /usr/bin/printf '%s\t%s\n' "$rank" "$row" >> "$candidates"
  done < <(
    /usr/bin/jq -r \
      '.rows[]
        | select(.row.text != "IGNORE_TIME_SEGMENT_IN_SCORING")
        | select(.row.text | contains("PARTICIPANT NUMBER") | not)
        | select(.row.text | split(" ") | length >= 3)
        | .row_idx' \
      "$page"
  )

  selected_for_speaker=0
  while IFS=$'\t' read -r rank row; do
    entry="$TEMP_DIR/$speaker-entry-$row.json"
    /usr/bin/jq -c --argjson row "$row" '.rows[] | select(.row_idx == $row)' "$page" \
      > "$entry"
    audio_url="$(/usr/bin/jq -er '.row.audio[0].src' "$entry")"
    /usr/bin/jq -e \
      --arg revision "$DATASET_REVISION" \
      --arg config "$CONFIG" \
      --arg split "$SPLIT" \
      --argjson row "$row" \
      '.row.audio[0].src
        | contains("/--/" + $revision + "/--/" + $config + "/" + $split + "/" + ($row | tostring) + "/audio/")' \
      "$entry" >/dev/null || {
        echo "EdAcc cached audio URL is not pinned to row $row." >&2
        exit 1
      }

    staged="$TEMP_DIR/audio-$row.wav"
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
      --output "$staged" \
      "$audio_url"
    duration_ms="$(/usr/bin/afinfo "$staged" | /usr/bin/awk '
      /estimated duration/ { printf "%d", ($3 * 1000) + 0.5; found = 1 }
      END { if (!found) exit 1 }
    ')"
    if (( duration_ms < 1000 || duration_ms > 60000 )); then
      /usr/bin/find "$staged" -delete
      continue
    fi

    if (( duration_ms < 3000 )); then
      duration_bucket="1-3"
    elif (( duration_ms < 10000 )); then
      duration_bucket="3-10"
    elif (( duration_ms < 20000 )); then
      duration_bucket="10-20"
    elif (( duration_ms <= 29000 )); then
      duration_bucket="20-29"
    elif (( duration_ms < 45000 )); then
      duration_bucket="29-45"
    else
      duration_bucket="45-60"
    fi

    size_bytes="$(/usr/bin/stat -f '%z' "$staged")"
    sha256="$(/usr/bin/shasum -a 256 "$staged" | /usr/bin/awk '{print $1}')"
    item_id="$(/usr/bin/printf 'edacc-test-%05d' "$row")"
    destination="$DATA_DIR/edacc-test/$row.wav"
    /bin/mv "$staged" "$destination"

    /usr/bin/jq -cn \
      --arg id "$item_id" \
      --argjson row "$row" \
      --arg audio "edacc-test/$row.wav" \
      --arg reference "$(/usr/bin/jq -r '.row.text' "$entry")" \
      --argjson duration_ms "$duration_ms" \
      --arg duration_bucket "$duration_bucket" \
      --argjson size_bytes "$size_bytes" \
      --arg sha256 "$sha256" \
      --arg speaker_id "$speaker" \
      --arg accent "$(/usr/bin/jq -r '.row.accent' "$entry")" \
      --arg raw_accent "$(/usr/bin/jq -r '.row.raw_accent' "$entry")" \
      --arg gender "$(/usr/bin/jq -r '.row.gender' "$entry")" \
      --arg first_language "$(/usr/bin/jq -r '.row.l1' "$entry")" \
      '{
        id: $id,
        subsetID: "edacc-test",
        row: $row,
        audio: $audio,
        reference: $reference,
        durationMs: $duration_ms,
        durationBucket: $duration_bucket,
        sizeBytes: $size_bytes,
        sha256: $sha256,
        speakerID: $speaker_id,
        slices: ({
          accent: $accent,
          rawAccent: $raw_accent,
          gender: $gender,
          firstLanguage: $first_language
        } | with_entries(select(.value != "")))
      }' >> "$items"

    selected_for_speaker=$((selected_for_speaker + 1))
    if (( selected_for_speaker == 4 )); then
      break
    fi
  done < <(/usr/bin/sort -t $'\t' -k1,1 "$candidates")

  if (( selected_for_speaker != 4 )); then
    echo "Could not select four compatible EdAcc clips for $speaker." >&2
    exit 1
  fi
done < "$speakers"

item_count="$(/usr/bin/wc -l < "$items" | /usr/bin/tr -d ' ')"
if [[ "$item_count" != "240" ]]; then
  echo "Expected 240 EdAcc nightly items, generated $item_count." >&2
  exit 1
fi

generated="$TEMP_DIR/edacc-english-nightly-v1.json"
/usr/bin/jq -s \
  --arg dataset_id "$DATASET_ID" \
  --arg dataset_revision "$DATASET_REVISION" \
  --arg viewer_base_url "$VIEWER_BASE_URL" \
  --arg selection_seed "$SELECTION_SEED" \
  'sort_by(.row)
    | {
      schemaVersion: 2,
      id: "edacc-english-nightly-v1",
      name: "EdAcc English nightly accent evaluation",
      language: "en",
      dataset: {
        id: $dataset_id,
        revision: $dataset_revision,
        viewerBaseURL: $viewer_base_url
      },
      selection: {
        seed: $selection_seed,
        rule: "four seeded 1-60 second conversational clips per test speaker from the first 100 speaker rows"
      },
      durationLanes: [
        {id: "short-10", maxAudioSeconds: 10},
        {id: "universal", maxAudioSeconds: 29},
        {id: "full-60", maxAudioSeconds: 60}
      ],
      requiredDurationBuckets: ["1-3", "3-10"],
      subsets: [
        {
          id: "edacc-test",
          config: "default",
          split: "test",
          role: "public-quality",
          speechOrigin: "human-natural",
          license: "CC-BY-SA-4.0",
          sourceURL: "https://huggingface.co/datasets/edinburghcstr/edacc"
        }
      ],
      items: .
    }' \
  "$items" > "$generated"

/bin/mv "$generated" "$OUTPUT"
echo "Generated 240-item EdAcc nightly manifest at $OUTPUT"
