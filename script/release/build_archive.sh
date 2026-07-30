#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"
: "${TEXTIFY_SIGNING_IDENTITY:?Set TEXTIFY_SIGNING_IDENTITY}"

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
ensure_xcode_project
mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH"

xcodebuild archive \
  -project "$REPO_ROOT/Textify.xcodeproj" \
  -scheme Textify \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEXTIFY_DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="$TEXTIFY_SIGNING_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO

[[ -d "$ARCHIVE_PATH" ]]
git -C "$REPO_ROOT" rev-parse HEAD > "$ARCHIVE_COMMIT_PATH"
