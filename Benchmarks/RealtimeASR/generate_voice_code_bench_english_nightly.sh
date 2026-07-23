#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/Corpus/voice-code-bench-english-nightly-v1.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/voice-code-bench-english-nightly-v1"
TEMP_DIR="$(mktemp -d)"

DATASET_ID="besimple-ai/voice-code-bench"
DATASET_REVISION="2fdcc76d280fb4fdfa6240114bb5c5a3cdefe132"
METADATA_URL="https://huggingface.co/datasets/$DATASET_ID/raw/$DATASET_REVISION/data/metadata.jsonl"
RESOLVE_BASE_URL="https://huggingface.co/datasets/$DATASET_ID/resolve/$DATASET_REVISION/data"
VIEWER_BASE_URL="https://datasets-server.huggingface.co"

cleanup() {
  /usr/bin/find "$TEMP_DIR" -type f -delete 2>/dev/null || true
  /bin/rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

download() {
  local url="$1"
  local destination="$2"
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
}

metadata="$TEMP_DIR/metadata.jsonl"
download "$METADATA_URL" "$metadata"

row_count="$(/usr/bin/wc -l < "$metadata" | /usr/bin/tr -d ' ')"
if [[ "$row_count" != "300" ]]; then
  echo "Expected 300 VoiceCodeBench test rows, received $row_count." >&2
  exit 1
fi
/usr/bin/jq -se \
  'length == 300
    and all(.[]; .language == "en")
    and all(.[]; .file_name | test("^audio/[0-9]{3}\\.wav$"))
    and all(.[]; .audio_id | test("^[a-z0-9_]+$"))
    and ([.[] | select(.duration >= 1 and .duration <= 60)] | length == 108)' \
  "$metadata" >/dev/null || {
    echo "Pinned VoiceCodeBench metadata no longer has the expected English 1-60 second slice." >&2
    exit 1
  }

mkdir -p "$DATA_DIR/voice-code-bench-test"
items="$TEMP_DIR/items.jsonl"

download_queue="$TEMP_DIR/downloads.txt"
/usr/bin/jq -jcs \
  --arg resolve_base_url "$RESOLVE_BASE_URL" \
  --arg data_dir "$DATA_DIR" \
  'to_entries[]
    | select(.value.duration >= 1 and .value.duration <= 60)
    | ($resolve_base_url + "/" + .value.file_name), "\u0000",
      ($data_dir + "/voice-code-bench-test/" + (.value.file_name | sub("^audio/"; ""))), "\u0000"' \
  "$metadata" > "$download_queue"

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

