#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$SCRIPT_DIR/Corpus/english-nightly-bootstrap-v1.index.json"

cd "$SCRIPT_DIR"
/usr/bin/swift build -c release --product TextifyEvaluationTool
TOOL="$SCRIPT_DIR/.build/release/TextifyEvaluationTool"
"$TOOL" validate-index "$INDEX"

"$SCRIPT_DIR/prepare_open_asr_english_nightly.sh"
"$SCRIPT_DIR/prepare_edacc_english_nightly.sh"
"$SCRIPT_DIR/prepare_berst_english_nightly.sh"
"$SCRIPT_DIR/prepare_voice_code_bench_english_nightly.sh"
"$SCRIPT_DIR/prepare_musan_no_speech_nightly.sh"

echo "Verified all English nightly bootstrap corpora"
