# Dictation promo source

This 42-second, 1920 × 1080, 30 fps promotion illustrates macOS global-shortcut
dictation in a sample email and document. It is an animation, not recorded proof
of automatic insertion or a transcription-speed benchmark.

## Visuals

`edit.js` uses the native Higgsedit 0.14.0 composition API: editable text,
rectangles, icons, media and timed motion tracks. It uses Inter and the native
Lucide icon library. The logo is the existing Textify app icon. No generated
third-party application screenshots are used.

The recording bar is reconstructed from the current app's actual reference
capture. It identifies the destination on the left and Textify on the right.
Both scenes insert the entire final sentence after the illustrated shortcut
release and processing state. No destination text streams while speech plays.

With the native Higgsedit CLI available, stage a working directory:

```sh
cp docs/media/promo-source/edit.js /path/to/work/edit.js
cp electron/assets/textify-icon.png /path/to/work/textify-icon.png
cd /path/to/work
higgsedit build edit.js
higgsedit check textify-promo
higgsedit render textify-promo --out renders/visual.mp4 --quality final --depth 8 --bitrate 8M
```

The hosted Higgsfield environment supplied the native CLI for this production.
It is not an npm dependency of Textify. The script exports eight proof frames
before the full render. Frame paths and imported assets are project-relative.

## Audio

`audio.py` creates six synthetic speech segments through the configured TTS
service. The `announcer_kenney_male` preset narrates, and
`announcer_kenney_female` speaks the two dictated examples. The service identifies
their reference material as the CC0 Kenney Voiceover Pack. `audio.json` records
the text, voice identities, cue times and measured durations. Voice synthesis is
a production tool; these are not recordings of a person using Textify.

The same script composes an original D-major instrumental bed from oscillators,
soft pads and piano-like notes. It uses no stock recording or sampled instrument.
Music ducks beneath speech. Narration and the dictation examples never overlap.
The WAV mix measures approximately −16 LUFS integrated and −1.7 dBTP. The final
AAC video mix, with another 0.5 dB of headroom, measures −16.5 LUFS and −2.2 dBTP.

Use Python 3, NumPy, curl, ffmpeg and ffprobe. Pass the local service guide and
an output directory. The private service URL is read at runtime and must never
be committed. Only the promotion's script is sent for speech generation; this
service is not an application dependency.

```sh
python3 docs/media/promo-source/audio.py \
  --service-guide /private/path/to/AGENT_GUIDE.md --output-dir /path/to/audio
```

Existing generated takes can be remixed without a service call using
`--takes-dir /path/to/takes --output-dir /path/to/audio`. All six published takes
fit without time stretching. Silence trimming preserves a short margin around
speech, and both dictation examples finish before the illustrated key release.

```sh
ffmpeg -i textify-promo/renders/visual.mp4 -i audio/finalmix.wav \
  -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k \
  -af volume=-0.5dB -t 42 -movflags +faststart textify-promo.mp4
```

The video carries an animated-workflow disclosure during both writing scenes.
Its end card calls out the hardware GPU requirement and Linux's Copy + paste
workflow. The README and release notes retain the full platform requirements.

`delivery.json` records the final media hashes, dimensions, audio measurements
and verification performed. The GIF is a full-length, silent 960 × 540 preview.
