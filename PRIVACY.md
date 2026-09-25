# Textify Privacy

This statement applies to the desktop app in `electron/`, distributed for
macOS, Windows, and Linux. Textify has no accounts, analytics service, crash
reporting service, transcript history, or speech upload.

## Audio and dictated text

- Audio is captured while you actively dictate and processed locally by the
  installed speech model.
- Audio, live previews, and pending dictated text stay in memory for the active
  session. Textify does not retain recordings or transcript history.
- Textify does not send audio, dictated text, custom vocabulary, or replacement
  pairs to a cloud speech service.

## Clipboard and text delivery

On macOS and Windows, global dictation can paste into the original app after
checking that it is still focused. Automatic paste restores the previous
clipboard only if the clipboard has not changed. Textify does not overwrite
newer clipboard content or retry an uncertain paste.

The in-app microphone button uses an explicit Copy workflow. Linux also uses
Copy followed by manual paste. Explicit Copy replaces the clipboard normally.
Third-party clipboard managers may observe or retain copied text.

## Local data

Preferences, custom vocabulary, replacement pairs, app exclusions, downloaded
models, verification records, and model download progress remain on the device.
The desktop app uses its existing Textify Electron data directory so updates
retain these settings.

Activity stores daily numeric totals for completed dictations. Day, week, and
month views are derived from those totals; dictated words, recordings, and
destination apps are not stored in Activity or sent to an analytics service.

The desktop preview does not provide a diagnostics export. Review screenshots
or error details before voluntarily attaching them to a support issue.

## Network access

Signed model catalogs and revocation metadata are bundled with the app. A model
download makes an explicit request to its listed host, such as GitHub or Hugging
Face, and verifies the received files before use. Dictation works offline once
a supported model is installed.

Download hosts receive the requested model URL and ordinary request metadata,
such as the IP address, user agent, and request time. This can reveal which
model file was requested. Textify does not add dictated content or an analytics
payload to those requests.

Opening model, source, or license links uses the default browser, whose privacy
practices apply. App updates are downloaded manually from GitHub Releases;
Textify does not run an automatic update check.
