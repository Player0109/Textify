#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_DEVELOPMENT_TEAM:?Set TEXTIFY_DEVELOPMENT_TEAM}"
: "${TEXTIFY_SIGNING_IDENTITY:?Set TEXTIFY_SIGNING_IDENTITY}"

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIRECTORY/common.sh"
APP_PATH="${1:?Usage: verify_release_artifact.sh path/to/Textify.app expected-version [--gatekeeper]}"
EXPECTED_VERSION="${2:?Usage: verify_release_artifact.sh path/to/Textify.app expected-version [--gatekeeper]}"
GATEKEEPER_MODE="${3:-}"
MODEL_CATALOG_DIRECTORY="$APP_PATH/Contents/Resources/ModelCatalog"
MODEL_CATALOG_KEY_ID="textify-model-manifest-2026-huggingface"
MODEL_CATALOG_PUBLIC_KEY_BASE64="eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="

[[ -d "$APP_PATH" ]]
INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]]

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

macos_version_is_at_most_14_0() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    return 1
  fi
  local major minor patch
  IFS=. read -r major minor patch <<<"$version"
  minor="${minor:-0}"
  patch="${patch:-0}"
  (( major < 14 || (major == 14 && minor == 0 && patch == 0) ))
}

assert_macos_14_compatible_macho() {
  local binary_path="$1"
  local minimum_versions minimum_version
  minimum_versions="$(
    otool -l "$binary_path" \
      | awk '$1 == "cmd" { load_command = $2; next }
             load_command == "LC_BUILD_VERSION" && $1 == "minos" {
               print $2
               load_command = ""
             }
             load_command == "LC_VERSION_MIN_MACOSX" && $1 == "version" {
               print $2
               load_command = ""
             }'
  )"
  [[ -n "$minimum_versions" ]]
  while IFS= read -r minimum_version; do
    if ! macos_version_is_at_most_14_0 "$minimum_version"; then
      echo "$binary_path requires macOS $minimum_version, later than 14.0." >&2
      return 1
    fi
  done <<<"$minimum_versions"
}

[[ "$(plist_value CFBundleIdentifier)" == "io.github.Player0109.Textify" ]]
[[ "$(plist_value CFBundleShortVersionString)" == "$EXPECTED_VERSION" ]]
[[ "$(plist_value CFBundleVersion)" == "1" ]]
[[ "$(plist_value LSMinimumSystemVersion)" == "14.0" ]]
[[ "$(plist_value LSApplicationCategoryType)" == "public.app-category.utilities" ]]
[[ "$(plist_value CFBundleIconName)" == "AppIcon" ]]
[[ "$(plist_value LSUIElement)" == "true" ]]
[[ -n "$(plist_value NSMicrophoneUsageDescription)" ]]
EMBEDDED_SOURCE_COMMIT="$(plist_value "$SOURCE_COMMIT_PLIST_KEY")"
require_release_commit "$EMBEDDED_SOURCE_COMMIT"
if [[ -n "${TEXTIFY_EXPECTED_SOURCE_COMMIT:-}" ]]; then
  require_embedded_source_commit \
    "$APP_PATH" \
    "$TEXTIFY_EXPECTED_SOURCE_COMMIT"
fi
[[ -s "$APP_PATH/Contents/Resources/AppIcon.icns" ]]
[[ -s "$APP_PATH/Contents/Resources/LICENSE" ]]
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
[[ -s "$APP_PATH/Contents/Resources/LiteRT-LM.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/CC-BY-4.0.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/OpenAI-Whisper.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/CrisperWhisper-2.0-Nyra-License.md" ]]
[[ -s "$APP_PATH/Contents/Resources/CrisperWhisper.cpp-LICENSE.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/ggml-small.en-q5_1.LICENSES.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/NVIDIA_Open_Model_License.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/OpenMDW-1.1.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/SwiftNIO-NOTICE.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/SwiftCrypto-NOTICE.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/FluidAudio-fastcluster.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/FluidAudio-VBx.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/MLXSwift-fmt.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/MLXSwift-nlohmann-json.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/MLXSwift-metal-cpp.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/MLXSwift-MLX-Core.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/transcribe.cpp-ggml.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/transcribe.cpp-miniz.txt" ]]
[[ -s "$APP_PATH/Contents/Resources/ONNX_Runtime_ThirdPartyNotices.txt" ]]
printf '%s  %s\n' \
  '42f43bf4dc72ef422f91f6ca143f4514e21a68b353940d99091c1addcd0aee79' \
  "$APP_PATH/Contents/Resources/CrisperWhisper-2.0-Nyra-License.md" \
  'bccb9e9fa28644216f919d1f80567e49a41990705d3c3b036c334dc03e00dd31' \
  "$APP_PATH/Contents/Resources/CrisperWhisper.cpp-LICENSE.txt" \
  | shasum -a 256 -c -
