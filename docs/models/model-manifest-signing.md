# Model Manifest Signing

The retained catalog tools support model-manifest versions 1, 2, and 3. The
Electron desktop app accepts manifest v3 and revocation versions 1 and 2 with
the canonical detached JSON signature envelope. The envelope records the
SHA-256 of the exact raw JSON bytes. Do not reformat or rewrite those bytes
between signing and publishing.

The root Swift package contains catalog verification tools, not an application.
Catalog validity and desktop model support are separate: see the
[desktop guide](../../electron/README.md) for the implemented artifact subset.

## Secret Boundary

Never commit private keys, seeds, `.env` files, or generated secrets. The
verified `models/manifest.json` and `models/manifest.json.sig` pair is an
intentional tracked release input; only the public key and key ID are embedded
in source.

The preferred local store is the macOS Keychain service
`io.github.Player0109.Textify.model-manifest-signing`. The optional
`TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64` override is the base64-encoded
CryptoKit raw Ed25519 private key representation, not a PEM file. Use that
override only in a protected release environment and unset it immediately.

`TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64` is the base64-encoded CryptoKit raw
Ed25519 public key representation. The matching public key and `keyId` are safe
to publish and embed in the app.

## Sign

```bash
script/models/create_model_manifest_signing_key.sh \
  textify-model-manifest-2026-huggingface

TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-huggingface' \
  script/models/sign_model_manifest.sh path/to/manifest.json
```

The key-creation helper creates or reuses the Keychain item and prints only the
public key, key ID, and Keychain service. The signing helper reads the private
key from that item without printing it.

The script writes `path/to/manifest.json.sig` with this envelope shape:

```json
{
  "algorithm": "Ed25519",
  "contentSHA256": "<lowercase SHA-256 of the exact manifest bytes>",
  "contentType": "application/vnd.textify.model-manifest+json;version=3",
  "keyId": "textify-model-manifest-2026-huggingface",
  "manifestFile": "manifest.json",
  "signature": "<unpadded base64url Ed25519 signature>",
  "signatureType": "io.github.Player0109.Textify.model-manifest",
  "signatureVersion": 1
}
```

## Sign The Bundled Revocation Pair

The independently typed revocation envelope may use the same allowlisted
maintainer key, but it is signed over the distinct model-revocations canonical
payload. Create or review `models/revocations.json`, advance its `generatedAt`
revision monotonically, then run:

```bash
TEXTIFY_MODEL_REVOCATION_KEY_ID='textify-model-manifest-2026-huggingface' \
  script/models/sign_model_revocations.sh \
    models/revocations.json \
    models/revocations.json.sig

TEXTIFY_MODEL_REVOCATION_KEY_ID='textify-model-manifest-2026-huggingface' \
  script/models/verify_model_revocations.sh \
    models/revocations.json \
    models/revocations.json.sig
```

The signer reads the matching private key from the existing manifest-signing
Keychain service by default; a separately managed service can be named with
`TEXTIFY_MODEL_REVOCATION_KEYCHAIN_SERVICE`. Only the exact signed pair and
public trust entry are committed. The private key is never printed or copied
into the repository.

The Electron verifier requires the canonical envelope's exact fields. Legacy
signature formats accepted by archival tooling are not accepted desktop inputs.

The signing helper reads `manifestVersion` from the exact input bytes and
emits the matching content type. Versions 1, 2, and 3 are accepted, and
verification rejects a correctly signed envelope when its content-type version
differs from the parsed manifest version.

## Verify Before Publishing

The signature covers a canonical UTF-8 payload with exactly this field order
and a final LF:

```text
TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1
signatureVersion=1
signatureType=io.github.Player0109.Textify.model-manifest
algorithm=Ed25519
keyId=<trusted key ID>
manifestFile=manifest.json
contentType=application/vnd.textify.model-manifest+json;version=<manifest version>
contentSHA256=<lowercase SHA-256 of the exact JSON bytes>
```

For revocations, use `TEXTIFY-MODEL-REVOCATIONS-SIGNATURE-V1`, the
`io.github.Player0109.Textify.model-revocations` signature type,
`revocationFile=revocations.json`, and the
`application/vnd.textify.model-revocations+json;version=<revocation version>`
content type in the same positions. The Ed25519 signature is encoded as
unpadded base64url in the envelope. The signature does not sign itself. The
desktop implementation is [trust.ts](../../electron/src/main/trust.ts).

```bash
export TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64='<raw public key base64>'
export TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-huggingface'

script/models/verify_model_manifest.sh path/to/manifest.json path/to/manifest.json.sig
```

Verification checks the detached signature and the production catalog policy:

