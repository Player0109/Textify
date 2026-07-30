#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.1.0}"
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DMG_PATH="$BUILD_DIR/Textify-$VERSION-arm64.dmg"
TEMPORARY_DMG_PATH="$BUILD_DIR/.Textify-$VERSION-arm64.dmg.in-progress"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
rm -f "$DMG_PATH" "$DMG_PATH.sha256" "$TEMPORARY_DMG_PATH"
[[ -f "$EXPORT_COMMIT_PATH" ]]
[[ "$(<"$EXPORT_COMMIT_PATH")" == "$(git -C "$REPO_ROOT" rev-parse HEAD)" ]]
"$REPO_ROOT/script/release/verify_release_artifact.sh" "$APP_PATH" "$VERSION"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/Textify.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Textify $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$TEMPORARY_DMG_PATH"

MOUNT_DIRECTORY="$(mktemp -d)"
cleanup() {
  hdiutil detach "$MOUNT_DIRECTORY" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIRECTORY" >/dev/null 2>&1 || true
  rm -rf "$STAGING"
  rm -f "$TEMPORARY_DMG_PATH"
}
trap cleanup EXIT
hdiutil attach "$TEMPORARY_DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIRECTORY" -quiet
"$REPO_ROOT/script/release/verify_release_artifact.sh" "$MOUNT_DIRECTORY/Textify.app" "$VERSION"
hdiutil detach "$MOUNT_DIRECTORY" -quiet
rmdir "$MOUNT_DIRECTORY"
mv "$TEMPORARY_DMG_PATH" "$DMG_PATH"
rm -rf "$STAGING"
trap - EXIT
