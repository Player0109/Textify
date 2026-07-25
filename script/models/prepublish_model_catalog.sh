#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: script/models/prepublish_model_catalog.sh \
  [--bootstrap] \
  <manifest.json> <manifest.json.sig> \
  <revocations.json> <revocations.json.sig> \
  <candidate.app> <evidence.json> <previous-evidence.json>

Verifies the exact signed v3 catalog and sticky revocation input, validates
production metadata and monotonic revisions, and writes reviewable publication
evidence. Signers must be in the candidate source's embedded production trust
table, and build identity is derived from the candidate app's Info.plist and
executable digest after its code signature passes strict verification.
Normal publication requires retained prior evidence. Use --bootstrap without
previous evidence only once, for the audited initial v3 authority baseline.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

bootstrap=0
if [[ "${1:-}" == "--bootstrap" ]]; then
  bootstrap=1
  shift
fi

if [[ "$bootstrap" == 1 && "$#" != 6 ]] \
  || [[ "$bootstrap" == 0 && "$#" != 7 ]]; then
  usage
  exit 2
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
arguments=(
  "$1"
  "$2"
  "$3"
  "$4"
  "$5"
  "$6"
)
if [[ "$bootstrap" == 1 ]]; then
  arguments=("--bootstrap" "${arguments[@]}")
else
  arguments+=("$7")
fi

swift run \
  --package-path "$root_dir" \
  --quiet \
  TextifyCatalogPublicationVerifier \
  "${arguments[@]}"
