#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"
: "${TEXTIFY_SIGNING_IDENTITY:?Set TEXTIFY_SIGNING_IDENTITY}"

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <version> <declaration.json> <evidence-root>" >&2
  exit 2
fi

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

VERSION="$1"
DECLARATION_PATH="$2"
EVIDENCE_ROOT="$3"
TAG="v$VERSION"
DMG_NAME="Textify-$VERSION-arm64.dmg"
LOCAL_DMG_PATH="$BUILD_DIR/$DMG_NAME"
LOCAL_CHECKSUM_PATH="$LOCAL_DMG_PATH.sha256"
REPOSITORY="Player0109/Textify"

require_exact_draft_assets() {
  local actual_assets
  local expected_assets
  actual_assets="$(
    gh api \
      "repos/$REPOSITORY/releases/tags/$TAG" \
      --jq '[.assets[].name] | sort'
  )"
  expected_assets="$(
    jq -cn \
      --arg dmg "$DMG_NAME" \
      '[$dmg, ($dmg + ".sha256")] | sort'
  )"
  if [[ "$actual_assets" != "$expected_assets" ]]; then
    echo "Draft release assets do not match the exact production allowlist." >&2
    printf 'expected: %s\nactual:   %s\n' "$expected_assets" "$actual_assets" >&2
    return 1
  fi
}

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ -f "$DECLARATION_PATH" ]]
[[ -d "$EVIDENCE_ROOT" ]]
[[ -f "$LOCAL_DMG_PATH" && -f "$LOCAL_CHECKSUM_PATH" ]]
require_clean_source_tree
require_manual_release_qa_complete

TEMPORARY_DIRECTORY="$(mktemp -d)"
MOUNT_DIRECTORY="$TEMPORARY_DIRECTORY/mount"
mkdir "$MOUNT_DIRECTORY"
MOUNTED=false
cleanup() {
  if [[ "$MOUNTED" == true ]]; then
    hdiutil detach "$MOUNT_DIRECTORY" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMPORARY_DIRECTORY"
}
trap cleanup EXIT

"$REPO_ROOT/script/release/assemble_release_evidence.sh" \
  "$DECLARATION_PATH" \
  "$EVIDENCE_ROOT" \
  "$TEMPORARY_DIRECTORY/release-evidence-bundle.json"

RELEASE_COMMIT="$(jq -er '.releaseCommitSHA' "$DECLARATION_PATH")"
require_clean_head_at_commit "$RELEASE_COMMIT"
"$REPO_ROOT/script/release/verify_artifact_source_commit.sh" \
  "$LOCAL_DMG_PATH" \
  "$RELEASE_COMMIT"
require_clean_head_at_commit "$RELEASE_COMMIT"
LOCAL_DMG_SHA256="$(
  shasum -a 256 "$LOCAL_DMG_PATH" | awk '{print $1}'
)"
EVIDENCE_DMG_SHA256="$(
  jq -er \
    --arg name "$DMG_NAME" \
    '
      [.buildArtifacts[] | select(.name == $name)]
      | if length == 1 then .[0].sha256
        else error("evidence must name exactly one release DMG")
        end
    ' \
    "$DECLARATION_PATH"
)"
[[ "$LOCAL_DMG_SHA256" == "$EVIDENCE_DMG_SHA256" ]]
(
  cd "$BUILD_DIR"
  shasum -a 256 -c "$DMG_NAME.sha256"
)

PUBLICATION_ATTACHMENT_ID="$(
  jq -er '.catalogIdentity.publicationEvidenceAttachmentID' \
    "$DECLARATION_PATH"
)"
PUBLICATION_RELATIVE_PATH="$(
  jq -er \
    --arg id "$PUBLICATION_ATTACHMENT_ID" \
    '
      [.attachments[] | select(.id == $id)]
      | if length == 1 then .[0].relativePath
        else error("publication evidence attachment is not unique")
        end
    ' \
    "$DECLARATION_PATH"
)"
EVIDENCE_EXECUTABLE_SHA256="$(
  jq -er '.buildIdentity.executableSHA256' \
    "$EVIDENCE_ROOT/$PUBLICATION_RELATIVE_PATH"
)"

