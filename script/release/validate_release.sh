#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

if ! command -v rg >/dev/null; then
  echo "ripgrep (rg) is required for release-source validation." >&2
  exit 1
fi

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
  [[ -f "$binary_path" ]]
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

ensure_xcode_project
TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64="eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos=" \
  TEXTIFY_MODEL_MANIFEST_KEY_ID="textify-model-manifest-2026-huggingface" \
  script/models/verify_model_manifest.sh models/manifest.json models/manifest.json.sig
TEXTIFY_MODEL_REVOCATION_KEY_ID="textify-model-manifest-2026-huggingface" \
  script/models/verify_model_revocations.sh \
    models/revocations.json \
    models/revocations.json.sig
swift test
swift build -c release --arch arm64
RELEASE_BIN_DIRECTORY="$(swift build -c release --arch arm64 --show-bin-path)"
RELEASE_EXECUTABLE="$RELEASE_BIN_DIRECTORY/Textify"
[[ -x "$RELEASE_EXECUTABLE" ]]
[[ "$(lipo -archs "$RELEASE_EXECUTABLE")" == "arm64" ]]
RELEASE_EXECUTABLE_MINOS="$(
  otool -l "$RELEASE_EXECUTABLE" \
    | awk '$1 == "cmd" { in_build_version = ($2 == "LC_BUILD_VERSION"); next }
           in_build_version && $1 == "minos" { print $2; exit }'
)"
[[ "$RELEASE_EXECUTABLE_MINOS" == "14.0" ]]
for release_dependency in \
  "$RELEASE_BIN_DIRECTORY/libCLiteRTLM_mac.dylib" \
  Vendor/sherpa-onnx/v1.13.2/lib/libsherpa-onnx-c-api.dylib \
  Vendor/sherpa-onnx/v1.13.2/lib/libonnxruntime.1.24.4.dylib \
  Vendor/transcribe.cpp/v0.1.3/lib/libtextify-transcribe.0.1.3.dylib; do
  assert_macos_14_compatible_macho "$release_dependency"
done
plutil -lint Resources/Info.plist
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)" == "io.github.Player0109.Textify" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" Resources/Info.plist)" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :LSApplicationCategoryType" Resources/Info.plist)" == "public.app-category.utilities" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" Resources/Info.plist)" == "AppIcon" ]]
[[ -n "$(/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" Resources/Info.plist)" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.device.audio-input" Textify.entitlements)" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.device.audio-input" Textify.Local.entitlements)" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.cs.disable-library-validation" Textify.Local.entitlements)" == "true" ]]
plutil -convert json -o - Textify.entitlements \
  | jq -e '
      keys == ["com.apple.security.device.audio-input"]
      and .["com.apple.security.device.audio-input"] == true
    ' >/dev/null
for icon in Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-*.png; do
  [[ -s "$icon" ]]
done
[[ "$(find Resources/Assets.xcassets/AppIcon.appiconset -name 'AppIcon-*.png' -type f | wc -l | tr -d ' ')" == "10" ]]
! rg -n "SUFeedURL|SUPublicEDKey|Sparkle" Resources Sources Package.swift project.yml
! rg -n "Run Mock Dictation|Mock dictation|Developer Mode|Check for Updates|transcript history" Sources/Textify
printf '%s  %s\n' \
  'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4' \
  'LICENSE' \
  'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4' \
  'THIRD_PARTY_LICENSES/LiteRT-LM.txt' \
  '9ba9550ad48438d0836ddab3da480b3b69ffa0aac7b7878b5a0039e7ab429411' \
  'THIRD_PARTY_LICENSES/CC-BY-4.0.txt' \
  'b5d65a59060e68c4ff940e1eddfa6f94b2d68fdf58ed7f4dd57721c997e35e9d' \
  'THIRD_PARTY_LICENSES/OpenAI-Whisper.txt' \
  '42f43bf4dc72ef422f91f6ca143f4514e21a68b353940d99091c1addcd0aee79' \
  'THIRD_PARTY_LICENSES/CrisperWhisper-2.0-Nyra-License.md' \
  'bccb9e9fa28644216f919d1f80567e49a41990705d3c3b036c334dc03e00dd31' \
  'THIRD_PARTY_LICENSES/CrisperWhisper.cpp-LICENSE.txt' \
  '5745650da468d88786f6805e04b3458f69f5d884d9aa82fe39a00bb41b59cd1e' \
  'THIRD_PARTY_LICENSES/ggml-small.en-q5_1.LICENSES.txt' \
  '1e62abdfd004da72038581ea98b9dd3a94b7b859d66efa6b13e2992a523ef5cd' \
  'THIRD_PARTY_LICENSES/NVIDIA_Open_Model_License.txt' \
  '46f043dbe040e781acdf5fd0cfbbdc1662eec4a23a08d0646b061511b2e7f97b' \
  'THIRD_PARTY_LICENSES/OpenMDW-1.1.txt' \
  '7dba975a2069691db4992b0592d70828b330d2f8a30a71450f4e152a554e84f8' \
  'THIRD_PARTY_LICENSES/FunASR_Model_License_1.1.txt' \
  'd25ed2452b3476c342082d11e4e8bf5459174d2836124f842b499850bcebc50e' \
  'THIRD_PARTY_LICENSES/SwiftNIO-NOTICE.txt' \
  'b3ddc2ae068e76b3beb71be03c0400f90090f9469aa491bf7b1ac42320af37b8' \
  'THIRD_PARTY_LICENSES/SwiftCrypto-NOTICE.txt' \
  '67594dbe4a7477719c8160373e7767c2c319ef966a6042f76846a18af02cde0a' \
  'THIRD_PARTY_LICENSES/FluidAudio-fastcluster.txt' \
  '08e57fdb5187c816e937916f1e176aadb400ca76f4b3b493d69730ec8f10dd80' \
  'THIRD_PARTY_LICENSES/FluidAudio-VBx.txt' \
  '07580f2a3b35709ce703d523f447b242f6dfec7582a8c0df102c7fa2849375f8' \
  'THIRD_PARTY_LICENSES/MLXSwift-fmt.txt' \
  '86b998c792894ccb911a1cb7994f7a9652894e7a094c0b5e45be2f553f45cf14' \
  'THIRD_PARTY_LICENSES/MLXSwift-nlohmann-json.txt' \
  'f4e92c7fe2aa066e294c0da9d08683dc9fb741ee6e6debbfad99a0c96e07c1f2' \
  'THIRD_PARTY_LICENSES/MLXSwift-metal-cpp.txt' \
  'ccfab7ccb2ea306f71531c8ca77bb55507606cd90768b1e32b8b52ab5b48cf01' \
  'THIRD_PARTY_LICENSES/MLXSwift-MLX-Core.txt' \
  '94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d' \
  'THIRD_PARTY_LICENSES/transcribe.cpp-ggml.txt' \
  '6f20fa7672b00e2e975c291df737cf227addf3ad32e36fef3fe0f416e4664d3d' \
  'THIRD_PARTY_LICENSES/transcribe.cpp-miniz.txt' \
  '0e07b95f3a8d6230037707c5c4a2b554d12c4cb67369669ac255635528ffcee2' \
  'THIRD_PARTY_LICENSES/ONNX_Runtime_ThirdPartyNotices.txt' \
  | shasum -a 256 -c -