- strict signature-envelope fields
- exact manifest-byte SHA-256 binding
- canonical payload and unpadded base64url signature validation
- one or more unique safe model identifiers
- a supported engine/accelerator/artifact-layout combination
- a positive model-specific capture window; Paraformer entries are capped at
  29 seconds because the released Core ML preprocessor accepts at most 30
  seconds and Textify reserves room for capture/tap timing
- immutable HTTPS Textify GitHub Release URLs or exact Hugging Face
  `resolve/<40-character-lowercase-commit>/<path>` URLs; mutable refs,
  authority/suffix overrides, percent encoding, and traversal are rejected
- positive per-file sizes and 64-character lowercase SHA-256 values
- exact model-size totals, unique filenames, and safe unique relative paths for
  multi-file model directories
- signed positive `installationStorage.finalArtifactBytes` and
  `installationStorage.peakInstallationBytes` bounds for every production
  artifact; the peak must be at least both the transfer total and final
  artifact size so unknown or unbounded installation layouts fail closed
- non-empty language capabilities for new catalog entries
- optional picker metadata for finalization speed, accuracy tradeoff, and
  hardware/runtime requirements; when present, every field must be non-empty
- optional manifest-v2 benchmark metadata with strict nested fields, the
  direct-score `english-catalog-rating-v2` policy, exact 932-case v1
  suite-index hash, three Apple M4 Max runs, exact runtime identity, source Git
  revision, internally consistent absolute score math, and an artifact
  fingerprint recomputed from the signed file paths, hashes, and sizes
- a manifest-v3 presentation graph in which every exact artifact appears once
  under one checkpoint and family, with valid signed order, recommendation,
  fallback, format, numeric format, runtime, compute route, and compatibility
  metadata

Manifest v1 remains valid and cannot contain `benchmark`. Manifest v2 adds
benchmark evidence, and manifest v3 retains those exact operational records
while requiring the normalized presentation graph. A model may leave
`benchmark` absent. Existing ratings and benchmark records are retained as
historical provenance; the legacy benchmark runner has been retired. They do
not establish Electron accuracy or performance. Keep a v3 production catalog
at v3, preserve its graph mapping, and verify any metadata change before
signing. No automated workflow receives a manifest private key.

The retained base-catalog policy includes these historical runtime tuples.
This table is not the desktop app's supported-model list:

| Engine | Accelerator | Artifact layout |
| --- | --- | --- |
| `whisper_cpp` | `metal_gpu` | `single_file` |
| `fluid_audio_parakeet` | `coreml_neural_engine` | `model_directory` |
| `fluid_audio_paraformer` | `coreml_neural_engine` | `model_directory` |
| `sherpa_onnx` | `cpu` | `model_directory` |
| `transcribe_cpp` | `metal_gpu` | `single_file` |
| `mlx_audio` | `metal_gpu` | `model_directory` |
| `litert_lm` | `metal_gpu` | `single_file` |

Every Core ML leaf file must have a safe unique `relativePath`. The signed
catalog may advertise only a released variant implemented by the pinned
FluidAudio version; a conversion repository existing on its own is not enough.

The desktop build copies the root signed pairs into `electron/resources/` and
its supplementary pair into `electron/resources/extra-models/`. Packaging
includes them in the app's `textify` resource directory. The app verifies both
catalogs locally and selects only implemented exact artifacts. Catalog changes
require a new desktop app release. Model weights are never embedded in the app.

There is no runtime catalog endpoint. The old native-app endpoint and
bundle-publication helpers have been retired; use the
[bundled catalog release rules](catalog-publication-and-rollback.md).

Model files may use an immutable Textify GitHub Release asset, for example:

`https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.bin`

or an exact public Hugging Face file, for example:

`https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/aed02740059203c4a87495924f685de3722ae9ce/parakeet_vocab.json`

Every manifest file record still requires the exact byte size and lowercase
SHA-256. Every model record also requires precise signed final-artifact and
peak-installation byte bounds appropriate to direct staging, directory
assembly, expansion, conversion, or replacement. A repository being public
does not make `main`, a tag, or an unpinned download eligible for production.

For a selected Hugging Face runtime directory, generate the reproducible
`sizeBytes` and `files` fragment from the downloaded bytes with:

```bash
script/models/create_huggingface_file_list.sh \
  FluidInference/parakeet-tdt-ctc-110m-coreml \
  9bc92ead6e8f17eca92a869fd578ae76842b82ba \
  /path/to/parakeet-tdt-ctc-110m \
  parakeet-110m
```

The local directory must contain only the runtime leaves Textify will install.
The helper excludes Hugging Face cache metadata, sorts paths deterministically,
hashes the exact bytes, totals their sizes, and emits commit-pinned URLs. It
does not decide which repository files are required or whether a model is
licensed and benchmarked for promotion.
