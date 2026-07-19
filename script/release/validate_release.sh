#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

ensure_xcode_project
TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64="eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos=" \
  TEXTIFY_MODEL_MANIFEST_KEY_ID="textify-model-manifest-2026-huggingface" \
  script/models/verify_model_manifest.sh models/manifest.json models/manifest.json.sig
swift test
swift build -c release --arch arm64
plutil -lint Resources/Info.plist
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)" == "io.github.Player0109.Textify" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" Resources/Info.plist)" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :LSApplicationCategoryType" Resources/Info.plist)" == "public.app-category.utilities" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" Resources/Info.plist)" == "AppIcon" ]]
[[ -n "$(/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" Resources/Info.plist)" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.device.audio-input" Textify.entitlements)" == "true" ]]
if /usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" Textify.entitlements >/dev/null 2>&1; then
  echo "Textify must remain non-sandboxed for global hotkeys and cross-app insertion." >&2
  exit 1
fi
for icon in Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-*.png; do
  [[ -s "$icon" ]]
done
[[ "$(find Resources/Assets.xcassets/AppIcon.appiconset -name 'AppIcon-*.png' -type f | wc -l | tr -d ' ')" == "10" ]]
! rg -n "SUFeedURL|SUPublicEDKey|Sparkle" Resources Sources Package.swift project.yml
! rg -n "Run Mock Dictation|Mock dictation|Developer Mode|Check for Updates|transcript history" Sources/Textify
lipo -archs .build/arm64-apple-macosx/release/Textify | rg '^arm64$'
printf '%s  %s\n' \
  'b9dce3ad05294742b57627d86e7815be497a2f426e954476cdc31fea22197318' \
  'Vendor/sherpa-onnx/v1.13.2/lib/libsherpa-onnx-c-api.dylib' \
  '3b76ed91e19443f04b79d53bf415d5fe66dd81211e3b7787ba48009e49e2d04d' \
  'Vendor/sherpa-onnx/v1.13.2/lib/libonnxruntime.1.24.4.dylib' \
  '437b1279047877167d8fadc74a60d47f3df514d703fdac1c1b6851da9bc2fdb4' \
  'Vendor/sherpa-onnx/v1.13.2/include/sherpa-onnx/c-api/c-api.h' \
  | shasum -a 256 -c -
[[ "$(lipo -archs Vendor/sherpa-onnx/v1.13.2/lib/libsherpa-onnx-c-api.dylib)" == "arm64" ]]
[[ "$(lipo -archs Vendor/sherpa-onnx/v1.13.2/lib/libonnxruntime.1.24.4.dylib)" == "arm64" ]]
printf '%s  %s\n' \
  '543b2d9be14e1f3d834534d9f230e9828184466c653bb940787fdd517e5f7855' \
  'Vendor/transcribe.cpp/v0.1.3/lib/libtextify-transcribe.0.1.3.dylib' \
  '2b7c468b2153ebda9110840945fb83652148f787cb4cb0a4d049d1ee7c65bbda' \
  'Vendor/transcribe.cpp/v0.1.3/include/transcribe.h' \
  'e4837fc78edc92a861fe8f3e72bbc3bcb1d9269ef3dc38cd2c81022fdf02f26b' \
  'Vendor/transcribe.cpp/v0.1.3/patches/0001-funasr-publisher-language-names.patch' \
  'ea17b5a8faf925bd83385e6d05c2d6eda0c22c6c39c483a244e107894bda3242' \
  'Vendor/transcribe.cpp/v0.1.3/EXPORTED_SYMBOLS' \
  '86a53633b56f6b029d3cb42158bcc7aac0cdff898aceb13e83b93e368bbc4ac6' \
  'THIRD_PARTY_LICENSES/transcribe.cpp.txt' \
  | shasum -a 256 -c -
[[ "$(lipo -archs Vendor/transcribe.cpp/v0.1.3/lib/libtextify-transcribe.0.1.3.dylib)" == "arm64" ]]
[[ "$(otool -D Vendor/transcribe.cpp/v0.1.3/lib/libtextify-transcribe.0.1.3.dylib | tail -1)" == '@rpath/libtextify-transcribe.0.1.3.dylib' ]]
nm -gjU Vendor/transcribe.cpp/v0.1.3/lib/libtextify-transcribe.0.1.3.dylib \
  | sort -u \
  | cmp Vendor/transcribe.cpp/v0.1.3/EXPORTED_SYMBOLS -
! nm -gjU Vendor/transcribe.cpp/v0.1.3/lib/libtextify-transcribe.0.1.3.dylib \
  | grep -Eq '^_ggml_'
shell_scripts=(
  script/release/*.sh
  script/models/*.sh
  script/runtime/*.sh
  script/build_and_run.sh
  script/build_whisper_metallib.sh
  script/generate_xcode_project.sh
)
for shell_script in "${shell_scripts[@]}"; do
  [[ -f "$shell_script" ]]
  bash -n "$shell_script"
done
