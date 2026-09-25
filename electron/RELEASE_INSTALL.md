# Install Textify desktop

Textify transcribes speech locally after you install a model. It requires a
hardware GPU: Metal on Apple Silicon, or Vulkan on Windows and Linux. Models
are downloaded separately and verified before use.

## macOS 14+ (Apple Silicon)

Download the `Textify-…-mac-arm64.dmg` file and verify its SHA-256 value against
`SHA256SUMS.txt`. Open the DMG, drag Textify to Applications, and launch it from
Applications. Allow Microphone and Accessibility access when prompted. The
default global trigger is Right Command. The Mac app in this release is signed
with Developer ID and notarized by Apple; check the release notes for its exact
version and signing status.

## Windows x64

Download the `Textify-…-win-x64.exe` installer and compare its SHA-256 value
with `SHA256SUMS.txt`. Windows installers are currently unsigned, so Windows may
show a SmartScreen warning. Verify the repository, release, and checksum before
choosing More info → Run anyway. Managed-device policy may prevent installation.
The default global trigger is Right Control.

## Linux x64

Choose either the Debian/Ubuntu `.deb` or the portable `.AppImage` and verify
its SHA-256 value against `SHA256SUMS.txt`. Before opening the AppImage, run
`chmod +x` followed by the downloaded file's path. The AppImage needs FUSE for
normal mounting. Linux uses explicit Copy and manual paste; on Wayland, the
global trigger also depends on desktop GlobalShortcuts portal support.

After launch, open Transcription models, install a supported model, then use the
microphone button for a first recording. Check the release notes for tested
hardware, supported models, and any remaining platform limitations.
