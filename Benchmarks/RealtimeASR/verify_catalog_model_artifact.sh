#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "Usage: $0 MODEL_MANIFEST MODEL_ID ARTIFACT_DIRECTORY" >&2
  exit 2
fi

MODEL_MANIFEST="$1"
MODEL_ID="$2"
ARTIFACT_DIRECTORY="$3"

if [[ ! -f "$MODEL_MANIFEST" ]]; then
  echo "Model manifest does not exist: $MODEL_MANIFEST" >&2
  exit 1
fi
if [[ ! -d "$ARTIFACT_DIRECTORY" ]]; then
  echo "Artifact directory does not exist: $ARTIFACT_DIRECTORY" >&2
  exit 1
fi

model_count="$(/usr/bin/jq --arg model_id "$MODEL_ID" '[.models[] | select(.id == $model_id)] | length' "$MODEL_MANIFEST")"
if [[ "$model_count" -ne 1 ]]; then
  echo "Expected exactly one catalog model with id '$MODEL_ID'; found $model_count." >&2
  exit 1
fi

fingerprint_input="$(/usr/bin/mktemp -t textify-catalog-artifact.XXXXXX)"
trap 'rm -f "$fingerprint_input"' EXIT

while IFS=$'\t' read -r relative_path expected_sha256 expected_size; do
  if [[ -z "$relative_path" || "$relative_path" == /* || "$relative_path" == ".." || "$relative_path" == ../* || "$relative_path" == */../* || "$relative_path" == */.. ]]; then
    echo "Unsafe catalog artifact path: $relative_path" >&2
    exit 1
  fi
  artifact="$ARTIFACT_DIRECTORY/$relative_path"
  if [[ ! -f "$artifact" ]]; then
    echo "Catalog artifact is missing: $artifact" >&2
    exit 1
  fi
  actual_size="$(/usr/bin/stat -f '%z' "$artifact")"
  if [[ "$actual_size" != "$expected_size" ]]; then
    echo "Catalog artifact size mismatch for $relative_path: expected $expected_size, found $actual_size." >&2
    exit 1
  fi
  actual_sha256="$(/usr/bin/shasum -a 256 "$artifact" | /usr/bin/awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Catalog artifact SHA-256 mismatch for $relative_path." >&2
    exit 1
  fi
  /usr/bin/printf '%s\t%s\t%s\n' "$relative_path" "$expected_sha256" "$expected_size" >> "$fingerprint_input"
done < <(
  /usr/bin/jq -r --arg model_id "$MODEL_ID" '
    .models[]
    | select(.id == $model_id)
    | .files
    | sort_by(.relativePath // .filename)
    | .[]
    | [(.relativePath // .filename), .sha256, (.sizeBytes | tostring)]
    | @tsv
  ' "$MODEL_MANIFEST"
)

if [[ ! -s "$fingerprint_input" ]]; then
  echo "Catalog model has no declared artifacts: $MODEL_ID" >&2
  exit 1
fi

/usr/bin/shasum -a 256 "$fingerprint_input" | /usr/bin/awk '{print $1}'
