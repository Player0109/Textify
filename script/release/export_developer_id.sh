#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$REPO_ROOT/script/release/ExportOptions.DeveloperID.plist"
