# Third-party software

The application bundle includes license texts in `textify/licenses`, the
whisper.cpp license in `textify/WHISPER-LICENSE`, and Electron/Chromium notices
provided by Electron. Node packages retain their own notices in the archive.

The model browser includes publisher logos solely to identify the source of
each model. These logos and names belong to their respective owners; their
appearance does not imply endorsement of Textify. The bundled images came from
the publishers' public profiles or site:

- OpenAI: https://huggingface.co/openai
- NVIDIA: https://nvidianews.nvidia.com/multimedia/corporate/nvidia-logos
- Qwen: https://github.com/QwenLM
- NetEase Youdao: https://dict.youdao.com/home

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

Windows/Linux builds use Vulkan-Headers and Vulkan-Hpp (Khronos Group),
Apache-2.0; the license is included in `textify/licenses/Vulkan.txt`. Vulkan
drivers and the system Vulkan loader are external dependencies, not bundled.
The Vulkan SDK/glslc is used at build time; end users do not need the SDK.
The pinned whisper source is modified by `native/require-gpu.mjs` to refuse
CPU graph execution, require GPU weights/backends and reject software Vulkan
devices.

All builds also contain isolated, statically linked GPU workers, using Metal on
macOS and Vulkan on Windows and Linux:

- transcribe.cpp 0.1.3, MIT, commit `5a5a49664a8ea1f0e5b3be1dfc544730d1b62561`:
  https://github.com/handy-computer/transcribe.cpp
- audio.cpp, Apache-2.0, commit `9ba884179826c3b33dd305185b5f94c79175a03d`:
  https://github.com/0xShug0/audio.cpp

The checksum-pinned source archives include their exact ggml and tokenizer
sources. `native/prepare-extra.mjs` adds CPU graph refusal, rejects software
Vulkan devices and moves Parakeet TDT's predictor/joint graphs to the GPU. The
audio.cpp C ABI is linked statically into its worker so its ggml symbols do not
collide with other runtimes.
Bundled `transcribe.cpp.txt` and `audio.cpp.txt` include dependency notices.
Qwen3-ASR, Parakeet TDT and Confucius4-R2T2 weights are downloaded or imported
separately and remain subject to the licenses shown in the signed catalog.
Confucius uses the NetEase Youdao Model Use License Agreement; it is not MIT.
The original BF16 checkpoint is pinned to NetEase Youdao's Hugging Face revision
`185ce639118ad1362d049ca0d8ed04b6ec5cd6c9`. Its original weights are not converted
or quantized by Textify. The existing bundled `Confucius4-R2T2.txt` contains the
publisher's model terms. audio.cpp is built with its model specifications embedded
for offline safetensors-directory loading.
