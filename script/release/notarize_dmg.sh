#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_NOTARY_PROFILE:?Set TEXTIFY_NOTARY_PROFILE}"

DMG_PATH="${1:?Usage: notarize_dmg.sh path/to/Textify.dmg}"
CHECKSUM_PATH="$DMG_PATH.sha256"
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DMG_FILENAME="$(basename "$DMG_PATH")"
if [[ "$DMG_FILENAME" =~ ^Textify-(.+)-arm64\.dmg$ ]]; then
  EXPECTED_VERSION="${BASH_REMATCH[1]}"
else
  echo "Unexpected Textify DMG filename: $DMG_FILENAME" >&2
  exit 1
fi

rm -f "$CHECKSUM_PATH"

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$TEXTIFY_NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"

MOUNT_DIRECTORY="$(mktemp -d)"
cleanup_mount() {
  hdiutil detach "$MOUNT_DIRECTORY" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIRECTORY" >/dev/null 2>&1 || true
}
trap cleanup_mount EXIT
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIRECTORY" -quiet
"$SCRIPT_DIRECTORY/verify_release_artifact.sh" \
  "$MOUNT_DIRECTORY/Textify.app" \
  "$EXPECTED_VERSION" \
  --gatekeeper
cleanup_mount
trap - EXIT

shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"
shasum -a 256 -c "$CHECKSUM_PATH"
