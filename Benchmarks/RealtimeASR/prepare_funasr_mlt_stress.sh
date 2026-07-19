#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIRECTORY="$SCRIPT_DIRECTORY/.benchmark-data/funasr-mlt-stress"
FLEURS_DIRECTORY="$SCRIPT_DIRECTORY/.benchmark-data/fleurs-funasr-mlt-31-sample"
mkdir -p "$OUTPUT_DIRECTORY"

command -v ffmpeg >/dev/null
command -v say >/dev/null

generate_voice() {
  local slug="$1"
  local voice="$2"
  local text="$3"
  local aiff="$OUTPUT_DIRECTORY/$slug.aiff"
  local wav="$OUTPUT_DIRECTORY/$slug.wav"
  say -v "$voice" -r 185 -o "$aiff" "$text"
  ffmpeg -hide_banner -loglevel error -y -i "$aiff" \
    -ar 16000 -ac 1 -c:a pcm_f32le "$wav"
}

generate_voice one-word-en Samantha "Satellite"
generate_voice one-word-ar Majed "قمر صناعي"
generate_voice one-word-id Damayanti "Satelit"
generate_voice one-word-ja Kyoko "衛星"
generate_voice one-word-ko Yuna "위성"
generate_voice one-word-ms Amira "Satelit"
generate_voice one-word-th Kanya "ดาวเทียม"
generate_voice one-word-vi Linh "Vệ tinh"
generate_voice one-word-yue Sinji "衛星"
generate_voice one-word-zh Tingting "卫星"

generate_voice technical Samantha \
  "Please review the Swift package, verify the SHA 256 checksum, and keep transcription entirely offline."
generate_voice numerals Samantha \
  "Textify version 2 point 1 costs 42 dollars and 50 cents on July 19th, 2026."
generate_voice accent-india Aman \
  "Textify should return the final transcript quickly after I release the key."
generate_voice accent-britain Daniel \
  "Textify should return the final transcript quickly after I release the key."
generate_voice accent-australia Karen \
  "Textify should return the final transcript quickly after I release the key."
generate_voice code-switch-en Samantha "The meeting starts at nine thirty."
generate_voice code-switch-zh Tingting "请打开项目并检查最新版本。"
generate_voice paragraph Samantha \
  "A responsive dictation utility should preserve stable words, revise uncertain words quietly, and insert the final sentence without making the user wait."

printf '%s\n' \
  "file '$OUTPUT_DIRECTORY/code-switch-en.wav'" \
  "file '$OUTPUT_DIRECTORY/code-switch-zh.wav'" \
  > "$OUTPUT_DIRECTORY/code-switch.concat"
ffmpeg -hide_banner -loglevel error -y \
  -f concat -safe 0 -i "$OUTPUT_DIRECTORY/code-switch.concat" \
  -ar 16000 -ac 1 -c:a pcm_f32le "$OUTPUT_DIRECTORY/code-switch.wav"

ffmpeg -hide_banner -loglevel error -y \
  -stream_loop -1 -i "$OUTPUT_DIRECTORY/paragraph.wav" -t 59.5 \
  -ar 16000 -ac 1 -c:a pcm_f32le "$OUTPUT_DIRECTORY/max-duration.wav"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i anullsrc=r=16000:cl=mono -t 5 \
  -c:a pcm_f32le "$OUTPUT_DIRECTORY/silence.wav"

for language in ar en id ja ko ms th tl vi yue zh; do
  source_audio="$FLEURS_DIRECTORY/$language/0.wav"
  [[ -s "$source_audio" ]] || {
    echo "missing prepared FLEURS stress source: $source_audio" >&2
    exit 1
  }
  ffmpeg -hide_banner -loglevel error -y \
    -i "$source_audio" \
    -f lavfi -i anoisesrc=color=white:sample_rate=16000:duration=30 \
    -filter_complex \
      '[0:a]loudnorm=I=-23:TP=-2:LRA=7[speech];[1:a]volume=0.02[noise];[speech][noise]amix=inputs=2:duration=first:normalize=0' \
    -ar 16000 -ac 1 -c:a pcm_f32le \
    "$OUTPUT_DIRECTORY/noisy-$language.wav"
done

echo "Fun-ASR MLT stress audio written to $OUTPUT_DIRECTORY"
