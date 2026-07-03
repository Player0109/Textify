# Acknowledgments

Textify uses whisper.cpp for local speech transcription. whisper.cpp is
developed by the ggml-org community and is licensed under the MIT License.

Whisper was developed and released by OpenAI. Textify V1.1 does not bundle model
binaries; published V1.1 releases must host the single curated
`ggml-small.en-q5_1` ggml model as a Textify GitHub Release asset and expose it
through the signed model manifest. Model source, checksum, and provenance are
tracked in the model manifest docs and published manifest.

Third-party notices are in `THIRD_PARTY_NOTICES.md`. The copied whisper.cpp
license text is in `THIRD_PARTY_LICENSES/whisper.cpp.txt`.
