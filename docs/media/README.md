# Video provenance

## Promotion video

`textify-ad.mp4` is a 45-second motion graphic promotion in 1080p at 30 fps,
with synthetic voiceover, one spoken dictation example, music and sound effects.
The README uses GitHub's video player for playback with sound, volume controls
and seeking. The repository MP4 remains available as a download.
`textify-ad.gif` is the earlier silent preview: the shortcut and email dictation
scenes, from 5.1 to 18.55 seconds.

The frames are HTML, CSS and SVG animation rendered with
[HyperFrames](https://github.com/heygen-com/hyperframes). The Textify logo is the
existing app asset and the only image in the video; all text is set in Inter.
The writing apps (an email draft, notes, a document, code and chat) are generic
illustrations, not footage of named products, and the recording bar is a
simplified drawing of the app's floating bar. The dictated email appears once
after release and processing, matching the macOS shortcut workflow. These scenes
are not evidence of microphone capture, cross-app insertion or measured
recognition speed.

Narration and the dictated example are synthetic speech from the configured TTS
service, cloned from a reference clip supplied by the project owner
(`voice_preview_beth`). The music is a track from the HeyGen music library, cut
to the edit and ducked beneath speech. The keyboard, click, whoosh, pop and
impact sounds come from the HeyGen sound library. The soundtrack is mastered to
-14 LUFS integrated with a -1 dBTP true-peak ceiling.

The end card names macOS, Windows and Linux and states the hardware
requirements: Apple Silicon with macOS 14 or later, or a Vulkan GPU on Windows
and Linux. The animation demonstrates the macOS workflow only; on Linux,
Textify uses Copy and manual paste.

The editable HyperFrames project is not included in this repository.

## Earlier dictation promotion

The README now shows the promotion above; these files remain for reference.

`textify-promo.mp4` is a 42-second motion graphic promotion in 1080p at 30 fps,
with synthetic voiceover, two spoken dictation examples and original instrumental
music. `textify-promo.gif` is its silent README preview; `textify-promo-poster.png`
is a still from the email example.

The animation focuses on writing in other applications: an email draft and a
document. The sample applications are generic illustrations, not footage of
Apple Mail, Word, Gmail or another named product. Both writing scenes are labeled
**Animated macOS workflow · sample apps · illustrative timing**. Their final
sentences appear once after release and processing, matching the current
macOS shortcut workflow. These scenes are not evidence of physical microphone
capture, actual cross-app insertion or measured recognition speed.

The Textify logo is the existing app asset. The recording bar was reconstructed
from current isolated app screenshots. The screenshots used the signed
Whisper small.en model and real Metal inference; they were visual references,
not automatic-insertion footage. No personal documents, real microphone audio,
messages, permission changes or installed-app data were used.

Narration and dictated examples use the configured TTS service's clear male and
female Kenney voice presets (`announcer_kenney_male` and
`announcer_kenney_female`). The service identifies their reference material as
the CC0 Kenney Voiceover Pack. Speech is synthetic and fits the original edit
without acceleration. The instrumental bed is composed and synthesized locally
without stock music. The two voices do not overlap, and the music ducks beneath
speech.

The end card links to the desktop preview and states that a hardware GPU is
required and Linux uses Copy + paste. The animation demonstrates the macOS
workflow only; it does not establish Windows or Linux physical-device testing.

[Editable motion and audio source](promo-source/README.md).

## Actual app recording

The demo shows Textify desktop `0.2.0-preview.23`, recorded from an unpackaged
development build. It uses the verified Whisper small.en GGML Q5_1 model and
real Metal inference on an Apple M4 Max.

The prerecorded sample was generated locally with macOS `say`, using Samantha
at 170 words per minute:

> Hello, this is a short voice note. I can speak naturally, choose a local model,
> and copy the result. The audio is processed on this computer.

The footage shows the actual app window. Recording, recognition, and Copy run
at their original speed. The MP4 includes the same sample audio, synchronized
with recording. The caption below the app frame, labeled **Text copied by
Textify**, contains the exact recognition result captured from Copy; it is an
editorial caption, not an additional app screen.

The session used isolated app data and intercepted Copy in memory. It did not
use the physical microphone, change permissions, or touch the system clipboard.
This demonstrates local recognition and the Copy workflow, not automatic
insertion into another app.

- `textify-demo.mp4`: 24-second video with audio.
- `textify-demo.gif`: silent, looping preview.
- `textify-demo-poster.png`: still showing the copied result.