SHERPA_LIBRARY="$APP_PATH/Contents/Frameworks/libsherpa-onnx-c-api.dylib"
ONNX_RUNTIME_LIBRARY="$APP_PATH/Contents/Frameworks/libonnxruntime.1.24.4.dylib"
PINNED_ONNX_RUNTIME_LIBRARY="$REPO_ROOT/Vendor/sherpa-onnx/v1.13.2/lib/libonnxruntime.1.24.4.dylib"
TRANSCRIBE_CPP_LIBRARY="$APP_PATH/Contents/Frameworks/libtextify-transcribe.0.1.3.dylib"
LITERT_LM_LIBRARY="$APP_PATH/Contents/Frameworks/libCLiteRTLM_mac.dylib"
SWIFT_COMPATIBILITY_LIBRARY="$APP_PATH/Contents/Frameworks/libswiftCompatibilitySpan.dylib"
MLX_METAL_LIBRARY="$APP_PATH/Contents/MacOS/mlx.metallib"
WHISPER_RUNTIME_METAL_LIBRARY="$APP_PATH/Contents/Resources/Textify_WhisperCppVendor.bundle/Contents/Resources/default.metallib"
[[ -s "$SHERPA_LIBRARY" ]]
[[ -s "$ONNX_RUNTIME_LIBRARY" ]]
[[ -s "$PINNED_ONNX_RUNTIME_LIBRARY" ]]
[[ -s "$TRANSCRIBE_CPP_LIBRARY" ]]
[[ -s "$LITERT_LM_LIBRARY" ]]
[[ -s "$SWIFT_COMPATIBILITY_LIBRARY" ]]
[[ -s "$MLX_METAL_LIBRARY" ]]
[[ -s "$WHISPER_RUNTIME_METAL_LIBRARY" ]]
[[ -s "$MODEL_CATALOG_DIRECTORY/manifest.json" ]]
[[ -s "$MODEL_CATALOG_DIRECTORY/manifest.json.sig" ]]
[[ -s "$MODEL_CATALOG_DIRECTORY/revocations.json" ]]
[[ -s "$MODEL_CATALOG_DIRECTORY/revocations.json.sig" ]]
printf '%s  %s\n' \
  '872533f130f1839a5bc01788ddb4f75c83a189763441ba1178788ed965449289' \
  "$PINNED_ONNX_RUNTIME_LIBRARY" \
  | shasum -a 256 -c -
cmp -s "$REPO_ROOT/models/manifest.json" "$MODEL_CATALOG_DIRECTORY/manifest.json"
cmp -s "$REPO_ROOT/models/manifest.json.sig" "$MODEL_CATALOG_DIRECTORY/manifest.json.sig"
cmp -s "$REPO_ROOT/models/revocations.json" "$MODEL_CATALOG_DIRECTORY/revocations.json"
cmp -s "$REPO_ROOT/models/revocations.json.sig" "$MODEL_CATALOG_DIRECTORY/revocations.json.sig"
WHISPER_FALLBACK_METAL_LIBRARY="$APP_PATH/Contents/Resources/default.metallib"
file "$WHISPER_FALLBACK_METAL_LIBRARY" | grep -Fq "MetalLib executable"
file "$WHISPER_RUNTIME_METAL_LIBRARY" | grep -Fq "MetalLib executable"
for whisper_metal_library in \
  "$WHISPER_RUNTIME_METAL_LIBRARY" \
  "$WHISPER_FALLBACK_METAL_LIBRARY"; do
  xcrun metal-objdump \
    --metallib \
    --private-headers \
    "$whisper_metal_library" \
    | grep -Fq 'PlatformMajor: 14'
  grep -aFq 'kernel_get_rows_q5_1' "$whisper_metal_library"
  grep -aFq 'kernel_mul_mm_q5_1_f32' "$whisper_metal_library"
  grep -aFq 'kernel_soft_max_f32' "$whisper_metal_library"
done
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
TEXTIFY_MODEL_REVOCATION_KEY_ID="$MODEL_CATALOG_KEY_ID" \
  "$SCRIPT_DIRECTORY/../models/verify_model_revocations.sh" \
    "$MODEL_CATALOG_DIRECTORY/revocations.json" \
    "$MODEL_CATALOG_DIRECTORY/revocations.json.sig"
