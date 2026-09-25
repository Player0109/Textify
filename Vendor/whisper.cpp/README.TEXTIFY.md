# whisper.cpp license and historical provenance

The retired standalone Swift app's vendored implementation has been removed.
`LICENSE` remains an input to Electron packaging. `UPSTREAM.md` records the
historical source snapshot and patches used by that app.

The current desktop builds its own checksum-pinned whisper.cpp archive through
`electron/scripts/prepare-native.mjs` and `electron/native/CMakeLists.txt`; it does
not compile sources from this directory.
