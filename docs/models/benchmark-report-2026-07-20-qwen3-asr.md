# Qwen3-ASR MLX and GGUF benchmark record

Date: 2026-07-20

Host: Apple M4 Max, arm64, macOS 26.5.1 build 25F80

Status: eight Experimental catalog entries accepted with Automatic and
explicit compatible-language routing and a 60-second recording cap.

## Exact artifacts

| Catalog entry | Source and immutable revision | Selected artifact | Bytes | SHA-256 |
| --- | --- | --- | ---: | --- |
| `qwen3-asr-0.6b-mlx-8bit` | `mlx-community/Qwen3-ASR-0.6B-8bit` at `89e96d92ba34aca20b3e29fb10cc284097d1219f` | Complete nine-file MLX directory | 1,010,771,234 | Weights: `b5bfe4abc1b4c6e58b633096682ec2b6297298add1527119936107d211adf0e8` |
| `qwen3-asr-1.7b-mlx-8bit` | `mlx-community/Qwen3-ASR-1.7B-8bit` at `a8379a2e2f9e313c9292cdf1af4055ab56d50d55` | Complete nine-file MLX directory | 2,467,856,503 | Weights: `bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c` |
| `qwen3-asr-0.6b-bf16` | `handy-computer/Qwen3-ASR-0.6B-gguf` at `e4e16599b900eb0cb36e524514756bb92eb092b7` | `Qwen3-ASR-0.6B-BF16.gguf` | 1,571,490,016 | `dadb8196937aa6b998a94124a043fce694e0ab6c3c6eb0ae1669fa49d04aab84` |
| `qwen3-asr-0.6b-q8-0` | Same 0.6B GGUF revision | `Qwen3-ASR-0.6B-Q8_0.gguf` | 850,423,456 | `f081b2d5e23bd669d92cc331d722a8a0681943b8e6f34b48996fd5c319b5acd8` |
| `qwen3-asr-0.6b-q5-k-m` | Same 0.6B GGUF revision | `Qwen3-ASR-0.6B-Q5_K_M.gguf` | 645,356,192 | `062a7bcb18675c2fe5ffd0e8b354eac6a1ceada9b2af9ef7168746ae16b54358` |
| `qwen3-asr-1.7b-bf16` | `handy-computer/Qwen3-ASR-1.7B-gguf` at `92282af1610a2db19d66f2bef1e260f5deca782d` | `Qwen3-ASR-1.7B-BF16.gguf` | 4,083,087,904 | `57db745f8ec3ad2ea391b0205661e7d74f76158877a33f151e4d4624ed2b7cc9` |
| `qwen3-asr-1.7b-q8-0` | Same 1.7B GGUF revision | `Qwen3-ASR-1.7B-Q8_0.gguf` | 2,185,030,624 | `9a0d81792dfea2d5f278b8a63deb3ea6e02139ce42c2301f32ea19c4f77526b7` |
| `qwen3-asr-1.7b-q5-k-m` | Same 1.7B GGUF revision | `Qwen3-ASR-1.7B-Q5_K_M.gguf` | 1,517,290,464 | `034c557fe92ff8fcd9a9c041cbdaad347be0a86a58d3a348f63cf3f0180879d0` |

Every MLX inference file, not only the weights named above, matched the size
and SHA-256 in `models/manifest.json`. All model and conversion repositories
declare Apache-2.0. The MLX Audio Swift, MLX Swift, and transcribe.cpp runtime
layers are MIT.

## Runtime choice

The two MLX directories run through Textify's existing pinned native
`mlx-audio-swift` dependency at commit
`d302a5c6080d2bb97bae38c7418f82abb76013b6`, which includes
`Qwen3ASRModel`, and MLX Swift 0.31.3 at
`61b9e011e09a62b489f6bd647958f1555bdf2896`. The six GGUF files run through
the isolated transcribe.cpp 0.1.3 Metal runtime at commit
`5a5a49664a8ea1f0e5b3be1dfc544730d1b62561`.

