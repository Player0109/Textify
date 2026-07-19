#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.1.0}"
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DMG_PATH="$BUILD_DIR/Textify-$VERSION-arm64.dmg"
STAGING="$BUILD_DIR/dmg-staging"
"$REPO_ROOT/script/release/verify_release_artifact.sh" "$APP_PATH" "$VERSION"
rm -rf "$STAGING" "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/Textify.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Textify $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

MOUNT_DIRECTORY="$(mktemp -d)"
cleanup_mount() {
  hdiutil detach "$MOUNT_DIRECTORY" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIRECTORY" >/dev/null 2>&1 || true
}
trap cleanup_mount EXIT
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIRECTORY" -quiet
"$REPO_ROOT/script/release/verify_release_artifact.sh" "$MOUNT_DIRECTORY/Textify.app" "$VERSION"
cleanup_mount
trap - EXIT
