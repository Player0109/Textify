# Video provenance

## Dictation promotion

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

Narration uses the installed macOS Aman voice; dictated examples use Samantha.
The instrumental bed is composed and synthesized locally without stock music.
The two voices do not overlap, and the music ducks beneath speech.

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
