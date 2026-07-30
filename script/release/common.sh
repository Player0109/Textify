#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Textify.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Textify.app"
ARCHIVE_COMMIT_PATH="$ARCHIVE_PATH/.textify-source-commit"
EXPORT_COMMIT_PATH="$EXPORT_PATH/.textify-source-commit"
ARCHIVED_APP_PATH="$ARCHIVE_PATH/Products/Applications/Textify.app"
SOURCE_COMMIT_PLIST_KEY="TextifySourceCommit"

require_release_commit() {
  local source_commit="${1:-}"
  if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Expected a lowercase 40-character source commit, got: $source_commit" >&2
    return 1
  fi
}

require_clean_source_tree() {
  local source_status
  source_status="$(
    git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all
  )"
  if [[ -n "$source_status" ]]; then
    echo "Release operations require a clean tracked and untracked source tree." >&2
    printf '%s\n' "$source_status" >&2
    return 1
  fi
}

require_clean_head_at_commit() {
  local expected_commit="$1"
  local current_commit
  require_release_commit "$expected_commit"
  current_commit="$(git -C "$REPO_ROOT" rev-parse --verify HEAD)"
  if [[ "$current_commit" != "$expected_commit" ]]; then
    echo "Current HEAD $current_commit does not match release source $expected_commit." >&2
    return 1
  fi
  require_clean_source_tree
}

require_manual_release_qa_complete() {
  local manual_qa_path="$REPO_ROOT/docs/MANUAL_QA.md"
  local unchecked_items
  local unresolved_blockers
  [[ -f "$manual_qa_path" && ! -L "$manual_qa_path" ]]
  if ! grep -Fqx \
    "## Known Specification-Conformance Blockers" \
    "$manual_qa_path"; then
    echo "MANUAL_QA.md is missing the specification-conformance blocker section." >&2
    return 1
  fi
  unchecked_items="$(
    grep -nE '^[[:space:]]*- \[ \]' "$manual_qa_path" || true
  )"
  unresolved_blockers="$(
    awk '
      /^## Known Specification-Conformance Blockers[[:space:]]*$/ {
        in_blocker_section = 1
        next
      }
      in_blocker_section && /^##[[:space:]]/ {
        exit
      }
      in_blocker_section && /^[[:space:]]*- BLOCKED:/ {
        print NR ":" $0
      }
    ' "$manual_qa_path"
  )"
  if [[ -n "$unchecked_items" || -n "$unresolved_blockers" ]]; then
    echo "Manual QA and specification blockers must be resolved before app publication." >&2
    if [[ -n "$unchecked_items" ]]; then
      printf '%s\n' "$unchecked_items" >&2
    fi
    if [[ -n "$unresolved_blockers" ]]; then
      printf '%s\n' "$unresolved_blockers" >&2
    fi
    return 1
  fi
}

embedded_source_commit() {
  local app_path="$1"
  local info_plist="$app_path/Contents/Info.plist"
  [[ -d "$app_path" && ! -L "$app_path" ]]
  [[ -f "$info_plist" && ! -L "$info_plist" ]]
  /usr/libexec/PlistBuddy \
    -c "Print :$SOURCE_COMMIT_PLIST_KEY" \
    "$info_plist"
}

require_embedded_source_commit() {
  local app_path="$1"
  local expected_commit="$2"
  local actual_commit
  require_release_commit "$expected_commit"
  actual_commit="$(embedded_source_commit "$app_path")"
  require_release_commit "$actual_commit"
  if [[ "$actual_commit" != "$expected_commit" ]]; then
    echo "Signed app source $actual_commit does not match expected commit $expected_commit." >&2
    return 1
  fi
}

ensure_xcode_project() {
  cd "$REPO_ROOT"
  local project_file="$REPO_ROOT/Textify.xcodeproj/project.pbxproj"
  local checksum_before=""
  if [[ -f "$project_file" ]]; then
    checksum_before="$(shasum -a 256 "$project_file" | awk '{print $1}')"
  fi
  "$REPO_ROOT/script/generate_xcode_project.sh"
  if [[ -n "$checksum_before" ]]; then
    local checksum_after
    checksum_after="$(shasum -a 256 "$project_file" | awk '{print $1}')"
    if [[ "$checksum_before" != "$checksum_after" ]]; then
      echo "Textify.xcodeproj was stale and has been regenerated. Review it, then rerun the release command." >&2
      exit 1
    fi
  fi
}
