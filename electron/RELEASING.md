# Publishing the Textify desktop app

The existing GitHub Release is for the native macOS app. Publish the Electron
desktop app under its own `v0.2.0-preview.*` tag until its platform QA is
complete. Do not reuse a native app tag or label an unsigned build as a
notarized release.

## Release gates

1. Merge the reviewed Electron changes and confirm the Electron workflow passes
   on macOS, Windows, and Linux for the exact commit to release. Hosted runners
   test a GPU-less refusal path; they do not prove recognition on physical GPUs.
2. Complete and record the outstanding physical-desktop checks in
   [MANUAL_QA.md](MANUAL_QA.md), especially microphone, global shortcut,
   insertion, permissions, Windows Vulkan, and Linux Wayland behavior. Keep
   unverified platforms clearly labeled in release notes.
3. On the maintainer Mac, install a **Developer ID Application** certificate
   with its private key and save notarization credentials in the local Keychain.
   `Apple Development` is only for development and cannot replace Developer ID
   for direct distribution. Never put the certificate, its private key, or
   notarization credentials in GitHub Actions or the repository.

## Build and verify the Mac download

From `electron/` on Apple Silicon, use Node.js 24 and the native build tools:

```sh
npm ci
npm run native:prepare
npm run native:build
npm run check
npm run smoke
security find-identity -v -p codesigning
APPLE_KEYCHAIN_PROFILE=textify-notary npm run dist
codesign --verify --deep --strict release/mac-arm64/Textify.app
xcrun stapler validate release/mac-arm64/Textify.app
spctl --assess --verbose --type execute release/mac-arm64/Textify.app
node scripts/mac-signature-smoke.mjs release/mac-arm64/Textify.app
node scripts/packaged-smoke.mjs release/mac-arm64/Textify.app/Contents/MacOS/Textify
```

Replace `textify-notary` with the actual local `notarytool` Keychain profile.
The production packaging command requires both a Developer ID identity and
notarization credentials; it never publishes. Verify the DMG by mounting it,
checking its `Textify.app` signature and Gatekeeper assessment, and checking the
DMG after building. Confirm a fresh install and update on a second Mac before
making the release public.

The Windows and Linux installers come from the successful Electron workflow's
artifacts. They are not code-signed. Download those exact artifacts and verify
their workflow checksums. Place the final Mac, Windows, and Linux installers in
`electron/release/`, then run `node scripts/checksums.mjs --production` from
`electron/` to
write one combined checksum file and copy `RELEASE_INSTALL.md`. Check the file
against all installers before attaching them to a GitHub pre-release. The
release notes must state the macOS version/architecture, GPU requirements,
model download requirement, physical hardware tested, and the unsigned status
of Windows and Linux. Publish only after the owner reviews the final artifacts
and notes.
