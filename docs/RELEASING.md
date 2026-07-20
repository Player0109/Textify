# Releasing Textify V1.1

This document covers the V1.1 local release workflow. It does not add Sparkle,
notarization secrets, DMG upload automation, appcast hosting, or bundled model
weights. The small signed catalog is bundled as a trusted baseline. Sparkle
remains deferred, so users update manually by downloading the next GitHub
Release DMG.

## Prerequisites

- Xcode with Swift 6.2 or later and macOS 14 SDK support. The pinned MLX Audio
  package declares Swift tools 6.2 while Textify continues to deploy to macOS 14.
- XcodeGen installed locally: `brew install xcodegen`.
- A clean worktree except for intentional release files.
- The production model-manifest public key and `keyId` are embedded in the app.
- The model-manifest private key is available only from the maintainer's macOS
  Keychain or other encrypted/offline maintainer storage.
- Every model selected for publication has exact immutable artifacts, per-file
  checksums/sizes, license texts, provenance, benchmark evidence, and picker
  guidance ready.
- Public release docs are current: `README.md`, `PRIVACY.md`, `CHANGELOG.md`,
  `ACKNOWLEDGMENTS.md`, `THIRD_PARTY_NOTICES.md`, and
  `THIRD_PARTY_LICENSES/`.

## Local Validation

Run the local validation gate before using release credentials:

```bash
bash script/release/validate_release.sh
```

This regenerates the Xcode project, runs the Swift test suite, builds the arm64
release executable, checks the release plist and hardened-runtime audio-input
entitlement, confirms Sparkle/mock release strings are absent, validates every
release shell script, verifies the tracked signed 35-model catalog, and
verifies the SwiftPM release binary is arm64 only. A
staged or archived app must also contain a valid compiled
`Contents/Resources/default.metallib`; the artifact verifier rejects a bundle
that would silently lose Whisper's Metal path. MLX Audio models separately
require the pinned `Contents/MacOS/mlx.metallib`; the verifier checks its exact
hash and required `layer_normfloat32` kernel so Whisper's library cannot be
mistaken for it. It also requires the exact
verified catalog/signature pair under `Contents/Resources/ModelCatalog/`. If
the catalog includes sherpa-onnx, the app must contain the pinned arm64
`libsherpa-onnx-c-api.dylib` and `libonnxruntime.1.24.4.dylib` under
`Contents/Frameworks`; both nested signatures and the app's strict deep
signature must verify. The app must also contain the exact pinned arm64
`libtextify-transcribe.0.1.3.dylib`; validation checks its macOS 14 deployment
target, isolated public symbol surface, nested signature, and copied MIT
license. If
project regeneration changes `Textify.xcodeproj`, the command stops once so the
maintainer can review and commit the generated project before rerunning it.

## Developer ID Archive, DMG, And Notarization

```bash
TEXTIFY_DEVELOPMENT_TEAM="<TEAM_ID>" \
TEXTIFY_SIGNING_IDENTITY="Developer ID Application: <NAME> (<TEAM_ID>)" \
bash script/release/build_archive.sh

TEXTIFY_DEVELOPMENT_TEAM="<TEAM_ID>" \
TEXTIFY_SIGNING_IDENTITY="Developer ID Application: <NAME> (<TEAM_ID>)" \
bash script/release/export_developer_id.sh

TEXTIFY_DEVELOPMENT_TEAM="<TEAM_ID>" \
TEXTIFY_SIGNING_IDENTITY="Developer ID Application: <NAME> (<TEAM_ID>)" \
bash script/release/make_dmg.sh 1.1.0

TEXTIFY_NOTARY_PROFILE="TextifyNotary" \
TEXTIFY_DEVELOPMENT_TEAM="<TEAM_ID>" \
TEXTIFY_SIGNING_IDENTITY="Developer ID Application: <NAME> (<TEAM_ID>)" \
bash script/release/notarize_dmg.sh build/release/Textify-1.1.0-arm64.dmg
```

Release artifacts are written under `build/release/`. Do not commit generated
release artifacts. The expected upload artifacts are `Textify-1.1.0-arm64.dmg`
and `Textify-1.1.0-arm64.dmg.sha256`. The checksum is deliberately created only
after notarization and stapling, because stapling mutates the DMG. If
notarization or validation fails, the notarization script removes any stale
checksum and does not produce a replacement. The workflow verifies the exact
exported app and mounted DMG copy for version/build metadata, arm64-only code,
Developer ID identity and team, hardened runtime, audio-input entitlement,
strict code-signature validity, designated requirement, and (after
notarization) Gatekeeper acceptance.

## Model Publishing

Textify ships no bundled model weights. The app downloads only files described
by the selected signed catalog. Production files may use either immutable
Textify GitHub Release assets or exact commit-pinned Hugging Face URLs.

