# Canary-Qwen 2.5B Catalog Benchmark - 2026-07-20

This report records Textify's promotion evidence for the exact Canary-Qwen
2.5B model requested from the supplied Artificial Analysis comparison. It does
not generalize the English measurements to other languages.

## Immutable inputs

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `canary-qwen-2.5b-Q4_K_M.gguf` | 1,737,575,808 | `db5162229d6fa22597d06a613bd9b543eddb3ee02e6afc5e759120fde02bebf7` |

The file came from `handy-computer/canary-qwen-2.5b-gguf` revision
`3370d4e2f28cc70eea79dfc9f2f43fb91eef3163`. The original NVIDIA source is
pinned at revision `b1469e1bba1cfe140205529c79c434ca47180960`. The model and
conversion are CC-BY-4.0, its Qwen component is Apache-2.0, and Textify's
transcribe.cpp 0.1.3 runtime is pinned to
`5a5a49664a8ea1f0e5b3be1dfc544730d1b62561` under MIT.

## Method

- Host: Apple M4 Max, arm64, macOS 26.5.1 build 25F80.
- Runtime: Textify's release-built isolated transcribe.cpp dynamic adapter. It
  reported the exact Canary-Qwen architecture and Apple M4 Max Metal backend.
- Corpus: the ten fixed `dev-clean-2` utterances in `Corpus/openslr31.json`,
  totaling 210 reference words under CC BY 4.0.
- Feed: accelerated, explicit English, greedy whole-recording transcription.
- Timing: release-to-final is recorded independently for each utterance. With
  ten samples, p95 uses the nearest-rank value and is therefore the maximum.
- Accuracy: aggregate WER is total edit errors divided by total reference words;
  punctuation and capitalization are normalized by the shared scorer.

## Results

| Word errors / words | Aggregate WER | Release-to-final median | p95 | Median RTF | Peak resident memory |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 2 / 210 | 0.95% | 255.5 ms | 373 ms | 0.0312 | 3,163,389,952 bytes |

Per-clip release-to-final values, in corpus order, were 143, 216, 143, 123,
323, 295, 327, 373, 171, and 308 ms. Warm process model loads measured 490-504
ms and warmups 80-99 ms. The first native process also spent 6.555 seconds
loading the embedded ggml Metal library; later process loads used the compiled
Metal cache, so that first initialization is disclosed separately rather than
included in release-to-final latency.

## Runtime and install evidence

Textify's adapter rejects CPU fallback, automatic language detection,
non-English language selection, and audio beyond the model's 40-second quality
window. It also bypasses the autoregressive runtime for digital or near-digital
silence. The pinned dynamic library is loaded `RTLD_LOCAL` so its ggml symbols
cannot collide with Textify's separate whisper.cpp copy.

An opt-in native regression loaded the exact Q4_K_M file through the shipped
runtime directory, verified the Metal route, and produced
`A man said to the universe, Sir, I exist` under 700 ms. The signed-catalog
integration covers atomic download/install and the same runtime route when its
network-heavy opt-in gate is enabled.

## Catalog decision

The exact artifact is promoted as Accurate. It meets Textify's local-only,
immutable-artifact, Metal-routing, English accuracy, and interactive latency
gates. Its 1.74 GB download, 3.16 GB peak process footprint, English-only
coverage, and 40-second cap are disclosed directly in the picker.
