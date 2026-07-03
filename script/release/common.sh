#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Textify.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Textify.app"

ensure_xcode_project() {
  cd "$REPO_ROOT"
  if [[ ! -d Textify.xcodeproj ]]; then
    xcodegen generate
  fi
}