grep -Fq "FluidAudio" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
grep -Fq "Apache License" "$APP_PATH/Contents/Resources/FluidAudio.txt"
grep -Fq "MIT License" "$APP_PATH/Contents/Resources/whisper.cpp.txt"
grep -Fq "Apache License" "$APP_PATH/Contents/Resources/sherpa-onnx.txt"
grep -Fq "MIT License" "$APP_PATH/Contents/Resources/ONNX_Runtime.txt"
grep -Fq "FunASR Model Open Source License Agreement" "$APP_PATH/Contents/Resources/FunASR_Model_License_1.1.txt"
grep -Fq "FunASR 模型开源协议" "$APP_PATH/Contents/Resources/FunASR_Model_License_1.1.txt"
grep -Fq "SenseVoiceSmall" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
grep -Fq "transcribe.cpp" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
grep -Fq "Fun-ASR MLT-Nano" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
grep -Fq "MIT License" "$APP_PATH/Contents/Resources/transcribe.cpp.txt"
grep -Fq "MIT License" "$APP_PATH/Contents/Resources/MLXAudioSwift.txt"
grep -Fq "MIT License" "$APP_PATH/Contents/Resources/MLXSwift.txt"
grep -Fq "Apache License" "$APP_PATH/Contents/Resources/LiteRT-LM.txt"
grep -Fq "Attribution 4.0 International" "$APP_PATH/Contents/Resources/CC-BY-4.0.txt"
grep -Fq "Copyright (c) 2022 OpenAI" "$APP_PATH/Contents/Resources/OpenAI-Whisper.txt"
grep -Fq "NYRA HEALTH NON-COMMERCIAL RESEARCH LICENSE AGREEMENT" \
  "$APP_PATH/Contents/Resources/CrisperWhisper-2.0-Nyra-License.md"
grep -Fq "Copyright (c) 2026 drbaph" \
  "$APP_PATH/Contents/Resources/CrisperWhisper.cpp-LICENSE.txt"
grep -Fq "CrisperWhisper 2.0 models and CrisperWhisper.cpp" \
  "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
grep -Fq "Textify curated model: ggml-small.en-q5_1.bin" "$APP_PATH/Contents/Resources/ggml-small.en-q5_1.LICENSES.txt"
grep -Fq "NVIDIA Open Model License Agreement" "$APP_PATH/Contents/Resources/NVIDIA_Open_Model_License.txt"
grep -Fq "OpenMDW License Agreement, version 1.1" "$APP_PATH/Contents/Resources/OpenMDW-1.1.txt"
grep -Fq "The SwiftNIO Project" "$APP_PATH/Contents/Resources/SwiftNIO-NOTICE.txt"
grep -Fq "The SwiftCrypto Project" "$APP_PATH/Contents/Resources/SwiftCrypto-NOTICE.txt"
grep -Fq "Daniel Müllner" "$APP_PATH/Contents/Resources/FluidAudio-fastcluster.txt"
grep -Fq "BUT Speech@FIT" "$APP_PATH/Contents/Resources/FluidAudio-VBx.txt"
grep -Fq "Victor Zverovich" "$APP_PATH/Contents/Resources/MLXSwift-fmt.txt"
grep -Fq "Niels Lohmann" "$APP_PATH/Contents/Resources/MLXSwift-nlohmann-json.txt"
grep -Fq "Copyright © 2024 Apple Inc." "$APP_PATH/Contents/Resources/MLXSwift-metal-cpp.txt"
grep -Fq "Copyright © 2023 Apple Inc." "$APP_PATH/Contents/Resources/MLXSwift-MLX-Core.txt"
grep -Fq "Copyright (c) 2023-2026 The ggml authors" "$APP_PATH/Contents/Resources/transcribe.cpp-ggml.txt"
grep -Fq "RAD Game Tools and Valve Software" "$APP_PATH/Contents/Resources/transcribe.cpp-miniz.txt"
grep -Fq "THIRD PARTY SOFTWARE NOTICES AND INFORMATION" "$APP_PATH/Contents/Resources/ONNX_Runtime_ThirdPartyNotices.txt"
grep -Fq "TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION" "$APP_PATH/Contents/Resources/LICENSE"
[[ "$(lipo -archs "$SHERPA_LIBRARY")" == "arm64" ]]
[[ "$(lipo -archs "$ONNX_RUNTIME_LIBRARY")" == "arm64" ]]
[[ "$(lipo -archs "$TRANSCRIBE_CPP_LIBRARY")" == "arm64" ]]
[[ "$(lipo -archs "$LITERT_LM_LIBRARY")" == "arm64" ]]
[[ "$(lipo -archs "$SWIFT_COMPATIBILITY_LIBRARY")" == "arm64" ]]
otool -L "$SHERPA_LIBRARY" | grep -Fq '@rpath/libonnxruntime.1.24.4.dylib'
[[ "$(otool -D "$ONNX_RUNTIME_LIBRARY" | tail -1)" == '@rpath/libonnxruntime.1.24.4.dylib' ]]
[[ "$(dwarfdump --uuid "$ONNX_RUNTIME_LIBRARY" | awk '{print $2}')" == \
  "$(dwarfdump --uuid "$PINNED_ONNX_RUNTIME_LIBRARY" | awk '{print $2}')" ]]
