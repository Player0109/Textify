#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/.benchmark-data/synthetic"
mkdir -p "$OUTPUT_DIR"

generate() {
  local filename="$1"
  local text="$2"
  /usr/bin/say \
    --voice Samantha \
    --rate 185 \
    --output-file "$OUTPUT_DIR/$filename" \
    "$text"
}

generate short.aiff \
  "Textify should show useful words while I am still speaking."
generate technical.aiff \
  "Please review the Swift package, verify the checksum, and keep the transcription entirely offline."
generate paragraph.aiff \
  "A responsive dictation utility should begin understanding speech before the recording ends. It should preserve stable words, revise uncertain words quietly, and insert the final sentence without making the user wait."

echo "Synthetic corpus written to $OUTPUT_DIR"
