#!/usr/bin/env bash
set -euo pipefail

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
DMG_PATH="$BUILD_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
NOTES_PATH="$REPO_ROOT/docs/release/$TAG.md"
REPOSITORY="Player0109/Textify"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ -f "$DECLARATION_PATH" ]]
[[ -d "$EVIDENCE_ROOT" ]]
[[ -f "$DMG_PATH" && -f "$CHECKSUM_PATH" ]]
[[ -f "$NOTES_PATH" ]]
[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]]

TEMPORARY_DIRECTORY="$(mktemp -d)"
cleanup() {
  rm -rf "$TEMPORARY_DIRECTORY"
}
trap cleanup EXIT

"$REPO_ROOT/script/release/assemble_release_evidence.sh" \
  "$DECLARATION_PATH" \
  "$EVIDENCE_ROOT" \
  "$TEMPORARY_DIRECTORY/release-evidence-bundle.json"

RELEASE_COMMIT="$(jq -er '.releaseCommitSHA' "$DECLARATION_PATH")"
DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
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
[[ "$DMG_SHA256" == "$EVIDENCE_DMG_SHA256" ]]
(
  cd "$BUILD_DIR"
  shasum -a 256 -c "$DMG_NAME.sha256"
)

git -C "$REPO_ROOT" fetch origin master --tags
[[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$RELEASE_COMMIT" ]]
[[ "$(git -C "$REPO_ROOT" rev-parse origin/master)" == "$RELEASE_COMMIT" ]]

if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  [[ "$(git -C "$REPO_ROOT" cat-file -t "$TAG")" == "tag" ]]
  [[ "$(git -C "$REPO_ROOT" rev-list -n 1 "$TAG")" == "$RELEASE_COMMIT" ]]
else
  git -C "$REPO_ROOT" tag -a "$TAG" -m "Textify $VERSION" "$RELEASE_COMMIT"
fi

git -C "$REPO_ROOT" push origin "refs/tags/$TAG"
if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
  echo "GitHub Release already exists for $TAG" >&2
  exit 1
fi
gh release create "$TAG" \
  "$DMG_PATH" \
  "$CHECKSUM_PATH" \
  --repo "$REPOSITORY" \
  --title "Textify $VERSION" \
  --notes-file "$NOTES_PATH" \
  --verify-tag \
  --draft
[[ "$(
  gh api "repos/$REPOSITORY/releases/tags/$TAG" --jq '.draft'
)" == "true" ]]

trap - EXIT
rm -rf "$TEMPORARY_DIRECTORY"
echo "Created verified draft GitHub Release $TAG"
