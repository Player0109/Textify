import { readFile, writeFile } from "node:fs/promises";

// Exact edits to the checksum-pinned whisper revision. Fail if upstream drifts.
// CPU still handles PCM preparation/token sampling and graph bookkeeping;
// it must never execute a model graph or replace an unavailable GPU.
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
        if (ggml_backend_dev_type(ggml_backend_get_device(split_backend)) != GGML_BACKEND_DEVICE_TYPE_GPU) {
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
}