1. Select only models that passed `docs/models/curated-models.md` promotion
   gates. The currently proven general runtimes are Whisper/Metal and Parakeet
   V3/Core ML ANE. Paraformer int8 may be published only as a Mandarin
   Specialist with the measured first-preparation warning. Whisper Large V3
   Turbo q5_0 may be published only as the measured English/Hindi Specialist;
   broader upstream language support is not a Textify support claim.
   ReazonSpeech K2 V2 int8 may be published as the Fast Japanese CPU choice
   with its 29-second recording limit and measured quality/latency guidance.
   SenseVoiceSmall int8 2024-07-17 may be published as the Accurate CPU choice
   for English, Mandarin, Cantonese, Japanese, and Korean with its custom
   FunASR model license attribution, 29-second limit, and measured stress
   warning. Do not substitute the later Cantonese-specific fine-tune.
   Fun-ASR MLT-Nano Q8_0 may be published only after its narrowed language
   routes pass Textify's multilingual and robustness gates through the pinned
   transcribe.cpp Metal runtime. Do not translate the upstream 31-language
   capability into a Textify support claim without measured per-language
   evidence.
   Qwen3-ASR MLX and GGUF variants remain Experimental until their exact
   artifacts pass Textify's install-shaped Metal smokes and fixed-corpus
   measurements. They require automatic language detection; do not send an
   explicit language prompt through either runtime.
   Parakeet TDT V2/V3 and Nemotron MLX/GGUF variants likewise remain
   Experimental until their declared multilingual routes gain representative
   per-language evidence. The Handy repositories publish F16 rather than BF16
   for these three GGUF families; never relabel F16 artifacts as BF16.
   Nemotron must remain a whole-buffer dictation route unless Textify separately
   implements and verifies a live-partial product path.

2. Choose an immutable approved source for every exact artifact. Whisper may
   use a Textify GitHub Release asset. Public Hugging Face files must use
   `https://huggingface.co/<owner>/<repo>/resolve/<40-character-lowercase-commit>/<path>`.
   Never use `main`, a tag, a query/fragment, encoded/traversing paths, or a
   ModelScope download URL. Core ML directories declare every selected leaf
   with a safe unique `relativePath` so the installer reconstructs them
   atomically.

3. Record license and provenance for each model. Custom model licenses such as
   FunASR Model License 1.1 must be copied into the app resources, attributed,
   and linked by immutable revision. The provenance must
   include the original checkpoint, exact revision, conversion repository and
   revision, quantization/conversion recipe, selected filenames, sizes, audit
   date, and curator. Record every applicable license layer, not only the
   runtime library license. Textify-hosted mirrors also publish license and
   provenance sidecars beside the assets.

4. Download every immutable final URL and compute lowercase SHA-256 and byte
   size from those final bytes. Put every leaf checksum/size in
   `manifest.json`; `model.sizeBytes` must equal their exact sum.

   ```bash
   shasum -a 256 path/to/final-uploaded-asset
   stat -f %z path/to/final-uploaded-asset
   ```

5. Complete every catalog field: unique model id, tier, languages, runtime
   engine/variant/accelerator/layout, minimum app version, decoding parameters,
   hallucination thresholds, licenses, provenance, expected finalization,
   accuracy tradeoff, and requirements. Do not add near-duplicate choices that
   provide no measured advantage.

6. Create or reuse the Keychain signing key and sign the canonical envelope for
   the exact raw `manifest.json` bytes. The generated envelope binds the
   manifest SHA-256, content type, filename, algorithm, and key ID before
   signing.

   ```bash
   script/models/create_model_manifest_signing_key.sh \
     textify-model-manifest-2026-huggingface

   TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-huggingface' \
     script/models/sign_model_manifest.sh path/to/manifest.json
   ```

7. Verify the detached signature and production manifest policy with the public
   key before publishing.

   ```bash
   export TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64='<raw public key base64>'
   export TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-huggingface'
   script/models/verify_model_manifest.sh path/to/manifest.json path/to/manifest.json.sig
   ```

8. Replace the tracked `models/manifest.json` and `.sig`, build the app, and
   verify the exact same bytes are embedded under
   `Contents/Resources/ModelCatalog/`. A valid remote catalog older than this
   bundled baseline cannot downgrade it.

9. Publish both manifest files to GitHub Pages when updating the remote
   catalog for installed builds:

   - `https://player0109.github.io/Textify/models/manifest.json`
   - `https://player0109.github.io/Textify/models/manifest.json.sig`

10. On a clean machine, install and dictate once with every catalog backend
   from the final signed arm64 app. Confirm diagnostics prove Metal, Neural
   Engine, or the explicitly declared CPU provider and that offline dictation
   still works after network access is disabled.

A catalog entry is not release-ready until every immutable URL returns the
signed size/hash and a clean signed-app test passes for that backend. Remote
catalog publication is optional for a new app whose newer bundled catalog is
authoritative, but it remains required when updating already-installed builds
without shipping an app update.

More detail lives in `docs/models/curated-models.md` and
`docs/models/model-manifest-signing.md`.

## Public Docs And Manual QA Gate

Before publishing the GitHub Release, verify the public docs do not promise
deferred or unsupported V1.1 behavior:

```bash
rg -n "Intel|Mac App Store|Sparkle auto|automatic update|history|per-app profile|encryption" README.md PRIVACY.md CHANGELOG.md docs
```

Any match must describe absence, deferral, or out-of-scope behavior accurately.

Then complete every release-blocking checkbox in `docs/MANUAL_QA.md`. The DMG
must pass fresh install, Gatekeeper, notarization/stapling, arm64-only binary,
permissions, Right Command dictation, insertion, clipboard, diagnostics, Launch
at Login, and Sparkle-absence checks before the release is published.

Re-run the automated release validation script before final upload if any
release files changed after the archive was created.

## Signing Boundary

The generated Xcode project uses manual ad hoc local signing for development.
Its hardened-runtime entitlements allow microphone audio input and do not
enable App Sandbox. Developer ID signing, notarization, stapling, DMG creation,
and upload are manual maintainer-machine steps. Sparkle appcast signing is
deferred with Sparkle.

Do not commit private certificates, `.p12` files, notary credentials, Sparkle
private keys, model-manifest private keys, signing environment files, generated
secrets, or Keychain exports. The verified catalog and detached signature are
intentional tracked release inputs; the signing secret is not.