git -C "$REPO_ROOT" fetch origin master --tags
require_clean_head_at_commit "$RELEASE_COMMIT"
[[ "$(git -C "$REPO_ROOT" rev-parse origin/master)" == "$RELEASE_COMMIT" ]]
[[ "$(git -C "$REPO_ROOT" cat-file -t "$TAG")" == "tag" ]]
[[ "$(git -C "$REPO_ROOT" rev-list -n 1 "$TAG")" == "$RELEASE_COMMIT" ]]
[[ "$(
  gh api "repos/$REPOSITORY/releases/tags/$TAG" --jq '.draft'
)" == "true" ]]
require_exact_draft_assets

DOWNLOAD_DIRECTORY="$TEMPORARY_DIRECTORY/download"
mkdir "$DOWNLOAD_DIRECTORY"
gh release download "$TAG" \
  --repo "$REPOSITORY" \
  --dir "$DOWNLOAD_DIRECTORY" \
  --pattern "$DMG_NAME*"
DOWNLOADED_DMG_PATH="$DOWNLOAD_DIRECTORY/$DMG_NAME"
DOWNLOADED_CHECKSUM_PATH="$DOWNLOADED_DMG_PATH.sha256"
[[ -f "$DOWNLOADED_DMG_PATH" && -f "$DOWNLOADED_CHECKSUM_PATH" ]]
[[ "$(
  shasum -a 256 "$DOWNLOADED_DMG_PATH" | awk '{print $1}'
)" == "$EVIDENCE_DMG_SHA256" ]]
[[ "$(awk '{print $1}' "$DOWNLOADED_CHECKSUM_PATH")" == "$EVIDENCE_DMG_SHA256" ]]
(
  cd "$DOWNLOAD_DIRECTORY"
  shasum -a 256 -c "$DMG_NAME.sha256"
)
xcrun stapler validate "$DOWNLOADED_DMG_PATH"
spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose \
  "$DOWNLOADED_DMG_PATH"
DMG_SIGNING_DETAILS="$(
  codesign --display --verbose=4 "$DOWNLOADED_DMG_PATH" 2>&1
)"
grep -Fqx \
  "TeamIdentifier=$TEXTIFY_DEVELOPMENT_TEAM" \
  <<<"$DMG_SIGNING_DETAILS"
grep -Fqx \
  "Authority=$TEXTIFY_SIGNING_IDENTITY" \
  <<<"$DMG_SIGNING_DETAILS"
"$REPO_ROOT/script/release/verify_artifact_source_commit.sh" \
  "$DOWNLOADED_DMG_PATH" \
  "$RELEASE_COMMIT"

hdiutil attach \
  "$DOWNLOADED_DMG_PATH" \
  -nobrowse \
  -readonly \
  -mountpoint "$MOUNT_DIRECTORY" \
  -quiet
MOUNTED=true
TEXTIFY_EXPECTED_SOURCE_COMMIT="$RELEASE_COMMIT" \
  "$REPO_ROOT/script/release/verify_release_artifact.sh" \
    "$MOUNT_DIRECTORY/Textify.app" \
    "$VERSION" \
    --gatekeeper
[[ "$(
  shasum -a 256 \
    "$MOUNT_DIRECTORY/Textify.app/Contents/MacOS/Textify" \
    | awk '{print $1}'
)" == "$EVIDENCE_EXECUTABLE_SHA256" ]]
hdiutil detach "$MOUNT_DIRECTORY" -quiet
MOUNTED=false

require_clean_head_at_commit "$RELEASE_COMMIT"
[[ "$(git -C "$REPO_ROOT" rev-list -n 1 "$TAG")" == "$RELEASE_COMMIT" ]]
require_exact_draft_assets
gh release edit "$TAG" \
  --repo "$REPOSITORY" \
  --draft=false \
  --latest
[[ "$(
  gh api "repos/$REPOSITORY/releases/tags/$TAG" --jq '.draft'
)" == "false" ]]
[[ "$(
  gh api "repos/$REPOSITORY/releases/latest" --jq '.tag_name'
)" == "$TAG" ]]
require_clean_head_at_commit "$RELEASE_COMMIT"

trap - EXIT
rm -rf "$TEMPORARY_DIRECTORY"
echo "Published verified GitHub Release $TAG"
