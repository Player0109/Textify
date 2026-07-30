#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_NOTARY_PROFILE:?Set TEXTIFY_NOTARY_PROFILE}"
: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"
: "${TEXTIFY_SIGNING_IDENTITY:?Set TEXTIFY_SIGNING_IDENTITY}"

DMG_PATH="${1:?Usage: notarize_dmg.sh path/to/Textify.dmg}"
CHECKSUM_PATH="$DMG_PATH.sha256"
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DMG_FILENAME="$(basename "$DMG_PATH")"
DMG_DIRECTORY="$(cd "$(dirname "$DMG_PATH")" && pwd)"
if [[ "$DMG_FILENAME" =~ ^Textify-(.+)-arm64\.dmg$ ]]; then
  EXPECTED_VERSION="${BASH_REMATCH[1]}"
else
  echo "Unexpected Textify DMG filename: $DMG_FILENAME" >&2
  exit 1
fi

rm -f "$CHECKSUM_PATH"

codesign --force \
  --sign "$TEXTIFY_SIGNING_IDENTITY" \
  --timestamp \
  "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"
DMG_SIGNING_DETAILS="$(codesign --display --verbose=4 "$DMG_PATH" 2>&1)"
grep -Fqx "TeamIdentifier=$TEXTIFY_DEVELOPMENT_TEAM" <<<"$DMG_SIGNING_DETAILS"
grep -Fqx "Authority=$TEXTIFY_SIGNING_IDENTITY" <<<"$DMG_SIGNING_DETAILS"

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

(
  cd "$DMG_DIRECTORY"
  shasum -a 256 "$DMG_FILENAME" > "$DMG_FILENAME.sha256"
  shasum -a 256 -c "$DMG_FILENAME.sha256"
)
