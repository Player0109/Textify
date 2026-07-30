#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <Textify.app-or-dmg> <expected-source-commit> [--allow-unsigned-dmg]" >&2
  exit 2
fi

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ARTIFACT_PATH="$1"
EXPECTED_COMMIT="$2"
MODE="${3:-}"

require_release_commit "$EXPECTED_COMMIT"
if [[ -n "$MODE" && "$MODE" != "--allow-unsigned-dmg" ]]; then
  echo "unexpected option: $MODE" >&2
  exit 2
fi

verify_signed_app() {
  local app_path="$1"
  [[ -d "$app_path" && ! -L "$app_path" ]]
  codesign --verify --deep --strict --verbose=2 "$app_path"
  require_embedded_source_commit "$app_path" "$EXPECTED_COMMIT"
}

if [[ -d "$ARTIFACT_PATH" ]]; then
  verify_signed_app "$ARTIFACT_PATH"
  printf 'Verified signed app source commit %s\n' "$EXPECTED_COMMIT"
  exit 0
fi

[[ -f "$ARTIFACT_PATH" && ! -L "$ARTIFACT_PATH" ]]
if [[ "$MODE" != "--allow-unsigned-dmg" ]]; then
  codesign --verify --strict --verbose=2 "$ARTIFACT_PATH"
fi

MOUNT_DIRECTORY="$(mktemp -d)"
MOUNTED=false
cleanup() {
  if [[ "$MOUNTED" == true ]]; then
    hdiutil detach "$MOUNT_DIRECTORY" -quiet >/dev/null 2>&1 || true
  fi
  rmdir "$MOUNT_DIRECTORY" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach \
  "$ARTIFACT_PATH" \
  -nobrowse \
  -readonly \
  -mountpoint "$MOUNT_DIRECTORY" \
  -quiet
MOUNTED=true
verify_signed_app "$MOUNT_DIRECTORY/Textify.app"
hdiutil detach "$MOUNT_DIRECTORY" -quiet
MOUNTED=false
rmdir "$MOUNT_DIRECTORY"
trap - EXIT

printf 'Verified signed DMG app source commit %s\n' "$EXPECTED_COMMIT"
