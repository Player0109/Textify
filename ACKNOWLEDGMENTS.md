# Acknowledgments

Textify's desktop app uses Electron and Chromium, React, uiohook-napi and
libuiohook, and the Delta Chat fork of dbus-next for its interface and desktop
integration.

Local speech recognition uses ggml-org's whisper.cpp, handy-computer's
transcribe.cpp, and ShugoAI's audio.cpp. Whisper was developed by OpenAI,
Parakeet by NVIDIA, Qwen3-ASR by the Qwen team, and Confucius4-R2T2 by NetEase
Youdao. Textify also credits the publishers of the model conversions identified
in its signed catalogs.

Model binaries are downloaded separately. Exact revisions, checksums, licenses,
and provenance are recorded in the signed model catalogs. Availability varies
by platform; see the [desktop guide](electron/README.md).

The [desktop notices](electron/THIRD_PARTY_NOTICES.md) describe the software and
license texts included in the current app. [Root third-party notices](THIRD_PARTY_NOTICES.md)
and [copied license texts](THIRD_PARTY_LICENSES/) retain attribution for the
shared catalogs and historical model evaluation, including models and runtimes
that are not exposed by the current desktop app.
