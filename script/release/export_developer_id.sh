#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"
: "${TEXTIFY_SIGNING_IDENTITY:?Set TEXTIFY_SIGNING_IDENTITY}"

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
rm -rf "$EXPORT_PATH"
[[ -d "$ARCHIVE_PATH" ]]
[[ -f "$ARCHIVE_COMMIT_PATH" ]]
SOURCE_COMMIT="$(<"$ARCHIVE_COMMIT_PATH")"
require_clean_head_at_commit "$SOURCE_COMMIT"
"$REPO_ROOT/script/release/verify_artifact_source_commit.sh" \
  "$ARCHIVED_APP_PATH" \
  "$SOURCE_COMMIT"
mkdir -p "$EXPORT_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$REPO_ROOT/script/release/ExportOptions.DeveloperID.plist"

SWIFT_COMPATIBILITY_LIBRARY="$APP_PATH/Contents/Frameworks/libswiftCompatibilitySpan.dylib"
[[ -s "$SWIFT_COMPATIBILITY_LIBRARY" ]]
TEMPORARY_DIRECTORY="$(mktemp -d)"
cleanup() {
  rm -rf "$TEMPORARY_DIRECTORY"
}
trap cleanup EXIT
lipo \
  "$SWIFT_COMPATIBILITY_LIBRARY" \
  -thin arm64 \
  -output "$TEMPORARY_DIRECTORY/libswiftCompatibilitySpan.dylib"
mv \
  "$TEMPORARY_DIRECTORY/libswiftCompatibilitySpan.dylib" \
  "$SWIFT_COMPATIBILITY_LIBRARY"
codesign \
  --force \
  --sign "$TEXTIFY_SIGNING_IDENTITY" \
  --timestamp \
  --options runtime \
  "$SWIFT_COMPATIBILITY_LIBRARY"
codesign \
  --force \
  --sign "$TEXTIFY_SIGNING_IDENTITY" \
  --timestamp \
  --options runtime \
  --entitlements "$REPO_ROOT/Textify.entitlements" \
  "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
"$REPO_ROOT/script/release/verify_artifact_source_commit.sh" \
  "$APP_PATH" \
  "$SOURCE_COMMIT"
require_clean_head_at_commit "$SOURCE_COMMIT"
printf '%s\n' "$SOURCE_COMMIT" > "$EXPORT_COMMIT_PATH"
trap - EXIT
rm -rf "$TEMPORARY_DIRECTORY"
