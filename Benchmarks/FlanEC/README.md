# FlanEC prototype

This is a throwaway, non-shipping prototype answering one question:

> Does the public FlanEC post-ASR model safely correct Textify's `to`/`two`,
> spoken filename, and `soda`/`SOTA` failures well enough to justify an app
> integration?

Run the real pinned Base checkpoint in one command:

```bash
uv run Benchmarks/FlanEC/flanec_prototype.py
```

The first run downloads about 993 MB into the standard Hugging Face cache. It
does not put model files in the repository. Later offline runs use:

```bash
uv run Benchmarks/FlanEC/flanec_prototype.py --offline
```

To simulate any current Textify one-best transcript:

```bash
uv run Benchmarks/FlanEC/flanec_prototype.py \
  --offline \
  --one-best "there are to models available" \
  --expected "there are two models available"
```

The optional Large comparison is a 3.1 GB download:

```bash
uv run Benchmarks/FlanEC/flanec_prototype.py --checkpoint large
```

## Pinned inputs

- Base: `morenolq/flanec-base-cd` at
  `e3c8a1ea702dfb2e47ce77733a31123ea18dbe56`
- Large: `morenolq/flanec-large-cd` at
  `f86eb6dbc8de5b8f2612e49ddae2db4114ef8aed`
- Model license: MIT; underlying Flan-T5 provenance is Apache-2.0.
- Generation matches the public inference script: three beams and at most 128
  new tokens.

The Python and model dependencies are prototype-only PEP 723 pins inside the
runner. They are not linked into Textify, its Swift package, or its release
bundle.

## Initial verdict — 2026-08-10

The prototype was run on an Apple M4 Max using the MPS backend. Both checkpoints
loaded successfully. Base reproduced the model card's published widget example;
Large rewrote that example incorrectly, which is additional over-correction
evidence.

| Case | Base output | Large output | Verdict |
| --- | --- | --- | --- |
| Published widget control | Exact match | Rewritten incorrectly | Base only |
| One-best `soda model` | `soda model` | `soda model` | No correction |
| N-best containing `sota` | `sota model` | `sort of model` | Wrong casing / wrong words |
| Valid beverage `soda` | Preserved | Preserved | Pass |
| One-best `to models` | Unchanged | `two models` | Large only |
| `fixes dot md` with candidates | `fixes dot m d` | `fixes dot m d` | No filename rendering |
| Already-correct `SOTA` | `s a t a` | `sato` | Harmful over-correction |

Both checkpoints passed 3 of the 9 exact-output cases. Observed warm case
latency was roughly 0.1–0.9 seconds after model loading. The first inference
also paid an MPS compilation cost of several seconds.

The answer is currently **no**: FlanEC is a legitimate N-best benchmark model,
but these checkpoints are unsafe for Textify's target examples and Textify does
not yet expose N-best hypotheses. The prototype intentionally does not connect
to the production post-processing path.
