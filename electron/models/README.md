# Electron additional model catalog

`manifest.json` contains the original Confucius4-R2T2 BF16 safetensors artifact.
It is a signed v3 envelope verified with the same embedded Ed25519 key table as
the root catalog. `build.mjs` bundles both files under `textify/extra-models/`.
The original Swift schema does not admit this audio.cpp directory format, so its
catalog is kept unchanged. The Electron adapter accepts this one additional ID
and combines its presentation with the existing Confucius checkpoint.

Publisher: https://huggingface.co/netease-youdao/Confucius4-R2T2

Immutable revision: `185ce639118ad1362d049ca0d8ed04b6ec5cd6c9`.
All eleven files were downloaded and SHA-256 checked locally. The complete
directory is 4,092,092,714 bytes; `model.safetensors` is 4,076,191,640 bytes with
SHA-256 `cc4d5324d386c80f98a8a7b09fbcdcc813ad08a6503fe3a586ebb144ec4610dc`.
The original NetEase model license is linked in the entry and included, with
its Chinese version, in the existing bundled `Confucius4-R2T2.txt` notice.

Sign updates using the existing Keychain helper; never add private keys here:

```sh
TEXTIFY_MODEL_MANIFEST_KEY_ID=textify-model-manifest-2026-huggingface \
  ../script/models/sign_model_manifest.sh models/manifest.json
```

The installer verifies every file, accepts only the flat signed layout and rejects
extra installed files or symlinks before loading. Revocations cover exact IDs,
managed files and the canonical layout hash. Imports copy only signed files and
leave the user's source folder untouched.
