#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.1.0}"
PREVIEW_NUMBER="${2:-1}"
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$PREVIEW_NUMBER" =~ ^[1-9][0-9]*$ ]]

PREVIEW_VERSION="$VERSION-unsigned-preview.$PREVIEW_NUMBER"
DMG_NAME="Textify-$PREVIEW_VERSION-arm64.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
TEMPORARY_DMG_PATH="$BUILD_DIR/.Textify-$PREVIEW_VERSION-arm64.in-progress.dmg"
STAGING_PATH="$BUILD_DIR/unsigned-preview-staging"
STAGED_APP_PATH="$REPO_ROOT/dist/Textify.app"
SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse --verify HEAD)"
ENTITLEMENTS_PLIST=""
OUTPUTS_COMPLETE=false

require_clean_head_at_commit "$SOURCE_COMMIT"
REMOTE_MASTER_COMMIT="$(
  git -C "$REPO_ROOT" ls-remote --exit-code origin refs/heads/master \
    | awk '{print $1}'
)"
require_release_commit "$REMOTE_MASTER_COMMIT"
if [[ "$SOURCE_COMMIT" != "$REMOTE_MASTER_COMMIT" ]]; then
  echo "Unsigned previews must be built from the current origin/master commit." >&2
  echo "HEAD:          $SOURCE_COMMIT" >&2
  echo "origin/master: $REMOTE_MASTER_COMMIT" >&2
  exit 1
fi

if [[ -e "$DMG_PATH" || -e "$CHECKSUM_PATH" ]]; then
  echo "Unsigned preview output already exists; refusing to overwrite it." >&2
  echo "$DMG_PATH" >&2
  echo "$CHECKSUM_PATH" >&2
  exit 1
fi
rm -rf "$STAGING_PATH"
rm -f "$TEMPORARY_DMG_PATH"
mkdir -p "$BUILD_DIR"

cleanup() {
  rm -rf "$STAGING_PATH"
  rm -f "$TEMPORARY_DMG_PATH"
  if [[ -n "$ENTITLEMENTS_PLIST" ]]; then
    rm -f "$ENTITLEMENTS_PLIST"
  fi
  if [[ "$OUTPUTS_COMPLETE" != true ]]; then
    rm -f "$DMG_PATH" "$CHECKSUM_PATH"
  fi
}
trap cleanup EXIT

TEXTIFY_SOURCE_COMMIT="$SOURCE_COMMIT" \
  "$REPO_ROOT/script/build_and_run.sh" --stage-full-release

[[ -d "$STAGED_APP_PATH" && ! -L "$STAGED_APP_PATH" ]]
require_embedded_source_commit "$STAGED_APP_PATH" "$SOURCE_COMMIT"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STAGED_APP_PATH/Contents/Info.plist")" == "$VERSION" ]]
/usr/libexec/PlistBuddy \
  -c "Add :CFBundleDisplayName string Textify Unsigned Preview $PREVIEW_NUMBER" \
  "$STAGED_APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Add :TextifyReleaseChannel string unsigned-preview.$PREVIEW_NUMBER" \
  "$STAGED_APP_PATH/Contents/Info.plist"
codesign \
  --force \
  --sign - \
  --timestamp=none \
  --options runtime \
  --entitlements "$REPO_ROOT/Textify.Local.entitlements" \
  "$STAGED_APP_PATH"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP_PATH"
APP_SIGNING_DETAILS="$(codesign --display --verbose=4 "$STAGED_APP_PATH" 2>&1)"
grep -Fqx 'Signature=adhoc' <<<"$APP_SIGNING_DETAILS"
grep -Fqx 'TeamIdentifier=not set' <<<"$APP_SIGNING_DETAILS"
grep -Eq '^CodeDirectory .* flags=.*\([^)]*adhoc[^)]*runtime[^)]*\)' \
  <<<"$APP_SIGNING_DETAILS"
if grep -Eq '^Authority=' <<<"$APP_SIGNING_DETAILS"; then
  echo "Unsigned previews must not carry a Developer ID authority." >&2
  exit 1
