# Releasing Textify V1.1

This document covers the V1.1 local release workflow. It does not add Sparkle,
notarization secrets, DMG upload automation, appcast hosting, or bundled model
weights. The small signed catalog is bundled as a trusted baseline. Sparkle
remains deferred, so users update manually by downloading the next GitHub
Release DMG.

## Model workflow fault evidence

Before assembling release-candidate evidence, run:

```bash
script/release/run_model_fault_campaign.sh dist/release-evidence/model-faults
```

Retain the generated report, focused production-path test log, seed, and
checksums. The campaign is release-only and uses generated localhost fixture
bytes; it does not contact the production catalog or fetch model artifacts.
See `docs/models/model-fault-campaign.md` for the covered matrix.

## Release-candidate evidence sign-off

Start from `docs/release/release-evidence-template.json`, retain every evidence
attachment below one release-candidate directory, and fill the declaration
with exact relative paths and lowercase SHA-256 values. Then run:

```bash
script/release/assemble_release_evidence.sh \
  dist/release-evidence/declaration.json \
  dist/release-evidence \
  dist/release-evidence/release-evidence-bundle.json
```

The gate binds the declaration to the current Git commit and current
`docs/SPEC.md`. It fails on incomplete semantic UI or manual accessibility
coverage, insufficient real-device performance, an unexercised Compute Route,
unacceptable defects, missing independent critical reviews, changed
attachments, or fewer than two distinct human approvals. See
`docs/release/release-evidence.md` for the full declaration contract.

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

5. Record exact signed `installationStorage.finalArtifactBytes` and
   `installationStorage.peakInstallationBytes` for every artifact. Measure the
   peak across directory staging, expansion, conversion, and atomic replacement
   when those transformations apply; direct artifacts normally use
   `model.sizeBytes` for both values. Do not publish an unknown or unbounded
   peak.

6. Complete every catalog field: unique model id, tier, languages, runtime
   engine/variant/accelerator/layout, minimum app version, decoding parameters,
   hallucination thresholds, licenses, provenance, expected finalization,
   accuracy tradeoff, and requirements. Do not add near-duplicate choices that
   provide no measured advantage.

   If manifest v3 intentionally contains multiple Exact Artifact IDs with the
   same typed artifact digest, add a signed `artifactAliases` entry only when
   one identity is the reviewed canonical target. The alias and canonical IDs
   must both exist and have equal typed digests. Never use an alias to bridge
   different bytes, a missing artifact, a self-reference, or an alias chain;
   without a valid signed alias, installed-content matching remains ambiguous
   and fails closed.

7. For manifest v2 measured ratings, review the unsigned
   `english-catalog-rating-v2` candidate generated from three complete runs of
   the checksum-pinned `english-catalog-rating-v1` suite on the reference M4
   Max. Confirm its artifact fingerprint matches the final signed file list,
   its quality level maps directly from its quality score, the speed result
   passed the repeated-run stability gate, and the model page shows the
   no-speech rate as separate raw evidence. Models without that evidence remain
   `Unrated`; do not substitute their tier. Nightly output is candidate
   evidence only and must never sign or rewrite the production manifest.

8. Create or reuse the Keychain signing key and sign the canonical envelope for
   the exact raw `manifest.json` bytes. The generated envelope binds the
   manifest SHA-256, content type, filename, algorithm, and key ID before
   signing.

   ```bash
   script/models/create_model_manifest_signing_key.sh \
     textify-model-manifest-2026-huggingface

   TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-huggingface' \
     script/models/sign_model_manifest.sh path/to/manifest.json
   ```

9. Verify the detached signature and production manifest policy with the public
   key before publishing.

   ```bash
   export TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64='<raw public key base64>'
   export TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-huggingface'
   script/models/verify_model_manifest.sh path/to/manifest.json path/to/manifest.json.sig
   ```

   For manifest v3 publication, also run the complete catalog/revocation
   publication gate and retain its JSON evidence. The gate binds both signer
   identities, both monotonic revisions, and the exact app build identity:

   ```bash
   script/models/prepublish_model_catalog.sh \
     path/to/manifest.json \
     path/to/manifest.json.sig \
     path/to/revocations.json \
     path/to/revocations.json.sig \
     build/release/Textify.app \
     build/release/catalog-publication-evidence.json \
     path/to/previous-catalog-publication-evidence.json
   ```

   The previous evidence argument is mandatory for normal publication. Only
   the audited first v3 authority baseline may use a leading `--bootstrap` and
   omit it; retain that baseline evidence permanently.

10. Replace the tracked `models/manifest.json` and `.sig`, build the app, and
   verify the exact same bytes are embedded under
   `Contents/Resources/ModelCatalog/`. A valid remote catalog older than this
   bundled baseline cannot downgrade it.

11. Publish both manifest files to GitHub Pages when updating the remote
   catalog for installed builds:

   - `https://player0109.github.io/Textify/models/manifest.json`
   - `https://player0109.github.io/Textify/models/manifest.json.sig`

12. Review the independently signed model revocation pair before publishing
   catalog changes:

   - `https://player0109.github.io/Textify/models/revocations.json`
   - `https://player0109.github.io/Textify/models/revocations.json.sig`

   Every record must have an immutable stable `recordID` and target an Exact
   Artifact ID, a lowercase SHA-256 with one explicit supported digest scope,
   or both. Both targets use OR semantics. Never derive identity from a
   filename or publish an unscoped digest. A new envelope may add records but
   must not mutate or omit a previously published record as a removal
   mechanism; installed clients retain accepted records across omission.
   A restoration requires revocation schema version 2, a higher signed
   revision, a new immutable `restorationID`, the exact prior `recordID`, and
   one or both prior targets repeated byte-for-byte. Never use a restoration to
   clear another overlapping record or to name a compatible replacement.
   Verify the detached Ed25519 signature over the exact JSON bytes and publish
   the JSON/signature pair before or atomically with a catalog update that
   changes how an affected artifact is presented.

   Revocation lookup is private and local. Do not add query parameters,
   request bodies, per-install endpoints, telemetry, or any publication flow
   that receives installed Artifact IDs, Custom hashes, local filenames, or
   storage inventory.

13. On a clean machine, install and dictate once with every catalog backend
   from the final signed arm64 app. Confirm diagnostics prove Metal, Neural
   Engine, or the explicitly declared CPU provider and that offline dictation
   still works after network access is disabled.

14. Before changing the live GitHub Pages files, run the real endpoint smoke
    against the staged HTTPS endpoint. This verifies both exact signed pairs
    and writes endpoint evidence without downloading model artifacts:

    ```bash
    script/models/smoke_model_catalog_endpoint.sh \
      'https://<staging-host>/Textify/models' \
      build/release/Textify.app \
      build/release/catalog-endpoint-evidence.json \
      path/to/previous-catalog-publication-evidence.json
    ```

15. Rehearse withdrawal with the designated v3 rollback bridge and retain its
    log. Never present an arbitrary pre-v3 application downgrade as recovery.
    Catalog corrections require a higher revision; security withdrawal uses a
    higher signed revocation; restoration follows the signed restoration
    protocol and never silently reactivates a model.

A catalog entry is not release-ready until every immutable URL returns the
signed size/hash and a clean signed-app test passes for that backend. Remote
catalog publication is optional for a new app whose newer bundled catalog is
authoritative, but it remains required when updating already-installed builds
without shipping an app update.

More detail lives in `docs/models/curated-models.md` and
`docs/models/model-manifest-signing.md`. Publication identities, revision
rules, additive state ownership, and the designated rollback contract are in
`docs/models/catalog-publication-and-rollback.md`.

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
