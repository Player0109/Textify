# Releasing Textify V1.1

This document covers the V1.1 local release workflow. It does not add Sparkle,
notarization secrets, DMG upload automation, appcast hosting, or bundled model
files. Sparkle remains deferred.

## Prerequisites

- Xcode with macOS 14 SDK support.
- XcodeGen installed locally: `brew install xcodegen`.
- A clean worktree except for intentional release files.
- The production model-manifest public key and `keyId` are embedded in the app.
- The model-manifest private key is available only from local encrypted or
  offline maintainer storage.
- The final curated model asset is ready as `ggml-small.en-q5_1.bin`.

## Local Archive

```bash
swift test
chmod +x script/generate_xcode_project.sh
./script/generate_xcode_project.sh
xcodebuild -resolvePackageDependencies -project Textify.xcodeproj -scheme Textify
xcodebuild -project Textify.xcodeproj -scheme Textify -configuration Release -destination 'generic/platform=macOS' -archivePath dist/archive/Textify.xcarchive archive
```

The archive is written under `dist/archive/`, which stays untracked.

## Model Publishing

Textify V1.1 ships no bundled model. The app downloads the curated model from a
Textify GitHub Release asset and accepts it only through a signed manifest.

1. Upload `ggml-small.en-q5_1.bin` as a Textify GitHub Release asset, for
   example:

   `https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.bin`

2. Compute SHA-256 from the exact uploaded asset bytes and put that lowercase
   hex value in `manifest.json`.

   ```bash
   shasum -a 256 ggml-small.en-q5_1.bin
   ```

3. Keep the production manifest to one model entry: `ggml-small.en-q5_1`,
   display name `Balanced - Whisper small.en q5_1`, English only, with an HTTPS
   Textify GitHub Release asset URL.

4. Sign the exact raw `manifest.json` bytes on the maintainer machine.

   ```bash
   export TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64='<local raw private key base64>'
   export TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-primary'
   script/models/sign_model_manifest.sh path/to/manifest.json
   unset TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64
   ```

5. Verify the detached signature and production manifest policy with the public
   key before publishing.

   ```bash
   export TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64='<raw public key base64>'
   export TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-primary'
   script/models/verify_model_manifest.sh path/to/manifest.json path/to/manifest.json.sig
   ```

6. Publish both manifest files to GitHub Pages:

   - `https://player0109.github.io/Textify/models/manifest.json`
   - `https://player0109.github.io/Textify/models/manifest.json.sig`

The release remains blocked until the model asset URL and both GitHub Pages
manifest endpoints are live and match the verified files.

More detail lives in `docs/models/curated-models.md` and
`docs/models/model-manifest-signing.md`.

## Signing Boundary

The generated Xcode project uses manual ad hoc local signing and an empty entitlements file. V1 remains non-sandboxed. Developer ID signing, notarization, stapling, DMG creation, Sparkle appcast signing, and upload are manual maintainer-machine steps after this scaffold.

Do not commit private certificates, `.p12` files, notary credentials, Sparkle
private keys, model-manifest private keys, signing environment files, generated
secrets, or generated production model-manifest signatures.