Textify does not add the Python `mlx-lm`, `mlx-vlm`, or `mlx-audio` packages.
`mlx-swift-examples` is example code rather than an application runtime. The
native Swift speech package already supplies the required local-directory
Qwen3-ASR loader, so adding those packages would not improve the shipping
runtime.

Both routes require the actual Metal backend. With Automatic selected, MLX
receives no language prompt and the Textify C shim maps its internal `auto`
sentinel to a null transcribe.cpp language parameter. With an explicit
compatible language selected, Textify forwards the normalized language through
the native MLX or transcribe.cpp route and disables detection. A language not
declared by the signed catalog entry or accepted by the runtime variant fails
closed before inference.

## Fixed English corpus

The benchmark used all ten utterances in `Corpus/openslr31.json`: 219 reference
words from Mini LibriSpeech `dev-clean-2`. Each row below is corpus WER, median
and p95/max trigger-release-to-final latency, maximum process RSS, and median
warm model-load time across ten separate release-process runs.

| Route | WER | Median | p95/max | Peak RSS | Median load |
| --- | ---: | ---: | ---: | ---: | ---: |
| MLX 0.6B 8-bit | 3.20% | 191.5 ms | 277 ms | 1.15 GB | 351.5 ms |
| MLX 1.7B 8-bit | 1.83% | 211.5 ms | 421 ms | 2.62 GB | 397 ms |
| GGUF 0.6B BF16 | 3.65% | 178.5 ms | 305 ms | 2.61 GB | 431.5 ms |
| GGUF 0.6B Q8_0 | 3.65% | 156.5 ms | 260 ms | 1.57 GB | 283.5 ms |
| GGUF 0.6B Q5_K_M | 3.65% | 174.5 ms | 283 ms | 1.26 GB | 241.5 ms |
| GGUF 1.7B BF16 | 3.33% | 317.5 ms | 545 ms | 6.52 GB | 961.5 ms |
| GGUF 1.7B Q8_0 | 3.33% | 231 ms | 393 ms | 3.64 GB | 572.5 ms |
| GGUF 1.7B Q5_K_M | 3.33% | 210 ms | 346 ms | 2.63 GB | 430 ms |

Every route reproduced the first reference at zero WER in an explicit native
smoke. Metal device evidence was returned by each Textify runtime. The first
GGUF smoke after introducing the transcribe.cpp executable incurred a one-time
6.9-second Metal library/pipeline preparation; its 7.14-second total load is
not hidden by the warm-process median above.

## Automatic Hindi corpus

The multilingual check used all ten fixed FLEURS `hi_in` validation fixtures:
440 normalized reference words and 557 normalized reference characters.

| Representative route | WER | CER | Median | p95/max | Peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| MLX 0.6B 8-bit | 15.00% | 12.39% | 529.5 ms | 627 ms | 1.16 GB |
| MLX 1.7B 8-bit | 14.77% | 11.67% | 894 ms | 1,142 ms | 2.61 GB |
| GGUF 0.6B Q5_K_M | 11.36% | 10.05% | 504 ms | 717 ms | 1.26 GB |
| GGUF 1.7B Q5_K_M | 10.00% | 7.00% | 737.5 ms | 920 ms | 2.63 GB |

These runs prove that both engine families perform automatic non-English
recognition. They do not constitute per-language quality evidence for every
one of the 30 upstream-declared languages. The entries therefore remain
Experimental, and their picker text reports only the measured English and
Hindi results.

## Product interpretation

- MLX 1.7B delivered the best English WER in this slice.
- Q5_K_M is the practical GGUF choice for each size: the larger quantizations
  showed no English WER advantage here and used substantially more memory.
- GGUF 1.7B Q5_K_M delivered the best measured Hindi quality, but its Hindi
  p95 exceeded the 700 ms interactive target.
- All eight requested artifacts remain available as explicit choices so users
  can select precision, download size, and memory tradeoffs themselves.

The catalog is signed only after the exact measurements above are reflected in
each entry's finalization, accuracy, and requirements copy.