while IFS= read -r entry; do
  row="$(/usr/bin/jq -er '.row_idx' <<< "$entry")"
  file_name="$(/usr/bin/jq -er '.row.file_name' <<< "$entry")"
  audio_id="$(/usr/bin/jq -er '.row.audio_id' <<< "$entry")"
  metadata_duration_ms="$(
    /usr/bin/jq -er '.row.duration * 1000 | round' <<< "$entry"
  )"

  if [[ ! "$file_name" =~ ^audio/[0-9]{3}\.wav$ ]]; then
    echo "Unsafe VoiceCodeBench audio path at row $row: $file_name" >&2
    exit 1
  fi
  if [[ ! "$audio_id" =~ ^[a-z0-9_]+$ ]]; then
    echo "Unsafe VoiceCodeBench audio id at row $row: $audio_id" >&2
    exit 1
  fi

  relative_audio="voice-code-bench-test/${file_name#audio/}"
  destination="$DATA_DIR/$relative_audio"

  duration_ms="$(/usr/bin/afinfo "$destination" | /usr/bin/awk '
    /estimated duration/ { printf "%d", ($3 * 1000) + 0.5; found = 1 }
    END { if (!found) exit 1 }
  ')"
  if (( duration_ms < 1000 || duration_ms > 60000 )); then
    echo "VoiceCodeBench row $row is outside the 1-60 second lane after decoding." >&2
    exit 1
  fi
  if (( duration_ms < metadata_duration_ms - 2 || duration_ms > metadata_duration_ms + 2 )); then
    echo "VoiceCodeBench duration metadata disagrees with audio at row $row." >&2
    exit 1
  fi

  if (( duration_ms < 45000 )); then
    duration_bucket="29-45"
  else
    duration_bucket="45-60"
  fi

  size_bytes="$(/usr/bin/stat -f '%z' "$destination")"
  sha256="$(/usr/bin/shasum -a 256 "$destination" | /usr/bin/awk '{print $1}')"

  /usr/bin/jq -cn \
    --arg id "voice-code-bench-$audio_id" \
    --argjson row "$row" \
    --arg audio "$relative_audio" \
    --arg reference "$(/usr/bin/jq -r '.row.transcripts.acoustic' <<< "$entry")" \
    --argjson duration_ms "$duration_ms" \
    --arg duration_bucket "$duration_bucket" \
    --argjson size_bytes "$size_bytes" \
    --arg sha256 "$sha256" \
    --arg speaker_id "$(/usr/bin/jq -r '.row.speaker.id' <<< "$entry")" \
    --arg domain "$(/usr/bin/jq -r '.row.domain' <<< "$entry")" \
    --arg scenario "$(/usr/bin/jq -r '.row.scenario' <<< "$entry")" \
    --arg difficulty "$(/usr/bin/jq -r '.row.difficulty' <<< "$entry")" \
    --arg accent "$(/usr/bin/jq -r '.row.speaker.accent' <<< "$entry")" \
    --arg sex "$(/usr/bin/jq -r '.row.speaker.sex' <<< "$entry")" \
    --arg age_bucket "$(/usr/bin/jq -r '.row.speaker.age_bucket' <<< "$entry")" \
    --arg entity_count "$(/usr/bin/jq -r '.row.entity_count | tostring' <<< "$entry")" \
    '{
      id: $id,
      subsetID: "voice-code-bench-test",
      row: $row,
      audio: $audio,
      reference: $reference,
      durationMs: $duration_ms,
      durationBucket: $duration_bucket,
      sizeBytes: $size_bytes,
      sha256: $sha256,
      speakerID: $speaker_id,
      slices: {
        domain: $domain,
        scenario: $scenario,
        difficulty: $difficulty,
        accent: $accent,
        sex: $sex,
        ageBucket: $age_bucket,
        entityCount: $entity_count
      }
    }' >> "$items"
done < <(
  /usr/bin/jq -cs \
    'to_entries[]
      | select(.value.duration >= 1 and .value.duration <= 60)
      | {row_idx: .key, row: .value}' \
    "$metadata"
)

item_count="$(/usr/bin/wc -l < "$items" | /usr/bin/tr -d ' ')"
if [[ "$item_count" != "108" ]]; then
  echo "Expected 108 VoiceCodeBench nightly items, generated $item_count." >&2
  exit 1
fi

generated="$TEMP_DIR/voice-code-bench-english-nightly-v1.json"
/usr/bin/jq -s \
  --arg dataset_id "$DATASET_ID" \
  --arg dataset_revision "$DATASET_REVISION" \
  --arg viewer_base_url "$VIEWER_BASE_URL" \
  'sort_by(.row)
    | {
      schemaVersion: 2,
      id: "voice-code-bench-english-nightly-v1",
      name: "VoiceCodeBench English nightly workplace dictation evaluation",
      language: "en",
      dataset: {
        id: $dataset_id,
        revision: $dataset_revision,
        viewerBaseURL: $viewer_base_url
      },
      selection: {
        rule: "all official test recordings whose decoded duration is 1-60 seconds; WER reference is the acoustic transcript"
      },
      durationLanes: [
        {id: "full-60", maxAudioSeconds: 60}
      ],
      requiredDurationBuckets: ["29-45", "45-60"],
      subsets: [
        {
          id: "voice-code-bench-test",
          config: "default",
          split: "test",
          role: "product-diagnostic",
          speechOrigin: "human-read",
          license: "MIT",
          sourceURL: "https://huggingface.co/datasets/besimple-ai/voice-code-bench"
        }
      ],
      items: .
    }' \
  "$items" > "$generated"

/bin/mv "$generated" "$OUTPUT"
echo "Generated 108-item VoiceCodeBench nightly manifest at $OUTPUT"
