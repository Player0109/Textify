# Releasing Textify V1

This document covers the V1 local archive scaffold only. It does not add Sparkle, notarization secrets, DMG upload automation, appcast hosting, or bundled model files.

## Prerequisites

- Xcode with macOS 14 SDK support.
- XcodeGen installed locally: `brew install xcodegen`.
- A clean worktree except for intentional release files.

## Local Archive

```bash
swift test
chmod +x script/generate_xcode_project.sh
./script/generate_xcode_project.sh
xcodebuild -resolvePackageDependencies -project Textify.xcodeproj -scheme Textify
xcodebuild -project Textify.xcodeproj -scheme Textify -configuration Release -destination 'generic/platform=macOS' -archivePath dist/archive/Textify.xcarchive archive
```

The archive is written under `dist/archive/`, which stays untracked.

## Signing Boundary

The generated Xcode project uses manual ad hoc local signing and an empty entitlements file. V1 remains non-sandboxed. Developer ID signing, notarization, stapling, DMG creation, Sparkle appcast signing, and upload are manual maintainer-machine steps after this scaffold.

Do not commit private certificates, `.p12` files, notary credentials, Sparkle private keys, model-manifest private keys, or signing environment files.
