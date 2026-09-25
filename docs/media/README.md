# Demo provenance

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
