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
ASSET_CATALOG="$ROOT_DIR/Resources/Assets.xcassets"
LOCAL_ENTITLEMENTS="$ROOT_DIR/Textify.Local.entitlements"
WHISPER_RESOURCE_BUNDLE_NAME="Textify_WhisperCppVendor.bundle"
METAL_LIBRARY="$APP_RESOURCES/default.metallib"
MLX_METAL_LIBRARY="$APP_MACOS/mlx.metallib"
LITERT_LM_LIBRARY="$APP_FRAMEWORKS/libCLiteRTLM_mac.dylib"
SWIFT_COMPATIBILITY_LIBRARY="$APP_FRAMEWORKS/libswiftCompatibilitySpan.dylib"
MODEL_CATALOG_DIRECTORY="$APP_RESOURCES/ModelCatalog"
MODEL_CATALOG_MANIFEST="$MODEL_CATALOG_DIRECTORY/manifest.json"
MODEL_CATALOG_SIGNATURE="$MODEL_CATALOG_DIRECTORY/manifest.json.sig"
MODEL_REVOCATION_MANIFEST="$MODEL_CATALOG_DIRECTORY/revocations.json"
MODEL_REVOCATION_SIGNATURE="$MODEL_CATALOG_DIRECTORY/revocations.json.sig"
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
  BUILD_ARGUMENTS=(-c debug)
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
  if ! otool -l "$APP_BINARY" | /usr/bin/grep -Fq '@executable_path/../Frameworks'; then
    /usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BINARY"
  fi
  cp "$RESOURCE_INFO_PLIST" "$INFO_PLIST"
  xcrun actool "$ASSET_CATALOG" \
    --compile "$APP_RESOURCES" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$DIST_DIR/assetcatalog-info.plist" \
    --warnings \
    --notices >/dev/null
  cp "$ROOT_DIR/ACKNOWLEDGMENTS.md" "$APP_RESOURCES/ACKNOWLEDGMENTS.md"
  cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/FluidAudio.txt" "$APP_RESOURCES/FluidAudio.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/whisper.cpp.txt" "$APP_RESOURCES/whisper.cpp.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/sherpa-onnx.txt" "$APP_RESOURCES/sherpa-onnx.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/ONNX_Runtime.txt" "$APP_RESOURCES/ONNX_Runtime.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/FunASR_Model_License_1.1.txt" "$APP_RESOURCES/FunASR_Model_License_1.1.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/transcribe.cpp.txt" "$APP_RESOURCES/transcribe.cpp.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/MLXAudioSwift.txt" "$APP_RESOURCES/MLXAudioSwift.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/MLXSwift.txt" "$APP_RESOURCES/MLXSwift.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/LiteRT-LM.txt" "$APP_RESOURCES/LiteRT-LM.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/CC-BY-4.0.txt" "$APP_RESOURCES/CC-BY-4.0.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/OpenAI-Whisper.txt" "$APP_RESOURCES/OpenAI-Whisper.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/ggml-small.en-q5_1.LICENSES.txt" "$APP_RESOURCES/ggml-small.en-q5_1.LICENSES.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/NVIDIA_Open_Model_License.txt" "$APP_RESOURCES/NVIDIA_Open_Model_License.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/OpenMDW-1.1.txt" "$APP_RESOURCES/OpenMDW-1.1.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/SwiftNIO-NOTICE.txt" "$APP_RESOURCES/SwiftNIO-NOTICE.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/SwiftCrypto-NOTICE.txt" "$APP_RESOURCES/SwiftCrypto-NOTICE.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/FluidAudio-fastcluster.txt" "$APP_RESOURCES/FluidAudio-fastcluster.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/FluidAudio-VBx.txt" "$APP_RESOURCES/FluidAudio-VBx.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/MLXSwift-fmt.txt" "$APP_RESOURCES/MLXSwift-fmt.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/MLXSwift-nlohmann-json.txt" "$APP_RESOURCES/MLXSwift-nlohmann-json.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/MLXSwift-metal-cpp.txt" "$APP_RESOURCES/MLXSwift-metal-cpp.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/MLXSwift-MLX-Core.txt" "$APP_RESOURCES/MLXSwift-MLX-Core.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/transcribe.cpp-ggml.txt" "$APP_RESOURCES/transcribe.cpp-ggml.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/transcribe.cpp-miniz.txt" "$APP_RESOURCES/transcribe.cpp-miniz.txt"
  cp "$ROOT_DIR/THIRD_PARTY_LICENSES/ONNX_Runtime_ThirdPartyNotices.txt" "$APP_RESOURCES/ONNX_Runtime_ThirdPartyNotices.txt"
  cp "$ROOT_DIR/LICENSE" "$APP_RESOURCES/LICENSE"
  cp "$ROOT_DIR/models/manifest.json" "$MODEL_CATALOG_MANIFEST"
  cp "$ROOT_DIR/models/manifest.json.sig" "$MODEL_CATALOG_SIGNATURE"
  cp "$ROOT_DIR/models/revocations.json" "$MODEL_REVOCATION_MANIFEST"
  cp "$ROOT_DIR/models/revocations.json.sig" "$MODEL_REVOCATION_SIGNATURE"
  /usr/bin/ditto "$BUILD_RESOURCE_BUNDLE" "$APP_RESOURCES/$WHISPER_RESOURCE_BUNDLE_NAME"
  "$ROOT_DIR/script/build_whisper_metallib.sh" "$METAL_LIBRARY"
  "$ROOT_DIR/script/runtime/embed_mlx_metallib.sh" "$MLX_METAL_LIBRARY" -
  "$ROOT_DIR/script/runtime/embed_sherpa_runtime.sh" "$APP_FRAMEWORKS" -
  "$ROOT_DIR/script/runtime/embed_transcribe_cpp_runtime.sh" "$APP_FRAMEWORKS" -
  "$ROOT_DIR/script/runtime/embed_litert_lm_runtime.sh" \
    "$BUILD_BIN_DIR/libCLiteRTLM_mac.dylib" "$APP_FRAMEWORKS" -
  chmod +x "$APP_BINARY"

  codesign --force --sign - "$APP_BUNDLE" >/dev/null
  verify_staged_app
  if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
    verify_staged_app_launch
  fi
}

