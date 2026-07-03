# Textify V1.1 Privacy

Textify is a local dictation utility. V1.1 has no accounts, analytics service,
crash reporter, transcript history, or automatic upload path for dictated
content.

## Audio And Transcription

- Audio is captured only while you actively dictate.
- Transcription runs locally on your Mac through whisper.cpp.
- Raw audio is processed for the active dictation and is not retained after that
  dictation finishes.
- Textify does not keep transcript history.

## Clipboard Use

Textify uses the system clipboard only as an insertion transport. Before paste,
it snapshots the current clipboard, writes the dictated text, posts paste, and
then restores the snapshot when the expected marker remains. If another app or
the user changes the clipboard during insertion, Textify does not overwrite that
new clipboard content.

## Diagnostics

Diagnostics export is explicit. Diagnostics are redacted and must not contain
transcripts, clipboard content, or raw audio. They are intended for technical
state such as permissions, model status, timing, and error categories.

## Network

Textify V1.1 does not automatically upload audio, transcripts, clipboard
content, diagnostics, or settings. Network access is used for the signed model
manifest and signature from GitHub Pages, the curated model download from
Textify GitHub Release assets, and manual app downloads from GitHub Releases.

GitHub Pages and GitHub Releases may receive ordinary request metadata for those
downloads, such as IP address, user agent, and request time. Textify does not add
analytics payloads or dictated content to those requests.

Sparkle is deferred in V1.1, so Textify does not send Sparkle update requests or
Sparkle system profile data.
