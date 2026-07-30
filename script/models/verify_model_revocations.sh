#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: script/models/verify_model_revocations.sh [revocations.json] [revocations.json.sig]

Verifies the detached Textify model-revocations Ed25519 signature, strict
revocation policy, and production embedded key allowlist. Optionally set
TEXTIFY_MODEL_REVOCATION_KEY_ID to require one exact trusted signer.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

revocation_path="${1:-revocations.json}"
signature_path="${2:-${revocation_path}.sig}"

if [[ ! -f "$revocation_path" ]]; then
  echo "error: revocation file not found: $revocation_path" >&2
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
  TextifyModelRevocationVerifier \
  "$revocation_path" \
  "$signature_path"
