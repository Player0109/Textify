#!/usr/bin/env bash
set -euo pipefail

KEY_ID="${1:-${TEXTIFY_MODEL_MANIFEST_KEY_ID:-}}"
KEYCHAIN_SERVICE="${TEXTIFY_MODEL_MANIFEST_KEYCHAIN_SERVICE:-io.github.Player0109.Textify.model-manifest-signing}"

if [[ -z "$KEY_ID" ]]; then
  echo "Usage: create_model_manifest_signing_key.sh key-id" >&2
  exit 1
fi

if private_key="$(security find-generic-password -a "$KEY_ID" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)"; then
  :
else
  key_pair="$(swift - <<'SWIFT'
import CryptoKit

let privateKey = Curve25519.Signing.PrivateKey()
print(privateKey.rawRepresentation.base64EncodedString())
print(privateKey.publicKey.rawRepresentation.base64EncodedString())
SWIFT
)"
  private_key="$(printf '%s\n' "$key_pair" | sed -n '1p')"
  public_key="$(printf '%s\n' "$key_pair" | sed -n '2p')"
  security add-generic-password \
    -a "$KEY_ID" \
    -s "$KEYCHAIN_SERVICE" \
    -w "$private_key" >/dev/null
  unset key_pair
fi

if [[ -z "${public_key:-}" ]]; then
  public_key="$(TEXTIFY_TEMP_PRIVATE_KEY_BASE64="$private_key" swift - <<'SWIFT'
import CryptoKit
import Foundation

guard let encoded = ProcessInfo.processInfo.environment["TEXTIFY_TEMP_PRIVATE_KEY_BASE64"],
      let raw = Data(base64Encoded: encoded),
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
    FileHandle.standardError.write(Data("Stored manifest private key is invalid.\n".utf8))
    exit(1)
}
print(privateKey.publicKey.rawRepresentation.base64EncodedString())
SWIFT
)"
fi

unset private_key
printf 'keyId=%s\n' "$KEY_ID"
printf 'publicKeyBase64=%s\n' "$public_key"
printf 'keychainService=%s\n' "$KEYCHAIN_SERVICE"
