# Model Manifest Signing

Textify model-manifest versions 1 and 2 use a detached JSON signature envelope at
`manifest.json.sig`. The envelope records the SHA-256 of the exact raw manifest
bytes, and the Ed25519 signature covers the canonical UTF-8 payload defined in
`docs/SPEC.md` section 22.2. Do not reformat or rewrite the manifest between
signing and publishing.

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
  "contentType": "application/vnd.textify.model-manifest+json;version=2",
  "keyId": "textify-model-manifest-2026-huggingface",
  "manifestFile": "manifest.json",
  "signature": "<unpadded base64url Ed25519 signature>",
  "signatureType": "io.github.Player0109.Textify.model-manifest",
  "signatureVersion": 1
}
```

The app and verification helper temporarily accept the previously deployed
four-field raw-byte signature envelope so existing V1.1 installs can still
download the production model. The signing helper emits only the canonical
SPEC envelope; republish the live signature in that format at the next
maintainer signing opportunity.

The signing helper reads `manifestVersion` from the exact input bytes and
emits the matching content type. Versions 1 and 2 are the only accepted values,
and verification rejects a correctly signed envelope when its content-type
version differs from the parsed manifest version.

## Verify Before Publishing

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
- non-empty language capabilities for new catalog entries
- optional picker metadata for finalization speed, accuracy tradeoff, and
  hardware/runtime requirements; when present, every field must be non-empty
- optional manifest-v2 benchmark metadata with strict nested fields, the
  direct-score `english-catalog-rating-v2` policy, exact 932-case v1
  suite-index hash, three Apple M4 Max runs, exact runtime identity, source Git
  revision, internally consistent absolute score math, and an artifact
  fingerprint recomputed from the signed file paths, hashes, and sizes

Manifest v1 remains valid and cannot contain `benchmark`. Manifest v2 may
leave a model without `benchmark`; the app then shows quality and speed as
`Unrated`. An eligible candidate is generated under
`Benchmarks/RealtimeASR` and reviewed manually:

```bash
./generate_english_catalog_rating.sh \
  MODEL_ID MEASURED_AT RUN_ID_1 RUN_ID_2 RUN_ID_3 candidate.json
```

Copy the complete candidate object into that model entry's `benchmark`
field, change the document to `manifestVersion: 2`, run the verification
tests, and only then sign with the maintainer key. Nightly workflows never
modify the catalog and never receive a manifest private key.

The production runtime tuples are deliberately closed:

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

The app release embeds this signed pair under
`Contents/Resources/ModelCatalog/`. The app verifies it at runtime and selects
a valid remote catalog only when the remote signed `generatedAt` timestamp is
at least as new; remote failure falls back to the complete valid bundled pair.
Model weights are never embedded in the app.

After verification, the same pair may also be published to GitHub Pages:

- `https://player0109.github.io/Textify/models/manifest.json`
- `https://player0109.github.io/Textify/models/manifest.json.sig`

Model files may use an immutable Textify GitHub Release asset, for example:

`https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.bin`

or an exact public Hugging Face file, for example:

`https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/aed02740059203c4a87495924f685de3722ae9ce/parakeet_vocab.json`

Every manifest file record still requires the exact byte size and lowercase
SHA-256. A repository being public does not make `main`, a tag, or an unpinned
download eligible for production.

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
