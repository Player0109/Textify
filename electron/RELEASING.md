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
`.blockmap` and the update feed, `preview-mac.yml` for a preview version.
Explicit preview packaging is unchanged and has no update feed.
Verify the DMG by mounting it,
checking its `Textify.app` signature and Gatekeeper assessment, and checking the
DMG after building. Confirm a fresh install and update on a second Mac before
making the release public.

## Collect the Windows and Linux installers

Push the release tag, `v<version>`, on the commit you built the Mac app from.
The Electron workflow for that tag builds the Windows and Linux installers with
their update feeds. Its `sign-windows` job then sends the Windows installer to
SignPath; see [Sign the Windows installer](#sign-the-windows-installer). Until
the release is published, update checks find the tag without feeds and fail
quietly, so publish soon after the tag.

Download `textify-desktop-ubuntu-24.04` and `textify-windows-signed` from that
run and verify their workflow checksums. Until SignPath signing is set up, use
`textify-desktop-windows-2025` and leave out its `preview.yml`. Place the final
Mac, Windows, and Linux files in `electron/release/`, then run
`node scripts/checksums.mjs --production` from `electron/` on the maintainer
Mac to write one combined checksum file and copy `RELEASE_INSTALL.md`.

This requires all four current-version installers and the Mac ZIP. It checks the
DMG's Developer ID signature, staple, and Gatekeeper result. It also checks that
each update feed names this version and matches its installers' exact sizes and
SHA-512 values, and that the app inside the ZIP passes the same signature,
staple, and Gatekeeper checks. A Windows installer signed by SignPath
Foundation must have a matching `preview.yml`. An unsigned Windows installer
must not have one, because installed apps would download it and then refuse it;
the command says when Windows installs will not be offered the release. It
removes stale combined checksums and signed-release installation notes before
validation.

Checksums must be generated only after the final notarization and stapling.
Check the file
against all installers before attaching them to a GitHub pre-release. The
release notes must state the macOS version/architecture, GPU requirements,
model download requirement, physical hardware tested, whether the Windows
installer is signed, and that Linux packages are unsigned. Publish only after
the owner reviews the final artifacts and notes.

## Sign the Windows installer

Windows installers are signed with SignPath Foundation's free certificate for
open-source projects. Windows then names SignPath Foundation as the publisher,
and installed apps accept only updates with that signature. SmartScreen may
still warn until the signed releases build reputation. The private key stays
with SignPath; GitHub holds only an API token.

SignPath Foundation signs many open-source projects with the same certificate.
The publisher check proves that an update passed through SignPath Foundation,
not that it came from Textify, so the GitHub account and release assets still
need strong protection.

One-time setup:

1. Turn on multi-factor authentication for the GitHub account and, later, for
   the SignPath account. SignPath Foundation requires it.
2. Apply at <https://signpath.org/apply>. The root README's code signing policy
   and the Apache 2.0 license are part of the requirements. Wait for approval.
3. In SignPath, connect the project to GitHub as a trusted build system and add
   this artifact configuration. SignPath may add restrictions on the product
   name, Textify, and the version from `package.json`.

   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <artifact-configuration xmlns="http://signpath.io/artifact-configuration/v1">
     <zip-file>
       <pe-file path="Textify-*-win-x64.exe">
         <authenticode-sign/>
       </pe-file>
     </zip-file>
   </artifact-configuration>
   ```

4. Use a release signing policy with SignPath Foundation's certificate and
   manual approval. Create a CI user that may submit to it and copy its API
   token.
5. In GitHub, open **Settings → Environments**, create `release`, limit it to
   `v*` tags, and add the secret `SIGNPATH_API_TOKEN`. Under **Settings →
   Secrets and variables → Actions → Variables**, add
   `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG` and
   `SIGNPATH_SIGNING_POLICY_SLUG`. The signing job runs only after
   `SIGNPATH_ORGANIZATION_ID` is set.

For each release, approve the signing request in SignPath within two hours of
pushing the tag. The job checks that Windows reports a valid SignPath
Foundation signature, rebuilds the installer's blockmap and `preview.yml` from
the signed bytes, and uploads them as `textify-windows-signed`. Signing only
adds a signature, so the job does not run the installation tests again.
Install the signed release on a Windows machine before publishing.

The Linux AppImage and `.deb` are not signed. They update themselves after the
feed's SHA-512 check. Ubuntu still describes a downloaded `.deb` as coming from
a third party.

## Publish the release

Installed apps with automatic checks find a release as soon as it is public.
Create the GitHub pre-release as a draft on the pushed tag and attach every
file before publishing it:

- the four installers, `SHA256SUMS.txt` and `RELEASE_INSTALL.md`;
- `Textify-<version>-mac-arm64.zip` and its `.blockmap`;
- `preview-mac.yml` and `preview-linux.yml`;
- for a signed Windows installer, `preview.yml` and
  `Textify-<version>-win-x64.exe.blockmap`.

A stable version uses `latest-mac.yml`, `latest-linux.yml` and `latest.yml`
instead.

The tag must follow `v<version>` with a `-preview.<n>` version, as in
`v0.2.0-preview.24`. Preview installs only move to newer `preview` tags, so
tags such as `models-v1` and the retired Swift app's release are ignored. Never
replace the assets of a published release; publish a new version instead.
Preview installs never offer a stable release. Before the first stable
release, ship and test a final preview whose updater follows the stable
channel.

Only the first release that contains the updater needs a manual install.
Update the root README's download notes when that release is published.
