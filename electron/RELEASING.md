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

For first-time setup, open **Xcode → Settings → Apple Accounts**, select the
approved team, then **Manage Certificates → + → Developer ID Application**.
After the certificate and its private key are available locally, store and
check notarization credentials interactively:

```sh
xcrun notarytool store-credentials textify-notary
xcrun notarytool history --keychain-profile textify-notary
```

The first command prompts for the account, team, and app-specific password;
password input is hidden. Keep secrets in the local Keychain, never in chat,
the repository, or CI. An existing Apple API-key setup is also supported by the
packaging script's `APPLE_API_KEY`, `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER`
environment variables. Do not mix credential methods.

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
notarization credentials; it never publishes. It notarizes and staples the app,
signs the final DMG, submits that DMG to Apple, requires an Accepted result,
staples it, and validates its signature, staple, and Gatekeeper assessment before
reporting success. Production DMGs omit automatic-update blockmaps because
stapling changes the final bytes. Explicit preview packaging is unchanged.
Verify the DMG by mounting it,
checking its `Textify.app` signature and Gatekeeper assessment, and checking the
DMG after building. Confirm a fresh install and update on a second Mac before
making the release public.

The Windows and Linux installers come from the successful Electron workflow's
artifacts. They are not code-signed. Download those exact artifacts and verify
their workflow checksums. Place the final Mac, Windows, and Linux installers in
`electron/release/`, then run `node scripts/checksums.mjs --production` from
`electron/` on the maintainer Mac to write one combined checksum file and copy
`RELEASE_INSTALL.md`. This requires all four current-version installers, checks
the DMG's Developer ID signature, staple, and Gatekeeper result, and removes
stale combined checksums and signed-release installation notes before validation.
Checksums must be generated only after the final notarization and stapling.
Check the file
against all installers before attaching them to a GitHub pre-release. The
release notes must state the macOS version/architecture, GPU requirements,
model download requirement, physical hardware tested, and the unsigned status
of Windows and Linux. Publish only after the owner reviews the final artifacts
and notes.
