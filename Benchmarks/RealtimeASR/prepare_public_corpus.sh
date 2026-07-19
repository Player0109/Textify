#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/.benchmark-data/openslr31"
ARCHIVE="$DATA_DIR/dev-clean-2.tar.gz"
EXPECTED_MD5="6d7ab67ac6a1d2c993d050e16d61080d"

mkdir -p "$DATA_DIR"

if [[ ! -f "$ARCHIVE" ]]; then
  /usr/bin/curl \
    --fail \
    --location \
    --output "$ARCHIVE" \
    "https://www.openslr.org/resources/31/dev-clean-2.tar.gz"
fi

actual_md5="$(/sbin/md5 -q "$ARCHIVE")"
if [[ "$actual_md5" != "$EXPECTED_MD5" ]]; then
  echo "Archive checksum mismatch: expected $EXPECTED_MD5, received $actual_md5" >&2
  exit 1
fi

/usr/bin/tar -xzf "$ARCHIVE" -C "$DATA_DIR"

missing=0
while IFS= read -r relative_path; do
  if [[ ! -f "$DATA_DIR/$relative_path" ]]; then
    echo "Missing corpus item: $relative_path" >&2
    missing=1
  fi
done < <(/usr/bin/jq -r '.items[].audio' "$SCRIPT_DIR/Corpus/openslr31.json")

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "Verified OpenSLR 31 corpus at $DATA_DIR"
