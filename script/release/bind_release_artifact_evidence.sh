#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <declaration.json> <evidence-root> <release-artifact>" >&2
  exit 2
fi

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DECLARATION_PATH="$1"
EVIDENCE_ROOT="$2"
ARTIFACT_PATH="$3"

[[ -f "$DECLARATION_PATH" && ! -L "$DECLARATION_PATH" ]]
[[ -d "$EVIDENCE_ROOT" && ! -L "$EVIDENCE_ROOT" ]]
[[ -f "$ARTIFACT_PATH" && ! -L "$ARTIFACT_PATH" ]]

DECLARATION_PATH="$(
  cd "$(dirname "$DECLARATION_PATH")"
  printf '%s/%s\n' "$PWD" "$(basename "$DECLARATION_PATH")"
)"
EVIDENCE_ROOT="$(cd "$EVIDENCE_ROOT" && pwd)"
ARTIFACT_PATH="$(
  cd "$(dirname "$ARTIFACT_PATH")"
  printf '%s/%s\n' "$PWD" "$(basename "$ARTIFACT_PATH")"
)"

if [[ "$(dirname "$DECLARATION_PATH")" != "$EVIDENCE_ROOT" ]]; then
  echo "declaration must be directly inside the evidence root" >&2
  exit 1
fi

ARTIFACT_NAME="$(basename "$ARTIFACT_PATH")"
if [[ ! "$ARTIFACT_NAME" =~ ^Textify-[0-9]+\.[0-9]+\.[0-9]+-arm64\.dmg$ ]]; then
  echo "unexpected release artifact name: $ARTIFACT_NAME" >&2
  exit 1
fi

RELEASE_COMMIT="$(jq -er '.releaseCommitSHA' "$DECLARATION_PATH")"
require_clean_head_at_commit "$RELEASE_COMMIT"
"$REPO_ROOT/script/release/verify_artifact_source_commit.sh" \
  "$ARTIFACT_PATH" \
  "$RELEASE_COMMIT"
require_clean_head_at_commit "$RELEASE_COMMIT"

ARTIFACT_SHA256="$(shasum -a 256 "$ARTIFACT_PATH" | awk '{print $1}')"
ARTIFACT_DIRECTORY="$EVIDENCE_ROOT/artifacts"
[[ ! -L "$ARTIFACT_DIRECTORY" ]]
mkdir -p "$ARTIFACT_DIRECTORY"
RETAINED_RELATIVE_PATH="artifacts/$ARTIFACT_NAME"
RETAINED_PATH="$EVIDENCE_ROOT/$RETAINED_RELATIVE_PATH"
TEMPORARY_ARTIFACT="$(mktemp "$ARTIFACT_DIRECTORY/.release-artifact.XXXXXX")"
TEMPORARY_DECLARATION="$(mktemp "$EVIDENCE_ROOT/.declaration.XXXXXX")"

cleanup() {
  rm -f "$TEMPORARY_ARTIFACT" "$TEMPORARY_DECLARATION"
}
trap cleanup EXIT

cp "$ARTIFACT_PATH" "$TEMPORARY_ARTIFACT"
if [[ "$(shasum -a 256 "$TEMPORARY_ARTIFACT" | awk '{print $1}')" != "$ARTIFACT_SHA256" ]]; then
  echo "retained release artifact hash mismatch" >&2
  exit 1
fi
mv "$TEMPORARY_ARTIFACT" "$RETAINED_PATH"

jq \
  --arg id "release-dmg" \
  --arg relativePath "$RETAINED_RELATIVE_PATH" \
  --arg name "$ARTIFACT_NAME" \
  --arg sha256 "$ARTIFACT_SHA256" \
  '
    .attachments = (
      [.attachments[] | select(.id != $id)]
      + [{
          id: $id,
          relativePath: $relativePath,
          sha256: $sha256,
          kind: "automated",
          categories: []
        }]
    )
    | .buildArtifacts = (
      [.buildArtifacts[] | select(.attachmentID != $id)]
      + [{
          name: $name,
          sha256: $sha256,
          attachmentID: $id
        }]
    )
  ' \
  "$DECLARATION_PATH" > "$TEMPORARY_DECLARATION"
jq -e 'type == "object"' "$TEMPORARY_DECLARATION" >/dev/null
require_clean_head_at_commit "$RELEASE_COMMIT"
mv "$TEMPORARY_DECLARATION" "$DECLARATION_PATH"

trap - EXIT
printf 'Bound %s at sha256:%s\n' "$ARTIFACT_NAME" "$ARTIFACT_SHA256"
