#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Textify.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Textify.app"

ensure_xcode_project() {
  cd "$REPO_ROOT"
  local project_file="$REPO_ROOT/Textify.xcodeproj/project.pbxproj"
  local checksum_before=""
  if [[ -f "$project_file" ]]; then
    checksum_before="$(shasum -a 256 "$project_file" | awk '{print $1}')"
  fi
  "$REPO_ROOT/script/generate_xcode_project.sh"
  if [[ -n "$checksum_before" ]]; then
    local checksum_after
    checksum_after="$(shasum -a 256 "$project_file" | awk '{print $1}')"
    if [[ "$checksum_before" != "$checksum_after" ]]; then
      echo "Textify.xcodeproj was stale and has been regenerated. Review it, then rerun the release command." >&2
      exit 1
    fi
  fi
}
