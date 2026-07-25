#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <declaration.json> <evidence-root> <bundle-output.json>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DECLARATION_PATH="$1"
EVIDENCE_ROOT="$2"
BUNDLE_OUTPUT="$3"
RELEASE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"

swift run \
  --package-path "$ROOT_DIR" \
  TextifyReleaseEvidenceVerifier \
  "$DECLARATION_PATH" \
  "$EVIDENCE_ROOT" \
  "$ROOT_DIR/docs/SPEC.md" \
  "$RELEASE_COMMIT" \
  "$BUNDLE_OUTPUT"

echo "Validated release evidence bundle written to $BUNDLE_OUTPUT"
