# MLX Metal library

`mlx.metallib` contains the ahead-of-time Metal kernels required by Textify's
pinned `mlx-swift` dependency. Command-line SwiftPM cannot compile these
shaders, so Textify embeds the exact verified library beside its executable.

- Source: `https://github.com/ml-explore/mlx-swift`
- Revision: `61b9e011e09a62b489f6bd647958f1555bdf2896`
- MLX Swift package version: `0.31.3`
- Minimum deployment target: macOS 14.0
- Entry points: the nine generated `.metal` files validated by
  `script/build_mlx_metallib.sh`
- SHA-256: `cffe8fbfa9cfb794f1d920ff187016f823a555f7814cede99026699a936b92c7`
- License: MIT; see `THIRD_PARTY_LICENSES/MLXSwift.txt`

Rebuild from the pinned SwiftPM checkout:

```sh
script/build_mlx_metallib.sh Vendor/mlx-swift/0.31.3/mlx.metallib
```
