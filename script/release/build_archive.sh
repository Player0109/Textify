#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"
: "${TEXTIFY_SIGNING_IDENTITY:?Set TEXTIFY_SIGNING_IDENTITY}"

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

rm -f "$ARCHIVE_COMMIT_PATH"
require_clean_source_tree
ensure_xcode_project
mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH"

SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse --verify HEAD)"
require_clean_head_at_commit "$SOURCE_COMMIT"

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
  ONLY_ACTIVE_ARCH=NO \
  TEXTIFY_SOURCE_COMMIT="$SOURCE_COMMIT"

[[ -d "$ARCHIVE_PATH" ]]
[[ -d "$ARCHIVED_APP_PATH" ]]
require_clean_head_at_commit "$SOURCE_COMMIT"
"$REPO_ROOT/script/release/verify_artifact_source_commit.sh" \
  "$ARCHIVED_APP_PATH" \
  "$SOURCE_COMMIT"
require_clean_head_at_commit "$SOURCE_COMMIT"
printf '%s\n' "$SOURCE_COMMIT" > "$ARCHIVE_COMMIT_PATH"
