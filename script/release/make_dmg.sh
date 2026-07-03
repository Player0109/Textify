#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.1.0}"
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DMG_PATH="$BUILD_DIR/Textify-$VERSION-arm64.dmg"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/Textify.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Textify $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
