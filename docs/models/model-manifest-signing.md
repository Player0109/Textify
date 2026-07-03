# Model Manifest Signing

Textify V1.1 model manifests use a detached JSON signature envelope at
`manifest.json.sig`. The Ed25519 signature is over the exact raw
`manifest.json` bytes. Do not canonicalize, reformat, or rewrite the manifest
between signing and publishing.

## Secret Boundary

Never commit private keys, seeds, `.env` files, generated secrets, or generated
production signatures.

`TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64` is the base64-encoded CryptoKit raw
Ed25519 private key representation. It is not a PEM file. Keep it in local
encrypted or offline storage only.

`TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64` is the base64-encoded CryptoKit raw
Ed25519 public key representation. The matching public key and `keyId` are safe
to publish and embed in the app.

## Sign

```bash
export TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64='<local raw private key base64>'
export TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-primary'

script/models/sign_model_manifest.sh path/to/manifest.json

unset TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64
```

The script writes `path/to/manifest.json.sig` with this envelope shape:

```json
{
  "algorithm": "Ed25519",
  "keyId": "textify-model-manifest-2026-primary",
  "signatureBase64": "...",
  "signatureVersion": 1
}
```

## Verify Before Publishing

```bash
export TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64='<raw public key base64>'
export TEXTIFY_MODEL_MANIFEST_KEY_ID='textify-model-manifest-2026-primary'

script/models/verify_model_manifest.sh path/to/manifest.json path/to/manifest.json.sig
```

Verification checks the detached signature and the V1.1 production manifest
policy:

- exactly one model entry
- model id `ggml-small.en-q5_1`
- one file named `ggml-small.en-q5_1.bin`
- HTTPS Textify GitHub Release asset URL
- 64-character lowercase hex SHA-256
- English runtime language

After verification, publish both files to GitHub Pages:

- `https://player0109.github.io/Textify/models/manifest.json`
- `https://player0109.github.io/Textify/models/manifest.json.sig`

The model binary itself is published as a Textify GitHub Release asset, for
example:

`https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.bin`