otool -l "$ONNX_RUNTIME_LIBRARY" \
  | awk '/LC_BUILD_VERSION/{show=1} show && /minos/{print $2; exit}' \
  | grep -Fxq '14.0'
[[ "$(otool -D "$TRANSCRIBE_CPP_LIBRARY" | tail -1)" == '@rpath/libtextify-transcribe.0.1.3.dylib' ]]
[[ "$(otool -D "$LITERT_LM_LIBRARY" | tail -1)" == '@rpath/libCLiteRTLM_mac.dylib' ]]
otool -l "$TRANSCRIBE_CPP_LIBRARY" \
  | awk '/LC_BUILD_VERSION/{show=1} show && /minos/{print $2; exit}' \
  | grep -Fxq '14.0'
! nm -gjU "$TRANSCRIBE_CPP_LIBRARY" | grep -Eq '^_ggml_'

EXECUTABLE="$APP_PATH/Contents/MacOS/$(plist_value CFBundleExecutable)"
[[ -x "$EXECUTABLE" ]]
[[ "$(lipo -archs "$EXECUTABLE")" == "arm64" ]]
EXECUTABLE_MINOS="$(
  otool -l "$EXECUTABLE" \
    | awk '$1 == "cmd" { in_build_version = ($2 == "LC_BUILD_VERSION"); next }
           in_build_version && $1 == "minos" { print $2; exit }'
)"
[[ "$EXECUTABLE_MINOS" == "14.0" ]]

while IFS= read -r -d '' packaged_file; do
  [[ "$(file -b "$packaged_file")" == *Mach-O* ]] || continue
  PACKAGED_ARCHITECTURES="$(lipo -archs "$packaged_file")"
  if [[ "$PACKAGED_ARCHITECTURES" != "arm64" ]]; then
    echo "$packaged_file contains unexpected architectures: $PACKAGED_ARCHITECTURES" >&2
    exit 1
  fi
  assert_macos_14_compatible_macho "$packaged_file"
done < <(find "$APP_PATH/Contents" -type f -print0)

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNING_DETAILS="$(codesign --display --verbose=4 "$APP_PATH" 2>&1)"
grep -Fqx "Identifier=io.github.Player0109.Textify" <<<"$SIGNING_DETAILS"
grep -Fqx "TeamIdentifier=$TEXTIFY_DEVELOPMENT_TEAM" <<<"$SIGNING_DETAILS"
grep -Fqx "Authority=$TEXTIFY_SIGNING_IDENTITY" <<<"$SIGNING_DETAILS"
grep -Eq '^CodeDirectory .* flags=.*\(runtime\)' <<<"$SIGNING_DETAILS"

for nested_library in \
  "$ONNX_RUNTIME_LIBRARY" \
  "$SHERPA_LIBRARY" \
  "$TRANSCRIBE_CPP_LIBRARY" \
  "$LITERT_LM_LIBRARY" \
  "$SWIFT_COMPATIBILITY_LIBRARY" \
  "$MLX_METAL_LIBRARY"; do
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
plutil -convert json -o - "$ENTITLEMENTS_PLIST" \
  | jq -e '
      keys == ["com.apple.security.device.audio-input"]
      and .["com.apple.security.device.audio-input"] == true
    ' >/dev/null

if [[ -n "$GATEKEEPER_MODE" ]]; then
  [[ "$GATEKEEPER_MODE" == "--gatekeeper" ]]
  spctl --assess --type execute --verbose=4 "$APP_PATH"
fi
