# Whisper Large V2/V3 Catalog Benchmark - 2026-07-20

This report records the promotion evidence for the exact Whisper Large V2 and
V3 q5_0 artifacts requested from the supplied Artificial Analysis comparison.
It does not generalize these English measurements to other languages.

## Immutable inputs

| Model | File | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Whisper Large V2 | `ggml-large-v2-q5_0.bin` | 1,080,732,091 | `3a214837221e4530dbc1fe8d734f302af393eb30bd0ed046042ebf4baf70f6f2` |
| Whisper Large V3 | `ggml-large-v3-q5_0.bin` | 1,081,140,203 | `d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1` |

Both files came from `ggerganov/whisper.cpp` revision
`c521a4b02f422512d734391fdf08bb08c0862f68`. Local byte sizes and SHA-256
digests matched the signed catalog before inference.

## Method

- Host: Apple M4 Max, arm64, macOS 26.5.1 build 25F80.
- Runtime: Textify's release-built whisper.cpp adapter with the Metal backend
  requested; the benchmark records that individual CPU operations may remain.
- Corpus: the ten fixed `dev-clean-2` utterances in `Corpus/openslr31.json`,
  totaling 210 reference words under CC BY 4.0.
- Feed: accelerated, English forced, greedy decoding, no prior context.
- Timing: release-to-final is recorded independently for each utterance. With
  ten samples, p95 uses the nearest-rank value and is therefore the maximum.
- Accuracy: aggregate WER is total edit errors divided by total reference words.

## Results

| Model | Word errors / words | Aggregate WER | Release-to-final median | p95 | Median RTF | Peak resident memory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Whisper Large V2 q5_0 | 7 / 210 | 3.33% | 551 ms | 746 ms | 0.0775 | 1,489,108,992 bytes |
| Whisper Large V3 q5_0 | 8 / 210 | 3.81% | 542.5 ms | 728 ms | 0.0788 | 1,494,908,928 bytes |

The V3 run also captured an 8.543-second first cold load while Metal initialized;
subsequent per-process loads were 266-275 ms. V2 was run after Metal had already
initialized and recorded 261-277 ms loads, so those load distributions are not
a fair cold-start comparison.

## Catalog decision

Both exact artifacts remain Experimental. They meet Textify's offline, immutable
artifact, Metal-routing, English accuracy, and release-to-final evidence gates,
but their approximately 1.08 GB downloads and 1.5 GB peak resident footprints
are materially larger than the default. Only English is advertised until each
additional language has equivalent fixed-corpus evidence.