verify_staged_app() {
  local packaged_architectures
  local packaged_file

  if [[ ! -s "$METAL_LIBRARY" ]] || ! /usr/bin/file "$METAL_LIBRARY" | /usr/bin/grep -q "MetalLib executable"; then
    echo "staged app is missing a valid Metal library: $METAL_LIBRARY" >&2
    exit 1
  fi
  if [[ ! -s "$MLX_METAL_LIBRARY" ]] || ! /usr/bin/file "$MLX_METAL_LIBRARY" | /usr/bin/grep -q "MetalLib executable"; then
    echo "staged app is missing a valid MLX Metal library: $MLX_METAL_LIBRARY" >&2
    exit 1
  fi
  codesign --verify --strict "$MLX_METAL_LIBRARY"

  codesign --verify --deep --strict "$APP_BUNDLE"
  [[ -s "$APP_RESOURCES/Assets.car" ]]
  [[ -s "$APP_RESOURCES/ACKNOWLEDGMENTS.md" ]]
  [[ -s "$APP_RESOURCES/THIRD_PARTY_NOTICES.md" ]]
  [[ -s "$APP_RESOURCES/FluidAudio.txt" ]]
  [[ -s "$APP_RESOURCES/whisper.cpp.txt" ]]
  [[ -s "$APP_RESOURCES/sherpa-onnx.txt" ]]
  [[ -s "$APP_RESOURCES/ONNX_Runtime.txt" ]]
  [[ -s "$APP_RESOURCES/FunASR_Model_License_1.1.txt" ]]
  [[ -s "$APP_RESOURCES/transcribe.cpp.txt" ]]
  [[ -s "$APP_RESOURCES/MLXAudioSwift.txt" ]]
  [[ -s "$APP_RESOURCES/MLXSwift.txt" ]]
  [[ -s "$APP_RESOURCES/LiteRT-LM.txt" ]]
  [[ -s "$APP_RESOURCES/CC-BY-4.0.txt" ]]
  [[ -s "$APP_RESOURCES/OpenAI-Whisper.txt" ]]
  [[ -s "$APP_RESOURCES/ggml-small.en-q5_1.LICENSES.txt" ]]
  [[ -s "$APP_RESOURCES/NVIDIA_Open_Model_License.txt" ]]
  [[ -s "$APP_RESOURCES/OpenMDW-1.1.txt" ]]
  [[ -s "$APP_RESOURCES/SwiftNIO-NOTICE.txt" ]]
  [[ -s "$APP_RESOURCES/SwiftCrypto-NOTICE.txt" ]]
  [[ -s "$APP_RESOURCES/FluidAudio-fastcluster.txt" ]]
  [[ -s "$APP_RESOURCES/FluidAudio-VBx.txt" ]]
  [[ -s "$APP_RESOURCES/MLXSwift-fmt.txt" ]]
  [[ -s "$APP_RESOURCES/MLXSwift-nlohmann-json.txt" ]]
  [[ -s "$APP_RESOURCES/MLXSwift-metal-cpp.txt" ]]
  [[ -s "$APP_RESOURCES/MLXSwift-MLX-Core.txt" ]]
  [[ -s "$APP_RESOURCES/transcribe.cpp-ggml.txt" ]]
  [[ -s "$APP_RESOURCES/transcribe.cpp-miniz.txt" ]]
  [[ -s "$APP_RESOURCES/ONNX_Runtime_ThirdPartyNotices.txt" ]]
  [[ -s "$APP_RESOURCES/LICENSE" ]]
  [[ "$(lipo -archs "$APP_FRAMEWORKS/libsherpa-onnx-c-api.dylib")" == "arm64" ]]
  [[ "$(lipo -archs "$APP_FRAMEWORKS/libonnxruntime.1.24.4.dylib")" == "arm64" ]]
  [[ "$(lipo -archs "$APP_FRAMEWORKS/libtextify-transcribe.0.1.3.dylib")" == "arm64" ]]
  [[ "$(lipo -archs "$LITERT_LM_LIBRARY")" == "arm64" ]]
  while IFS= read -r -d '' packaged_file; do
    [[ "$(/usr/bin/file -b "$packaged_file")" == *Mach-O* ]] || continue
    packaged_architectures="$(lipo -archs "$packaged_file")"
    if [[ "$packaged_architectures" != "arm64" ]]; then
      echo "$packaged_file contains unexpected architectures: $packaged_architectures" >&2
      exit 1
    fi
  done < <(find "$APP_CONTENTS" -type f -print0)
  codesign --verify --strict "$APP_FRAMEWORKS/libsherpa-onnx-c-api.dylib"
  codesign --verify --strict "$APP_FRAMEWORKS/libonnxruntime.1.24.4.dylib"
  codesign --verify --strict "$APP_FRAMEWORKS/libtextify-transcribe.0.1.3.dylib"
  codesign --verify --strict "$LITERT_LM_LIBRARY"
  TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64="$MODEL_CATALOG_PUBLIC_KEY_BASE64" \
    TEXTIFY_MODEL_MANIFEST_KEY_ID="$MODEL_CATALOG_KEY_ID" \
    "$ROOT_DIR/script/models/verify_model_manifest.sh" \
      "$MODEL_CATALOG_MANIFEST" \
      "$MODEL_CATALOG_SIGNATURE"
  TEXTIFY_MODEL_REVOCATION_KEY_ID="$MODEL_CATALOG_KEY_ID" \
    "$ROOT_DIR/script/models/verify_model_revocations.sh" \
      "$MODEL_REVOCATION_MANIFEST" \
      "$MODEL_REVOCATION_SIGNATURE"
}

