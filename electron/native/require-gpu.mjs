import { readFile, writeFile } from "node:fs/promises";

// Exact edits to the checksum-pinned whisper revision. Fail if upstream drifts.
// CPU still handles PCM preparation/token sampling and graph bookkeeping;
// it must never execute a model graph or replace an unavailable GPU. The one
// exception is the small Silero speech detector, which runs on the CPU by
// design: only its scheduler may compute there.
export async function requireGPU(root) {
  async function edit(path, before, after) {
    const file = `${root}/${path}`;
    const source = await readFile(file, "utf8");
    if (source.split(before).length !== 2)
      throw new Error(`GPU policy patch did not match pinned source: ${path}`);
    await writeFile(file, source.replace(before, after));
  }
  await edit(
    "src/whisper.cpp",
    "    if (backend_gpu) {\n        result.push_back(backend_gpu);\n    }",
    "    if (!backend_gpu) return result; // Textify: no CPU fallback.\n    result.push_back(backend_gpu);",
  );
  await edit(
    "src/whisper.cpp",
    "    // CPU Extra\n    auto * cpu_dev",
    "    return buft_list; // Textify: model weights must fit on the GPU.\n\n    // CPU Extra\n    auto * cpu_dev",
  );
  await edit(
    "ggml/src/ggml-backend.cpp",
    "        // copy the input tensors to the split backend",
    `        // Textify: reject CPU model computation, including per-op fallback.
        if (!sched->textify_cpu_allowed &&
            ggml_backend_dev_type(ggml_backend_get_device(split_backend)) != GGML_BACKEND_DEVICE_TYPE_GPU) {
            for (int n = 0; n < split->graph.n_nodes; ++n) {
                const auto op = split->graph.nodes[n]->op;
                if (op != GGML_OP_NONE && op != GGML_OP_RESHAPE && op != GGML_OP_VIEW &&
                    op != GGML_OP_PERMUTE && op != GGML_OP_TRANSPOSE) return GGML_STATUS_FAILED;
            }
        }

        // copy the input tensors to the split backend`,
  );
  await edit(
    "ggml/src/ggml-vulkan/ggml-vulkan.cpp",
    '    GGML_LOG_DEBUG("ggml_vulkan: Found %zu Vulkan devices:\\n", vk_instance.device_indices.size());',
    `    // Textify: reject software and virtual devices, even with a visibility override.
    const auto physical_devices = vk_instance.instance.enumeratePhysicalDevices();
    auto & indices = vk_instance.device_indices;
    indices.erase(std::remove_if(indices.begin(), indices.end(), [&](size_t index) {
        const auto type = physical_devices[index].getProperties().deviceType;
        return type != vk::PhysicalDeviceType::eDiscreteGpu && type != vk::PhysicalDeviceType::eIntegratedGpu;
    }), indices.end());
    GGML_LOG_DEBUG("ggml_vulkan: Found %zu Vulkan devices:\\n", vk_instance.device_indices.size());`,
  );
  // Speech detection: CPU weights, a CPU backend, and one scheduler that may
  // compute on the CPU. Every other scheduler still refuses. The detector takes
  // the CPU backend directly, so it never starts Metal or Vulkan.
  await edit(
    "src/whisper.cpp",
    '#include "ggml-backend.h"\n',
    '#include "ggml-backend.h"\n#include "ggml-cpu.h"\n',
  );
  await edit(
    "ggml/src/ggml-backend.cpp",
    "    int debug;\n};",
    "    int debug;\n\n    bool textify_cpu_allowed; // Textify: set only for speech detection.\n};",
  );
  await edit(
    "ggml/src/ggml-backend.cpp",
    "void ggml_backend_sched_reset(ggml_backend_sched_t sched) {",
    `void ggml_backend_sched_textify_allow_cpu(ggml_backend_sched_t sched) {
    sched->textify_cpu_allowed = true;
}

void ggml_backend_sched_reset(ggml_backend_sched_t sched) {`,
  );
  await edit(
    "ggml/include/ggml-backend.h",
    "    GGML_API void                 ggml_backend_sched_free(ggml_backend_sched_t sched);",
    `    GGML_API void                 ggml_backend_sched_free(ggml_backend_sched_t sched);
    // Textify: let this scheduler compute on the CPU (speech detection only).
    GGML_API void                 ggml_backend_sched_textify_allow_cpu(ggml_backend_sched_t sched);`,
  );
  await edit(
    "src/whisper.cpp",
    `    whisper_context_params wparams = whisper_context_default_params();
    wparams.use_gpu = params.use_gpu;
    wparams.gpu_device = params.gpu_device;
    buft_list_t buft_list = make_buft_list(wparams);`,
    `    // Textify: the speech detector keeps its weights on the CPU.
    auto * cpu_dev = ggml_backend_reg_dev_get(ggml_backend_cpu_reg(), 0);
    buft_list_t buft_list = { { cpu_dev, ggml_backend_dev_buffer_type(cpu_dev) } };`,
  );
  await edit(
    "src/whisper.cpp",
    `    auto whisper_context_params = whisper_context_default_params();
    // TODO: GPU VAD is forced disabled until the performance is improved
    //whisper_context_params.use_gpu    = vctx->params.use_gpu;
    whisper_context_params.use_gpu    = false;
    whisper_context_params.gpu_device = vctx->params.gpu_device;

    vctx->backends = whisper_backend_init(whisper_context_params);`,
    `    // Textify: the speech detector runs on the CPU backend only.
    ggml_backend_t backend_cpu = ggml_backend_cpu_init();
    if (backend_cpu) vctx->backends.push_back(backend_cpu);`,
  );
  await edit(
    "src/whisper.cpp",
    '        WHISPER_LOG_INFO("%s: compute buffer (VAD)   = %7.2f MB\\n", __func__, whisper_sched_size(vctx->sched) / 1e6);',
    `        ggml_backend_sched_textify_allow_cpu(vctx->sched.sched);
        WHISPER_LOG_INFO("%s: compute buffer (VAD)   = %7.2f MB\\n", __func__, whisper_sched_size(vctx->sched) / 1e6);`,
  );
  await edit(
    "src/whisper.cpp",
    '            WHISPER_LOG_ERROR("%s: failed to compute VAD graph\\n", __func__);\n            break;',
    `            WHISPER_LOG_ERROR("%s: failed to compute VAD graph\\n", __func__);
            ggml_backend_sched_reset(sched);
            return false; // Textify: a failed detection must not read as silence.`,
  );
}