grep -Fq 'NVIDIA Canary-Qwen model' THIRD_PARTY_NOTICES.md
grep -Fq 'LiteRT-LM' THIRD_PARTY_NOTICES.md
grep -Fq 'IBM Granite Speech models' THIRD_PARTY_NOTICES.md
grep -Fq 'Mistral Voxtral Mini model' THIRD_PARTY_NOTICES.md
grep -Fq 'OpenMOSS MOSS Transcribe-Diarize model' THIRD_PARTY_NOTICES.md
grep -Fq 'CrisperWhisper 2.0 models and CrisperWhisper.cpp' THIRD_PARTY_NOTICES.md
printf '%s  %s\n' \
  'b9dce3ad05294742b57627d86e7815be497a2f426e954476cdc31fea22197318' \
  'Vendor/sherpa-onnx/v1.13.2/lib/libsherpa-onnx-c-api.dylib' \
  '872533f130f1839a5bc01788ddb4f75c83a189763441ba1178788ed965449289' \
  'Vendor/sherpa-onnx/v1.13.2/lib/libonnxruntime.1.24.4.dylib' \
  '437b1279047877167d8fadc74a60d47f3df514d703fdac1c1b6851da9bc2fdb4' \
  'Vendor/sherpa-onnx/v1.13.2/include/sherpa-onnx/c-api/c-api.h' \
  | shasum -a 256 -c -
[[ "$(lipo -archs Vendor/sherpa-onnx/v1.13.2/lib/libsherpa-onnx-c-api.dylib)" == "arm64" ]]
[[ "$(lipo -archs Vendor/sherpa-onnx/v1.13.2/lib/libonnxruntime.1.24.4.dylib)" == "arm64" ]]
otool -l Vendor/sherpa-onnx/v1.13.2/lib/libonnxruntime.1.24.4.dylib \
  | awk '/LC_BUILD_VERSION/{show=1} show && /minos/{print $2; exit}' \
  | grep -Fxq '14.0'
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
  'fd330bb5d9adf9e65bfe4d8f6f90c808a4196ef5c98aad018a3344256fcb2374' \
  'THIRD_PARTY_LICENSES/MLXAudioSwift.txt' \
  '44326a4ea062241ae6fc26ee2ec90bdc81af7eb7b9d3966181b733fa69d42057' \
  'THIRD_PARTY_LICENSES/MLXSwift.txt' \
  'cffe8fbfa9cfb794f1d920ff187016f823a555f7814cede99026699a936b92c7' \
  'Vendor/mlx-swift/0.31.3/mlx.metallib' \
  | shasum -a 256 -c -
file Vendor/mlx-swift/0.31.3/mlx.metallib | grep -Fq 'MetalLib executable'
grep -aFq 'layer_normfloat32' Vendor/mlx-swift/0.31.3/mlx.metallib
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
  script/build_mlx_metallib.sh
  script/build_whisper_metallib.sh
  script/generate_xcode_project.sh
)
for shell_script in "${shell_scripts[@]}"; do
  [[ -f "$shell_script" ]]
  bash -n "$shell_script"
done
