#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/Corpus/fleurs-funasr-mlt-31-sample.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/fleurs-funasr-mlt-31-sample"
DATASET_ID="google/fleurs"
DATASET_REVISION="70bb2e84b976b7e960aa89f1c648e09c59f894dd"
SPLIT="validation"
ROWS_PER_LANGUAGE=10
CACHE_DIR="$SCRIPT_DIR/.benchmark-cache/fleurs-funasr-mlt-31-sample"
RAW_FALLBACKS="$SCRIPT_DIR/Corpus/fleurs-funasr-mlt-31-raw-fallbacks.tsv"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

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
: > "$TEMP_DIR/items.jsonl"

while IFS=$'\t' read -r language config; do
  rows_file="$TEMP_DIR/$config.json"
  rows_url="https://datasets-server.huggingface.co/rows?dataset=$DATASET_ID&config=$config&split=$SPLIT&offset=0&length=$ROWS_PER_LANGUAGE"
  language_dir="$DATA_DIR/$language"
  used_parquet=0
  mkdir -p "$language_dir"

  if fallback_metadata "$config" >/dev/null; then
    extract_raw_rows "$config" "$language_dir" "$rows_file"
    used_parquet=1
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

  if [[ "$used_parquet" == 0 ]]; then
    download_pids=()
    while IFS=$'\t' read -r row_index audio_url; do
      destination="$language_dir/$row_index.wav"
      /usr/bin/curl --retry 10 --retry-all-errors --retry-delay 2 --fail --silent --show-error --location \
        "$audio_url" \
        --output "$destination" &
      download_pids+=("$!")
    done < <(/usr/bin/jq -r '.rows[] | [.row_idx, .row.audio[0].src] | @tsv' "$rows_file")

    for download_pid in "${download_pids[@]}"; do
      wait "$download_pid"
    done
  fi

  echo "Downloaded $language ($config)"

  for row_index in $(/usr/bin/jq -r '.rows[].row_idx' "$rows_file"); do
    reference="$(/usr/bin/jq -r --argjson row "$row_index" '.rows[] | select(.row_idx == $row) | .row.transcription' "$rows_file")"
    source_filename="$(/usr/bin/jq -r --argjson row "$row_index" '.rows[] | select(.row_idx == $row) | (.row.source_filename // "")' "$rows_file")"
    relative_audio="$language/$row_index.wav"
    destination="$DATA_DIR/$relative_audio"

    size_bytes="$(/usr/bin/stat -f '%z' "$destination")"
    sha256="$(/usr/bin/shasum -a 256 "$destination" | /usr/bin/awk '{print $1}')"

    /usr/bin/jq -nc \
      --arg id "$language-validation-$row_index" \
      --arg language "$language" \
      --arg config "$config" \
      --arg audio "$relative_audio" \
      --arg reference "$reference" \
      --arg sourceFilename "$source_filename" \
      --arg sha256 "$sha256" \
      --argjson row "$row_index" \
      --argjson sizeBytes "$size_bytes" \
      '{id:$id, language:$language, config:$config, row:$row, audio:$audio, reference:$reference, sizeBytes:$sizeBytes, sha256:$sha256} + (if $sourceFilename == "" then {} else {sourceFilename:$sourceFilename, sourceSplit:"dev"} end)' \
      >> "$TEMP_DIR/items.jsonl"
  done
done <<'LANGUAGES'
zh	cmn_hans_cn
en	en_us
yue	yue_hant_hk
ja	ja_jp
ko	ko_kr
vi	vi_vn
id	id_id
th	th_th
ms	ms_my
tl	fil_ph
ar	ar_eg
hi	hi_in
bg	bg_bg
hr	hr_hr
cs	cs_cz
da	da_dk
nl	nl_nl
et	et_ee
fi	fi_fi
el	el_gr
hu	hu_hu
ga	ga_ie
lv	lv_lv
lt	lt_lt
mt	mt_mt
pl	pl_pl
pt	pt_br
ro	ro_ro
sk	sk_sk
sl	sl_si
sv	sv_se
LANGUAGES

/usr/bin/jq -s \
  --arg id "$DATASET_ID" \
  --arg revision "$DATASET_REVISION" \
  --arg split "$SPLIT" \
  --arg license "CC-BY-4.0" \
  --argjson rowsPerLanguage "$ROWS_PER_LANGUAGE" \
  '{dataset:{id:$id, revision:$revision, split:$split, license:$license}, rowsPerLanguage:$rowsPerLanguage, languages:([.[].language] | unique), items:.}' \
  "$TEMP_DIR/items.jsonl" \
  > "$TEMP_DIR/corpus.json"

/bin/mv "$TEMP_DIR/corpus.json" "$CORPUS"
echo "Generated $CORPUS and verified audio at $DATA_DIR"
