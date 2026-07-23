#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/Corpus/edacc-english-nightly-v1.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/edacc-english-nightly-v1"
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
    --data-urlencode "config=default" \
    --data-urlencode "split=test" \
    --data-urlencode "where=\"speaker\" = '$speaker'" \
    --data-urlencode "offset=0" \
    --data-urlencode "length=100" \
    --output "$destination" \
    "$VIEWER_BASE_URL/filter"
}

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

metadata="$TEMP_DIR/metadata.jsonl"
while IFS= read -r speaker; do
  page="$TEMP_DIR/$speaker.json"
  fetch_speaker_rows "$speaker" "$page"
  /usr/bin/jq -c '.rows[]' "$page" >> "$metadata"
done < <(/usr/bin/jq -r '[.items[].speakerID] | unique[]' "$CORPUS")

mkdir -p "$DATA_DIR"
while IFS=$'\t' read -r item_id config split row audio_path reference duration_ms \
  expected_size expected_sha speaker_id accent raw_accent gender first_language; do
  destination="$DATA_DIR/$audio_path"
  mkdir -p "$(dirname "$destination")"
  if [[ -f "$destination" ]] \
    && verify_file "$destination" "$duration_ms" "$expected_size" "$expected_sha"; then
    continue
  fi

  row_json="$(mktemp "$TEMP_DIR/row.XXXXXX")"
  /usr/bin/jq -c --argjson row "$row" 'select(.row_idx == $row)' "$metadata" \
    > "$row_json"
  if [[ ! -s "$row_json" ]]; then
    echo "Pinned EdAcc row is not present in the speaker selection window: $item_id." >&2
    exit 1
  fi

  /usr/bin/jq -e \
    --argjson row "$row" \
    --arg revision "$DATASET_REVISION" \
    --arg config "$config" \
    --arg split "$split" \
    --arg reference "$reference" \
    --arg speaker_id "$speaker_id" \
    --arg accent "$accent" \
    --arg raw_accent "$raw_accent" \
    --arg gender "$gender" \
    --arg first_language "$first_language" \
    '. as $entry
      | $entry.row_idx == $row
      and $entry.row.text == $reference
      and $entry.row.speaker == $speaker_id
      and $entry.row.accent == $accent
      and $entry.row.raw_accent == $raw_accent
      and $entry.row.gender == $gender
      and $entry.row.l1 == $first_language
      and ($entry.row.audio[0].src
        | contains("/--/" + $revision + "/--/" + $config + "/" + $split + "/" + ($row | tostring) + "/audio/"))' \
    "$row_json" >/dev/null || {
      echo "Dataset metadata changed for $item_id." >&2
      exit 1
    }

  audio_url="$(/usr/bin/jq -er '.row.audio[0].src' "$row_json")"
  staged="$(mktemp "$TEMP_DIR/audio.XXXXXX")"
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

  if ! verify_file "$staged" "$duration_ms" "$expected_size" "$expected_sha"; then
    echo "Audio verification failed for $item_id." >&2
    exit 1
  fi
  /bin/mv "$staged" "$destination"
done < <(
  /usr/bin/jq -r \
    '.items[] as $item
      | .subsets[]
      | select(.id == $item.subsetID)
      | [$item.id, .config, .split, $item.row, $item.audio, $item.reference,
         $item.durationMs, $item.sizeBytes, $item.sha256, $item.speakerID,
         $item.slices.accent, ($item.slices.rawAccent // ""), $item.slices.gender,
         $item.slices.firstLanguage]
      | @tsv' \
    "$CORPUS"
)

echo "Verified EdAcc English nightly corpus at $DATA_DIR"
