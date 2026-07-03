#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Textify"
BUNDLE_ID="io.github.Player0109.Textify"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
DERIVED_DATA_DIR="$DIST_DIR/DerivedData"
FULL_APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

stage_fast_app() {
  swift build
  BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  cp "$BUILD_BINARY" "$APP_BINARY"
  cp "$RESOURCE_INFO_PLIST" "$INFO_PLIST"
  chmod +x "$APP_BINARY"

  codesign --force --sign - "$APP_BUNDLE" >/dev/null
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

open_full_app() {
  "$ROOT_DIR/script/generate_xcode_project.sh"
  xcodebuild -project "$ROOT_DIR/Textify.xcodeproj" -scheme "$APP_NAME" -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA_DIR" build
  /usr/bin/open -n "$FULL_APP_BUNDLE"
}

stop_app

case "$MODE" in
  run)
    stage_fast_app
    open_app
    ;;
  --debug|debug)
    stage_fast_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stage_fast_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stage_fast_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stage_fast_app
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --full|full)
    open_full_app
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--full]" >&2
    exit 2
    ;;
esac