fi
ENTITLEMENTS_PLIST="$(mktemp)"
codesign \
  --display \
  --xml \
  --entitlements "$ENTITLEMENTS_PLIST" \
  "$STAGED_APP_PATH"
plutil -convert json -o - "$ENTITLEMENTS_PLIST" \
  | jq -e '
      keys == [
        "com.apple.security.cs.disable-library-validation",
        "com.apple.security.device.audio-input"
      ]
      and .["com.apple.security.cs.disable-library-validation"] == true
      and .["com.apple.security.device.audio-input"] == true
    ' >/dev/null

mkdir -p "$STAGING_PATH"
/usr/bin/ditto "$STAGED_APP_PATH" "$STAGING_PATH/Textify.app"
ln -s /Applications "$STAGING_PATH/Applications"

hdiutil create \
  -volname "Textify $VERSION Unsigned Preview $PREVIEW_NUMBER" \
  -srcfolder "$STAGING_PATH" \
  -ov \
  -format UDZO \
  "$TEMPORARY_DMG_PATH"

if codesign --verify --strict "$TEMPORARY_DMG_PATH" >/dev/null 2>&1; then
  echo "Unsigned preview DMG unexpectedly has a valid code signature." >&2
  exit 1
fi

MOUNT_DIRECTORY="$(mktemp -d)"
MOUNTED=false
cleanup_mount() {
  if [[ "$MOUNTED" == true ]]; then
    hdiutil detach "$MOUNT_DIRECTORY" -quiet >/dev/null 2>&1 || true
  fi
  rmdir "$MOUNT_DIRECTORY" >/dev/null 2>&1 || true
}
trap 'cleanup_mount; cleanup' EXIT

hdiutil attach \
  "$TEMPORARY_DMG_PATH" \
  -nobrowse \
  -readonly \
  -mountpoint "$MOUNT_DIRECTORY" \
  -quiet
MOUNTED=true

MOUNTED_APP_PATH="$MOUNT_DIRECTORY/Textify.app"
require_embedded_source_commit "$MOUNTED_APP_PATH" "$SOURCE_COMMIT"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$MOUNTED_APP_PATH/Contents/Info.plist")" == "Textify Unsigned Preview $PREVIEW_NUMBER" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :TextifyReleaseChannel' "$MOUNTED_APP_PATH/Contents/Info.plist")" == "unsigned-preview.$PREVIEW_NUMBER" ]]
codesign --verify --deep --strict --verbose=2 "$MOUNTED_APP_PATH"
MOUNTED_SIGNING_DETAILS="$(codesign --display --verbose=4 "$MOUNTED_APP_PATH" 2>&1)"
grep -Fqx 'Signature=adhoc' <<<"$MOUNTED_SIGNING_DETAILS"

hdiutil detach "$MOUNT_DIRECTORY" -quiet
MOUNTED=false
rmdir "$MOUNT_DIRECTORY"
trap cleanup EXIT

require_clean_head_at_commit "$SOURCE_COMMIT"
mv "$TEMPORARY_DMG_PATH" "$DMG_PATH"
(
  cd "$BUILD_DIR"
  shasum -a 256 "$DMG_NAME" >"$DMG_NAME.sha256"
  shasum -a 256 -c "$DMG_NAME.sha256"
)
require_clean_head_at_commit "$SOURCE_COMMIT"
REMOTE_MASTER_COMMIT="$(
  git -C "$REPO_ROOT" ls-remote --exit-code origin refs/heads/master \
    | awk '{print $1}'
)"
require_release_commit "$REMOTE_MASTER_COMMIT"
[[ "$REMOTE_MASTER_COMMIT" == "$SOURCE_COMMIT" ]]

OUTPUTS_COMPLETE=true
cleanup
trap - EXIT

printf 'Created unsigned preview from source commit %s\n' "$SOURCE_COMMIT"
printf 'DMG: %s\n' "$DMG_PATH"
printf 'Checksum: %s\n' "$CHECKSUM_PATH"
printf 'Expected tag: v%s\n' "$PREVIEW_VERSION"
