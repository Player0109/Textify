#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"
: "${TEXTIFY_SIGNING_IDENTITY:?Set TEXTIFY_SIGNING_IDENTITY}"

APP_PATH="${1:?Usage: verify_release_artifact.sh path/to/Textify.app expected-version [--gatekeeper]}"
EXPECTED_VERSION="${2:?Usage: verify_release_artifact.sh path/to/Textify.app expected-version [--gatekeeper]}"
GATEKEEPER_MODE="${3:-}"
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_CATALOG_DIRECTORY="$APP_PATH/Contents/Resources/ModelCatalog"
MODEL_CATALOG_KEY_ID="textify-model-manifest-2026-huggingface"
MODEL_CATALOG_PUBLIC_KEY_BASE64="eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="

[[ -d "$APP_PATH" ]]
INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]]

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

[[ "$(plist_value CFBundleIdentifier)" == "io.github.Player0109.Textify" ]]
[[ "$(plist_value CFBundleShortVersionString)" == "$EXPECTED_VERSION" ]]
[[ "$(plist_value CFBundleVersion)" == "1" ]]
[[ "$(plist_value LSMinimumSystemVersion)" == "14.0" ]]
[[ "$(plist_value LSApplicationCategoryType)" == "public.app-category.utilities" ]]
[[ "$(plist_value CFBundleIconName)" == "AppIcon" ]]
[[ "$(plist_value LSUIElement)" == "true" ]]
[[ -n "$(plist_value NSMicrophoneUsageDescription)" ]]
[[ -s "$APP_PATH/Contents/Resources/AppIcon.icns" ]]
[[ -s "$APP_PATH/Contents/Resources/ACKNOWLEDGMENTS.md" ]]
[[ -s "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md" ]]
[[ -s "$APP_PATH/Contents/Resources/FluidAudio.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/whisper.cpp.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/sherpa-onnx.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/ONNX_Runtime.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/FunASR_Model_License_1.1.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/transcribe.cpp.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/default.metallib" ]]
[[ -s "$APP_PATH/Contents/Resources/MLXAudioSwift.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/MLXSwift.txt" ]]
SHERPA_LIBRARY="$APP_PATH/Contents/Frameworks/libsherpa-onnx-c-api.dylib"
ONNX_RUNTIME_LIBRARY="$APP_PATH/Contents/Frameworks/libonnxruntime.1.24.4.dylib"
TRANSCRIBE_CPP_LIBRARY="$APP_PATH/Contents/Frameworks/libtextify-transcribe.0.1.3.dylib"
MLX_METAL_LIBRARY="$APP_PATH/Contents/MacOS/mlx.metallib"
[[ -s "$SHERPA_LIBRARY" ]]
[[ -s "$ONNX_RUNTIME_LIBRARY" ]]
[[ -s "$TRANSCRIBE_CPP_LIBRARY" ]]
[[ -s "$MLX_METAL_LIBRARY" ]]
[[ -s "$MODEL_CATALOG_DIRECTORY/manifest.json" ]]
[[ -s "$MODEL_CATALOG_DIRECTORY/manifest.json.sig" ]]
file "$APP_PATH/Contents/Resources/default.metallib" | grep -Fq "MetalLib executable"
file "$MLX_METAL_LIBRARY" | grep -Fq "MetalLib executable"
codesign --verify --strict --verbose=2 "$MLX_METAL_LIBRARY"
printf '%s  %s\n' \
  'cffe8fbfa9cfb794f1d920ff187016f823a555f7814cede99026699a936b92c7' \
  "$MLX_METAL_LIBRARY" \
  | shasum -a 256 -c -
grep -aFq 'layer_normfloat32' "$MLX_METAL_LIBRARY"
TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64="$MODEL_CATALOG_PUBLIC_KEY_BASE64" \
  TEXTIFY_MODEL_MANIFEST_KEY_ID="$MODEL_CATALOG_KEY_ID" \
  "$SCRIPT_DIRECTORY/../models/verify_model_manifest.sh" \
    "$MODEL_CATALOG_DIRECTORY/manifest.json" \
    "$MODEL_CATALOG_DIRECTORY/manifest.json.sig"
