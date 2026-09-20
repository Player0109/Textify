# Confucius4-R2T2 local smoke

The integration uses audio.cpp commit
`9ba884179826c3b33dd305185b5f94c79175a03d` and
`davidxifeng/Confucius4-R2T2-gguf` revision
`a8e6b385d7df7eae9519363e07034a209004797a`, file `r2t2-q8_0.gguf`.
The 2,477,512,064-byte download was hashed locally and matches
`19f5ccd624484bcb5d44301437de41560b0ecc40c430e8850dfeefefbe82ccf5`.

The F16 version uses the same pinned publisher revision and native runtime.
Its `r2t2-f16.gguf` artifact is 4,092,155,264 bytes, with locally verified SHA-256
`d1b531ceaf5640d98352d3a9180238d99d36d393e160afd4692031077e7bae2c`.
F16 and Q8_0 are separate versions of one catalog checkpoint; Q8_0 remains
recommended. Both offer the same live preview and final-pass behavior.

The public English fixture is `assets/resources/sample_16k.wav` in that pinned
runtime checkout. `smoke-english-m4-max.txt` records the initial default-parameter
run of Textify's C shim on Apple M4 Max. Audio was supplied in real time. This
is a single smoke run, not a quality rating, representative latency benchmark,
or proof of performance on all Apple Silicon machines. The reported native
streaming flush latency excludes Textify's final-pass recognition and cleanup.

`smoke-english-preview-m4-max.txt` and `smoke-chinese-preview-m4-max.txt`
record the chosen preview settings below. First nonempty output appeared at
1.699 seconds for the English sample and 2.042 seconds for the Chinese sample
in these individual, warmed-session runs. They include audio arrival time and
are not general latency guarantees. The Chinese fixture is `resources/test.wav`
in upstream Confucius4-R2T2 commit
`80c22e6140bcb9166fb9906798894fc8b18c8309`; offline output matched the runtime's
pinned Chinese golden text exactly.

The F16 equivalents are recorded in `smoke-english-f16-preview-m4-max.txt`
and `smoke-chinese-f16-preview-m4-max.txt`. Both emitted incremental text with
real-time audio delivery and completed final recognition on M4 Max. The native
adapter switching test and the longer F16 wrapper test also passed. These are
fixture checks, not comparative quality or speed benchmarks.

Textify's chosen preview configuration uses 320 ms chunks, zero unfixed leading
chunks, and one unfixed token to emit stable words sooner than the community
runtime's default five-token rollback. Final recognition uses the complete
capture, with the existing final silence check, optional voice cleaning,
post-processing, and single insertion.

The Swift wrapper smoke also repeats the fixture across the 25-second preview
reset, then verifies a separate final pass and unload. Run it after downloading
the pinned checkpoint:

```bash
python3 - /path/to/audio.cpp/assets/resources/sample_16k.wav /tmp/confucius.f32 <<'PY'
import array, sys, wave
with wave.open(sys.argv[1]) as audio:
    assert audio.getframerate() == 16000 and audio.getnchannels() == 1
    assert audio.getsampwidth() == 2
    pcm = array.array('h', audio.readframes(audio.getnframes()))
with open(sys.argv[2], 'wb') as output:
    array.array('f', (sample / 32768 for sample in pcm)).tofile(output)
PY
TEXTIFY_CONFUCIUS_SMOKE_MODEL=/path/to/r2t2-q8_0.gguf \
TEXTIFY_CONFUCIUS_SMOKE_LIBRARY="$PWD/Vendor/audio.cpp/9ba8841/lib/libtextify-confucius.dylib" \
TEXTIFY_CONFUCIUS_SMOKE_AUDIO=/tmp/confucius.f32 \
  swift test --filter ConfuciusRuntimeTests
```

For F16 preview, final recognition, and switching F16 → Q8_0 → F16 through
Textify's production adapter and the signed catalog's Automatic language
setting, also run:

```bash
TEXTIFY_CONFUCIUS_SMOKE_F16_MODEL=/path/to/r2t2-f16.gguf \
TEXTIFY_CONFUCIUS_SMOKE_MODEL=/path/to/r2t2-q8_0.gguf \
TEXTIFY_CONFUCIUS_SMOKE_LIBRARY="$PWD/Vendor/audio.cpp/9ba8841/lib/libtextify-confucius.dylib" \
TEXTIFY_CONFUCIUS_SMOKE_AUDIO=/tmp/confucius.f32 \
  swift test --filter ConfuciusRuntimeAdapterTests
```

The longer wrapper smoke above can also test F16 by setting
`TEXTIFY_CONFUCIUS_SMOKE_MODEL` to `r2t2-f16.gguf`.

These fixtures contain public sample speech only. No user dictation is saved.
