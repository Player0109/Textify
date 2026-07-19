#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/Corpus/fleurs-funasr-mlt-31-sample.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/fleurs-funasr-mlt-31-sample"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

DATASET_ID="$(/usr/bin/jq -r '.dataset.id' "$CORPUS")"
DATASET_REVISION="$(/usr/bin/jq -r '.dataset.revision' "$CORPUS")"
SPLIT="$(/usr/bin/jq -r '.dataset.split' "$CORPUS")"
ROWS_PER_LANGUAGE="$(/usr/bin/jq -r '.rowsPerLanguage' "$CORPUS")"
CACHE_DIR="$SCRIPT_DIR/.benchmark-cache/fleurs-funasr-mlt-31-sample"
RAW_FALLBACKS="$SCRIPT_DIR/Corpus/fleurs-funasr-mlt-31-raw-fallbacks.tsv"

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

fallback_metadata() {
  local config="$1"
  /usr/bin/awk -F '\t' -v config="$config" \
    '$1 == config { print $2 "\t" $3 "\t" $4 "\t" $5; found = 1 } END { if (!found) exit 1 }' \
    "$RAW_FALLBACKS"
}

extract_raw_rows() {
  local config="$1"
  local language_dir="$2"
  local rows_file="$3"
  local metadata
  local tar_size
  local tar_sha
  local tsv_size
  local tsv_sha
  local source_root="https://huggingface.co/datasets/$DATASET_ID/resolve/$DATASET_REVISION/data/$config"

  metadata="$(fallback_metadata "$config")"
  IFS=$'\t' read -r tar_size tar_sha tsv_size tsv_sha <<<"$metadata"
  /usr/bin/python3 "$SCRIPT_DIR/extract_fleurs_raw_rows.py" \
    --tar-url "$source_root/audio/dev.tar.gz" \
    --tar-size "$tar_size" \
    --tar-sha256 "$tar_sha" \
    --tsv-url "$source_root/dev.tsv" \
    --tsv-size "$tsv_size" \
    --tsv-sha256 "$tsv_sha" \
    --output-directory "$language_dir" \
    --rows-json "$rows_file" \
    --revision "$DATASET_REVISION" \
    --config "$config" \
    --split "$SPLIT" \
    --count "$ROWS_PER_LANGUAGE"
}

mkdir -p "$DATA_DIR" "$CACHE_DIR"

while IFS=$'\t' read -r language config; do
  rows_file="$TEMP_DIR/$config.json"
  rows_url="https://datasets-server.huggingface.co/rows?dataset=$DATASET_ID&config=$config&split=$SPLIT&offset=0&length=$ROWS_PER_LANGUAGE"
  language_dir="$DATA_DIR/$language"
  mkdir -p "$language_dir"
  if fallback_metadata "$config" >/dev/null; then
    extract_raw_rows "$config" "$language_dir" "$rows_file"
  else
    /usr/bin/curl --retry 10 --retry-all-errors --retry-delay 2 --fail --silent --show-error --location \
      "$rows_url" \
      --output "$rows_file"
  fi

  /usr/bin/jq -e \
    --arg revision "$DATASET_REVISION" \
    --arg config "$config" \
    --arg split "$SPLIT" \
    --argjson expected "$ROWS_PER_LANGUAGE" \
    '(.rows | length) == $expected and all(.rows[]; .row.audio[0].src | contains("/--/" + $revision + "/--/" + $config + "/" + $split + "/"))' \
    "$rows_file" >/dev/null

  while IFS=$'\t' read -r row_index audio_path expected_size expected_sha expected_reference; do
    destination="$DATA_DIR/$audio_path"
    mkdir -p "$(dirname "$destination")"
    if [[ -f "$destination" ]] && verify_file "$destination" "$expected_size" "$expected_sha"; then
      continue
    fi

    source_row="$(/usr/bin/jq -c --argjson row "$row_index" '.rows[] | select(.row_idx == $row)' "$rows_file")"
    audio_url="$(/usr/bin/jq -r '.row.audio[0].src' <<<"$source_row")"
    actual_reference="$(/usr/bin/jq -r '.row.transcription' <<<"$source_row")"
    [[ "$actual_reference" == "$expected_reference" ]]

    staged="$TEMP_DIR/$language-$row_index.wav"
    /usr/bin/curl --retry 10 --retry-all-errors --retry-delay 2 --fail --silent --show-error --location \
      "$audio_url" \
      --output "$staged"
    verify_file "$staged" "$expected_size" "$expected_sha"
    /bin/mv "$staged" "$destination"
  done < <(/usr/bin/jq -r --arg language "$language" '.items[] | select(.language == $language) | [.row, .audio, .sizeBytes, .sha256, .reference] | @tsv' "$CORPUS")
done < <(/usr/bin/jq -r '.items | map({language,config}) | unique | .[] | [.language,.config] | @tsv' "$CORPUS")

echo "Verified multilingual FLEURS sample at $DATA_DIR"
