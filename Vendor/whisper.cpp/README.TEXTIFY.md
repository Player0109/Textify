# Textify Vendor Notes

This directory contains a pinned whisper.cpp source snapshot for Textify's native
macOS transcription runtime.

Textify vendors only the source subset needed for the Apple Silicon CPU and
Metal path. SwiftPM owns the native target membership, C/C++ standards, warning
suppressions, and Apple framework/library links in the root `Package.swift`.
The thin Xcode project must consume SwiftPM products only.

Do not add model binaries, sample audio, CLI tools, server examples, generated
build output, or alternate accelerator sources here. See `UPSTREAM.md` for the
exact upstream commit, included paths, excluded paths, and local patch record.
