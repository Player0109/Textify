#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/Corpus/jsut-basic5000-sample.json"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/jsut-basic5000-sample"
REVISION="$(/usr/bin/jq -r '.revision' "$CORPUS")"
BASE_URL="https://huggingface.co/datasets/FluidInference/JSUT-basic5000/resolve/$REVISION"

mkdir -p "$DATA_DIR"

while IFS=$'\t' read -r audio_path expected_sha expected_size; do
  destination="$DATA_DIR/$audio_path"
  mkdir -p "$(dirname "$destination")"

  if [[ -f "$destination" ]]; then
    actual_sha="$(/usr/bin/shasum -a 256 "$destination" | /usr/bin/awk '{print $1}')"
    actual_size="$(/usr/bin/stat -f '%z' "$destination")"
    if [[ "$actual_sha" == "$expected_sha" && "$actual_size" == "$expected_size" ]]; then
      continue
    fi
  fi

  temporary="$(/usr/bin/mktemp "$DATA_DIR/.audio.XXXXXX")"
  /usr/bin/curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --output "$temporary" \
    "$BASE_URL/$audio_path"
  actual_sha="$(/usr/bin/shasum -a 256 "$temporary" | /usr/bin/awk '{print $1}')"
  actual_size="$(/usr/bin/stat -f '%z' "$temporary")"
  if [[ "$actual_sha" != "$expected_sha" || "$actual_size" != "$expected_size" ]]; then
    /bin/rm -f "$temporary"
    echo "JSUT artifact changed: $audio_path" >&2
    exit 1
  fi
  /bin/mv "$temporary" "$destination"
done < <(/usr/bin/jq -r '.items[] | [.audio, .sha256, .sizeBytes] | @tsv' "$CORPUS")

echo "Verified JSUT sample at $DATA_DIR"
