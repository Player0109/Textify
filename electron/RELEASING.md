# Publishing the Textify desktop app

Publish the desktop app under a new `v0.2.0-preview.*` tag until its platform QA
is complete. Do not reuse a published tag or label an unsigned build as a
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
stapling changes the final bytes. The update feed instead uses
`Textify-<version>-mac-arm64.zip`, which electron-builder creates from the
already notarized and stapled app. The same command writes the ZIP's
`.blockmap` and the update feed, `latest-mac.yml`. electron-builder uses the
`latest` feed names for preview versions too.
Explicit preview packaging is unchanged and has no update feed.
Verify the DMG by mounting it,
checking its `Textify.app` signature and Gatekeeper assessment, and checking the
DMG after building. Confirm a fresh install and update on a second Mac before
making the release public.

The Windows and Linux installers come from the successful Electron workflow's
artifacts. They are not code-signed. Download those exact artifacts with their
update feeds, `latest.yml` and `latest-linux.yml`, and the Windows
installer's blockmap, and verify their workflow checksums. Place the final Mac,
Windows, and Linux files in `electron/release/`, then run
`node scripts/checksums.mjs --production` from `electron/` on the maintainer
Mac to write one combined checksum file and copy `RELEASE_INSTALL.md`. This
requires all four current-version installers and the Mac ZIP. It checks the
DMG's Developer ID signature, staple, and Gatekeeper result. It also checks that
each update feed names this version and matches its installers' exact sizes and
SHA-512 values, and that the app inside the ZIP passes the same signature,
staple, and Gatekeeper checks. It removes stale combined checksums
and signed-release installation notes before validation.
Checksums must be generated only after the final notarization and stapling.
Check the file
against all installers before attaching them to a GitHub pre-release. The
release notes must state the macOS version/architecture, GPU requirements,
model download requirement, physical hardware tested, and the unsigned status
of Windows and Linux. Publish only after the owner reviews the final artifacts
and notes.

## Publish the release

Installed apps with automatic checks find a release as soon as it is public.
Create the GitHub pre-release as a draft and attach every file before
publishing it:

- the four installers, `SHA256SUMS.txt` and `RELEASE_INSTALL.md`;
- `Textify-<version>-mac-arm64.zip` and its `.blockmap`;
- `Textify-<version>-win-x64.exe.blockmap`;
- `latest-mac.yml`, `latest.yml` and `latest-linux.yml`.

A preview install first asks the release for `preview-mac.yml`, `preview.yml`
or `preview-linux.yml`, then falls back to the `latest` file.

Windows and Linux updates are unsigned. Installed apps install whatever the
release's feed lists, so the GitHub account and release assets need strong
protection.

The tag must follow `v<version>` with a `-preview.<n>` version, as in
`v0.2.0-preview.24`. Preview installs only move to newer `preview` tags, so
tags such as `models-v1` and the retired Swift app's release are ignored. Never
replace the assets of a published release; publish a new version instead.
Preview installs never offer a stable release. Before the first stable
release, ship and test a final preview whose updater follows the stable
channel.

Only the first release that contains the updater needs a manual install.
Update the root README's download notes when that release is published.