verify_staged_app_launch() {
  local launch_log
  local launch_pid
  local launch_status

  launch_log="$(mktemp -t textify-launch-smoke)"
  "$APP_BINARY" >"$launch_log" 2>&1 &
  launch_pid=$!
  sleep 2

  if ! kill -0 "$launch_pid" >/dev/null 2>&1; then
    if wait "$launch_pid"; then
      launch_status=0
    else
      launch_status=$?
    fi
    echo "staged app exited during launch smoke test with status $launch_status" >&2
    /bin/cat "$launch_log" >&2
    rm -f "$launch_log"
    exit 1
  fi

  kill "$launch_pid" >/dev/null 2>&1 || true
  wait "$launch_pid" >/dev/null 2>&1 || true
  rm -f "$launch_log"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

open_full_app() {
  "$ROOT_DIR/script/generate_xcode_project.sh"
  xcodebuild -project "$ROOT_DIR/Textify.xcodeproj" -scheme "$APP_NAME" -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA_DIR" build
  /usr/bin/open -n "$FULL_APP_BUNDLE"
}

thin_staged_swift_compatibility_library() (
  local temporary_directory

  [[ -s "$SWIFT_COMPATIBILITY_LIBRARY" ]]
  temporary_directory="$(mktemp -d)"
  cleanup_staged_swift_compatibility_library() {
    rm -rf "$temporary_directory"
  }
  trap cleanup_staged_swift_compatibility_library EXIT
  lipo \
    "$SWIFT_COMPATIBILITY_LIBRARY" \
    -thin arm64 \
    -output "$temporary_directory/libswiftCompatibilitySpan.dylib"
  mv \
    "$temporary_directory/libswiftCompatibilitySpan.dylib" \
    "$SWIFT_COMPATIBILITY_LIBRARY"
  codesign \
    --force \
    --sign - \
    --timestamp=none \
    --options runtime \
    "$SWIFT_COMPATIBILITY_LIBRARY"
  codesign \
    --force \
    --sign - \
    --timestamp=none \
    --options runtime \
    --entitlements "$LOCAL_ENTITLEMENTS" \
    "$APP_BUNDLE"
)

stage_full_release_app() {
  local source_commit

  source_commit="${TEXTIFY_SOURCE_COMMIT:-local-development-not-for-release}"
  "$ROOT_DIR/script/generate_xcode_project.sh"
  xcodebuild -project "$ROOT_DIR/Textify.xcodeproj" -scheme "$APP_NAME" -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA_DIR" CODE_SIGN_ENTITLEMENTS="$LOCAL_ENTITLEMENTS" TEXTIFY_SOURCE_COMMIT="$source_commit" build
  [[ -d "$FULL_RELEASE_APP_BUNDLE" ]]
  rm -rf "$APP_BUNDLE"
  /usr/bin/ditto "$FULL_RELEASE_APP_BUNDLE" "$APP_BUNDLE"
  thin_staged_swift_compatibility_library
  verify_staged_app
  verify_staged_app_launch
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
