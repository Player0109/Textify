#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/Corpus/voice-code-bench-english-nightly-v1.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/voice-code-bench-english-nightly-v1"
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
METADATA_URL="https://huggingface.co/datasets/$DATASET_ID/raw/$DATASET_REVISION/data/metadata.jsonl"
RESOLVE_BASE_URL="https://huggingface.co/datasets/$DATASET_ID/resolve/$DATASET_REVISION/data"

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

metadata_jsonl="$TEMP_DIR/metadata.jsonl"
metadata="$TEMP_DIR/metadata.json"
download "$METADATA_URL" "$metadata_jsonl"
/usr/bin/jq -s '.' "$metadata_jsonl" > "$metadata"
if [[ "$(/usr/bin/jq -r 'length' "$metadata")" != "300" ]]; then
  echo "Expected 300 pinned VoiceCodeBench metadata rows." >&2
  exit 1
fi

mkdir -p "$DATA_DIR"
while IFS=$'\t' read -r item_id row audio_path reference duration_ms expected_size \
  expected_sha speaker_id domain scenario difficulty accent sex age_bucket entity_count; do
  row_json="$(mktemp "$TEMP_DIR/row.XXXXXX")"
  /usr/bin/jq -c --argjson row "$row" '.[$row]' "$metadata" > "$row_json"
  source_file_name="audio/${audio_path#voice-code-bench-test/}"
  metadata_duration_ms="$(/usr/bin/jq -r '.duration * 1000 | round' "$row_json")"

  /usr/bin/jq -e \
    --arg item_id "$item_id" \
    --arg file_name "$source_file_name" \
    --arg reference "$reference" \
    --arg speaker_id "$speaker_id" \
    --arg domain "$domain" \
    --arg scenario "$scenario" \
    --arg difficulty "$difficulty" \
    --arg accent "$accent" \
    --arg sex "$sex" \
    --arg age_bucket "$age_bucket" \
    --arg entity_count "$entity_count" \
    '.language == "en"
      and ("voice-code-bench-" + .audio_id) == $item_id
      and .file_name == $file_name
      and .transcripts.acoustic == $reference
      and .speaker.id == $speaker_id
      and .domain == $domain
      and .scenario == $scenario
      and .difficulty == $difficulty
      and .speaker.accent == $accent
      and .speaker.sex == $sex
      and .speaker.age_bucket == $age_bucket
      and (.entity_count | tostring) == $entity_count' \
    "$row_json" >/dev/null || {
      echo "Pinned VoiceCodeBench metadata changed for $item_id." >&2
      exit 1
    }
  if (( duration_ms < metadata_duration_ms - 2 || duration_ms > metadata_duration_ms + 2 )); then
    echo "Pinned VoiceCodeBench duration metadata changed for $item_id." >&2
    exit 1
  fi

  destination="$DATA_DIR/$audio_path"
  mkdir -p "$(dirname "$destination")"
  if [[ -f "$destination" ]] \
    && verify_file "$destination" "$duration_ms" "$expected_size" "$expected_sha"; then
    continue
  fi

  staged="$(mktemp "$TEMP_DIR/audio.XXXXXX")"
  download "$RESOLVE_BASE_URL/$source_file_name" "$staged"
  if ! verify_file "$staged" "$duration_ms" "$expected_size" "$expected_sha"; then
    echo "Audio verification failed for $item_id." >&2
    exit 1
  fi
  /bin/mv "$staged" "$destination"
done < <(
  /usr/bin/jq -r \
    '.items[]
      | [.id, .row, .audio, .reference, .durationMs, .sizeBytes, .sha256,
         .speakerID, .slices.domain, .slices.scenario, .slices.difficulty,
         .slices.accent, .slices.sex, .slices.ageBucket, .slices.entityCount]
      | @tsv' \
    "$CORPUS"
)

echo "Verified VoiceCodeBench English nightly corpus at $DATA_DIR"
