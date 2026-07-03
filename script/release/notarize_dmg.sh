#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_NOTARY_PROFILE:?Set TEXTIFY_NOTARY_PROFILE}"

DMG_PATH="${1:?Usage: notarize_dmg.sh path/to/Textify.dmg}"

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$TEXTIFY_NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
