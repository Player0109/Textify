# Releasing Textify V1.1

This document covers the V1.1 local release workflow. It does not add Sparkle,
notarization secrets, DMG upload automation, appcast hosting, or bundled model
files. Sparkle remains deferred, so users update manually by downloading the
next GitHub Release DMG.

## Prerequisites

- Xcode with macOS 14 SDK support.
- XcodeGen installed locally: `brew install xcodegen`.
- A clean worktree except for intentional release files.
- The production model-manifest public key and `keyId` are embedded in the app.
- The model-manifest private key is available only from local encrypted or
  offline maintainer storage.
- The final curated model asset is ready as `ggml-small.en-q5_1.bin`.
- Public release docs are current: `README.md`, `PRIVACY.md`, `CHANGELOG.md`,
  `ACKNOWLEDGMENTS.md`, `THIRD_PARTY_NOTICES.md`, and
  `THIRD_PARTY_LICENSES/`.

## Local Validation

Run the local validation gate before using release credentials:

```bash
bash script/release/validate_release.sh
```

This runs the Swift test suite, builds the arm64 release executable, checks the
release plist, confirms Sparkle/mock release strings are absent, and verifies
the SwiftPM release binary is arm64 only.

## Developer ID Archive, DMG, And Notarization

```bash
TEXTIFY_DEVELOPMENT_TEAM="<TEAM_ID>" \
TEXTIFY_SIGNING_IDENTITY="Developer ID Application: <NAME> (<TEAM_ID>)" \
bash script/release/build_archive.sh

TEXTIFY_DEVELOPMENT_TEAM="<TEAM_ID>" \
bash script/release/export_developer_id.sh

bash script/release/make_dmg.sh 1.1.0

TEXTIFY_NOTARY_PROFILE="TextifyNotary" \
bash script/release/notarize_dmg.sh build/release/Textify-1.1.0-arm64.dmg
```

Release artifacts are written under `build/release/`. Do not commit generated
release artifacts. The expected upload artifacts are `Textify-1.1.0-arm64.dmg`
and `Textify-1.1.0-arm64.dmg.sha256`.

## Model Publishing

Textify V1.1 ships no bundled model. The app downloads the curated model from a
Textify GitHub Release asset and accepts it only through a signed manifest.

1. Upload `ggml-small.en-q5_1.bin` as a Textify GitHub Release asset, for
   example:

   `https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.bin`

2. Upload matching model sidecars to the same GitHub Release:

   - `ggml-small.en-q5_1.LICENSES.txt`, containing the model redistribution
     license text, including the OpenAI Whisper MIT license for the original
     model.
   - `ggml-small.en-q5_1.provenance.json`, containing the exact upstream URL,
     revision or commit, source filename, size, date mirrored, and maintainer
     who mirrored the file.

3. Compute SHA-256 from the exact uploaded model asset bytes and put that lowercase
   hex value in `manifest.json`.

   ```bash
   shasum -a 256 ggml-small.en-q5_1.bin
   ```

4. Keep the production manifest to one model entry: `ggml-small.en-q5_1`,
   display name `Balanced - Whisper small.en q5_1`, English only, with an HTTPS
   Textify GitHub Release asset URL. Its `licenses[].licenseTextUrl` must point
   to the uploaded `.LICENSES.txt`, and its `provenance` fields must match the
   uploaded `.provenance.json`.

5. Sign the exact raw `manifest.json` bytes on the maintainer machine.

   ```bash
   export TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64='<local raw private key base64>'
   export TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-primary'
   script/models/sign_model_manifest.sh path/to/manifest.json
   unset TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64
   ```

6. Verify the detached signature and production manifest policy with the public
   key before publishing.

   ```bash
   export TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64='<raw public key base64>'
   export TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-primary'
   script/models/verify_model_manifest.sh path/to/manifest.json path/to/manifest.json.sig
   ```

7. Publish both manifest files to GitHub Pages:

   - `https://player0109.github.io/Textify/models/manifest.json`
   - `https://player0109.github.io/Textify/models/manifest.json.sig`

The release remains blocked until the model asset URL, license/provenance
sidecars, and both GitHub Pages manifest endpoints are live and match the
verified files.

More detail lives in `docs/models/curated-models.md` and
`docs/models/model-manifest-signing.md`.

## Public Docs And Manual QA Gate

Before publishing the GitHub Release, verify the public docs do not promise
deferred or unsupported V1.1 behavior:

```bash
rg -n "Intel|Mac App Store|Sparkle auto|automatic update|history|multi-language|arbitrary model|per-app profile|encryption" README.md PRIVACY.md CHANGELOG.md docs
```

Any match must describe absence, deferral, or out-of-scope behavior accurately.

Then complete every release-blocking checkbox in `docs/MANUAL_QA.md`. The DMG
must pass fresh install, Gatekeeper, notarization/stapling, arm64-only binary,
permissions, Right Command dictation, insertion, clipboard, diagnostics, Launch
at Login, and Sparkle-absence checks before the release is published.

Re-run the automated release validation script before final upload if any
release files changed after the archive was created.

## Signing Boundary

The generated Xcode project uses manual ad hoc local signing and an empty
entitlements file. V1 remains non-sandboxed. Developer ID signing,
notarization, stapling, DMG creation, and upload are manual maintainer-machine
steps. Sparkle appcast signing is deferred with Sparkle.

Do not commit private certificates, `.p12` files, notary credentials, Sparkle
private keys, model-manifest private keys, signing environment files, generated
secrets, or generated production model-manifest signatures.
