#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"
: "${TEXTIFY_SIGNING_IDENTITY:?Set TEXTIFY_SIGNING_IDENTITY}"

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_clean_source_tree() {
  local source_status
  source_status="$(git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all)"
  if [[ -n "$source_status" ]]; then
    echo "Release archives require a clean tracked and untracked source tree." >&2
    printf '%s\n' "$source_status" >&2
    exit 1
  fi
}

rm -f "$ARCHIVE_COMMIT_PATH"
ensure_xcode_project
mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH"

require_clean_source_tree
SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse --verify HEAD)"

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
[[ "$(git -C "$REPO_ROOT" rev-parse --verify HEAD)" == "$SOURCE_COMMIT" ]]
require_clean_source_tree
printf '%s\n' "$SOURCE_COMMIT" > "$ARCHIVE_COMMIT_PATH"
