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
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
WHISPER_RESOURCE_BUNDLE_NAME="Textify_WhisperCppVendor.bundle"
METAL_LIBRARY="$APP_RESOURCES/default.metallib"
MODEL_CATALOG_DIRECTORY="$APP_RESOURCES/ModelCatalog"
MODEL_CATALOG_MANIFEST="$MODEL_CATALOG_DIRECTORY/manifest.json"
MODEL_CATALOG_SIGNATURE="$MODEL_CATALOG_DIRECTORY/manifest.json.sig"
MODEL_CATALOG_KEY_ID="textify-model-manifest-2026-huggingface"
MODEL_CATALOG_PUBLIC_KEY_BASE64="eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="
DERIVED_DATA_DIR="$DIST_DIR/DerivedData"
FULL_APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
FULL_RELEASE_APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME.app"

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

stage_fast_app() {
  BUILD_CONFIGURATION="${1:-debug}"
  BUILD_ARGUMENTS=()
  if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
    BUILD_ARGUMENTS=(-c release --arch arm64)
  fi

  swift build "${BUILD_ARGUMENTS[@]}"
  BUILD_BIN_DIR="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"
  BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"
  BUILD_RESOURCE_BUNDLE="$BUILD_BIN_DIR/$WHISPER_RESOURCE_BUNDLE_NAME"

  if [[ ! -d "$BUILD_RESOURCE_BUNDLE" ]]; then
    echo "missing SwiftPM resource bundle: $BUILD_RESOURCE_BUNDLE" >&2
    exit 1
  fi

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS" "$MODEL_CATALOG_DIRECTORY"
  cp "$BUILD_BINARY" "$APP_BINARY"
  cp "$RESOURCE_INFO_PLIST" "$INFO_PLIST"
  cp "$ROOT_DIR/ACKNOWLEDGMENTS.md" "$APP_RESOURCES/ACKNOWLEDGMENTS.md"
  cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/FluidAudio.txt" "$APP_RESOURCES/FluidAudio.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/whisper.cpp.txt" "$APP_RESOURCES/whisper.cpp.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/sherpa-onnx.txt" "$APP_RESOURCES/sherpa-onnx.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/ONNX_Runtime.txt" "$APP_RESOURCES/ONNX_Runtime.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/FunASR_Model_License_1.1.txt" "$APP_RESOURCES/FunASR_Model_License_1.1.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/transcribe.cpp.txt" "$APP_RESOURCES/transcribe.cpp.txt"
  cp "$ROOT_DIR/models/manifest.json" "$MODEL_CATALOG_MANIFEST"
  cp "$ROOT_DIR/models/manifest.json.sig" "$MODEL_CATALOG_SIGNATURE"
  /usr/bin/ditto "$BUILD_RESOURCE_BUNDLE" "$APP_RESOURCES/$WHISPER_RESOURCE_BUNDLE_NAME"
  "$ROOT_DIR/script/build_whisper_metallib.sh" "$METAL_LIBRARY"
  "$ROOT_DIR/script/runtime/embed_sherpa_runtime.sh" "$APP_FRAMEWORKS" -
  "$ROOT_DIR/script/runtime/embed_transcribe_cpp_runtime.sh" "$APP_FRAMEWORKS" -
  chmod +x "$APP_BINARY"

  codesign --force --sign - "$APP_BUNDLE" >/dev/null
  verify_staged_app
}

verify_staged_app() {
  if [[ ! -s "$METAL_LIBRARY" ]] || ! /usr/bin/file "$METAL_LIBRARY" | /usr/bin/grep -q "MetalLib executable"; then
    echo "staged app is missing a valid Metal library: $METAL_LIBRARY" >&2
    exit 1
  fi

  codesign --verify --deep --strict "$APP_BUNDLE"
  [[ -s "$APP_RESOURCES/ACKNOWLEDGMENTS.md" ]]
  [[ -s "$APP_RESOURCES/THIRD_PARTY_NOTICES.md" ]]
  [[ -s "$APP_RESOURCES/FluidAudio.txt" ]]
  [[ -s "$APP_RESOURCES/whisper.cpp.txt" ]]
  [[ -s "$APP_RESOURCES/sherpa-onnx.txt" ]]
  [[ -s "$APP_RESOURCES/ONNX_Runtime.txt" ]]
  [[ -s "$APP_RESOURCES/FunASR_Model_License_1.1.txt" ]]
  [[ -s "$APP_RESOURCES/transcribe.cpp.txt" ]]
  [[ "$(lipo -archs "$APP_FRAMEWORKS/libsherpa-onnx-c-api.dylib")" == "arm64" ]]
  [[ "$(lipo -archs "$APP_FRAMEWORKS/libonnxruntime.1.24.4.dylib")" == "arm64" ]]
  [[ "$(lipo -archs "$APP_FRAMEWORKS/libtextify-transcribe.0.1.3.dylib")" == "arm64" ]]
  codesign --verify --strict "$APP_FRAMEWORKS/libsherpa-onnx-c-api.dylib"
  codesign --verify --strict "$APP_FRAMEWORKS/libonnxruntime.1.24.4.dylib"
  codesign --verify --strict "$APP_FRAMEWORKS/libtextify-transcribe.0.1.3.dylib"
  TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64="$MODEL_CATALOG_PUBLIC_KEY_BASE64" \
    TEXTIFY_MODEL_MANIFEST_KEY_ID="$MODEL_CATALOG_KEY_ID" \
    "$ROOT_DIR/script/models/verify_model_manifest.sh" \
      "$MODEL_CATALOG_MANIFEST" \
      "$MODEL_CATALOG_SIGNATURE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

open_full_app() {
  "$ROOT_DIR/script/generate_xcode_project.sh"
  xcodebuild -project "$ROOT_DIR/Textify.xcodeproj" -scheme "$APP_NAME" -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA_DIR" build
  /usr/bin/open -n "$FULL_APP_BUNDLE"
}

stage_full_release_app() {
  "$ROOT_DIR/script/generate_xcode_project.sh"
  xcodebuild -project "$ROOT_DIR/Textify.xcodeproj" -scheme "$APP_NAME" -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA_DIR" build
  [[ -d "$FULL_RELEASE_APP_BUNDLE" ]]
  rm -rf "$APP_BUNDLE"
  /usr/bin/ditto "$FULL_RELEASE_APP_BUNDLE" "$APP_BUNDLE"
  verify_staged_app
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
  --release|release)
    stage_fast_app release
    open_app
    ;;
  --full|full)
    open_full_app
    ;;
  --stage-full-release|stage-full-release)
    stage_full_release_app
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--release|--full|--stage-full-release]" >&2
    exit 2
    ;;
esac