grep -Fq "FluidAudio" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
grep -Fq "Apache License" "$APP_PATH/Contents/Resources/FluidAudio.txt"
grep -Fq "MIT License" "$APP_PATH/Contents/Resources/whisper.cpp.txt"
grep -Fq "Apache License" "$APP_PATH/Contents/Resources/sherpa-onnx.txt"
grep -Fq "MIT License" "$APP_PATH/Contents/Resources/ONNX_Runtime.txt"
grep -Fq "FunASR Model Open Source License Agreement" "$APP_PATH/Contents/Resources/FunASR_Model_License_1.1.txt"
grep -Fq "SenseVoiceSmall" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
grep -Fq "transcribe.cpp" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
grep -Fq "Fun-ASR MLT-Nano" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
grep -Fq "MIT License" "$APP_PATH/Contents/Resources/transcribe.cpp.txt"
grep -Fq "MIT License" "$APP_PATH/Contents/Resources/MLXAudioSwift.txt"
grep -Fq "MIT License" "$APP_PATH/Contents/Resources/MLXSwift.txt"
[[ "$(lipo -archs "$SHERPA_LIBRARY")" == "arm64" ]]
[[ "$(lipo -archs "$ONNX_RUNTIME_LIBRARY")" == "arm64" ]]
[[ "$(lipo -archs "$TRANSCRIBE_CPP_LIBRARY")" == "arm64" ]]
otool -L "$SHERPA_LIBRARY" | grep -Fq '@rpath/libonnxruntime.1.24.4.dylib'
[[ "$(otool -D "$TRANSCRIBE_CPP_LIBRARY" | tail -1)" == '@rpath/libtextify-transcribe.0.1.3.dylib' ]]
otool -l "$TRANSCRIBE_CPP_LIBRARY" \
  | awk '/LC_BUILD_VERSION/{show=1} show && /minos/{print $2; exit}' \
  | grep -Fxq '14.0'
! nm -gjU "$TRANSCRIBE_CPP_LIBRARY" | grep -Eq '^_ggml_'

EXECUTABLE="$APP_PATH/Contents/MacOS/$(plist_value CFBundleExecutable)"
[[ -x "$EXECUTABLE" ]]
[[ "$(lipo -archs "$EXECUTABLE")" == "arm64" ]]

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNING_DETAILS="$(codesign --display --verbose=4 "$APP_PATH" 2>&1)"
grep -Fqx "Identifier=io.github.Player0109.Textify" <<<"$SIGNING_DETAILS"
grep -Fqx "TeamIdentifier=$TEXTIFY_DEVELOPMENT_TEAM" <<<"$SIGNING_DETAILS"
grep -Fqx "Authority=$TEXTIFY_SIGNING_IDENTITY" <<<"$SIGNING_DETAILS"
grep -Eq '^CodeDirectory .* flags=.*\(runtime\)' <<<"$SIGNING_DETAILS"

for nested_library in "$ONNX_RUNTIME_LIBRARY" "$SHERPA_LIBRARY" "$TRANSCRIBE_CPP_LIBRARY" "$MLX_METAL_LIBRARY"; do
  codesign --verify --strict --verbose=2 "$nested_library"
  NESTED_SIGNING_DETAILS="$(codesign --display --verbose=4 "$nested_library" 2>&1)"
  grep -Fqx "TeamIdentifier=$TEXTIFY_DEVELOPMENT_TEAM" <<<"$NESTED_SIGNING_DETAILS"
  grep -Fqx "Authority=$TEXTIFY_SIGNING_IDENTITY" <<<"$NESTED_SIGNING_DETAILS"
  grep -Eq '^CodeDirectory .* flags=.*\(runtime\)' <<<"$NESTED_SIGNING_DETAILS"
done

DESIGNATED_REQUIREMENT="=anchor apple generic and identifier \"io.github.Player0109.Textify\" and certificate leaf[subject.OU] = \"$TEXTIFY_DEVELOPMENT_TEAM\""
codesign --verify --strict --test-requirement "$DESIGNATED_REQUIREMENT" "$APP_PATH"

ENTITLEMENTS_PLIST="$(mktemp)"
cleanup_entitlements() {
  rm -f "$ENTITLEMENTS_PLIST"
}
trap cleanup_entitlements EXIT
codesign --display --xml --entitlements "$ENTITLEMENTS_PLIST" "$APP_PATH"
[[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.device.audio-input" "$ENTITLEMENTS_PLIST")" == "true" ]]
if /usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$ENTITLEMENTS_PLIST" >/dev/null 2>&1; then
  echo "Exported Textify.app unexpectedly has the App Sandbox entitlement." >&2
  exit 1
fi
if /usr/libexec/PlistBuddy -c "Print :com.apple.security.cs.disable-library-validation" "$ENTITLEMENTS_PLIST" >/dev/null 2>&1; then
  echo "Exported Textify.app unexpectedly disables library validation." >&2
  exit 1
fi

if [[ -n "$GATEKEEPER_MODE" ]]; then
  [[ "$GATEKEEPER_MODE" == "--gatekeeper" ]]
  spctl --assess --type execute --verbose=4 "$APP_PATH"
fi
