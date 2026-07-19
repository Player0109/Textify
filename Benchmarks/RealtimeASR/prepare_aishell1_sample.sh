#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/aishell1-sample"
CORPUS="$SCRIPT_DIR/Corpus/aishell1-sample.json"
ROWS="$DATA_DIR/rows.json"

mkdir -p "$DATA_DIR"

/usr/bin/curl \
  --fail \
  --silent \
  --show-error \
  --get \
  --data-urlencode "dataset=AudioLLMs/aishell_1_zh_test" \
  --data-urlencode "config=default" \
  --data-urlencode "split=test" \
  --data-urlencode "offset=0" \
  --data-urlencode "length=10" \
  --output "$ROWS" \
  "https://datasets-server.huggingface.co/rows"

while IFS=$'\t' read -r item_id audio_path expected_sha reference; do
  row_reference="$(/usr/bin/jq -r --argjson row "$item_id" '.rows[] | select(.row_idx == $row) | .row.answer' "$ROWS")"
  if [[ "$row_reference" != "$reference" ]]; then
    echo "Dataset reference changed for row $item_id." >&2
    exit 1
  fi

  destination="$DATA_DIR/$audio_path"
  if [[ -f "$destination" ]] && [[ "$(/usr/bin/shasum -a 256 "$destination" | /usr/bin/awk '{print $1}')" == "$expected_sha" ]]; then
    continue
  fi

  audio_url="$(/usr/bin/jq -r --argjson row "$item_id" '.rows[] | select(.row_idx == $row) | .row.context[0].src' "$ROWS")"
  temporary="$(/usr/bin/mktemp "$DATA_DIR/.audio-$item_id.XXXXXX")"
  /usr/bin/curl --fail --silent --show-error --location --output "$temporary" "$audio_url"
  actual_sha="$(/usr/bin/shasum -a 256 "$temporary" | /usr/bin/awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "Audio checksum changed for row $item_id." >&2
    exit 1
  fi
  /bin/mv "$temporary" "$destination"
done < <(/usr/bin/jq -r '.items[] | [.id, .audio, .sha256, .reference] | @tsv' "$CORPUS")

echo "Verified AISHELL-1 sample at $DATA_DIR"
