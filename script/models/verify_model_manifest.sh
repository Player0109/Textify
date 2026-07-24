#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64:?public key required}"

usage() {
  cat >&2 <<'USAGE'
Usage: script/models/verify_model_manifest.sh [manifest.json] [manifest.json.sig]

Verifies the detached Textify model-manifest Ed25519 signature and the signed
production catalog policy. Set TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64 to the
base64-encoded CryptoKit raw public key representation. Optionally set
TEXTIFY_MODEL_MANIFEST_KEY_ID to require a specific signature key id.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

manifest_path="${1:-manifest.json}"
signature_path="${2:-${manifest_path}.sig}"

if [[ ! -f "$manifest_path" ]]; then
  echo "error: manifest not found: $manifest_path" >&2
  exit 1
fi

if [[ ! -f "$signature_path" ]]; then
  echo "error: signature not found: $signature_path" >&2
  exit 1
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
swift run \
  --package-path "$root_dir" \
  --quiet \
  TextifyModelManifestVerifier \
  "$manifest_path" \
  "$signature_path"
