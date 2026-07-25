#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: script/models/smoke_model_catalog_endpoint.sh \
  <https-catalog-base-url> <candidate.app> \
  <evidence.json> <previous-evidence.json>

Fetches and verifies the staged or production catalog and revocation pairs.
It intentionally does not download model artifacts and is not part of ordinary
CI; run it as a real prepublication endpoint smoke.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" != 4 ]]; then
  usage
  exit 2
fi

base_url="${1%/}"
if [[ ! "$base_url" =~ ^https://[^/?#]+(/[^?#]*)?$ ]]; then
  echo "error: catalog base URL must be an HTTPS URL without query or fragment" >&2
  exit 2
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/textify-catalog-smoke.XXXXXX")"
cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

for filename in \
  manifest.json \
  manifest.json.sig \
  revocations.json \
  revocations.json.sig
do
  curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto '=https' \
    --proto-redir '=https' \
    --tlsv1.2 \
    --output "$temporary_directory/$filename" \
    "$base_url/$filename"
done

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
arguments=(
  "$temporary_directory/manifest.json"
  "$temporary_directory/manifest.json.sig"
  "$temporary_directory/revocations.json"
  "$temporary_directory/revocations.json.sig"
  "$2"
  "$3"
  "$4"
)

TEXTIFY_CATALOG_SOURCE_ENDPOINT="$base_url" \
  "$root_dir/script/models/prepublish_model_catalog.sh" \
  "${arguments[@]}"
