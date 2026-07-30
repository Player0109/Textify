# Textify Privacy

This statement applies to Textify 1.1.x. Textify is a local dictation utility
with no accounts, analytics service, crash reporter, transcript history, or
automatic upload path for dictated content.

## Audio and dictated text

- Audio is captured only while you actively dictate.
- Audio and optional voice cleaning are processed locally through the installed
  on-device runtime.
- Raw audio is processed in memory and is not saved by default. It is released
  after the active dictation finishes.
- Dictated text is inserted locally. Textify does not keep transcript history.
- Textify does not send audio, transcripts, vocabulary, custom words, or
  replacement pairs to a Textify server or cloud speech service.

## Clipboard use

Textify uses the system clipboard only as an insertion transport. Before paste,
it snapshots the current clipboard, writes the dictated text, marks that item
transient and concealed on a best-effort basis, posts paste, and restores the
snapshot only while Textify's expected clipboard marker remains.

If another app or the user changes the clipboard during insertion, Textify does
not overwrite that newer content. Transient and concealed pasteboard markers
are conventions, not guarantees; third-party clipboard managers may still
observe or retain the temporary dictated text.

## Local settings and diagnostics

Settings, model receipts, vocabulary, custom words, replacement pairs, and
excluded-app records remain local.

Diagnostics export is explicit. Exported diagnostics are redacted and must not
contain transcripts, clipboard contents, vocabulary, custom words, replacement
text, or raw audio. They are limited to technical state such as permissions,
model status, timings, and error categories.

## Network access

The signed model catalog and its signature are bundled with Textify. The app
does not fetch catalog or revocation metadata when it launches, when onboarding
opens, or when Settings opens.

Textify itself makes network requests only for a model download that you
explicitly start, from an immutable Textify GitHub Release asset or an exact
commit-pinned public Hugging Face file.

GitHub or Hugging Face receives the requested immutable URL, including its
repository path and model filename, and ordinary request metadata such as IP
address, user agent, and request time. The provider can therefore infer which
model file was requested. Textify does not send a separate installed-model
inventory, local storage paths, analytics, system profiles, or dictated content
with that request.

Actions you explicitly initiate outside Textify can create separate browser
requests. These include downloading the app manually from GitHub Releases and
opening model, source, or license links from Settings. Those links may visit
GitHub, Hugging Face, ModelScope, or a license publisher. Your default browser
then sends the requested URL and ordinary request metadata to that provider
under the browser's and provider's privacy practices.

Automatic updates are deferred in Textify 1.1, so the app does not make update
checks or send Sparkle system-profile data.
