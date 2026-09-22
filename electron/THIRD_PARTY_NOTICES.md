# Third-party software

The application bundle includes license texts in `textify/licenses`, the
whisper.cpp license in `textify/WHISPER-LICENSE`, and Electron/Chromium notices
provided by Electron. Node packages retain their own notices in the archive.

- Electron and Chromium: https://github.com/electron/electron
- React and React DOM, MIT: https://github.com/facebook/react
- whisper.cpp, MIT, pinned to `a8d002cfd879315632a579e73f0148d06959de36`:
  https://github.com/ggml-org/whisper.cpp
- OpenAI Whisper and small.en, large-v2, large-v3, large-v3-turbo models, MIT:
  https://github.com/openai/whisper
- uiohook-napi, MIT: https://github.com/SnosMe/uiohook-napi
- libuiohook, LGPL-3.0-or-later, copyright Alexander Barker:
  https://github.com/kwhat/libuiohook
- dbus-next (Delta Chat fork), MIT:
  https://github.com/deltachat/node-dbus-next

The installed uiohook-napi source, its included libuiohook source, and build
description are provided in `textify/native-source/uiohook-napi`. Its native
module is external to the application archive under `app.asar.unpacked` and can
be replaced with a rebuilt module. Use its included `binding.gyp` with node-gyp
for the target platform. Changes to a macOS bundle require re-signing it.

Whisper weights are downloaded or imported separately, verified against
the signed catalog, and are not included in the application package.
